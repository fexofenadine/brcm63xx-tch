

package Pod::Text;

require 5.004;

use strict;
use vars qw(@ISA @EXPORT %ESCAPES $VERSION);

use Carp qw(carp croak);
use Encode qw(encode);
use Exporter ();
use Pod::Simple ();

@ISA = qw(Pod::Simple Exporter);

@EXPORT = qw(pod2text);

$VERSION = '3.18';


sub handle_code {
    my ($line, $number, $parser) = @_;
    $parser->output_code ($line . "\n");
}

sub new {
    my $class = shift;
    my $self = $class->SUPER::new;

    # Tell Pod::Simple to handle S<> by automatically inserting &nbsp;.
    $self->nbsp_for_S (1);

    # Tell Pod::Simple to keep whitespace whenever possible.
    if ($self->can ('preserve_whitespace')) {
        $self->preserve_whitespace (1);
    } else {
        $self->fullstop_space_harden (1);
    }

    # The =for and =begin targets that we accept.
    $self->accept_targets (qw/text TEXT/);

    # Ensure that contiguous blocks of code are merged together.  Otherwise,
    # some of the guesswork heuristics don't work right.
    $self->merge_text (1);

    # Pod::Simple doesn't do anything useful with our arguments, but we want
    # to put them in our object as hash keys and values.  This could cause
    # problems if we ever clash with Pod::Simple's own internal class
    # variables.
    my %opts = @_;
    my @opts = map { ("opt_$_", $opts{$_}) } keys %opts;
    %$self = (%$self, @opts);

    # Send errors to stderr if requested.
    if ($$self{opt_stderr} and not $$self{opt_errors}) {
        $$self{opt_errors} = 'stderr';
    }
    delete $$self{opt_stderr};

    # Validate the errors parameter and act on it.
    if (not defined $$self{opt_errors}) {
        $$self{opt_errors} = 'pod';
    }
    if ($$self{opt_errors} eq 'stderr' || $$self{opt_errors} eq 'die') {
        $self->no_errata_section (1);
        $self->complain_stderr (1);
        if ($$self{opt_errors} eq 'die') {
            $$self{complain_die} = 1;
        }
    } elsif ($$self{opt_errors} eq 'pod') {
        $self->no_errata_section (0);
        $self->complain_stderr (0);
    } elsif ($$self{opt_errors} eq 'none') {
        $self->no_whining (1);
    } else {
        croak (qq(Invalid errors setting: "$$self{errors}"));
    }
    delete $$self{errors};

    # Initialize various things from our parameters.
    $$self{opt_alt}      = 0  unless defined $$self{opt_alt};
    $$self{opt_indent}   = 4  unless defined $$self{opt_indent};
    $$self{opt_margin}   = 0  unless defined $$self{opt_margin};
    $$self{opt_loose}    = 0  unless defined $$self{opt_loose};
    $$self{opt_sentence} = 0  unless defined $$self{opt_sentence};
    $$self{opt_width}    = 76 unless defined $$self{opt_width};

    # Figure out what quotes we'll be using for C<> text.
    $$self{opt_quotes} ||= '"';
    if ($$self{opt_quotes} eq 'none') {
        $$self{LQUOTE} = $$self{RQUOTE} = '';
    } elsif (length ($$self{opt_quotes}) == 1) {
        $$self{LQUOTE} = $$self{RQUOTE} = $$self{opt_quotes};
    } elsif ($$self{opt_quotes} =~ /^(.)(.)$/
             || $$self{opt_quotes} =~ /^(..)(..)$/) {
        $$self{LQUOTE} = $1;
        $$self{RQUOTE} = $2;
    } else {
        croak qq(Invalid quote specification "$$self{opt_quotes}");
    }

    # If requested, do something with the non-POD text.
    $self->code_handler (\&handle_code) if $$self{opt_code};

    # Return the created object.
    return $self;
}



sub _handle_text {
    my ($self, $text) = @_;
    my $tag = $$self{PENDING}[-1];
    $$tag[1] .= $text;
}

sub method_for_element {
    my ($self, $element) = @_;
    $element =~ tr/-/_/;
    $element =~ tr/A-Z/a-z/;
    $element =~ tr/_a-z0-9//cd;
    return $element;
}

sub _handle_element_start {
    my ($self, $element, $attrs) = @_;
    my $method = $self->method_for_element ($element);

    # If we have a command handler, we need to accumulate the contents of the
    # tag before calling it.
    if ($self->can ("cmd_$method")) {
        push (@{ $$self{PENDING} }, [ $attrs, '' ]);
    } elsif ($self->can ("start_$method")) {
        my $method = 'start_' . $method;
        $self->$method ($attrs, '');
    }
}

