use strict;
BEGIN {
    my $dir_name = __FILE__; $dir_name =~ s{[^/]+$}{}; $dir_name ||= '.';
    $dir_name .= '/../../t_deps/lib'; unshift @INC, $dir_name;
}
use warnings;
use Test::AutoTest;
use AnyEvent::Git::Repository;
use AutoTest::Action::RunTest;
use Test::AnyEvent::plackup;

my $http_server = Test::AnyEvent::plackup->new;
$http_server->server('Twiggy');
$http_server->set_app_code(q{
    use strict;
    use warnings;
    use Wanage::HTTP;
    use JSON::Functions::XS qw(perl2json_bytes);
    my $repos = {};
    my $i = 0;
    return sub {
        my $http = Wanage::HTTP->new_from_psgi_env($_[0]);
        my $path = $http->url->{path};
        if ($path eq '/repos/logs') {
            if ($http->request_method eq 'POST') {
                my $params = $http->request_body_params;
                $i++;
                my $log = {
                    sha => $params->{sha}->[0],
                    title => $params->{title}->[0],
                    data => $params->{data}->[0],
                    id => $i,
                };
                push @{$repos->{$params->{repository_url}->[0]}->{logs} ||= []}, $log;
                $http->set_status(201);
                $http->set_response_header(Location => q</repos/logs/> . $i);
                $http->send_response_body_as_text(perl2json_bytes $log);
                $http->close_response_body;
                return $http->send_response;
            } else {
                my $params = $http->query_params;
                my $logs = $repos->{$params->{repository_url}->[0]}->{logs} ||= [];
                $http->send_response_body_as_text(perl2json_bytes $logs);
                $http->close_response_body;
                return $http->send_response;
            }
        } elsif ($path =~ m{^/repos/statuses/(\S+)\.json$}) {
            if ($http->request_method eq 'POST') {
                my $params = $http->request_body_params;
                my $status = {
                    sha => $1,
                    description => $params->{description}->[0],
                    state => $params->{state}->[0],
                    target_url => $params->{target_url}->[0],
                };
                push @{$repos->{$params->{repository_url}->[0]}->{commit_statuses} ||= []}, $status;
                $http->send_response_body_as_text(perl2json_bytes $status);
                $http->close_response_body;
                return $http->send_response;
            } else {
                my $params = $http->query_params;
                my $statuses = $repos->{$params->{repository_url}->[0]}->{commit_statuses} ||= [];
                $http->send_response_body_as_text(perl2json_bytes $statuses);
                $http->close_response_body;
                return $http->send_response;
            }
        }
        return [404, [], ['404']];
    };
});
my ($server_start_cv, $server_stop_cv) = $http_server->start_server;
my $server_host = 'localhost:' . $http_server->port;
$server_start_cv->recv;

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

$http_server->stop_server;
$server_stop_cv->recv;
