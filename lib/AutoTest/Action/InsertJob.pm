package AutoTest::Action::InsertJob;
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

sub create_table {
    my $self = shift;
    $self->db->execute(q{
        CREATE TABLE IF NOT EXISTS job (
            url VARCHAR(511) NOT NULL,
            branch VARCHAR(511) NOT NULL,
            sha BINARY(40) NOT NULL,
            process_id BIGINT UNSIGNED NOT NULL,
            process_started BIGINT UNSIGNED NOT NULL,
            UNIQUE KEY (url, sha),
            KEY (process_id),
            KEY (process_started)
        ) DEFAULT CHARSET=BINARY;
    });
}

sub insert {
    my ($self, %args) = @_;

    my $db = $self->db;
    my $pid = $db->execute(
        'select uuid_short() as uuid', {},
        source_name => 'master',
    )->first->{uuid};
    $db->insert(
        'job',
        [{
            url => $args{url},
            branch => $args{branch},
            sha => $args{sha},
            process_id => 0,
            process_started => 0,
        }],
        duplicate => 'ignore',
    );
}

1;
