use strict;
BEGIN {
    my $dir_name = __FILE__; $dir_name =~ s{[^/]+$}{}; $dir_name ||= '.';
    $dir_name .= '/../../t_deps/lib'; unshift @INC, $dir_name;
}
use warnings;
use Test::AutoTest;
use AutoTest::Action::InsertJob;
use AutoTest::Action::ProcessJob;
use Dongry::Database;
use Test::AnyEvent::MySQL::CreateDatabase;

my $mysqld_cv = sub {
    my $mysqld = Test::AnyEvent::MySQL::CreateDatabase->new;
    my $mysqld_cv = $mysqld->prep_text_to_cv(q{
        db autotestjobs
    });
    $mysqld_cv->{_server} = $mysqld;
    return $mysqld_cv;
};

sub get_dbreg ($) {
    my $c = shift;
    my $dbreg = Dongry::Database->create_registry;
    $dbreg->{Registry}->{autotestjobs} = {
        sources => {master => {dsn => (file2perl $c->received_data->json_f)->{dsns}->{autotestjobs}, writable => 1}},
    };
    return $dbreg;
}

test {
    my $c = shift;

    my $action = AutoTest::Action::ProcessJob->new_from_dbreg(get_dbreg $c);
    is $action->get_job, undef;
    is $action->get_job, undef;

    done $c;
} name => 'empty', n => 2, wait => $mysqld_cv;

test {
    my $c = shift;

    my $dbreg = get_dbreg $c;

    my $action = AutoTest::Action::InsertJob->new_from_dbreg($dbreg);
    $action->create_table;
    $action->insert(
        url => q<git://hogte/fuga>,
        branch => q<devel>,
        sha => q<7449a5bf4026e10c3b5b63d69079fbeb9b71685f>,
    );

    my $action2 = AutoTest::Action::ProcessJob->new_from_dbreg($dbreg);
    my $job = $action2->get_job;

    is $job->{url}, q<git://hogte/fuga>;
    is $job->{branch}, q<devel>;
    is $job->{sha}, q<7449a5bf4026e10c3b5b63d69079fbeb9b71685f>;

    my $job2 = $action2->get_job;
    is $job2, undef;

    $action2->complete_job($job);
    
    my $job3 = $action2->get_job;
    is $job3, undef;
    
    done $c;
} n => 5, wait => $mysqld_cv;

run_tests;
