package Test::AutoTest;
use strict;
BEGIN {
    my $file_name = __FILE__; $file_name =~ s{[^/]+$}{}; $file_name ||= '.';
    $file_name .= '/../../../config/perl/libs.txt';
    if (-f $file_name) {
        open my $file, '<', $file_name or die "$0: $file_name: $!";
        unshift @INC, split /:/, <$file>;
    }
    $file_name =~ s{/config/perl/libs.txt$}{/t_deps/modules/*/lib};
    unshift @INC, glob $file_name;
}
use warnings;
use Exporter::Lite;
use Test::More;
use Test::Differences;
use Test::X1;
use AnyEvent;
use Path::Class qw(file dir);
use File::Temp qw(tempdir);
use Web::UserAgent::Functions qw(http_get http_post);
use JSON::Functions::XS qw(json_bytes2perl file2perl);

our @EXPORT = (
    @Test::More::EXPORT, @Test::Differences::EXPORT,
    @Test::X1::EXPORT,
    qw(file dir tempdir http_get http_post json_bytes2perl file2perl),
);

1;
