package CGI::Fast;
use strict;
use if $] >= 5.019, 'deprecate';

local $^W = 1;




$CGI::Fast::VERSION='1.10';

use CGI;
use FCGI;
use vars qw(
    @ISA
    $ignore
);
@ISA = ('CGI');

while (($ignore) = each %ENV) { }

sub save_request {
    # no-op
}

use vars qw($Ext_Request);
BEGIN {
    # If ENV{FCGI_SOCKET_PATH} is given, explicitly open the socket.
    if ($ENV{FCGI_SOCKET_PATH}) {
        my $path    = $ENV{FCGI_SOCKET_PATH};
        my $backlog = $ENV{FCGI_LISTEN_QUEUE} || 100;
        my $socket  = FCGI::OpenSocket( $path, $backlog );
        $Ext_Request = FCGI::Request( \*STDIN, \*STDOUT, \*STDERR,
                    \%ENV, $socket, 1 );
    }
    else {
        $Ext_Request = FCGI::Request();
    }
}

sub new {
     my ($self, $initializer, @param) = @_;
     unless (defined $initializer) {
         return undef unless $Ext_Request->Accept() >= 0;
     }
     CGI->_reset_globals;
     $self->_setup_symbols(@CGI::SAVED_SYMBOLS) if @CGI::SAVED_SYMBOLS;
     return $CGI::Q = $self->SUPER::new($initializer, @param);
}

1;

