package DBD::Gofer::Transport::stream;


use strict;
use warnings;

use Carp;

use base qw(DBD::Gofer::Transport::pipeone);

our $VERSION = "0.014599";

__PACKAGE__->mk_accessors(qw(
    go_persist
));

my $persist_all = 5;
my %persist;


sub _connection_key {
    my ($self) = @_;
    return join "~", $self->go_url||"", @{ $self->go_perl || [] };
}


sub _connection_get {
    my ($self) = @_;

    my $persist = $self->go_persist; # = 0 can force non-caching
    $persist = $persist_all if not defined $persist;
    my $key = ($persist) ? $self->_connection_key : '';
    if ($persist{$key} && $self->_connection_check($persist{$key})) {
        $self->trace_msg("reusing persistent connection $key\n",0) if $self->trace >= 1;
        return $persist{$key};
    }

    my $connection = $self->_make_connection;

    if ($key) {
        %persist = () if keys %persist > $persist_all; # XXX quick hack to limit subprocesses
        $persist{$key} = $connection;
    }

    return $connection;
}


sub _connection_check {
    my ($self, $connection) = @_;
    $connection ||= $self->connection_info;
    my $pid = $connection->{pid};
    my $ok = (kill 0, $pid);
    $self->trace_msg("_connection_check: $ok (pid $$)\n",0) if $self->trace;
    return $ok;
}


sub _connection_kill {
    my ($self) = @_;
    my $connection = $self->connection_info;
    my ($pid, $wfh, $rfh, $efh) = @{$connection}{qw(pid wfh rfh efh)};
    $self->trace_msg("_connection_kill: closing write handle\n",0) if $self->trace;
    # closing the write file handle should be enough, generally
    close $wfh;
    # in future we may want to be more aggressive
    #close $rfh; close $efh; kill 15, $pid
    # but deleting from the persist cache...
    delete $persist{ $self->_connection_key };
    # ... and removing the connection_info should suffice
    $self->connection_info( undef );
    return;
}


sub _make_connection {
    my ($self) = @_;

    my $go_perl = $self->go_perl;
    my $cmd = [ @$go_perl, qw(-MDBI::Gofer::Transport::stream -e run_stdio_hex)];

    #push @$cmd, "DBI_TRACE=2=/tmp/goferstream.log", "sh", "-c";
    if (my $url = $self->go_url) {
        die "Only 'ssh:user\@host' style url supported by this transport"
            unless $url =~ s/^ssh://;
        my $ssh = $url;
        my $setup_env = join "||", map { "source $_ 2>/dev/null" } qw(.bash_profile .bash_login .profile);
        my $setup = $setup_env.q{; exec "$@"};
        # don't use $^X on remote system by default as it's possibly wrong
        $cmd->[0] = 'perl' if "@$go_perl" eq $^X;
        # -x not only 'Disables X11 forwarding' but also makes connections *much* faster
        unshift @$cmd, qw(ssh -xq), split(' ', $ssh), qw(bash -c), $setup;
    }

    $self->trace_msg("new connection: @$cmd\n",0) if $self->trace;

    # XXX add a handshake - some message from DBI::Gofer::Transport::stream that's
    # sent as soon as it starts that we can wait for to report success - and soak up
    # and report useful warnings etc from ssh before we get it? Increases latency though.
    my $connection = $self->start_pipe_command($cmd);
    return $connection;
}


sub transmit_request_by_transport {
    my ($self, $request) = @_;
    my $trace = $self->trace;

    my $connection = $self->connection_info || do {
        my $con = $self->_connection_get;
        $self->connection_info( $con );
        $con;
    };

    my $encoded_request = unpack("H*", $self->freeze_request($request));
    $encoded_request .= "\015\012";

    my $wfh = $connection->{wfh};
    $self->trace_msg(sprintf("transmit_request_by_transport: to fh %s fd%d\n", $wfh, fileno($wfh)),0)
        if $trace >= 4;

    # send frozen request
    local $\;
    $wfh->print($encoded_request) # autoflush enabled
        or do {
            my $err = $!;
            # XXX could/should make new connection and retry
            $self->_connection_kill;
            die "Error sending request: $err";
        };
    $self->trace_msg("Request sent: $encoded_request\n",0) if $trace >= 4;

    return undef; # indicate no response yet (so caller calls receive_response_by_transport)
}


sub receive_response_by_transport {
    my $self = shift;
    my $trace = $self->trace;

    $self->trace_msg("receive_response_by_transport: awaiting response\n",0) if $trace >= 4;
    my $connection = $self->connection_info || die;
    my ($pid, $rfh, $efh, $cmd) = @{$connection}{qw(pid rfh efh cmd)};

    my $errno = 0;
    my $encoded_response;
    my $stderr_msg;

    $self->read_response_from_fh( {
        $efh => {
            error => sub { warn "error reading response stderr: $!"; $errno||=$!; 1 },
            eof   => sub { warn "eof reading efh" if $trace >= 4; 1 },
            read  => sub { $stderr_msg .= $_; 0 },
        },
        $rfh => {
            error => sub { warn "error reading response: $!"; $errno||=$!; 1 },
            eof   => sub { warn "eof reading rfh" if $trace >= 4; 1 },
            read  => sub { $encoded_response .= $_; ($encoded_response=~s/\015\012$//) ? 1 : 0 },
        },
    });

    # if we got no output on stdout at all then the command has
    # probably exited, possibly with an error to stderr.
    # Turn this situation into a reasonably useful DBI error.
    if (not $encoded_response) {
        my @msg;
        push @msg, "error while reading response: $errno" if $errno;
        if ($stderr_msg) {
            chomp $stderr_msg;
            push @msg, sprintf "error reported by \"%s\" (pid %d%s): %s",
                $self->cmd_as_string,
                $pid, ((kill 0, $pid) ? "" : ", exited"),
                $stderr_msg;
        }
        die join(", ", "No response received", @msg)."\n";
    }

    $self->trace_msg("Response received: $encoded_response\n",0)
        if $trace >= 4;

    $self->trace_msg("Gofer stream stderr message: $stderr_msg\n",0)
        if $stderr_msg && $trace;

    my $frozen_response = pack("H*", $encoded_response);

    # XXX need to be able to detect and deal with corruption
    my $response = $self->thaw_response($frozen_response);

    if ($stderr_msg) {
        # add stderr messages as warnings (for PrintWarn)
        $response->add_err(0, $stderr_msg, undef, $trace)
            # but ignore warning from old version of blib
            unless $stderr_msg =~ /^Using .*blib/ && "@$cmd" =~ /-Mblib/;
    }

    return $response;
}

sub transport_timedout {
    my $self = shift;
    $self->_connection_kill;
    return $self->SUPER::transport_timedout(@_);
}

1;

__END__

