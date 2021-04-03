package locale;

our $VERSION = '1.03';
use Config;

$Carp::Internal{ (__PACKAGE__) } = 1;



$locale::hint_bits = 0x4;
$locale::not_chars_hint_bits = 0x10;

sub import {
    shift;  # should be 'locale'; not checked

    my $found_not_chars = 0;
    while (defined (my $arg = shift)) {
        if ($arg eq ":not_characters") {
            $^H |= $locale::not_chars_hint_bits;

            # This form of the pragma overrides the other
            $^H &= ~$locale::hint_bits;
            $found_not_chars = 1;
        }
        else {
            require Carp;
            Carp::croak("Unknown parameter '$arg' to 'use locale'");
        }
    }

    # Use the plain form if not doing the :not_characters one.
    $^H |= $locale::hint_bits unless $found_not_chars;
}

sub unimport {
    $^H &= ~($locale::hint_bits|$locale::not_chars_hint_bits);
}

1;
