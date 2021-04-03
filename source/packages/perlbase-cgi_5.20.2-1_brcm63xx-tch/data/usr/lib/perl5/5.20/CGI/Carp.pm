package CGI::Carp;
use if $] >= 5.019, 'deprecate';


require 5.000;
use Exporter;
BEGIN { 
  require Carp; 
  *CORE::GLOBAL::die = \&CGI::Carp::die;
}

use File::Spec;

@ISA = qw(Exporter);
@EXPORT = qw(confess croak carp);
@EXPORT_OK = qw(carpout fatalsToBrowser warningsToBrowser wrap set_message set_die_handler set_progname cluck ^name= die);

$main::SIG{__WARN__}=\&CGI::Carp::warn;

$CGI::Carp::VERSION     = '3.64';
$CGI::Carp::CUSTOM_MSG  = undef;
$CGI::Carp::DIE_HANDLER = undef;
$CGI::Carp::TO_BROWSER  = 1;


sub import {
    my $pkg = shift;
    my(%routines);
    my(@name);
    if (@name=grep(/^name=/,@_))
      {
        my($n) = (split(/=/,$name[0]))[1];
        set_progname($n);
        @_=grep(!/^name=/,@_);
      }

    grep($routines{$_}++,@_,@EXPORT);
    $WRAP++ if $routines{'fatalsToBrowser'} || $routines{'wrap'};
    $WARN++ if $routines{'warningsToBrowser'};
    my($oldlevel) = $Exporter::ExportLevel;
    $Exporter::ExportLevel = 1;
    Exporter::import($pkg,keys %routines);
    $Exporter::ExportLevel = $oldlevel;
    $main::SIG{__DIE__} =\&CGI::Carp::die if $routines{'fatalsToBrowser'};
}

sub realwarn { CORE::warn(@_); }
sub realdie { CORE::die(@_); }

sub id {
    my $level = shift;
    my($pack,$file,$line,$sub) = caller($level);
    my($dev,$dirs,$id) = File::Spec->splitpath($file);
    return ($file,$line,$id);
}

sub stamp {
    my $time = scalar(localtime);
    my $frame = 0;
    my ($id,$pack,$file,$dev,$dirs);
    if (defined($CGI::Carp::PROGNAME)) {
        $id = $CGI::Carp::PROGNAME;
    } else {
        do {
  	  $id = $file;
	  ($pack,$file) = caller($frame++);
        } until !$file;
    }
    ($dev,$dirs,$id) = File::Spec->splitpath($id);
    return "[$time] $id: ";
}

sub set_progname {
    $CGI::Carp::PROGNAME = shift;
    return $CGI::Carp::PROGNAME;
}


sub warn {
    my $message = shift;
    my($file,$line,$id) = id(1);
    $message .= " at $file line $line.\n" unless $message=~/\n$/;
    _warn($message) if $WARN;
    my $stamp = stamp;
    $message=~s/^/$stamp/gm;
    realwarn $message;
}

sub _warn {
    my $msg = shift;
    if ($EMIT_WARNINGS) {
	# We need to mangle the message a bit to make it a valid HTML
	# comment.  This is done by substituting similar-looking ISO
	# 8859-1 characters for <, > and -.  This is a hack.
	$msg =~ tr/<>-/\253\273\255/;
	chomp $msg;
	print STDOUT "<!-- warning: $msg -->\n";
    } else {
	push @WARNINGS, $msg;
    }
}


sub _longmess {
    my $message = Carp::longmess();
    $message =~ s,eval[^\n]+(ModPerl|Apache)/(?:Registry|Dispatch)\w*\.pm.*,,s
        if exists $ENV{MOD_PERL};
    return $message;
}

