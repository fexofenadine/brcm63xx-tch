package open;
use warnings;

our $VERSION = '1.10';

require 5.008001; # for PerlIO::get_layers()

my $locale_encoding;

sub _get_encname {
    return ($1, Encode::resolve_alias($1)) if $_[0] =~ /^:?encoding\((.+)\)$/;
    return;
}

sub croak {
    require Carp; goto &Carp::croak;
}

sub _drop_oldenc {
    # If by the time we arrive here there already is at the top of the
    # perlio layer stack an encoding identical to what we would like
    # to push via this open pragma, we will pop away the old encoding
    # (+utf8) so that we can push ourselves in place (this is easier
    # than ignoring pushing ourselves because of the way how ${^OPEN}
    # works).  So we are looking for something like
    #
    #   stdio encoding(xxx) utf8
    #
    # in the existing layer stack, and in the new stack chunk for
    #
    #   :encoding(xxx)
    #
    # If we find a match, we pop the old stack (once, since
    # the utf8 is just a flag on the encoding layer)
    my ($h, @new) = @_;
    return unless @new >= 1 && $new[-1] =~ /^:encoding\(.+\)$/;
    my @old = PerlIO::get_layers($h);
    return unless @old >= 3 &&
	          $old[-1] eq 'utf8' &&
                  $old[-2] =~ /^encoding\(.+\)$/;
    require Encode;
    my ($loname, $lcname) = _get_encname($old[-2]);
    unless (defined $lcname) { # Should we trust get_layers()?
	croak("open: Unknown encoding '$loname'");
    }
    my ($voname, $vcname) = _get_encname($new[-1]);
    unless (defined $vcname) {
	croak("open: Unknown encoding '$voname'");
    }
    if ($lcname eq $vcname) {
	binmode($h, ":pop"); # utf8 is part of the encoding layer
    }
}

sub import {
    my ($class,@args) = @_;
    croak("open: needs explicit list of PerlIO layers") unless @args;
    my $std;
    my ($in,$out) = split(/\0/,(${^OPEN} || "\0"), -1);
    while (@args) {
	my $type = shift(@args);
	my $dscp;
	if ($type =~ /^:?(utf8|locale|encoding\(.+\))$/) {
	    $type = 'IO';
	    $dscp = ":$1";
	} elsif ($type eq ':std') {
	    $std = 1;
	    next;
	} else {
	    $dscp = shift(@args) || '';
	}
	my @val;
	foreach my $layer (split(/\s+/,$dscp)) {
            $layer =~ s/^://;
	    if ($layer eq 'locale') {
		require Encode;
		require encoding;
		$locale_encoding = encoding::_get_locale_encoding()
		    unless defined $locale_encoding;
		(warnings::warnif("layer", "Cannot figure out an encoding to use"), last)
		    unless defined $locale_encoding;
                $layer = "encoding($locale_encoding)";
		$std = 1;
	    } else {
		my $target = $layer;		# the layer name itself
		$target =~ s/^(\w+)\(.+\)$/$1/;	# strip parameters

		unless(PerlIO::Layer::->find($target,1)) {
		    warnings::warnif("layer", "Unknown PerlIO layer '$target'");
		}
	    }
	    push(@val,":$layer");
	    if ($layer =~ /^(crlf|raw)$/) {
		$^H{"open_$type"} = $layer;
	    }
	}
	if ($type eq 'IN') {
	    _drop_oldenc(*STDIN, @val) if $std;
	    $in  = join(' ', @val);
	}
	elsif ($type eq 'OUT') {
	    if ($std) {
		_drop_oldenc(*STDOUT, @val);
		_drop_oldenc(*STDERR, @val);
	    }
	    $out = join(' ', @val);
	}
	elsif ($type eq 'IO') {
	    if ($std) {
		_drop_oldenc(*STDIN, @val);
		_drop_oldenc(*STDOUT, @val);
		_drop_oldenc(*STDERR, @val);
	    }
	    $in = $out = join(' ', @val);
	}
	else {
	    croak "Unknown PerlIO layer class '$type' (need IN, OUT or IO)";
	}
    }
    ${^OPEN} = join("\0", $in, $out);
    if ($std) {
	if ($in) {
	    if ($in =~ /:utf8\b/) {
		    binmode(STDIN,  ":utf8");
		} elsif ($in =~ /(\w+\(.+\))/) {
		    binmode(STDIN,  ":$1");
		}
	}
	if ($out) {
	    if ($out =~ /:utf8\b/) {
		binmode(STDOUT,  ":utf8");
		binmode(STDERR,  ":utf8");
	    } elsif ($out =~ /(\w+\(.+\))/) {
		binmode(STDOUT,  ":$1");
		binmode(STDERR,  ":$1");
	    }
	}
    }
}

1;
__END__

