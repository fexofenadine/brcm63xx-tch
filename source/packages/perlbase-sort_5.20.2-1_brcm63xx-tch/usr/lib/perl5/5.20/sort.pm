package sort;

our $VERSION = '2.02';


$sort::quicksort_bit   = 0x00000001;
$sort::mergesort_bit   = 0x00000002;
$sort::sort_bits       = 0x000000FF; # allow 256 different ones
$sort::stable_bit      = 0x00000100;

use strict;

sub import {
    shift;
    if (@_ == 0) {
	require Carp;
	Carp::croak("sort pragma requires arguments");
    }
    local $_;
    $^H{sort} //= 0;
    while ($_ = shift(@_)) {
	if (/^_q(?:uick)?sort$/) {
	    $^H{sort} &= ~$sort::sort_bits;
	    $^H{sort} |=  $sort::quicksort_bit;
	} elsif ($_ eq '_mergesort') {
	    $^H{sort} &= ~$sort::sort_bits;
	    $^H{sort} |=  $sort::mergesort_bit;
	} elsif ($_ eq 'stable') {
	    $^H{sort} |=  $sort::stable_bit;
	} elsif ($_ eq 'defaults') {
	    $^H{sort} =   0;
	} else {
	    require Carp;
	    Carp::croak("sort: unknown subpragma '$_'");
	}
    }
}

sub unimport {
    shift;
    if (@_ == 0) {
	require Carp;
	Carp::croak("sort pragma requires arguments");
    }
    local $_;
    no warnings 'uninitialized';	# bitops would warn
    while ($_ = shift(@_)) {
	if (/^_q(?:uick)?sort$/) {
	    $^H{sort} &= ~$sort::sort_bits;
	} elsif ($_ eq '_mergesort') {
	    $^H{sort} &= ~$sort::sort_bits;
	} elsif ($_ eq 'stable') {
	    $^H{sort} &= ~$sort::stable_bit;
	} else {
	    require Carp;
	    Carp::croak("sort: unknown subpragma '$_'");
	}
    }
}

sub current {
    my @sort;
    if ($^H{sort}) {
	push @sort, 'quicksort' if $^H{sort} & $sort::quicksort_bit;
	push @sort, 'mergesort' if $^H{sort} & $sort::mergesort_bit;
	push @sort, 'stable'    if $^H{sort} & $sort::stable_bit;
    }
    push @sort, 'mergesort' unless @sort;
    join(' ', @sort);
}

1;
__END__


