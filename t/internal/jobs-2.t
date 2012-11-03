use strict;
BEGIN {
    my $dir_name = __FILE__; $dir_name =~ s{[^/]+$}{}; $dir_name ||= '.';
    $dir_name .= '/../../t_deps/lib'; unshift @INC, $dir_name;
}
use warnings;
use Test::AutoTest;
use Test::AutoTest::GWServer;
use Karasuma::Config::JSON;
use AutoTest::Action::InsertJob;
use AutoTest::Runner;
use Dongry::Database;
use Test::AnyEvent::MySQL::CreateDatabase;
use Test::AnyEvent::plackup;
use MIME::Base64;

Test::AutoTest::GWServer->start_server_as_cv->recv;
my $server_host = Test::AutoTest::GWServer->server_host;

my $mysqld_cv = sub {
    my $mysqld = Test::AnyEvent::MySQL::CreateDatabase->new;
    my $mysqld_cv = $mysqld->prep_text_to_cv(q{
        db autotestjobs
    });
    $mysqld_cv->{_server} = $mysqld;
    return $mysqld_cv;
};

sub get_dsns ($) {
    my $c = shift;
    return (file2perl $c->received_data->json_f)->{dsns};
}

sub get_dbreg ($) {
    my $c = shift;
    my $dbreg = Dongry::Database->create_registry;
    $dbreg->{Registry}->{autotestjobs} = {
        sources => {master => {dsn => (get_dsns $c)->{autotestjobs}, writable => 1}},
    };
    return $dbreg;
}

test {
    my $c = shift;
    my $cached_d = dir(tempdir(CLEANUP => 1));
    my $base_d = dir(tempdir(CLEANUP => 1));
    my $config = Karasuma::Config::JSON->new_from_config_data({
        'autotest.repos.log_post_url' => "http://$server_host/repos/logs",
        'autotest.repos.commit_status_post_url' => "http://$server_host/repos/statuses/%s.json",
        'autotest.cached_repo_set_dir_name' => $cached_d->absolute->stringify,
        'autotest.web.port' => Test::AnyEvent::plackup::FindPort->find_listenable_port,
        'autotest.web.api_key' => 'api_key.txt',
    });
    $config->base_d($base_d);
    my $api_key = 'hoge' . rand;
    print { $base_d->file('api_key.txt')->openw } encode_base64 $api_key;

    my $temp_d = dir(tempdir(CLEANUP => 1));
    system "cd $temp_d && git init && echo 'test:\n\techo 1234 > $temp_d/foo.txt' > Makefile && git add Makefile && git commit -m New";
    my $rev = `cd $temp_d && git rev-parse HEAD`;
    chomp $rev;

    my $runner = AutoTest::Runner->new_from_config_and_dsns($config, get_dsns $c);
    $runner->process_as_cv->cb(sub {
        test {
            done $c;
            undef $c;
        } $c;
    });
    my $timer; $timer = AE::timer 1, 0, sub {
        test {
            my $port = $runner->web_port;
            http_post_data
                url => qq<http://localhost:$port/jobs>,
                #basic_auth => [api_key => $api_key],
                header_fields => {'Content-Type' => 'application/json'},
                content => perl2json_bytes +{
                    repository => {url => $temp_d->stringify},
                    ref => 'refs/heads/master',
                    after => $rev,
                },
                anyevent => 1,
                cb => sub {
                    my ($req, $res) = @_;
                    test {
                        is $res->code, 401;

                        my $timer2; $timer2 = AE::timer 15, 0, sub {
                            test {
                                ok !-f $temp_d->file('foo.txt');
                                undef $timer2;
                                kill 'TERM', $$;
                            } $c;
                        };
                    } $c;
                };
            undef $timer;
        } $c;
    };
} name => 'post no auth', n => 2, wait => $mysqld_cv;

run_tests;
Test::AutoTest::GWServer->stop_server_as_cv->recv;
