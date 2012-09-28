use strict;
BEGIN {
    my $dir_name = __FILE__; $dir_name =~ s{[^/]+$}{}; $dir_name ||= '.';
    $dir_name .= '/../../t_deps/lib'; unshift @INC, $dir_name;
}
use warnings;
use Test::AutoTest;
use Test::AutoTest::GWServer;
use AnyEvent::Git::Repository;
use AutoTest::Action::RunTest;
use Test::AnyEvent::plackup;

Test::AutoTest::GWServer->start_server_as_cv->recv;
my $server_host = Test::AutoTest::GWServer->server_host;

test {
    my $c = shift;

    my $temp_d = dir(tempdir(CLEANUP => 1));
    system "cd $temp_d && git init && echo 'hoge:\n\techo 1234 > foo.txt' > Makefile && git add Makefile && git commit -m New";
    my $rev = `cd $temp_d && git rev-parse HEAD`;
    chomp $rev;

    my $cached_d = dir(tempdir(CLEANUP => 1));
    my $repo = AnyEvent::Git::Repository->new_from_url_and_cached_repo_set_d($temp_d, $cached_d);
    $repo->branch('master');
    $repo->revision($rev);
    
    my $action = AutoTest::Action::RunTest->new_from_repository($repo);
    $action->log_post_url("http://$server_host/repos/logs");
    $action->commit_status_post_url("http://$server_host/repos/statuses/%s.json");
    $action->run_test_as_cv->cb(sub {
        test {
            my $cv = AE::cv;
            $cv->begin;

            $cv->begin;
            http_get
                url => qq<http://$server_host/repos/logs>,
                params => {
                    repository_url => $temp_d,
                },
                anyevent => 1,
                cb => sub {
                    my (undef, $res) = @_;
                    test {
                        my $json = json_bytes2perl $res->content;
                        is scalar @$json, 1;
                        is $json->[0]->{sha}, $rev;
                        is $json->[0]->{title}, 'AutoTest2013 result - failed';
                        like $json->[0]->{data}, qr{^cd \\/tmp\\/\S+ && make test 2>&1}m;
                        like $json->[0]->{data}, qr{^Exited with status 2}m;
                        $cv->end;
                    } $c;
                };

            $cv->begin;
            http_get
                url => qq<http://$server_host/repos/statuses/> . $rev . q<.json>,
                params => {
                    repository_url => $temp_d,
                },
                anyevent => 1,
                cb => sub {
                    my (undef, $res) = @_;
                    test {
                        my $json = json_bytes2perl $res->content;
                        is scalar @$json, 1;
                        is $json->[0]->{sha}, $rev;
                        like $json->[0]->{target_url}, qr{/repos/logs/\d+$};
                        is $json->[0]->{description}, 'AutoTest2013 result - failed';
                        is $json->[0]->{state}, 'failure';
                        $cv->end;
                    } $c;
                };
            $cv->end;
            
            $cv->cb(sub {
                test {
                    done $c;
                    undef $c;
                } $c;
            });
        } $c;
    });
} n => 10, name => 'failed (no rule)';

