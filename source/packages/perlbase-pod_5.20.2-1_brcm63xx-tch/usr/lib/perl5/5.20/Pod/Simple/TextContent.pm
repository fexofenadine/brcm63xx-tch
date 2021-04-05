

require 5;
package Pod::Simple::TextContent;
use strict;
use Carp ();
use Pod::Simple ();
use vars qw( @ISA $VERSION );
$VERSION = '3.28';
@ISA = ('Pod::Simple');

sub new {
  my $self = shift;
  my $new = $self->SUPER::new(@_);
  $new->{'output_fh'} ||= *STDOUT{IO};
  $new->nix_X_codes(1);
  return $new;
}


sub _handle_element_start {
  print {$_[0]{'output_fh'}} "\n"  unless $_[1] =~ m/^[A-Z]$/s;
  return;
}

sub _handle_text {
  if( chr(65) eq 'A' ) {     # in ASCIIworld
    $_[1] =~ tr/\xAD//d;
    $_[1] =~ tr/\xA0/ /;
  }
  print {$_[0]{'output_fh'}} $_[1];
  return;
}

sub _handle_element_end {
  print {$_[0]{'output_fh'}} "\n"  unless $_[1] =~ m/^[A-Z]$/s;
  return;
}

1;


__END__

