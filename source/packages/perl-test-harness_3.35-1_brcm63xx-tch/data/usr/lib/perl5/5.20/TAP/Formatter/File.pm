package TAP::Formatter::File;

use strict;
use warnings;
use TAP::Formatter::File::Session;
use POSIX qw(strftime);

use base 'TAP::Formatter::Base';


our $VERSION = '3.35';


sub open_test {
    my ( $self, $test, $parser ) = @_;

    my $session = TAP::Formatter::File::Session->new(
        {   name      => $test,
            formatter => $self,
            parser    => $parser,
        }
    );

    $session->header;

    return $session;
}

sub _should_show_count {
    return 0;
}

1;
