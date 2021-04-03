package Pod::Perldoc::ToPod;
use strict;
use warnings;
use parent qw(Pod::Perldoc::BaseTo);

use vars qw($VERSION);
$VERSION = '3.23';

sub is_pageable        { 1 }
sub write_with_binmode { 0 }
sub output_extension   { 'pod' }

sub new { return bless {}, ref($_[0]) || $_[0] }

sub parse_from_file {
  my( $self, $in, $outfh ) = @_;

  open(IN, "<", $in) or $self->die( "Can't read-open $in: $!\nAborting" );

  my $cut_mode = 1;

  # A hack for finding things between =foo and =cut, inclusive
  local $_;
  while (<IN>) {
    if(  m/^=(\w+)/s ) {
      if($cut_mode = ($1 eq 'cut')) {
        print $outfh "\n=cut\n\n";
         # Pass thru the =cut line with some harmless
         #  (and occasionally helpful) padding
      }
    }
    next if $cut_mode;
    print $outfh $_ or $self->die( "Can't print to $outfh: $!" );
  }

  close IN or $self->die( "Can't close $in: $!" );
  return;
}

1;
__END__


