package LWP::Protocol::ftp;


use Carp ();

use HTTP::Status ();
use HTTP::Negotiate ();
use HTTP::Response ();
use LWP::MediaTypes ();
use File::Listing ();

require LWP::Protocol;
@ISA = qw(LWP::Protocol);

use strict;
eval {
    package LWP::Protocol::MyFTP;

    require Net::FTP;
    Net::FTP->require_version(2.00);

    use vars qw(@ISA);
    @ISA=qw(Net::FTP);

    sub new {
	my $class = shift;

	my $self = $class->SUPER::new(@_) || return undef;

	my $mess = $self->message;  # welcome message
	$mess =~ s|\n.*||s; # only first line left
	$mess =~ s|\s*ready\.?$||;
	# Make the version number more HTTP like
	$mess =~ s|\s*\(Version\s*|/| and $mess =~ s|\)$||;
	${*$self}{myftp_server} = $mess;
	#$response->header("Server", $mess);

	$self;
    }

    sub http_server {
	my $self = shift;
	${*$self}{myftp_server};
    }

    sub home {
	my $self = shift;
	my $old = ${*$self}{myftp_home};
	if (@_) {
	    ${*$self}{myftp_home} = shift;
	}
	$old;
    }

    sub go_home {
	my $self = shift;
	$self->cwd(${*$self}{myftp_home});
    }

    sub request_count {
	my $self = shift;
	++${*$self}{myftp_reqcount};
    }

    sub ping {
	my $self = shift;
	return $self->go_home;
    }

};
my $init_failed = $@;


sub _connect {
    my($self, $host, $port, $user, $account, $password, $timeout) = @_;

    my $key;
    my $conn_cache = $self->{ua}{conn_cache};
    if ($conn_cache) {
	$key = "$host:$port:$user";
	$key .= ":$account" if defined($account);
	if (my $ftp = $conn_cache->withdraw("ftp", $key)) {
	    if ($ftp->ping) {
		# save it again
		$conn_cache->deposit("ftp", $key, $ftp);
		return $ftp;
	    }
	}
    }

    # try to make a connection
    my $ftp = LWP::Protocol::MyFTP->new($host,
					Port => $port,
					Timeout => $timeout,
					LocalAddr => $self->{ua}{local_address},
				       );
    # XXX Should be some what to pass on 'Passive' (header??)
    unless ($ftp) {
	$@ =~ s/^Net::FTP: //;
	return HTTP::Response->new(&HTTP::Status::RC_INTERNAL_SERVER_ERROR, $@);
    }

    unless ($ftp->login($user, $password, $account)) {
	# Unauthorized.  Let's fake a RC_UNAUTHORIZED response
	my $mess = scalar($ftp->message);
	$mess =~ s/\n$//;
	my $res =  HTTP::Response->new(&HTTP::Status::RC_UNAUTHORIZED, $mess);
	$res->header("Server", $ftp->http_server);
	$res->header("WWW-Authenticate", qq(Basic Realm="FTP login"));
	return $res;
    }

    my $home = $ftp->pwd;
    $ftp->home($home);

    $conn_cache->deposit("ftp", $key, $ftp) if $conn_cache;

    return $ftp;
}


