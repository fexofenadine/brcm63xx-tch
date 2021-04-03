package TAP::Formatter::Color;

use strict;
use warnings;

use constant IS_WIN32 => ( $^O =~ /^(MS)?Win32$/ );

use base 'TAP::Object';

my $NO_COLOR;

BEGIN {
    $NO_COLOR = 0;

    if (IS_WIN32) {
        eval 'use Win32::Console';
        if ($@) {
            $NO_COLOR = $@;
        }
        else {
            my $console = Win32::Console->new( STD_OUTPUT_HANDLE() );

            # eval here because we might not know about these variables
            my $fg = eval '$FG_LIGHTGRAY';
            my $bg = eval '$BG_BLACK';

            *set_color = sub {
                my ( $self, $output, $color ) = @_;

                my $var;
                if ( $color eq 'reset' ) {
                    $fg = eval '$FG_LIGHTGRAY';
                    $bg = eval '$BG_BLACK';
                }
                elsif ( $color =~ /^on_(.+)$/ ) {
                    $bg = eval '$BG_' . uc($1);
                }
                else {
                    $fg = eval '$FG_' . uc($color);
                }

                # In case of colors that aren't defined
                $self->set_color('reset')
                  unless defined $bg && defined $fg;

                $console->Attr( $bg | $fg );
            };
        }
    }
    else {
        eval 'use Term::ANSIColor';
        if ($@) {
            $NO_COLOR = $@;
        }
        else {
            *set_color = sub {
                my ( $self, $output, $color ) = @_;
                $output->( color($color) );
            };
        }
    }

    if ($NO_COLOR) {
        *set_color = sub { };
    }
}


our $VERSION = '3.30';



sub _initialize {
    my $self = shift;

    if ($NO_COLOR) {

        # shorten that message a bit
        ( my $error = $NO_COLOR ) =~ s/ in \@INC .*//s;
        warn "Note: Cannot run tests in color: $error\n";
        return;    # abort object construction
    }

    return $self;
}



sub can_color {
    return !$NO_COLOR;
}


1;
