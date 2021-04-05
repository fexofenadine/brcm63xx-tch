package TAP::Parser::SourceHandler::RawTAP;

use strict;
use warnings;

use TAP::Parser::IteratorFactory ();
use TAP::Parser::Iterator::Array ();

use base 'TAP::Parser::SourceHandler';

TAP::Parser::IteratorFactory->register_handler(__PACKAGE__);


our $VERSION = '3.35';


sub can_handle {
    my ( $class, $src ) = @_;
    my $meta = $src->meta;

    return 0 if $meta->{file};
    if ( $meta->{is_scalar} ) {
        return 0 unless $meta->{has_newlines};
        return 0.9 if ${ $src->raw } =~ /\d\.\.\d/;
        return 0.7 if ${ $src->raw } =~ /ok/;
        return 0.3;
    }
    elsif ( $meta->{is_array} ) {
        return 0.5;
    }
    return 0;
}


sub make_iterator {
    my ( $class, $src ) = @_;
    my $meta = $src->meta;

    my $tap_array;
    if ( $meta->{is_scalar} ) {
        $tap_array = [ split "\n" => ${ $src->raw } ];
    }
    elsif ( $meta->{is_array} ) {
        $tap_array = $src->raw;
    }

    $class->_croak('No raw TAP found in $source->raw')
      unless scalar $tap_array;

    return TAP::Parser::Iterator::Array->new($tap_array);
}

1;

