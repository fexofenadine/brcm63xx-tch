
require 5;
package Pod::Simple::PullParserTextToken;
use Pod::Simple::PullParserToken ();
use strict;
use vars qw(@ISA $VERSION);
@ISA = ('Pod::Simple::PullParserToken');
$VERSION = '3.28';

sub new {  # Class->new(text);
  my $class = shift;
  return bless ['text', @_], ref($class) || $class;
}


sub text { (@_ == 2) ? ($_[0][1] = $_[1]) : $_[0][1] }

sub text_r { \ $_[0][1] }

1;

__END__

