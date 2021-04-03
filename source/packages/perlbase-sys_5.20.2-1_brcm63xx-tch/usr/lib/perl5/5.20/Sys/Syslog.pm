package Sys::Syslog;
use strict;
use warnings;
use warnings::register;
use Carp;
use Exporter        qw< import >;
use File::Basename;
use POSIX           qw< strftime setlocale LC_TIME >;
use Socket          qw< :all >;
require 5.005;


{   no strict 'vars';
    $VERSION = '0.33';

    %EXPORT_TAGS = (
        standard => [qw(openlog syslog closelog setlogmask)],
        extended => [qw(setlogsock)],
        macros => [
            # levels
            qw(
                LOG_ALERT LOG_CRIT LOG_DEBUG LOG_EMERG LOG_ERR 
                LOG_INFO LOG_NOTICE LOG_WARNING
            ), 

            # standard facilities
            qw(
                LOG_AUTH LOG_AUTHPRIV LOG_CRON LOG_DAEMON LOG_FTP LOG_KERN
                LOG_LOCAL0 LOG_LOCAL1 LOG_LOCAL2 LOG_LOCAL3 LOG_LOCAL4
                LOG_LOCAL5 LOG_LOCAL6 LOG_LOCAL7 LOG_LPR LOG_MAIL LOG_NEWS
                LOG_SYSLOG LOG_USER LOG_UUCP
            ),
            # Mac OS X specific facilities
            qw( LOG_INSTALL LOG_LAUNCHD LOG_NETINFO LOG_RAS LOG_REMOTEAUTH ),
            # modern BSD specific facilities
            qw( LOG_CONSOLE LOG_NTP LOG_SECURITY ),
            # IRIX specific facilities
            qw( LOG_AUDIT LOG_LFMT ),

            # options
            qw(
                LOG_CONS LOG_PID LOG_NDELAY LOG_NOWAIT LOG_ODELAY LOG_PERROR 
            ), 

            # others macros
            qw(
                LOG_FACMASK LOG_NFACILITIES LOG_PRIMASK 
                LOG_MASK LOG_UPTO
            ), 
        ],
    );

    @EXPORT = (
        @{$EXPORT_TAGS{standard}}, 
    );

    @EXPORT_OK = (
        @{$EXPORT_TAGS{extended}}, 
        @{$EXPORT_TAGS{macros}}, 
    );

    eval {
        require XSLoader;
        XSLoader::load('Sys::Syslog', $VERSION);
        1
    } or do {
        require DynaLoader;
        push @ISA, 'DynaLoader';
        bootstrap Sys::Syslog $VERSION;
    };
}


use vars qw($host);             # host to send syslog messages to (see notes at end)

sub silent_eval (&);

use vars qw($facility);
my $connected       = 0;        # flag to indicate if we're connected or not
my $syslog_send;                # coderef of the function used to send messages
my $syslog_path     = undef;    # syslog path for "stream" and "unix" mechanisms
my $syslog_xobj     = undef;    # if defined, holds the external object used to send messages
my $transmit_ok     = 0;        # flag to indicate if the last message was transmitted
my $sock_port       = undef;    # socket port
my $sock_timeout    = 0;        # socket timeout, see below
my $current_proto   = undef;    # current mechanism used to transmit messages
my $ident           = '';       # identifiant prepended to each message
$facility           = '';       # current facility
my $maskpri         = LOG_UPTO(&LOG_DEBUG);     # current log mask

my %options = (
    ndelay  => 0, 
    noeol   => 0,
    nofatal => 0, 
    nonul   => 0,
    nowait  => 0, 
    perror  => 0, 
    pid     => 0, 
);

my @connectMethods = qw(native tcp udp unix pipe stream console);
if ($^O eq "freebsd" or $^O eq "linux") {
    @connectMethods = grep { $_ ne 'udp' } @connectMethods;
}

EVENTLOG: {
    my $is_Win32 = $^O =~ /Win32/i;

    if (can_load("Sys::Syslog::Win32", $is_Win32)) {
        unshift @connectMethods, 'eventlog';
    }
}

my @defaultMethods = @connectMethods;
my @fallbackMethods = ();


