package TAP::Parser::SourceHandler::File;

use strict;
use warnings;

use TAP::Parser::IteratorFactory  ();
use TAP::Parser::Iterator::Stream ();

use base 'TAP::Parser::SourceHandler';

TAP::Parser::IteratorFactory->register_handler(__PACKAGE__);


our $VERSION = '3.30';


sub can_handle {
    my ( $class, $src ) = @_;
    my $meta   = $src->meta;
    my $config = $src->config_for($class);

    return 0 unless $meta->{is_file};
    my $file = $meta->{file};
    return 0.9 if $file->{lc_ext} eq '.tap';

    if ( my $exts = $config->{extensions} ) {
        return 0.9 if grep { lc($_) eq $file->{lc_ext} } @$exts;
    }

    return 0;
}


sub make_iterator {
    my ( $class, $source ) = @_;

    $class->_croak('$source->raw must be a scalar ref')
      unless $source->meta->{is_scalar};

    my $file = ${ $source->raw };
    my $fh;
    open( $fh, '<', $file )
      or $class->_croak("error opening TAP source file '$file': $!");
    return $class->iterator_class->new($fh);
}


use constant iterator_class => 'TAP::Parser::Iterator::Stream';

1;

__END__