sub _handle_element_end {
    my ($self, $element) = @_;
    my $method = $self->method_for_element ($element);

    # If we have a command handler, pull off the pending text and pass it to
    # the handler along with the saved attribute hash.
    if ($self->can ("cmd_$method")) {
        my $tag = pop @{ $$self{PENDING} };
        my $method = 'cmd_' . $method;
        my $text = $self->$method (@$tag);
        if (defined $text) {
            if (@{ $$self{PENDING} } > 1) {
                $$self{PENDING}[-1][1] .= $text;
            } else {
                $self->output ($text);
            }
        }
    } elsif ($self->can ("end_$method")) {
        my $method = 'end_' . $method;
        $self->$method ();
    }
}


sub wrap {
    my $self = shift;
    local $_ = shift;
    my $output = '';
    my $spaces = ' ' x $$self{MARGIN};
    my $width = $$self{opt_width} - $$self{MARGIN};
    while (length > $width) {
        if (s/^([^\n]{0,$width})\s+// || s/^([^\n]{$width})//) {
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

    # If we're trying to preserve two spaces after sentences, do some munging
    # to support that.  Otherwise, smash all repeated whitespace.
    if ($$self{opt_sentence}) {
        s/ +$//mg;
        s/\.\n/. \n/g;
        s/\n/ /g;
        s/   +/  /g;
    } else {
        s/\s+/ /g;
    }
    return $self->wrap ($_);
}

sub output {
    my ($self, @text) = @_;
    my $text = join ('', @text);
    $text =~ tr/\240\255/ /d;
    unless ($$self{opt_utf8} || $$self{CHECKED_ENCODING}) {
        my $encoding = $$self{encoding} || '';
        if ($encoding) {
            eval { binmode ($$self{output_fh}, ":encoding($encoding)") };
        }
        $$self{CHECKED_ENCODING} = 1;
    }
    if ($$self{ENCODE}) {
        print { $$self{output_fh} } encode ('UTF-8', $text);
    } else {
        print { $$self{output_fh} } $text;
    }
}

sub output_code { $_[0]->output ($_[1]) }


sub start_document {
    my ($self, $attrs) = @_;
    if ($$attrs{contentless} && !$$self{ALWAYS_EMIT_SOMETHING}) {
        $$self{CONTENTLESS} = 1;
    } else {
        delete $$self{CONTENTLESS};
    }
    my $margin = $$self{opt_indent} + $$self{opt_margin};

    # Initialize a few per-document variables.
    $$self{INDENTS} = [];       # Stack of indentations.
    $$self{MARGIN}  = $margin;  # Default left margin.
    $$self{PENDING} = [[]];     # Pending output.

    # We have to redo encoding handling for each document.
    delete $$self{CHECKED_ENCODING};

    # When UTF-8 output is set, check whether our output file handle already
    # has a PerlIO encoding layer set.  If it does not, we'll need to encode
    # our output before printing it (handled in the output() sub).  Wrap the
    # check in an eval to handle versions of Perl without PerlIO.
    $$self{ENCODE} = 0;
    if ($$self{opt_utf8}) {
        $$self{ENCODE} = 1;
        eval {
            my @options = (output => 1, details => 1);
            my $flag = (PerlIO::get_layers ($$self{output_fh}, @options))[-1];
            if ($flag & PerlIO::F_UTF8 ()) {
                $$self{ENCODE} = 0;
            }
        };
    }

    return '';
}

sub end_document {
    my ($self) = @_;
    if ($$self{complain_die} && $self->errors_seen) {
        croak ("POD document had syntax errors");
    }
}


sub strip_format {
    my ($self, $string) = @_;
    return $string;
}

sub item {
    my ($self, $text) = @_;
    my $tag = $$self{ITEM};
    unless (defined $tag) {
        carp "Item called without tag";
        return;
    }
    undef $$self{ITEM};

    # Calculate the indentation and margin.  $fits is set to true if the tag
    # will fit into the margin of the paragraph given our indentation level.
    my $indent = $$self{INDENTS}[-1];
    $indent = $$self{opt_indent} unless defined $indent;
    my $margin = ' ' x $$self{opt_margin};
    my $tag_length = length ($self->strip_format ($tag));
    my $fits = ($$self{MARGIN} - $indent >= $tag_length + 1);

    # If the tag doesn't fit, or if we have no associated text, print out the
    # tag separately.  Otherwise, put the tag in the margin of the paragraph.
    if (!$text || $text =~ /^\s+$/ || !$fits) {
        my $realindent = $$self{MARGIN};
        $$self{MARGIN} = $indent;
        my $output = $self->reformat ($tag);
        $output =~ s/^$margin /$margin:/ if ($$self{opt_alt} && $indent > 0);
        $output =~ s/\n*$/\n/;

        # If the text is just whitespace, we have an empty item paragraph;
        # this can result from =over/=item/=back without any intermixed
        # paragraphs.  Insert some whitespace to keep the =item from merging
        # into the next paragraph.
        $output .= "\n" if $text && $text =~ /^\s*$/;

        $self->output ($output);
        $$self{MARGIN} = $realindent;
        $self->output ($self->reformat ($text)) if ($text && $text =~ /\S/);
    } else {
        my $space = ' ' x $indent;
        $space =~ s/^$margin /$margin:/ if $$self{opt_alt};
        $text = $self->reformat ($text);
        $text =~ s/^$margin /$margin:/ if ($$self{opt_alt} && $indent > 0);
        my $tagspace = ' ' x $tag_length;
        $text =~ s/^($space)$tagspace/$1$tag/ or warn "Bizarre space in item";
        $self->output ($text);
    }
}

sub cmd_para {
    my ($self, $attrs, $text) = @_;
    $text =~ s/\s+$/\n/;
    if (defined $$self{ITEM}) {
        $self->item ($text . "\n");
    } else {
        $self->output ($self->reformat ($text . "\n"));
    }
    return '';
}

sub cmd_verbatim {
    my ($self, $attrs, $text) = @_;
    $self->item if defined $$self{ITEM};
    return if $text =~ /^\s*$/;
    $text =~ s/^(\n*)([ \t]*\S+)/$1 . (' ' x $$self{MARGIN}) . $2/gme;
    $text =~ s/\s*$/\n\n/;
    $self->output ($text);
    return '';
}

sub cmd_data {
    my ($self, $attrs, $text) = @_;
    $text =~ s/^\n+//;
    $text =~ s/\n{0,2}$/\n/;
    $self->output ($text);
    return '';
}


sub heading {
    my ($self, $text, $indent, $marker) = @_;
    $self->item ("\n\n") if defined $$self{ITEM};
    $text =~ s/\s+$//;
    if ($$self{opt_alt}) {
        my $closemark = reverse (split (//, $marker));
        my $margin = ' ' x $$self{opt_margin};
        $self->output ("\n" . "$margin$marker $text $closemark" . "\n\n");
    } else {
        $text .= "\n" if $$self{opt_loose};
        my $margin = ' ' x ($$self{opt_margin} + $indent);
        $self->output ($margin . $text . "\n");
    }
    return '';
}

sub cmd_head1 {
    my ($self, $attrs, $text) = @_;
    $self->heading ($text, 0, '====');
}

sub cmd_head2 {
    my ($self, $attrs, $text) = @_;
    $self->heading ($text, $$self{opt_indent} / 2, '==  ');
}

sub cmd_head3 {
    my ($self, $attrs, $text) = @_;
    $self->heading ($text, $$self{opt_indent} * 2 / 3 + 0.5, '=   ');
}

sub cmd_head4 {
    my ($self, $attrs, $text) = @_;
    $self->heading ($text, $$self{opt_indent} * 3 / 4 + 0.5, '-   ');
}


sub over_common_start {
    my ($self, $attrs) = @_;
    $self->item ("\n\n") if defined $$self{ITEM};

    # Find the indentation level.
    my $indent = $$attrs{indent};
    unless (defined ($indent) && $indent =~ /^\s*[-+]?\d{1,4}\s*$/) {
        $indent = $$self{opt_indent};
    }

    # Add this to our stack of indents and increase our current margin.
    push (@{ $$self{INDENTS} }, $$self{MARGIN});
    $$self{MARGIN} += ($indent + 0);
    return '';
}

sub over_common_end {
    my ($self) = @_;
    $self->item ("\n\n") if defined $$self{ITEM};
    $$self{MARGIN} = pop @{ $$self{INDENTS} };
    return '';
}

sub start_over_bullet { $_[0]->over_common_start ($_[1]) }
sub start_over_number { $_[0]->over_common_start ($_[1]) }
sub start_over_text   { $_[0]->over_common_start ($_[1]) }
sub start_over_block  { $_[0]->over_common_start ($_[1]) }
sub end_over_bullet { $_[0]->over_common_end }
sub end_over_number { $_[0]->over_common_end }
sub end_over_text   { $_[0]->over_common_end }
sub end_over_block  { $_[0]->over_common_end }

sub item_common {
    my ($self, $type, $attrs, $text) = @_;
    $self->item if defined $$self{ITEM};

    # Clean up the text.  We want to end up with two variables, one ($text)
    # which contains any body text after taking out the item portion, and
    # another ($item) which contains the actual item text.  Note the use of
    # the internal Pod::Simple attribute here; that's a potential land mine.
    $text =~ s/\s+$//;
    my ($item, $index);
    if ($type eq 'bullet') {
        $item = '*';
    } elsif ($type eq 'number') {
        $item = $$attrs{'~orig_content'};
    } else {
        $item = $text;
        $item =~ s/\s*\n\s*/ /g;
        $text = '';
    }
    $$self{ITEM} = $item;

    # If body text for this item was included, go ahead and output that now.
    if ($text) {
        $text =~ s/\s*$/\n/;
        $self->item ($text);
    }
    return '';
}

sub cmd_item_bullet { my $self = shift; $self->item_common ('bullet', @_) }
sub cmd_item_number { my $self = shift; $self->item_common ('number', @_) }
sub cmd_item_text   { my $self = shift; $self->item_common ('text',   @_) }
sub cmd_item_block  { my $self = shift; $self->item_common ('block',  @_) }


sub cmd_b { return $_[0]{alt} ? "``$_[2]''" : $_[2] }
sub cmd_f { return $_[0]{alt} ? "\"$_[2]\"" : $_[2] }
sub cmd_i { return '*' . $_[2] . '*' }
sub cmd_x { return '' }

sub cmd_c {
    my ($self, $attrs, $text) = @_;

    # A regex that matches the portion of a variable reference that's the
    # array or hash index, separated out just because we want to use it in
    # several places in the following regex.
    my $index = '(?: \[.*\] | \{.*\} )?';

    # Check for things that we don't want to quote, and if we find any of
    # them, return the string with just a font change and no quoting.
    $text =~ m{
      ^\s*
      (?:
         ( [\'\`\"] ) .* \1                             # already quoted
       | \` .* \'                                       # `quoted'
       | \$+ [\#^]? \S $index                           # special ($^Foo, $")
       | [\$\@%&*]+ \#? [:\'\w]+ $index                 # plain var or func
       | [\$\@%&*]* [:\'\w]+ (?: -> )? \(\s*[^\s,]\s*\) # 0/1-arg func call
       | [+-]? ( \d[\d.]* | \.\d+ ) (?: [eE][+-]?\d+ )? # a number
       | 0x [a-fA-F\d]+                                 # a hex constant
      )
      \s*\z
     }xo && return $text;

    # If we didn't return, go ahead and quote the text.
    return $$self{opt_alt}
        ? "``$text''"
        : "$$self{LQUOTE}$text$$self{RQUOTE}";
}

sub cmd_l {
    my ($self, $attrs, $text) = @_;
    if ($$attrs{type} eq 'url') {
        if (not defined($$attrs{to}) or $$attrs{to} eq $text) {
            return "<$text>";
        } elsif ($$self{opt_nourls}) {
            return $text;
        } else {
            return "$text <$$attrs{to}>";
        }
    } else {
        return $text;
    }
}


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
    my $parser = Pod::Text->new (@args);

    # If two arguments were given, the second argument is going to be a file
    # handle.  That means we want to call parse_from_filehandle(), which means
    # we need to turn the first argument into a file handle.  Magic open will
    # handle the <&STDIN case automagically.
    if (defined $_[1]) {
        my @fhs = @_;
        local *IN;
        unless (open (IN, $fhs[0])) {
            croak ("Can't open $fhs[0] for reading: $!\n");
            return;
        }
        $fhs[0] = \*IN;
        $parser->output_fh ($fhs[1]);
        my $retval = $parser->parse_file ($fhs[0]);
        my $fh = $parser->output_fh ();
        close $fh;
        return $retval;
    } else {
        $parser->output_fh (\*STDOUT);
        return $parser->parse_file (@_);
    }
}

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
    my $retval = $self->Pod::Simple::parse_from_file (@_);

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
    $self->parse_from_file (@_);
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


1;
__END__