$sock_timeout = 0.001 if $^O =~ /darwin|gnukfreebsd/;


if (not defined &warnings::warnif) {
    *warnings::warnif = sub {
        goto &warnings::warn if warnings::enabled(__PACKAGE__)
    }
}

my $err_sub = $options{nofatal} ? \&warnings::warnif : \&croak;


sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.
    no strict 'vars';
    my $constname;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    croak "Sys::Syslog::constant() not defined" if $constname eq 'constant';
    my ($error, $val) = constant($constname);
    croak $error if $error;
    no strict 'refs';
    *$AUTOLOAD = sub { $val };
    goto &$AUTOLOAD;
}


sub openlog {
    ($ident, my $logopt, $facility) = @_;

    # default values
    $ident    ||= basename($0) || getlogin() || getpwuid($<) || 'syslog';
    $logopt   ||= '';
    $facility ||= LOG_USER();

    for my $opt (split /\b/, $logopt) {
        $options{$opt} = 1 if exists $options{$opt}
    }

    $err_sub = delete $options{nofatal} ? \&warnings::warnif : \&croak;
    return 1 unless $options{ndelay};
    connect_log();
} 

sub closelog {
    disconnect_log() if $connected;
    $options{$_} = 0 for keys %options;
    $facility = $ident = "";
    $connected = 0;
    return 1
} 

sub setlogmask {
    my $oldmask = $maskpri;
    $maskpri = shift unless $_[0] == 0;
    $oldmask;
}


my %mechanism = (
    console => {
        check   => sub { 1 },
    },
    eventlog => {
        check   => sub { return can_load("Win32::EventLog") },
        err_msg => "no Win32 API available",
    },
    inet => {
        check   => sub { 1 },
    },
    native => {
        check   => sub { 1 },
    },
    pipe => {
        check   => sub {
            ($syslog_path) = grep { defined && length && -p && -w _ }
                                $syslog_path, &_PATH_LOG, "/dev/log";
            return $syslog_path ? 1 : 0
        },
        err_msg => "path not available",
    },
    stream => {
        check   => sub {
            if (not defined $syslog_path) {
                my @try = qw(/dev/log /dev/conslog);
                unshift @try, &_PATH_LOG  if length &_PATH_LOG;
                ($syslog_path) = grep { -w } @try;
            }
            return defined $syslog_path && -w $syslog_path
        },
        err_msg => "could not find any writable device",
    },
    tcp => {
        check   => sub {
            return 1 if defined $sock_port;

            if (getservbyname('syslog', 'tcp') || getservbyname('syslogng', 'tcp')) {
                $host = $syslog_path;
                return 1
            }
            else {
                return
            }
        },
        err_msg => "TCP service unavailable",
    },
    udp => {
        check   => sub {
            return 1 if defined $sock_port;

            if (getservbyname('syslog', 'udp')) {
                $host = $syslog_path;
                return 1
            }
            else {
                return
            }
        },
        err_msg => "UDP service unavailable",
    },
    unix => {
        check   => sub {
            my @try = ($syslog_path, &_PATH_LOG);
            ($syslog_path) = grep { defined && length && -w } @try;
            return defined $syslog_path && -w $syslog_path
        },
        err_msg => "path not available",
    },
);
 
