
package Net::Cmd;

require 5.001;
require Exporter;

use strict;
use vars qw(@ISA @EXPORT $VERSION);
use Carp;
use Symbol 'gensym';

BEGIN {
  if ($^O eq 'os390') {
    require Convert::EBCDIC;

    #    Convert::EBCDIC->import;
  }
}

BEGIN {
  if (!eval { require utf8 }) {
    *is_utf8 = sub { 0 };
  }
  elsif (eval { utf8::is_utf8(undef); 1 }) {
    *is_utf8 = \&utf8::is_utf8;
  }
  elsif (eval { require Encode; Encode::is_utf8(undef); 1 }) {
    *is_utf8 = \&Encode::is_utf8;
  }
  else {
    *is_utf8 = sub { $_[0] =~ /[^\x00-\xff]/ };
  }
}

$VERSION = "2.30";
@ISA     = qw(Exporter);
@EXPORT  = qw(CMD_INFO CMD_OK CMD_MORE CMD_REJECT CMD_ERROR CMD_PENDING);


sub CMD_INFO    {1}
sub CMD_OK      {2}
sub CMD_MORE    {3}
sub CMD_REJECT  {4}
sub CMD_ERROR   {5}
sub CMD_PENDING {0}

my %debug = ();

my $tr = $^O eq 'os390' ? Convert::EBCDIC->new() : undef;


sub toebcdic {
  my $cmd = shift;

  unless (exists ${*$cmd}{'net_cmd_asciipeer'}) {
    my $string    = $_[0];
    my $ebcdicstr = $tr->toebcdic($string);
    ${*$cmd}{'net_cmd_asciipeer'} = $string !~ /^\d+/ && $ebcdicstr =~ /^\d+/;
  }

  ${*$cmd}{'net_cmd_asciipeer'}
    ? $tr->toebcdic($_[0])
    : $_[0];
}


sub toascii {
  my $cmd = shift;
  ${*$cmd}{'net_cmd_asciipeer'}
    ? $tr->toascii($_[0])
    : $_[0];
}


sub _print_isa {
  no strict qw(refs);

  my $pkg = shift;
  my $cmd = $pkg;

  $debug{$pkg} ||= 0;

  my %done = ();
  my @do   = ($pkg);
  my %spc  = ($pkg, "");

  while ($pkg = shift @do) {
    next if defined $done{$pkg};

    $done{$pkg} = 1;

    my $v =
      defined ${"${pkg}::VERSION"}
      ? "(" . ${"${pkg}::VERSION"} . ")"
      : "";

    my $spc = $spc{$pkg};
    $cmd->debug_print(1, "${spc}${pkg}${v}\n");

    if (@{"${pkg}::ISA"}) {
      @spc{@{"${pkg}::ISA"}} = ("  " . $spc{$pkg}) x @{"${pkg}::ISA"};
      unshift(@do, @{"${pkg}::ISA"});
    }
  }
}


sub debug {
  @_ == 1 or @_ == 2 or croak 'usage: $obj->debug([LEVEL])';

  my ($cmd, $level) = @_;
  my $pkg    = ref($cmd) || $cmd;
  my $oldval = 0;

  if (ref($cmd)) {
    $oldval = ${*$cmd}{'net_cmd_debug'} || 0;
  }
  else {
    $oldval = $debug{$pkg} || 0;
  }

  return $oldval
    unless @_ == 2;

  $level = $debug{$pkg} || 0
    unless defined $level;

  _print_isa($pkg)
    if ($level && !exists $debug{$pkg});

  if (ref($cmd)) {
    ${*$cmd}{'net_cmd_debug'} = $level;
  }
  else {
    $debug{$pkg} = $level;
  }

  $oldval;
}


sub message {
  @_ == 1 or croak 'usage: $obj->message()';

  my $cmd = shift;

  wantarray
    ? @{${*$cmd}{'net_cmd_resp'}}
    : join("", @{${*$cmd}{'net_cmd_resp'}});
}


sub debug_text { $_[2] }


