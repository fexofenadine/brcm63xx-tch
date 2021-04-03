package Pod::Perldoc::ToRtf;
use strict;
use warnings;
use parent qw( Pod::Simple::RTF );

use vars qw($VERSION);
$VERSION = '3.23';

sub is_pageable        { 0 }
sub write_with_binmode { 0 }
sub output_extension   { 'rtf' }

sub page_for_perldoc {
  my($self, $tempfile, $perldoc) = @_;
  return unless $perldoc->IS_MSWin32;

  my $rtf_pager = $ENV{'RTFREADER'} || 'write.exe';

  $perldoc->aside( "About to launch <\"$rtf_pager\" \"$tempfile\">\n" );

  return 1 if system( qq{"$rtf_pager"}, qq{"$tempfile"} ) == 0;
  return 0;
}

1;
__END__


