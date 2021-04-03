package Pod::Perldoc::BaseTo;
use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '3.23';

use Carp                  qw(croak carp);
use Config                qw(%Config);
use File::Spec::Functions qw(catfile);

sub is_pageable        { '' }
sub write_with_binmode {  1 }

sub output_extension   { 'txt' }  # override in subclass!



sub TRUE  () {1}
sub FALSE () {return}

BEGIN {
 *is_vms     = $^O eq 'VMS'      ? \&TRUE : \&FALSE unless defined &is_vms;
 *is_mswin32 = $^O eq 'MSWin32'  ? \&TRUE : \&FALSE unless defined &is_mswin32;
 *is_dos     = $^O eq 'dos'      ? \&TRUE : \&FALSE unless defined &is_dos;
 *is_os2     = $^O eq 'os2'      ? \&TRUE : \&FALSE unless defined &is_os2;
 *is_cygwin  = $^O eq 'cygwin'   ? \&TRUE : \&FALSE unless defined &is_cygwin;
 *is_linux   = $^O eq 'linux'    ? \&TRUE : \&FALSE unless defined &is_linux;
 *is_hpux    = $^O =~ m/hpux/    ? \&TRUE : \&FALSE unless defined &is_hpux;
 *is_openbsd = $^O =~ m/openbsd/ ? \&TRUE : \&FALSE unless defined &is_openbsd;
 *is_bitrig = $^O =~ m/bitrig/ ? \&TRUE : \&FALSE unless defined &is_bitrig;
}

sub _perldoc_elem {
  my($self, $name) = splice @_,0,2;
  if(@_) {
    $self->{$name} = $_[0];
  } else {
    $self->{$name};
  }
}

sub debugging {
	my( $self, @messages ) = @_;

    ( defined(&Pod::Perldoc::DEBUG) and &Pod::Perldoc::DEBUG() )
	}

sub debug {
	my( $self, @messages ) = @_;
	return unless $self->debugging;
	print STDERR map { "DEBUG $_" } @messages;
	}

sub warn {
	my( $self, @messages ) = @_;
	carp join "\n", @messages, '';
	}

sub die {
	my( $self, @messages ) = @_;
	croak join "\n", @messages, '';
	}

sub _get_path_components {
	my( $self ) = @_;

	my @paths = split /\Q$Config{path_sep}/, $ENV{PATH};

	return @paths;
	}

sub _find_executable_in_path {
	my( $self, $program ) = @_;

	my @found = ();
	foreach my $dir ( $self->_get_path_components ) {
		my $binary = catfile( $dir, $program );
		$self->debug( "Looking for $binary\n" );
		next unless -e $binary;
		unless( -x $binary ) {
			$self->warn( "Found $binary but it's not executable. Skipping.\n" );
			next;
			}
		$self->debug( "Found $binary\n" );
		push @found, $binary;
		}

	return @found;
	}

1;

__END__

