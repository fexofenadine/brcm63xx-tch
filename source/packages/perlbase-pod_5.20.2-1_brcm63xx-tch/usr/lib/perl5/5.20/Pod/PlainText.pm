

package Pod::PlainText;
use strict;

require 5.005;

use Carp qw(carp croak);
use Pod::Select ();

use vars qw(@ISA %ESCAPES $VERSION);

@ISA = qw(Pod::Select);

$VERSION = '2.07';

BEGIN {
   if ($] < 5.006) {
      require Symbol;
      import Symbol;
   }
}


%ESCAPES = (
    'amp'       =>    '&',      # ampersand
    'lt'        =>    '<',      # left chevron, less-than
    'gt'        =>    '>',      # right chevron, greater-than
    'quot'      =>    '"',      # double quote

    "Aacute"    =>    "\xC1",   # capital A, acute accent
    "aacute"    =>    "\xE1",   # small a, acute accent
    "Acirc"     =>    "\xC2",   # capital A, circumflex accent
    "acirc"     =>    "\xE2",   # small a, circumflex accent
    "AElig"     =>    "\xC6",   # capital AE diphthong (ligature)
    "aelig"     =>    "\xE6",   # small ae diphthong (ligature)
    "Agrave"    =>    "\xC0",   # capital A, grave accent
    "agrave"    =>    "\xE0",   # small a, grave accent
    "Aring"     =>    "\xC5",   # capital A, ring
    "aring"     =>    "\xE5",   # small a, ring
    "Atilde"    =>    "\xC3",   # capital A, tilde
    "atilde"    =>    "\xE3",   # small a, tilde
    "Auml"      =>    "\xC4",   # capital A, dieresis or umlaut mark
    "auml"      =>    "\xE4",   # small a, dieresis or umlaut mark
    "Ccedil"    =>    "\xC7",   # capital C, cedilla
    "ccedil"    =>    "\xE7",   # small c, cedilla
    "Eacute"    =>    "\xC9",   # capital E, acute accent
    "eacute"    =>    "\xE9",   # small e, acute accent
    "Ecirc"     =>    "\xCA",   # capital E, circumflex accent
    "ecirc"     =>    "\xEA",   # small e, circumflex accent
    "Egrave"    =>    "\xC8",   # capital E, grave accent
    "egrave"    =>    "\xE8",   # small e, grave accent
    "ETH"       =>    "\xD0",   # capital Eth, Icelandic
    "eth"       =>    "\xF0",   # small eth, Icelandic
    "Euml"      =>    "\xCB",   # capital E, dieresis or umlaut mark
    "euml"      =>    "\xEB",   # small e, dieresis or umlaut mark
    "Iacute"    =>    "\xCD",   # capital I, acute accent
    "iacute"    =>    "\xED",   # small i, acute accent
    "Icirc"     =>    "\xCE",   # capital I, circumflex accent
    "icirc"     =>    "\xEE",   # small i, circumflex accent
    "Igrave"    =>    "\xCD",   # capital I, grave accent
    "igrave"    =>    "\xED",   # small i, grave accent
    "Iuml"      =>    "\xCF",   # capital I, dieresis or umlaut mark
    "iuml"      =>    "\xEF",   # small i, dieresis or umlaut mark
    "Ntilde"    =>    "\xD1",   # capital N, tilde
    "ntilde"    =>    "\xF1",   # small n, tilde
    "Oacute"    =>    "\xD3",   # capital O, acute accent
    "oacute"    =>    "\xF3",   # small o, acute accent
    "Ocirc"     =>    "\xD4",   # capital O, circumflex accent
    "ocirc"     =>    "\xF4",   # small o, circumflex accent
    "Ograve"    =>    "\xD2",   # capital O, grave accent
    "ograve"    =>    "\xF2",   # small o, grave accent
    "Oslash"    =>    "\xD8",   # capital O, slash
    "oslash"    =>    "\xF8",   # small o, slash
    "Otilde"    =>    "\xD5",   # capital O, tilde
    "otilde"    =>    "\xF5",   # small o, tilde
    "Ouml"      =>    "\xD6",   # capital O, dieresis or umlaut mark
    "ouml"      =>    "\xF6",   # small o, dieresis or umlaut mark
    "szlig"     =>    "\xDF",   # small sharp s, German (sz ligature)
    "THORN"     =>    "\xDE",   # capital THORN, Icelandic
    "thorn"     =>    "\xFE",   # small thorn, Icelandic
    "Uacute"    =>    "\xDA",   # capital U, acute accent
    "uacute"    =>    "\xFA",   # small u, acute accent
    "Ucirc"     =>    "\xDB",   # capital U, circumflex accent
    "ucirc"     =>    "\xFB",   # small u, circumflex accent
    "Ugrave"    =>    "\xD9",   # capital U, grave accent
    "ugrave"    =>    "\xF9",   # small u, grave accent
    "Uuml"      =>    "\xDC",   # capital U, dieresis or umlaut mark
    "uuml"      =>    "\xFC",   # small u, dieresis or umlaut mark
    "Yacute"    =>    "\xDD",   # capital Y, acute accent
    "yacute"    =>    "\xFD",   # small y, acute accent
    "yuml"      =>    "\xFF",   # small y, dieresis or umlaut mark

    "lchevron"  =>    "\xAB",   # left chevron (double less than)
    "rchevron"  =>    "\xBB",   # right chevron (double greater than)
);



