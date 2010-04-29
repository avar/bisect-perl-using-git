#!/usr/bin/env perl
use strict;
use warnings;
use autodie;
use Test::More 'no_plan';
use File::Temp qw<tempdir tempfile>;

my $dir = tempdir( "test-exit-XXXX", CLEANUP => 1, TMPDIR => 1 );


for my $exit (0 .. 255) {
    my ($fh, $sh) = tempfile( DIR => $dir, SUFFIX => '.sh', EXLOCK => 0 );

    print $fh <<"END";
#!/bin/sh
exit $exit;
END
    close $fh;

    chmod 0755, $sh;

    my $code = system $sh;
    $code = $code >> 8;
    cmp_ok($code, '==', $exit, ">> 8 is sane; Exit code was $code, expected $exit");
}
