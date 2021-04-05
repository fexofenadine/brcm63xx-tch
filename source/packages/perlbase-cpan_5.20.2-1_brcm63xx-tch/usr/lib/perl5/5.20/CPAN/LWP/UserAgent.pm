package CPAN::LWP::UserAgent;
use strict;
use vars qw(@ISA $USER $PASSWD $SETUPDONE);
use CPAN::HTTP::Credentials;

$CPAN::LWP::UserAgent::VERSION = $CPAN::LWP::UserAgent::VERSION = "1.9601";


sub config {
    return if $SETUPDONE;
    if ($CPAN::META->has_usable('LWP::UserAgent')) {
        require LWP::UserAgent;
        @ISA = qw(Exporter LWP::UserAgent); ## no critic
        $SETUPDONE++;
    } else {
        $CPAN::Frontend->mywarn("  LWP::UserAgent not available\n");
    }
}

sub get_basic_credentials {
    my($self, $realm, $uri, $proxy) = @_;
    if ( $proxy ) {
        return CPAN::HTTP::Credentials->get_proxy_credentials();
    } else {
        return CPAN::HTTP::Credentials->get_non_proxy_credentials();
    }
}

sub no_proxy {
    my ( $self, $no_proxy ) = @_;
    return $self->SUPER::no_proxy( split(',',$no_proxy) );
}




sub mirror {
    my($self,$url,$aslocal) = @_;
    my $result = $self->SUPER::mirror($url,$aslocal);
    if ($result->code == 407) {
        CPAN::HTTP::Credentials->clear_credentials;
        $result = $self->SUPER::mirror($url,$aslocal);
    }
    $result;
}

1;
