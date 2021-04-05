;# $Id
;#
;#  @COPYRIGHT@
;#
;# $Log: Lock.pm,v $
;# Revision 0.3  2007/09/28 19:20:14  jv
;# Track where lock was issued in the code.
;#
;# Revision 0.2.1.1  2000/01/04 21:16:28  ram
;# patch1: track where lock was issued in the code
;#
;# Revision 0.2  1999/12/07 20:51:04  ram
;# Baseline for 0.2 release.
;#

use strict;

package LockFile::Lock;


sub _lock_init {
	my $self = shift;
	my ($scheme, $filename, $line) = @_;
	$self->{'scheme'} = $scheme;
	$self->{'filename'} = $filename;
	$self->{'line'} = $line;
}


sub scheme		{ $_[0]->{'scheme'} }
sub filename	{ $_[0]->{'filename'} }
sub line		{ $_[0]->{'line'} }

sub release {
	my $self = shift;
	return $self->scheme->release($self);
}

sub where {
	my $self = shift;
	return sprintf '"%s", line %d', $self->filename, $self->line;
}

1;

