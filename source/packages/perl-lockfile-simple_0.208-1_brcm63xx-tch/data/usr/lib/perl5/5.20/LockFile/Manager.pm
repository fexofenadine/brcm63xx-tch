;# $Id
;#
;#  @COPYRIGHT@
;#
;# $Log: Manager.pm,v $
;# Revision 0.2  1999/12/07 20:51:05  ram
;# Baseline for 0.2 release.
;#

use strict;

package LockFile::Manager;


my $MANAGER = undef;		# The main manager

sub make {
	my $self = bless {}, shift;
	my ($wfunc, $efunc) = @_;
	$self->{'pool'} = {};
	$self->{'wfunc'} = $wfunc;
	$self->{'efunc'} = $efunc;
	return $self;
}


sub pool	{ $_[0]->{'pool'} }
sub wfunc	{ $_[0]->{'wfunc'} }
sub efunc	{ $_[0]->{'efunc'} }

sub manager {
	my ($class, $wfunc, $efunc) = @_;
	return $MANAGER || ($MANAGER = $class->make($wfunc, $efunc));
}

sub remember {
	my $self = shift;
	my ($lock) = @_;				# A LockFile::Lock object
	my $pool = $self->pool;
	if (exists $pool->{$lock}) {
		&{$self->efunc}("lock $lock already remembered");
		return;
	}
	$pool->{$lock} = $lock;
}

sub forget {
	my $self = shift;
	my ($lock) = @_;				# A LockFile::Lock object
	my $pool = $self->pool;
	unless (exists $pool->{$lock}) {
		&{$self->efunc}("lock $lock not remembered yet");
		return;
	}
	delete $pool->{$lock};
}

sub release_all {
	my $self = shift;
	my $pool = $self->pool;
	my $locks = scalar keys %$pool;
	return unless $locks;

	my $s = $locks == 1 ? '' : 's';
	&{$self->wfunc}("releasing $locks pending lock$s...");

	foreach my $lock (values %$pool) {
		$lock->release;
	}
}

sub END { $MANAGER->release_all if defined $MANAGER }

1;

