package Bisect::Perl::UsingGit;
use Moose;
use MooseX::Types::Path::Class;
with 'MooseX::Getopt';
use Capture::Tiny qw(tee);
our $VERSION = '0.33';

has 'action' => ( is => 'rw', isa => 'Str', required => 1 );
has 'filename' =>
    ( is => 'rw', isa => 'Path::Class::File', required => 1, coerce => 1, );
has 'verbose' => ( is => 'rw', isa => 'Bool', default => 0 );

sub run {
    my $self   = shift;
    my $action = $self->action;
    $self->_describe();

    exit $self->$action;
}

sub file_added {
    my $self     = shift;
    my $filename = $self->filename;

    if ( -f $filename ) {
        $self->_message("have $filename");
        return 1;
    } else {
        $self->_message("do not have $filename");
        return 0;
    }
}

sub file_removed {
    my $self     = shift;
    my $filename = $self->filename;
    return !$self->file_added($filename);
}

sub _before_perlX {
    my $self     = shift;

    $self->_call_or_error('git clean -dxf');

    # Fix configure error in makedepend: unterminated quoted string
    # http://perl5.git.perl.org/perl.git/commitdiff/a9ff62
    $self->_call_or_error($^X . q{ -pi -e "s|##\`\"|##'\`\"|" makedepend.SH})
        if -f 'makedepend.SH';

    # Allow recent gccs (4.2.0 20060715 onwards) to build perl.
    # It switched from '<command line>' to '<command-line>'.
    # http://perl5.git.perl.org/perl.git/commit/d64920
    $self->_call_or_error(
        $^X . q{ -pi -e "s|command line|command-line|" makedepend.SH})
        if -f 'makedepend.SH';

    # http://perl5.git.perl.org/perl.git/commit/205bd5
    $self->_call_or_error(
        $^X . q{ -pi -e "s|#   include <asm/page.h>||" ext/IPC/SysV/SysV.xs})
        if -f 'ext/IPC/SysV/SysV.xs';

    $self->_call_or_error(
        'sh Configure -des -Dusedevel -Doptimize="-g" -Dcc=ccache\ gcc -Dld=gcc'
    );

    -f 'config.sh' || $self->_error('Missing config.sh');

    return;
}

sub _after_perlX {
    my $self = shift;

    $self->_call_or_error('git clean -dxf');
    $self->_call_or_error('git checkout ext/IPC/SysV/SysV.xs')
        if -f 'ext/IPC/SysV/SysV.xs';
    $self->_call_or_error('git checkout makedepend.SH') if -f 'makedepend.SH';

    return;
}

sub run_perlX {
    my ($self, $whatperl) = @_;
    my $filename = $self->filename;

    -x "./$whatperl" || $self->_error('No ./$whatperl executable');
    my $code = $self->_call("./$whatperl -Ilib $filename")->{code};
    $self->_message("Status: $code");
    if ( $code < 0 || $code >= 128 ) {
        $self->_message("Changing code to 127 as it is < 0 or >= 128");
        $code = 127;
    }

    return $code;
}

before $_ => \&_before_perlX for qw< perl_fails miniperl_fails >;
before $_ => \&_after_perlX for qw< perl_fails miniperl_fails >;

sub perl_fails {
    my $self     = shift;
    my $filename = $self->filename;

    $self->_call_or_error('make');
    my $code = $self->run_perlX('perl');

    return $code;
}

sub miniperl_fails {
    my $self     = shift;
    my $filename = $self->filename;

    $self->_call_or_error('make miniperl');
    my $code = $self->run_perlX('miniperl');

    return $code;
}

sub _describe {
    my $self     = shift;
    my $describe = $self->_call_or_error('git describe')->{stdout};
    chomp $describe;
    $self->_error('No git describe') unless $describe;
    $self->_message("\n*** $describe ***\n");
}

sub _call {
    my ( $self, $command ) = @_;
    $self->_message("calling $command");
    my $status;
    my ( $stdout, $stderr ) = tee {
        $status = system($command);
    };
    my $code = $status >> 8;
    return {
        code   => $code,
        stdout => $stdout,
        stderr => $stderr,
    };
}

sub _call_or_error {
    my ( $self, $command ) = @_;
    my $captured = $self->_call($command);
    unless ( $captured->{code} == 0 ) {
        $self->_error( "$command failed: $?: " . $captured->{stderr} );
    }
    $self->_message($command);
    return $captured;
}

sub _message {
    my ( $self, $text ) = @_;

    #    $log->print("$text\n");
    print "$text\n";
}

sub _error {
    my ( $self, $text ) = @_;
    $self->_message($text);
    exit 125;
}

1;

__END__

=head1 NAME

Bisect::Perl::UsingGit - Help you to bisect Perl

=head1 DESCRIPTION

L<Bisect::Perl::UsingGit> is a module which holds the code which helps
you to bisect Perl. See L<bisect_perl_using_git> for practical examples.

=head1 AUTHOR

Leon Brocard, C<< <acme@astray.com> >>

=head1 COPYRIGHT

Copyright (C) 2009, Leon Brocard

=head1 LICENSE

This module is free software; you can redistribute it or modify it
under the same terms as Perl itself.
