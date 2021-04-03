
require 5;
package Pod::Simple::Methody;
use strict;
use Pod::Simple ();
use vars qw(@ISA $VERSION);
$VERSION = '3.28';
@ISA = ('Pod::Simple');


sub _handle_element_start {
  $_[1] =~ tr/-:./__/;
  ( $_[0]->can( 'start_' . $_[1] )
    || return
  )->(
    $_[0], $_[2]
  );
}

sub _handle_text {
  ( $_[0]->can( 'handle_text' )
    || return
  )->(
    @_
  );
}

sub _handle_element_end {
  $_[1] =~ tr/-:./__/;
  ( $_[0]->can( 'end_' . $_[1] )
    || return
  )->(
    $_[0], $_[2]
  );
}

1;


__END__

