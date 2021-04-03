package CGI::Cookie;

use strict;
use warnings;

use if $] >= 5.019, 'deprecate';




our $VERSION='1.31';

use CGI::Util qw(rearrange unescape escape);
use overload '""' => \&as_string, 'cmp' => \&compare, 'fallback' => 1;

my $PERLEX = 0;
$PERLEX++ if defined($ENV{'GATEWAY_INTERFACE'}) && $ENV{'GATEWAY_INTERFACE'} =~ /^CGI-PerlEx/;

my $MOD_PERL = 0;
if (exists $ENV{MOD_PERL} && ! $PERLEX) {
  if (exists $ENV{MOD_PERL_API_VERSION} && $ENV{MOD_PERL_API_VERSION} == 2) {
      $MOD_PERL = 2;
      require Apache2::RequestUtil;
      require APR::Table;
  } else {
    $MOD_PERL = 1;
    require Apache;
  }
}

sub fetch {
    my $class = shift;
    my $raw_cookie = get_raw_cookie(@_) or return;
    return $class->parse($raw_cookie);
}

 sub raw_fetch {
   my $class = shift;
   my $raw_cookie = get_raw_cookie(@_) or return;
   my %results;
   my($key,$value);
   
   my @pairs = split("[;,] ?",$raw_cookie);
  for my $pair ( @pairs ) {
    $pair =~ s/^\s+|\s+$//g;    # trim leading trailing whitespace
    my ( $key, $value ) = split "=", $pair;

    $value = defined $value ? $value : '';
    $results{$key} = $value;
  }
  return wantarray ? %results : \%results;
}

sub get_raw_cookie {
  my $r = shift;
  $r ||= eval { $MOD_PERL == 2                    ? 
                  Apache2::RequestUtil->request() :
                  Apache->request } if $MOD_PERL;

  return $r->headers_in->{'Cookie'} if $r;

  die "Run $r->subprocess_env; before calling fetch()" 
    if $MOD_PERL and !exists $ENV{REQUEST_METHOD};
    
  return $ENV{HTTP_COOKIE} || $ENV{COOKIE};
}


sub parse {
  my ($self,$raw_cookie) = @_;
  return wantarray ? () : {} unless $raw_cookie;

  my %results;

  my @pairs = split("[;,] ?",$raw_cookie);
  for (@pairs) {
    s/^\s+//;
    s/\s+$//;

    my($key,$value) = split("=",$_,2);

    # Some foreign cookies are not in name=value format, so ignore
    # them.
    next if !defined($value);
    my @values = ();
    if ($value ne '') {
      @values = map unescape($_),split(/[&;]/,$value.'&dmy');
      pop @values;
    }
    $key = unescape($key);
    # A bug in Netscape can cause several cookies with same name to
    # appear.  The FIRST one in HTTP_COOKIE is the most recent version.
    $results{$key} ||= $self->new(-name=>$key,-value=>\@values);
  }
  return wantarray ? %results : \%results;
}

sub new {
  my ( $class, @params ) = @_;
  $class = ref( $class ) || $class;
  # Ignore mod_perl request object--compatibility with Apache::Cookie.
  shift if ref $params[0]
        && eval { $params[0]->isa('Apache::Request::Req') || $params[0]->isa('Apache') };
  my ( $name, $value, $path, $domain, $secure, $expires, $max_age, $httponly )
   = rearrange(
    [
      'NAME', [ 'VALUE', 'VALUES' ],
      'PATH',   'DOMAIN',
      'SECURE', 'EXPIRES',
      'MAX-AGE','HTTPONLY'
    ],
    @params
   );
  return undef unless defined $name and defined $value;
  my $self = {};
  bless $self, $class;
  $self->name( $name );
  $self->value( $value );
  $path ||= "/";
  $self->path( $path )         if defined $path;
  $self->domain( $domain )     if defined $domain;
  $self->secure( $secure )     if defined $secure;
  $self->expires( $expires )   if defined $expires;
  $self->max_age($expires)     if defined $max_age;
  $self->httponly( $httponly ) if defined $httponly;
  return $self;
}

sub as_string {
    my $self = shift;
    return "" unless $self->name;

    no warnings; # some things may be undefined, that's OK.

    my $name  = escape( $self->name );
    my $value = join "&", map { escape($_) } $self->value;
    my @cookie = ( "$name=$value" );

    push @cookie,"domain=".$self->domain   if $self->domain;
    push @cookie,"path=".$self->path       if $self->path;
    push @cookie,"expires=".$self->expires if $self->expires;
    push @cookie,"max-age=".$self->max_age if $self->max_age;
    push @cookie,"secure"                  if $self->secure;
    push @cookie,"HttpOnly"                if $self->httponly;

    return join "; ", @cookie;
}

sub compare {
    my ( $self, $value ) = @_;
    return "$self" cmp $value;
}

sub bake {
  my ($self, $r) = @_;

  $r ||= eval {
      $MOD_PERL == 2
          ? Apache2::RequestUtil->request()
          : Apache->request
  } if $MOD_PERL;
  if ($r) {
      $r->headers_out->add('Set-Cookie' => $self->as_string);
  } else {
      require CGI;
      print CGI::header(-cookie => $self);
  }

}

sub name {
    my ( $self, $name ) = @_;
    $self->{'name'} = $name if defined $name;
    return $self->{'name'};
}

sub value {
  my ( $self, $value ) = @_;
  if ( defined $value ) {
    my @values
     = ref $value eq 'ARRAY' ? @$value
     : ref $value eq 'HASH'  ? %$value
     :                         ( $value );
    $self->{'value'} = [@values];
  }
  return wantarray ? @{ $self->{'value'} } : $self->{'value'}->[0];
}

sub domain {
    my ( $self, $domain ) = @_;
    $self->{'domain'} = lc $domain if defined $domain;
    return $self->{'domain'};
}

sub secure {
    my ( $self, $secure ) = @_;
    $self->{'secure'} = $secure if defined $secure;
    return $self->{'secure'};
}

sub expires {
    my ( $self, $expires ) = @_;
    $self->{'expires'} = CGI::Util::expires($expires,'cookie') if defined $expires;
    return $self->{'expires'};
}

sub max_age {
    my ( $self, $max_age ) = @_;
    $self->{'max-age'} = CGI::Util::expire_calc($max_age)-time() if defined $max_age;
    return $self->{'max-age'};
}

sub path {
    my ( $self, $path ) = @_;
    $self->{'path'} = $path if defined $path;
    return $self->{'path'};
}


sub httponly { # HttpOnly
    my ( $self, $httponly ) = @_;
    $self->{'httponly'} = $httponly if defined $httponly;
    return $self->{'httponly'};
}

1;

