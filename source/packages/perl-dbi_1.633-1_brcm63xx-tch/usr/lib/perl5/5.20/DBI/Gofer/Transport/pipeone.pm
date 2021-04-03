package DBI::Gofer::Transport::pipeone;


use strict;
use warnings;

use DBI::Gofer::Execute;

use base qw(DBI::Gofer::Transport::Base Exporter);

our $VERSION = "0.012537";

our @EXPORT = qw(run_one_stdio);

my $executor = DBI::Gofer::Execute->new();

sub run_one_stdio {

    my $transport = DBI::Gofer::Transport::pipeone->new();

    my $frozen_request = do { local $/; <STDIN> };

    my $response = $executor->execute_request( $transport->thaw_request($frozen_request) );

    my $frozen_response = $transport->freeze_response($response);

    print $frozen_response;

    # no point calling $executor->update_stats(...) for pipeONE
}

1;
__END__


