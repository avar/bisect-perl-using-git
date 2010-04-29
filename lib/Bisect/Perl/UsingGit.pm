package Bisect::Perl::UsingGit;
use Moose;
use MooseX::Types::Path::Class;
with 'MooseX::Getopt';
use Capture::Tiny qw(tee);
our $VERSION = '0.33';

has help => (
    traits        => [ qw/ Getopt / ],
    cmd_aliases   => 'h',
    cmd_flag      => 'help',
    isa           => 'Bool',
    is            => 'ro',
    default       => 0,
    documentation => "You're soaking it in",
);

has 'verbose' => (
    traits        => [ qw/ Getopt / ],
    cmd_aliases   => 'v',
    cmd_flag      => 'verbose',
    is            => 'ro',
    isa           => 'Bool',
    default       => 0,
    documentation => 'Display Configure and make output',
);

has 'action' => (
    traits        => [ qw/ Getopt / ],
    cmd_aliases   => 'a',
    cmd_flag      => 'action',
    is            => 'ro',
    isa           => 'Str',
    required      => 1,
    documentation => 'Any of: file-added, file-removed, perl-fail, miniperl-fail, perl-ok, miniperl-ok',
 
);

{
my $configure_default = q[-des -Dusedevel -Doptimize="-g" -Dcc=ccache\ gcc -Dld=gcc];
has 'configure_options' => (
    traits        => [ qw/ Getopt / ],
    cmd_aliases   => 'c',
    cmd_flag      => 'configure-options',
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    default       => $configure_default,
    documentation => "Our ./Configure options, default: $configure_default",
);
}

has 'filename' => (
    traits        => [ qw/ Getopt / ],
    cmd_aliases   => 'f',
    cmd_flag      => 'filename',
    is            => 'ro',
    isa           => 'Path::Class::File',
    required      => 1,
    coerce        => 1,
    documentation => "The test file to run with the *perl_fails actions",
    trigger       => sub {
        my ($self, $file) = @_;

        $self->_error("There's no file $file") unless -f $file;
        $self->_error("I can't read the file $file") unless -r $file;
        return;
    },
);

sub run {
    my $self   = shift;
    my $action = $self->action;
    $self->_describe();

    $action =~ s/-/_/g;
    $action =~ s/fails$/fail/g;

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

# Things to run before we `make' perl. There are a lot of bugs in old
# perls that can keep us from building them on new platforms.
sub _before_perlX {
    my $self     = shift;

    $self->_call_or_error('git clean -dxf' . $self->_maybe_shutup);

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

    $self->_call_or_error('sh Configure ' . $self->configure_options . $self->_maybe_shutup);

    -f 'config.sh' || $self->_error('Missing config.sh');

    return;
}

# Clean up after the build
sub _after_perlX {
    my $self = shift;

    $self->_call_or_error('git clean -dxf' . $self->_maybe_shutup);
    $self->_call_or_error('git checkout ext/IPC/SysV/SysV.xs')
        if -f 'ext/IPC/SysV/SysV.xs';
    $self->_call_or_error('git checkout makedepend.SH') if -f 'makedepend.SH';

    return;
}

# Run some target/perl
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

before $_ => \&_before_perlX for qw< perl_fail miniperl_fail >;

sub perl_fail {
    my $self     = shift;

    $self->_call_or_error('make' . $self->_maybe_shutup);
    my $code = $self->run_perlX('perl');
    $self->_after_perlX();
    return $code;
}

sub miniperl_fail {
    my $self     = shift;
    
    $self->_call_or_error('make miniperl' . $self->_maybe_shutup);
    my $code = $self->run_perlX('miniperl');
    $self->_after_perlX();
    return $code;
}

sub perl_ok     { int not shift->perl_fail }
sub miniperl_ok { int not shift->miniperl_fail }

sub _describe {
    my $self     = shift;
    my $describe = $self->_call_or_error('git describe')->{stdout};
    chomp $describe;
    $self->_error('No git describe') unless $describe;
    $self->_message("\n*** $describe ***\n");
}

sub _call {
    my ( $self, $command ) = @_;
    $self->_message("calling $command") if $self->verbose;
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

sub _maybe_shutup {
    my $self = shift;
    my $verbose = $self->verbose;
    return $verbose ? '' : ' >/dev/null 2>&1'
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
