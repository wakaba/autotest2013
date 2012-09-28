use strict;
BEGIN {
    my $dir_name = __FILE__; $dir_name =~ s{[^/]+$}{}; $dir_name ||= '.';
    $dir_name .= '/../../t_deps/lib'; unshift @INC, $dir_name;
}
use warnings;
use Test::AutoTest;
use AutoTest::Action::InsertJob;
use Dongry::Database;
use Test::AnyEvent::MySQL::CreateDatabase;

my $mysqld = Test::AnyEvent::MySQL::CreateDatabase->new;
my $mysqld_cv = $mysqld->prep_text_to_cv(q{
    db autotestjobs
});

test {
    my $c = shift;

    my $dbreg = Dongry::Database->create_registry;
    $dbreg->{Registry}->{autotestjobs} = {
        sources => {master => {dsn => (file2perl $c->received_data->json_f)->{dsns}->{autotestjobs}, writable => 1}},
    };

    my $action = AutoTest::Action::InsertJob->new_from_dbreg($dbreg);
    $action->create_table;
    $action->insert(
        url => q<git://hogte/fuga>,
        branch => q<devel>,
        sha => q<7449a5bf4026e10c3b5b63d69079fbeb9b71685f>,
    );

    my $data = $dbreg->load('autotestjobs')->execute('select * from job', {}, source_name => 'master')->all;
    is scalar @$data, 1;
    is $data->[0]->{url}, q<git://hogte/fuga>;
    is $data->[0]->{branch}, q<devel>;
    is $data->[0]->{sha}, q<7449a5bf4026e10c3b5b63d69079fbeb9b71685f>;
    
    done $c;
} n => 4, wait => $mysqld_cv;

run_tests;
