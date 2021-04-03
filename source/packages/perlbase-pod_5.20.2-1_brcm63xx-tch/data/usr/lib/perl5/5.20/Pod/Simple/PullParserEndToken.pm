
require 5;
package Pod::Simple::PullParserEndToken;
use Pod::Simple::PullParserToken ();
use strict;
use vars qw(@ISA $VERSION);
@ISA = ('Pod::Simple::PullParserToken');
$VERSION = '3.28';

sub new {  # Class->new(tagname);
  my $class = shift;
  return bless ['end', @_], ref($class) || $class;
}


sub tagname { (@_ == 2) ? ($_[0][1] = $_[1]) : $_[0][1] }
sub tag { shift->tagname(@_) }

sub is_tagname { $_[0][1] eq $_[1] }
sub is_tag { shift->is_tagname(@_) }

1;


__END__

