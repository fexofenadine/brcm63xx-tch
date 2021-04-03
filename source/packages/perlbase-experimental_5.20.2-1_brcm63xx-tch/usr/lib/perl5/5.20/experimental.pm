package experimental;
$experimental::VERSION = '0.007';
use strict;
use warnings;

use feature ();
use Carp qw/croak carp/;

my %warnings = map { $_ => 1 } grep { /^experimental::/ } keys %warnings::Offsets;
my %features = map { $_ => 1 } keys %feature::feature;

my %min_version = (
	array_base    => 5,
	autoderef     => 5.014000,
	lexical_topic => 5.010000,
	regex_sets    => 5.018000,
	smartmatch    => 5.010001,
	signatures    => 5.019009, # change to 5.20.0 someday? -- rjbs, 2014-02-08
);

my %additional = (
	postderef  => ['postderef_qq'],
	switch     => ['smartmatch'],
);

sub _enable {
	my $pragma = shift;
	if ($warnings{"experimental::$pragma"}) {
		warnings->unimport("experimental::$pragma");
		feature->import($pragma) if exists $features{$pragma};
		_enable(@{ $additional{$pragma} }) if $additional{$pragma};
	}
	elsif ($features{$pragma}) {
		feature->import($pragma);
		_enable(@{ $additional{$pragma} }) if $additional{$pragma};
	}
	elsif (not exists $min_version{$pragma}) {
		croak "Can't enable unknown feature $pragma";
	}
	elsif ($min_version{$pragma} > $]) {
		croak "Need perl version $min_version{$pragma} or later for feature $pragma";
	}
}

sub import {
	my ($self, @pragmas) = @_;

	for my $pragma (@pragmas) {
		_enable($pragma);
	}
	return;
}

sub _disable {
	my $pragma = shift;
	if ($warnings{"experimental::$pragma"}) {
		warnings->import("experimental::$pragma");
		feature->unimport($pragma) if exists $features{$pragma};
		_disable(@{ $additional{$pragma} }) if $additional{$pragma};
	}
	elsif ($features{$pragma}) {
		feature->unimport($pragma);
		_disable(@{ $additional{$pragma} }) if $additional{$pragma};
	}
	elsif (not exists $min_version{$pragma}) {
		carp "Can't disable unknown feature $pragma, ignoring";
	}
}

sub unimport {
	my ($self, @pragmas) = @_;

	for my $pragma (@pragmas) {
		_disable($pragma);
	}
	return;
}

1;


__END__