sub setlogsock {
    my %opt;

    # handle arguments
    # - old API: setlogsock($sock_type, $sock_path, $sock_timeout)
    # - new API: setlogsock(\%options)
    croak "setlogsock(): Invalid number of arguments"
        unless @_ >= 1 and @_ <= 3;

    if (my $ref = ref $_[0]) {
        if ($ref eq "HASH") {
            %opt = %{ $_[0] };
            croak "setlogsock(): No argument given" unless keys %opt;
        }
        elsif ($ref eq "ARRAY") {
            @opt{qw< type path timeout >} = @_;
        }
        else {
            croak "setlogsock(): Unexpected \L$ref\E reference"
        }
    }
    else {
        @opt{qw< type path timeout >} = @_;
    }

    # check socket type, remove invalid ones
    my $diag_invalid_type = "setlogsock(): Invalid type%s; must be one of "
                          . join ", ", map { "'$_'" } sort keys %mechanism;
    croak sprintf $diag_invalid_type, "" unless defined $opt{type};
    my @sock_types = ref $opt{type} eq "ARRAY" ? @{$opt{type}} : ($opt{type});
    my @tmp;

    for my $sock_type (@sock_types) {
        carp sprintf $diag_invalid_type, " '$sock_type'" and next
            unless exists $mechanism{$sock_type};
        push @tmp, "tcp", "udp" and next  if $sock_type eq "inet";
        push @tmp, $sock_type;
    }

    @sock_types = @tmp;

    # set global options
    $syslog_path  = $opt{path}    if defined $opt{path};
    $host         = $opt{host}    if defined $opt{host};
    $sock_timeout = $opt{timeout} if defined $opt{timeout};
    $sock_port    = $opt{port}    if defined $opt{port};

    disconnect_log() if $connected;
    $transmit_ok = 0;
    @fallbackMethods = ();
    @connectMethods = ();
    my $found = 0;

    # check each given mechanism and test if it can be used on the current system
    for my $sock_type (@sock_types) {
        if ( $mechanism{$sock_type}{check}->() ) {
            push @connectMethods, $sock_type;
            $found = 1;
        }
        else {
            warnings::warnif("setlogsock(): type='$sock_type': "
                           . $mechanism{$sock_type}{err_msg});
        }
    }

    # if no mechanism worked from the given ones, use the default ones
    @connectMethods = @defaultMethods unless @connectMethods;

    return $found;
}

sub syslog {
    my ($priority, $mask, @args) = @_;
    my ($message, $buf);
    my (@words, $num, $numpri, $numfac, $sum);
    my $failed = undef;
    my $fail_time = undef;
    my $error = $!;

    # if $ident is undefined, it means openlog() wasn't previously called
    # so do it now in order to have sensible defaults
    openlog() unless $ident;

    local $facility = $facility;    # may need to change temporarily.

    croak "syslog: expecting argument \$priority" unless defined $priority;
    croak "syslog: expecting argument \$format"   unless defined $mask;

    if ($priority =~ /^\d+$/) {
        $numpri = LOG_PRI($priority);
        $numfac = LOG_FAC($priority) << 3;
    }
    elsif ($priority =~ /^\w+/) {
        # Allow "level" or "level|facility".
        @words = split /\W+/, $priority, 2;

        undef $numpri;
        undef $numfac;

        for my $word (@words) {
            next if length $word == 0;

            # Translate word to number.
            $num = xlate($word);

            if ($num < 0) {
                croak "syslog: invalid level/facility: $word"
            }
            elsif ($num <= LOG_PRIMASK() and $word ne "kern") {
                croak "syslog: too many levels given: $word"
                    if defined $numpri;
                $numpri = $num;
            }
            else {
                croak "syslog: too many facilities given: $word"
                    if defined $numfac;
                $facility = $word if $word =~ /^[A-Za-z]/;
                $numfac = $num;
            }
        }
    }
    else {
        croak "syslog: invalid level/facility: $priority"
    }

    croak "syslog: level must be given" unless defined $numpri;

    # don't log if priority is below mask level
    return 0 unless LOG_MASK($numpri) & $maskpri;

    if (not defined $numfac) {  # Facility not specified in this call.
	$facility = 'user' unless $facility;
	$numfac = xlate($facility);
    }

    connect_log() unless $connected;

    if ($mask =~ /%m/) {
        # escape percent signs for sprintf()
        $error =~ s/%/%%/g if @args;
        # replace %m with $error, if preceded by an even number of percent signs
        $mask =~ s/(?<!%)((?:%%)*)%m/$1$error/g;
    }

    $mask .= "\n" unless $mask =~ /\n$/;
    $message = @args ? sprintf($mask, @args) : $mask;

    if ($current_proto eq 'native') {
        $buf = $message;
    }
    elsif ($current_proto eq 'eventlog') {
        $buf = $message;
    }
    else {
        my $whoami = $ident;
        $whoami .= "[$$]" if $options{pid};

        $sum = $numpri + $numfac;
        my $oldlocale = setlocale(LC_TIME);
        setlocale(LC_TIME, 'C');
        my $timestamp = strftime "%b %d %H:%M:%S", localtime;
        setlocale(LC_TIME, $oldlocale);

        # construct the stream that will be transmitted
        $buf = "<$sum>$timestamp $whoami: $message";

        # add (or not) a newline
        $buf .= "\n" if !$options{noeol} and rindex($buf, "\n") == -1;

        # add (or not) a NUL character
        $buf .= "\0" if !$options{nonul};
    }

    # handle PERROR option
    # "native" mechanism already handles it by itself
    if ($options{perror} and $current_proto ne 'native') {
        my $whoami = $ident;
        $whoami .= "[$$]" if $options{pid};
        print STDERR "$whoami: $message\n";
    }

    # it's possible that we'll get an error from sending
    # (e.g. if method is UDP and there is no UDP listener,
    # then we'll get ECONNREFUSED on the send). So what we
    # want to do at this point is to fallback onto a different
    # connection method.
    while (scalar @fallbackMethods || $syslog_send) {
	if ($failed && (time - $fail_time) > 60) {
	    # it's been a while... maybe things have been fixed
	    @fallbackMethods = ();
	    disconnect_log();
	    $transmit_ok = 0; # make it look like a fresh attempt
	    connect_log();
        }

	if ($connected && !connection_ok()) {
	    # Something was OK, but has now broken. Remember coz we'll
	    # want to go back to what used to be OK.
	    $failed = $current_proto unless $failed;
	    $fail_time = time;
	    disconnect_log();
	}

	connect_log() unless $connected;
	$failed = undef if ($current_proto && $failed && $current_proto eq $failed);

	if ($syslog_send) {
            if ($syslog_send->($buf, $numpri, $numfac)) {
		$transmit_ok++;
		return 1;
	    }
	    # typically doesn't happen, since errors are rare from write().
	    disconnect_log();
	}
    }
    # could not send, could not fallback onto a working
    # connection method. Lose.
    return 0;
}

