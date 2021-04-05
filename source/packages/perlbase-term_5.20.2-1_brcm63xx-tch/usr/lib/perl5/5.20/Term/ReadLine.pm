
use strict;

package Term::ReadLine::Stub;
our @ISA = qw'Term::ReadLine::Tk Term::ReadLine::TermCap';

$DB::emacs = $DB::emacs;	# To pacify -w
our @rl_term_set;
*rl_term_set = \@Term::ReadLine::TermCap::rl_term_set;

sub PERL_UNICODE_STDIN () { 0x0001 }

sub ReadLine {'Term::ReadLine::Stub'}
sub readline {
  my $self = shift;
  my ($in,$out,$str) = @$self;
  my $prompt = shift;
  print $out $rl_term_set[0], $prompt, $rl_term_set[1], $rl_term_set[2]; 
  $self->register_Tk 
     if not $Term::ReadLine::registered and $Term::ReadLine::toloop;
  #$str = scalar <$in>;
  $str = $self->get_line;
  utf8::upgrade($str)
      if (${^UNICODE} & PERL_UNICODE_STDIN || defined ${^ENCODING}) &&
         utf8::valid($str);
  print $out $rl_term_set[3]; 
  # bug in 5.000: chomping empty string creates length -1:
  chomp $str if defined $str;
  $str;
}
sub addhistory {}

sub findConsole {
    my $console;
    my $consoleOUT;

    if (-e "/dev/tty" and $^O ne 'MSWin32') {
	$console = "/dev/tty";
    } elsif (-e "con" or $^O eq 'MSWin32' or $^O eq 'msys') {
       $console = 'CONIN$';
       $consoleOUT = 'CONOUT$';
    } elsif ($^O eq 'VMS') {
	$console = "sys\$command";
    } elsif ($^O eq 'os2' && !$DB::emacs) {
	$console = "/dev/con";
    } else {
	$console = undef;
    }

    $consoleOUT = $console unless defined $consoleOUT;
    $console = "&STDIN" unless defined $console;
    if ($console eq "/dev/tty" && !open(my $fh, "<", $console)) {
      $console = "&STDIN";
      undef($consoleOUT);
    }
    if (!defined $consoleOUT) {
      $consoleOUT = defined fileno(STDERR) && $^O ne 'MSWin32' ? "&STDERR" : "&STDOUT";
    }
    ($console,$consoleOUT);
}

sub new {
  die "method new called with wrong number of arguments" 
    unless @_==2 or @_==4;
  #local (*FIN, *FOUT);
  my ($FIN, $FOUT, $ret);
  if (@_==2) {
    my($console, $consoleOUT) = $_[0]->findConsole;


    # the Windows CONIN$ needs GENERIC_WRITE mode to allow
    # a SetConsoleMode() if we end up using Term::ReadKey
    open FIN, (  $^O eq 'MSWin32' && $console eq 'CONIN$' ) ? "+<$console" :
                                                              "<$console";
    open FOUT,">$consoleOUT";

    #OUT->autoflush(1);		# Conflicts with debugger?
    my $sel = select(FOUT);
    $| = 1;				# for DB::OUT
    select($sel);
    $ret = bless [\*FIN, \*FOUT];
  } else {			# Filehandles supplied
    $FIN = $_[2]; $FOUT = $_[3];
    #OUT->autoflush(1);		# Conflicts with debugger?
    my $sel = select($FOUT);
    $| = 1;				# for DB::OUT
    select($sel);
    $ret = bless [$FIN, $FOUT];
  }
  if ($ret->Features->{ornaments} 
      and not ($ENV{PERL_RL} and $ENV{PERL_RL} =~ /\bo\w*=0/)) {
    local $Term::ReadLine::termcap_nowarn = 1;
    $ret->ornaments(1);
  }
  return $ret;
}

sub newTTY {
  my ($self, $in, $out) = @_;
  $self->[0] = $in;
  $self->[1] = $out;
  my $sel = select($out);
  $| = 1;				# for DB::OUT
  select($sel);
}

sub IN { shift->[0] }
sub OUT { shift->[1] }
sub MinLine { undef }
sub Attribs { {} }

my %features = (tkRunning => 1, ornaments => 1, 'newTTY' => 1);
sub Features { \%features }


package Term::ReadLine;		# So late to allow the above code be defined?

our $VERSION = '1.14';

