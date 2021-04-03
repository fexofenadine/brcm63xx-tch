package TAP::Parser::SourceHandler::Perl;

use strict;
use warnings;
use Config;

use constant IS_WIN32 => ( $^O =~ /^(MS)?Win32$/ );
use constant IS_VMS => ( $^O eq 'VMS' );

use TAP::Parser::IteratorFactory           ();
use TAP::Parser::Iterator::Process         ();
use Text::ParseWords qw(shellwords);

use base 'TAP::Parser::SourceHandler::Executable';

TAP::Parser::IteratorFactory->register_handler(__PACKAGE__);


our $VERSION = '3.30';


sub can_handle {
    my ( $class, $source ) = @_;
    my $meta = $source->meta;

    return 0 unless $meta->{is_file};
    my $file = $meta->{file};

    if ( my $shebang = $file->{shebang} ) {
        return 0.9 if $shebang =~ /^#!.*\bperl/;

        # We favour Perl as the interpreter for any shebang to preserve
        # previous semantics: we used to execute everything via Perl and
        # relied on it to pass the shebang off to the appropriate
        # interpreter.
        return 0.3;
    }

    return 0.8 if $file->{lc_ext} eq '.t';    # vote higher than Executable
    return 0.9 if $file->{lc_ext} eq '.pl';

    return 0.75 if $file->{dir} =~ /^t\b/;    # vote higher than Executable

    # backwards compat, always vote:
    return 0.25;
}


sub _autoflush_stdhandles {
    my ($class) = @_;

    $class->_autoflush( \*STDOUT );
    $class->_autoflush( \*STDERR );
}

sub make_iterator {
    my ( $class, $source ) = @_;
    my $meta        = $source->meta;
    my $perl_script = ${ $source->raw };

    $class->_croak("Cannot find ($perl_script)") unless $meta->{is_file};

    # TODO: does this really need to be done here?
    $class->_autoflush_stdhandles;

    my ( $libs, $switches )
      = $class->_mangle_switches(
        $class->_filter_libs( $class->_switches($source) ) );

    $class->_run( $source, $libs, $switches );
}


sub _has_taint_switch {
    my( $class, $switches ) = @_;

    my $has_taint = grep { $_ eq "-T" || $_ eq "-t" } @{$switches};
    return $has_taint ? 1 : 0;
}

sub _mangle_switches {
    my ( $class, $libs, $switches ) = @_;

    # Taint mode ignores environment variables so we must retranslate
    # PERL5LIB as -I switches and place PERL5OPT on the command line
    # in order that it be seen.
    if ( $class->_has_taint_switch($switches) ) {
        my @perl5lib = defined $ENV{PERL5LIB} ? split /$Config{path_sep}/, $ENV{PERL5LIB} : ();
        return (
            $libs,
            [   @{$switches},
                $class->_libs2switches([@$libs, @perl5lib]),
                defined $ENV{PERL5OPT} ? shellwords( $ENV{PERL5OPT} ) : ()
            ],
        );
    }

    return ( $libs, $switches );
}

sub _filter_libs {
    my ( $class, @switches ) = @_;

    my $path_sep = $Config{path_sep};
    my $path_re  = qr{$path_sep};

    # Filter out any -I switches to be handled as libs later.
    #
    # Nasty kludge. It might be nicer if we got the libs separately
    # although at least this way we find any -I switches that were
    # supplied other then as explicit libs.
    #
    # We filter out any names containing colons because they will break
    # PERL5LIB
    my @libs;
    my @filtered_switches;
    for (@switches) {
        if ( !/$path_re/ && m/ ^ ['"]? -I ['"]? (.*?) ['"]? $ /x ) {
            push @libs, $1;
        }
        else {
            push @filtered_switches, $_;
        }
    }

    return \@libs, \@filtered_switches;
}

sub _iterator_hooks {
    my ( $class, $source, $libs, $switches ) = @_;

    my $setup = sub {
        if ( @{$libs} and !$class->_has_taint_switch($switches) ) {
            $ENV{PERL5LIB} = join(
                $Config{path_sep}, grep {defined} @{$libs},
                $ENV{PERL5LIB}
            );
        }
    };

    # VMS environment variables aren't guaranteed to reset at the end of
    # the process, so we need to put PERL5LIB back.
    my $previous = $ENV{PERL5LIB};
    my $teardown = sub {
        if ( defined $previous ) {
            $ENV{PERL5LIB} = $previous;
        }
        else {
            delete $ENV{PERL5LIB};
        }
    };

    return ( $setup, $teardown );
}

sub _run {
    my ( $class, $source, $libs, $switches ) = @_;

    my @command = $class->_get_command_for_switches( $source, $switches )
      or $class->_croak("No command found!");

    my ( $setup, $teardown ) = $class->_iterator_hooks( $source, $libs, $switches );

    return $class->_create_iterator( $source, \@command, $setup, $teardown );
}

sub _create_iterator {
    my ( $class, $source, $command, $setup, $teardown ) = @_;

    return TAP::Parser::Iterator::Process->new(
        {   command  => $command,
            merge    => $source->merge,
            setup    => $setup,
            teardown => $teardown,
        }
    );
}

sub _get_command_for_switches {
    my ( $class, $source, $switches ) = @_;
    my $file    = ${ $source->raw };
    my @args    = @{ $source->test_args || [] };
    my $command = $class->get_perl;

   # XXX don't need to quote if we treat the parts as atoms (except maybe vms)
   #$file = qq["$file"] if ( $file =~ /\s/ ) && ( $file !~ /^".*"$/ );
    my @command = ( $command, @{$switches}, $file, @args );
    return @command;
}

sub _libs2switches {
    my $class = shift;
    return map {"-I$_"} grep {$_} @{ $_[0] };
}


sub get_taint {
    my ( $class, $shebang ) = @_;
    return
      unless defined $shebang
          && $shebang =~ /^#!.*\bperl.*\s-\w*([Tt]+)/;
    return $1;
}

sub _switches {
    my ( $class, $source ) = @_;
    my $file     = ${ $source->raw };
    my @switches = @{ $source->switches || [] };
    my $shebang  = $source->meta->{file}->{shebang};
    return unless defined $shebang;

    my $taint = $class->get_taint($shebang);
    push @switches, "-$taint" if defined $taint;

    # Quote the argument if we're VMS, since VMS will downcase anything
    # not quoted.
    if (IS_VMS) {
        for (@switches) {
            $_ = qq["$_"];
        }
    }

    return @switches;
}


sub get_perl {
    my $class = shift;
    return $ENV{HARNESS_PERL} if defined $ENV{HARNESS_PERL};
    return qq["$^X"] if IS_WIN32 && ( $^X =~ /[^\w\.\/\\]/ );
    return $^X;
}

1;

__END__

