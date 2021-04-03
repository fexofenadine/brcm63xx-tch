package SelfLoader;
use 5.008;
use strict;
use IO::Handle;
our $VERSION = "1.21";

use vars qw/$AttrList/;
BEGIN {
  if ($] > 5.009004) {
    eval <<'NEWERPERL';
use 5.009005; # due to new regexp features
$AttrList = qr{
    \s* : \s*
    (?:
	# one attribute
	(?> # no backtrack
	    (?! \d) \w+
	    (?<nested> \( (?: [^()]++ | (?&nested)++ )*+ \) ) ?
	)
	(?: \s* : \s* | \s+ (?! :) )
    )*
}x;

NEWERPERL
  }
  else {
    eval <<'OLDERPERL';
our $nested;
$nested = qr{ \( (?: (?> [^()]+ ) | (??{ $nested }) )* \) }x;
our $one_attr = qr{ (?> (?! \d) \w+ (?:$nested)? ) (?:\s*\:\s*|\s+(?!\:)) }x;
$AttrList = qr{ \s* : \s* (?: $one_attr )* }x;
OLDERPERL
  }
}
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(AUTOLOAD);
sub Version {$VERSION}
sub DEBUG () { 0 }

my %Cache;      # private cache for all SelfLoader's client packages


sub croak { { local $@; require Carp; } goto &Carp::croak }
sub carp { { local $@; require Carp; } goto &Carp::carp }

AUTOLOAD {
    our $AUTOLOAD;
    print STDERR "SelfLoader::AUTOLOAD for $AUTOLOAD\n" if DEBUG;
    my $SL_code = $Cache{$AUTOLOAD};
    my $save = $@; # evals in both AUTOLOAD and _load_stubs can corrupt $@
    unless ($SL_code) {
        # Maybe this pack had stubs before __DATA__, and never initialized.
        # Or, this maybe an automatic DESTROY method call when none exists.
        $AUTOLOAD =~ m/^(.*)::/;
        SelfLoader->_load_stubs($1) unless exists $Cache{"${1}::<DATA"};
        $SL_code = $Cache{$AUTOLOAD};
        $SL_code = "sub $AUTOLOAD { }"
            if (!$SL_code and $AUTOLOAD =~ m/::DESTROY$/);
        croak "Undefined subroutine $AUTOLOAD" unless $SL_code;
    }
    print STDERR "SelfLoader::AUTOLOAD eval: $SL_code\n" if DEBUG;

    {
	no strict;
	eval $SL_code;
    }
    if ($@) {
        $@ =~ s/ at .*\n//;
        croak $@;
    }
    $@ = $save;
    defined(&$AUTOLOAD) || die "SelfLoader inconsistency error";
    delete $Cache{$AUTOLOAD};
    goto &$AUTOLOAD
}

sub load_stubs { shift->_load_stubs((caller)[0]) }

sub _load_stubs {
    # $endlines is used by Devel::SelfStubber to capture lines after __END__
    my($self, $callpack, $endlines) = @_;
    no strict "refs";
    my $fh = \*{"${callpack}::DATA"};
    use strict;
    my $currpack = $callpack;
    my($line,$name,@lines, @stubs, $protoype);

    print STDERR "SelfLoader::load_stubs($callpack)\n" if DEBUG;
    croak("$callpack doesn't contain an __DATA__ token")
        unless defined fileno($fh);
    # Protect: fork() shares the file pointer between the parent and the kid
    if(sysseek($fh, tell($fh), 0)) {
      open my $nfh, '<&', $fh or croak "reopen: $!";# dup() the fd
      close $fh or die "close: $!";                 # autocloses, but be paranoid
      open $fh, '<&', $nfh or croak "reopen2: $!";  # dup() the fd "back"
      close $nfh or die "close after reopen: $!";   # autocloses, but be paranoid
      $fh->untaint;
    }
    $Cache{"${currpack}::<DATA"} = 1;   # indicate package is cached

    local($/) = "\n";
    while(defined($line = <$fh>) and $line !~ m/^__END__/) {
	if ($line =~ m/^\s*sub\s+([\w:]+)\s*((?:\([\\\$\@\%\&\*\;]*\))?(?:$AttrList)?)/) {
            push(@stubs, $self->_add_to_cache($name, $currpack, \@lines, $protoype));
            $protoype = $2;
            @lines = ($line);
            if (index($1,'::') == -1) {         # simple sub name
                $name = "${currpack}::$1";
            } else {                            # sub name with package
                $name = $1;
                $name =~ m/^(.*)::/;
                if (defined(&{"${1}::AUTOLOAD"})) {
                    \&{"${1}::AUTOLOAD"} == \&SelfLoader::AUTOLOAD ||
                        die 'SelfLoader Error: attempt to specify Selfloading',
                            " sub $name in non-selfloading module $1";
                } else {
                    $self->export($1,'AUTOLOAD');
                }
            }
        } elsif ($line =~ m/^package\s+([\w:]+)/) { # A package declared
            push(@stubs, $self->_add_to_cache($name, $currpack, \@lines, $protoype));
            $self->_package_defined($line);
            $name = '';
            @lines = ();
            $currpack = $1;
            $Cache{"${currpack}::<DATA"} = 1;   # indicate package is cached
            if (defined(&{"${1}::AUTOLOAD"})) {
                \&{"${1}::AUTOLOAD"} == \&SelfLoader::AUTOLOAD ||
                    die 'SelfLoader Error: attempt to specify Selfloading',
                        " package $currpack which already has AUTOLOAD";
            } else {
                $self->export($currpack,'AUTOLOAD');
            }
        } else {
            push(@lines,$line);
        }
    }
    if (defined($line) && $line =~ /^__END__/) { # __END__
        unless ($line =~ /^__END__\s*DATA/) {
            if ($endlines) {
                # Devel::SelfStubber would like us to capture the lines after
                # __END__ so it can write out the entire file
                @$endlines = <$fh>;
            }
            close($fh);
        }
    }
    push(@stubs, $self->_add_to_cache($name, $currpack, \@lines, $protoype));
    no strict;
    eval join('', @stubs) if @stubs;
}


sub _add_to_cache {
    my($self,$fullname,$pack,$lines, $protoype) = @_;
    return () unless $fullname;
    carp("Redefining sub $fullname")
      if exists $Cache{$fullname};
    $Cache{$fullname} = join('', "\n\#line 1 \"sub $fullname\"\npackage $pack; ", @$lines);
    #$Cache{$fullname} = join('', "package $pack; ",@$lines);
    print STDERR "SelfLoader cached $fullname: $Cache{$fullname}" if DEBUG;
    # return stub to be eval'd
    defined($protoype) ? "sub $fullname $protoype;" : "sub $fullname;"
}

sub _package_defined {}

1;
__END__

