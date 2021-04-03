

package Pod::Text::Termcap;

require 5.004;

use Pod::Text ();
use POSIX ();
use Term::Cap;

use strict;
use vars qw(@ISA $VERSION);

@ISA = qw(Pod::Text);

$VERSION = '2.08';


sub new {
    my ($self, @args) = @_;
    my ($ospeed, $term, $termios);
    $self = $self->SUPER::new (@args);

    # $ENV{HOME} is usually not set on Windows.  The default Term::Cap path
    # may not work on Solaris.
    my $home = exists $ENV{HOME} ? "$ENV{HOME}/.termcap:" : '';
    $ENV{TERMPATH} = $home . '/etc/termcap:/usr/share/misc/termcap'
                           . ':/usr/share/lib/termcap';

    # Fall back on a hard-coded terminal speed if POSIX::Termios isn't
    # available (such as on VMS).
    eval { $termios = POSIX::Termios->new };
    if ($@) {
        $ospeed = 9600;
    } else {
        $termios->getattr;
        $ospeed = $termios->getospeed || 9600;
    }

    # Fall back on the ANSI escape sequences if Term::Cap doesn't work.
    eval { $term = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed } };
    $$self{BOLD} = $$term{_md} || "\e[1m";
    $$self{UNDL} = $$term{_us} || "\e[4m";
    $$self{NORM} = $$term{_me} || "\e[m";

    unless (defined $$self{width}) {
        $$self{opt_width} = $ENV{COLUMNS} || $$term{_co} || 80;
        $$self{opt_width} -= 2;
    }

    return $self;
}

sub cmd_head1 {
    my ($self, $attrs, $text) = @_;
    $text =~ s/\s+$//;
    $self->SUPER::cmd_head1 ($attrs, "$$self{BOLD}$text$$self{NORM}");
}

sub cmd_head2 {
    my ($self, $attrs, $text) = @_;
    $text =~ s/\s+$//;
    $self->SUPER::cmd_head2 ($attrs, "$$self{BOLD}$text$$self{NORM}");
}

sub cmd_b { my $self = shift; return "$$self{BOLD}$_[1]$$self{NORM}" }
sub cmd_i { my $self = shift; return "$$self{UNDL}$_[1]$$self{NORM}" }

sub output_code {
    my ($self, $code) = @_;
    $self->output ($$self{BOLD} . $code . $$self{NORM});
}

sub strip_format {
    my ($self, $text) = @_;
    $text =~ s/\Q$$self{BOLD}//g;
    $text =~ s/\Q$$self{UNDL}//g;
    $text =~ s/\Q$$self{NORM}//g;
    return $text;
}

sub wrap {
    my $self = shift;
    local $_ = shift;
    my $output = '';
    my $spaces = ' ' x $$self{MARGIN};
    my $width = $$self{opt_width} - $$self{MARGIN};

    # $codes matches a single special sequence.  $char matches any number of
    # special sequences preceding a single character other than a newline.
    # We have to do $shortchar and $longchar in variables because the
    # construct ${char}{0,$width} didn't do the right thing until Perl 5.8.x.
    my $codes = "(?:\Q$$self{BOLD}\E|\Q$$self{UNDL}\E|\Q$$self{NORM}\E)";
    my $char = "(?:$codes*[^\\n])";
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
    return $output;
}


1;
__END__

