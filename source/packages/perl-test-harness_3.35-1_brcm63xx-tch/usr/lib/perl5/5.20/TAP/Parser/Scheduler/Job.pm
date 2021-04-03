package TAP::Parser::Scheduler::Job;

use strict;
use warnings;
use Carp;


our $VERSION = '3.35';


sub new {
    my ( $class, $name, $desc, @ctx ) = @_;
    return bless {
        filename    => $name,
        description => $desc,
        @ctx ? ( context => \@ctx ) : (),
    }, $class;
}


sub on_finish {
    my ( $self, $cb ) = @_;
    $self->{on_finish} = $cb;
}


sub finish {
    my $self = shift;
    if ( my $cb = $self->{on_finish} ) {
        $cb->($self);
    }
}


sub filename    { shift->{filename} }
sub description { shift->{description} }
sub context     { @{ shift->{context} || [] } }


sub as_array_ref {
    my $self = shift;
    return [ $self->filename, $self->description, $self->{context} ||= [] ];
}


sub is_spinner {0}

1;
