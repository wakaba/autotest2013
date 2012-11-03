package AutoTest::Loader::PendingJobs;
use strict;
use warnings;
use List::Ish;

sub new_from_dbreg {
    return bless {dbreg => $_[1]}, $_[0];
}

sub dbreg {
    return $_[0]->{dbreg};
}

sub per_page {
    return 100;
}

sub get_items {
    my $self = shift;
    my $db = $self->dbreg->load('autotestjobs');
    return List::Ish->new unless $db->has_table('job', source_name => 'master');

    return $db->execute(
        'SELECT * FROM `job` ORDER BY `timestamp` DESC LIMIT :limit',
        {limit => $self->per_page},
        source_name => 'master',
    )->all;
}

1;
