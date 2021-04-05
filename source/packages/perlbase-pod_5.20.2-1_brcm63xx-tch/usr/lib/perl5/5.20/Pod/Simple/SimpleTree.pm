

require 5;
package Pod::Simple::SimpleTree;
use strict;
use Carp ();
use Pod::Simple ();
use vars qw( $ATTR_PAD @ISA $VERSION $SORT_ATTRS);
$VERSION = '3.28';
BEGIN {
  @ISA = ('Pod::Simple');
  *DEBUG = \&Pod::Simple::DEBUG unless defined &DEBUG;
}

__PACKAGE__->_accessorize(
  'root',   # root of the tree
);


sub _handle_element_start { # self, tagname, attrhash
  DEBUG > 2 and print "Handling $_[1] start-event\n";
  my $x = [$_[1], $_[2]];
  if($_[0]{'_currpos'}) {
    push    @{ $_[0]{'_currpos'}[0] }, $x; # insert in parent's child-list
    unshift @{ $_[0]{'_currpos'} },    $x; # prefix to stack
  } else {
    DEBUG and print " And oo, it gets to be root!\n";
    $_[0]{'_currpos'} = [   $_[0]{'root'} = $x   ];
      # first event!  set to stack, and set as root.
  }
  DEBUG > 3 and print "Stack is now: ",
    join(">", map $_->[0], @{$_[0]{'_currpos'}}), "\n";
  return;
}

sub _handle_element_end { # self, tagname
  DEBUG > 2 and print "Handling $_[1] end-event\n";
  shift @{$_[0]{'_currpos'}};
  DEBUG > 3 and print "Stack is now: ",
    join(">", map $_->[0], @{$_[0]{'_currpos'}}), "\n";
  return;
}

sub _handle_text { # self, text
  DEBUG > 2 and print "Handling $_[1] text-event\n";
  push @{ $_[0]{'_currpos'}[0] }, $_[1];
  return;
}


sub _traverse_treelet_bit {
  DEBUG > 2 and print "Handling $_[1] paragraph event\n";
  my $self = shift;
  push @{ $self->{'_currpos'}[0] }, [@_];
  return;
}
1;
__END__

