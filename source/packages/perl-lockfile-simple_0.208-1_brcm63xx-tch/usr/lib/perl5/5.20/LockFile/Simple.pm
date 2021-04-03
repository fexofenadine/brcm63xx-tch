;# $Id$
;#
;#  @COPYRIGHT@
;#
;# $Log: Simple.pm,v $
;# Revision 0.4  2007/09/28 19:22:05  jv
;# Bump version.
;#
;# Revision 0.3  2007/09/28 19:19:41  jv
;# Revision 0.2.1.5  2000/09/18 19:55:07  ram
;# patch5: fixed computation of %F and %D when no '/' in file name
;# patch5: fixed OO example of lock to emphasize check on returned value
;# patch5: now warns when no lockfile is found during unlocking
;#
;# Revision 0.2.1.4  2000/08/15 18:41:43  ram
;# patch4: updated version number, grrr...
;#
;# Revision 0.2.1.3  2000/08/15 18:37:37  ram
;# patch3: fixed non-working "-wfunc => undef" due to misuse of defined()
;# patch3: check for stale lock while we wait for it
;# patch3: untaint pid before running kill() for -T scripts
;#
;# Revision 0.2.1.2  2000/03/02 22:35:02  ram
;# patch2: allow "undef" in -efunc and -wfunc to suppress logging
;# patch2: documented how to force warn() despite Log::Agent being there
;#
;# Revision 0.2.1.1  2000/01/04 21:18:10  ram
;# patch1: logerr and logwarn are autoloaded, need to check something real
;# patch1: forbid re-lock of a file we already locked
;# patch1: force $\ to be undef prior to writing the PID to lockfile
;# patch1: track where lock was issued in the code
;#
;# Revision 0.2.1.5  2000/09/18 19:55:07  ram
;# patch5: fixed computation of %F and %D when no '/' in file name
;# patch5: fixed OO example of lock to emphasize check on returned value
;# patch5: now warns when no lockfile is found during unlocking
;#
;# Revision 0.2.1.4  2000/08/15 18:41:43  ram
;# patch4: updated version number, grrr...
;#
;# Revision 0.2.1.3  2000/08/15 18:37:37  ram
;# patch3: fixed non-working "-wfunc => undef" due to misuse of defined()
;# patch3: check for stale lock while we wait for it
;# patch3: untaint pid before running kill() for -T scripts
;#
;# Revision 0.2.1.2  2000/03/02 22:35:02  ram
;# patch2: allow "undef" in -efunc and -wfunc to suppress logging
;# patch2: documented how to force warn() despite Log::Agent being there
;#
;# Revision 0.2.1.1  2000/01/04 21:18:10  ram
;# patch1: logerr and logwarn are autoloaded, need to check something real
;# patch1: forbid re-lock of a file we already locked
;# patch1: force $\ to be undef prior to writing the PID to lockfile
;# patch1: track where lock was issued in the code
;#
;# Revision 0.2  1999/12/07 20:51:05  ram
;# Baseline for 0.2 release.
;#

use strict;

package LockFile::Simple;


use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

use Sys::Hostname;
require Exporter;
require LockFile::Lock::Simple;
eval "use Log::Agent";

@ISA = qw(Exporter);
@EXPORT = ();
@EXPORT_OK = qw(lock trylock unlock);
$VERSION = '0.208';

my $LOCKER = undef;			# Default locking object

sub make {
	my $self = bless {}, shift;
	my (@hlist) = @_;

	# Set configuration defaults, then override with user preferences
	$self->{'max'} = 30;
	$self->{'delay'} = 2;
	$self->{'hold'} = 3600;
	$self->{'ext'} = '.lock';
	$self->{'nfs'} = 0;
	$self->{'stale'} = 0;
	$self->{'warn'} = 1;
	$self->{'wmin'} = 15;
	$self->{'wafter'} = 20;
	$self->{'autoclean'} = 0;
	$self->{'lock_by_file'} = {};

	# The logxxx routines are autoloaded, so need to check for @EXPORT
	$self->{'wfunc'} = @Log::Agent::EXPORT ? \&logwarn : \&core_warn;
	$self->{'efunc'} = @Log::Agent::EXPORT ?  \&logerr  : \&core_warn;

	$self->configure(@hlist);		# Will init "manager" if necessary
	return $self;
}

sub locker {
	return $LOCKER || ($LOCKER = LockFile::Simple->make('-warn' => 1));
}

sub configure {
	my $self = shift;
	my (%hlist) = @_;
	my @known = qw(
		autoclean
		max delay hold format ext nfs warn wfunc wmin wafter efunc stale
	);

	foreach my $attr (@known) {
		$self->{$attr} = $hlist{"-$attr"} if exists $hlist{"-$attr"};
	}

	$self->{'wfunc'} = \&no_warn unless defined $self->{'wfunc'};
	$self->{'efunc'} = \&no_warn unless defined $self->{'efunc'};

	if ($self->autoclean) {
		require LockFile::Manager;
		# Created via "once" function
		$self->{'manager'} = LockFile::Manager->manager(
			$self->wfunc, $self->efunc);
	}
}


