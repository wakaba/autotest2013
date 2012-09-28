package AutoTest::Runner;
use strict;
use warnings;
use Path::Class;
use Dongry::Database;
use AnyEvent;
use AnyEvent::Git::Repository;
use AutoTest::Action::RunTest;
use AutoTest::Action::ProcessJob;

sub new_from_config_and_dsns {
    return bless {config => $_[1], dsns => $_[2]}, $_[0];
}

sub new_from_env {
    my $class = shift;
    require Karasuma::Config::JSON;
    my $config = Karasuma::Config::JSON->new_from_env;
    require JSON::Functions::XS;
    my $json_f = file($ENV{MYSQL_DSNS_JSON});
    my $json = JSON::Functions::XS::file2perl($json_f);
    return $class->new_from_config_and_dsns($config, $json->{dsns});
}

sub config {
    return $_[0]->{config};
}

sub dsns {
    return $_[0]->{dsns};
}

sub dbreg {
    return $_[0]->{dbreg} if $_[0]->{dbreg};

    my $dbreg = Dongry::Database->create_registry;
    $dbreg->{Registry}->{autotestjobs} = {
        sources => {
            master => {
                dsn => $_[0]->dsns->{autotestjobs},
                writable => 1,
            },
        },
    };

    return $_[0]->{dbreg} = $dbreg;
}

sub log_post_url {
    return $_[0]->{log_post_url} ||= $_[0]->{config}->get_text('autotest.repos.log_post_url');
}

sub commit_status_post_url {
    return $_[0]->{commit_status_post_url} ||= $_[0]->{config}->get_text('autotest.repos.commit_status_post_url');
}

sub cached_repo_set_d {
    return $_[0]->{cached_repo_set_d} ||= do {
        my $d = dir($_[0]->{config}->get_text('autotest.cached_repo_set_dir_name'));
        $d->mkpath;
        $d;
    };
}

sub job_action {
    my $self = shift;
    return $self->{job_action} ||= AutoTest::Action::ProcessJob->new_from_dbreg($self->dbreg);
}

sub process_next_as_cv {
    my $self = shift;
    
    my $job = $self->job_action->get_job or return do {
        my $cv = AE::cv;
        $cv->send;
        $cv;
    };

    my $repo = AnyEvent::Git::Repository->new_from_url_and_cached_repo_set_d(
        $job->{url},
        $self->cached_repo_set_d,
    );
    $repo->branch($job->{branch});
    $repo->revision($job->{sha});
    
    my $action = AutoTest::Action::RunTest->new_from_repository($repo);
    $action->log_post_url($self->log_post_url);
    $action->commit_status_post_url($self->commit_status_post_url);
    my $cv = AE::cv;
    $action->run_test_as_cv->cb(sub {
        $self->job_action->complete_job($job);
        $cv->send;
    });
    return $cv;
}

sub interval {
    return 10;
}

sub process_as_cv {
    my $self = shift;
    
    my $cv = AE::cv;

    my $schedule_test;
    my $schedule_sleep;
    my $sleeping = 1;

    $schedule_test = sub {
        $sleeping = 0;
        #warn "test...\n";
        $self->process_next_as_cv->cb($schedule_sleep);
    };
    $schedule_sleep = sub {
        $sleeping = 1;
        #warn "sleep...\n";
        my $watcher; $watcher = AE::timer $self->interval, 0, sub {
            undef $watcher;
            $schedule_test->();
        };
    };
    
    my $schedule_end = sub {
        my $timer; $timer = AE::timer 0, 0, sub {
            #warn "end...\n";
            $cv->send;
            undef $timer;
        };
        $schedule_test = $schedule_sleep = sub { };
    };
    my $signal; $signal = AE::signal 'TERM' => sub {
        if ($sleeping) {
            $schedule_end->();
            undef $signal;
        } else {
            $schedule_test = $schedule_sleep = $schedule_end;
            $sleeping = 1; # for second kill
        }
    };

    $schedule_test->();

    return $cv;
}

1;