sub debug_print {
  my ($cmd, $out, $text) = @_;
  print STDERR $cmd, ($out ? '>>> ' : '<<< '), $cmd->debug_text($out, $text);
}


sub code {
  @_ == 1 or croak 'usage: $obj->code()';

  my $cmd = shift;

  ${*$cmd}{'net_cmd_code'} = "000"
    unless exists ${*$cmd}{'net_cmd_code'};

  ${*$cmd}{'net_cmd_code'};
}


sub status {
  @_ == 1 or croak 'usage: $obj->status()';

  my $cmd = shift;

  substr(${*$cmd}{'net_cmd_code'}, 0, 1);
}


sub set_status {
  @_ == 3 or croak 'usage: $obj->set_status(CODE, MESSAGE)';

  my $cmd = shift;
  my ($code, $resp) = @_;

  $resp = [$resp]
    unless ref($resp);

  (${*$cmd}{'net_cmd_code'}, ${*$cmd}{'net_cmd_resp'}) = ($code, $resp);

  1;
}


sub command {
  my $cmd = shift;

  unless (defined fileno($cmd)) {
    $cmd->set_status("599", "Connection closed");
    return $cmd;
  }


  $cmd->dataend()
    if (exists ${*$cmd}{'net_cmd_last_ch'});

  if (scalar(@_)) {
    local $SIG{PIPE} = 'IGNORE' unless $^O eq 'MacOS';

    my $str = join(
      " ",
      map {
        /\n/
          ? do { my $n = $_; $n =~ tr/\n/ /; $n }
          : $_;
        } @_
    );
    $str = $cmd->toascii($str) if $tr;
    $str .= "\015\012";

    my $len = length $str;
    my $swlen;

    $cmd->close
      unless (defined($swlen = syswrite($cmd, $str, $len)) && $swlen == $len);

    $cmd->debug_print(1, $str)
      if ($cmd->debug);

    ${*$cmd}{'net_cmd_resp'} = [];       # the response
    ${*$cmd}{'net_cmd_code'} = "000";    # Made this one up :-)
  }

  $cmd;
}


sub ok {
  @_ == 1 or croak 'usage: $obj->ok()';

  my $code = $_[0]->code;
  0 < $code && $code < 400;
}


sub unsupported {
  my $cmd = shift;

  ${*$cmd}{'net_cmd_resp'} = ['Unsupported command'];
  ${*$cmd}{'net_cmd_code'} = 580;
  0;
}


sub getline {
  my $cmd = shift;

  ${*$cmd}{'net_cmd_lines'} ||= [];

  return shift @{${*$cmd}{'net_cmd_lines'}}
    if scalar(@{${*$cmd}{'net_cmd_lines'}});

  my $partial = defined(${*$cmd}{'net_cmd_partial'}) ? ${*$cmd}{'net_cmd_partial'} : "";
  my $fd      = fileno($cmd);

  return undef
    unless defined $fd;

  my $rin = "";
  vec($rin, $fd, 1) = 1;

  my $buf;

  until (scalar(@{${*$cmd}{'net_cmd_lines'}})) {
    my $timeout = $cmd->timeout || undef;
    my $rout;

    my $select_ret = select($rout = $rin, undef, undef, $timeout);
    if ($select_ret > 0) {
      unless (sysread($cmd, $buf = "", 1024)) {
        carp(ref($cmd) . ": Unexpected EOF on command channel")
          if $cmd->debug;
        $cmd->close;
        return undef;
      }

      substr($buf, 0, 0) = $partial;    ## prepend from last sysread

      my @buf = split(/\015?\012/, $buf, -1);    ## break into lines

      $partial = pop @buf;

      push(@{${*$cmd}{'net_cmd_lines'}}, map {"$_\n"} @buf);

    }
    else {
      my $msg = $select_ret ? "Error or Interrupted: $!" : "Timeout";
      carp("$cmd: $msg") if ($cmd->debug);
      return undef;
    }
  }

  ${*$cmd}{'net_cmd_partial'} = $partial;

  if ($tr) {
    foreach my $ln (@{${*$cmd}{'net_cmd_lines'}}) {
      $ln = $cmd->toebcdic($ln);
    }
  }

  shift @{${*$cmd}{'net_cmd_lines'}};
}