sub max				{ $_[0]->{'max'} }
sub delay			{ $_[0]->{'delay'} }
sub format			{ $_[0]->{'format'} }
sub hold			{ $_[0]->{'hold'} }
sub nfs				{ $_[0]->{'nfs'} }
sub stale			{ $_[0]->{'stale'} }
sub ext				{ $_[0]->{'ext'} }
sub warn			{ $_[0]->{'warn'} }
sub wmin			{ $_[0]->{'wmin'} }
sub wafter			{ $_[0]->{'wafter'} }
sub wfunc			{ $_[0]->{'wfunc'} }
sub efunc			{ $_[0]->{'efunc'} }
sub autoclean		{ $_[0]->{'autoclean'} }
sub lock_by_file	{ $_[0]->{'lock_by_file'} }
sub manager			{ $_[0]->{'manager'} }


sub core_warn	{ CORE::warn(@_) }
sub no_warn		{ return }

sub lock {
	my $self = shift;
	unless (ref $self) {			# Not invoked as a method
		unshift(@_, $self);
		$self = locker();
	}
	my ($file, $format) = @_;		# File to be locked, lock format
	return $self->take_lock($file, $format, 0);
}

sub trylock {
	my $self = shift;
	unless (ref $self) {			# Not invoked as a method
		unshift(@_, $self);
		$self = locker();
	}
	my ($file, $format) = @_;		# File to be locked, lock format
	return $self->take_lock($file, $format, 1);
}

sub take_lock {
	my $self = shift;
	my ($file, $format, $tryonly) = @_;

	#
	# If lock was already taken by us, it's an error when $tryonly is 0.
	# Otherwise, simply fail to get the lock.
	#

	my $lock = $self->lock_by_file->{$file};
	if (defined $lock) {
		my $where = $lock->where;
		&{$self->efunc}("file $file already locked at $where") unless $tryonly;
		return undef;
	}

	my $locked = $self->_acs_lock($file, $format, $tryonly);
	return undef unless $locked;

	#
	# Create LockFile::Lock object
	#

	my ($package, $filename, $line) = caller(1);
	$lock = LockFile::Lock::Simple->make($self, $file, $format,
		$filename, $line);
	$self->manager->remember($lock) if $self->autoclean;
	$self->lock_by_file->{$file} = $lock;

	return $lock;
}

sub unlock {
	my $self = shift;
	unless (ref $self) {			# Not invoked as a method
		unshift(@_, $self);
		$self = locker();
	}
	my ($file, $format) = @_;		# File to be unlocked, lock format

	if (defined $format) {
		require Carp;
		Carp::carp("2nd argument (format) is no longer needed nor used");
	}

	#
	# Retrieve LockFile::Lock object
	#

	my $lock = $self->lock_by_file->{$file};

	unless (defined $lock) {
		&{$self->efunc}("file $file not currently locked");
		return undef;
	}

	return $self->release($lock);
}

sub release {
	my $self = shift;
	my ($lock) = @_;
	my $file = $lock->file;
	my $format = $lock->format;
	$self->manager->forget($lock) if $self->autoclean;
	delete $self->lock_by_file->{$file};
	return $self->_acs_unlock($file, $format);
}

sub lockfile {
	my $self = shift;
	my ($file, $format) = @_;
	local $_ = defined($format) ? $format : $self->format;
	s/%%/\01/g;				# Protect double percent signs
	s/%/\02/g;				# Protect against substitutions adding their own %
	s/\02f/$file/g;			# %f is the full path name
	s/\02D/&dir($file)/ge;	# %D is the dir name
	s/\02F/&base($file)/ge;	# %F is the base name
	s/\02p/$$/g;			# %p is the process's pid
	s/\02/%/g;				# All other % kept as-is
	s/\01/%/g;				# Restore escaped % signs
	$_;
}

sub base {
	my ($file) = @_;
	my ($base) = $file =~ m|^.*/(.*)|;
	return ($base eq '') ? $file : $base;
}

sub dir {
	my ($file) = @_;
	my ($dir) = $file =~ m|^(.*)/.*|;
	return ($dir eq '') ? '.' : $dir;
}

