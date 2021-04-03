

package Pod::Man;

require 5.005;

use strict;
use subs qw(makespace);
use vars qw(@ISA %ESCAPES $PREAMBLE $VERSION);

use Carp qw(croak);
use Encode qw(encode);
use Pod::Simple ();

@ISA = qw(Pod::Simple);

$VERSION = '2.28';

BEGIN {
    my $parent = defined (&Pod::Simple::DEBUG) ? \&Pod::Simple::DEBUG : undef;
    unless (defined &DEBUG) {
        *DEBUG = $parent || sub () { 10 };
    }
}

BEGIN { *ASCII = \&Pod::Simple::ASCII }

BEGIN { *pretty = \&Pod::Simple::pretty }

my %FORMATTING = (
    DEFAULT  => { cleanup => 1, convert => 1, guesswork => 1, literal => 0 },
    Data     => { cleanup => 0, convert => 0, guesswork => 0, literal => 0 },
    Verbatim => {                             guesswork => 0, literal => 1 },
    C        => {                             guesswork => 0, literal => 1 },
    X        => { cleanup => 0,               guesswork => 0               },
);


sub new {
    my $class = shift;
    my $self = $class->SUPER::new;

    # Tell Pod::Simple not to handle S<> by automatically inserting &nbsp;.
    $self->nbsp_for_S (1);

    # Tell Pod::Simple to keep whitespace whenever possible.
    if (my $preserve_whitespace = $self->can ('preserve_whitespace')) {
        $self->$preserve_whitespace (1);
    } else {
        $self->fullstop_space_harden (1);
    }

    # The =for and =begin targets that we accept.
    $self->accept_targets (qw/man MAN roff ROFF/);

    # Ensure that contiguous blocks of code are merged together.  Otherwise,
    # some of the guesswork heuristics don't work right.
    $self->merge_text (1);

    # Pod::Simple doesn't do anything useful with our arguments, but we want
    # to put them in our object as hash keys and values.  This could cause
    # problems if we ever clash with Pod::Simple's own internal class
    # variables.
    %$self = (%$self, @_);

    # Send errors to stderr if requested.
    if ($$self{stderr} and not $$self{errors}) {
        $$self{errors} = 'stderr';
    }
    delete $$self{stderr};

    # Validate the errors parameter and act on it.
    if (not defined $$self{errors}) {
        $$self{errors} = 'pod';
    }
    if ($$self{errors} eq 'stderr' || $$self{errors} eq 'die') {
        $self->no_errata_section (1);
        $self->complain_stderr (1);
        if ($$self{errors} eq 'die') {
            $$self{complain_die} = 1;
        }
    } elsif ($$self{errors} eq 'pod') {
        $self->no_errata_section (0);
        $self->complain_stderr (0);
    } elsif ($$self{errors} eq 'none') {
        $self->no_whining (1);
    } else {
        croak (qq(Invalid errors setting: "$$self{errors}"));
    }
    delete $$self{errors};

    # Initialize various other internal constants based on our arguments.
    $self->init_fonts;
    $self->init_quotes;
    $self->init_page;

    # For right now, default to turning on all of the magic.
    $$self{MAGIC_CPP}       = 1;
    $$self{MAGIC_EMDASH}    = 1;
    $$self{MAGIC_FUNC}      = 1;
    $$self{MAGIC_MANREF}    = 1;
    $$self{MAGIC_SMALLCAPS} = 1;
    $$self{MAGIC_VARS}      = 1;

    return $self;
}

sub toescape { (length ($_[0]) > 1 ? '\f(' : '\f') . $_[0] }

sub init_fonts {
    my ($self) = @_;

    # Figure out the fixed-width font.  If user-supplied, make sure that they
    # are the right length.
    for (qw/fixed fixedbold fixeditalic fixedbolditalic/) {
        my $font = $$self{$_};
        if (defined ($font) && (length ($font) < 1 || length ($font) > 2)) {
            croak qq(roff font should be 1 or 2 chars, not "$font");
        }
    }

    # Set the default fonts.  We can't be sure portably across different
    # implementations what fixed bold-italic may be called (if it's even
    # available), so default to just bold.
    $$self{fixed}           ||= 'CW';
    $$self{fixedbold}       ||= 'CB';
    $$self{fixeditalic}     ||= 'CI';
    $$self{fixedbolditalic} ||= 'CB';

    # Set up a table of font escapes.  First number is fixed-width, second is
    # bold, third is italic.
    $$self{FONTS} = { '000' => '\fR', '001' => '\fI',
                      '010' => '\fB', '011' => '\f(BI',
                      '100' => toescape ($$self{fixed}),
                      '101' => toescape ($$self{fixeditalic}),
                      '110' => toescape ($$self{fixedbold}),
                      '111' => toescape ($$self{fixedbolditalic}) };
}

sub init_quotes {
    my ($self) = (@_);

    $$self{quotes} ||= '"';
    if ($$self{quotes} eq 'none') {
        $$self{LQUOTE} = $$self{RQUOTE} = '';
    } elsif (length ($$self{quotes}) == 1) {
        $$self{LQUOTE} = $$self{RQUOTE} = $$self{quotes};
    } elsif ($$self{quotes} =~ /^(.)(.)$/
             || $$self{quotes} =~ /^(..)(..)$/) {
        $$self{LQUOTE} = $1;
        $$self{RQUOTE} = $2;
    } else {
        croak(qq(Invalid quote specification "$$self{quotes}"))
    }

    # Double the first quote; note that this should not be s///g as two double
    # quotes is represented in *roff as three double quotes, not four.  Weird,
    # I know.
    $$self{LQUOTE} =~ s/\"/\"\"/;
    $$self{RQUOTE} =~ s/\"/\"\"/;
}

sub init_page {
    my ($self) = @_;

    # We used to try first to get the version number from a local binary, but
    # we shouldn't need that any more.  Get the version from the running Perl.
    # Work a little magic to handle subversions correctly under both the
    # pre-5.6 and the post-5.6 version numbering schemes.
    my @version = ($] =~ /^(\d+)\.(\d{3})(\d{0,3})$/);
    $version[2] ||= 0;
    $version[2] *= 10 ** (3 - length $version[2]);
    for (@version) { $_ += 0 }
    my $version = join ('.', @version);

    # Set the defaults for page titles and indentation if the user didn't
    # override anything.
    $$self{center} = 'User Contributed Perl Documentation'
        unless defined $$self{center};
    $$self{release} = 'perl v' . $version
        unless defined $$self{release};
    $$self{indent} = 4
        unless defined $$self{indent};

    # Double quotes in things that will be quoted.
    for (qw/center release/) {
        $$self{$_} =~ s/\"/\"\"/g if $$self{$_};
    }
}



