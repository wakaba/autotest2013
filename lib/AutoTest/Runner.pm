package AutoTest::Runner;
use strict;
use warnings;
use Path::Class;
use Dongry::Database;
use AnyEvent;
use AnyEvent::HTTPD;
use AnyEvent::Git::Repository;
use AutoTest::Action::RunTest;
use AutoTest::Action::ProcessJob;
use Wanage::HTTP;
use AutoTest::Warabe::App;

sub new_from_config_and_dsns {
    return bless {config => $_[1], dsns => $_[2]}, $_[0];
}

sub new_from_env {
    my $class = shift;
    require Karasuma::Config::JSON;
    my $config = Karasuma::Config::JSON->new_from_env;
    require JSON::Functions::XS;
    my $json_f = file($ENV{MYSQL_DSNS_JSON} || die "|MYSQL_DSNS_JSON| is not set");
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

sub log_basic_auth {
    return $_[0]->{log_basic_auth} ||= [
        $_[0]->{config}->get_file_base64_text('autotest.repos.log_basic_auth.user'),
        $_[0]->{config}->get_file_base64_text('autotest.repos.log_basic_auth.password'),
    ];
}

sub commit_status_basic_auth {
    return $_[0]->{commit_status_basic_auth} ||= [
        $_[0]->{config}->get_file_base64_text('autotest.repos.commit_status_basic_auth.user'),
        $_[0]->{config}->get_file_base64_text('autotest.repos.commit_status_basic_auth.password'),
    ];
}

sub cached_repo_set_d {
    return $_[0]->{cached_repo_set_d} ||= do {
        my $d = dir($_[0]->{config}->get_text('autotest.cached_repo_set_dir_name'));
        $d->mkpath;
        $d->resolve;
    };
}

sub job_action {
    my $self = shift;
    return $self->{job_action} ||= AutoTest::Action::ProcessJob->new_from_dbreg_and_config($self->dbreg, $self->{config});
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
    $repo->onmessage(sub { $self->log($_[0]) });
    
    my $action = AutoTest::Action::RunTest->new_from_repository($repo);
    $action->log_post_url($self->log_post_url);
    $action->commit_status_post_url($self->commit_status_post_url);
    $action->log_basic_auth($self->log_basic_auth);
    $action->commit_status_basic_auth($self->commit_status_basic_auth);
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

sub web_port {
    return $_[0]->{web_port} ||= $_[0]->{config}->get_text('autotest.web.port');
}

sub web_api_key {
    return $_[0]->{web_api_key} ||= $_[0]->{config}->get_file_base64_text('autotest.web.api_key');
}

sub log {
    my $self = shift;
    warn sprintf "[%s] %d: %s\n", scalar gmtime, $$, $_[0];
}

sub process_as_cv {
    my $self = shift;
    
    my $cv = AE::cv;

    my $schedule_test;
    my $schedule_sleep;
    my $sleeping = 1;

    my $httpd = AnyEvent::HTTPD->new(port => $self->web_port);
    $httpd->reg_cb(request => sub {
        my ($httpd, $req) = @_;
        my $http = Wanage::HTTP->new_from_anyeventhttpd_httpd_and_req($httpd, $req);
        $self->log($http->client_ip_addr->as_text . ': ' . $http->request_method . ' ' . $http->url->stringify);
        my $app = AutoTest::Warabe::App->new_from_http($http);
        $http->send_response(onready => sub {
            $app->execute (sub {
                $self->process_http($app);
            });
        });
        $httpd->stop_request;
    });

    $schedule_test = sub {
        $sleeping = 0;
        $self->log("Finding a test job...");
        $self->process_next_as_cv->cb($schedule_sleep);
    };
    $schedule_sleep = sub {
        $sleeping = 1;
        $self->log("Sleep @{[$self->interval]}s");
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
    for my $sig (qw(TERM INT)) {
        my $signal; $signal = AE::signal $sig => sub {
            $self->log("Signal: SIG$sig");
            if ($sleeping) {
                $schedule_end->();
                undef $signal;
                undef $httpd;
            } else {
                $schedule_test = $schedule_sleep = $schedule_end;
                $sleeping = 1; # for second kill
            }
        };
    }

    $schedule_test->();

    return $cv;
}

sub process_http {
    my ($self, $app) = @_;
    my $path = $app->path_segments;

    if ($path->[0] eq 'jobs' and not defined $path->[1]) {
        # /jobs
        $app->requires_request_method({POST => 1});
        $app->requires_basic_auth({api_key => $self->web_api_key});

        my $json = $app->request_json;

        my $branch = ref $json eq 'HASH' ? $json->{ref} || '' : '';
        $branch =~ s{^refs/heads/}{};
        $app->throw_error(400, reason_phrase => 'bad ref') unless $branch;

        my $url = ref $json->{repository} eq 'HASH' ? $json->{repository}->{url} : undef
            or $app->throw_error(400, reason_phrase => 'bad repository.url');
        my $rev = $json->{after}
            or $app->throw_error(400, reason_phrase => 'bad after');

        $app->http->set_response_header('Content-Type' => 'text/plain; charset=utf-8');
        $app->http->send_response_body_as_text("Inserting a job... ");

        require AutoTest::Action::InsertJob;
        my $action = AutoTest::Action::InsertJob->new_from_dbreg($self->dbreg);
        $action->create_table;
        my $count = $action->insert(
            url => $url,
            branch => $branch,
            sha => $rev,
        );

        $self->log("A job inserted") if $count;
        $app->http->send_response_body_as_text("done ($count)");
        $app->http->close_response_body;
        return $app->throw;
    } elsif ($path->[0] eq 'jobs.json' and not defined $path->[1]) {
        $app->requires_basic_auth({api_key => $self->web_api_key});
        require AutoTest::Loader::PendingJobs;
        my $loader = AutoTest::Loader::PendingJobs->new_from_dbreg($self->dbreg);
        $app->send_json($loader->get_items);
        return $app->throw;
    }
    
    return $app->throw_error(404);
}

1;
