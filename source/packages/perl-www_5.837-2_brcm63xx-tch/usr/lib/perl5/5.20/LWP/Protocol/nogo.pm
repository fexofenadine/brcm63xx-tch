package LWP::Protocol::nogo;

use strict;
use vars qw(@ISA);
require HTTP::Response;
require HTTP::Status;
require LWP::Protocol;
@ISA = qw(LWP::Protocol);

sub request {
    my($self, $request) = @_;
    my $scheme = $request->uri->scheme;
    
    return HTTP::Response->new(
      &HTTP::Status::RC_INTERNAL_SERVER_ERROR,
      "Access to \'$scheme\' URIs has been disabled"
    );
}
1;