sub ungetline {
  my ($cmd, $str) = @_;

  ${*$cmd}{'net_cmd_lines'} ||= [];
  unshift(@{${*$cmd}{'net_cmd_lines'}}, $str);
}


sub parse_response {
  return ()
    unless $_[1] =~ s/^(\d\d\d)(.?)//o;
  ($1, $2 eq "-");
}


sub response {
  my $cmd = shift;
  my ($code, $more) = (undef) x 2;

  ${*$cmd}{'net_cmd_resp'} ||= [];

  while (1) {
    my $str = $cmd->getline();

    return CMD_ERROR
      unless defined($str);

    $cmd->debug_print(0, $str)
      if ($cmd->debug);

    ($code, $more) = $cmd->parse_response($str);
    unless (defined $code) {
      $cmd->ungetline($str);
      $@ = $str;   # $@ used as tunneling hack
      last;
    }

    ${*$cmd}{'net_cmd_code'} = $code;

    push(@{${*$cmd}{'net_cmd_resp'}}, $str);

    last unless ($more);
  }

  return undef unless defined $code;
  substr($code, 0, 1);
}


sub read_until_dot {
  my $cmd = shift;
  my $fh  = shift;
  my $arr = [];

  while (1) {
    my $str = $cmd->getline() or return undef;

    $cmd->debug_print(0, $str)
      if ($cmd->debug & 4);

    last if ($str =~ /^\.\r?\n/o);

    $str =~ s/^\.\././o;

    if (defined $fh) {
      print $fh $str;
    }
    else {
      push(@$arr, $str);
    }
  }

  $arr;
}


sub datasend {
  my $cmd  = shift;
  my $arr  = @_ == 1 && ref($_[0]) ? $_[0] : \@_;
  my $line = join("", @$arr);

  # encode to individual utf8 bytes if
  # $line is a string (in internal UTF-8)
  utf8::encode($line) if is_utf8($line);

  return 0 unless defined(fileno($cmd));

  my $last_ch = ${*$cmd}{'net_cmd_last_ch'};

  # We have not send anything yet, so last_ch = "\012" means we are at the start of a line
  $last_ch = ${*$cmd}{'net_cmd_last_ch'} = "\012" unless defined $last_ch;

  return 1 unless length $line;

  if ($cmd->debug) {
    foreach my $b (split(/\n/, $line)) {
      $cmd->debug_print(1, "$b\n");
    }
  }

  $line =~ tr/\r\n/\015\012/ unless "\r" eq "\015";

  my $first_ch = '';

  if ($last_ch eq "\015") {
    # Remove \012 so it does not get prefixed with another \015 below
    # and escape the . if there is one following it because the fixup
    # below will not find it
    $first_ch = "\012" if $line =~ s/^\012(\.?)/$1$1/;
  }
  elsif ($last_ch eq "\012") {
    # Fixup below will not find the . as the first character of the buffer
    $first_ch = "." if $line =~ /^\./;
  }

  $line =~ s/\015?\012(\.?)/\015\012$1$1/sg;

  substr($line, 0, 0) = $first_ch;

  ${*$cmd}{'net_cmd_last_ch'} = substr($line, -1, 1);

  my $len    = length($line);
  my $offset = 0;
  my $win    = "";
  vec($win, fileno($cmd), 1) = 1;
  my $timeout = $cmd->timeout || undef;

  local $SIG{PIPE} = 'IGNORE' unless $^O eq 'MacOS';

  while ($len) {
    my $wout;
    my $s = select(undef, $wout = $win, undef, $timeout);
    if ((defined $s and $s > 0) or -f $cmd)    # -f for testing on win32
    {
      my $w = syswrite($cmd, $line, $len, $offset);
      unless (defined($w)) {
        carp("$cmd: $!") if $cmd->debug;
        return undef;
      }
      $len -= $w;
      $offset += $w;
    }
    else {
      carp("$cmd: Timeout") if ($cmd->debug);
      return undef;
    }
  }

  1;
}