sub _acs_lock {		## private
	my $self = shift;
	my ($file, $format, $try) = @_;
	my $max = $self->max;
	my $delay = $self->delay;
	my $stamp = $$;

	# For NFS, we need something more unique than the process's PID
	$stamp .= ':' . hostname if $self->nfs;

	# Compute locking file name -- hardwired default format is "%f.lock"
	my $lockfile = $file . $self->ext;
	$format = $self->format unless defined $format;
	$lockfile = $self->lockfile($file, $format) if defined $format;

	# Detect stale locks or break lock if held for too long
	$self->_acs_stale($file, $lockfile) if $self->stale;
	$self->_acs_check($file, $lockfile) if $self->hold;

	my $waited = 0;					# Amount of time spent sleeping
	my $lastwarn = 0;				# Last time we warned them...
	my $warn = $self->warn;
	my ($wmin, $wafter, $wfunc);
	($wmin, $wafter, $wfunc) = 
		($self->wmin, $self->wafter, $self->wfunc) if $warn;
	my $locked = 0;
	my $mask = umask(0333);			# No write permission
	local *FILE;

	while ($max-- > 0) {
		if (-f $lockfile) {
			next unless $try;
			umask($mask);
			return 0;				# Already locked
		}

		# Attempt to create lock
		if (open(FILE, ">$lockfile")) {
			local $\ = undef;
			print FILE "$stamp\n";
			close FILE;
			open(FILE, $lockfile);	# Check lock
			my $l;
			chop($l = <FILE>);
			$locked = $l eq $stamp;
			$l = <FILE>;			# Must be EOF
			$locked = 0 if defined $l; 
			close FILE;
			last if $locked;		# Lock seems to be ours
		} elsif ($try) {
			umask($mask);
			return 0;				# Already locked, or cannot create lock
		}
	} continue {
		sleep($delay);				# Busy: wait
		$waited += $delay;

		# Warn them once after $wmin seconds and then every $wafter seconds
		if (
			$warn &&
				((!$lastwarn && $waited > $wmin) ||
				($waited - $lastwarn) > $wafter)
		) {
			my $waiting  = $lastwarn ? 'still waiting' : 'waiting';
			my $after  = $lastwarn ? 'after' : 'since';
			my $s = $waited == 1 ? '' : 's';
			&$wfunc("$waiting for $file lock $after $waited second$s");
			$lastwarn = $waited;
		}

		# While we wait, existing lockfile may become stale or too old
		$self->_acs_stale($file, $lockfile) if $self->stale;
		$self->_acs_check($file, $lockfile) if $self->hold;
	}

	umask($mask);
	return $locked;
}

sub _acs_unlock {	## private
	my $self = shift;
	my ($file, $format) = @_;		# Locked file, locking format
	my $stamp = $$;
	$stamp .= ':' . hostname if $self->nfs;

	# Compute locking file name -- hardwired default format is "%f.lock"
	my $lockfile = $file . $self->ext;
	$format = $self->format unless defined $format;
	$lockfile = $self->lockfile($file, $format) if defined $format;

	local *FILE;
	my $unlocked = 0;

	if (-f $lockfile) {
		open(FILE, $lockfile);
		my $l;
		chop($l = <FILE>);
		close FILE;
		if ($l eq $stamp) {			# Pid (plus hostname possibly) is OK
			$unlocked = 1;
			unless (unlink $lockfile) {
				$unlocked = 0;
				&{$self->efunc}("cannot unlock $file: $!");
			}
		} else {
			&{$self->efunc}("cannot unlock $file: lock not owned");
		}
	} else {
		&{$self->wfunc}("no lockfile found for $file");
	}

	return $unlocked;				# Did we successfully unlock?
}

sub _acs_check {
	my $self = shift;
	my ($file, $lockfile) = @_;

	my $mtime = (stat($lockfile))[9];
	return unless defined $mtime;	# Assume file does not exist
	my $hold = $self->hold;

	# If file too old to be considered stale?
	if ((time - $mtime) > $hold) {

		# RACE CONDITION -- shall we lock the lockfile?

		unless (unlink $lockfile) {
			&{$self->efunc}("cannot unlink $lockfile: $!");
			return;
		}

		if ($self->warn) {
			my $s = $hold == 1 ? '' : 's';
			&{$self->wfunc}("UNLOCKED $file (lock older than $hold second$s)");
		}
	}
}

sub _acs_stale {
	my $self = shift;
	my ($file, $lockfile) = @_;

	local *FILE;
	open(FILE, $lockfile) || return;
	my $stamp;
	chop($stamp = <FILE>);
	close FILE;

	my ($pid, $hostname);

	if ($self->nfs) {
		($pid, $hostname) = $stamp =~ /^(\d+):(\S+)/;
		my $local = hostname;
		return if $local ne $hostname;
		return if kill 0, $pid;
		$hostname = " on $hostname";
	} else {
		($pid) = $stamp =~ /^(\d+)$/;		# Untaint $pid for kill()
		$hostname = '';
		return if kill 0, $pid;
	}

	# RACE CONDITION -- shall we lock the lockfile?

	unless (unlink $lockfile) {
		&{$self->efunc}("cannot unlink stale $lockfile: $!");
		return;
	}

	&{$self->wfunc}("UNLOCKED $file (stale lock by PID $pid$hostname)");
}

1;