test {
    my $c = shift;

    my $temp_d = dir(tempdir(CLEANUP => 1));
    system "cd $temp_d && git init && echo 'test:\n\techo 1234 > foo.txt\n\techo PATH=\$\$PATH' > Makefile && git add Makefile && git commit -m New";
    my $rev = `cd $temp_d && git rev-parse HEAD`;
    chomp $rev;

    my $cached_d = dir(tempdir(CLEANUP => 1));
    my $repo = AnyEvent::Git::Repository->new_from_url_and_cached_repo_set_d($temp_d, $cached_d);
    $repo->branch('master');
    $repo->revision($rev);
    
    my $action = AutoTest::Action::RunTest->new_from_repository($repo);
    $action->log_post_url("http://$server_host/repos/logs");
    $action->commit_status_post_url("http://$server_host/repos/statuses/%s.json");
    $action->run_test_as_cv->cb(sub {
        test {
            my $cv = AE::cv;
            $cv->begin;

            $cv->begin;
            http_get
                url => qq<http://$server_host/repos/logs>,
                params => {
                    repository_url => $temp_d,
                },
                anyevent => 1,
                cb => sub {
                    my (undef, $res) = @_;
                    test {
                        my $json = json_bytes2perl $res->content;
                        is scalar @$json, 1;
                        is $json->[0]->{sha}, $rev;
                        is $json->[0]->{title}, 'AutoTest2013 result - success';
                        like $json->[0]->{data}, qr{^cd \\/tmp\\/\S+ && make test 2>&1}m;
                        like $json->[0]->{data}, qr{^Exited with status 0}m;
                        $cv->end;
                    } $c;
                };

            $cv->begin;
            http_get
                url => qq<http://$server_host/repos/statuses/> . $rev . q<.json>,
                params => {
                    repository_url => $temp_d,
                },
                anyevent => 1,
                cb => sub {
                    my (undef, $res) = @_;
                    test {
                        my $json = json_bytes2perl $res->content;
                        is scalar @$json, 1;
                        is $json->[0]->{sha}, $rev;
                        like $json->[0]->{target_url}, qr{/repos/logs/\d+$};
                        is $json->[0]->{description}, 'AutoTest2013 result - success';
                        is $json->[0]->{state}, 'success';
                        $cv->end;
                    } $c;
                };
            $cv->end;
            
            $cv->cb(sub {
                test {
                    done $c;
                    undef $c;
                } $c;
            });
        } $c;
    });
} n => 10, name => 'success';

test {
    my $c = shift;

    my $temp_d = dir(tempdir(CLEANUP => 1));
    system "cd $temp_d && git init && echo 'test:\n\tfalse > foo.txt' > Makefile && git add Makefile && git commit -m New";
    my $rev = `cd $temp_d && git rev-parse HEAD`;
    chomp $rev;

    my $cached_d = dir(tempdir(CLEANUP => 1));
    my $repo = AnyEvent::Git::Repository->new_from_url_and_cached_repo_set_d($temp_d, $cached_d);
    $repo->branch('master');
    $repo->revision($rev);
    
    my $action = AutoTest::Action::RunTest->new_from_repository($repo);
    $action->log_post_url("http://$server_host/repos/logs");
    $action->commit_status_post_url("http://$server_host/repos/statuses/%s.json");
    $action->run_test_as_cv->cb(sub {
        test {
            my $cv = AE::cv;
            $cv->begin;

            $cv->begin;
            http_get
                url => qq<http://$server_host/repos/logs>,
                params => {
                    repository_url => $temp_d,
                },
                anyevent => 1,
                cb => sub {
                    my (undef, $res) = @_;
                    test {
                        my $json = json_bytes2perl $res->content;
                        is scalar @$json, 1;
                        is $json->[0]->{sha}, $rev;
                        is $json->[0]->{title}, 'AutoTest2013 result - failed';
                        like $json->[0]->{data}, qr{^cd \\/tmp\\/\S+ && make test 2>&1}m;
                        like $json->[0]->{data}, qr{^Exited with status 2}m;
                        $cv->end;
                    } $c;
                };

            $cv->begin;
            http_get
                url => qq<http://$server_host/repos/statuses/> . $rev . q<.json>,
                params => {
                    repository_url => $temp_d,
                },
                anyevent => 1,
                cb => sub {
                    my (undef, $res) = @_;
                    test {
                        my $json = json_bytes2perl $res->content;
                        is scalar @$json, 1;
                        is $json->[0]->{sha}, $rev;
                        like $json->[0]->{target_url}, qr{/repos/logs/\d+$};
                        is $json->[0]->{description}, 'AutoTest2013 result - failed';
                        is $json->[0]->{state}, 'failure';
                        $cv->end;
                    } $c;
                };
            $cv->end;
            
            $cv->cb(sub {
                test {
                    done $c;
                    undef $c;
                } $c;
            });
        } $c;
    });
} n => 10, name => 'failed (make failed)';

run_tests;
Test::AutoTest::GWServer->stop_server_as_cv->recv;
