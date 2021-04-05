

package Term::ANSIColor;

use 5.006;
use strict;
use warnings;

use Carp qw(croak);
use Exporter ();


our (@EXPORT, @EXPORT_OK, %EXPORT_TAGS, @ISA, $VERSION);

our $AUTOLOAD;

BEGIN {
    $VERSION = '4.02';

    # All of the basic supported constants, used in %EXPORT_TAGS.
    my @colorlist = qw(
      CLEAR           RESET             BOLD            DARK
      FAINT           ITALIC            UNDERLINE       UNDERSCORE
      BLINK           REVERSE           CONCEALED

      BLACK           RED               GREEN           YELLOW
      BLUE            MAGENTA           CYAN            WHITE
      ON_BLACK        ON_RED            ON_GREEN        ON_YELLOW
      ON_BLUE         ON_MAGENTA        ON_CYAN         ON_WHITE

      BRIGHT_BLACK    BRIGHT_RED        BRIGHT_GREEN    BRIGHT_YELLOW
      BRIGHT_BLUE     BRIGHT_MAGENTA    BRIGHT_CYAN     BRIGHT_WHITE
      ON_BRIGHT_BLACK ON_BRIGHT_RED     ON_BRIGHT_GREEN ON_BRIGHT_YELLOW
      ON_BRIGHT_BLUE  ON_BRIGHT_MAGENTA ON_BRIGHT_CYAN  ON_BRIGHT_WHITE
    );

    # 256-color constants, used in %EXPORT_TAGS.
    ## no critic (ValuesAndExpressions::ProhibitMagicNumbers)
    my @colorlist256 = (
        (map { ("ANSI$_", "ON_ANSI$_") } 0 .. 15),
        (map { ("GREY$_", "ON_GREY$_") } 0 .. 23),
    );
    for my $r (0 .. 5) {
        for my $g (0 .. 5) {
            push @colorlist256, map { ("RGB$r$g$_", "ON_RGB$r$g$_") } 0 .. 5;
        }
    }

    # Exported symbol configuration.
    @ISA         = qw(Exporter);
    @EXPORT      = qw(color colored);
    @EXPORT_OK   = qw(uncolor colorstrip colorvalid coloralias);
    %EXPORT_TAGS = (
        constants    => \@colorlist,
        constants256 => \@colorlist256,
        pushpop      => [@colorlist, qw(PUSHCOLOR POPCOLOR LOCALCOLOR)],
    );
    Exporter::export_ok_tags('pushpop', 'constants256');
}


our $AUTOLOCAL;

our $AUTORESET;

our $EACHLINE;



our %ATTRIBUTES = (
    'clear'          => 0,
    'reset'          => 0,
    'bold'           => 1,
    'dark'           => 2,
    'faint'          => 2,
    'italic'         => 3,
    'underline'      => 4,
    'underscore'     => 4,
    'blink'          => 5,
    'reverse'        => 7,
    'concealed'      => 8,

    'black'          => 30,   'on_black'          => 40,
    'red'            => 31,   'on_red'            => 41,
    'green'          => 32,   'on_green'          => 42,
    'yellow'         => 33,   'on_yellow'         => 43,
    'blue'           => 34,   'on_blue'           => 44,
    'magenta'        => 35,   'on_magenta'        => 45,
    'cyan'           => 36,   'on_cyan'           => 46,
    'white'          => 37,   'on_white'          => 47,

    'bright_black'   => 90,   'on_bright_black'   => 100,
    'bright_red'     => 91,   'on_bright_red'     => 101,
    'bright_green'   => 92,   'on_bright_green'   => 102,
    'bright_yellow'  => 93,   'on_bright_yellow'  => 103,
    'bright_blue'    => 94,   'on_bright_blue'    => 104,
    'bright_magenta' => 95,   'on_bright_magenta' => 105,
    'bright_cyan'    => 96,   'on_bright_cyan'    => 106,
    'bright_white'   => 97,   'on_bright_white'   => 107,
);


for my $code (0 .. 15) {
    $ATTRIBUTES{"ansi$code"}    = "38;5;$code";
    $ATTRIBUTES{"on_ansi$code"} = "48;5;$code";
}

for my $r (0 .. 5) {
    for my $g (0 .. 5) {
        for my $b (0 .. 5) {
            my $code = 16 + (6 * 6 * $r) + (6 * $g) + $b;
            $ATTRIBUTES{"rgb$r$g$b"}    = "38;5;$code";
            $ATTRIBUTES{"on_rgb$r$g$b"} = "48;5;$code";
        }
    }
}

