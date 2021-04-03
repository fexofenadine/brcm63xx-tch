package B::Showlex;

our $VERSION = '1.04';

use strict;
use B qw(svref_2object comppadlist class);
use B::Terse ();
use B::Concise ();



our $walkHandle = \*STDOUT;

sub walk_output { # updates $walkHandle
    $walkHandle = B::Concise::walk_output(@_);
    #print "got $walkHandle";
    #print $walkHandle "using it";
    $walkHandle;
}

sub shownamearray {
    my ($name, $av) = @_;
    my @els = $av->ARRAY;
    my $count = @els;
    my $i;
    print $walkHandle "$name has $count entries\n";
    for ($i = 0; $i < $count; $i++) {
	my $sv = $els[$i];
	if (class($sv) ne "SPECIAL") {
	    printf $walkHandle "$i: %s (0x%lx) %s\n", class($sv), $$sv, $sv->PVX;
	} else {
	    printf $walkHandle "$i: %s\n", $sv->terse;
	    #printf $walkHandle "$i: %s\n", B::Concise::concise_sv($sv);
	}
    }
}

sub showvaluearray {
    my ($name, $av) = @_;
    my @els = $av->ARRAY;
    my $count = @els;
    my $i;
    print $walkHandle "$name has $count entries\n";
    for ($i = 0; $i < $count; $i++) {
	printf $walkHandle "$i: %s\n", $els[$i]->terse;
	#print $walkHandle "$i: %s\n", B::Concise::concise_sv($els[$i]);
    }
}

sub showlex {
    my ($objname, $namesav, $valsav) = @_;
    shownamearray("Pad of lexical names for $objname", $namesav);
    showvaluearray("Pad of lexical values for $objname", $valsav);
}

my ($newlex, $nosp1); # rendering state vars

sub newlex { # drop-in for showlex
    my ($objname, $names, $vals) = @_;
    my @names = $names->ARRAY;
    my @vals  = $vals->ARRAY;
    my $count = @names;
    print $walkHandle "$objname Pad has $count entries\n";
    printf $walkHandle "0: %s\n", $names[0]->terse unless $nosp1;
    for (my $i = 1; $i < $count; $i++) {
	printf $walkHandle "$i: %s = %s\n", $names[$i]->terse, $vals[$i]->terse
	    unless $nosp1 and $names[$i]->terse =~ /SPECIAL/;
    }
}

sub showlex_obj {
    my ($objname, $obj) = @_;
    $objname =~ s/^&main::/&/;
    showlex($objname, svref_2object($obj)->PADLIST->ARRAY) if !$newlex;
    newlex ($objname, svref_2object($obj)->PADLIST->ARRAY) if  $newlex;
}

sub showlex_main {
    showlex("comppadlist", comppadlist->ARRAY)	if !$newlex;
    newlex ("main", comppadlist->ARRAY)		if  $newlex;
}

sub compile {
    my @options = grep(/^-/, @_);
    my @args = grep(!/^-/, @_);
    for my $o (@options) {
	$newlex = 1 if $o eq "-newlex";
	$nosp1  = 1 if $o eq "-nosp";
    }

    return \&showlex_main unless @args;
    return sub {
	my $objref;
	foreach my $objname (@args) {
	    next unless $objname;	# skip nulls w/o carping

	    if (ref $objname) {
		print $walkHandle "B::Showlex::compile($objname)\n";
		$objref = $objname;
	    } else {
		$objname = "main::$objname" unless $objname =~ /::/;
		print $walkHandle "$objname:\n";
		no strict 'refs';
		die "err: unknown function ($objname)\n"
		    unless *{$objname}{CODE};
		$objref = \&$objname;
	    }
	    showlex_obj($objname, $objref);
	}
    }
}

1;

__END__

