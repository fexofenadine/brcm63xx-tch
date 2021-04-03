package DBD::Gofer::Transport::Base;


use strict;
use warnings;

use base qw(DBI::Gofer::Transport::Base);

our $VERSION = "0.014121";

__PACKAGE__->mk_accessors(qw(
    trace
    go_dsn
    go_url
    go_policy
    go_timeout
    go_retry_hook
    go_retry_limit
    go_cache
    cache_hit
    cache_miss
    cache_store
));
__PACKAGE__->mk_accessors_using(make_accessor_autoviv_hashref => qw(
    meta
));


sub new {
    my ($class, $args) = @_;
    $args->{$_} = 0 for (qw(cache_hit cache_miss cache_store));
    $args->{keep_meta_frozen} ||= 1 if $args->{go_cache};
    #warn "args @{[ %$args ]}\n";
    return $class->SUPER::new($args);
}


sub _init_trace { $ENV{DBD_GOFER_TRACE} || 0 }


sub new_response {
    my $self = shift;
    return DBI::Gofer::Response->new(@_);
}


sub transmit_request {
    my ($self, $request) = @_;
    my $trace = $self->trace;
    my $response;

    my ($go_cache, $request_cache_key);
    if ($go_cache = $self->{go_cache}) {
        $request_cache_key
            = $request->{meta}{request_cache_key}
            = $self->get_cache_key_for_request($request);
        if ($request_cache_key) {
            my $frozen_response = eval { $go_cache->get($request_cache_key) };
            if ($frozen_response) {
                $self->_dump("cached response found for ".ref($request), $request)
                    if $trace;
                $response = $self->thaw_response($frozen_response);
                $self->trace_msg("transmit_request is returning a response from cache $go_cache\n")
                    if $trace;
                ++$self->{cache_hit};
                return $response;
            }
            warn $@ if $@;
            ++$self->{cache_miss};
            $self->trace_msg("transmit_request cache miss\n")
                if $trace;
        }
    }

    my $to = $self->go_timeout;
    my $transmit_sub = sub {
        $self->trace_msg("transmit_request\n") if $trace;
        local $SIG{ALRM} = sub { die "TIMEOUT\n" } if $to;

        my $response = eval {
            local $SIG{PIPE} = sub {
                my $extra = ($! eq "Broken pipe") ? "" : " ($!)";
                die "Unable to send request: Broken pipe$extra\n";
            };
            alarm($to) if $to;
            $self->transmit_request_by_transport($request);
        };
        alarm(0) if $to;

        if ($@) {
            return $self->transport_timedout("transmit_request", $to)
                if $@ eq "TIMEOUT\n";
            return $self->new_response({ err => 1, errstr => $@ });
        }

        return $response;
    };

    $response = $self->_transmit_request_with_retries($request, $transmit_sub);

    if ($response) {
        my $frozen_response = delete $response->{meta}{frozen};
        $self->_store_response_in_cache($frozen_response, $request_cache_key)
            if $request_cache_key;
    }

    $self->trace_msg("transmit_request is returning a response itself\n")
        if $trace && $response;

    return $response unless wantarray;
    return ($response, $transmit_sub);
}


sub _transmit_request_with_retries {
    my ($self, $request, $transmit_sub) = @_;
    my $response;
    do {
        $response = $transmit_sub->();
    } while ( $response && $self->response_needs_retransmit($request, $response) );
    return $response;
}


sub receive_response {
    my ($self, $request, $retransmit_sub) = @_;
    my $to = $self->go_timeout;

    my $receive_sub = sub {
        $self->trace_msg("receive_response\n");
        local $SIG{ALRM} = sub { die "TIMEOUT\n" } if $to;

        my $response = eval {
            alarm($to) if $to;
            $self->receive_response_by_transport($request);
        };
        alarm(0) if $to;

        if ($@) {
            return $self->transport_timedout("receive_response", $to)
                if $@ eq "TIMEOUT\n";
            return $self->new_response({ err => 1, errstr => $@ });
        }
        return $response;
    };

    my $response;
    do {
        $response = $receive_sub->();
        if ($self->response_needs_retransmit($request, $response)) {
            $response = $self->_transmit_request_with_retries($request, $retransmit_sub);
            $response ||= $receive_sub->();
        }
    } while ( $self->response_needs_retransmit($request, $response) );

    if ($response) {
        my $frozen_response = delete $response->{meta}{frozen};
        my $request_cache_key = $request->{meta}{request_cache_key};
        $self->_store_response_in_cache($frozen_response, $request_cache_key)
            if $request_cache_key && $self->{go_cache};
    }

    return $response;
}


