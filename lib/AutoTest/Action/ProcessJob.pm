package AutoTest::Action::ProcessJob;
use strict;
use warnings;

sub new_from_dbreg {
    return bless {dbreg => $_[1]}, $_[0];
}

sub dbreg {
    return $_[0]->{dbreg};
}

sub timeout {
    return 60*60;
}

sub db {
    my $self = shift;
    return $self->{db} ||= $self->dbreg->load('autotestjobs');
}

sub get_job {
    my $self = shift;
    my $db = $self->dbreg->load('autotestjobs');
    return undef unless $db->has_table('job', source_name => 'master');
    my $pid = $db->execute(
        'select uuid_short() as uuid', {},
        source_name => 'master',
    )->first->{uuid};
    $db->update(
        'job',
        {
            process_id => $pid,
            process_started => time,
        },
        where => {
            process_started => {'<=', time - $self->timeout},
        },
        order => [process_started => 'ASC'],
        limit => 1,
    );
    return $db->select(
        'job',
        {process_id => $pid},
        source_name => 'master',
    )->first; # or undef
}

sub complete_job {
    my ($self, $job) = @_;
    return unless $job;
    $self->db->delete(
        'job',
        {process_id => $job->{process_id}},
    );
}

1;