for my $n (0 .. 23) {
    my $code = $n + 232;
    $ATTRIBUTES{"grey$n"}    = "38;5;$code";
    $ATTRIBUTES{"on_grey$n"} = "48;5;$code";
}


our %ATTRIBUTES_R;
for my $attr (reverse sort keys %ATTRIBUTES) {
    $ATTRIBUTES_R{ $ATTRIBUTES{$attr} } = $attr;
}

our %ALIASES;
if (exists $ENV{ANSI_COLORS_ALIASES}) {
    my $spec = $ENV{ANSI_COLORS_ALIASES};
    $spec =~ s{\s+}{}xmsg;

    # Error reporting here is an interesting question.  Use warn rather than
    # carp because carp would report the line of the use or require, which
    # doesn't help anyone understand what's going on, whereas seeing this code
    # will be more helpful.
    ## no critic (ErrorHandling::RequireCarping)
    for my $definition (split m{,}xms, $spec) {
        my ($new, $old) = split m{=}xms, $definition, 2;
        if (!$new || !$old) {
            warn qq{Bad color mapping "$definition"};
        } else {
            my $result = eval { coloralias($new, $old) };
            if (!$result) {
                my $error = $@;
                $error =~ s{ [ ] at [ ] .* }{}xms;
                warn qq{$error in "$definition"};
            }
        }
    }
}

our @COLORSTACK;


sub AUTOLOAD {
    my ($sub, $attr) = $AUTOLOAD =~ m{ \A ([\w:]*::([[:upper:]\d_]+)) \z }xms;

    # Check if we were called with something that doesn't look like an
    # attribute.
    if (!$attr || !defined $ATTRIBUTES{ lc $attr }) {
        croak("undefined subroutine &$AUTOLOAD called");
    }

    # If colors are disabled, just return the input.  Do this without
    # installing a sub for (marginal, unbenchmarked) speed.
    if ($ENV{ANSI_COLORS_DISABLED}) {
        return join q{}, @_;
    }

    # We've untainted the name of the sub.
    $AUTOLOAD = $sub;

    # Figure out the ANSI string to set the desired attribute.
    my $escape = "\e[" . $ATTRIBUTES{ lc $attr } . 'm';

    # Save the current value of $@.  We can't just use local since we want to
    # restore it before dispatching to the newly-created sub.  (The caller may
    # be colorizing output that includes $@.)
    my $eval_err = $@;

    # Generate the constant sub, which should still recognize some of our
    # package variables.  Use string eval to avoid a dependency on
    # Sub::Install, even though it makes it somewhat less readable.
    ## no critic (BuiltinFunctions::ProhibitStringyEval)
    ## no critic (ValuesAndExpressions::ProhibitImplicitNewlines)
    my $eval_result = eval qq{
        sub $AUTOLOAD {
            if (\$ENV{ANSI_COLORS_DISABLED}) {
                return join q{}, \@_;
            } elsif (\$AUTOLOCAL && \@_) {
                return PUSHCOLOR('$escape') . join(q{}, \@_) . POPCOLOR;
            } elsif (\$AUTORESET && \@_) {
                return '$escape' . join(q{}, \@_) . "\e[0m";
            } else {
                return '$escape' . join q{}, \@_;
            }
        }
        1;
    };

    # Failure is an internal error, not a problem with the caller.
    ## no critic (ErrorHandling::RequireCarping)
    if (!$eval_result) {
        die "failed to generate constant $attr: $@";
    }

    # Restore $@.
    ## no critic (Variables::RequireLocalizedPunctuationVars)
    $@ = $eval_err;

    # Dispatch to the newly-created sub.
    ## no critic (References::ProhibitDoubleSigils)
    goto &$AUTOLOAD;
}

