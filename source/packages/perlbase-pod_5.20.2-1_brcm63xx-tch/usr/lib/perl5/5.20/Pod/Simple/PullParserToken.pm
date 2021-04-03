
require 5;
package Pod::Simple::PullParserToken;
 # Base class for tokens gotten from Pod::Simple::PullParser's $parser->get_token
@ISA = ();
$VERSION = '3.28';
use strict;

sub new {  # Class->new('type', stuff...);  ## Overridden in derived classes anyway
  my $class = shift;
  return bless [@_], ref($class) || $class;
}

sub type { $_[0][0] }  # Can't change the type of an object
sub dump { Pod::Simple::pretty( [ @{ $_[0] } ] ) }

sub is_start { $_[0][0] eq 'start' }
sub is_end   { $_[0][0] eq 'end'   }
sub is_text  { $_[0][0] eq 'text'  }

1;
__END__

sub dump { '[' . _esc( @{ $_[0] } ) . ']' }


sub _esc {
  return '' unless @_;
  my @out;
  foreach my $in (@_) {
    push @out, '"' . $in . '"';
    $out[-1] =~ s/([^- \:\:\.\,\'\>\<\"\/\=\?\+\|\[\]\{\}\_a-zA-Z0-9_\`\~\!\#\%\^\&\*\(\)])/
      sprintf( (ord($1) < 256) ? "\\x%02X" : "\\x{%X}", ord($1))
    /eg;
  }
  return join ', ', @out;
}


__END__