sub _syslog_send_console {
    my ($buf) = @_;

    # The console print is a method which could block
    # so we do it in a child process and always return success
    # to the caller.
    if (my $pid = fork) {

	if ($options{nowait}) {
	    return 1;
	} else {
	    if (waitpid($pid, 0) >= 0) {
	    	return ($? >> 8);
	    } else {
		# it's possible that the caller has other
		# plans for SIGCHLD, so let's not interfere
		return 1;
	    }
	}
    } else {
        if (open(CONS, ">/dev/console")) {
	    my $ret = print CONS $buf . "\r";  # XXX: should this be \x0A ?
	    POSIX::_exit($ret) if defined $pid;
	    close CONS;
	}

	POSIX::_exit(0) if defined $pid;
    }
}

sub _syslog_send_stream {
    my ($buf) = @_;
    # XXX: this only works if the OS stream implementation makes a write 
    # look like a putmsg() with simple header. For instance it works on 
    # Solaris 8 but not Solaris 7.
    # To be correct, it should use a STREAMS API, but perl doesn't have one.
    return syswrite(SYSLOG, $buf, length($buf));
}

sub _syslog_send_pipe {
    my ($buf) = @_;
    return print SYSLOG $buf;
}

sub _syslog_send_socket {
    my ($buf) = @_;
    return syswrite(SYSLOG, $buf, length($buf));
    #return send(SYSLOG, $buf, 0);
}

sub _syslog_send_native {
    my ($buf, $numpri, $numfac) = @_;
    syslog_xs($numpri|$numfac, $buf);
    return 1;
}


sub xlate {
    my ($name) = @_;

    return $name+0 if $name =~ /^\s*\d+\s*$/;
    $name = uc $name;
    $name = "LOG_$name" unless $name =~ /^LOG_/;

    # ExtUtils::Constant 0.20 introduced a new way to implement
    # constants, called ProxySubs.  When it was used to generate
    # the C code, the constant() function no longer returns the 
    # correct value.  Therefore, we first try a direct call to 
    # constant(), and if the value is an error we try to call the 
    # constant by its full name. 
    my $value = constant($name);

    if (index($value, "not a valid") >= 0) {
        $name = "Sys::Syslog::$name";
        $value = eval { no strict "refs"; &$name };
        $value = $@ unless defined $value;
    }

    $value = -1 if index($value, "not a valid") >= 0;

    return defined $value ? $value : -1;
}