sub _handle_text {
    my ($self, $text) = @_;
    DEBUG > 3 and print "== $text\n";
    my $tag = $$self{PENDING}[-1];
    $$tag[2] .= $self->format_text ($$tag[1], $text);
}

sub method_for_element {
    my ($self, $element) = @_;
    $element =~ tr/A-Z-/a-z_/;
    $element =~ tr/_a-z0-9//cd;
    return $element;
}

sub _handle_element_start {
    my ($self, $element, $attrs) = @_;
    DEBUG > 3 and print "++ $element (<", join ('> <', %$attrs), ">)\n";
    my $method = $self->method_for_element ($element);

    # If we have a command handler, we need to accumulate the contents of the
    # tag before calling it.  Turn off IN_NAME for any command other than
    # <Para> and the formatting codes so that IN_NAME isn't still set for the
    # first heading after the NAME heading.
    if ($self->can ("cmd_$method")) {
        DEBUG > 2 and print "<$element> starts saving a tag\n";
        $$self{IN_NAME} = 0 if ($element ne 'Para' && length ($element) > 1);

        # How we're going to format embedded text blocks depends on the tag
        # and also depends on our parent tags.  Thankfully, inside tags that
        # turn off guesswork and reformatting, nothing else can turn it back
        # on, so this can be strictly inherited.
        my $formatting = {
            %{ $$self{PENDING}[-1][1] || $FORMATTING{DEFAULT} },
            %{ $FORMATTING{$element} || {} },
        };
        push (@{ $$self{PENDING} }, [ $attrs, $formatting, '' ]);
        DEBUG > 4 and print "Pending: [", pretty ($$self{PENDING}), "]\n";
    } elsif (my $start_method = $self->can ("start_$method")) {
        $self->$start_method ($attrs, '');
    } else {
        DEBUG > 2 and print "No $method start method, skipping\n";
    }
}

sub _handle_element_end {
    my ($self, $element) = @_;
    DEBUG > 3 and print "-- $element\n";
    my $method = $self->method_for_element ($element);

    # If we have a command handler, pull off the pending text and pass it to
    # the handler along with the saved attribute hash.
    if (my $cmd_method = $self->can ("cmd_$method")) {
        DEBUG > 2 and print "</$element> stops saving a tag\n";
        my $tag = pop @{ $$self{PENDING} };
        DEBUG > 4 and print "Popped: [", pretty ($tag), "]\n";
        DEBUG > 4 and print "Pending: [", pretty ($$self{PENDING}), "]\n";
        my $text = $self->$cmd_method ($$tag[0], $$tag[2]);
        if (defined $text) {
            if (@{ $$self{PENDING} } > 1) {
                $$self{PENDING}[-1][2] .= $text;
            } else {
                $self->output ($text);
            }
        }
    } elsif (my $end_method = $self->can ("end_$method")) {
        $self->$end_method ();
    } else {
        DEBUG > 2 and print "No $method end method, skipping\n";
    }
}


