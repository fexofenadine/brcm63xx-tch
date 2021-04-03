

package Pod::Text::Overstrike;

require 5.004;

use Pod::Text ();

use strict;
use vars qw(@ISA $VERSION);

@ISA = qw(Pod::Text);

$VERSION = '2.05';


sub cmd_head1 {
    my ($self, $attrs, $text) = @_;
    $text =~ s/\s+$//;
    $text = $self->strip_format ($text);
    $text =~ s/(.)/$1\b$1/g;
    return $self->SUPER::cmd_head1 ($attrs, $text);
}

sub cmd_head2 {
    my ($self, $attrs, $text) = @_;
    $text =~ s/\s+$//;
    $text = $self->strip_format ($text);
    $text =~ s/(.)/$1\b$1/g;
    return $self->SUPER::cmd_head2 ($attrs, $text);
}

sub cmd_head3 {
    my ($self, $attrs, $text) = @_;
    $text =~ s/\s+$//;
    $text = $self->strip_format ($text);
    $text =~ s/(.)/_\b$1/g;
    return $self->SUPER::cmd_head3 ($attrs, $text);
}

sub cmd_head4 {
    my ($self, $attrs, $text) = @_;
    $text =~ s/\s+$//;
    $text = $self->strip_format ($text);
    $text =~ s/(.)/_\b$1/g;
    return $self->SUPER::cmd_head4 ($attrs, $text);
}

sub heading {
    my ($self, $text, $indent, $marker) = @_;
    $self->item ("\n\n") if defined $$self{ITEM};
    $text .= "\n" if $$self{opt_loose};
    my $margin = ' ' x ($$self{opt_margin} + $indent);
    $self->output ($margin . $text . "\n");
    return '';
}

sub cmd_b { local $_ = $_[0]->strip_format ($_[2]); s/(.)/$1\b$1/g; $_ }
sub cmd_f { local $_ = $_[0]->strip_format ($_[2]); s/(.)/_\b$1/g; $_ }
sub cmd_i { local $_ = $_[0]->strip_format ($_[2]); s/(.)/_\b$1/g; $_ }

sub output_code {
    my ($self, $code) = @_;
    $code =~ s/(.)/$1\b$1/g;
    $self->output ($code);
}

sub strip_format {
    my ($self, $text) = @_;
    $text =~ s/(.)[\b]\1/$1/g;
    $text =~ s/_[\b]//g;
    return $text;
}

sub wrap {
    my $self = shift;
    local $_ = shift;
    my $output = '';
    my $spaces = ' ' x $$self{MARGIN};
    my $width = $$self{opt_width} - $$self{MARGIN};
    while (length > $width) {
        # This regex represents a single character, that's possibly underlined
        # or in bold (in which case, it's three characters; the character, a
        # backspace, and a character).  Use [^\n] rather than . to protect
        # against odd settings of $*.
        my $char = '(?:[^\n][\b])?[^\n]';
        if (s/^((?>$char){0,$width})(?:\Z|\s+)//) {
            $output .= $spaces . $1 . "\n";
        } else {
            last;
        }
    }
    $output .= $spaces . $_;
    $output =~ s/\s+$/\n\n/;
    return $output;
}


1;
__END__

