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
    my $config = Karasuma::Config::JSON->new_from_config_data({
        'autotest.repos.log_post_url' => '',
        'autotest.repos.commit_status_post_url' => '',
        'autotest.cached_repo_set_dir_name' => $cached_d->absolute->stringify,
    });
    my $runner = AutoTest::Runner->new_from_config_and_dsns($config, get_dsns $c);
    my $timer; $timer = AE::timer 12, 0, sub {
        kill 'TERM', $$;
        undef $timer;
    };
    $runner->process_as_cv->cb(sub {
        test {
            ok 1;
            done $c;
            undef $c;
        } $c;
    });
} name => 'empty', n => 1, wait => $mysqld_cv;

test {
    my $c = shift;
    my $cached_d = dir(tempdir(CLEANUP => 1));
    print { $cached_d->file('config.json')->openw } JSON::Functions::XS::perl2json_bytes {
        'autotest.repos.log_post_url' => 'hoge',
        'autotest.repos.commit_status_post_url' => 'fuga',
        'autotest.cached_repo_set_dir_name' => $cached_d->absolute->stringify,
    };
    local $ENV{KARASUMA_CONFIG_JSON} = $cached_d->file('config.json');
    local $ENV{KARASUMA_CONFIG_FILE_DIR_NAME} = $cached_d->subdir('keys');
    local $ENV{MYSQL_DSNS_JSON} = $c->received_data->json_f;
    my $runner = AutoTest::Runner->new_from_env;
    my $timer; $timer = AE::timer 1, 0, sub {
        kill 'TERM', $$;
        undef $timer;
    };
    $runner->process_as_cv->cb(sub {
        test {
            is $runner->log_post_url, 'hoge';
            is $runner->commit_status_post_url, 'fuga';
            done $c;
            undef $c;
        } $c;
    });
} name => 'env', n => 2, wait => $mysqld_cv;

test {
    my $c = shift;
    my $cached_d = dir(tempdir(CLEANUP => 1));
    my $config = Karasuma::Config::JSON->new_from_config_data({
        'autotest.repos.log_post_url' => "http://$server_host/repos/logs",
        'autotest.repos.commit_status_post_url' => "http://$server_host/repos/statuses/%s.json",
        'autotest.cached_repo_set_dir_name' => $cached_d->absolute->stringify,
    });
    my $runner = AutoTest::Runner->new_from_config_and_dsns($config, get_dsns $c);
    my $timer; $timer = AE::timer 12, 0, sub {
        kill 'TERM', $$;
        undef $timer;
    };

    my $temp_d = dir(tempdir(CLEANUP => 1));
    my $temp2_d = dir(tempdir(CLEANUP => 1));
    system "cd $temp_d && git init && echo 'test:\n\techo 1234 > $temp2_d/foo.txt' > Makefile && git add Makefile && git commit -m New";
    my $rev = `cd $temp_d && git rev-parse HEAD`;
    chomp $rev;

    my $action = AutoTest::Action::InsertJob->new_from_dbreg(get_dbreg $c);
    $action->create_table;
    $action->insert(
        url => $temp_d,
        branch => q<master>,
        sha => $rev,
    );

    my $cv = AE::cv;
    $cv->begin;

    $cv->begin;
    $runner->process_as_cv->cb(sub {
        test {
            ok -f $temp2_d->file('foo.txt');
            $cv->end;
        } $c;
    });

    $cv->begin;
    $cv->begin;
    my $timer2; $timer2 = AE::timer 4, 0, sub {
        test {
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
                        undef $timer2;
                        $cv->end;
                    } $c;
                };
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
                        undef $timer2;
                        $cv->end;
                    } $c;
                };
        } $c;
    };

    $cv->end;
    $cv->cb(sub {
        test {
            done $c;
            undef $c;
        } $c;
    });
} name => 'non empty', n => 3, wait => $mysqld_cv;

run_tests;
Test::AutoTest::GWServer->stop_server_as_cv->recv;
