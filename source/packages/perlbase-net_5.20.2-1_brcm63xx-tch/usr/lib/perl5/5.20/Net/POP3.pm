
package Net::POP3;

use strict;
use IO::Socket;
use vars qw(@ISA $VERSION $debug);
use Net::Cmd;
use Carp;
use Net::Config;

$VERSION = "2.31";

@ISA = qw(Net::Cmd IO::Socket::INET);


sub new {
  my $self = shift;
  my $type = ref($self) || $self;
  my ($host, %arg);
  if (@_ % 2) {
    $host = shift;
    %arg  = @_;
  }
  else {
    %arg  = @_;
    $host = delete $arg{Host};
  }
  my $hosts = defined $host ? [$host] : $NetConfig{pop3_hosts};
  my $obj;
  my @localport = exists $arg{ResvPort} ? (LocalPort => $arg{ResvPort}) : ();

  my $h;
  foreach $h (@{$hosts}) {
    $obj = $type->SUPER::new(
      PeerAddr => ($host = $h),
      PeerPort => $arg{Port} || 'pop3(110)',
      Proto => 'tcp',
      @localport,
      Timeout => defined $arg{Timeout}
      ? $arg{Timeout}
      : 120
      )
      and last;
  }

  return undef
    unless defined $obj;

  ${*$obj}{'net_pop3_host'} = $host;

  $obj->autoflush(1);
  $obj->debug(exists $arg{Debug} ? $arg{Debug} : undef);

  unless ($obj->response() == CMD_OK) {
    $obj->close();
    return undef;
  }

  ${*$obj}{'net_pop3_banner'} = $obj->message;

  $obj;
}


sub host {
  my $me = shift;
  ${*$me}{'net_pop3_host'};
}



sub debug_text { $_[2] =~ /^(pass|rpop)/i ? "$1 ....\n" : $_[2]; }


sub login {
  @_ >= 1 && @_ <= 3 or croak 'usage: $pop3->login( USER, PASS )';
  my ($me, $user, $pass) = @_;

  if (@_ <= 2) {
    ($user, $pass) = $me->_lookup_credentials($user);
  }

  $me->user($user)
    and $me->pass($pass);
}


sub apop {
  @_ >= 1 && @_ <= 3 or croak 'usage: $pop3->apop( USER, PASS )';
  my ($me, $user, $pass) = @_;
  my $banner;
  my $md;

  if (eval { local $SIG{__DIE__}; require Digest::MD5 }) {
    $md = Digest::MD5->new();
  }
  elsif (eval { local $SIG{__DIE__}; require MD5 }) {
    $md = MD5->new();
  }
  else {
    carp "You need to install Digest::MD5 or MD5 to use the APOP command";
    return undef;
  }

  return undef
    unless ($banner = (${*$me}{'net_pop3_banner'} =~ /(<.*>)/)[0]);

  if (@_ <= 2) {
    ($user, $pass) = $me->_lookup_credentials($user);
  }

  $md->add($banner, $pass);

  return undef
    unless ($me->_APOP($user, $md->hexdigest));

  $me->_get_mailbox_count();
}


sub user {
  @_ == 2 or croak 'usage: $pop3->user( USER )';
  $_[0]->_USER($_[1]) ? 1 : undef;
}


sub pass {
  @_ == 2 or croak 'usage: $pop3->pass( PASS )';

  my ($me, $pass) = @_;

  return undef
    unless ($me->_PASS($pass));

  $me->_get_mailbox_count();
}


sub reset {
  @_ == 1 or croak 'usage: $obj->reset()';

  my $me = shift;

  return 0
    unless ($me->_RSET);

  if (defined ${*$me}{'net_pop3_mail'}) {
    local $_;
    foreach (@{${*$me}{'net_pop3_mail'}}) {
      delete $_->{'net_pop3_deleted'};
    }
  }
}


sub last {
  @_ == 1 or croak 'usage: $obj->last()';

  return undef
    unless $_[0]->_LAST && $_[0]->message =~ /(\d+)/;

  return $1;
}


sub top {
  @_ == 2 || @_ == 3 or croak 'usage: $pop3->top( MSGNUM [, NUMLINES ])';
  my $me = shift;

  return undef
    unless $me->_TOP($_[0], $_[1] || 0);

  $me->read_until_dot;
}


sub popstat {
  @_ == 1 or croak 'usage: $pop3->popstat()';
  my $me = shift;

  return ()
    unless $me->_STAT && $me->message =~ /(\d+)\D+(\d+)/;

  ($1 || 0, $2 || 0);
}


