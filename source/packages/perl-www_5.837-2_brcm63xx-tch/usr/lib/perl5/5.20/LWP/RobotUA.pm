package LWP::RobotUA;

require LWP::UserAgent;
@ISA = qw(LWP::UserAgent);
$VERSION = "5.835";

require WWW::RobotRules;
require HTTP::Request;
require HTTP::Response;

use Carp ();
use HTTP::Status ();
use HTTP::Date qw(time2str);
use strict;



sub new
{
    my $class = shift;
    my %cnf;
    if (@_ < 4) {
	# legacy args
	@cnf{qw(agent from rules)} = @_;
    }
    else {
	%cnf = @_;
    }

    Carp::croak('LWP::RobotUA agent required') unless $cnf{agent};
    Carp::croak('LWP::RobotUA from address required')
	unless $cnf{from} && $cnf{from} =~ m/\@/;

    my $delay = delete $cnf{delay} || 1;
    my $use_sleep = delete $cnf{use_sleep};
    $use_sleep = 1 unless defined($use_sleep);
    my $rules = delete $cnf{rules};

    my $self = LWP::UserAgent->new(%cnf);
    $self = bless $self, $class;

    $self->{'delay'} = $delay;   # minutes
    $self->{'use_sleep'} = $use_sleep;

    if ($rules) {
	$rules->agent($cnf{agent});
	$self->{'rules'} = $rules;
    }
    else {
	$self->{'rules'} = WWW::RobotRules->new($cnf{agent});
    }

    $self;
}


sub delay     { shift->_elem('delay',     @_); }
sub use_sleep { shift->_elem('use_sleep', @_); }


sub agent
{
    my $self = shift;
    my $old = $self->SUPER::agent(@_);
    if (@_) {
	# Changing our name means to start fresh
	$self->{'rules'}->agent($self->{'agent'}); 
    }
    $old;
}


sub rules {
    my $self = shift;
    my $old = $self->_elem('rules', @_);
    $self->{'rules'}->agent($self->{'agent'}) if @_;
    $old;
}


sub no_visits
{
    my($self, $netloc) = @_;
    $self->{'rules'}->no_visits($netloc) || 0;
}

*host_count = \&no_visits;  # backwards compatibility with LWP-5.02


sub host_wait
{
    my($self, $netloc) = @_;
    return undef unless defined $netloc;
    my $last = $self->{'rules'}->last_visit($netloc);
    if ($last) {
	my $wait = int($self->{'delay'} * 60 - (time - $last));
	$wait = 0 if $wait < 0;
	return $wait;
    }
    return 0;
}


sub simple_request
{
    my($self, $request, $arg, $size) = @_;

    # Do we try to access a new server?
    my $allowed = $self->{'rules'}->allowed($request->uri);

    if ($allowed < 0) {
	# Host is not visited before, or robots.txt expired; fetch "robots.txt"
	my $robot_url = $request->uri->clone;
	$robot_url->path("robots.txt");
	$robot_url->query(undef);

	# make access to robot.txt legal since this will be a recursive call
	$self->{'rules'}->parse($robot_url, ""); 

	my $robot_req = HTTP::Request->new('GET', $robot_url);
	my $robot_res = $self->request($robot_req);
	my $fresh_until = $robot_res->fresh_until;
	if ($robot_res->is_success) {
	    my $c = $robot_res->content;
	    if ($robot_res->content_type =~ m,^text/, && $c =~ /^\s*Disallow\s*:/mi) {
		$self->{'rules'}->parse($robot_url, $c, $fresh_until);
	    }
	    else {
		$self->{'rules'}->parse($robot_url, "", $fresh_until);
	    }

	}
	else {
	    $self->{'rules'}->parse($robot_url, "", $fresh_until);
	}

	# recalculate allowed...
	$allowed = $self->{'rules'}->allowed($request->uri);
    }

    # Check rules
    unless ($allowed) {
	my $res = HTTP::Response->new(
	  &HTTP::Status::RC_FORBIDDEN, 'Forbidden by robots.txt');
	$res->request( $request ); # bind it to that request
	return $res;
    }

    my $netloc = eval { local $SIG{__DIE__}; $request->uri->host_port; };
    my $wait = $self->host_wait($netloc);

    if ($wait) {
	if ($self->{'use_sleep'}) {
	    sleep($wait)
	}
	else {
	    my $res = HTTP::Response->new(
	      &HTTP::Status::RC_SERVICE_UNAVAILABLE, 'Please, slow down');
	    $res->header('Retry-After', time2str(time + $wait));
	    $res->request( $request ); # bind it to that request
	    return $res;
	}
    }

    # Perform the request
    my $res = $self->SUPER::simple_request($request, $arg, $size);

    $self->{'rules'}->visit($netloc);

    $res;
}


sub as_string
{
    my $self = shift;
    my @s;
    push(@s, "Robot: $self->{'agent'} operated by $self->{'from'}  [$self]");
    push(@s, "    Minimum delay: " . int($self->{'delay'}*60) . "s");
    push(@s, "    Will sleep if too early") if $self->{'use_sleep'};
    push(@s, "    Rules = $self->{'rules'}");
    join("\n", @s, '');
}

1;


__END__

