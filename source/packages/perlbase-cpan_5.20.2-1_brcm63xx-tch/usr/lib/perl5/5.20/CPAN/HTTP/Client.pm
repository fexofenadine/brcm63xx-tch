package CPAN::HTTP::Client;
use strict;
use vars qw(@ISA);
use CPAN::HTTP::Credentials;
use HTTP::Tiny 0.005;

$CPAN::HTTP::Client::VERSION = $CPAN::HTTP::Client::VERSION = "1.9601";


sub new {
    my $class = shift;
    my %args = @_;
    for my $k ( keys %args ) {
        $args{$k} = '' unless defined $args{$k};
    }
    $args{no_proxy} = [split(",", $args{no_proxy}) ] if $args{no_proxy};
    return bless \%args, $class;
}


sub mirror {
    my($self, $uri, $path) = @_;

    my $want_proxy = $self->_want_proxy($uri);
    my $http = HTTP::Tiny->new(
        $want_proxy ? (proxy => $self->{proxy}) : ()
    );

    my ($response, %headers);
    my $retries = 0;
    while ( $retries++ < 5 ) {
        $response = $http->mirror( $uri, $path, {headers => \%headers} );
        if ( $response->{status} eq '401' ) {
            last unless $self->_get_auth_params( $response, 'non_proxy' );
        }
        elsif ( $response->{status} eq '407' ) {
            last unless $self->_get_auth_params( $response, 'proxy' );
        }
        else {
            last; # either success or failure
        }
        my %headers = (
            $self->_auth_headers( $uri, 'non_proxy' ),
            ( $want_proxy ? $self->_auth_headers($uri, 'proxy') : () ),
        );
    }

    return $response;
}

sub _want_proxy {
    my ($self, $uri) = @_;
    return unless $self->{proxy};
    my($host) = $uri =~ m|://([^/:]+)|;
    return ! grep { $host =~ /\Q$_\E$/ } @{ $self->{no_proxy} || [] };
}

sub _auth_headers {
    my ($self, $uri, $mode) = @_;
    # Get names for our mode-specific attributes
    my ($type_key, $param_key) = map {"_" . $mode . $_} qw/_type _params/;

    # If _prepare_auth has not been called, we can't prepare headers
    return unless $self->{$type_key};

    # Get user credentials for mode
    my $cred_method = "get_" . ($mode ? "proxy" : "non_proxy") ."_credentials";
    my ($user, $pass) = CPAN::HTTP::Credentials->$cred_method;

    # Generate the header for the mode & type
    my $header = $mode eq 'proxy' ? 'Proxy-Authorization' : 'Authorization';
    my $value_method = "_" . $self->{$type_key} . "_auth";
    my $value = $self->$value_method($user, $pass, $self->{$param_key}, $uri);

    # If we didn't get a value, we didn't have the right modules available
    return $value ? ( $header, $value ) : ();
}

sub _get_auth_params {
    my ($self, $response, $mode) = @_;
    my $prefix = $mode eq 'proxy' ? 'Proxy' : 'WWW';
    my ($type_key, $param_key) = map {"_" . $mode . $_} qw/_type _params/;
    if ( ! $response->{success} ) { # auth failed
        my $method = "clear_${mode}_credentials";
        CPAN::HTTP::Credentials->$method;
        delete $self->{$_} for $type_key, $param_key;
    }
    ($self->{$type_key}, $self->{$param_key}) =
        $self->_get_challenge( $response, "${prefix}-Authenticate");
    return $self->{$type_key};
}

sub _get_challenge {
    my ($self, $response, $auth_header) = @_;

    my $auth_list = $response->{headers}(lc $auth_header);
    return unless defined $auth_list;
    $auth_list = [$auth_list] unless ref $auth_list;

    for my $challenge (@$auth_list) {
        $challenge =~ tr/,/;/;  # "," is used to separate auth-params!!
        ($challenge) = $self->split_header_words($challenge);
        my $scheme = shift(@$challenge);
        shift(@$challenge); # no value
        $challenge = { @$challenge };  # make rest into a hash

        unless ($scheme =~ /^(basic|digest)$/) {
            next; # bad scheme
        }
        $scheme = $1;  # untainted now

        return ($scheme, $challenge);
    }
    return;
}