sub PUSHCOLOR {
    my (@text) = @_;
    my $text = join q{}, @text;

    # Extract any number of color-setting escape sequences from the start of
    # the string.
    my ($color) = $text =~ m{ \A ( (?:\e\[ [\d;]+ m)+ ) }xms;

    # If we already have a stack, append these escapes to the set from the top
    # of the stack.  This way, each position in the stack stores the complete
    # enabled colors for that stage, at the cost of some potential
    # inefficiency.
    if (@COLORSTACK) {
        $color = $COLORSTACK[-1] . $color;
    }

    # Push the color onto the stack.
    push @COLORSTACK, $color;
    return $text;
}

sub POPCOLOR {
    my (@text) = @_;
    pop @COLORSTACK;
    if (@COLORSTACK) {
        return $COLORSTACK[-1] . join q{}, @text;
    } else {
        return RESET(@text);
    }
}

sub LOCALCOLOR {
    my (@text) = @_;
    return PUSHCOLOR(join q{}, @text) . POPCOLOR();
}


sub color {
    my (@codes) = @_;
    @codes = map { split } @codes;

    # Return the empty string if colors are disabled.
    if ($ENV{ANSI_COLORS_DISABLED}) {
        return q{};
    }

    # Build the attribute string from semicolon-separated numbers.
    my $attribute = q{};
    for my $code (@codes) {
        $code = lc $code;
        if (defined $ATTRIBUTES{$code}) {
            $attribute .= $ATTRIBUTES{$code} . q{;};
        } elsif (defined $ALIASES{$code}) {
            $attribute .= $ALIASES{$code} . q{;};
        } else {
            croak("Invalid attribute name $code");
        }
    }

    # We added one too many semicolons for simplicity.  Remove the last one.
    chop $attribute;

    # Return undef if there were no attributes.
    return ($attribute ne q{}) ? "\e[${attribute}m" : undef;
}

sub uncolor {
    my (@escapes) = @_;
    my (@nums, @result);

    # Walk the list of escapes and build a list of attribute numbers.
    for my $escape (@escapes) {
        $escape =~ s{ \A \e\[ }{}xms;
        $escape =~ s{ m \z }   {}xms;
        my ($attrs) = $escape =~ m{ \A ((?:\d+;)* \d*) \z }xms;
        if (!defined $attrs) {
            croak("Bad escape sequence $escape");
        }

        # Pull off 256-color codes (38;5;n or 48;5;n) as a unit.
        push @nums, $attrs =~ m{ ( 0*[34]8;0*5;\d+ | \d+ ) (?: ; | \z ) }xmsg;
    }

    # Now, walk the list of numbers and convert them to attribute names.
    # Strip leading zeroes from any of the numbers.  (xterm, at least, allows
    # leading zeroes to be added to any number in an escape sequence.)
    for my $num (@nums) {
        $num =~ s{ ( \A | ; ) 0+ (\d) }{$1$2}xmsg;
        my $name = $ATTRIBUTES_R{$num};
        if (!defined $name) {
            croak("No name for escape sequence $num");
        }
        push @result, $name;
    }

    # Return the attribute names.
    return @result;
}

sub colored {
    my ($first, @rest) = @_;
    my ($string, @codes);
    if (ref($first) && ref($first) eq 'ARRAY') {
        @codes = @{$first};
        $string = join q{}, @rest;
    } else {
        $string = $first;
        @codes  = @rest;
    }

    # Return the string unmolested if colors are disabled.
    if ($ENV{ANSI_COLORS_DISABLED}) {
        return $string;
    }

    # Find the attribute string for our colors.
    my $attr = color(@codes);

    # If $EACHLINE is defined, split the string on line boundaries, suppress
    # empty segments, and then colorize each of the line sections.
    if (defined $EACHLINE) {
        my @text = map { ($_ ne $EACHLINE) ? $attr . $_ . "\e[0m" : $_ }
          grep { length($_) > 0 }
          split m{ (\Q$EACHLINE\E) }xms, $string;
        return join q{}, @text;
    } else {
        return $attr . $string . "\e[0m";
    }
}

sub coloralias {
    my ($alias, $color) = @_;
    if (!defined $color) {
        if (!exists $ALIASES{$alias}) {
            return;
        } else {
            return $ATTRIBUTES_R{ $ALIASES{$alias} };
        }
    }
    if ($alias !~ m{ \A [\w._-]+ \z }xms) {
        croak(qq{Invalid alias name "$alias"});
    } elsif ($ATTRIBUTES{$alias}) {
        croak(qq{Cannot alias standard color "$alias"});
    } elsif (!exists $ATTRIBUTES{$color}) {
        croak(qq{Invalid attribute name "$color"});
    }
    $ALIASES{$alias} = $ATTRIBUTES{$color};
    return $color;
}

sub colorstrip {
    my (@string) = @_;
    for my $string (@string) {
        $string =~ s{ \e\[ [\d;]* m }{}xmsg;
    }
    return wantarray ? @string : join q{}, @string;
}

sub colorvalid {
    my (@codes) = @_;
    @codes = map { split q{ }, lc $_ } @codes;
    for my $code (@codes) {
        if (!defined $ATTRIBUTES{$code} && !defined $ALIASES{$code}) {
            return;
        }
    }
    return 1;
}


1;
__END__

