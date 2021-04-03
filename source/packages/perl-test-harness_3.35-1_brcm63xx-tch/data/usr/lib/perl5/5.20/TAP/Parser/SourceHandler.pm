package TAP::Parser::SourceHandler;

use strict;
use warnings;

use TAP::Parser::Iterator ();
use base 'TAP::Object';


our $VERSION = '3.35';


sub can_handle {
    my ( $class, $args ) = @_;
    $class->_croak(
        "Abstract method 'can_handle' not implemented for $class!");
    return;
}


sub make_iterator {
    my ( $class, $args ) = @_;
    $class->_croak(
        "Abstract method 'make_iterator' not implemented for $class!");
    return;
}
1;

__END__


