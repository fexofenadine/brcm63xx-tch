package TAP::Parser::SourceHandler::Handle;

use strict;
use warnings;

use TAP::Parser::IteratorFactory  ();
use TAP::Parser::Iterator::Stream ();

use base 'TAP::Parser::SourceHandler';

TAP::Parser::IteratorFactory->register_handler(__PACKAGE__);


our $VERSION = '3.30';


sub can_handle {
    my ( $class, $src ) = @_;
    my $meta = $src->meta;

    return 0.9
      if $meta->{is_object}
          && UNIVERSAL::isa( $src->raw, 'IO::Handle' );

    return 0.8 if $meta->{is_glob};

    return 0;
}


sub make_iterator {
    my ( $class, $source ) = @_;

    $class->_croak('$source->raw must be a glob ref or an IO::Handle')
      unless $source->meta->{is_glob}
          || UNIVERSAL::isa( $source->raw, 'IO::Handle' );

    return $class->iterator_class->new( $source->raw );
}


use constant iterator_class => 'TAP::Parser::Iterator::Stream';

1;

