package TAP::Parser::IteratorFactory;

use strict;
use warnings;

use Carp qw( confess );
use File::Basename qw( fileparse );

use base 'TAP::Object';

use constant handlers => [];


our $VERSION = '3.30';


sub _initialize {
    my ( $self, $config ) = @_;
    $self->config( $config || {} )->load_handlers;
    return $self;
}


sub register_handler {
    my ( $class, $dclass ) = @_;

    confess("$dclass must implement can_handle & make_iterator methods!")
      unless UNIVERSAL::can( $dclass, 'can_handle' )
          && UNIVERSAL::can( $dclass, 'make_iterator' );

    my $handlers = $class->handlers;
    push @{$handlers}, $dclass
      unless grep { $_ eq $dclass } @{$handlers};

    return $class;
}



sub config {
    my $self = shift;
    return $self->{config} unless @_;
    unless ( 'HASH' eq ref $_[0] ) {
        $self->_croak('Argument to &config must be a hash reference');
    }
    $self->{config} = shift;
    return $self;
}

sub _last_handler {
    my $self = shift;
    return $self->{last_handler} unless @_;
    $self->{last_handler} = shift;
    return $self;
}

sub _testing {
    my $self = shift;
    return $self->{testing} unless @_;
    $self->{testing} = shift;
    return $self;
}



sub load_handlers {
    my ($self) = @_;
    for my $handler ( keys %{ $self->config } ) {
        my $sclass = $self->_load_handler($handler);

        # TODO: store which class we loaded anywhere?
    }
    return $self;
}

sub _load_handler {
    my ( $self, $handler ) = @_;

    my @errors;
    for my $dclass ( "TAP::Parser::SourceHandler::$handler", $handler ) {
        return $dclass
          if UNIVERSAL::can( $dclass, 'can_handle' )
              && UNIVERSAL::can( $dclass, 'make_iterator' );

        eval "use $dclass";
        if ( my $e = $@ ) {
            push @errors, $e;
            next;
        }

        return $dclass
          if UNIVERSAL::can( $dclass, 'can_handle' )
              && UNIVERSAL::can( $dclass, 'make_iterator' );
        push @errors,
          "handler '$dclass' does not implement can_handle & make_iterator";
    }

    $self->_croak(
        "Cannot load handler '$handler': " . join( "\n", @errors ) );
}



sub make_iterator {
    my ( $self, $source ) = @_;

    $self->_croak('no raw source defined!') unless defined $source->raw;

    $source->config( $self->config )->assemble_meta;

    # is the raw source already an object?
    return $source->raw
      if ( $source->meta->{is_object}
        && UNIVERSAL::isa( $source->raw, 'TAP::Parser::SourceHandler' ) );

    # figure out what kind of source it is
    my $sd_class = $self->detect_source($source);
    $self->_last_handler($sd_class);

    return if $self->_testing;

    # create it
    my $iterator = $sd_class->make_iterator($source);

    return $iterator;
}


sub detect_source {
    my ( $self, $source ) = @_;

    confess('no raw source ref defined!') unless defined $source->raw;

    # find a list of handlers that can handle this source:
    my %handlers;
    for my $dclass ( @{ $self->handlers } ) {
        my $confidence = $dclass->can_handle($source);

        # warn "handler: $dclass: $confidence\n";
        $handlers{$dclass} = $confidence if $confidence;
    }

    if ( !%handlers ) {

        # use Data::Dump qw( pp );
        # warn pp( $meta );

        # error: can't detect source
        my $raw_source_short = substr( ${ $source->raw }, 0, 50 );
        confess("Cannot detect source of '$raw_source_short'!");
        return;
    }

    # if multiple handlers can handle it, choose the most confident one
    my @handlers = (
        map    {$_}
          sort { $handlers{$a} cmp $handlers{$b} }
          keys %handlers
    );

    # this is really useful for debugging handlers:
    if ( $ENV{TAP_HARNESS_SOURCE_FACTORY_VOTES} ) {
        warn(
            "votes: ",
            join( ', ', map {"$_: $handlers{$_}"} @handlers ),
            "\n"
        );
    }

    # return 1st
    return pop @handlers;
}

1;

__END__


