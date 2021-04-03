package TAP::Parser::Iterator;

use strict;
use warnings;

use base 'TAP::Object';


our $VERSION = '3.35';


sub next {
    my $self = shift;
    my $line = $self->next_raw;

    # vms nit:  When encountering 'not ok', vms often has the 'not' on a line
    # by itself:
    #   not
    #   ok 1 - 'I hate VMS'
    if ( defined($line) and $line =~ /^\s*not\s*$/ ) {
        $line .= ( $self->next_raw || '' );
    }

    return $line;
}

sub next_raw {
    require Carp;
    my $msg = Carp::longmess('abstract method called directly!');
    $_[0]->_croak($msg);
}


sub handle_unicode { }


sub get_select_handles {
    return;
}


sub wait {
    require Carp;
    my $msg = Carp::longmess('abstract method called directly!');
    $_[0]->_croak($msg);
}

sub exit {
    require Carp;
    my $msg = Carp::longmess('abstract method called directly!');
    $_[0]->_croak($msg);
}

1;