sub list {
  @_ == 1 || @_ == 2 or croak 'usage: $pop3->list( [ MSGNUM ] )';
  my $me = shift;

  return undef
    unless $me->_LIST(@_);

  if (@_) {
    $me->message =~ /\d+\D+(\d+)/;
    return $1 || undef;
  }

  my $info = $me->read_until_dot
    or return undef;

  my %hash = map { (/(\d+)\D+(\d+)/) } @$info;

  return \%hash;
}


sub get {
  @_ == 2 or @_ == 3 or croak 'usage: $pop3->get( MSGNUM [, FH ])';
  my $me = shift;

  return undef
    unless $me->_RETR(shift);

  $me->read_until_dot(@_);
}


sub getfh {
  @_ == 2 or croak 'usage: $pop3->getfh( MSGNUM )';
  my $me = shift;

  return unless $me->_RETR(shift);
  return $me->tied_fh;
}


sub delete {
  @_ == 2 or croak 'usage: $pop3->delete( MSGNUM )';
  my $me = shift;
  return 0 unless $me->_DELE(@_);
  ${*$me}{'net_pop3_deleted'} = 1;
}


sub uidl {
  @_ == 1 || @_ == 2 or croak 'usage: $pop3->uidl( [ MSGNUM ] )';
  my $me = shift;
  my $uidl;

  $me->_UIDL(@_)
    or return undef;
  if (@_) {
    $uidl = ($me->message =~ /\d+\s+([\041-\176]+)/)[0];
  }
  else {
    my $ref = $me->read_until_dot
      or return undef;
    my $ln;
    $uidl = {};
    foreach $ln (@$ref) {
      my ($msg, $uid) = $ln =~ /^\s*(\d+)\s+([\041-\176]+)/;
      $uidl->{$msg} = $uid;
    }
  }
  return $uidl;
}


sub ping {
  @_ == 2 or croak 'usage: $pop3->ping( USER )';
  my $me = shift;

  return () unless $me->_PING(@_) && $me->message =~ /(\d+)\D+(\d+)/;

  ($1 || 0, $2 || 0);
}


sub _lookup_credentials {
  my ($me, $user) = @_;

  require Net::Netrc;

       $user ||= eval { local $SIG{__DIE__}; (getpwuid($>))[0] }
    || $ENV{NAME}
    || $ENV{USER}
    || $ENV{LOGNAME};

  my $m = Net::Netrc->lookup(${*$me}{'net_pop3_host'}, $user);
  $m ||= Net::Netrc->lookup(${*$me}{'net_pop3_host'});

  my $pass = $m
    ? $m->password || ""
    : "";

  ($user, $pass);
}


sub _get_mailbox_count {
  my ($me) = @_;
  my $ret = ${*$me}{'net_pop3_count'} =
    ($me->message =~ /(\d+)\s+message/io) ? $1 : ($me->popstat)[0];

  $ret ? $ret : "0E0";
}


sub _STAT { shift->command('STAT'       )->response() == CMD_OK }
sub _LIST { shift->command('LIST',    @_)->response() == CMD_OK }
sub _RETR { shift->command('RETR', $_[0])->response() == CMD_OK }
sub _DELE { shift->command('DELE', $_[0])->response() == CMD_OK }
sub _NOOP { shift->command('NOOP'       )->response() == CMD_OK }
sub _RSET { shift->command('RSET'       )->response() == CMD_OK }
sub _QUIT { shift->command('QUIT'       )->response() == CMD_OK }
sub _TOP  { shift->command( 'TOP',    @_)->response() == CMD_OK }
sub _UIDL { shift->command('UIDL',    @_)->response() == CMD_OK }
sub _USER { shift->command('USER', $_[0])->response() == CMD_OK }
sub _PASS { shift->command('PASS', $_[0])->response() == CMD_OK }
sub _APOP { shift->command('APOP',    @_)->response() == CMD_OK }
sub _PING { shift->command('PING', $_[0])->response() == CMD_OK }
sub _RPOP { shift->command('RPOP', $_[0])->response() == CMD_OK }
sub _LAST { shift->command('LAST'       )->response() == CMD_OK }
sub _CAPA { shift->command('CAPA'       )->response() == CMD_OK }


sub quit {
  my $me = shift;

  $me->_QUIT;
  $me->close;
}


sub DESTROY {
  my $me = shift;

  if (defined fileno($me) and ${*$me}{'net_pop3_deleted'}) {
    $me->reset;
    $me->quit;
  }
}



