package TAP::Base;

use strict;
use warnings;

use base 'TAP::Object';


our $VERSION = '3.35';

use constant GOT_TIME_HIRES => do {
    eval 'use Time::HiRes qw(time);';
    $@ ? 0 : 1;
};


sub _initialize {
    my ( $self, $arg_for, $ok_callback ) = @_;

    my %ok_map = map { $_ => 1 } @$ok_callback;

    $self->{ok_callbacks} = \%ok_map;

    if ( my $cb = delete $arg_for->{callbacks} ) {
        while ( my ( $event, $callback ) = each %$cb ) {
            $self->callback( $event, $callback );
        }
    }

    return $self;
}


sub callback {
    my ( $self, $event, $callback ) = @_;

    my %ok_map = %{ $self->{ok_callbacks} };

    $self->_croak('No callbacks may be installed')
      unless %ok_map;

    $self->_croak( "Callback $event is not supported. Valid callbacks are "
          . join( ', ', sort keys %ok_map ) )
      unless exists $ok_map{$event};

    push @{ $self->{code_for}{$event} }, $callback;

    return;
}

sub _has_callbacks {
    my $self = shift;
    return keys %{ $self->{code_for} } != 0;
}

sub _callback_for {
    my ( $self, $event ) = @_;
    return $self->{code_for}{$event};
}

sub _make_callback {
    my $self  = shift;
    my $event = shift;

    my $cb = $self->_callback_for($event);
    return unless defined $cb;
    return map { $_->(@_) } @$cb;
}


sub get_time { return time() }


sub time_is_hires { return GOT_TIME_HIRES }


sub get_times { return [ times() ] }

1;
