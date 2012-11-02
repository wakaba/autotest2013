package AutoTest::Action::RunTest;
use strict;
use warnings;
use Path::Class;
use AnyEvent;
use AnyEvent::Util;
use Web::UserAgent::Functions qw(http_post);

sub new_from_repository {
    return bless {repository => $_[1]}, $_[0];
}

sub repository {
    return $_[0]->{repository};
}

sub log_basic_auth {
    if (@_ > 1) {
        $_[0]->{log_basic_auth} = $_[1];
    }
    return $_[0]->{log_basic_auth};
}

sub commit_status_basic_auth {
    if (@_ > 1) {
        $_[0]->{commit_status_basic_auth} = $_[1];
    }
    return $_[0]->{commit_status_basic_auth};
}

sub timeout {
    if (@_ > 1) {
        $_[0]->{timeout} = $_[1];
    }
    return $_[0]->{timeout} || 60*60;
}

sub run_test_as_cv {
    my $self = shift;
    my $cv = AE::cv;
    my $repo = $self->repository;
    $repo->clone_as_cv->cb(sub {
        my $d = $repo->temp_repo_d;
        my $onmessage = $repo->onmessage;
        my $command = "cd \Q$d\E && make test 2>&1";
        my $output =
            '$ hostname' . "\n" .
            `hostname` . "\n" .
            '$ ' . $command . "\n";
        my $start_time = time;
        my $prefix = file(__FILE__)->dir->parent->parent->parent->absolute;
        local $ENV{LANG} = 'C';
        local $ENV{PATH} = $ENV{PMBP_ORIG_PATH} || join ':', grep {not /^\Q$prefix\E\// } split /:/, $ENV{PATH};
        local $ENV{PERL5LIB} = '';
        local $ENV{PMBP_DUMP_BEFORE_DIE} = 1;
        local $ENV{PMBP_PARALLEL_COUNT} = 4;
        my $pid;
        run_cmd(
            $command,
            '>' => sub {
                if (defined $_[0]) {
                    $output .= $_[0];
                    $onmessage->($_[0]);
                }
            },
            '$$' => \$pid,
            on_prepare => sub { setpgrp 0, 0 },
        )->cb(sub {
            my $return = $_[0]->recv;
            my $failed = $return;
            my $end_time = time;
            if ($return & 127) {
                $output .= sprintf "Exited with signal %d (%.2fs)\n",
                    $return & 127, $end_time - $start_time;
            } else {
                $output .= sprintf "Exited with status %d (%.2fs)\n",
                    $return >> 8, $end_time - $start_time;
            }

            $self->add_log_as_cv(failed => $failed, data => $output)->cb(sub {
                my $log_info = $_[0]->recv;
                $self->add_commit_status_as_cv(failed => $failed, log_url => $log_info->{log_url})->cb(sub {
                    $cv->send;
                });
            });
        });
        my $timer; $timer = AE::timer $self->timeout, 0, sub {
            kill -9, getpgrp $pid;
            $output .= sprintf "\nTest killed by timeout (= %d s)!\n",
                $self->timeout;
            undef $timer;
        };
    });
    return $cv;
}

sub log_post_url {
    if (@_ > 1) {
        $_[0]->{log_post_url} = $_[1];
    }
    return $_[0]->{log_post_url};
}

sub commit_status_post_url {
    if (@_ > 1) {
        $_[0]->{commit_status_post_url} = $_[1];
    }
    return $_[0]->{commit_status_post_url};
}

sub add_log_as_cv {
    my ($self, %args) = @_;
    my $cv = AE::cv;
    my $url = $self->log_post_url;
    my $repo = $self->repository;
    my $title = $args{failed} ? 'AutoTest2013 result - failed' : 'AutoTest2013 result - success';
    http_post
        url => $url,
        basic_auth => $self->log_basic_auth,
        params => {
            repository_url => $repo->url,
            branch => $repo->branch,
            sha => $repo->revision,
            title => $title,
            data => $args{data},
        },
        anyevent => 1,
        cb => sub {
            my (undef, $res) = @_;
            if ($res->code == 201) {
                my $url = $res->header('Location');
                $cv->send({log_url => $url});
            } else {
                $cv->send({});
            }
        };
    return $cv;
}

sub add_commit_status_as_cv {
    my ($self, %args) = @_;
    my $cv = AE::cv;
    my $url = $self->commit_status_post_url;
    my $repo = $self->repository;
    my $state = $args{failed} ? 'failure' : 'success';
    my $title = $args{failed} ? 'AutoTest2013 result - failed' : 'AutoTest2013 result - success';
    $url =~ s/%s/$repo->revision/e;
    http_post
        url => $url,
        basic_auth => $self->commit_status_basic_auth,
        params => {
            repository_url => $repo->url,
            branch => $repo->branch,
            state => $state,
            target_url => $args{log_url},
            description => $title,
        },
        anyevent => 1,
        cb => sub {
            my (undef, $res) = @_;
            $cv->send({});
        };
    return $cv;
}

1;
