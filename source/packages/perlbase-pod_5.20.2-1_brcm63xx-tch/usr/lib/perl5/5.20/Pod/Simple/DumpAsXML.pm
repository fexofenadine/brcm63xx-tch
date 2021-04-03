
require 5;
package Pod::Simple::DumpAsXML;
$VERSION = '3.28';
use Pod::Simple ();
BEGIN {@ISA = ('Pod::Simple')}

use strict;

use Carp ();
use Text::Wrap qw(wrap);

BEGIN { *DEBUG = \&Pod::Simple::DEBUG unless defined &DEBUG }

sub new {
  my $self = shift;
  my $new = $self->SUPER::new(@_);
  $new->{'output_fh'} ||= *STDOUT{IO};
  $new->accept_codes('VerbatimFormatted');
  $new->keep_encoding_directive(1);
  return $new;
}


sub _handle_element_start {
  # ($self, $element_name, $attr_hash_r)
  my $fh = $_[0]{'output_fh'};
  my($key, $value);
  DEBUG and print "++ $_[1]\n";
  
  print $fh   '  ' x ($_[0]{'indent'} || 0),  "<", $_[1];

  foreach my $key (sort keys %{$_[2]}) {
    unless($key =~ m/^~/s) {
      next if $key eq 'start_line' and $_[0]{'hide_line_numbers'};
      _xml_escape($value = $_[2]{$key});
      print $fh ' ', $key, '="', $value, '"';
    }
  }


  print $fh ">\n";
  $_[0]{'indent'}++;
  return;
}

sub _handle_text {
  DEBUG and print "== \"$_[1]\"\n";
  if(length $_[1]) {
    my $indent = '  ' x $_[0]{'indent'};
    my $text = $_[1];
    _xml_escape($text);
    local $Text::Wrap::huge = 'overflow';
    $text = wrap('', $indent, $text);
    print {$_[0]{'output_fh'}} $indent, $text, "\n";
  }
  return;
}

sub _handle_element_end {
  DEBUG and print "-- $_[1]\n";
  print {$_[0]{'output_fh'}}
   '  ' x --$_[0]{'indent'}, "</", $_[1], ">\n";
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