sub ineval {
  (exists $ENV{MOD_PERL} ? 0 : $^S) || _longmess() =~ /eval [\{\']/m
}

sub die {
    # if no argument is passed, propagate $@ like
    # the real die
  my ($arg,@rest) = @_ ? @_ 
                  : $@ ? "$@\t...propagated" 
                  :      "Died"
                  ;

  &$DIE_HANDLER($arg,@rest) if $DIE_HANDLER;

  # the "$arg" is done on purpose!
  # if called as die( $object, 'string' ),
  # all is stringified, just like with
  # the real 'die'
  $arg = join '' => "$arg", @rest if @rest;

  my($file,$line,$id) = id(1);

  $arg .= " at $file line $line.\n" unless ref $arg or $arg=~/\n$/;

  realdie $arg           if ineval();
  &fatalsToBrowser($arg) if ($WRAP and $CGI::Carp::TO_BROWSER);

  $arg=~s/^/ stamp() /gme if $arg =~ /\n$/ or not exists $ENV{MOD_PERL};

  $arg .= "\n" unless $arg =~ /\n$/;

  realdie $arg;
}

sub set_message {
    $CGI::Carp::CUSTOM_MSG = shift;
    return $CGI::Carp::CUSTOM_MSG;
}

sub set_die_handler {

    my ($handler) = shift;
    
    #setting SIG{__DIE__} here is necessary to catch runtime
    #errors which are not called by literally saying "die",
    #such as the line "undef->explode();". however, doing this
    #will interfere with fatalsToBrowser, which also sets 
    #SIG{__DIE__} in the import() function above (or the 
    #import() function above may interfere with this). for
    #this reason, you should choose to either set the die
    #handler here, or use fatalsToBrowser, not both. 
    $main::SIG{__DIE__} = $handler;
    
    $CGI::Carp::DIE_HANDLER = $handler; 
    
    return $CGI::Carp::DIE_HANDLER;
}

sub confess { CGI::Carp::die Carp::longmess @_; }
sub croak   { CGI::Carp::die Carp::shortmess @_; }
sub carp    { CGI::Carp::warn Carp::shortmess @_; }
sub cluck   { CGI::Carp::warn Carp::longmess @_; }

sub carpout {
    my($in) = @_;
    my($no) = fileno(to_filehandle($in));
    realdie("Invalid filehandle $in\n") unless defined $no;
    
    open(SAVEERR, ">&STDERR");
    open(STDERR, ">&$no") or 
	( print SAVEERR "Unable to redirect STDERR: $!\n" and exit(1) );
}

sub warningsToBrowser {
    $EMIT_WARNINGS = @_ ? shift : 1;
    _warn(shift @WARNINGS) while $EMIT_WARNINGS and @WARNINGS;
}

sub fatalsToBrowser {
  my $msg = shift;

  $msg = "$msg" if ref $msg;

  $msg=~s/&/&amp;/g;
  $msg=~s/>/&gt;/g;
  $msg=~s/</&lt;/g;
  $msg=~s/"/&quot;/g;

  my($wm) = $ENV{SERVER_ADMIN} ? 
    qq[the webmaster (<a href="mailto:$ENV{SERVER_ADMIN}">$ENV{SERVER_ADMIN}</a>)] :
      "this site's webmaster";
  my ($outer_message) = <<END;
For help, please send mail to $wm, giving this error message 
and the time and date of the error.
END
  ;
  my $mod_perl = exists $ENV{MOD_PERL};

  if ($CUSTOM_MSG) {
    if (ref($CUSTOM_MSG) eq 'CODE') {
      print STDOUT "Content-type: text/html\n\n" 
        unless $mod_perl;
        eval { 
            &$CUSTOM_MSG($msg); # nicer to perl 5.003 users
        };
        if ($@) { print STDERR q(error while executing the error handler: $@); }

      return;
    } else {
      $outer_message = $CUSTOM_MSG;
    }
  }

  my $mess = <<END;
<h1>Software error:</h1>
<pre>$msg</pre>
<p>
$outer_message
</p>
END
  ;

  if ($mod_perl) {
    my $r;
    if ($ENV{MOD_PERL_API_VERSION} && $ENV{MOD_PERL_API_VERSION} == 2) {
      $mod_perl = 2;
      require Apache2::RequestRec;
      require Apache2::RequestIO;
      require Apache2::RequestUtil;
      require APR::Pool;
      require ModPerl::Util;
      require Apache2::Response;
      $r = Apache2::RequestUtil->request;
    }
    else {
      $r = Apache->request;
    }
    # If bytes have already been sent, then
    # we print the message out directly.
    # Otherwise we make a custom error
    # handler to produce the doc for us.
    if ($r->bytes_sent) {
      $r->print($mess);
      $mod_perl == 2 ? ModPerl::Util::exit(0) : $r->exit;
    } else {
      # MSIE won't display a custom 500 response unless it is >512 bytes!
      if ($ENV{HTTP_USER_AGENT} =~ /MSIE/) {
        $mess = "<!-- " . (' ' x 513) . " -->\n$mess";
      }
      $r->custom_response(500,$mess);
    }
  } else {
    my $bytes_written = eval{tell STDOUT};
    if (defined $bytes_written && $bytes_written > 0) {
        print STDOUT $mess;
    }
    else {
        print STDOUT "Status: 500\n";
        print STDOUT "Content-type: text/html\n\n";
        print STDOUT $mess;
    }
  }

  warningsToBrowser(1);    # emit warnings before dying
}

sub to_filehandle {
    my $thingy = shift;
    return undef unless $thingy;
    return $thingy if UNIVERSAL::isa($thingy,'GLOB');
    return $thingy if UNIVERSAL::isa($thingy,'FileHandle');
    if (!ref($thingy)) {
	my $caller = 1;
	while (my $package = caller($caller++)) {
	    my($tmp) = $thingy=~/[\':]/ ? $thingy : "$package\:\:$thingy"; 
	    return $tmp if defined(fileno($tmp));
	}
    }
    return undef;
}

1;
