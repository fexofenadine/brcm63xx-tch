

package Pod::Text::Color;

require 5.004;

use Pod::Text ();
use Term::ANSIColor qw(colored);

use strict;
use vars qw(@ISA $VERSION);

@ISA = qw(Pod::Text);

$VERSION = '2.07';


sub cmd_head1 {
    my ($self, $attrs, $text) = @_;
    $text =~ s/\s+$//;
    $self->SUPER::cmd_head1 ($attrs, colored ($text, 'bold'));
}

sub cmd_head2 {
    my ($self, $attrs, $text) = @_;
    $text =~ s/\s+$//;
    $self->SUPER::cmd_head2 ($attrs, colored ($text, 'bold'));
}

sub cmd_b { return colored ($_[2], 'bold')   }
sub cmd_f { return colored ($_[2], 'cyan')   }
sub cmd_i { return colored ($_[2], 'yellow') }

sub output_code {
    my ($self, $code) = @_;
    $code = colored ($code, 'green');
    $self->output ($code);
}

sub strip_format {
    my ($self, $text) = @_;
    $text =~ s/\e\[[\d;]*m//g;
    return $text;
}

sub wrap {
    my $self = shift;
    local $_ = shift;
    my $output = '';
    my $spaces = ' ' x $$self{MARGIN};
    my $width = $$self{opt_width} - $$self{MARGIN};

    # We have to do $shortchar and $longchar in variables because the
    # construct ${char}{0,$width} didn't do the right thing until Perl 5.8.x.
    my $char = '(?:(?:\e\[[\d;]+m)*[^\n])';
    my $shortchar = $char . "{0,$width}";
    my $longchar = $char . "{$width}";
    while (length > $width) {
        if (s/^($shortchar)\s+// || s/^($longchar)//) {
            $output .= $spaces . $1 . "\n";
        } else {
            last;
        }
    }
    $output .= $spaces . $_;
    $output =~ s/\s+$/\n\n/;
    $output;
}


1;
__END__

