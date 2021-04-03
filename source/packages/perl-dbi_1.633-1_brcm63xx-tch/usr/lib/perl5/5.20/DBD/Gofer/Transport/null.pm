package DBD::Gofer::Transport::null;


use strict;
use warnings;

use base qw(DBD::Gofer::Transport::Base);

use DBI::Gofer::Execute;

our $VERSION = "0.010088";

__PACKAGE__->mk_accessors(qw(
    pending_response
    transmit_count
));

my $executor = DBI::Gofer::Execute->new();


sub transmit_request_by_transport {
    my ($self, $request) = @_;
    $self->transmit_count( ($self->transmit_count()||0) + 1 ); # just for tests

    my $frozen_request = $self->freeze_request($request);

    # ...
    # the request is magically transported over to ... ourselves
    # ...

    my $response = $executor->execute_request( $self->thaw_request($frozen_request, undef, 1) );

    # put response 'on the shelf' ready for receive_response()
    $self->pending_response( $response );

    return undef;
}


sub receive_response_by_transport {
    my $self = shift;

    my $response = $self->pending_response;

    my $frozen_response = $self->freeze_response($response, undef, 1);

    # ...
    # the response is magically transported back to ... ourselves
    # ...

    return $self->thaw_response($frozen_response);
}


1;
__END__