sub response {
  my $cmd  = shift;
  my $str  = $cmd->getline() or return undef;
  my $code = "500";

  $cmd->debug_print(0, $str)
    if ($cmd->debug);

  if ($str =~ s/^\+OK\s*//io) {
    $code = "200";
  }
  elsif ($str =~ s/^\+\s*//io) {
    $code = "300";
  }
  else {
    $str =~ s/^-ERR\s*//io;
  }

  ${*$cmd}{'net_cmd_resp'} = [$str];
  ${*$cmd}{'net_cmd_code'} = $code;

  substr($code, 0, 1);
}


sub capa {
  my $this = shift;
  my ($capa, %capabilities);

  # Fake a capability here
  $capabilities{APOP} = '' if ($this->banner() =~ /<.*>/);

  if ($this->_CAPA()) {
    $capabilities{CAPA} = 1;
    $capa = $this->read_until_dot();
    %capabilities = (%capabilities, map {/^\s*(\S+)\s*(.*)/} @$capa);
  }
  else {

    # Check AUTH for SASL capabilities
    if ($this->command('AUTH')->response() == CMD_OK) {
      my $mechanism = $this->read_until_dot();
      $capabilities{SASL} = join " ", map {m/([A-Z0-9_-]+)/} @{$mechanism};
    }
  }

  return ${*$this}{'net_pop3e_capabilities'} = \%capabilities;
}


sub capabilities {
  my $this = shift;

  ${*$this}{'net_pop3e_capabilities'} || $this->capa;
}


sub auth {
  my ($self, $username, $password) = @_;

  eval {
    require MIME::Base64;
    require Authen::SASL;
  } or $self->set_status(500, ["Need MIME::Base64 and Authen::SASL todo auth"]), return 0;

  my $capa       = $self->capa;
  my $mechanisms = $capa->{SASL} || 'CRAM-MD5';

  my $sasl;

  if (ref($username) and UNIVERSAL::isa($username, 'Authen::SASL')) {
    $sasl = $username;
    my $user_mech = $sasl->mechanism || '';
    my @user_mech = split(/\s+/, $user_mech);
    my %user_mech;
    @user_mech{@user_mech} = ();

    my @server_mech = split(/\s+/, $mechanisms);
    my @mech = @user_mech
      ? grep { exists $user_mech{$_} } @server_mech
      : @server_mech;
    unless (@mech) {
      $self->set_status(
        500,
        [ 'Client SASL mechanisms (',
          join(', ', @user_mech),
          ') do not match the SASL mechnism the server announces (',
          join(', ', @server_mech), ')',
        ]
      );
      return 0;
    }

    $sasl->mechanism(join(" ", @mech));
  }
  else {
    die "auth(username, password)" if not length $username;
    $sasl = Authen::SASL->new(
      mechanism => $mechanisms,
      callback  => {
        user     => $username,
        pass     => $password,
        authname => $username,
      }
    );
  }

  # We should probably allow the user to pass the host, but I don't
  # currently know and SASL mechanisms that are used by smtp that need it
  my ($hostname) = split /:/, ${*$self}{'net_pop3_host'};
  my $client = eval { $sasl->client_new('pop', $hostname, 0) };

  unless ($client) {
    my $mech = $sasl->mechanism;
    $self->set_status(
      500,
      [ " Authen::SASL failure: $@",
        '(please check if your local Authen::SASL installation',
        "supports mechanism '$mech'"
      ]
    );
    return 0;
  }

  my ($token) = $client->client_start
    or do {
    my $mech = $client->mechanism;
    $self->set_status(
      500,
      [ ' Authen::SASL failure:  $client->client_start ',
        "mechanism '$mech' hostname #$hostname#",
        $client->error
      ]
    );
    return 0;
    };

  # We don't support sasl mechanisms that encrypt the socket traffic.
  # todo that we would really need to change the ISA hierarchy
  # so we don't inherit from IO::Socket, but instead hold it in an attribute

  my @cmd = ("AUTH", $client->mechanism);
  my $code;

  push @cmd, MIME::Base64::encode_base64($token, '')
    if defined $token and length $token;

  while (($code = $self->command(@cmd)->response()) == CMD_MORE) {

    my ($token) = $client->client_step(MIME::Base64::decode_base64(($self->message)[0])) or do {
      $self->set_status(
        500,
        [ ' Authen::SASL failure:  $client->client_step ',
          "mechanism '", $client->mechanism, " hostname #$hostname#, ",
          $client->error
        ]
      );
      return 0;
    };

    @cmd = (MIME::Base64::encode_base64(defined $token ? $token : '', ''));
  }

  $code == CMD_OK;
}


sub banner {
  my $this = shift;

  return ${*$this}{'net_pop3_banner'};
}

1;

__END__