sub response_retry_preference {
    my ($self, $request, $response) = @_;

    # give the user a chance to express a preference (or undef for default)
    if (my $go_retry_hook = $self->go_retry_hook) {
        my $retry = $go_retry_hook->($request, $response, $self);
        $self->trace_msg(sprintf "go_retry_hook returned %s\n",
            (defined $retry) ? $retry : 'undef');
        return $retry if defined $retry;
    }

    # This is the main decision point.  We don't retry requests that got
    # as far as executing because the error is probably from the database
    # (not transport) so retrying is unlikely to help. But note that any
    # severe transport error occurring after execute is likely to return
    # a new response object that doesn't have the execute flag set. Beware!
    return 0 if $response->executed_flag_set;

    return 1 if ($response->errstr || '') =~ m/induced by DBI_GOFER_RANDOM/;

    return 1 if $request->is_idempotent; # i.e. is SELECT or ReadOnly was set

    return undef; # we couldn't make up our mind
}


sub response_needs_retransmit {
    my ($self, $request, $response) = @_;

    my $err = $response->err
        or return 0; # nothing went wrong

    my $retry = $self->response_retry_preference($request, $response);

    if (!$retry) {  # false or undef
        $self->trace_msg("response_needs_retransmit: response not suitable for retry\n");
        return 0;
    }

    # we'd like to retry but have we retried too much already?

    my $retry_limit = $self->go_retry_limit;
    if (!$retry_limit) {
        $self->trace_msg("response_needs_retransmit: retries disabled (retry_limit not set)\n");
        return 0;
    }

    my $request_meta = $request->meta;
    my $retry_count = $request_meta->{retry_count} || 0;
    if ($retry_count >= $retry_limit) {
        $self->trace_msg("response_needs_retransmit: $retry_count is too many retries\n");
        # XXX should be possible to disable altering the err
        $response->errstr(sprintf "%s (after %d retries by gofer)", $response->errstr, $retry_count);
        return 0;
    }

    # will retry now, do the admin
    ++$retry_count;
    $self->trace_msg("response_needs_retransmit: retry $retry_count\n");

    # hook so response_retry_preference can defer some code execution
    # until we've checked retry_count and retry_limit.
    if (ref $retry eq 'CODE') {
        $retry->($retry_count, $retry_limit)
            and warn "should return false"; # protect future use
    }

    ++$request_meta->{retry_count};         # update count for this request object
    ++$self->meta->{request_retry_count};   # update cumulative transport stats

    return 1;
}


sub transport_timedout {
    my ($self, $method, $timeout) = @_;
    $timeout ||= $self->go_timeout;
    return $self->new_response({ err => 1, errstr => "DBD::Gofer $method timed-out after $timeout seconds" });
}


sub get_cache_key_for_request {
    my ($self, $request) = @_;

    # we only want to cache idempotent requests
    # is_idempotent() is true if GOf_REQUEST_IDEMPOTENT or GOf_REQUEST_READONLY set
    return undef if not $request->is_idempotent;

    # XXX would be nice to avoid the extra freeze here
    my $key = $self->freeze_request($request, undef, 1);

    #use Digest::MD5; warn "get_cache_key_for_request: ".Digest::MD5::md5_base64($key)."\n";

    return $key;
}


sub _store_response_in_cache {
    my ($self, $frozen_response, $request_cache_key) = @_;
    my $go_cache = $self->{go_cache}
        or return;

    # new() ensures that enabling go_cache also enables keep_meta_frozen
    warn "No meta frozen in response" if !$frozen_response;
    warn "No request_cache_key" if !$request_cache_key;

    if ($frozen_response && $request_cache_key) {
        $self->trace_msg("receive_response added response to cache $go_cache\n");
        eval { $go_cache->set($request_cache_key, $frozen_response) };
        warn $@ if $@;
        ++$self->{cache_store};
    }
}

1;

__END__