sub format_text {
    my ($self, $options, $text) = @_;
    my $guesswork = $$options{guesswork} && !$$self{IN_NAME};
    my $cleanup = $$options{cleanup};
    my $convert = $$options{convert};
    my $literal = $$options{literal};

    # Cleanup just tidies up a few things, telling *roff that the hyphens are
    # hard, putting a bit of space between consecutive underscores, and
    # escaping backslashes.  Be careful not to mangle our character
    # translations by doing this before processing character translation.
    if ($cleanup) {
        $text =~ s/\\/\\e/g;
        $text =~ s/-/\\-/g;
        $text =~ s/_(?=_)/_\\|/g;
    }

    # Normally we do character translation, but we won't even do that in
    # <Data> blocks or if UTF-8 output is desired.
    if ($convert && !$$self{utf8} && ASCII) {
        $text =~ s/([^\x00-\x7F])/$ESCAPES{ord ($1)} || "X"/eg;
    }

    # Ensure that *roff doesn't convert literal quotes to UTF-8 single quotes,
    # but don't mess up our accept escapes.
    if ($literal) {
        $text =~ s/(?<!\\\*)\'/\\*\(Aq/g;
        $text =~ s/(?<!\\\*)\`/\\\`/g;
    }

    # If guesswork is asked for, do that.  This involves more substantial
    # formatting based on various heuristics that may only be appropriate for
    # particular documents.
    if ($guesswork) {
        $text = $self->guesswork ($text);
    }

    return $text;
}

sub quote_literal {
    my $self = shift;
    local $_ = shift;

    # A regex that matches the portion of a variable reference that's the
    # array or hash index, separated out just because we want to use it in
    # several places in the following regex.
    my $index = '(?: \[.*\] | \{.*\} )?';

    # If in NAME section, just return an ASCII quoted string to avoid
    # confusing tools like whatis.
    return qq{"$_"} if $$self{IN_NAME};

    # Check for things that we don't want to quote, and if we find any of
    # them, return the string with just a font change and no quoting.
    m{
      ^\s*
      (?:
         ( [\'\`\"] ) .* \1                             # already quoted
       | \\\*\(Aq .* \\\*\(Aq                           # quoted and escaped
       | \\?\` .* ( \' | \\\*\(Aq )                     # `quoted'
       | \$+ [\#^]? \S $index                           # special ($^Foo, $")
       | [\$\@%&*]+ \#? [:\'\w]+ $index                 # plain var or func
       | [\$\@%&*]* [:\'\w]+ (?: -> )? \(\s*[^\s,]\s*\) # 0/1-arg func call
       | [-+]? ( \d[\d.]* | \.\d+ ) (?: [eE][-+]?\d+ )? # a number
       | 0x [a-fA-F\d]+                                 # a hex constant
      )
      \s*\z
     }xso and return '\f(FS' . $_ . '\f(FE';

    # If we didn't return, go ahead and quote the text.
    return '\f(FS\*(C`' . $_ . "\\*(C'\\f(FE";
}

sub guesswork {
    my $self = shift;
    local $_ = shift;
    DEBUG > 5 and print "   Guesswork called on [$_]\n";

    # By the time we reach this point, all hyphens will be escaped by adding a
    # backslash.  We want to undo that escaping if they're part of regular
    # words and there's only a single dash, since that's a real hyphen that
    # *roff gets to consider a possible break point.  Make sure that a dash
    # after the first character of a word stays non-breaking, however.
    #
    # Note that this is not user-controllable; we pretty much have to do this
    # transformation or *roff will mangle the output in unacceptable ways.
    s{
        ( (?:\G|^|\s) [\(\"]* [a-zA-Z] ) ( \\- )?
        ( (?: [a-zA-Z\']+ \\-)+ )
        ( [a-zA-Z\']+ ) (?= [\)\".?!,;:]* (?:\s|\Z|\\\ ) )
        \b
    } {
        my ($prefix, $hyphen, $main, $suffix) = ($1, $2, $3, $4);
        $hyphen ||= '';
        $main =~ s/\\-/-/g;
        $prefix . $hyphen . $main . $suffix;
    }egx;

    # Translate "--" into a real em-dash if it's used like one.  This means
    # that it's either surrounded by whitespace, it follows a regular word, or
    # it occurs between two regular words.
    if ($$self{MAGIC_EMDASH}) {
        s{          (\s) \\-\\- (\s)                } { $1 . '\*(--' . $2 }egx;
        s{ (\b[a-zA-Z]+) \\-\\- (\s|\Z|[a-zA-Z]+\b) } { $1 . '\*(--' . $2 }egx;
    }

    # Make words in all-caps a little bit smaller; they look better that way.
    # However, we don't want to change Perl code (like @ARGV), nor do we want
    # to fix the MIME in MIME-Version since it looks weird with the
    # full-height V.
    #
    # We change only a string of all caps (2) either at the beginning of the
    # line or following regular punctuation (like quotes) or whitespace (1),
    # and followed by either similar punctuation, an em-dash, or the end of
    # the line (3).
    #
    # Allow the text we're changing to small caps to include double quotes,
    # commas, newlines, and periods as long as it doesn't otherwise interrupt
    # the string of small caps and still fits the criteria.  This lets us turn
    # entire warranty disclaimers in man page output into small caps.
    if ($$self{MAGIC_SMALLCAPS}) {
        s{
            ( ^ | [\s\(\"\'\`\[\{<>] | \\[ ]  )                     # (1)
            ( [A-Z] [A-Z] (?: [/A-Z+:\d_\$&] | \\- | [.,\"\s] )* )  # (2)
            (?= [\s>\}\]\(\)\'\".?!,;] | \\*\(-- | \\[ ] | $ )      # (3)
        } {
            $1 . '\s-1' . $2 . '\s0'
        }egx;
    }

    # Note that from this point forward, we have to adjust for \s-1 and \s-0
    # strings inserted around things that we've made small-caps if later
    # transforms should work on those strings.

    # Italicize functions in the form func(), including functions that are in
    # all capitals, but don't italize if there's anything between the parens.
    # The function must start with an alphabetic character or underscore and
    # then consist of word characters or colons.
    if ($$self{MAGIC_FUNC}) {
        s{
            ( \b | \\s-1 )
            ( [A-Za-z_] ([:\w] | \\s-?[01])+ \(\) )
        } {
            $1 . '\f(IS' . $2 . '\f(IE'
        }egx;
    }

    # Change references to manual pages to put the page name in italics but
    # the number in the regular font, with a thin space between the name and
    # the number.  Only recognize func(n) where func starts with an alphabetic
    # character or underscore and contains only word characters, periods (for
    # configuration file man pages), or colons, and n is a single digit,
    # optionally followed by some number of lowercase letters.  Note that this
    # does not recognize man page references like perl(l) or socket(3SOCKET).
    if ($$self{MAGIC_MANREF}) {
        s{
            ( \b | \\s-1 )
            ( [A-Za-z_] (?:[.:\w] | \\- | \\s-?[01])+ )
            ( \( \d [a-z]* \) )
        } {
            $1 . '\f(IS' . $2 . '\f(IE\|' . $3
        }egx;
    }

    # Convert simple Perl variable references to a fixed-width font.  Be
    # careful not to convert functions, though; there are too many subtleties
    # with them to want to perform this transformation.
    if ($$self{MAGIC_VARS}) {
        s{
           ( ^ | \s+ )
           ( [\$\@%] [\w:]+ )
           (?! \( )
        } {
            $1 . '\f(FS' . $2 . '\f(FE'
        }egx;
    }

    # Fix up double quotes.  Unfortunately, we miss this transformation if the
    # quoted text contains any code with formatting codes and there's not much
    # we can effectively do about that, which makes it somewhat unclear if
    # this is really a good idea.
    s{ \" ([^\"]+) \" } { '\*(L"' . $1 . '\*(R"' }egx;

    # Make C++ into \*(C+, which is a squinched version.
    if ($$self{MAGIC_CPP}) {
        s{ \b C\+\+ } {\\*\(C+}gx;
    }

    # Done.
    DEBUG > 5 and print "   Guesswork returning [$_]\n";
    return $_;
}


sub mapfonts {
    my ($self, $text) = @_;
    my ($fixed, $bold, $italic) = (0, 0, 0);
    my %magic = (F => \$fixed, B => \$bold, I => \$italic);
    my $last = '\fR';
    $text =~ s<
        \\f\((.)(.)
    > <
        my $sequence = '';
        my $f;
        if ($last ne '\fR') { $sequence = '\fP' }
        ${ $magic{$1} } += ($2 eq 'S') ? 1 : -1;
        $f = $$self{FONTS}{ ($fixed && 1) . ($bold && 1) . ($italic && 1) };
        if ($f eq $last) {
            '';
        } else {
            if ($f ne '\fR') { $sequence .= $f }
            $last = $f;
            $sequence;
        }
    >gxe;
    return $text;
}

sub textmapfonts {
    my ($self, $text) = @_;
    my ($fixed, $bold, $italic) = (0, 0, 0);
    my %magic = (F => \$fixed, B => \$bold, I => \$italic);
    $text =~ s<
        \\f\((.)(.)
    > <
        ${ $magic{$1} } += ($2 eq 'S') ? 1 : -1;
        $$self{FONTS}{ ($fixed && 1) . ($bold && 1) . ($italic && 1) };
    >gxe;
    return $text;
}

sub switchquotes {
    my ($self, $command, $text, $extra) = @_;
    $text =~ s/\\\*\([LR]\"/\"/g;

    # We also have to deal with \*C` and \*C', which are used to add the
    # quotes around C<> text, since they may expand to " and if they do this
    # confuses the .SH macros and the like no end.  Expand them ourselves.
    # Also separate troff from nroff if there are any fixed-width fonts in use
    # to work around problems with Solaris nroff.
    my $c_is_quote = ($$self{LQUOTE} =~ /\"/) || ($$self{RQUOTE} =~ /\"/);
    my $fixedpat = join '|', @{ $$self{FONTS} }{'100', '101', '110', '111'};
    $fixedpat =~ s/\\/\\\\/g;
    $fixedpat =~ s/\(/\\\(/g;
    if ($text =~ m/\"/ || $text =~ m/$fixedpat/) {
        $text =~ s/\"/\"\"/g;
        my $nroff = $text;
        my $troff = $text;
        $troff =~ s/\"\"([^\"]*)\"\"/\`\`$1\'\'/g;
        if ($c_is_quote and $text =~ m/\\\*\(C[\'\`]/) {
            $nroff =~ s/\\\*\(C\`/$$self{LQUOTE}/g;
            $nroff =~ s/\\\*\(C\'/$$self{RQUOTE}/g;
            $troff =~ s/\\\*\(C[\'\`]//g;
        }
        $nroff = qq("$nroff") . ($extra ? " $extra" : '');
        $troff = qq("$troff") . ($extra ? " $extra" : '');

        # Work around the Solaris nroff bug where \f(CW\fP leaves the font set
        # to Roman rather than the actual previous font when used in headings.
        # troff output may still be broken, but at least we can fix nroff by
        # just switching the font changes to the non-fixed versions.
        $nroff =~ s/\Q$$self{FONTS}{100}\E(.*?)\\f[PR]/$1/g;
        $nroff =~ s/\Q$$self{FONTS}{101}\E(.*?)\\f([PR])/\\fI$1\\f$2/g;
        $nroff =~ s/\Q$$self{FONTS}{110}\E(.*?)\\f([PR])/\\fB$1\\f$2/g;
        $nroff =~ s/\Q$$self{FONTS}{111}\E(.*?)\\f([PR])/\\f\(BI$1\\f$2/g;

        # Now finally output the command.  Bother with .ie only if the nroff
        # and troff output aren't the same.
        if ($nroff ne $troff) {
            return ".ie n $command $nroff\n.el $command $troff\n";
        } else {
            return "$command $nroff\n";
        }
    } else {
        $text = qq("$text") . ($extra ? " $extra" : '');
        return "$command $text\n";
    }
}

sub protect {
    my ($self, $text) = @_;
    $text =~ s/^([.\'\\])/\\&$1/mg;
    return $text;
}

sub makespace {
    my ($self) = @_;
    $self->output (".PD\n") if $$self{ITEMS} > 1;
    $$self{ITEMS} = 0;
    $self->output ($$self{INDENT} > 0 ? ".Sp\n" : ".PP\n")
        if $$self{NEEDSPACE};
}

sub outindex {
    my ($self, $section, $index) = @_;
    my @entries = map { split m%\s*/\s*% } @{ $$self{INDEX} };
    return unless ($section || @entries);

    # We're about to output all pending entries, so clear our pending queue.
    $$self{INDEX} = [];

    # Build the output.  Regular index entries are marked Xref, and headings
    # pass in their own section.  Undo some *roff formatting on headings.
    my @output;
    if (@entries) {
        push @output, [ 'Xref', join (' ', @entries) ];
    }
    if ($section) {
        $index =~ s/\\-/-/g;
        $index =~ s/\\(?:s-?\d|.\(..|.)//g;
        push @output, [ $section, $index ];
    }

    # Print out the .IX commands.
    for (@output) {
        my ($type, $entry) = @$_;
        $entry =~ s/\s+/ /g;
        $entry =~ s/\"/\"\"/g;
        $entry =~ s/\\/\\\\/g;
        $self->output (".IX $type " . '"' . $entry . '"' . "\n");
    }
}

sub output {
    my ($self, @text) = @_;
    if ($$self{ENCODE}) {
        print { $$self{output_fh} } encode ('UTF-8', join ('', @text));
    } else {
        print { $$self{output_fh} } @text;
    }
}


sub start_document {
    my ($self, $attrs) = @_;
    if ($$attrs{contentless} && !$$self{ALWAYS_EMIT_SOMETHING}) {
        DEBUG and print "Document is contentless\n";
        $$self{CONTENTLESS} = 1;
    } else {
        delete $$self{CONTENTLESS};
    }

    # When UTF-8 output is set, check whether our output file handle already
    # has a PerlIO encoding layer set.  If it does not, we'll need to encode
    # our output before printing it (handled in the output() sub).  Wrap the
    # check in an eval to handle versions of Perl without PerlIO.
    $$self{ENCODE} = 0;
    if ($$self{utf8}) {
        $$self{ENCODE} = 1;
        eval {
            my @options = (output => 1, details => 1);
            my $flag = (PerlIO::get_layers ($$self{output_fh}, @options))[-1];
            if ($flag & PerlIO::F_UTF8 ()) {
                $$self{ENCODE} = 0;
            }
        }
    }

    # Determine information for the preamble and then output it unless the
    # document was content-free.
    if (!$$self{CONTENTLESS}) {
        my ($name, $section);
        if (defined $$self{name}) {
            $name = $$self{name};
            $section = $$self{section} || 1;
        } else {
            ($name, $section) = $self->devise_title;
        }
        my $date = $$self{date} || $self->devise_date;
        $self->preamble ($name, $section, $date)
            unless $self->bare_output or DEBUG > 9;
    }

    # Initialize a few per-document variables.
    $$self{INDENT}    = 0;      # Current indentation level.
    $$self{INDENTS}   = [];     # Stack of indentations.
    $$self{INDEX}     = [];     # Index keys waiting to be printed.
    $$self{IN_NAME}   = 0;      # Whether processing the NAME section.
    $$self{ITEMS}     = 0;      # The number of consecutive =items.
    $$self{ITEMTYPES} = [];     # Stack of =item types, one per list.
    $$self{SHIFTWAIT} = 0;      # Whether there is a shift waiting.
    $$self{SHIFTS}    = [];     # Stack of .RS shifts.
    $$self{PENDING}   = [[]];   # Pending output.
}

sub end_document {
    my ($self) = @_;
    if ($$self{complain_die} && $self->errors_seen) {
        croak ("POD document had syntax errors");
    }
    return if $self->bare_output;
    return if ($$self{CONTENTLESS} && !$$self{ALWAYS_EMIT_SOMETHING});
    $self->output (q(.\" [End document]) . "\n") if DEBUG;
}

sub devise_title {
    my ($self) = @_;
    my $name = $self->source_filename || '';
    my $section = $$self{section} || 1;
    $section = 3 if (!$$self{section} && $name =~ /\.pm\z/i);
    $name =~ s/\.p(od|[lm])\z//i;

    # If the section isn't 3, then the name defaults to just the basename of
    # the file.  Otherwise, assume we're dealing with a module.  We want to
    # figure out the full module name from the path to the file, but we don't
    # want to include too much of the path into the module name.  Lose
    # anything up to the first off:
    #
    #     */lib/*perl*/         standard or site_perl module
    #     */*perl*/lib/         from -Dprefix=/opt/perl
    #     */*perl*/             random module hierarchy
    #
    # which works.  Also strip off a leading site, site_perl, or vendor_perl
    # component, any OS-specific component, and any version number component,
    # and strip off an initial component of "lib" or "blib/lib" since that's
    # what ExtUtils::MakeMaker creates.  splitdir requires at least File::Spec
    # 0.8.
    if ($section !~ /^3/) {
        require File::Basename;
        $name = uc File::Basename::basename ($name);
    } else {
        require File::Spec;
        my ($volume, $dirs, $file) = File::Spec->splitpath ($name);
        my @dirs = File::Spec->splitdir ($dirs);
        my $cut = 0;
        my $i;
        for ($i = 0; $i < @dirs; $i++) {
            if ($dirs[$i] =~ /perl/) {
                $cut = $i + 1;
                $cut++ if ($dirs[$i + 1] && $dirs[$i + 1] eq 'lib');
                last;
            }
        }
        if ($cut > 0) {
            splice (@dirs, 0, $cut);
            shift @dirs if ($dirs[0] =~ /^(site|vendor)(_perl)?$/);
            shift @dirs if ($dirs[0] =~ /^[\d.]+$/);
            shift @dirs if ($dirs[0] =~ /^(.*-$^O|$^O-.*|$^O)$/);
        }
        shift @dirs if $dirs[0] eq 'lib';
        splice (@dirs, 0, 2) if ($dirs[0] eq 'blib' && $dirs[1] eq 'lib');

        # Remove empty directories when building the module name; they
        # occur too easily on Unix by doubling slashes.
        $name = join ('::', (grep { $_ ? $_ : () } @dirs), $file);
    }
    return ($name, $section);
}

sub devise_date {
    my ($self) = @_;
    my $input = $self->source_filename;
    my $time;
    if ($input) {
        $time = (stat $input)[9] || time;
    } else {
        $time = time;
    }

    # Can't use POSIX::strftime(), which uses Fcntl, because MakeMaker
    # uses this and it has to work in the core which can't load dynamic
    # libraries.
    my ($year, $month, $day) = (localtime $time)[5,4,3];
    return sprintf ("%04d-%02d-%02d", $year + 1900, $month + 1, $day);
}

sub preamble {
    my ($self, $name, $section, $date) = @_;
    my $preamble = $self->preamble_template (!$$self{utf8});

    # Build the index line and make sure that it will be syntactically valid.
    my $index = "$name $section";
    $index =~ s/\"/\"\"/g;

    # If name or section contain spaces, quote them (section really never
    # should, but we may as well be cautious).
    for ($name, $section) {
        if (/\s/) {
            s/\"/\"\"/g;
            $_ = '"' . $_ . '"';
        }
    }

    # Double quotes in date, since it will be quoted.
    $date =~ s/\"/\"\"/g;

    # Substitute into the preamble the configuration options.
    $preamble =~ s/\@CFONT\@/$$self{fixed}/;
    $preamble =~ s/\@LQUOTE\@/$$self{LQUOTE}/;
    $preamble =~ s/\@RQUOTE\@/$$self{RQUOTE}/;
    chomp $preamble;

    # Get the version information.
    my $version = $self->version_report;

    # Finally output everything.
    $self->output (<<"----END OF HEADER----");
.\\" Automatically generated by $version
.\\"
.\\" Standard preamble:
.\\" ========================================================================
$preamble
.\\" ========================================================================
.\\"
.IX Title "$index"
.TH $name $section "$date" "$$self{release}" "$$self{center}"
.\\" For nroff, turn off justification.  Always turn off hyphenation; it makes
.\\" way too many mistakes in technical documents.
.if n .ad l
.nh
----END OF HEADER----
    $self->output (".\\\" [End of preamble]\n") if DEBUG;
}


sub cmd_para {
    my ($self, $attrs, $text) = @_;
    my $line = $$attrs{start_line};

    # Output the paragraph.  We also have to handle =over without =item.  If
    # there's an =over without =item, SHIFTWAIT will be set, and we need to
    # handle creation of the indent here.  Add the shift to SHIFTS so that it
    # will be cleaned up on =back.
    $self->makespace;
    if ($$self{SHIFTWAIT}) {
        $self->output (".RS $$self{INDENT}\n");
        push (@{ $$self{SHIFTS} }, $$self{INDENT});
        $$self{SHIFTWAIT} = 0;
    }

    # Add the line number for debugging, but not in the NAME section just in
    # case the comment would confuse apropos.
    $self->output (".\\\" [At source line $line]\n")
        if defined ($line) && DEBUG && !$$self{IN_NAME};

    # Force exactly one newline at the end and strip unwanted trailing
    # whitespace at the end, but leave "\ " backslashed space from an S< > at
    # the end of a line.  Reverse the text first, to avoid having to scan the
    # entire paragraph.
    $text = reverse $text;
    $text =~ s/\A\s*?(?= \\|\S|\z)/\n/;
    $text = reverse $text;

    # Output the paragraph.
    $self->output ($self->protect ($self->textmapfonts ($text)));
    $self->outindex;
    $$self{NEEDSPACE} = 1;
    return '';
}

sub cmd_verbatim {
    my ($self, $attrs, $text) = @_;

    # Ignore an empty verbatim paragraph.
    return unless $text =~ /\S/;

    # Force exactly one newline at the end and strip unwanted trailing
    # whitespace at the end.  Reverse the text first, to avoid having to scan
    # the entire paragraph.
    $text = reverse $text;
    $text =~ s/\A\s*/\n/;
    $text = reverse $text;

    # Get a count of the number of lines before the first blank line, which
    # we'll pass to .Vb as its parameter.  This tells *roff to keep that many
    # lines together.  We don't want to tell *roff to keep huge blocks
    # together.
    my @lines = split (/\n/, $text);
    my $unbroken = 0;
    for (@lines) {
        last if /^\s*$/;
        $unbroken++;
    }
    $unbroken = 10 if ($unbroken > 12 && !$$self{MAGIC_VNOPAGEBREAK_LIMIT});

    # Prepend a null token to each line.
    $text =~ s/^/\\&/gm;

    # Output the results.
    $self->makespace;
    $self->output (".Vb $unbroken\n$text.Ve\n");
    $$self{NEEDSPACE} = 1;
    return '';
}

sub cmd_data {
    my ($self, $attrs, $text) = @_;
    $text =~ s/^\n+//;
    $text =~ s/\n{0,2}$/\n/;
    $self->output ($text);
    return '';
}


sub heading_common {
    my ($self, $text, $line) = @_;
    $text =~ s/\s+$//;
    $text =~ s/\s*\n\s*/ /g;

    # This should never happen; it means that we have a heading after =item
    # without an intervening =back.  But just in case, handle it anyway.
    if ($$self{ITEMS} > 1) {
        $$self{ITEMS} = 0;
        $self->output (".PD\n");
    }

    # Output the current source line.
    $self->output ( ".\\\" [At source line $line]\n" )
        if defined ($line) && DEBUG;
    return $text;
}

sub cmd_head1 {
    my ($self, $attrs, $text) = @_;
    $text =~ s/\\s-?\d//g;
    $text = $self->heading_common ($text, $$attrs{start_line});
    my $isname = ($text eq 'NAME' || $text =~ /\(NAME\)/);
    $self->output ($self->switchquotes ('.SH', $self->mapfonts ($text)));
    $self->outindex ('Header', $text) unless $isname;
    $$self{NEEDSPACE} = 0;
    $$self{IN_NAME} = $isname;
    return '';
}

sub cmd_head2 {
    my ($self, $attrs, $text) = @_;
    $text = $self->heading_common ($text, $$attrs{start_line});
    $self->output ($self->switchquotes ('.SS', $self->mapfonts ($text)));
    $self->outindex ('Subsection', $text);
    $$self{NEEDSPACE} = 0;
    return '';
}

sub cmd_head3 {
    my ($self, $attrs, $text) = @_;
    $text = $self->heading_common ($text, $$attrs{start_line});
    $self->makespace;
    $self->output ($self->textmapfonts ('\f(IS' . $text . '\f(IE') . "\n");
    $self->outindex ('Subsection', $text);
    $$self{NEEDSPACE} = 1;
    return '';
}

sub cmd_head4 {
    my ($self, $attrs, $text) = @_;
    $text = $self->heading_common ($text, $$attrs{start_line});
    $self->makespace;
    $self->output ($self->textmapfonts ($text) . "\n");
    $self->outindex ('Subsection', $text);
    $$self{NEEDSPACE} = 1;
    return '';
}


sub cmd_b { return $_[0]->{IN_NAME} ? $_[2] : '\f(BS' . $_[2] . '\f(BE' }
sub cmd_i { return $_[0]->{IN_NAME} ? $_[2] : '\f(IS' . $_[2] . '\f(IE' }
sub cmd_f { return $_[0]->{IN_NAME} ? $_[2] : '\f(IS' . $_[2] . '\f(IE' }
sub cmd_c { return $_[0]->quote_literal ($_[2]) }

sub cmd_x {
    my ($self, $attrs, $text) = @_;
    push (@{ $$self{INDEX} }, $text);
    return '';
}

sub cmd_l {
    my ($self, $attrs, $text) = @_;
    if ($$attrs{type} eq 'url') {
        my $to = $$attrs{to};
        if (defined $to) {
            my $tag = $$self{PENDING}[-1];
            $to = $self->format_text ($$tag[1], $to);
        }
        if (not defined ($to) or $to eq $text) {
            return "<$text>";
        } elsif ($$self{nourls}) {
            return $text;
        } else {
            return "$text <$$attrs{to}>";
        }
    } else {
        return $text;
    }
}


sub over_common_start {
    my ($self, $type, $attrs) = @_;
    my $line = $$attrs{start_line};
    my $indent = $$attrs{indent};
    DEBUG > 3 and print " Starting =over $type (line $line, indent ",
        ($indent || '?'), "\n";

    # Find the indentation level.
    unless (defined ($indent) && $indent =~ /^[-+]?\d{1,4}\s*$/) {
        $indent = $$self{indent};
    }

    # If we've gotten multiple indentations in a row, we need to emit the
    # pending indentation for the last level that we saw and haven't acted on
    # yet.  SHIFTS is the stack of indentations that we've actually emitted
    # code for.
    if (@{ $$self{SHIFTS} } < @{ $$self{INDENTS} }) {
        $self->output (".RS $$self{INDENT}\n");
        push (@{ $$self{SHIFTS} }, $$self{INDENT});
    }

    # Now, do record-keeping.  INDENTS is a stack of indentations that we've
    # seen so far, and INDENT is the current level of indentation.  ITEMTYPES
    # is a stack of list types that we've seen.
    push (@{ $$self{INDENTS} }, $$self{INDENT});
    push (@{ $$self{ITEMTYPES} }, $type);
    $$self{INDENT} = $indent + 0;
    $$self{SHIFTWAIT} = 1;
}

sub over_common_end {
    my ($self) = @_;
    DEBUG > 3 and print " Ending =over\n";
    $$self{INDENT} = pop @{ $$self{INDENTS} };
    pop @{ $$self{ITEMTYPES} };

    # If we emitted code for that indentation, end it.
    if (@{ $$self{SHIFTS} } > @{ $$self{INDENTS} }) {
        $self->output (".RE\n");
        pop @{ $$self{SHIFTS} };
    }

    # If we're still in an indentation, *roff will have now lost track of the
    # right depth of that indentation, so fix that.
    if (@{ $$self{INDENTS} } > 0) {
        $self->output (".RE\n");
        $self->output (".RS $$self{INDENT}\n");
    }
    $$self{NEEDSPACE} = 1;
    $$self{SHIFTWAIT} = 0;
}

sub start_over_bullet { my $s = shift; $s->over_common_start ('bullet', @_) }
sub start_over_number { my $s = shift; $s->over_common_start ('number', @_) }
sub start_over_text   { my $s = shift; $s->over_common_start ('text',   @_) }
sub start_over_block  { my $s = shift; $s->over_common_start ('block',  @_) }
sub end_over_bullet { $_[0]->over_common_end }
sub end_over_number { $_[0]->over_common_end }
sub end_over_text   { $_[0]->over_common_end }
sub end_over_block  { $_[0]->over_common_end }

sub item_common {
    my ($self, $type, $attrs, $text) = @_;
    my $line = $$attrs{start_line};
    DEBUG > 3 and print "  $type item (line $line): $text\n";

    # Clean up the text.  We want to end up with two variables, one ($text)
    # which contains any body text after taking out the item portion, and
    # another ($item) which contains the actual item text.
    $text =~ s/\s+$//;
    my ($item, $index);
    if ($type eq 'bullet') {
        $item = "\\\(bu";
        $text =~ s/\n*$/\n/;
    } elsif ($type eq 'number') {
        $item = $$attrs{number} . '.';
    } else {
        $item = $text;
        $item =~ s/\s*\n\s*/ /g;
        $text = '';
        $index = $item if ($item =~ /\w/);
    }

    # Take care of the indentation.  If shifts and indents are equal, close
    # the top shift, since we're about to create an indentation with .IP.
    # Also output .PD 0 to turn off spacing between items if this item is
    # directly following another one.  We only have to do that once for a
    # whole chain of items so do it for the second item in the change.  Note
    # that makespace is what undoes this.
    if (@{ $$self{SHIFTS} } == @{ $$self{INDENTS} }) {
        $self->output (".RE\n");
        pop @{ $$self{SHIFTS} };
    }
    $self->output (".PD 0\n") if ($$self{ITEMS} == 1);

    # Now, output the item tag itself.
    $item = $self->textmapfonts ($item);
    $self->output ($self->switchquotes ('.IP', $item, $$self{INDENT}));
    $$self{NEEDSPACE} = 0;
    $$self{ITEMS}++;
    $$self{SHIFTWAIT} = 0;

    # If body text for this item was included, go ahead and output that now.
    if ($text) {
        $text =~ s/\s*$/\n/;
        $self->makespace;
        $self->output ($self->protect ($self->textmapfonts ($text)));
        $$self{NEEDSPACE} = 1;
    }
    $self->outindex ($index ? ('Item', $index) : ());
}

sub cmd_item_bullet { my $self = shift; $self->item_common ('bullet', @_) }
sub cmd_item_number { my $self = shift; $self->item_common ('number', @_) }
sub cmd_item_text   { my $self = shift; $self->item_common ('text',   @_) }
sub cmd_item_block  { my $self = shift; $self->item_common ('block',  @_) }


sub parse_from_file {
    my $self = shift;
    $self->reinit;

    # Fake the old cutting option to Pod::Parser.  This fiddings with internal
    # Pod::Simple state and is quite ugly; we need a better approach.
    if (ref ($_[0]) eq 'HASH') {
        my $opts = shift @_;
        if (defined ($$opts{-cutting}) && !$$opts{-cutting}) {
            $$self{in_pod} = 1;
            $$self{last_was_blank} = 1;
        }
    }

    # Do the work.
    my $retval = $self->SUPER::parse_from_file (@_);

    # Flush output, since Pod::Simple doesn't do this.  Ideally we should also
    # close the file descriptor if we had to open one, but we can't easily
    # figure this out.
    my $fh = $self->output_fh ();
    my $oldfh = select $fh;
    my $oldflush = $|;
    $| = 1;
    print $fh '';
    $| = $oldflush;
    select $oldfh;
    return $retval;
}

sub parse_from_filehandle {
    my $self = shift;
    return $self->parse_from_file (@_);
}

sub parse_file {
    my ($self, $in) = @_;
    unless (defined $$self{output_fh}) {
        $self->output_fh (\*STDOUT);
    }
    return $self->SUPER::parse_file ($in);
}

sub parse_lines {
    my ($self, @lines) = @_;
    unless (defined $$self{output_fh}) {
        $self->output_fh (\*STDOUT);
    }
    return $self->SUPER::parse_lines (@lines);
}

sub parse_string_document {
    my ($self, $doc) = @_;
    unless (defined $$self{output_fh}) {
        $self->output_fh (\*STDOUT);
    }
    return $self->SUPER::parse_string_document ($doc);
}


@ESCAPES{0xA0 .. 0xFF} = (
    "\\ ", undef, undef, undef,            undef, undef, undef, undef,
    undef, undef, undef, undef,            undef, "\\%", undef, undef,

    undef, undef, undef, undef,            undef, undef, undef, undef,
    undef, undef, undef, undef,            undef, undef, undef, undef,

    "A\\*`",  "A\\*'", "A\\*^", "A\\*~",   "A\\*:", "A\\*o", "\\*(Ae", "C\\*,",
    "E\\*`",  "E\\*'", "E\\*^", "E\\*:",   "I\\*`", "I\\*'", "I\\*^",  "I\\*:",

    "\\*(D-", "N\\*~", "O\\*`", "O\\*'",   "O\\*^", "O\\*~", "O\\*:",  undef,
    "O\\*/",  "U\\*`", "U\\*'", "U\\*^",   "U\\*:", "Y\\*'", "\\*(Th", "\\*8",

    "a\\*`",  "a\\*'", "a\\*^", "a\\*~",   "a\\*:", "a\\*o", "\\*(ae", "c\\*,",
    "e\\*`",  "e\\*'", "e\\*^", "e\\*:",   "i\\*`", "i\\*'", "i\\*^",  "i\\*:",

    "\\*(d-", "n\\*~", "o\\*`", "o\\*'",   "o\\*^", "o\\*~", "o\\*:",  undef,
    "o\\*/" , "u\\*`", "u\\*'", "u\\*^",   "u\\*:", "y\\*'", "\\*(th", "y\\*:",
) if ASCII;


sub preamble_template {
    my ($self, $accents) = @_;
    my $preamble = <<'----END OF PREAMBLE----';
.de Sp \" Vertical space (when we can't use .PP)
.if t .sp .5v
.if n .sp
..
.de Vb \" Begin verbatim text
.ft @CFONT@
.nf
.ne \\$1
..
.de Ve \" End verbatim text
.ft R
.fi
..
.\" Set up some character translations and predefined strings.  \*(-- will
.\" give an unbreakable dash, \*(PI will give pi, \*(L" will give a left
.\" double quote, and \*(R" will give a right double quote.  \*(C+ will
.\" give a nicer C++.  Capital omega is used to do unbreakable dashes and
.\" therefore won't be available.  \*(C` and \*(C' expand to `' in nroff,
.\" nothing in troff, for use with C<>.
.tr \(*W-
.ds C+ C\v'-.1v'\h'-1p'\s-2+\h'-1p'+\s0\v'.1v'\h'-1p'
.ie n \{\
.    ds -- \(*W-
.    ds PI pi
.    if (\n(.H=4u)&(1m=24u) .ds -- \(*W\h'-12u'\(*W\h'-12u'-\" diablo 10 pitch
.    if (\n(.H=4u)&(1m=20u) .ds -- \(*W\h'-12u'\(*W\h'-8u'-\"  diablo 12 pitch
.    ds L" ""
.    ds R" ""
.    ds C` @LQUOTE@
.    ds C' @RQUOTE@
'br\}
.el\{\
.    ds -- \|\(em\|
.    ds PI \(*p
.    ds L" ``
.    ds R" ''
.    ds C`
.    ds C'
'br\}
.\"
.\" Escape single quotes in literal strings from groff's Unicode transform.
.ie \n(.g .ds Aq \(aq
.el       .ds Aq '
.\"
.\" If the F register is turned on, we'll generate index entries on stderr for
.\" titles (.TH), headers (.SH), subsections (.SS), items (.Ip), and index
.\" entries marked with X<> in POD.  Of course, you'll have to process the
.\" output yourself in some meaningful fashion.
.\"
.\" Avoid warning from groff about undefined register 'F'.
.de IX
..
.nr rF 0
.if \n(.g .if rF .nr rF 1
.if (\n(rF:(\n(.g==0)) \{
.    if \nF \{
.        de IX
.        tm Index:\\$1\t\\n%\t"\\$2"
..
.        if !\nF==2 \{
.            nr % 0
.            nr F 2
.        \}
.    \}
.\}
.rr rF
----END OF PREAMBLE----
#'# for cperl-mode

    if ($accents) {
        $preamble .= <<'----END OF PREAMBLE----'
.\"
.\" Accent mark definitions (@(#)ms.acc 1.5 88/02/08 SMI; from UCB 4.2).
.\" Fear.  Run.  Save yourself.  No user-serviceable parts.
.    \" fudge factors for nroff and troff
.if n \{\
.    ds #H 0
.    ds #V .8m
.    ds #F .3m
.    ds #[ \f1
.    ds #] \fP
.\}
.if t \{\
.    ds #H ((1u-(\\\\n(.fu%2u))*.13m)
.    ds #V .6m
.    ds #F 0
.    ds #[ \&
.    ds #] \&
.\}
.    \" simple accents for nroff and troff
.if n \{\
.    ds ' \&
.    ds ` \&
.    ds ^ \&
.    ds , \&
.    ds ~ ~
.    ds /
.\}
.if t \{\
.    ds ' \\k:\h'-(\\n(.wu*8/10-\*(#H)'\'\h"|\\n:u"
.    ds ` \\k:\h'-(\\n(.wu*8/10-\*(#H)'\`\h'|\\n:u'
.    ds ^ \\k:\h'-(\\n(.wu*10/11-\*(#H)'^\h'|\\n:u'
.    ds , \\k:\h'-(\\n(.wu*8/10)',\h'|\\n:u'
.    ds ~ \\k:\h'-(\\n(.wu-\*(#H-.1m)'~\h'|\\n:u'
.    ds / \\k:\h'-(\\n(.wu*8/10-\*(#H)'\z\(sl\h'|\\n:u'
.\}
.    \" troff and (daisy-wheel) nroff accents
.ds : \\k:\h'-(\\n(.wu*8/10-\*(#H+.1m+\*(#F)'\v'-\*(#V'\z.\h'.2m+\*(#F'.\h'|\\n:u'\v'\*(#V'
.ds 8 \h'\*(#H'\(*b\h'-\*(#H'
.ds o \\k:\h'-(\\n(.wu+\w'\(de'u-\*(#H)/2u'\v'-.3n'\*(#[\z\(de\v'.3n'\h'|\\n:u'\*(#]
.ds d- \h'\*(#H'\(pd\h'-\w'~'u'\v'-.25m'\f2\(hy\fP\v'.25m'\h'-\*(#H'
.ds D- D\\k:\h'-\w'D'u'\v'-.11m'\z\(hy\v'.11m'\h'|\\n:u'
.ds th \*(#[\v'.3m'\s+1I\s-1\v'-.3m'\h'-(\w'I'u*2/3)'\s-1o\s+1\*(#]
.ds Th \*(#[\s+2I\s-2\h'-\w'I'u*3/5'\v'-.3m'o\v'.3m'\*(#]
.ds ae a\h'-(\w'a'u*4/10)'e
.ds Ae A\h'-(\w'A'u*4/10)'E
.    \" corrections for vroff
.if v .ds ~ \\k:\h'-(\\n(.wu*9/10-\*(#H)'\s-2\u~\d\s+2\h'|\\n:u'
.if v .ds ^ \\k:\h'-(\\n(.wu*10/11-\*(#H)'\v'-.4m'^\v'.4m'\h'|\\n:u'
.    \" for low resolution devices (crt and lpr)
.if \n(.H>23 .if \n(.V>19 \
\{\
.    ds : e
.    ds 8 ss
.    ds o a
.    ds d- d\h'-1'\(ga
.    ds D- D\h'-1'\(hy
.    ds th \o'bp'
.    ds Th \o'LP'
.    ds ae ae
.    ds Ae AE
.\}
.rm #[ #] #H #V #F C
----END OF PREAMBLE----
    }
    return $preamble;
}


1;
__END__