sub initialize {
    my $self = shift;

    $$self{alt}      = 0  unless defined $$self{alt};
    $$self{indent}   = 4  unless defined $$self{indent};
    $$self{loose}    = 0  unless defined $$self{loose};
    $$self{sentence} = 0  unless defined $$self{sentence};
    $$self{width}    = 76 unless defined $$self{width};

    $$self{INDENTS}  = [];              # Stack of indentations.
    $$self{MARGIN}   = $$self{indent};  # Current left margin in spaces.

    return $self->SUPER::initialize;
}



sub command {
    my $self = shift;
    my $command = shift;
    return if $command eq 'pod';
    return if ($$self{EXCLUDE} && $command ne 'end');
    if (defined $$self{ITEM}) {
      $self->item ("\n");
      local $_ = "\n";
      $self->output($_) if($command eq 'back');
    }
    $command = 'cmd_' . $command;
    return $self->$command (@_);
}

sub verbatim {
    my $self = shift;
    return if $$self{EXCLUDE};
    $self->item if defined $$self{ITEM};
    local $_ = shift;
    return if /^\s*$/;
    s/^(\s*\S+)/(' ' x $$self{MARGIN}) . $1/gme;
    return $self->output($_);
}

sub textblock {
    my $self = shift;
    return if $$self{EXCLUDE};
    if($$self{VERBATIM}) {
      $self->output($_[0]);
      return;
    }
    local $_ = shift;
    my $line = shift;

    # Perform a little magic to collapse multiple L<> references.  This is
    # here mostly for backwards-compatibility.  We'll just rewrite the whole
    # thing into actual text at this part, bypassing the whole internal
    # sequence parsing thing.
    s{
        (
          L<                    # A link of the form L</something>.
              /
              (
                  [:\w]+        # The item has to be a simple word...
                  (\(\))?       # ...or simple function.
              )
          >
          (
              ,?\s+(and\s+)?    # Allow lots of them, conjuncted.
              L<  
                  /
                  (
                      [:\w]+
                      (\(\))?
                  )
              >
          )+
        )
    } {
        local $_ = $1;
        s%L</([^>]+)>%$1%g;
        my @items = split /(?:,?\s+(?:and\s+)?)/;
        my $string = "the ";
        my $i;
        for ($i = 0; $i < @items; $i++) {
            $string .= $items[$i];
            $string .= ", " if @items > 2 && $i != $#items;
            $string .= " and " if ($i == $#items - 1);
        }
        $string .= " entries elsewhere in this document";
        $string;
    }gex;

    # Now actually interpolate and output the paragraph.
    $_ = $self->interpolate ($_, $line);
    s/\s*$/\n/s;
    if (defined $$self{ITEM}) {
        $self->item ($_ . "\n");
    } else {
        $self->output ($self->reformat ($_ . "\n"));
    }
}

sub interior_sequence {
    my $self = shift;
    my $command = shift;
    local $_ = shift;
    return '' if ($command eq 'X' || $command eq 'Z');

    # Expand escapes into the actual character now, carping if invalid.
    if ($command eq 'E') {
        return $ESCAPES{$_} if defined $ESCAPES{$_};
        carp "Unknown escape: E<$_>";
        return "E<$_>";
    }

    # For all the other sequences, empty content produces no output.
    return if $_ eq '';

    # For S<>, compress all internal whitespace and then map spaces to \01.
    # When we output the text, we'll map this back.
    if ($command eq 'S') {
        s/\s{2,}/ /g;
        tr/ /\01/;
        return $_;
    }

    # Anything else needs to get dispatched to another method.
    if    ($command eq 'B') { return $self->seq_b ($_) }
    elsif ($command eq 'C') { return $self->seq_c ($_) }
    elsif ($command eq 'F') { return $self->seq_f ($_) }
    elsif ($command eq 'I') { return $self->seq_i ($_) }
    elsif ($command eq 'L') { return $self->seq_l ($_) }
    else { carp "Unknown sequence $command<$_>" }
}

sub preprocess_paragraph {
    my $self = shift;
    local $_ = shift;
    1 while s/^(.*?)(\t+)/$1 . ' ' x (length ($2) * 8 - length ($1) % 8)/me;
    return $_;
}




sub cmd_head1 {
    my $self = shift;
    local $_ = shift;
    s/\s+$//s;
    $_ = $self->interpolate ($_, shift);
    if ($$self{alt}) {
        $self->output ("\n==== $_ ====\n\n");
    } else {
        $_ .= "\n" if $$self{loose};
        $self->output ($_ . "\n");
    }
}

sub cmd_head2 {
    my $self = shift;
    local $_ = shift;
    s/\s+$//s;
    $_ = $self->interpolate ($_, shift);
    if ($$self{alt}) {
        $self->output ("\n==   $_   ==\n\n");
    } else {
        $_ .= "\n" if $$self{loose};
        $self->output (' ' x ($$self{indent} / 2) . $_ . "\n");
    }
}

sub cmd_head3 {
    my $self = shift;
    local $_ = shift;
    s/\s+$//s;
    $_ = $self->interpolate ($_, shift);
    if ($$self{alt}) {
        $self->output ("\n= $_ =\n");
    } else {
        $_ .= "\n" if $$self{loose};
        $self->output (' ' x ($$self{indent}) . $_ . "\n");
    }
}

*cmd_head4 = \&cmd_head3;

sub cmd_over {
    my $self = shift;
    local $_ = shift;
    unless (/^[-+]?\d+\s+$/) { $_ = $$self{indent} }
    push (@{ $$self{INDENTS} }, $$self{MARGIN});
    $$self{MARGIN} += ($_ + 0);
}

sub cmd_back {
    my $self = shift;
    $$self{MARGIN} = pop @{ $$self{INDENTS} };
    unless (defined $$self{MARGIN}) {
        carp 'Unmatched =back';
        $$self{MARGIN} = $$self{indent};
    }
}

sub cmd_item {
    my $self = shift;
    if (defined $$self{ITEM}) { $self->item }
    local $_ = shift;
    s/\s+$//s;
    $$self{ITEM} = $self->interpolate ($_);
}

sub cmd_begin {
    my $self = shift;
    local $_ = shift;
    my ($kind) = /^(\S+)/ or return;
    if ($kind eq 'text') {
        $$self{VERBATIM} = 1;
    } else {
        $$self{EXCLUDE} = 1;
    }
}

sub cmd_end {
    my $self = shift;
    $$self{EXCLUDE} = 0;
    $$self{VERBATIM} = 0;
}

sub cmd_for {
    my $self = shift;
    local $_ = shift;
    my $line = shift;
    return unless s/^text\b[ \t]*\r?\n?//;
    $self->verbatim ($_, $line);
}

sub cmd_encoding {
  return;
}


sub seq_b { return $_[0]{alt} ? "``$_[1]''" : $_[1] }
sub seq_c { return $_[0]{alt} ? "``$_[1]''" : "`$_[1]'" }
sub seq_f { return $_[0]{alt} ? "\"$_[1]\"" : $_[1] }
sub seq_i { return '*' . $_[1] . '*' }

sub seq_l {
    my $self = shift;
    local $_ = shift;

    # Smash whitespace in case we were split across multiple lines.
    s/\s+/ /g;

    # If we were given any explicit text, just output it.
    if (/^([^|]+)\|/) { return $1 }

    # Okay, leading and trailing whitespace isn't important; get rid of it.
    s/^\s+//;
    s/\s+$//;

    # Default to using the whole content of the link entry as a section
    # name.  Note that L<manpage/> forces a manpage interpretation, as does
    # something looking like L<manpage(section)>.  The latter is an
    # enhancement over the original Pod::Text.
    my ($manpage, $section) = ('', $_);
    if (/^(?:https?|ftp|news):/) {
        # a URL
        return $_;
    } elsif (/^"\s*(.*?)\s*"$/) {
        $section = '"' . $1 . '"';
    } elsif (m/^[-:.\w]+(?:\(\S+\))?$/) {
        ($manpage, $section) = ($_, '');
    } elsif (m{/}) {
        ($manpage, $section) = split (/\s*\/\s*/, $_, 2);
    }

    my $text = '';
    # Now build the actual output text.
    if (!length $section) {
        $text = "the $manpage manpage" if length $manpage;
    } elsif ($section =~ /^[:\w]+(?:\(\))?/) {
        $text .= 'the ' . $section . ' entry';
        $text .= (length $manpage) ? " in the $manpage manpage"
                                   : ' elsewhere in this document';
    } else {
        $section =~ s/^\"\s*//;
        $section =~ s/\s*\"$//;
        $text .= 'the section on "' . $section . '"';
        $text .= " in the $manpage manpage" if length $manpage;
    }
    return $text;
}



sub item {
    my $self = shift;
    local $_ = shift;
    my $tag = $$self{ITEM};
    unless (defined $tag) {
        carp 'item called without tag';
        return;
    }
    undef $$self{ITEM};
    my $indent = $$self{INDENTS}[-1];
    unless (defined $indent) { $indent = $$self{indent} }
    my $space = ' ' x $indent;
    $space =~ s/^ /:/ if $$self{alt};
    if (!$_ || /^\s+$/ || ($$self{MARGIN} - $indent < length ($tag) + 1)) {
        my $margin = $$self{MARGIN};
        $$self{MARGIN} = $indent;
        my $output = $self->reformat ($tag);
        $output =~ s/[\r\n]*$/\n/;
        $self->output ($output);
        $$self{MARGIN} = $margin;
        $self->output ($self->reformat ($_)) if /\S/;
    } else {
        $_ = $self->reformat ($_);
        s/^ /:/ if ($$self{alt} && $indent > 0);
        my $tagspace = ' ' x length $tag;
        s/^($space)$tagspace/$1$tag/ or carp 'Bizarre space in item';
        $self->output ($_);
    }
}



sub wrap {
    my $self = shift;
    local $_ = shift;
    my $output = '';
    my $spaces = ' ' x $$self{MARGIN};
    my $width = $$self{width} - $$self{MARGIN};
    while (length > $width) {
        if (s/^([^\r\n]{0,$width})\s+// || s/^([^\r\n]{$width})//) {
            $output .= $spaces . $1 . "\n";
        } else {
            last;
        }
    }
    $output .= $spaces . $_;
    $output =~ s/\s+$/\n\n/;
    return $output;
}

sub reformat {
    my $self = shift;
    local $_ = shift;

    # If we're trying to preserve two spaces after sentences, do some
    # munging to support that.  Otherwise, smash all repeated whitespace.
    if ($$self{sentence}) {
        s/ +$//mg;
        s/\.\r?\n/. \n/g;
        s/[\r\n]+/ /g;
        s/   +/  /g;
    } else {
        s/\s+/ /g;
    }
    return $self->wrap($_);
}

sub output { $_[1] =~ tr/\01/ /; print { $_[0]->output_handle } $_[1] }



sub pod2text {
    my @args;

    # This is really ugly; I hate doing option parsing in the middle of a
    # module.  But the old Pod::Text module supported passing flags to its
    # entry function, so handle -a and -<number>.
    while ($_[0] =~ /^-/) {
        my $flag = shift;
        if    ($flag eq '-a')       { push (@args, alt => 1)    }
        elsif ($flag =~ /^-(\d+)$/) { push (@args, width => $1) }
        else {
            unshift (@_, $flag);
            last;
        }
    }

    # Now that we know what arguments we're using, create the parser.
    my $parser = Pod::PlainText->new (@args);

    # If two arguments were given, the second argument is going to be a file
    # handle.  That means we want to call parse_from_filehandle(), which
    # means we need to turn the first argument into a file handle.  Magic
    # open will handle the <&STDIN case automagically.
    if (defined $_[1]) {
        my $infh;
        if ($] < 5.006) {
          $infh = gensym();
        }
        unless (open ($infh, $_[0])) {
            croak ("Can't open $_[0] for reading: $!\n");
        }
        $_[0] = $infh;
        return $parser->parse_from_filehandle (@_);
    } else {
        return $parser->parse_from_file (@_);
    }
}



1;
__END__