sub request
{
    my($self, $request, $proxy, $arg, $size, $timeout) = @_;

    $size = 4096 unless $size;

    # check proxy
    if (defined $proxy)
    {
	return HTTP::Response->new(&HTTP::Status::RC_BAD_REQUEST,
				   'You can not proxy through the ftp');
    }

    my $url = $request->uri;
    if ($url->scheme ne 'ftp') {
	my $scheme = $url->scheme;
	return HTTP::Response->new(&HTTP::Status::RC_INTERNAL_SERVER_ERROR,
		       "LWP::Protocol::ftp::request called for '$scheme'");
    }

    # check method
    my $method = $request->method;

    unless ($method eq 'GET' || $method eq 'HEAD' || $method eq 'PUT') {
	return HTTP::Response->new(&HTTP::Status::RC_BAD_REQUEST,
				   'Library does not allow method ' .
				   "$method for 'ftp:' URLs");
    }

    if ($init_failed) {
	return HTTP::Response->new(&HTTP::Status::RC_INTERNAL_SERVER_ERROR,
				   $init_failed);
    }

    my $host     = $url->host;
    my $port     = $url->port;
    my $user     = $url->user;
    my $password = $url->password;

    # If a basic autorization header is present than we prefer these over
    # the username/password specified in the URL.
    {
	my($u,$p) = $request->authorization_basic;
	if (defined $u) {
	    $user = $u;
	    $password = $p;
	}
    }

    # We allow the account to be specified in the "Account" header
    my $account = $request->header('Account');

    my $ftp = $self->_connect($host, $port, $user, $account, $password, $timeout);
    return $ftp if ref($ftp) eq "HTTP::Response"; # ugh!

    # Create an initial response object
    my $response = HTTP::Response->new(&HTTP::Status::RC_OK, "OK");
    $response->header(Server => $ftp->http_server);
    $response->header('Client-Request-Num' => $ftp->request_count);
    $response->request($request);

    # Get & fix the path
    my @path =  grep { length } $url->path_segments;
    my $remote_file = pop(@path);
    $remote_file = '' unless defined $remote_file;

    my $type;
    if (ref $remote_file) {
	my @params;
	($remote_file, @params) = @$remote_file;
	for (@params) {
	    $type = $_ if s/^type=//;
	}
    }

    if ($type && $type eq 'a') {
	$ftp->ascii;
    }
    else {
	$ftp->binary;
    }

    for (@path) {
	unless ($ftp->cwd($_)) {
	    return HTTP::Response->new(&HTTP::Status::RC_NOT_FOUND,
				       "Can't chdir to $_");
	}
    }

    if ($method eq 'GET' || $method eq 'HEAD') {
	if (my $mod_time = $ftp->mdtm($remote_file)) {
	    $response->last_modified($mod_time);
	    if (my $ims = $request->if_modified_since) {
		if ($mod_time <= $ims) {
		    $response->code(&HTTP::Status::RC_NOT_MODIFIED);
		    $response->message("Not modified");
		    return $response;
		}
	    }
	}

	# We'll use this later to abort the transfer if necessary. 
	# if $max_size is defined, we need to abort early. Otherwise, it's
      # a normal transfer
	my $max_size = undef;

	# Set resume location, if the client requested it
	if ($request->header('Range') && $ftp->supported('REST'))
	{
		my $range_info = $request->header('Range');

		# Change bytes=2772992-6781209 to just 2772992
		my ($start_byte,$end_byte) = $range_info =~ /.*=\s*(\d+)-(\d+)?/;
		if ( defined $start_byte && !defined $end_byte ) {

		  # open range -- only the start is specified

		  $ftp->restart( $start_byte );
		  # don't define $max_size, we don't want to abort early
		}
		elsif ( defined $start_byte && defined $end_byte &&
			$start_byte >= 0 && $end_byte >= $start_byte ) {

		  $ftp->restart( $start_byte );
		  $max_size = $end_byte - $start_byte;
		}
		else {

		  return HTTP::Response->new(&HTTP::Status::RC_BAD_REQUEST,
		     'Incorrect syntax for Range request');
		}
	}
	elsif ($request->header('Range') && !$ftp->supported('REST'))
	{
		return HTTP::Response->new(&HTTP::Status::RC_NOT_IMPLEMENTED,
	         "Server does not support resume.");
	}

	my $data;  # the data handle
	if (length($remote_file) and $data = $ftp->retr($remote_file)) {
	    my($type, @enc) = LWP::MediaTypes::guess_media_type($remote_file);
	    $response->header('Content-Type',   $type) if $type;
	    for (@enc) {
		$response->push_header('Content-Encoding', $_);
	    }
	    my $mess = $ftp->message;
	    if ($mess =~ /\((\d+)\s+bytes\)/) {
		$response->header('Content-Length', "$1");
	    }

	    if ($method ne 'HEAD') {
		# Read data from server
		$response = $self->collect($arg, $response, sub {
		    my $content = '';
		    my $result = $data->read($content, $size);

                    # Stop early if we need to.
                    if (defined $max_size)
                    {
                      # We need an interface to Net::FTP::dataconn for getting
                      # the number of bytes already read
                      my $bytes_received = $data->bytes_read();

                      # We were already over the limit. (Should only happen
                      # once at the end.)
                      if ($bytes_received - length($content) > $max_size)
                      {
                        $content = '';
                      }
                      # We just went over the limit
                      elsif ($bytes_received  > $max_size)
                      {
                        # Trim content
                        $content = substr($content, 0,
                          $max_size - ($bytes_received - length($content)) );
                      }
                      # We're under the limit
                      else
                      {
                      }
                    }

		    return \$content;
		} );
	    }
	    # abort is needed for HEAD, it's == close if the transfer has
	    # already completed.
	    unless ($data->abort) {
		# Something did not work too well.  Note that we treat
		# responses to abort() with code 0 in case of HEAD as ok
		# (at least wu-ftpd 2.6.1(1) does that).
		if ($method ne 'HEAD' || $ftp->code != 0) {
		    $response->code(&HTTP::Status::RC_INTERNAL_SERVER_ERROR);
		    $response->message("FTP close response: " . $ftp->code .
				       " " . $ftp->message);
		}
	    }
	}
	elsif (!length($remote_file) || ( $ftp->code >= 400 && $ftp->code < 600 )) {
	    # not a plain file, try to list instead
	    if (length($remote_file) && !$ftp->cwd($remote_file)) {
		return HTTP::Response->new(&HTTP::Status::RC_NOT_FOUND,
					   "File '$remote_file' not found");
	    }

	    # It should now be safe to try to list the directory
	    my @lsl = $ftp->dir;

	    # Try to figure out if the user want us to convert the
	    # directory listing to HTML.
	    my @variants =
	      (
	       ['html',  0.60, 'text/html'            ],
	       ['dir',   1.00, 'text/ftp-dir-listing' ]
	      );
	    #$HTTP::Negotiate::DEBUG=1;
	    my $prefer = HTTP::Negotiate::choose(\@variants, $request);

	    my $content = '';

	    if (!defined($prefer)) {
		return HTTP::Response->new(&HTTP::Status::RC_NOT_ACCEPTABLE,
			       "Neither HTML nor directory listing wanted");
	    }
	    elsif ($prefer eq 'html') {
		$response->header('Content-Type' => 'text/html');
		$content = "<HEAD><TITLE>File Listing</TITLE>\n";
		my $base = $request->uri->clone;
		my $path = $base->path;
		$base->path("$path/") unless $path =~ m|/$|;
		$content .= qq(<BASE HREF="$base">\n</HEAD>\n);
		$content .= "<BODY>\n<UL>\n";
		for (File::Listing::parse_dir(\@lsl, 'GMT')) {
		    my($name, $type, $size, $mtime, $mode) = @$_;
		    $content .= qq(  <LI> <a href="$name">$name</a>);
		    $content .= " $size bytes" if $type eq 'f';
		    $content .= "\n";
		}
		$content .= "</UL></body>\n";
	    }
	    else {
		$response->header('Content-Type', 'text/ftp-dir-listing');
		$content = join("\n", @lsl, '');
	    }

	    $response->header('Content-Length', length($content));

	    if ($method ne 'HEAD') {
		$response = $self->collect_once($arg, $response, $content);
	    }
	}
	else {
	    my $res = HTTP::Response->new(&HTTP::Status::RC_BAD_REQUEST,
			  "FTP return code " . $ftp->code);
	    $res->content_type("text/plain");
	    $res->content($ftp->message);
	    return $res;
	}
    }
    elsif ($method eq 'PUT') {
	# method must be PUT
	unless (length($remote_file)) {
	    return HTTP::Response->new(&HTTP::Status::RC_BAD_REQUEST,
				       "Must have a file name to PUT to");
	}
	my $data;
	if ($data = $ftp->stor($remote_file)) {
	    my $content = $request->content;
	    my $bytes = 0;
	    if (defined $content) {
		if (ref($content) eq 'SCALAR') {
		    $bytes = $data->write($$content, length($$content));
		}
		elsif (ref($content) eq 'CODE') {
		    my($buf, $n);
		    while (length($buf = &$content)) {
			$n = $data->write($buf, length($buf));
			last unless $n;
			$bytes += $n;
		    }
		}
		elsif (!ref($content)) {
		    if (defined $content && length($content)) {
			$bytes = $data->write($content, length($content));
		    }
		}
		else {
		    die "Bad content";
		}
	    }
	    $data->close;

	    $response->code(&HTTP::Status::RC_CREATED);
	    $response->header('Content-Type', 'text/plain');
	    $response->content("$bytes bytes stored as $remote_file on $host\n")

	}
	else {
	    my $res = HTTP::Response->new(&HTTP::Status::RC_BAD_REQUEST,
					  "FTP return code " . $ftp->code);
	    $res->content_type("text/plain");
	    $res->content($ftp->message);
	    return $res;
	}
    }
    else {
	return HTTP::Response->new(&HTTP::Status::RC_BAD_REQUEST,
				   "Illegal method $method");
    }

    $response;
}

1;

__END__