sub _basic_auth {
    my ($self, $user, $pass) = @_;
    unless ( $CPAN::META->has_usable('MIME::Base64') ) {
        $CPAN::Frontend->mywarn(
            "MIME::Base64 is required for 'Basic' style authentication"
        );
        return;
    }
    return "Basic " . MIME::Base64::encode_base64("$user\:$pass", q{});
}

sub _digest_auth {
    my ($self, $user, $pass, $auth_param, $uri) = @_;
    unless ( $CPAN::META->has_usable('Digest::MD5') ) {
        $CPAN::Frontend->mywarn(
            "Digest::MD5 is required for 'Digest' style authentication"
        );
        return;
    }

    my $nc = sprintf "%08X", ++$self->{_nonce_count}{$auth_param->{nonce}};
    my $cnonce = sprintf "%8x", time;

    my ($path) = $uri =~ m{^\w+?://[^/]+(/.*)$};
    $path = "/" unless defined $path;

    my $md5 = Digest::MD5->new;

    my(@digest);
    $md5->add(join(":", $user, $auth_param->{realm}, $pass));
    push(@digest, $md5->hexdigest);
    $md5->reset;

    push(@digest, $auth_param->{nonce});

    if ($auth_param->{qop}) {
        push(@digest, $nc, $cnonce, ($auth_param->{qop} =~ m|^auth[,;]auth-int$|) ? 'auth' : $auth_param->{qop});
    }

    $md5->add(join(":", 'GET', $path));
    push(@digest, $md5->hexdigest);
    $md5->reset;

    $md5->add(join(":", @digest));
    my($digest) = $md5->hexdigest;
    $md5->reset;

    my %resp = map { $_ => $auth_param->{$_} } qw(realm nonce opaque);
    @resp{qw(username uri response algorithm)} = ($user, $path, $digest, "MD5");

    if (($auth_param->{qop} || "") =~ m|^auth([,;]auth-int)?$|) {
        @resp{qw(qop cnonce nc)} = ("auth", $cnonce, $nc);
    }

    my(@order) =
        qw(username realm qop algorithm uri nonce nc cnonce response opaque);
    my @pairs;
    for (@order) {
        next unless defined $resp{$_};
        push(@pairs, "$_=" . qq("$resp{$_}"));
    }

    my $auth_value  = "Digest " . join(", ", @pairs);
    return $auth_value;
}

sub split_header_words {
    my ($self, @words) = @_;
    my @res = $self->_split_header_words(@words);
    for my $arr (@res) {
        for (my $i = @$arr - 2; $i >= 0; $i -= 2) {
            $arr->[$i] = lc($arr->[$i]);
        }
    }
    return @res;
}

sub _split_header_words {
    my($self, @val) = @_;
    my @res;
    for (@val) {
        my @cur;
        while (length) {
            if (s/^\s*(=*[^\s=;,]+)//) {  # 'token' or parameter 'attribute'
                push(@cur, $1);
                # a quoted value
                if (s/^\s*=\s*\"([^\"\\]*(?:\\.[^\"\\]*)*)\"//) {
                    my $val = $1;
                    $val =~ s/\\(.)/$1/g;
                    push(@cur, $val);
                    # some unquoted value
                }
                elsif (s/^\s*=\s*([^;,\s]*)//) {
                    my $val = $1;
                    $val =~ s/\s+$//;
                    push(@cur, $val);
                    # no value, a lone token
                }
                else {
                    push(@cur, undef);
                }
            }
            elsif (s/^\s*,//) {
                push(@res, [@cur]) if @cur;
                @cur = ();
            }
            elsif (s/^\s*;// || s/^\s+//) {
                # continue
            }
            else {
                die "This should not happen: '$_'";
            }
        }
        push(@res, \@cur) if @cur;
    }
    @res;
}

1;