my ($which) = exists $ENV{PERL_RL} ? split /\s+/, $ENV{PERL_RL} : undef;
if ($which) {
  if ($which =~ /\bgnu\b/i){
    eval "use Term::ReadLine::Gnu;";
  } elsif ($which =~ /\bperl\b/i) {
    eval "use Term::ReadLine::Perl;";
  } elsif ($which =~ /^(Stub|TermCap|Tk)$/) {
    # it is already in memory to avoid false exception as seen in:
    # PERL_RL=Stub perl -e'$SIG{__DIE__} = sub { print @_ }; require Term::ReadLine'
  } else {
    eval "use Term::ReadLine::$which;";
  }
} elsif (defined $which and $which ne '') {	# Defined but false
  # Do nothing fancy
} else {
  eval "use Term::ReadLine::Gnu; 1" or eval "use Term::ReadLine::EditLine; 1" or eval "use Term::ReadLine::Perl; 1";
}


our @ISA;
if (defined &Term::ReadLine::Gnu::readline) {
  @ISA = qw(Term::ReadLine::Gnu Term::ReadLine::Stub);
} elsif (defined &Term::ReadLine::EditLine::readline) {
  @ISA = qw(Term::ReadLine::EditLine Term::ReadLine::Stub);
} elsif (defined &Term::ReadLine::Perl::readline) {
  @ISA = qw(Term::ReadLine::Perl Term::ReadLine::Stub);
} elsif (defined $which && defined &{"Term::ReadLine::$which\::readline"}) {
  @ISA = "Term::ReadLine::$which";
} else {
  @ISA = qw(Term::ReadLine::Stub);
}

package Term::ReadLine::TermCap;

our @rl_term_set = ("","","","");
our $rl_term_set = ',,,';

our $terminal;
sub LoadTermCap {
  return if defined $terminal;
  
  require Term::Cap;
  $terminal = Tgetent Term::Cap ({OSPEED => 9600}); # Avoid warning.
}

sub ornaments {
  shift;
  return $rl_term_set unless @_;
  $rl_term_set = shift;
  $rl_term_set ||= ',,,';
  $rl_term_set = 'us,ue,md,me' if $rl_term_set eq '1';
  my @ts = split /,/, $rl_term_set, 4;
  eval { LoadTermCap };
  unless (defined $terminal) {
    warn("Cannot find termcap: $@\n") unless $Term::ReadLine::termcap_nowarn;
    $rl_term_set = ',,,';
    return;
  }
  @rl_term_set = map {$_ ? $terminal->Tputs($_,1) || '' : ''} @ts;
  return $rl_term_set;
}


package Term::ReadLine::Tk;


my ($giveup);

sub Tk_loop{
    if (ref $Term::ReadLine::toloop)
    {
        $Term::ReadLine::toloop->[0]->($Term::ReadLine::toloop->[2]);
    }
    else
    {
        Tk::DoOneEvent(0) until $giveup;
        $giveup = 0;
    }
};

sub register_Tk {
    my $self = shift;
    unless ($Term::ReadLine::registered++)
    {
        if (ref $Term::ReadLine::toloop)
        {
            $Term::ReadLine::toloop->[2] = $Term::ReadLine::toloop->[1]->($self->IN) if $Term::ReadLine::toloop->[1];
        }
        else
        {
            Tk->fileevent($self->IN,'readable',sub { $giveup = 1});
        }
    }
};

sub tkRunning {
  $Term::ReadLine::toloop = $_[1] if @_ > 1;
  $Term::ReadLine::toloop;
}

sub event_loop {
    shift;

    # T::RL::Gnu and T::RL::Perl check that this exists, if not,
    # it doesn't call the loop.  Those modules will need to be
    # fixed before this can be removed.
    if (not defined &Tk::DoOneEvent)
    {
        *Tk::DoOneEvent = sub {
            die "what?"; # this shouldn't be called.
        }
    }

    # store the callback in toloop, again so that other modules will
    # recognise it and call us for the loop.
    $Term::ReadLine::toloop = [ @_ ] if @_ > 0; # 0 because we shifted off $self.
    $Term::ReadLine::toloop;
}

sub PERL_UNICODE_STDIN () { 0x0001 }

sub get_line {
  my $self = shift;
  my ($in,$out,$str) = @$self;

  if ($Term::ReadLine::toloop) {
    $self->register_Tk if not $Term::ReadLine::registered;
    $self->Tk_loop;
  }

  local ($/) = "\n";
  $str = <$in>;

  utf8::upgrade($str)
      if (${^UNICODE} & PERL_UNICODE_STDIN || defined ${^ENCODING}) &&
         utf8::valid($str);
  print $out $rl_term_set[3];
  # bug in 5.000: chomping empty string creates length -1:
  chomp $str if defined $str;

  $str;
}

1;