sub rawdatasend {
  my $cmd  = shift;
  my $arr  = @_ == 1 && ref($_[0]) ? $_[0] : \@_;
  my $line = join("", @$arr);

  return 0 unless defined(fileno($cmd));

  return 1
    unless length($line);

  if ($cmd->debug) {
    my $b = "$cmd>>> ";
    print STDERR $b, join("\n$b", split(/\n/, $line)), "\n";
  }

  my $len    = length($line);
  my $offset = 0;
  my $win    = "";
  vec($win, fileno($cmd), 1) = 1;
  my $timeout = $cmd->timeout || undef;

  local $SIG{PIPE} = 'IGNORE' unless $^O eq 'MacOS';
  while ($len) {
    my $wout;
    if (select(undef, $wout = $win, undef, $timeout) > 0) {
      my $w = syswrite($cmd, $line, $len, $offset);
      unless (defined($w)) {
        carp("$cmd: $!") if $cmd->debug;
        return undef;
      }
      $len -= $w;
      $offset += $w;
    }
    else {
      carp("$cmd: Timeout") if ($cmd->debug);
      return undef;
    }
  }

  1;
}


sub dataend {
  my $cmd = shift;

  return 0 unless defined(fileno($cmd));

  my $ch = ${*$cmd}{'net_cmd_last_ch'};
  my $tosend;

  if (!defined $ch) {
    return 1;
  }
  elsif ($ch ne "\012") {
    $tosend = "\015\012";
  }

  $tosend .= ".\015\012";

  local $SIG{PIPE} = 'IGNORE' unless $^O eq 'MacOS';

  $cmd->debug_print(1, ".\n")
    if ($cmd->debug);

  syswrite($cmd, $tosend, length $tosend);

  delete ${*$cmd}{'net_cmd_last_ch'};

  $cmd->response() == CMD_OK;
}

sub tied_fh {
  my $cmd = shift;
  ${*$cmd}{'net_cmd_readbuf'} = '';
  my $fh = gensym();
  tie *$fh, ref($cmd), $cmd;
  return $fh;
}

sub TIEHANDLE {
  my $class = shift;
  my $cmd   = shift;
  return $cmd;
}

sub READ {
  my $cmd = shift;
  my ($len, $offset) = @_[1, 2];
  return unless exists ${*$cmd}{'net_cmd_readbuf'};
  my $done = 0;
  while (!$done and length(${*$cmd}{'net_cmd_readbuf'}) < $len) {
    ${*$cmd}{'net_cmd_readbuf'} .= $cmd->getline() or return;
    $done++ if ${*$cmd}{'net_cmd_readbuf'} =~ s/^\.\r?\n\Z//m;
  }

  $_[0] = '';
  substr($_[0], $offset + 0) = substr(${*$cmd}{'net_cmd_readbuf'}, 0, $len);
  substr(${*$cmd}{'net_cmd_readbuf'}, 0, $len) = '';
  delete ${*$cmd}{'net_cmd_readbuf'} if $done;

  return length $_[0];
}


sub READLINE {
  my $cmd = shift;

  # in this context, we use the presence of readbuf to
  # indicate that we have not yet reached the eof
  return unless exists ${*$cmd}{'net_cmd_readbuf'};
  my $line = $cmd->getline;
  return if $line =~ /^\.\r?\n/;
  $line;
}


sub PRINT {
  my $cmd = shift;
  my ($buf, $len, $offset) = @_;
  $len ||= length($buf);
  $offset += 0;
  return unless $cmd->datasend(substr($buf, $offset, $len));
  ${*$cmd}{'net_cmd_sending'}++;    # flag that we should call dataend()
  return $len;
}


sub CLOSE {
  my $cmd = shift;
  my $r = exists(${*$cmd}{'net_cmd_sending'}) ? $cmd->dataend : 1;
  delete ${*$cmd}{'net_cmd_readbuf'};
  delete ${*$cmd}{'net_cmd_sending'};
  $r;
}

1;

__END__


