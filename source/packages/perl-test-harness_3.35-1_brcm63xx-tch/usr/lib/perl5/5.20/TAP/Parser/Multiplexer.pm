package TAP::Parser::Multiplexer;

use strict;
use warnings;

use IO::Select;

use base 'TAP::Object';

use constant IS_WIN32 => $^O =~ /^(MS)?Win32$/;
use constant IS_VMS => $^O eq 'VMS';
use constant SELECT_OK => !( IS_VMS || IS_WIN32 );


our $VERSION = '3.35';



sub _initialize {
    my $self = shift;
    $self->{select} = IO::Select->new;
    $self->{avid}   = [];                # Parsers that can't select
    $self->{count}  = 0;
    return $self;
}



sub add {
    my ( $self, $parser, $stash ) = @_;

    if ( SELECT_OK && ( my @handles = $parser->get_select_handles ) ) {
        my $sel = $self->{select};

        # We have to turn handles into file numbers here because by
        # the time we want to remove them from our IO::Select they
        # will already have been closed by the iterator.
        my @filenos = map { fileno $_ } @handles;
        for my $h (@handles) {
            $sel->add( [ $h, $parser, $stash, @filenos ] );
        }

        $self->{count}++;
    }
    else {
        push @{ $self->{avid} }, [ $parser, $stash ];
    }
}


sub parsers {
    my $self = shift;
    return $self->{count} + scalar @{ $self->{avid} };
}

sub _iter {
    my $self = shift;

    my $sel   = $self->{select};
    my $avid  = $self->{avid};
    my @ready = ();

    return sub {

        # Drain all the non-selectable parsers first
        if (@$avid) {
            my ( $parser, $stash ) = @{ $avid->[0] };
            my $result = $parser->next;
            shift @$avid unless defined $result;
            return ( $parser, $stash, $result );
        }

        unless (@ready) {
            return unless $sel->count;
            @ready = $sel->can_read;
        }

        my ( $h, $parser, $stash, @handles ) = @{ shift @ready };
        my $result = $parser->next;

        unless ( defined $result ) {
            $sel->remove(@handles);
            $self->{count}--;

            # Force another can_read - we may now have removed a handle
            # thought to have been ready.
            @ready = ();
        }

        return ( $parser, $stash, $result );
    };
}


sub next {
    my $self = shift;
    return ( $self->{_iter} ||= $self->_iter )->();
}


1;