sub connect_log {
    @fallbackMethods = @connectMethods unless scalar @fallbackMethods;

    if ($transmit_ok && $current_proto) {
        # Retry what we were on, because it has worked in the past.
	unshift(@fallbackMethods, $current_proto);
    }

    $connected = 0;
    my @errs = ();
    my $proto = undef;

    while ($proto = shift @fallbackMethods) {
	no strict 'refs';
	my $fn = "connect_$proto";
	$connected = &$fn(\@errs) if defined &$fn;
	last if $connected;
    }

    $transmit_ok = 0;
    if ($connected) {
	$current_proto = $proto;
        my ($old) = select(SYSLOG); $| = 1; select($old);
    } else {
	@fallbackMethods = ();
        $err_sub->(join "\n\t- ", "no connection to syslog available", @errs);
        return undef;
    }
}

sub connect_tcp {
    my ($errs) = @_;

    my $proto = getprotobyname('tcp');
    if (!defined $proto) {
	push @$errs, "getprotobyname failed for tcp";
	return 0;
    }

    my $port = $sock_port || getservbyname('syslog', 'tcp');
    $port = getservbyname('syslogng', 'tcp') unless defined $port;
    if (!defined $port) {
	push @$errs, "getservbyname failed for syslog/tcp and syslogng/tcp";
	return 0;
    }

    my $addr;
    if (defined $host) {
        $addr = inet_aton($host);
        if (!$addr) {
	    push @$errs, "can't lookup $host";
	    return 0;
	}
    } else {
        $addr = INADDR_LOOPBACK;
    }
    $addr = sockaddr_in($port, $addr);

    if (!socket(SYSLOG, AF_INET, SOCK_STREAM, $proto)) {
	push @$errs, "tcp socket: $!";
	return 0;
    }

    setsockopt(SYSLOG, SOL_SOCKET, SO_KEEPALIVE, 1);
    if (silent_eval { IPPROTO_TCP() }) {
        # These constants don't exist in 5.005. They were added in 1999
        setsockopt(SYSLOG, IPPROTO_TCP(), TCP_NODELAY(), 1);
    }
    if (!connect(SYSLOG, $addr)) {
	push @$errs, "tcp connect: $!";
	return 0;
    }

    $syslog_send = \&_syslog_send_socket;

    return 1;
}

sub connect_udp {
    my ($errs) = @_;

    my $proto = getprotobyname('udp');
    if (!defined $proto) {
	push @$errs, "getprotobyname failed for udp";
	return 0;
    }

    my $port = $sock_port || getservbyname('syslog', 'udp');
    if (!defined $port) {
	push @$errs, "getservbyname failed for syslog/udp";
	return 0;
    }

    my $addr;
    if (defined $host) {
        $addr = inet_aton($host);
        if (!$addr) {
	    push @$errs, "can't lookup $host";
	    return 0;
	}
    } else {
        $addr = INADDR_LOOPBACK;
    }
    $addr = sockaddr_in($port, $addr);

    if (!socket(SYSLOG, AF_INET, SOCK_DGRAM, $proto)) {
	push @$errs, "udp socket: $!";
	return 0;
    }
    if (!connect(SYSLOG, $addr)) {
	push @$errs, "udp connect: $!";
	return 0;
    }

    # We want to check that the UDP connect worked. However the only
    # way to do that is to send a message and see if an ICMP is returned
    _syslog_send_socket("");
    if (!connection_ok()) {
	push @$errs, "udp connect: nobody listening";
	return 0;
    }

    $syslog_send = \&_syslog_send_socket;

    return 1;
}

