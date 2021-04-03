package TAP::Parser::SourceHandler::Executable;

use strict;
use warnings;

use TAP::Parser::IteratorFactory   ();
use TAP::Parser::Iterator::Process ();

use base 'TAP::Parser::SourceHandler';

TAP::Parser::IteratorFactory->register_handler(__PACKAGE__);


our $VERSION = '3.30';


sub can_handle {
    my ( $class, $src ) = @_;
    my $meta = $src->meta;

    if ( $meta->{is_file} ) {
        my $file = $meta->{file};

        return 0.85 if $file->{execute} && $file->{binary};
        return 0.8 if $file->{lc_ext} eq '.bat';
        return 0.25 if $file->{execute};
    }
    elsif ( $meta->{is_hash} ) {
        return 0.9 if $src->raw->{exec};
    }

    return 0;
}


sub make_iterator {
    my ( $class, $source ) = @_;
    my $meta = $source->meta;

    my @command;
    if ( $meta->{is_hash} ) {
        @command = @{ $source->raw->{exec} || [] };
    }
    elsif ( $meta->{is_scalar} ) {
        @command = ${ $source->raw };
    }
    elsif ( $meta->{is_array} ) {
        @command = @{ $source->raw };
    }

    $class->_croak('No command found in $source->raw!') unless @command;

    $class->_autoflush( \*STDOUT );
    $class->_autoflush( \*STDERR );

    push @command, @{ $source->test_args || [] };

    return $class->iterator_class->new(
        {   command => \@command,
            merge   => $source->merge
        }
    );
}


use constant iterator_class => 'TAP::Parser::Iterator::Process';

sub _autoflush {
    my ( $class, $flushed ) = @_;
    my $old_fh = select $flushed;
    $| = 1;
    select $old_fh;
}

1;

