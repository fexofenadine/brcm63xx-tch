
require 5;
package Pod::Simple::PullParserStartToken;
use Pod::Simple::PullParserToken ();
use strict;
use vars qw(@ISA $VERSION);
@ISA = ('Pod::Simple::PullParserToken');
$VERSION = '3.28';

sub new {  # Class->new(tagname, optional_attrhash);
  my $class = shift;
  return bless ['start', @_], ref($class) || $class;
}


sub tagname   { (@_ == 2) ? ($_[0][1] = $_[1]) : $_[0][1] }
sub tag { shift->tagname(@_) }

sub is_tagname { $_[0][1] eq $_[1] }
sub is_tag { shift->is_tagname(@_) }


sub attr_hash { $_[0][2] ||= {} }

sub attr      {
  if(@_ == 2) {      # Reading: $token->attr('attrname')
    ${$_[0][2] || return undef}{ $_[1] };
  } elsif(@_ > 2) {  # Writing: $token->attr('attrname', 'newval')
    ${$_[0][2] ||= {}}{ $_[1] } = $_[2];
  } else {
    require Carp;
    Carp::croak(
      'usage: $object->attr("val") or $object->attr("key", "newval")');
    return undef;
  }
}

1;


__END__