sub connect_stream {
    my ($errs) = @_;
    # might want syslog_path to be variable based on syslog.h (if only
    # it were in there!)
    $syslog_path = '/dev/conslog' unless defined $syslog_path; 

    if (!-w $syslog_path) {
	push @$errs, "stream $syslog_path is not writable";
	return 0;
    }

    require Fcntl;

    if (!sysopen(SYSLOG, $syslog_path, Fcntl::O_WRONLY(), 0400)) {
	push @$errs, "stream can't open $syslog_path: $!";
	return 0;
    }

    $syslog_send = \&_syslog_send_stream;

    return 1;
}

sub connect_pipe {
    my ($errs) = @_;

    $syslog_path ||= &_PATH_LOG || "/dev/log";

    if (not -w $syslog_path) {
        push @$errs, "$syslog_path is not writable";
        return 0;
    }

    if (not open(SYSLOG, ">$syslog_path")) {
        push @$errs, "can't write to $syslog_path: $!";
        return 0;
    }

    $syslog_send = \&_syslog_send_pipe;

    return 1;
}

sub connect_unix {
    my ($errs) = @_;

    $syslog_path ||= _PATH_LOG() if length _PATH_LOG();

    if (not defined $syslog_path) {
        push @$errs, "_PATH_LOG not available in syslog.h and no user-supplied socket path";
	return 0;
    }

    if (not (-S $syslog_path or -c _)) {
        push @$errs, "$syslog_path is not a socket";
	return 0;
    }

    my $addr = sockaddr_un($syslog_path);
    if (!$addr) {
	push @$errs, "can't locate $syslog_path";
	return 0;
    }
    if (!socket(SYSLOG, AF_UNIX, SOCK_STREAM, 0)) {
        push @$errs, "unix stream socket: $!";
	return 0;
    }

    if (!connect(SYSLOG, $addr)) {
        if (!socket(SYSLOG, AF_UNIX, SOCK_DGRAM, 0)) {
	    push @$errs, "unix dgram socket: $!";
	    return 0;
	}
        if (!connect(SYSLOG, $addr)) {
	    push @$errs, "unix dgram connect: $!";
	    return 0;
	}
    }

    $syslog_send = \&_syslog_send_socket;

    return 1;
}

sub connect_native {
    my ($errs) = @_;
    my $logopt = 0;

    # reconstruct the numeric equivalent of the options
    for my $opt (keys %options) {
        $logopt += xlate($opt) if $options{$opt}
    }

    openlog_xs($ident, $logopt, xlate($facility));
    $syslog_send = \&_syslog_send_native;

    return 1;
}

sub connect_eventlog {
    my ($errs) = @_;

    $syslog_xobj = Sys::Syslog::Win32::_install();
    $syslog_send = \&Sys::Syslog::Win32::_syslog_send;

    return 1;
}

sub connect_console {
    my ($errs) = @_;
    if (!-w '/dev/console') {
	push @$errs, "console is not writable";
	return 0;
    }
    $syslog_send = \&_syslog_send_console;
    return 1;
}

sub connection_ok {
    return 1 if defined $current_proto and (
        $current_proto eq 'native' or $current_proto eq 'console'
        or $current_proto eq 'eventlog'
    );

    my $rin = '';
    vec($rin, fileno(SYSLOG), 1) = 1;
    my $ret = select $rin, undef, $rin, $sock_timeout;
    return ($ret ? 0 : 1);
}

sub disconnect_log {
    $connected = 0;
    $syslog_send = undef;

    if (defined $current_proto and $current_proto eq 'native') {
        closelog_xs();
        unshift @fallbackMethods, $current_proto;
        $current_proto = undef;
        return 1;
    }
    elsif (defined $current_proto and $current_proto eq 'eventlog') {
        $syslog_xobj->Close();
        unshift @fallbackMethods, $current_proto;
        $current_proto = undef;
        return 1;
    }

    return close SYSLOG;
}


sub silent_eval (&) {
    local($SIG{__DIE__}, $SIG{__WARN__}, $@);
    return eval { $_[0]->() }
}

sub can_load {
    my ($module, $verbose) = @_;
    local($SIG{__DIE__}, $SIG{__WARN__}, $@);
    my $loaded = eval "use $module; 1";
    warn $@ if not $loaded and $verbose;
    return $loaded
}


"Eighth Rule: read the documentation."

__END__


