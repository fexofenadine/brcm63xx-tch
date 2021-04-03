
require 5;
package Pod::Simple::XMLOutStream;
use strict;
use Carp ();
use Pod::Simple ();
use vars qw( $ATTR_PAD @ISA $VERSION $SORT_ATTRS);
$VERSION = '3.28';
BEGIN {
  @ISA = ('Pod::Simple');
  *DEBUG = \&Pod::Simple::DEBUG unless defined &DEBUG;
}

$ATTR_PAD = "\n" unless defined $ATTR_PAD;
 # Don't mess with this unless you know what you're doing.

$SORT_ATTRS = 0 unless defined $SORT_ATTRS;

sub new {
  my $self = shift;
  my $new = $self->SUPER::new(@_);
  $new->{'output_fh'} ||= *STDOUT{IO};
  $new->keep_encoding_directive(1);
  #$new->accept_codes('VerbatimFormatted');
  return $new;
}


sub _handle_element_start {
  # ($self, $element_name, $attr_hash_r)
  my $fh = $_[0]{'output_fh'};
  my($key, $value);
  DEBUG and print "++ $_[1]\n";
  print $fh "<", $_[1];
  if($SORT_ATTRS) {
    foreach my $key (sort keys %{$_[2]}) {
      unless($key =~ m/^~/s) {
        next if $key eq 'start_line' and $_[0]{'hide_line_numbers'};
        _xml_escape($value = $_[2]{$key});
        print $fh $ATTR_PAD, $key, '="', $value, '"';
      }
    }
  } else { # faster
    while(($key,$value) = each %{$_[2]}) {
      unless($key =~ m/^~/s) {
        next if $key eq 'start_line' and $_[0]{'hide_line_numbers'};
        _xml_escape($value);
        print $fh $ATTR_PAD, $key, '="', $value, '"';
      }
    }
  }
  print $fh ">";
  return;
}

sub _handle_text {
  DEBUG and print "== \"$_[1]\"\n";
  if(length $_[1]) {
    my $text = $_[1];
    _xml_escape($text);
    print {$_[0]{'output_fh'}} $text;
  }
  return;
}

sub _handle_element_end {
  DEBUG and print "-- $_[1]\n";
  print {$_[0]{'output_fh'}} "</", $_[1], ">";
  return;
}


sub _xml_escape {
  foreach my $x (@_) {
    # Escape things very cautiously:
    $x =~ s/([^-\n\t !\#\$\%\(\)\*\+,\.\~\/\:\;=\?\@\[\\\]\^_\`\{\|\}abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789])/'&#'.(ord($1)).';'/eg;
    # Yes, stipulate the list without a range, so that this can work right on
    #  all charsets that this module happens to run under.
    # Altho, hmm, what about that ord?  Presumably that won't work right
    #  under non-ASCII charsets.  Something should be done about that.
  }
  return;
}

1;

__END__

