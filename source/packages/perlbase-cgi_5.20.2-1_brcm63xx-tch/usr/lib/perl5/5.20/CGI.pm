package CGI;
require 5.008001;
use if $] >= 5.019, 'deprecate';
use Carp 'croak';





$CGI::revision = '$Id: CGI.pm,v 1.266 2009/07/30 16:32:34 lstein Exp $';
$CGI::VERSION='3.65';

use CGI::Util qw(rearrange rearrange_header make_attributes unescape escape expires ebcdic2ascii ascii2ebcdic);


use constant XHTML_DTD => ['-//W3C//DTD XHTML 1.0 Transitional//EN',
                           'http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd'];

{
  local $^W = 0;
  $TAINTED = substr("$0$^X",0,0);
}

$MOD_PERL            = 0; # no mod_perl by default

$POST_MAX            = -1; # no limit to uploaded files
$DISABLE_UPLOADS     = 0;

@SAVED_SYMBOLS = ();


sub initialize_globals {
    # Set this to 1 to enable copious autoloader debugging messages
    $AUTOLOAD_DEBUG = 0;

    # Set this to 1 to generate XTML-compatible output
    $XHTML = 1;

    # Change this to the preferred DTD to print in start_html()
    # or use default_dtd('text of DTD to use');
    $DEFAULT_DTD = [ '-//W3C//DTD HTML 4.01 Transitional//EN',
		     'http://www.w3.org/TR/html4/loose.dtd' ] ;

    # Set this to 1 to enable NOSTICKY scripts
    # or: 
    #    1) use CGI '-nosticky';
    #    2) $CGI::NOSTICKY = 1;
    $NOSTICKY = 0;

    # Set this to 1 to enable NPH scripts
    # or: 
    #    1) use CGI qw(-nph)
    #    2) CGI::nph(1)
    #    3) print header(-nph=>1)
    $NPH = 0;

    # Set this to 1 to enable debugging from @ARGV
    # Set to 2 to enable debugging from STDIN
    $DEBUG = 1;

    # Set this to 1 to make the temporary files created
    # during file uploads safe from prying eyes
    # or do...
    #    1) use CGI qw(:private_tempfiles)
    #    2) CGI::private_tempfiles(1);
    $PRIVATE_TEMPFILES = 0;

    # Set this to 1 to generate automatic tab indexes
    $TABINDEX = 0;

    # Set this to 1 to cause files uploaded in multipart documents
    # to be closed, instead of caching the file handle
    # or:
    #    1) use CGI qw(:close_upload_files)
    #    2) $CGI::close_upload_files(1);
    # Uploads with many files run out of file handles.
    # Also, for performance, since the file is already on disk,
    # it can just be renamed, instead of read and written.
    $CLOSE_UPLOAD_FILES = 0;

    # Automatically determined -- don't change
    $EBCDIC = 0;

    # Change this to 1 to suppress redundant HTTP headers
    $HEADERS_ONCE = 0;

    # separate the name=value pairs by semicolons rather than ampersands
    $USE_PARAM_SEMICOLONS = 1;

    # Do not include undefined params parsed from query string
    # use CGI qw(-no_undef_params);
    $NO_UNDEF_PARAMS = 0;

    # return everything as utf-8
    $PARAM_UTF8      = 0;

    # Other globals that you shouldn't worry about.
    undef $Q;
    $BEEN_THERE = 0;
    $DTD_PUBLIC_IDENTIFIER = "";
    undef @QUERY_PARAM;
    undef %EXPORT;
    undef $QUERY_CHARSET;
    undef %QUERY_FIELDNAMES;
    undef %QUERY_TMPFILES;

    # prevent complaints by mod_perl
    1;
}


initialize_globals();

unless ($OS) {
    unless ($OS = $^O) {
	require Config;
	$OS = $Config::Config{'osname'};
    }
}
if ($OS =~ /^MSWin/i) {
  $OS = 'WINDOWS';
} elsif ($OS =~ /^VMS/i) {
  $OS = 'VMS';
} elsif ($OS =~ /^dos/i) {
  $OS = 'DOS';
} elsif ($OS =~ /^MacOS/i) {
    $OS = 'MACINTOSH';
} elsif ($OS =~ /^os2/i) {
    $OS = 'OS2';
} elsif ($OS =~ /^epoc/i) {
    $OS = 'EPOC';
} elsif ($OS =~ /^cygwin/i) {
    $OS = 'CYGWIN';
} elsif ($OS =~ /^NetWare/i) {
    $OS = 'NETWARE';
} else {
    $OS = 'UNIX';
}

$needs_binmode = $OS=~/^(WINDOWS|DOS|OS2|MSWin|CYGWIN|NETWARE)/;

$DefaultClass = 'CGI' unless defined $CGI::DefaultClass;

$AutoloadClass = $DefaultClass unless defined $CGI::AutoloadClass;

$SL = {
     UNIX    => '/',  OS2 => '\\', EPOC      => '/', CYGWIN => '/', NETWARE => '/',
     WINDOWS => '\\', DOS => '\\', MACINTOSH => ':', VMS    => '/'
    }->{$OS};

$IIS++ if defined($ENV{'SERVER_SOFTWARE'}) && $ENV{'SERVER_SOFTWARE'}=~/IIS/;

$PERLEX++ if defined($ENV{'GATEWAY_INTERFACE'}) && $ENV{'GATEWAY_INTERFACE'} =~ /^CGI-PerlEx/;

if (exists $ENV{MOD_PERL} && ! $PERLEX) {
  # mod_perl handlers may run system() on scripts using CGI.pm;
  # Make sure so we don't get fooled by inherited $ENV{MOD_PERL}
  if (exists $ENV{MOD_PERL_API_VERSION} && $ENV{MOD_PERL_API_VERSION} == 2) {
    $MOD_PERL = 2;
    require Apache2::Response;
    require Apache2::RequestRec;
    require Apache2::RequestUtil;
    require Apache2::RequestIO;
    require APR::Pool;
  } else {
    $MOD_PERL = 1;
    require Apache;
  }
}

$EBCDIC = "\t" ne "\011";
if ($OS eq 'VMS') {
  $CRLF = "\n";
} elsif ($EBCDIC) {
  $CRLF= "\r\n";
} else {
  $CRLF = "\015\012";
}

if ($needs_binmode) {
    $CGI::DefaultClass->binmode(\*main::STDOUT);
    $CGI::DefaultClass->binmode(\*main::STDIN);
    $CGI::DefaultClass->binmode(\*main::STDERR);
}

%EXPORT_TAGS = (
		':html2'=>['h1'..'h6',qw/p br hr ol ul li dl dt dd menu code var strong em
			   tt u i b blockquote pre img a address cite samp dfn html head
			   base body Link nextid title meta kbd start_html end_html
			   input Select option comment charset escapeHTML/],
		':html3'=>[qw/div table caption th td TR Tr sup Sub strike applet Param nobr
			   embed basefont style span layer ilayer font frameset frame script small big Area Map/],
                ':html4'=>[qw/abbr acronym bdo col colgroup del fieldset iframe
                            ins label legend noframes noscript object optgroup Q 
                            thead tbody tfoot/], 
		':netscape'=>[qw/blink fontsize center/],
		':form'=>[qw/textfield textarea filefield password_field hidden checkbox checkbox_group 
			  submit reset defaults radio_group popup_menu button autoEscape
			  scrolling_list image_button start_form end_form startform endform
			  start_multipart_form end_multipart_form isindex tmpFileName uploadInfo URL_ENCODED MULTIPART/],
		':cgi'=>[qw/param upload path_info path_translated request_uri url self_url script_name 
			 cookie Dump
			 raw_cookie request_method query_string Accept user_agent remote_host content_type
			 remote_addr referer server_name server_software server_port server_protocol virtual_port
			 virtual_host remote_ident auth_type http append
			 save_parameters restore_parameters param_fetch
			 remote_user user_name header redirect import_names put 
			 Delete Delete_all url_param cgi_error/],
		':ssl' => [qw/https/],
		':cgi-lib' => [qw/ReadParse PrintHeader HtmlTop HtmlBot SplitParam Vars/],
		':html' => [qw/:html2 :html3 :html4 :netscape/],
		':standard' => [qw/:html2 :html3 :html4 :form :cgi/],
		':push' => [qw/multipart_init multipart_start multipart_end multipart_final/],
		':all' => [qw/:html2 :html3 :netscape :form :cgi :internal :html4/]
		);


sub can {
	my($class, $method) = @_;

	# See if UNIVERSAL::can finds it.

	if (my $func = $class -> SUPER::can($method) ){
		return $func;
	}

	# Try to compile the function.

	eval {
		# _compile looks at $AUTOLOAD for the function name.

		local $AUTOLOAD = join "::", $class, $method;
		&_compile;
	};

	# Now that the function is loaded (if it exists)
	# just use UNIVERSAL::can again to do the work.

	return $class -> SUPER::can($method);
}

sub import {
    my $self = shift;

    # This causes modules to clash.
    undef %EXPORT_OK;
    undef %EXPORT;

    $self->_setup_symbols(@_);
    my ($callpack, $callfile, $callline) = caller;

    # To allow overriding, search through the packages
    # Till we find one in which the correct subroutine is defined.
    my @packages = ($self,@{"$self\:\:ISA"});
    for $sym (keys %EXPORT) {
	my $pck;
	my $def = ${"$self\:\:AutoloadClass"} || $DefaultClass;
	for $pck (@packages) {
	    if (defined(&{"$pck\:\:$sym"})) {
		$def = $pck;
		last;
	    }
	}
	*{"${callpack}::$sym"} = \&{"$def\:\:$sym"};
    }
}

sub compile {
    my $pack = shift;
    $pack->_setup_symbols('-compile',@_);
}

sub expand_tags {
    my($tag) = @_;
    return ("start_$1","end_$1") if $tag=~/^(?:\*|start_|end_)(.+)/;
    my(@r);
    return ($tag) unless $EXPORT_TAGS{$tag};
    for (@{$EXPORT_TAGS{$tag}}) {
	push(@r,&expand_tags($_));
    }
    return @r;
}

sub new {
  my($class,@initializer) = @_;
  my $self = {};

  bless $self,ref $class || $class || $DefaultClass;

  # always use a tempfile
  $self->{'use_tempfile'} = 1;

  if (ref($initializer[0])
      && (UNIVERSAL::isa($initializer[0],'Apache')
	  ||
	  UNIVERSAL::isa($initializer[0],'Apache2::RequestRec')
	 )) {
    $self->r(shift @initializer);
  }
 if (ref($initializer[0]) 
     && (UNIVERSAL::isa($initializer[0],'CODE'))) {
    $self->upload_hook(shift @initializer, shift @initializer);
    $self->{'use_tempfile'} = shift @initializer if (@initializer > 0);
  }
  if ($MOD_PERL) {
    if ($MOD_PERL == 1) {
      $self->r(Apache->request) unless $self->r;
      my $r = $self->r;
      $r->register_cleanup(\&CGI::_reset_globals);
      $self->_setup_symbols(@SAVED_SYMBOLS) if @SAVED_SYMBOLS;
    }
    else {
      # XXX: once we have the new API
      # will do a real PerlOptions -SetupEnv check
      $self->r(Apache2::RequestUtil->request) unless $self->r;
      my $r = $self->r;
      $r->subprocess_env unless exists $ENV{REQUEST_METHOD};
      $r->pool->cleanup_register(\&CGI::_reset_globals);
      $self->_setup_symbols(@SAVED_SYMBOLS) if @SAVED_SYMBOLS;
    }
    undef $NPH;
  }
  $self->_reset_globals if $PERLEX;
  $self->init(@initializer);
  return $self;
}

sub DESTROY {
  my $self = shift;
  if ($OS eq 'WINDOWS' || $OS eq 'VMS') {
    for my $href (values %{$self->{'.tmpfiles'}}) {
      $href->{hndl}->DESTROY if defined $href->{hndl};
      $href->{name}->DESTROY if defined $href->{name};
    }
  }
}

sub r {
  my $self = shift;
  my $r = $self->{'.r'};
  $self->{'.r'} = shift if @_;
  $r;
}

sub upload_hook {
  my $self;
  if (ref $_[0] eq 'CODE') {
    $CGI::Q = $self = $CGI::DefaultClass->new(@_);
  } else {
    $self = shift;
  }
  my ($hook,$data,$use_tempfile) = @_;
  $self->{'.upload_hook'} = $hook;
  $self->{'.upload_data'} = $data;
  $self->{'use_tempfile'} = $use_tempfile if defined $use_tempfile;
}

sub param {
    my($self,@p) = self_or_default(@_);
    return $self->all_parameters unless @p;
    my($name,$value,@other);

    # For compatibility between old calling style and use_named_parameters() style, 
    # we have to special case for a single parameter present.
    if (@p > 1) {
	($name,$value,@other) = rearrange([NAME,[DEFAULT,VALUE,VALUES]],@p);
	my(@values);

	if (substr($p[0],0,1) eq '-') {
	    @values = defined($value) ? (ref($value) && ref($value) eq 'ARRAY' ? @{$value} : $value) : ();
	} else {
	    for ($value,@other) {
		push(@values,$_) if defined($_);
	    }
	}
	# If values is provided, then we set it.
	if (@values or defined $value) {
	    $self->add_parameter($name);
	    $self->{param}{$name}=[@values];
	}
    } else {
	$name = $p[0];
    }

    return unless defined($name) && $self->{param}{$name};

    my @result = @{$self->{param}{$name}};

    if ($PARAM_UTF8) {
      eval "require Encode; 1;" unless Encode->can('decode'); # bring in these functions
      @result = map {ref $_ ? $_ : $self->_decode_utf8($_) } @result;
    }

    return wantarray ?  @result : $result[0];
}

sub _decode_utf8 {
    my ($self, $val) = @_;

    if (Encode::is_utf8($val)) {
        return $val;
    }
    else {
        return Encode::decode(utf8 => $val);
    }
}

sub self_or_default {
    return @_ if defined($_[0]) && (!ref($_[0])) &&($_[0] eq 'CGI');
    unless (defined($_[0]) && 
	    (ref($_[0]) eq 'CGI' || UNIVERSAL::isa($_[0],'CGI')) # slightly optimized for common case
	    ) {
	$Q = $CGI::DefaultClass->new unless defined($Q);
	unshift(@_,$Q);
    }
    return wantarray ? @_ : $Q;
}

sub self_or_CGI {
    local $^W=0;                # prevent a warning
    if (defined($_[0]) &&
	(substr(ref($_[0]),0,3) eq 'CGI' 
	 || UNIVERSAL::isa($_[0],'CGI'))) {
	return @_;
    } else {
	return ($DefaultClass,@_);
    }
}



sub init {
  my $self = shift;
  my($query_string,$meth,$content_length,$fh,@lines) = ('','','','');

  my $is_xforms;

  my $initializer = shift;  # for backward compatibility
  local($/) = "\n";

    # set autoescaping on by default
    $self->{'escape'} = 1;

    # if we get called more than once, we want to initialize
    # ourselves from the original query (which may be gone
    # if it was read from STDIN originally.)
    if (@QUERY_PARAM && !defined($initializer)) {
        for my $name (@QUERY_PARAM) {
            my $val = $QUERY_PARAM{$name}; # always an arrayref;
            $self->param('-name'=>$name,'-value'=> $val);
            if (defined $val and ref $val eq 'ARRAY') {
                for my $fh (grep {defined($_) && ref($_) && defined(fileno($_))} @$val) {
                   seek($fh,0,0); # reset the filehandle.  
                }

            }
        }
        $self->charset($QUERY_CHARSET);
        $self->{'.fieldnames'} = {%QUERY_FIELDNAMES};
        $self->{'.tmpfiles'}   = {%QUERY_TMPFILES};
        return;
    }

    $meth=$ENV{'REQUEST_METHOD'} if defined($ENV{'REQUEST_METHOD'});
    $content_length = defined($ENV{'CONTENT_LENGTH'}) ? $ENV{'CONTENT_LENGTH'} : 0;

    $fh = to_filehandle($initializer) if $initializer;

    # set charset to the safe ISO-8859-1
    $self->charset('ISO-8859-1');

  METHOD: {

      # avoid unreasonably large postings
      if (($POST_MAX > 0) && ($content_length > $POST_MAX)) {
	#discard the post, unread
	$self->cgi_error("413 Request entity too large");
	last METHOD;
      }

      # Process multipart postings, but only if the initializer is
      # not defined.
      if ($meth eq 'POST'
	  && defined($ENV{'CONTENT_TYPE'})
	  && $ENV{'CONTENT_TYPE'}=~m|^multipart/form-data|
	  && !defined($initializer)
	  ) {
	  my($boundary) = $ENV{'CONTENT_TYPE'} =~ /boundary=\"?([^\";,]+)\"?/;
	  $self->read_multipart($boundary,$content_length);
	  last METHOD;
      } 

      # Process XForms postings. We know that we have XForms in the
      # following cases:
      # method eq 'POST' && content-type eq 'application/xml'
      # method eq 'POST' && content-type =~ /multipart\/related.+start=/
      # There are more cases, actually, but for now, we don't support other
      # methods for XForm posts.
      # In a XForm POST, the QUERY_STRING is parsed normally.
      # If the content-type is 'application/xml', we just set the param
      # XForms:Model (referring to the xml syntax) param containing the
      # unparsed XML data.
      # In the case of multipart/related we set XForms:Model as above, but
      # the other parts are available as uploads with the Content-ID as the
      # the key.
      # See the URL below for XForms specs on this issue.
      # http://www.w3.org/TR/2006/REC-xforms-20060314/slice11.html#submit-options
      if ($meth eq 'POST' && defined($ENV{'CONTENT_TYPE'})) {
              if ($ENV{'CONTENT_TYPE'} eq 'application/xml') {
                      my($param) = 'XForms:Model';
                      my($value) = '';
                      $self->add_parameter($param);
                      $self->read_from_client(\$value,$content_length,0)
                        if $content_length > 0;
                      push (@{$self->{param}{$param}},$value);
                      $is_xforms = 1;
              } elsif ($ENV{'CONTENT_TYPE'} =~ /multipart\/related.+boundary=\"?([^\";,]+)\"?.+start=\"?\<?([^\"\>]+)\>?\"?/) {
                      my($boundary,$start) = ($1,$2);
                      my($param) = 'XForms:Model';
                      $self->add_parameter($param);
                      my($value) = $self->read_multipart_related($start,$boundary,$content_length,0);
                      push (@{$self->{param}{$param}},$value);
                      if ($MOD_PERL) {
                              $query_string = $self->r->args;
                      } else {
                              $query_string = $ENV{'QUERY_STRING'} if defined $ENV{'QUERY_STRING'};
                              $query_string ||= $ENV{'REDIRECT_QUERY_STRING'} if defined $ENV{'REDIRECT_QUERY_STRING'};
                      }
                      $is_xforms = 1;
              }
      }


      # If initializer is defined, then read parameters
      # from it.
      if (!$is_xforms && defined($initializer)) {
	  if (UNIVERSAL::isa($initializer,'CGI')) {
	      $query_string = $initializer->query_string;
	      last METHOD;
	  }
	  if (ref($initializer) && ref($initializer) eq 'HASH') {
	      for (keys %$initializer) {
		  $self->param('-name'=>$_,'-value'=>$initializer->{$_});
	      }
	      last METHOD;
	  }

          if (defined($fh) && ($fh ne '')) {
              while (my $line = <$fh>) {
                  chomp $line;
                  last if $line =~ /^=$/;
                  push(@lines,$line);
              }
              # massage back into standard format
              if ("@lines" =~ /=/) {
                  $query_string=join("&",@lines);
              } else {
                  $query_string=join("+",@lines);
              }
              last METHOD;
          }

	  # last chance -- treat it as a string
	  $initializer = $$initializer if ref($initializer) eq 'SCALAR';
	  $query_string = $initializer;

	  last METHOD;
      }

      # If method is GET, HEAD or DELETE, fetch the query from
      # the environment.
      if ($is_xforms || $meth=~/^(GET|HEAD|DELETE)$/) {
	  if ($MOD_PERL) {
	    $query_string = $self->r->args;
	  } else {
	      $query_string = $ENV{'QUERY_STRING'} if defined $ENV{'QUERY_STRING'};
	      $query_string ||= $ENV{'REDIRECT_QUERY_STRING'} if defined $ENV{'REDIRECT_QUERY_STRING'};
	  }
	  last METHOD;
      }

      if ($meth eq 'POST' || $meth eq 'PUT') {
	  if ( $content_length > 0 ) {
	    $self->read_from_client(\$query_string,$content_length,0);
	  }
	  # Some people want to have their cake and eat it too!
	  # Uncomment this line to have the contents of the query string
	  # APPENDED to the POST data.
	  # $query_string .= (length($query_string) ? '&' : '') . $ENV{'QUERY_STRING'} if defined $ENV{'QUERY_STRING'};
	  last METHOD;
      }

      # If $meth is not of GET, POST, PUT or HEAD, assume we're
      #   being debugged offline.
      # Check the command line and then the standard input for data.
      # We use the shellwords package in order to behave the way that
      # UN*X programmers expect.
      if ($DEBUG)
      {
          my $cmdline_ret = read_from_cmdline();
          $query_string = $cmdline_ret->{'query_string'};
          if (defined($cmdline_ret->{'subpath'}))
          {
              $self->path_info($cmdline_ret->{'subpath'});
          }
      }
  }

    if (!$is_xforms && ($meth eq 'POST' || $meth eq 'PUT')
        && defined($ENV{'CONTENT_TYPE'})
        && $ENV{'CONTENT_TYPE'} !~ m|^application/x-www-form-urlencoded|
	&& $ENV{'CONTENT_TYPE'} !~ m|^multipart/form-data| ) {
	    my($param) = $meth . 'DATA' ;
	    $self->add_parameter($param) ;
	    push (@{$self->{param}{$param}},$query_string);
	    undef $query_string ;
    }

    # We now have the query string in hand.  We do slightly
    # different things for keyword lists and parameter lists.
    if (defined $query_string && length $query_string) {
	if ($query_string =~ /[&=;]/) {
	    $self->parse_params($query_string);
	} else {
	    $self->add_parameter('keywords');
	    $self->{param}{'keywords'} = [$self->parse_keywordlist($query_string)];
	}
    }

    # Special case.  Erase everything if there is a field named
    # .defaults.
    if ($self->param('.defaults')) {
      $self->delete_all();
    }

    # hash containing our defined fieldnames
    $self->{'.fieldnames'} = {};
    for ($self->param('.cgifields')) {
	$self->{'.fieldnames'}->{$_}++;
    }
    
    # Clear out our default submission button flag if present
    $self->delete('.submit');
    $self->delete('.cgifields');

    $self->save_request unless defined $initializer;
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

sub put {
    my($self,@p) = self_or_default(@_);
    $self->print(@p);
}

sub print {
    shift;
    CORE::print(@_);
}

sub cgi_error {
    my ($self,$err) = self_or_default(@_);
    $self->{'.cgi_error'} = $err if defined $err;
    return $self->{'.cgi_error'};
}

sub save_request {
    my($self) = @_;
    # We're going to play with the package globals now so that if we get called
    # again, we initialize ourselves in exactly the same way.  This allows
    # us to have several of these objects.
    @QUERY_PARAM = $self->param; # save list of parameters
    for (@QUERY_PARAM) {
      next unless defined $_;
      $QUERY_PARAM{$_}=$self->{param}{$_};
    }
    $QUERY_CHARSET = $self->charset;
    %QUERY_FIELDNAMES = %{$self->{'.fieldnames'}};
    %QUERY_TMPFILES   = %{ $self->{'.tmpfiles'} || {} };
}

sub parse_params {
    my($self,$tosplit) = @_;
    my(@pairs) = split(/[&;]/,$tosplit);
    my($param,$value);
    for (@pairs) {
	($param,$value) = split('=',$_,2);
	next unless defined $param;
	next if $NO_UNDEF_PARAMS and not defined $value;
	$value = '' unless defined $value;
	$param = unescape($param);
	$value = unescape($value);
	$self->add_parameter($param);
	push (@{$self->{param}{$param}},$value);
    }
}

sub add_parameter {
    my($self,$param)=@_;
    return unless defined $param;
    push (@{$self->{'.parameters'}},$param) 
	unless defined($self->{param}{$param});
}

sub all_parameters {
    my $self = shift;
    return () unless defined($self) && $self->{'.parameters'};
    return () unless @{$self->{'.parameters'}};
    return @{$self->{'.parameters'}};
}

sub binmode {
    return unless defined($_[1]) && ref ($_[1]) && defined fileno($_[1]);
    CORE::binmode($_[1]);
}

sub _make_tag_func {
    my ($self,$tagname) = @_;
    my $func = qq(
	sub $tagname {
         my (\$q,\$a,\@rest) = self_or_default(\@_);
         my(\$attr) = '';
	 if (ref(\$a) && ref(\$a) eq 'HASH') {
	    my(\@attr) = make_attributes(\$a,\$q->{'escape'});
	    \$attr = " \@attr" if \@attr;
	  } else {
	    unshift \@rest,\$a if defined \$a;
	  }
	);
    if ($tagname=~/start_(\w+)/i) {
	$func .= qq! return "<\L$1\E\$attr>";} !;
    } elsif ($tagname=~/end_(\w+)/i) {
	$func .= qq! return "<\L/$1\E>"; } !;
    } else {
	$func .= qq#
	    return \$XHTML ? "\L<$tagname\E\$attr />" : "\L<$tagname\E\$attr>" unless \@rest;
	    my(\$tag,\$untag) = ("\L<$tagname\E\$attr>","\L</$tagname>\E");
	    my \@result = map { "\$tag\$_\$untag" } 
                              (ref(\$rest[0]) eq 'ARRAY') ? \@{\$rest[0]} : "\@rest";
	    return "\@result";
            }#;
    }
return $func;
}

sub AUTOLOAD {
    print STDERR "CGI::AUTOLOAD for $AUTOLOAD\n" if $CGI::AUTOLOAD_DEBUG;
    my $func = &_compile;
    goto &$func;
}

sub _compile {
    my($func) = $AUTOLOAD;
    my($pack,$func_name);
    {
	local($1,$2); # this fixes an obscure variable suicide problem.
	$func=~/(.+)::([^:]+)$/;
	($pack,$func_name) = ($1,$2);
	$pack=~s/::SUPER$//;	# fix another obscure problem
	$pack = ${"$pack\:\:AutoloadClass"} || $CGI::DefaultClass
	    unless defined(${"$pack\:\:AUTOLOADED_ROUTINES"});

        my($sub) = \%{"$pack\:\:SUBS"};
        unless (%$sub) {
	   my($auto) = \${"$pack\:\:AUTOLOADED_ROUTINES"};
	   local ($@,$!);
	   eval "package $pack; $$auto";
	   croak("$AUTOLOAD: $@") if $@;
           $$auto = '';  # Free the unneeded storage (but don't undef it!!!)
       }
       my($code) = $sub->{$func_name};

       $code = "sub $AUTOLOAD { }" if (!$code and $func_name eq 'DESTROY');
       if (!$code) {
	   (my $base = $func_name) =~ s/^(start_|end_)//i;
	   if ($EXPORT{':any'} || 
	       $EXPORT{'-any'} ||
	       $EXPORT{$base} || 
	       (%EXPORT_OK || grep(++$EXPORT_OK{$_},&expand_tags(':html')))
	           && $EXPORT_OK{$base}) {
	       $code = $CGI::DefaultClass->_make_tag_func($func_name);
	   }
       }
       croak("Undefined subroutine $AUTOLOAD\n") unless $code;
       local ($@,$!);
       eval "package $pack; $code";
       if ($@) {
	   $@ =~ s/ at .*\n//;
	   croak("$AUTOLOAD: $@");
       }
    }       
    CORE::delete($sub->{$func_name});  #free storage
    return "$pack\:\:$func_name";
}

sub _selected {
  my $self = shift;
  my $value = shift;
  return '' unless $value;
  return $XHTML ? qq(selected="selected" ) : qq(selected );
}

sub _checked {
  my $self = shift;
  my $value = shift;
  return '' unless $value;
  return $XHTML ? qq(checked="checked" ) : qq(checked );
}

sub _reset_globals { initialize_globals(); }

sub _setup_symbols {
    my $self = shift;
    my $compile = 0;

    # to avoid reexporting unwanted variables
    undef %EXPORT;

    for (@_) {
	$HEADERS_ONCE++,         next if /^[:-]unique_headers$/;
	$NPH++,                  next if /^[:-]nph$/;
	$NOSTICKY++,             next if /^[:-]nosticky$/;
	$DEBUG=0,                next if /^[:-]no_?[Dd]ebug$/;
	$DEBUG=2,                next if /^[:-][Dd]ebug$/;
	$USE_PARAM_SEMICOLONS++, next if /^[:-]newstyle_urls$/;
	$PARAM_UTF8++,           next if /^[:-]utf8$/;
	$XHTML++,                next if /^[:-]xhtml$/;
	$XHTML=0,                next if /^[:-]no_?xhtml$/;
	$USE_PARAM_SEMICOLONS=0, next if /^[:-]oldstyle_urls$/;
	$PRIVATE_TEMPFILES++,    next if /^[:-]private_tempfiles$/;
	$TABINDEX++,             next if /^[:-]tabindex$/;
	$CLOSE_UPLOAD_FILES++,   next if /^[:-]close_upload_files$/;
	$EXPORT{$_}++,           next if /^[:-]any$/;
	$compile++,              next if /^[:-]compile$/;
	$NO_UNDEF_PARAMS++,      next if /^[:-]no_undef_params$/;
	
	# This is probably extremely evil code -- to be deleted some day.
	if (/^[-]autoload$/) {
	    my($pkg) = caller(1);
	    *{"${pkg}::AUTOLOAD"} = sub { 
		my($routine) = $AUTOLOAD;
		$routine =~ s/^.*::/CGI::/;
		&$routine;
	    };
	    next;
	}

	for (&expand_tags($_)) {
	    tr/a-zA-Z0-9_//cd;  # don't allow weird function names
	    $EXPORT{$_}++;
	}
    }
    _compile_all(keys %EXPORT) if $compile;
    @SAVED_SYMBOLS = @_;
}

sub charset {
  my ($self,$charset) = self_or_default(@_);
  $self->{'.charset'} = $charset if defined $charset;
  $self->{'.charset'};
}

sub element_id {
  my ($self,$new_value) = self_or_default(@_);
  $self->{'.elid'} = $new_value if defined $new_value;
  sprintf('%010d',$self->{'.elid'}++);
}

sub element_tab {
  my ($self,$new_value) = self_or_default(@_);
  $self->{'.etab'} ||= 1;
  $self->{'.etab'} = $new_value if defined $new_value;
  my $tab = $self->{'.etab'}++;
  return '' unless $TABINDEX or defined $new_value;
  return qq(tabindex="$tab" );
}

$AUTOLOADED_ROUTINES = '';      # get rid of -w warning
$AUTOLOADED_ROUTINES=<<'END_OF_AUTOLOAD';

%SUBS = (

'URL_ENCODED'=> <<'END_OF_FUNC',
sub URL_ENCODED { 'application/x-www-form-urlencoded'; }
END_OF_FUNC

'MULTIPART' => <<'END_OF_FUNC',
sub MULTIPART {  'multipart/form-data'; }
END_OF_FUNC

'SERVER_PUSH' => <<'END_OF_FUNC',
sub SERVER_PUSH { 'multipart/x-mixed-replace;boundary="' . shift() . '"'; }
END_OF_FUNC

'new_MultipartBuffer' => <<'END_OF_FUNC',
sub new_MultipartBuffer {
    my($self,$boundary,$length) = @_;
    return MultipartBuffer->new($self,$boundary,$length);
}
END_OF_FUNC

'read_from_client' => <<'END_OF_FUNC',
sub read_from_client {
    my($self, $buff, $len, $offset) = @_;
    local $^W=0;                # prevent a warning
    return $MOD_PERL
        ? $self->r->read($$buff, $len, $offset)
        : read(\*STDIN, $$buff, $len, $offset);
}
END_OF_FUNC

'delete' => <<'END_OF_FUNC',
sub delete {
    my($self,@p) = self_or_default(@_);
    my(@names) = rearrange([NAME],@p);
    my @to_delete = ref($names[0]) eq 'ARRAY' ? @$names[0] : @names;
    my %to_delete;
    for my $name (@to_delete)
    {
        CORE::delete $self->{param}{$name};
        CORE::delete $self->{'.fieldnames'}->{$name};
        $to_delete{$name}++;
    }
    @{$self->{'.parameters'}}=grep { !exists($to_delete{$_}) } $self->param();
    return;
}
END_OF_FUNC

'import_names' => <<'END_OF_FUNC',
sub import_names {
    my($self,$namespace,$delete) = self_or_default(@_);
    $namespace = 'Q' unless defined($namespace);
    die "Can't import names into \"main\"\n" if \%{"${namespace}::"} == \%::;
    if ($delete || $MOD_PERL || exists $ENV{'FCGI_ROLE'}) {
	# can anyone find an easier way to do this?
	for (keys %{"${namespace}::"}) {
	    local *symbol = "${namespace}::${_}";
	    undef $symbol;
	    undef @symbol;
	    undef %symbol;
	}
    }
    my($param,@value,$var);
    for $param ($self->param) {
	# protect against silly names
	($var = $param)=~tr/a-zA-Z0-9_/_/c;
	$var =~ s/^(?=\d)/_/;
	local *symbol = "${namespace}::$var";
	@value = $self->param($param);
	@symbol = @value;
	$symbol = $value[0];
    }
}
END_OF_FUNC

'keywords' => <<'END_OF_FUNC',
sub keywords {
    my($self,@values) = self_or_default(@_);
    # If values is provided, then we set it.
    $self->{param}{'keywords'}=[@values] if @values;
    my(@result) = defined($self->{param}{'keywords'}) ? @{$self->{param}{'keywords'}} : ();
    @result;
}
END_OF_FUNC

'Vars' => <<'END_OF_FUNC',
sub Vars {
    my $q = shift;
    my %in;
    tie(%in,CGI,$q);
    return %in if wantarray;
    return \%in;
}
END_OF_FUNC

'ReadParse' => <<'END_OF_FUNC',
sub ReadParse {
    local(*in);
    if (@_) {
	*in = $_[0];
    } else {
	my $pkg = caller();
	*in=*{"${pkg}::in"};
    }
    tie(%in,CGI);
    return scalar(keys %in);
}
END_OF_FUNC

'PrintHeader' => <<'END_OF_FUNC',
sub PrintHeader {
    my($self) = self_or_default(@_);
    return $self->header();
}
END_OF_FUNC

'HtmlTop' => <<'END_OF_FUNC',
sub HtmlTop {
    my($self,@p) = self_or_default(@_);
    return $self->start_html(@p);
}
END_OF_FUNC

'HtmlBot' => <<'END_OF_FUNC',
sub HtmlBot {
    my($self,@p) = self_or_default(@_);
    return $self->end_html(@p);
}
END_OF_FUNC

'SplitParam' => <<'END_OF_FUNC',
sub SplitParam {
    my ($param) = @_;
    my (@params) = split ("\0", $param);
    return (wantarray ? @params : $params[0]);
}
END_OF_FUNC

'MethGet' => <<'END_OF_FUNC',
sub MethGet {
    return request_method() eq 'GET';
}
END_OF_FUNC

'MethPost' => <<'END_OF_FUNC',
sub MethPost {
    return request_method() eq 'POST';
}
END_OF_FUNC

'MethPut' => <<'END_OF_FUNC',
sub MethPut {
    return request_method() eq 'PUT';
}
END_OF_FUNC

'TIEHASH' => <<'END_OF_FUNC',
sub TIEHASH {
    my $class = shift;
    my $arg   = $_[0];
    if (ref($arg) && UNIVERSAL::isa($arg,'CGI')) {
       return $arg;
    }
    return $Q ||= $class->new(@_);
}
END_OF_FUNC

'STORE' => <<'END_OF_FUNC',
sub STORE {
    my $self = shift;
    my $tag  = shift;
    my $vals = shift;
    my @vals = index($vals,"\0")!=-1 ? split("\0",$vals) : $vals;
    $self->param(-name=>$tag,-value=>\@vals);
}
END_OF_FUNC

'FETCH' => <<'END_OF_FUNC',
sub FETCH {
    return $_[0] if $_[1] eq 'CGI';
    return undef unless defined $_[0]->param($_[1]);
    return join("\0",$_[0]->param($_[1]));
}
END_OF_FUNC

'FIRSTKEY' => <<'END_OF_FUNC',
sub FIRSTKEY {
    $_[0]->{'.iterator'}=0;
    $_[0]->{'.parameters'}->[$_[0]->{'.iterator'}++];
}
END_OF_FUNC

'NEXTKEY' => <<'END_OF_FUNC',
sub NEXTKEY {
    $_[0]->{'.parameters'}->[$_[0]->{'.iterator'}++];
}
END_OF_FUNC

'EXISTS' => <<'END_OF_FUNC',
sub EXISTS {
    exists $_[0]->{param}{$_[1]};
}
END_OF_FUNC

'DELETE' => <<'END_OF_FUNC',
sub DELETE {
    $_[0]->delete($_[1]);
}
END_OF_FUNC

'CLEAR' => <<'END_OF_FUNC',
sub CLEAR {
    %{$_[0]}=();
}
END_OF_FUNC

'append' => <<'EOF',
sub append {
    my($self,@p) = self_or_default(@_);
    my($name,$value) = rearrange([NAME,[VALUE,VALUES]],@p);
    my(@values) = defined($value) ? (ref($value) ? @{$value} : $value) : ();
    if (@values) {
	$self->add_parameter($name);
	push(@{$self->{param}{$name}},@values);
    }
    return $self->param($name);
}
EOF

'delete_all' => <<'EOF',
sub delete_all {
    my($self) = self_or_default(@_);
    my @param = $self->param();
    $self->delete(@param);
}
EOF

'Delete' => <<'EOF',
sub Delete {
    my($self,@p) = self_or_default(@_);
    $self->delete(@p);
}
EOF

'Delete_all' => <<'EOF',
sub Delete_all {
    my($self,@p) = self_or_default(@_);
    $self->delete_all(@p);
}
EOF

'autoEscape' => <<'END_OF_FUNC',
sub autoEscape {
    my($self,$escape) = self_or_default(@_);
    my $d = $self->{'escape'};
    $self->{'escape'} = $escape;
    $d;
}
END_OF_FUNC


'version' => <<'END_OF_FUNC',
sub version {
    return $VERSION;
}
END_OF_FUNC

'url_param' => <<'END_OF_FUNC',
sub url_param {
    my ($self,@p) = self_or_default(@_);
    my $name = shift(@p);
    return undef unless exists($ENV{QUERY_STRING});
    unless (exists($self->{'.url_param'})) {
	$self->{'.url_param'}={}; # empty hash
	if ($ENV{QUERY_STRING} =~ /=/) {
	    my(@pairs) = split(/[&;]/,$ENV{QUERY_STRING});
	    my($param,$value);
	    for (@pairs) {
		($param,$value) = split('=',$_,2);
		$param = unescape($param);
		$value = unescape($value);
		push(@{$self->{'.url_param'}->{$param}},$value);
	    }
	} else {
        my @keywords = $self->parse_keywordlist($ENV{QUERY_STRING});
	    $self->{'.url_param'}{'keywords'} = \@keywords if @keywords;
	}
    }
    return keys %{$self->{'.url_param'}} unless defined($name);
    return () unless $self->{'.url_param'}->{$name};
    return wantarray ? @{$self->{'.url_param'}->{$name}}
                     : $self->{'.url_param'}->{$name}->[0];
}
END_OF_FUNC

'Dump' => <<'END_OF_FUNC',
sub Dump {
    my($self) = self_or_default(@_);
    my($param,$value,@result);
    return '<ul></ul>' unless $self->param;
    push(@result,"<ul>");
    for $param ($self->param) {
	my($name)=$self->_maybe_escapeHTML($param);
	push(@result,"<li><strong>$name</strong></li>");
	push(@result,"<ul>");
	for $value ($self->param($param)) {
	    $value = $self->_maybe_escapeHTML($value);
            $value =~ s/\n/<br \/>\n/g;
	    push(@result,"<li>$value</li>");
	}
	push(@result,"</ul>");
    }
    push(@result,"</ul>");
    return join("\n",@result);
}
END_OF_FUNC

'as_string' => <<'END_OF_FUNC',
sub as_string {
    &Dump(@_);
}
END_OF_FUNC

'save' => <<'END_OF_FUNC',
sub save {
    my($self,$filehandle) = self_or_default(@_);
    $filehandle = to_filehandle($filehandle);
    my($param);
    local($,) = '';  # set print field separator back to a sane value
    local($\) = '';  # set output line separator to a sane value
    for $param ($self->param) {
	my($escaped_param) = escape($param);
	my($value);
	for $value ($self->param($param)) {
	    print $filehandle "$escaped_param=",escape("$value"),"\n"
	        if length($escaped_param) or length($value);
	}
    }
    for (keys %{$self->{'.fieldnames'}}) {
          print $filehandle ".cgifields=",escape("$_"),"\n";
    }
    print $filehandle "=\n";    # end of record
}
END_OF_FUNC


'save_parameters' => <<'END_OF_FUNC',
sub save_parameters {
    my $fh = shift;
    return save(to_filehandle($fh));
}
END_OF_FUNC

'restore_parameters' => <<'END_OF_FUNC',
sub restore_parameters {
    $Q = $CGI::DefaultClass->new(@_);
}
END_OF_FUNC

'multipart_init' => <<'END_OF_FUNC',
sub multipart_init {
    my($self,@p) = self_or_default(@_);
    my($boundary,@other) = rearrange_header([BOUNDARY],@p);
    if (!$boundary) {
        $boundary = '------- =_';
        my @chrs = ('0'..'9', 'A'..'Z', 'a'..'z');
        for (1..17) {
            $boundary .= $chrs[rand(scalar @chrs)];
        }
    }

    $self->{'separator'} = "$CRLF--$boundary$CRLF";
    $self->{'final_separator'} = "$CRLF--$boundary--$CRLF";
    $type = SERVER_PUSH($boundary);
    return $self->header(
	-nph => 0,
	-type => $type,
	(map { split "=", $_, 2 } @other),
    ) . "WARNING: YOUR BROWSER DOESN'T SUPPORT THIS SERVER-PUSH TECHNOLOGY." . $self->multipart_end;
}
END_OF_FUNC


'multipart_start' => <<'END_OF_FUNC',
sub multipart_start {
    my(@header);
    my($self,@p) = self_or_default(@_);
    my($type,@other) = rearrange([TYPE],@p);
    $type = $type || 'text/html';
    push(@header,"Content-Type: $type");

    # rearrange() was designed for the HTML portion, so we
    # need to fix it up a little.
    for (@other) {
        # Don't use \s because of perl bug 21951
        next unless my($header,$value) = /([^ \r\n\t=]+)=\"?(.+?)\"?$/;
	($_ = $header) =~ s/^(\w)(.*)/$1 . lc ($2) . ': '.$self->unescapeHTML($value)/e;
    }
    push(@header,@other);
    my $header = join($CRLF,@header)."${CRLF}${CRLF}";
    return $header;
}
END_OF_FUNC


'multipart_end' => <<'END_OF_FUNC',
sub multipart_end {
    my($self,@p) = self_or_default(@_);
    return $self->{'separator'};
}
END_OF_FUNC


'multipart_final' => <<'END_OF_FUNC',
sub multipart_final {
    my($self,@p) = self_or_default(@_);
    return $self->{'final_separator'} . "WARNING: YOUR BROWSER DOESN'T SUPPORT THIS SERVER-PUSH TECHNOLOGY." . $CRLF;
}
END_OF_FUNC


'header' => <<'END_OF_FUNC',
sub header {
    my($self,@p) = self_or_default(@_);
    my(@header);

    return "" if $self->{'.header_printed'}++ and $HEADERS_ONCE;

    my($type,$status,$cookie,$target,$expires,$nph,$charset,$attachment,$p3p,@other) = 
	rearrange([['TYPE','CONTENT_TYPE','CONTENT-TYPE'],
			    'STATUS',['COOKIE','COOKIES'],'TARGET',
                            'EXPIRES','NPH','CHARSET',
                            'ATTACHMENT','P3P'],@p);

    # Since $cookie and $p3p may be array references,
    # we must stringify them before CR escaping is done.
    my @cookie;
    for (ref($cookie) eq 'ARRAY' ? @{$cookie} : $cookie) {
        my $cs = UNIVERSAL::isa($_,'CGI::Cookie') ? $_->as_string : $_;
        push(@cookie,$cs) if defined $cs and $cs ne '';
    }
    $p3p = join ' ',@$p3p if ref($p3p) eq 'ARRAY';

    # CR escaping for values, per RFC 822
    for my $header ($type,$status,@cookie,$target,$expires,$nph,$charset,$attachment,$p3p,@other) {
        if (defined $header) {
            # From RFC 822:
            # Unfolding  is  accomplished  by regarding   CRLF   immediately
            # followed  by  a  LWSP-char  as equivalent to the LWSP-char.
            $header =~ s/$CRLF(\s)/$1/g;

            # All other uses of newlines are invalid input. 
            if ($header =~ m/$CRLF|\015|\012/) {
                # shorten very long values in the diagnostic
                $header = substr($header,0,72).'...' if (length $header > 72);
                die "Invalid header value contains a newline not followed by whitespace: $header";
            }
        } 
   }

    $nph     ||= $NPH;

    $type ||= 'text/html' unless defined($type);

    # sets if $charset is given, gets if not
    $charset = $self->charset( $charset );

    # rearrange() was designed for the HTML portion, so we
    # need to fix it up a little.
    for (@other) {
        # Don't use \s because of perl bug 21951
        next unless my($header,$value) = /([^ \r\n\t=]+)=\"?(.+?)\"?$/s;
        ($_ = $header) =~ s/^(\w)(.*)/"\u$1\L$2" . ': '.$self->unescapeHTML($value)/e;
    }

    $type .= "; charset=$charset"
      if     $type ne ''
         and $type !~ /\bcharset\b/
         and defined $charset
         and $charset ne '';

    # Maybe future compatibility.  Maybe not.
    my $protocol = $ENV{SERVER_PROTOCOL} || 'HTTP/1.0';
    push(@header,$protocol . ' ' . ($status || '200 OK')) if $nph;
    push(@header,"Server: " . &server_software()) if $nph;

    push(@header,"Status: $status") if $status;
    push(@header,"Window-Target: $target") if $target;
    push(@header,"P3P: policyref=\"/w3c/p3p.xml\", CP=\"$p3p\"") if $p3p;
    # push all the cookies -- there may be several
    push(@header,map {"Set-Cookie: $_"} @cookie);
    # if the user indicates an expiration time, then we need
    # both an Expires and a Date header (so that the browser is
    # uses OUR clock)
    push(@header,"Expires: " . expires($expires,'http'))
	if $expires;
    push(@header,"Date: " . expires(0,'http')) if $expires || $cookie || $nph;
    push(@header,"Pragma: no-cache") if $self->cache();
    push(@header,"Content-Disposition: attachment; filename=\"$attachment\"") if $attachment;
    push(@header,map {ucfirst $_} @other);
    push(@header,"Content-Type: $type") if $type ne '';
    my $header = join($CRLF,@header)."${CRLF}${CRLF}";
    if (($MOD_PERL >= 1) && !$nph) {
        $self->r->send_cgi_header($header);
        return '';
    }
    return $header;
}
END_OF_FUNC

'cache' => <<'END_OF_FUNC',
sub cache {
    my($self,$new_value) = self_or_default(@_);
    $new_value = '' unless $new_value;
    if ($new_value ne '') {
	$self->{'cache'} = $new_value;
    }
    return $self->{'cache'};
}
END_OF_FUNC


'redirect' => <<'END_OF_FUNC',
sub redirect {
    my($self,@p) = self_or_default(@_);
    my($url,$target,$status,$cookie,$nph,@other) = 
         rearrange([[LOCATION,URI,URL],TARGET,STATUS,['COOKIE','COOKIES'],NPH],@p);
    $status = '302 Found' unless defined $status;
    $url ||= $self->self_url;
    my(@o);
    for (@other) { tr/\"//d; push(@o,split("=",$_,2)); }
    unshift(@o,
	 '-Status'  => $status,
	 '-Location'=> $url,
	 '-nph'     => $nph);
    unshift(@o,'-Target'=>$target) if $target;
    unshift(@o,'-Type'=>'');
    my @unescaped;
    unshift(@unescaped,'-Cookie'=>$cookie) if $cookie;
    return $self->header((map {$self->unescapeHTML($_)} @o),@unescaped);
}
END_OF_FUNC


'start_html' => <<'END_OF_FUNC',
sub start_html {
    my($self,@p) = &self_or_default(@_);
    my($title,$author,$base,$xbase,$script,$noscript,
        $target,$meta,$head,$style,$dtd,$lang,$encoding,$declare_xml,@other) = 
	rearrange([TITLE,AUTHOR,BASE,XBASE,SCRIPT,NOSCRIPT,TARGET,
                   META,HEAD,STYLE,DTD,LANG,ENCODING,DECLARE_XML],@p);

    $self->element_id(0);
    $self->element_tab(0);

    $encoding = lc($self->charset) unless defined $encoding;

    # Need to sort out the DTD before it's okay to call escapeHTML().
    my(@result,$xml_dtd);
    if ($dtd) {
        if (defined(ref($dtd)) and (ref($dtd) eq 'ARRAY')) {
            $dtd = $DEFAULT_DTD unless $dtd->[0] =~ m|^-//|;
        } else {
            $dtd = $DEFAULT_DTD unless $dtd =~ m|^-//|;
        }
    } else {
        $dtd = $XHTML ? XHTML_DTD : $DEFAULT_DTD;
    }

    $xml_dtd++ if ref($dtd) eq 'ARRAY' && $dtd->[0] =~ /\bXHTML\b/i;
    $xml_dtd++ if ref($dtd) eq '' && $dtd =~ /\bXHTML\b/i;
    push @result,qq(<?xml version="1.0" encoding="$encoding"?>) if $xml_dtd && $declare_xml;

    if (ref($dtd) && ref($dtd) eq 'ARRAY') {
        push(@result,qq(<!DOCTYPE html\n\tPUBLIC "$dtd->[0]"\n\t "$dtd->[1]">));
	$DTD_PUBLIC_IDENTIFIER = $dtd->[0];
    } else {
        push(@result,qq(<!DOCTYPE html\n\tPUBLIC "$dtd">));
	$DTD_PUBLIC_IDENTIFIER = $dtd;
    }

    # Now that we know whether we're using the HTML 3.2 DTD or not, it's okay to
    # call escapeHTML().  Strangely enough, the title needs to be escaped as
    # HTML while the author needs to be escaped as a URL.
    $title = $self->_maybe_escapeHTML($title || 'Untitled Document');
    $author = $self->escape($author);

    if ($DTD_PUBLIC_IDENTIFIER =~ /[^X]HTML (2\.0|3\.2|4\.01?)/i) {
	$lang = "" unless defined $lang;
	$XHTML = 0;
    }
    else {
	$lang = 'en-US' unless defined $lang;
    }

    my $lang_bits = $lang ne '' ? qq( lang="$lang" xml:lang="$lang") : '';
    my $meta_bits = qq(<meta http-equiv="Content-Type" content="text/html; charset=$encoding" />) 
                    if $XHTML && $encoding && !$declare_xml;

    push(@result,$XHTML ? qq(<html xmlns="http://www.w3.org/1999/xhtml"$lang_bits>\n<head>\n<title>$title</title>)
                        : ($lang ? qq(<html lang="$lang">) : "<html>")
	                  . "<head><title>$title</title>");
	if (defined $author) {
    push(@result,$XHTML ? "<link rev=\"made\" href=\"mailto:$author\" />"
			: "<link rev=\"made\" href=\"mailto:$author\">");
	}

    if ($base || $xbase || $target) {
	my $href = $xbase || $self->url('-path'=>1);
	my $t = $target ? qq/ target="$target"/ : '';
	push(@result,$XHTML ? qq(<base href="$href"$t />) : qq(<base href="$href"$t>));
    }

    if ($meta && ref($meta) && (ref($meta) eq 'HASH')) {
	for (keys %$meta) { push(@result,$XHTML ? qq(<meta name="$_" content="$meta->{$_}" />) 
			: qq(<meta name="$_" content="$meta->{$_}">)); }
    }

    my $meta_bits_set = 0;
    if( $head ) {
        if( ref $head ) {
            push @result, @$head;
            $meta_bits_set = 1 if grep { /http-equiv=["']Content-Type/i }@$head;
        }
        else {
            push @result, $head;
            $meta_bits_set = 1 if $head =~ /http-equiv=["']Content-Type/i;
        }
    }

    # handle the infrequently-used -style and -script parameters
    push(@result,$self->_style($style))   if defined $style;
    push(@result,$self->_script($script)) if defined $script;
    push(@result,$meta_bits)              if defined $meta_bits and !$meta_bits_set;

    # handle -noscript parameter
    push(@result,<<END) if $noscript;
<noscript>
$noscript
</noscript>
END
    ;
    my($other) = @other ? " @other" : '';
    push(@result,"</head>\n<body$other>\n");
    return join("\n",@result);
}
END_OF_FUNC

'_style' => <<'END_OF_FUNC',
sub _style {
    my ($self,$style) = @_;
    my (@result);

    my $type = 'text/css';
    my $rel  = 'stylesheet';


    my $cdata_start = $XHTML ? "\n<!--/* <![CDATA[ */" : "\n<!-- ";
    my $cdata_end   = $XHTML ? "\n/* ]]> */-->\n" : " -->\n";

    my @s = ref($style) eq 'ARRAY' ? @$style : $style;
    my $other = '';

    for my $s (@s) {
      if (ref($s)) {
       my($src,$code,$verbatim,$stype,$alternate,$foo,@other) =
           rearrange([qw(SRC CODE VERBATIM TYPE ALTERNATE FOO)],
                      ('-foo'=>'bar',
                       ref($s) eq 'ARRAY' ? @$s : %$s));
       my $type = defined $stype ? $stype : 'text/css';
       my $rel  = $alternate ? 'alternate stylesheet' : 'stylesheet';
       $other = "@other" if @other;

       if (ref($src) eq "ARRAY") # Check to see if the $src variable is an array reference
       { # If it is, push a LINK tag for each one
           for $src (@$src)
         {
           push(@result,$XHTML ? qq(<link rel="$rel" type="$type" href="$src" $other/>)
                             : qq(<link rel="$rel" type="$type" href="$src"$other>)) if $src;
         }
       }
       else
       { # Otherwise, push the single -src, if it exists.
         push(@result,$XHTML ? qq(<link rel="$rel" type="$type" href="$src" $other/>)
                             : qq(<link rel="$rel" type="$type" href="$src"$other>)
              ) if $src;
        }
     if ($verbatim) {
           my @v = ref($verbatim) eq 'ARRAY' ? @$verbatim : $verbatim;
           push(@result, "<style type=\"text/css\">\n$_\n</style>") for @v;
      }
      my @c = ref($code) eq 'ARRAY' ? @$code : $code if $code;
      push(@result,style({'type'=>$type},"$cdata_start\n$_\n$cdata_end")) for @c;

      } else {
           my $src = $s;
           push(@result,$XHTML ? qq(<link rel="$rel" type="$type" href="$src" $other/>)
                               : qq(<link rel="$rel" type="$type" href="$src"$other>));
      }
    }
    @result;
}
END_OF_FUNC

'_script' => <<'END_OF_FUNC',
sub _script {
    my ($self,$script) = @_;
    my (@result);

    my (@scripts) = ref($script) eq 'ARRAY' ? @$script : ($script);
    for $script (@scripts) {
    my($src,$code,$language,$charset);
    if (ref($script)) { # script is a hash
        ($src,$code,$type,$charset) =
        rearrange(['SRC','CODE',['LANGUAGE','TYPE'],'CHARSET'],
                 '-foo'=>'bar', # a trick to allow the '-' to be omitted
                 ref($script) eq 'ARRAY' ? @$script : %$script);
            $type ||= 'text/javascript';
            unless ($type =~ m!\w+/\w+!) {
                $type =~ s/[\d.]+$//;
                $type = "text/$type";
            }
    } else {
        ($src,$code,$type,$charset) = ('',$script, 'text/javascript', '');
    }

    my $comment = '//';  # javascript by default
    $comment = '#' if $type=~/perl|tcl/i;
    $comment = "'" if $type=~/vbscript/i;

    my ($cdata_start,$cdata_end);
    if ($XHTML) {
       $cdata_start    = "$comment<![CDATA[\n";
       $cdata_end     .= "\n$comment]]>";
    } else {
       $cdata_start  =  "\n<!-- Hide script\n";
       $cdata_end    = $comment;
       $cdata_end   .= " End script hiding -->\n";
   }
     my(@satts);
     push(@satts,'src'=>$src) if $src;
     push(@satts,'type'=>$type);
     push(@satts,'charset'=>$charset) if ($src && $charset);
     $code = $cdata_start . $code . $cdata_end if defined $code;
     push(@result,$self->script({@satts},$code || ''));
    }
    @result;
}
END_OF_FUNC

'end_html' => <<'END_OF_FUNC',
sub end_html {
    return "\n</body>\n</html>";
}
END_OF_FUNC



'isindex' => <<'END_OF_FUNC',
sub isindex {
    my($self,@p) = self_or_default(@_);
    my($action,@other) = rearrange([ACTION],@p);
    $action = qq/ action="$action"/ if $action;
    my($other) = @other ? " @other" : '';
    return $XHTML ? "<isindex$action$other />" : "<isindex$action$other>";
}
END_OF_FUNC


'startform' => <<'END_OF_FUNC',
sub startform {
    my($self,@p) = self_or_default(@_);

    my($method,$action,$enctype,@other) = 
	rearrange([METHOD,ACTION,ENCTYPE],@p);

    $method  = $self->_maybe_escapeHTML(lc($method || 'post'));
    $enctype = $self->_maybe_escapeHTML($enctype || &URL_ENCODED);
    if (defined $action) {
       $action = $self->_maybe_escapeHTML($action);
    }
    else {
       $action = $self->_maybe_escapeHTML($self->request_uri || $self->self_url);
    }
    $action = qq(action="$action");
    my($other) = @other ? " @other" : '';
    $self->{'.parametersToAdd'}={};
    return qq/<form method="$method" $action enctype="$enctype"$other>/;
}
END_OF_FUNC

'start_form' => <<'END_OF_FUNC',
sub start_form {
    my($self,@p) = self_or_default(@_);

    my($method,$action,$enctype,@other) = 
	rearrange([METHOD,ACTION,ENCTYPE],@p);

    $method  = $self->_maybe_escapeHTML(lc($method || 'post'));

    if( $XHTML ){
        $enctype = $self->_maybe_escapeHTML($enctype || &MULTIPART);
    }else{
        $enctype = $self->_maybe_escapeHTML($enctype || &URL_ENCODED);
    }

    if (defined $action) {
       $action = $self->_maybe_escapeHTML($action);
    }
    else {
       $action = $self->_maybe_escapeHTML($self->request_uri || $self->self_url);
    }
    $action = qq(action="$action");
    my($other) = @other ? " @other" : '';
    $self->{'.parametersToAdd'}={};
    return qq/<form method="$method" $action enctype="$enctype"$other>/;
}
END_OF_FUNC

'start_multipart_form' => <<'END_OF_FUNC',
sub start_multipart_form {
    my($self,@p) = self_or_default(@_);
    if (defined($p[0]) && substr($p[0],0,1) eq '-') {
      return $self->start_form(-enctype=>&MULTIPART,@p);
    } else {
	my($method,$action,@other) = 
	    rearrange([METHOD,ACTION],@p);
	return $self->start_form($method,$action,&MULTIPART,@other);
    }
}
END_OF_FUNC



'end_form' => <<'END_OF_FUNC',
sub end_form {
    my($self,@p) = self_or_default(@_);
    if ( $NOSTICKY ) {
        return wantarray ? ("</form>") : "\n</form>";
    } else {
        if (my @fields = $self->get_fields) {
            return wantarray ? ("<div>",@fields,"</div>","</form>")
                             : "<div>".(join '',@fields)."</div>\n</form>";
        } else {
            return "</form>";
        }
    }
}
END_OF_FUNC

'endform' => <<'END_OF_FUNC',
sub endform {
    my($self,@p) = self_or_default(@_);
    if ( $NOSTICKY ) {
        return wantarray ? ("</form>") : "\n</form>";
    } else {
        if (my @fields = $self->get_fields) {
            return wantarray ? ("<div>",@fields,"</div>","</form>")
                             : "<div>".(join '',@fields)."</div>\n</form>";
        } else {
            return "</form>";
        }
    }
}
END_OF_FUNC

'end_multipart_form' => <<'END_OF_FUNC',
sub end_multipart_form {
    &end_form;
}
END_OF_FUNC


'_textfield' => <<'END_OF_FUNC',
sub _textfield {
    my($self,$tag,@p) = self_or_default(@_);
    my($name,$default,$size,$maxlength,$override,$tabindex,@other) = 
	rearrange([NAME,[DEFAULT,VALUE,VALUES],SIZE,MAXLENGTH,[OVERRIDE,FORCE],TABINDEX],@p);

    my $current = $override ? $default : 
	(defined($self->param($name)) ? $self->param($name) : $default);

    $current = defined($current) ? $self->_maybe_escapeHTML($current,1) : '';
    $name = defined($name) ? $self->_maybe_escapeHTML($name) : '';
    my($s) = defined($size) ? qq/ size="$size"/ : '';
    my($m) = defined($maxlength) ? qq/ maxlength="$maxlength"/ : '';
    my($other) = @other ? " @other" : '';
    # this entered at cristy's request to fix problems with file upload fields
    # and WebTV -- not sure it won't break stuff
    my($value) = $current ne '' ? qq(value="$current") : '';
    $tabindex = $self->element_tab($tabindex);
    return $XHTML ? qq(<input type="$tag" name="$name" $tabindex$value$s$m$other />) 
                  : qq(<input type="$tag" name="$name" $value$s$m$other>);
}
END_OF_FUNC

'textfield' => <<'END_OF_FUNC',
sub textfield {
    my($self,@p) = self_or_default(@_);
    $self->_textfield('text',@p);
}
END_OF_FUNC


'filefield' => <<'END_OF_FUNC',
sub filefield {
    my($self,@p) = self_or_default(@_);
    $self->_textfield('file',@p);
}
END_OF_FUNC


'password_field' => <<'END_OF_FUNC',
sub password_field {
    my ($self,@p) = self_or_default(@_);
    $self->_textfield('password',@p);
}
END_OF_FUNC

'textarea' => <<'END_OF_FUNC',
sub textarea {
    my($self,@p) = self_or_default(@_);
    my($name,$default,$rows,$cols,$override,$tabindex,@other) =
	rearrange([NAME,[DEFAULT,VALUE],ROWS,[COLS,COLUMNS],[OVERRIDE,FORCE],TABINDEX],@p);

    my($current)= $override ? $default :
	(defined($self->param($name)) ? $self->param($name) : $default);

    $name = defined($name) ? $self->_maybe_escapeHTML($name) : '';
    $current = defined($current) ? $self->_maybe_escapeHTML($current) : '';
    my($r) = $rows ? qq/ rows="$rows"/ : '';
    my($c) = $cols ? qq/ cols="$cols"/ : '';
    my($other) = @other ? " @other" : '';
    $tabindex = $self->element_tab($tabindex);
    return qq{<textarea name="$name" $tabindex$r$c$other>$current</textarea>};
}
END_OF_FUNC


'button' => <<'END_OF_FUNC',
sub button {
    my($self,@p) = self_or_default(@_);

    my($label,$value,$script,$tabindex,@other) = rearrange([NAME,[VALUE,LABEL],
						            [ONCLICK,SCRIPT],TABINDEX],@p);

    $label=$self->_maybe_escapeHTML($label);
    $value=$self->_maybe_escapeHTML($value,1);
    $script=$self->_maybe_escapeHTML($script);

    $script ||= '';

    my($name) = '';
    $name = qq/ name="$label"/ if $label;
    $value = $value || $label;
    my($val) = '';
    $val = qq/ value="$value"/ if $value;
    $script = qq/ onclick="$script"/ if $script;
    my($other) = @other ? " @other" : '';
    $tabindex = $self->element_tab($tabindex);
    return $XHTML ? qq(<input type="button" $tabindex$name$val$script$other />)
                  : qq(<input type="button"$name$val$script$other>);
}
END_OF_FUNC


'submit' => <<'END_OF_FUNC',
sub submit {
    my($self,@p) = self_or_default(@_);

    my($label,$value,$tabindex,@other) = rearrange([NAME,[VALUE,LABEL],TABINDEX],@p);

    $label=$self->_maybe_escapeHTML($label);
    $value=$self->_maybe_escapeHTML($value,1);

    my $name = $NOSTICKY ? '' : 'name=".submit" ';
    $name = qq/name="$label" / if defined($label);
    $value = defined($value) ? $value : $label;
    my $val = '';
    $val = qq/value="$value" / if defined($value);
    $tabindex = $self->element_tab($tabindex);
    my($other) = @other ? "@other " : '';
    return $XHTML ? qq(<input type="submit" $tabindex$name$val$other/>)
                  : qq(<input type="submit" $name$val$other>);
}
END_OF_FUNC


'reset' => <<'END_OF_FUNC',
sub reset {
    my($self,@p) = self_or_default(@_);
    my($label,$value,$tabindex,@other) = rearrange(['NAME',['VALUE','LABEL'],TABINDEX],@p);
    $label=$self->_maybe_escapeHTML($label);
    $value=$self->_maybe_escapeHTML($value,1);
    my ($name) = ' name=".reset"';
    $name = qq/ name="$label"/ if defined($label);
    $value = defined($value) ? $value : $label;
    my($val) = '';
    $val = qq/ value="$value"/ if defined($value);
    my($other) = @other ? " @other" : '';
    $tabindex = $self->element_tab($tabindex);
    return $XHTML ? qq(<input type="reset" $tabindex$name$val$other />)
                  : qq(<input type="reset"$name$val$other>);
}
END_OF_FUNC


'defaults' => <<'END_OF_FUNC',
sub defaults {
    my($self,@p) = self_or_default(@_);

    my($label,$tabindex,@other) = rearrange([[NAME,VALUE],TABINDEX],@p);

    $label=$self->_maybe_escapeHTML($label,1);
    $label = $label || "Defaults";
    my($value) = qq/ value="$label"/;
    my($other) = @other ? " @other" : '';
    $tabindex = $self->element_tab($tabindex);
    return $XHTML ? qq(<input type="submit" name=".defaults" $tabindex$value$other />)
                  : qq/<input type="submit" NAME=".defaults"$value$other>/;
}
END_OF_FUNC


'comment' => <<'END_OF_FUNC',
sub comment {
    my($self,@p) = self_or_CGI(@_);
    return "<!-- @p -->";
}
END_OF_FUNC

'checkbox' => <<'END_OF_FUNC',
sub checkbox {
    my($self,@p) = self_or_default(@_);

    my($name,$checked,$value,$label,$labelattributes,$override,$tabindex,@other) =
       rearrange([NAME,[CHECKED,SELECTED,ON],VALUE,LABEL,LABELATTRIBUTES,
                   [OVERRIDE,FORCE],TABINDEX],@p);

    $value = defined $value ? $value : 'on';

    if (!$override && ($self->{'.fieldnames'}->{$name} || 
		       defined $self->param($name))) {
	$checked = grep($_ eq $value,$self->param($name)) ? $self->_checked(1) : '';
    } else {
	$checked = $self->_checked($checked);
    }
    my($the_label) = defined $label ? $label : $name;
    $name = $self->_maybe_escapeHTML($name);
    $value = $self->_maybe_escapeHTML($value,1);
    $the_label = $self->_maybe_escapeHTML($the_label);
    my($other) = @other ? "@other " : '';
    $tabindex = $self->element_tab($tabindex);
    $self->register_parameter($name);
    return $XHTML ? CGI::label($labelattributes,
                    qq{<input type="checkbox" name="$name" value="$value" $tabindex$checked$other/>$the_label})
                  : qq{<input type="checkbox" name="$name" value="$value"$checked$other>$the_label};
}
END_OF_FUNC



'escapeHTML' => <<'END_OF_FUNC',
sub escapeHTML {
     # hack to work around  earlier hacks
     push @_,$_[0] if @_==1 && $_[0] eq 'CGI';
     my ($self,$toencode,$newlinestoo) = CGI::self_or_default(@_);
     return undef unless defined($toencode);
     $toencode =~ s{&}{&amp;}gso;
     $toencode =~ s{<}{&lt;}gso;
     $toencode =~ s{>}{&gt;}gso;
     if ($DTD_PUBLIC_IDENTIFIER =~ /[^X]HTML 3\.2/i) {
     # $quot; was accidentally omitted from the HTML 3.2 DTD -- see
     # <http://validator.w3.org/docs/errors.html#bad-entity> /
     # <http://lists.w3.org/Archives/Public/www-html/1997Mar/0003.html>.
        $toencode =~ s{"}{&#34;}gso;
     }
     else {
        $toencode =~ s{"}{&quot;}gso;
     }

    # Handle bug in some browsers with Latin charsets
    if ($self->{'.charset'} 
            && (uc($self->{'.charset'}) eq 'ISO-8859-1' 
            || uc($self->{'.charset'}) eq 'WINDOWS-1252')) {
                $toencode =~ s{'}{&#39;}gso;
                $toencode =~ s{\x8b}{&#8249;}gso;
                $toencode =~ s{\x9b}{&#8250;}gso;
        if (defined $newlinestoo && $newlinestoo) {
            $toencode =~ s{\012}{&#10;}gso;
            $toencode =~ s{\015}{&#13;}gso;
        }
    }
    return $toencode;
}
END_OF_FUNC

'unescapeHTML' => <<'END_OF_FUNC',
sub unescapeHTML {
    # hack to work around  earlier hacks
    push @_,$_[0] if @_==1 && $_[0] eq 'CGI';
    my ($self,$string) = CGI::self_or_default(@_);
    return undef unless defined($string);
    my $latin = defined $self->{'.charset'} ? $self->{'.charset'} =~ /^(ISO-8859-1|WINDOWS-1252)$/i
                                            : 1;
    # thanks to Randal Schwartz for the correct solution to this one
    $string=~ s[&([^\s&]*?);]{
	local $_ = $1;
	/^amp$/i	? "&" :
	/^quot$/i	? '"' :
        /^gt$/i		? ">" :
	/^lt$/i		? "<" :
	/^#(\d+)$/ && $latin	     ? chr($1) :
	/^#x([0-9a-f]+)$/i && $latin ? chr(hex($1)) :
	"&$_;"
	}gex;
    return $string;
}
END_OF_FUNC

'_tableize' => <<'END_OF_FUNC',
sub _tableize {
    my($rows,$columns,$rowheaders,$colheaders,@elements) = @_;
    my @rowheaders = $rowheaders ? @$rowheaders : ();
    my @colheaders = $colheaders ? @$colheaders : ();
    my($result);

    if (defined($columns)) {
	$rows = int(0.99 + @elements/$columns) unless defined($rows);
    }
    if (defined($rows)) {
	$columns = int(0.99 + @elements/$rows) unless defined($columns);
    }

    # rearrange into a pretty table
    $result = "<table>";
    my($row,$column);
    unshift(@colheaders,'') if @colheaders && @rowheaders;
    $result .= "<tr>" if @colheaders;
    for (@colheaders) {
	$result .= "<th>$_</th>";
    }
    for ($row=0;$row<$rows;$row++) {
	$result .= "<tr>";
	$result .= "<th>$rowheaders[$row]</th>" if @rowheaders;
	for ($column=0;$column<$columns;$column++) {
	    $result .= "<td>" . $elements[$column*$rows + $row] . "</td>"
		if defined($elements[$column*$rows + $row]);
	}
	$result .= "</tr>";
    }
    $result .= "</table>";
    return $result;
}
END_OF_FUNC


'radio_group' => <<'END_OF_FUNC',
sub radio_group {
    my($self,@p) = self_or_default(@_);
   $self->_box_group('radio',@p);
}
END_OF_FUNC


'checkbox_group' => <<'END_OF_FUNC',
sub checkbox_group {
    my($self,@p) = self_or_default(@_);
   $self->_box_group('checkbox',@p);
}
END_OF_FUNC

'_box_group' => <<'END_OF_FUNC',
sub _box_group {
    my $self     = shift;
    my $box_type = shift;

    my($name,$values,$defaults,$linebreak,$labels,$labelattributes,
       $attributes,$rows,$columns,$rowheaders,$colheaders,
       $override,$nolabels,$tabindex,$disabled,@other) =
        rearrange([NAME,[VALUES,VALUE],[DEFAULT,DEFAULTS],LINEBREAK,LABELS,LABELATTRIBUTES,
                       ATTRIBUTES,ROWS,[COLUMNS,COLS],[ROWHEADERS,ROWHEADER],[COLHEADERS,COLHEADER],
                       [OVERRIDE,FORCE],NOLABELS,TABINDEX,DISABLED
                  ],@_);


    my($result,$checked,@elements,@values);

    @values = $self->_set_values_and_labels($values,\$labels,$name);
    my %checked = $self->previous_or_default($name,$defaults,$override);

    # If no check array is specified, check the first by default
    $checked{$values[0]}++ if $box_type eq 'radio' && !%checked;

    $name=$self->_maybe_escapeHTML($name);

    my %tabs = ();
    if ($TABINDEX && $tabindex) {
      if (!ref $tabindex) {
          $self->element_tab($tabindex);
      } elsif (ref $tabindex eq 'ARRAY') {
          %tabs = map {$_=>$self->element_tab} @$tabindex;
      } elsif (ref $tabindex eq 'HASH') {
          %tabs = %$tabindex;
      }
    }
    %tabs = map {$_=>$self->element_tab} @values unless %tabs;
    my $other = @other ? "@other " : '';
    my $radio_checked;

    # for disabling groups of radio/checkbox buttons
    my %disabled;
    for (@{$disabled}) {
   	$disabled{$_}=1;
    }

    for (@values) {
    	 my $disable="";
	 if ($disabled{$_}) {
		$disable="disabled='1'";
	 }

        my $checkit = $self->_checked($box_type eq 'radio' ? ($checked{$_} && !$radio_checked++)
                                                           : $checked{$_});
	my($break);
	if ($linebreak) {
          $break = $XHTML ? "<br />" : "<br>";
	}
	else {
	  $break = '';
	}
	my($label)='';
	unless (defined($nolabels) && $nolabels) {
	    $label = $_;
	    $label = $labels->{$_} if defined($labels) && defined($labels->{$_});
	    $label = $self->_maybe_escapeHTML($label,1);
            $label = "<span style=\"color:gray\">$label</span>" if $disabled{$_};
	}
        my $attribs = $self->_set_attributes($_, $attributes);
        my $tab     = $tabs{$_};
	$_=$self->_maybe_escapeHTML($_);

        if ($XHTML) {
           push @elements,
              CGI::label($labelattributes,
                   qq(<input type="$box_type" name="$name" value="$_" $checkit$other$tab$attribs$disable/>$label)).${break};
        } else {
            push(@elements,qq/<input type="$box_type" name="$name" value="$_" $checkit$other$tab$attribs$disable>${label}${break}/);
        }
    }
    $self->register_parameter($name);
    return wantarray ? @elements : "@elements"
           unless defined($columns) || defined($rows);
    return _tableize($rows,$columns,$rowheaders,$colheaders,@elements);
}
END_OF_FUNC


'popup_menu' => <<'END_OF_FUNC',
sub popup_menu {
    my($self,@p) = self_or_default(@_);

    my($name,$values,$default,$labels,$attributes,$override,$tabindex,@other) =
       rearrange([NAME,[VALUES,VALUE],[DEFAULT,DEFAULTS],LABELS,
       ATTRIBUTES,[OVERRIDE,FORCE],TABINDEX],@p);
    my($result,%selected);

    if (!$override && defined($self->param($name))) {
	$selected{$self->param($name)}++;
    } elsif (defined $default) {
	%selected = map {$_=>1} ref($default) eq 'ARRAY' 
                                ? @$default 
                                : $default;
    }
    $name=$self->_maybe_escapeHTML($name);
    my($other) = @other ? " @other" : '';

    my(@values);
    @values = $self->_set_values_and_labels($values,\$labels,$name);
    $tabindex = $self->element_tab($tabindex);
    $name = q{} if ! defined $name;
    $result = qq/<select name="$name" $tabindex$other>\n/;
    for (@values) {
        if (/<optgroup/) {
            for my $v (split(/\n/)) {
                my $selectit = $XHTML ? 'selected="selected"' : 'selected';
		for my $selected (keys %selected) {
		    $v =~ s/(value="\Q$selected\E")/$selectit $1/;
		}
                $result .= "$v\n";
            }
        }
        else {
          my $attribs   = $self->_set_attributes($_, $attributes);
	  my($selectit) = $self->_selected($selected{$_});
	  my($label)    = $_;
	  $label        = $labels->{$_} if defined($labels) && defined($labels->{$_});
	  my($value)    = $self->_maybe_escapeHTML($_);
	  $label        = $self->_maybe_escapeHTML($label,1);
          $result      .= "<option${attribs} ${selectit}value=\"$value\">$label</option>\n";
        }
    }

    $result .= "</select>";
    return $result;
}
END_OF_FUNC


'optgroup' => <<'END_OF_FUNC',
sub optgroup {
    my($self,@p) = self_or_default(@_);
    my($name,$values,$attributes,$labeled,$noval,$labels,@other)
        = rearrange([NAME,[VALUES,VALUE],ATTRIBUTES,LABELED,NOVALS,LABELS],@p);

    my($result,@values);
    @values = $self->_set_values_and_labels($values,\$labels,$name,$labeled,$novals);
    my($other) = @other ? " @other" : '';

    $name = $self->_maybe_escapeHTML($name) || q{};
    $result = qq/<optgroup label="$name"$other>\n/;
    for (@values) {
        if (/<optgroup/) {
            for (split(/\n/)) {
                my $selectit = $XHTML ? 'selected="selected"' : 'selected';
                s/(value="$selected")/$selectit $1/ if defined $selected;
                $result .= "$_\n";
            }
        }
        else {
            my $attribs = $self->_set_attributes($_, $attributes);
            my($label) = $_;
            $label = $labels->{$_} if defined($labels) && defined($labels->{$_});
            $label=$self->_maybe_escapeHTML($label);
            my($value)=$self->_maybe_escapeHTML($_,1);
            $result .= $labeled ? $novals ? "<option$attribs label=\"$value\">$label</option>\n"
                                          : "<option$attribs label=\"$value\" value=\"$value\">$label</option>\n"
                                : $novals ? "<option$attribs>$label</option>\n"
                                          : "<option$attribs value=\"$value\">$label</option>\n";
        }
    }
    $result .= "</optgroup>";
    return $result;
}
END_OF_FUNC


'scrolling_list' => <<'END_OF_FUNC',
sub scrolling_list {
    my($self,@p) = self_or_default(@_);
    my($name,$values,$defaults,$size,$multiple,$labels,$attributes,$override,$tabindex,@other)
	= rearrange([NAME,[VALUES,VALUE],[DEFAULTS,DEFAULT],
          SIZE,MULTIPLE,LABELS,ATTRIBUTES,[OVERRIDE,FORCE],TABINDEX],@p);

    my($result,@values);
    @values = $self->_set_values_and_labels($values,\$labels,$name);

    $size = $size || scalar(@values);

    my(%selected) = $self->previous_or_default($name,$defaults,$override);

    my($is_multiple) = $multiple ? qq/ multiple="multiple"/ : '';
    my($has_size) = $size ? qq/ size="$size"/: '';
    my($other) = @other ? " @other" : '';

    $name=$self->_maybe_escapeHTML($name);
    $tabindex = $self->element_tab($tabindex);
    $result = qq/<select name="$name" $tabindex$has_size$is_multiple$other>\n/;
    for (@values) {
        if (/<optgroup/) {
            for my $v (split(/\n/)) {
                my $selectit = $XHTML ? 'selected="selected"' : 'selected';
		for my $selected (keys %selected) {
		    $v =~ s/(value="$selected")/$selectit $1/;
		}
                $result .= "$v\n";
            }
        }
        else {
          my $attribs   = $self->_set_attributes($_, $attributes);
	  my($selectit) = $self->_selected($selected{$_});
	  my($label)    = $_;
	  $label        = $labels->{$_} if defined($labels) && defined($labels->{$_});
	  my($value)    = $self->_maybe_escapeHTML($_);
	  $label        = $self->_maybe_escapeHTML($label,1);
          $result      .= "<option${attribs} ${selectit}value=\"$value\">$label</option>\n";
        }
    }

    $result .= "</select>";
    $self->register_parameter($name);
    return $result;
}
END_OF_FUNC


'hidden' => <<'END_OF_FUNC',
sub hidden {
    my($self,@p) = self_or_default(@_);

    # this is the one place where we departed from our standard
    # calling scheme, so we have to special-case (darn)
    my(@result,@value);
    my($name,$default,$override,@other) = 
	rearrange([NAME,[DEFAULT,VALUE,VALUES],[OVERRIDE,FORCE]],@p);

    my $do_override = 0;
    if ( ref($p[0]) || substr($p[0],0,1) eq '-') {
	@value = ref($default) ? @{$default} : $default;
	$do_override = $override;
    } else {
	for ($default,$override,@other) {
	    push(@value,$_) if defined($_);
	}
        undef @other;
    }

    # use previous values if override is not set
    my @prev = $self->param($name);
    @value = @prev if !$do_override && @prev;

    $name=$self->_maybe_escapeHTML($name);
    for (@value) {
	$_ = defined($_) ? $self->_maybe_escapeHTML($_,1) : '';
	push @result,$XHTML ? qq(<input type="hidden" name="$name" value="$_" @other />)
                            : qq(<input type="hidden" name="$name" value="$_" @other>);
    }
    return wantarray ? @result : join('',@result);
}
END_OF_FUNC


'image_button' => <<'END_OF_FUNC',
sub image_button {
    my($self,@p) = self_or_default(@_);

    my($name,$src,$alignment,@other) =
	rearrange([NAME,SRC,ALIGN],@p);

    my($align) = $alignment ? " align=\L\"$alignment\"" : '';
    my($other) = @other ? " @other" : '';
    $name=$self->_maybe_escapeHTML($name);
    return $XHTML ? qq(<input type="image" name="$name" src="$src"$align$other />)
                  : qq/<input type="image" name="$name" src="$src"$align$other>/;
}
END_OF_FUNC


'self_url' => <<'END_OF_FUNC',
sub self_url {
    my($self,@p) = self_or_default(@_);
    return $self->url('-path_info'=>1,'-query'=>1,'-full'=>1,@p);
}
END_OF_FUNC


'state' => <<'END_OF_FUNC',
sub state {
    &self_url;
}
END_OF_FUNC


'url' => <<'END_OF_FUNC',
sub url {
    my($self,@p) = self_or_default(@_);
    my ($relative,$absolute,$full,$path_info,$query,$base,$rewrite) = 
	rearrange(['RELATIVE','ABSOLUTE','FULL',['PATH','PATH_INFO'],['QUERY','QUERY_STRING'],'BASE','REWRITE'],@p);
    my $url  = '';
    $full++      if $base || !($relative || $absolute);
    $rewrite++   unless defined $rewrite;

    my $path        =  $self->path_info;
    my $script_name =  $self->script_name;
    my $request_uri =  unescape($self->request_uri) || '';
    my $query_str   =  $self->query_string;

    my $rewrite_in_use = $request_uri && $request_uri !~ /^\Q$script_name/;

    my $uri         =  $rewrite && $request_uri ? $request_uri : $script_name;
    $uri            =~ s/\?.*$//s;                                # remove query string
    $uri            =~ s/\Q$ENV{PATH_INFO}\E$// if defined $ENV{PATH_INFO};

    if ($full) {
        my $protocol = $self->protocol();
        $url = "$protocol://";
        my $vh = http('x_forwarded_host') || http('host') || '';
            $vh =~ s/\:\d+$//;  # some clients add the port number (incorrectly). Get rid of it.

        $url .= $vh || server_name();

        my $port = $self->virtual_port;

        # add the port to the url unless it's the protocol's default port
        $url .= ':' . $port unless (lc($protocol) eq 'http'  && $port == 80)
                                or (lc($protocol) eq 'https' && $port == 443);

        return $url if $base;

        $url .= $uri;
    } elsif ($relative) {
	($url) = $uri =~ m!([^/]+)$!;
    } elsif ($absolute) {
	$url = $uri;
    }

    $url .= $path         if $path_info and defined $path;
    $url .= "?$query_str" if $query     and $query_str ne '';
    $url ||= '';
    $url =~ s/([^a-zA-Z0-9_.%;&?\/\\:+=~-])/sprintf("%%%02X",ord($1))/eg;
    return $url;
}

END_OF_FUNC

'cookie' => <<'END_OF_FUNC',
sub cookie {
    my($self,@p) = self_or_default(@_);
    my($name,$value,$path,$domain,$secure,$expires,$httponly) =
	rearrange([NAME,[VALUE,VALUES],PATH,DOMAIN,SECURE,EXPIRES,HTTPONLY],@p);

    require CGI::Cookie;

    # if no value is supplied, then we retrieve the
    # value of the cookie, if any.  For efficiency, we cache the parsed
    # cookies in our state variables.
    unless ( defined($value) ) {
	$self->{'.cookies'} = CGI::Cookie->fetch;
	
	# If no name is supplied, then retrieve the names of all our cookies.
	return () unless $self->{'.cookies'};
	return keys %{$self->{'.cookies'}} unless $name;
	return () unless $self->{'.cookies'}->{$name};
	return $self->{'.cookies'}->{$name}->value if defined($name) && $name ne '';
    }

    # If we get here, we're creating a new cookie
    return undef unless defined($name) && $name ne '';	# this is an error

    my @param;
    push(@param,'-name'=>$name);
    push(@param,'-value'=>$value);
    push(@param,'-domain'=>$domain) if $domain;
    push(@param,'-path'=>$path) if $path;
    push(@param,'-expires'=>$expires) if $expires;
    push(@param,'-secure'=>$secure) if $secure;
    push(@param,'-httponly'=>$httponly) if $httponly;

    return CGI::Cookie->new(@param);
}
END_OF_FUNC

'parse_keywordlist' => <<'END_OF_FUNC',
sub parse_keywordlist {
    my($self,$tosplit) = @_;
    $tosplit = unescape($tosplit); # unescape the keywords
    $tosplit=~tr/+/ /;          # pluses to spaces
    my(@keywords) = split(/\s+/,$tosplit);
    return @keywords;
}
END_OF_FUNC

'param_fetch' => <<'END_OF_FUNC',
sub param_fetch {
    my($self,@p) = self_or_default(@_);
    my($name) = rearrange([NAME],@p);
    return [] unless defined $name;

    unless (exists($self->{param}{$name})) {
	$self->add_parameter($name);
	$self->{param}{$name} = [];
    }
    
    return $self->{param}{$name};
}
END_OF_FUNC


'path_info' => <<'END_OF_FUNC',
sub path_info {
    my ($self,$info) = self_or_default(@_);
    if (defined($info)) {
	$info = "/$info" if $info ne '' &&  substr($info,0,1) ne '/';
	$self->{'.path_info'} = $info;
    } elsif (! defined($self->{'.path_info'}) ) {
        my (undef,$path_info) = $self->_name_and_path_from_env;
	$self->{'.path_info'} = $path_info || '';
    }
    return $self->{'.path_info'};
}
END_OF_FUNC

'_name_and_path_from_env' => <<'END_OF_FUNC',
sub _name_and_path_from_env {
    my $self = shift;
    my $script_name = $ENV{SCRIPT_NAME}  || '';
    my $path_info   = $ENV{PATH_INFO}    || '';
    my $uri         = $self->request_uri || '';

    $uri =~ s/\?.*//s;
    $uri = unescape($uri);

    if ($uri ne "$script_name$path_info") {
        my $script_name_pattern = quotemeta($script_name);
        my $path_info_pattern = quotemeta($path_info);
        $script_name_pattern =~ s{(?:\\/)+}{/+}g;
        $path_info_pattern =~ s{(?:\\/)+}{/+}g;

        if ($uri =~ /^($script_name_pattern)($path_info_pattern)$/s) {
            # REQUEST_URI and SCRIPT_NAME . PATH_INFO only differ by the
            # numer of consecutive slashes, so we can extract the info from
            # REQUEST_URI:
            ($script_name, $path_info) = ($1, $2);
        }
    }
    return ($script_name,$path_info);
}
END_OF_FUNC


'request_method' => <<'END_OF_FUNC',
sub request_method {
    return (defined $ENV{'REQUEST_METHOD'}) ? $ENV{'REQUEST_METHOD'} : undef;
}
END_OF_FUNC

'content_type' => <<'END_OF_FUNC',
sub content_type {
    return (defined $ENV{'CONTENT_TYPE'}) ? $ENV{'CONTENT_TYPE'} : undef;
}
END_OF_FUNC

'path_translated' => <<'END_OF_FUNC',
sub path_translated {
    return (defined $ENV{'PATH_TRANSLATED'}) ? $ENV{'PATH_TRANSLATED'} : undef;
}
END_OF_FUNC


'request_uri' => <<'END_OF_FUNC',
sub request_uri {
    return (defined $ENV{'REQUEST_URI'}) ? $ENV{'REQUEST_URI'} : undef;
}
END_OF_FUNC


'query_string' => <<'END_OF_FUNC',
sub query_string {
    my($self) = self_or_default(@_);
    my($param,$value,@pairs);
    for $param ($self->param) {
       my($eparam) = escape($param);
       for $value ($self->param($param)) {
           $value = escape($value);
            next unless defined $value;
           push(@pairs,"$eparam=$value");
       }
    }
    for (keys %{$self->{'.fieldnames'}}) {
      push(@pairs,".cgifields=".escape("$_"));
    }
    return join($USE_PARAM_SEMICOLONS ? ';' : '&',@pairs);
}
END_OF_FUNC


'Accept' => <<'END_OF_FUNC',
sub Accept {
    my($self,$search) = self_or_CGI(@_);
    my(%prefs,$type,$pref,$pat);
    
    my(@accept) = defined $self->http('accept') 
                ? split(',',$self->http('accept'))
                : ();

    for (@accept) {
	($pref) = /q=(\d\.\d+|\d+)/;
	($type) = m#(\S+/[^;]+)#;
	next unless $type;
	$prefs{$type}=$pref || 1;
    }

    return keys %prefs unless $search;
    
    # if a search type is provided, we may need to
    # perform a pattern matching operation.
    # The MIME types use a glob mechanism, which
    # is easily translated into a perl pattern match

    # First return the preference for directly supported
    # types:
    return $prefs{$search} if $prefs{$search};

    # Didn't get it, so try pattern matching.
    for (keys %prefs) {
	next unless /\*/;       # not a pattern match
	($pat = $_) =~ s/([^\w*])/\\$1/g; # escape meta characters
	$pat =~ s/\*/.*/g; # turn it into a pattern
	return $prefs{$_} if $search=~/$pat/;
    }
}
END_OF_FUNC


'user_agent' => <<'END_OF_FUNC',
sub user_agent {
    my($self,$match)=self_or_CGI(@_);
    my $user_agent = $self->http('user_agent');
    return $user_agent unless defined $match && $match && $user_agent;
    return $user_agent =~ /$match/i;
}
END_OF_FUNC


'raw_cookie' => <<'END_OF_FUNC',
sub raw_cookie {
    my($self,$key) = self_or_CGI(@_);

    require CGI::Cookie;

    if (defined($key)) {
	$self->{'.raw_cookies'} = CGI::Cookie->raw_fetch
	    unless $self->{'.raw_cookies'};

	return () unless $self->{'.raw_cookies'};
	return () unless $self->{'.raw_cookies'}->{$key};
	return $self->{'.raw_cookies'}->{$key};
    }
    return $self->http('cookie') || $ENV{'COOKIE'} || '';
}
END_OF_FUNC

'virtual_host' => <<'END_OF_FUNC',
sub virtual_host {
    my $vh = http('x_forwarded_host') || http('host') || server_name();
    $vh =~ s/:\d+$//;		# get rid of port number
    return $vh;
}
END_OF_FUNC

'remote_host' => <<'END_OF_FUNC',
sub remote_host {
    return $ENV{'REMOTE_HOST'} || $ENV{'REMOTE_ADDR'} 
    || 'localhost';
}
END_OF_FUNC


'remote_addr' => <<'END_OF_FUNC',
sub remote_addr {
    return $ENV{'REMOTE_ADDR'} || '127.0.0.1';
}
END_OF_FUNC


'script_name' => <<'END_OF_FUNC',
sub script_name {
    my ($self,@p) = self_or_default(@_);
    if (@p) {
        $self->{'.script_name'} = shift @p;
    } elsif (!exists $self->{'.script_name'}) {
        my ($script_name,$path_info) = $self->_name_and_path_from_env();
        $self->{'.script_name'} = $script_name;
    }
    return $self->{'.script_name'};
}
END_OF_FUNC


'referer' => <<'END_OF_FUNC',
sub referer {
    my($self) = self_or_CGI(@_);
    return $self->http('referer');
}
END_OF_FUNC


'server_name' => <<'END_OF_FUNC',
sub server_name {
    return $ENV{'SERVER_NAME'} || 'localhost';
}
END_OF_FUNC

'server_software' => <<'END_OF_FUNC',
sub server_software {
    return $ENV{'SERVER_SOFTWARE'} || 'cmdline';
}
END_OF_FUNC

'virtual_port' => <<'END_OF_FUNC',
sub virtual_port {
    my($self) = self_or_default(@_);
    my $vh = $self->http('x_forwarded_host') || $self->http('host');
    my $protocol = $self->protocol;
    if ($vh) {
        return ($vh =~ /:(\d+)$/)[0] || ($protocol eq 'https' ? 443 : 80);
    } else {
        return $self->server_port();
    }
}
END_OF_FUNC

'server_port' => <<'END_OF_FUNC',
sub server_port {
    return $ENV{'SERVER_PORT'} || 80; # for debugging
}
END_OF_FUNC

'server_protocol' => <<'END_OF_FUNC',
sub server_protocol {
    return $ENV{'SERVER_PROTOCOL'} || 'HTTP/1.0'; # for debugging
}
END_OF_FUNC

'http' => <<'END_OF_FUNC',
sub http {
    my ($self,$parameter) = self_or_CGI(@_);
    if ( defined($parameter) ) {
        $parameter =~ tr/-a-z/_A-Z/;
        if ( $parameter =~ /^HTTP(?:_|$)/ ) {
            return $ENV{$parameter};
        }
        return $ENV{"HTTP_$parameter"};
    }
    return grep { /^HTTP(?:_|$)/ } keys %ENV;
}
END_OF_FUNC

'https' => <<'END_OF_FUNC',
sub https {
    my ($self,$parameter) = self_or_CGI(@_);
    if ( defined($parameter) ) {
        $parameter =~ tr/-a-z/_A-Z/;
        if ( $parameter =~ /^HTTPS(?:_|$)/ ) {
            return $ENV{$parameter};
        }
        return $ENV{"HTTPS_$parameter"};
    }
    return wantarray
        ? grep { /^HTTPS(?:_|$)/ } keys %ENV
        : $ENV{'HTTPS'};
}
END_OF_FUNC

'protocol' => <<'END_OF_FUNC',
sub protocol {
    local($^W)=0;
    my $self = shift;
    return 'https' if uc($self->https()) eq 'ON'; 
    return 'https' if $self->server_port == 443;
    my $prot = $self->server_protocol;
    my($protocol,$version) = split('/',$prot);
    return "\L$protocol\E";
}
END_OF_FUNC

'remote_ident' => <<'END_OF_FUNC',
sub remote_ident {
    return (defined $ENV{'REMOTE_IDENT'}) ? $ENV{'REMOTE_IDENT'} : undef;
}
END_OF_FUNC


'auth_type' => <<'END_OF_FUNC',
sub auth_type {
    return (defined $ENV{'AUTH_TYPE'}) ? $ENV{'AUTH_TYPE'} : undef;
}
END_OF_FUNC


'remote_user' => <<'END_OF_FUNC',
sub remote_user {
    return (defined $ENV{'REMOTE_USER'}) ? $ENV{'REMOTE_USER'} : undef;
}
END_OF_FUNC


'user_name' => <<'END_OF_FUNC',
sub user_name {
    my ($self) = self_or_CGI(@_);
    return $self->http('from') || $ENV{'REMOTE_IDENT'} || $ENV{'REMOTE_USER'};
}
END_OF_FUNC

'nosticky' => <<'END_OF_FUNC',
sub nosticky {
    my ($self,$param) = self_or_CGI(@_);
    $CGI::NOSTICKY = $param if defined($param);
    return $CGI::NOSTICKY;
}
END_OF_FUNC

'nph' => <<'END_OF_FUNC',
sub nph {
    my ($self,$param) = self_or_CGI(@_);
    $CGI::NPH = $param if defined($param);
    return $CGI::NPH;
}
END_OF_FUNC

'private_tempfiles' => <<'END_OF_FUNC',
sub private_tempfiles {
    my ($self,$param) = self_or_CGI(@_);
    $CGI::PRIVATE_TEMPFILES = $param if defined($param);
    return $CGI::PRIVATE_TEMPFILES;
}
END_OF_FUNC
'close_upload_files' => <<'END_OF_FUNC',
sub close_upload_files {
    my ($self,$param) = self_or_CGI(@_);
    $CGI::CLOSE_UPLOAD_FILES = $param if defined($param);
    return $CGI::CLOSE_UPLOAD_FILES;
}
END_OF_FUNC


'default_dtd' => <<'END_OF_FUNC',
sub default_dtd {
    my ($self,$param,$param2) = self_or_CGI(@_);
    if (defined $param2 && defined $param) {
        $CGI::DEFAULT_DTD = [ $param, $param2 ];
    } elsif (defined $param) {
        $CGI::DEFAULT_DTD = $param;
    }
    return $CGI::DEFAULT_DTD;
}
END_OF_FUNC

'_maybe_escapeHTML' => <<'END_OF_FUNC',
sub _maybe_escapeHTML {
    # hack to work around  earlier hacks
    push @_,$_[0] if @_==1 && $_[0] eq 'CGI';
    my ($self,$toencode,$newlinestoo) = CGI::self_or_default(@_);
    return undef unless defined($toencode);
    return $toencode if ref($self) && !$self->{'escape'};
    return $self->escapeHTML($toencode, $newlinestoo);
}
END_OF_FUNC

'previous_or_default' => <<'END_OF_FUNC',
sub previous_or_default {
    my($self,$name,$defaults,$override) = @_;
    my(%selected);

    if (!$override && ($self->{'.fieldnames'}->{$name} || 
		       defined($self->param($name)) ) ) {
	$selected{$_}++ for $self->param($name);
    } elsif (defined($defaults) && ref($defaults) && 
	     (ref($defaults) eq 'ARRAY')) {
	$selected{$_}++ for @{$defaults};
    } else {
	$selected{$defaults}++ if defined($defaults);
    }

    return %selected;
}
END_OF_FUNC

'register_parameter' => <<'END_OF_FUNC',
sub register_parameter {
    my($self,$param) = @_;
    $self->{'.parametersToAdd'}->{$param}++;
}
END_OF_FUNC

'get_fields' => <<'END_OF_FUNC',
sub get_fields {
    my($self) = @_;
    return $self->CGI::hidden('-name'=>'.cgifields',
			      '-values'=>[keys %{$self->{'.parametersToAdd'}}],
			      '-override'=>1);
}
END_OF_FUNC

'read_from_cmdline' => <<'END_OF_FUNC',
sub read_from_cmdline {
    my($input,@words);
    my($query_string);
    my($subpath);
    if ($DEBUG && @ARGV) {
	@words = @ARGV;
    } elsif ($DEBUG > 1) {
	require Text::ParseWords;
	print STDERR "(offline mode: enter name=value pairs on standard input; press ^D or ^Z when done)\n";
	chomp(@lines = <STDIN>); # remove newlines
	$input = join(" ",@lines);
	@words = &Text::ParseWords::old_shellwords($input);    
    }
    for (@words) {
	s/\\=/%3D/g;
	s/\\&/%26/g;	    
    }

    if ("@words"=~/=/) {
	$query_string = join('&',@words);
    } else {
	$query_string = join('+',@words);
    }
    if ($query_string =~ /^(.*?)\?(.*)$/)
    {
        $query_string = $2;
        $subpath = $1;
    }
    return { 'query_string' => $query_string, 'subpath' => $subpath };
}
END_OF_FUNC

'read_multipart' => <<'END_OF_FUNC',
sub read_multipart {
    my($self,$boundary,$length) = @_;
    my($buffer) = $self->new_MultipartBuffer($boundary,$length);
    return unless $buffer;
    my(%header,$body);
    my $filenumber = 0;
    while (!$buffer->eof) {
	%header = $buffer->readHeader;

	unless (%header) {
	    $self->cgi_error("400 Bad request (malformed multipart POST)");
	    return;
	}

	$header{'Content-Disposition'} ||= ''; # quench uninit variable warning

	my($param)= $header{'Content-Disposition'}=~/[\s;]name="([^"]*)"/;
        $param .= $TAINTED;

        # See RFC 1867, 2183, 2045
        # NB: File content will be loaded into memory should
        # content-disposition parsing fail.
        my ($filename) = $header{'Content-Disposition'}
	               =~/ filename=(("[^"]*")|([a-z\d!\#'\*\+,\.^_\`\{\}\|\~]*))/i;

	$filename ||= ''; # quench uninit variable warning

        $filename =~ s/^"([^"]*)"$/$1/;
	# Test for Opera's multiple upload feature
	my($multipart) = ( defined( $header{'Content-Type'} ) &&
		$header{'Content-Type'} =~ /multipart\/mixed/ ) ?
		1 : 0;

	# add this parameter to our list
	$self->add_parameter($param);

	# If no filename specified, then just read the data and assign it
	# to our parameter list.
	if ( ( !defined($filename) || $filename eq '' ) && !$multipart ) {
	    my($value) = $buffer->readBody;
            $value .= $TAINTED;
	    push(@{$self->{param}{$param}},$value);
	    next;
	}

	my ($tmpfile,$tmp,$filehandle);
      UPLOADS: {
	  # If we get here, then we are dealing with a potentially large
	  # uploaded form.  Save the data to a temporary file, then open
	  # the file for reading.

	  # skip the file if uploads disabled
	  if ($DISABLE_UPLOADS) {
	      while (defined($data = $buffer->read)) { }
	      last UPLOADS;
	  }

	  # set the filename to some recognizable value
          if ( ( !defined($filename) || $filename eq '' ) && $multipart ) {
              $filename = "multipart/mixed";
          }

	  # choose a relatively unpredictable tmpfile sequence number
          my $seqno = unpack("%16C*",join('',localtime,grep {defined $_} values %ENV));
          for (my $cnt=10;$cnt>0;$cnt--) {
	    next unless $tmpfile = CGITempFile->new($seqno);
	    $tmp = $tmpfile->as_string;
	    last if defined($filehandle = Fh->new($filename,$tmp,$PRIVATE_TEMPFILES));
            $seqno += int rand(100);
          }
          die "CGI.pm open of tmpfile $tmp/$filename failed: $!\n" unless defined $filehandle;
	  $CGI::DefaultClass->binmode($filehandle) if $CGI::needs_binmode 
                     && defined fileno($filehandle);

	  # if this is an multipart/mixed attachment, save the header
	  # together with the body for later parsing with an external
	  # MIME parser module
	  if ( $multipart ) {
	      for ( keys %header ) {
		  print $filehandle "$_: $header{$_}${CRLF}";
	      }
	      print $filehandle "${CRLF}";
	  }

	  my ($data);
	  local($\) = '';
          my $totalbytes = 0;
          while (defined($data = $buffer->read)) {
              if (defined $self->{'.upload_hook'})
               {
                  $totalbytes += length($data);
                   &{$self->{'.upload_hook'}}($filename ,$data, $totalbytes, $self->{'.upload_data'});
              }
              print $filehandle $data if ($self->{'use_tempfile'});
          }

	  # back up to beginning of file
	  seek($filehandle,0,0);

      ## Close the filehandle if requested this allows a multipart MIME
      ## upload to contain many files, and we won't die due to too many
      ## open file handles. The user can access the files using the hash
      ## below.
      close $filehandle if $CLOSE_UPLOAD_FILES;
	  $CGI::DefaultClass->binmode($filehandle) if $CGI::needs_binmode;

	  # Save some information about the uploaded file where we can get
	  # at it later.
	  # Use the typeglob as the key, as this is guaranteed to be
	  # unique for each filehandle.  Don't use the file descriptor as
	  # this will be re-used for each filehandle if the
	  # close_upload_files feature is used.
	  $self->{'.tmpfiles'}->{$$filehandle}= {
              hndl => $filehandle,
	      name => $tmpfile,
	      info => {%header},
	  };
	  push(@{$self->{param}{$param}},$filehandle);
      }
    }
}
END_OF_FUNC

'read_multipart_related' => <<'END_OF_FUNC',
sub read_multipart_related {
    my($self,$start,$boundary,$length) = @_;
    my($buffer) = $self->new_MultipartBuffer($boundary,$length);
    return unless $buffer;
    my(%header,$body);
    my $filenumber = 0;
    my $returnvalue;
    while (!$buffer->eof) {
	%header = $buffer->readHeader;

	unless (%header) {
	    $self->cgi_error("400 Bad request (malformed multipart POST)");
	    return;
	}

	my($param) = $header{'Content-ID'}=~/\<([^\>]*)\>/;
        $param .= $TAINTED;

	# If this is the start part, then just read the data and assign it
	# to our return variable.
	if ( $param eq $start ) {
	    $returnvalue = $buffer->readBody;
            $returnvalue .= $TAINTED;
	    next;
	}

	# add this parameter to our list
	$self->add_parameter($param);

	my ($tmpfile,$tmp,$filehandle);
      UPLOADS: {
	  # If we get here, then we are dealing with a potentially large
	  # uploaded form.  Save the data to a temporary file, then open
	  # the file for reading.

	  # skip the file if uploads disabled
	  if ($DISABLE_UPLOADS) {
	      while (defined($data = $buffer->read)) { }
	      last UPLOADS;
	  }

	  # choose a relatively unpredictable tmpfile sequence number
          my $seqno = unpack("%16C*",join('',localtime,grep {defined $_} values %ENV));
          for (my $cnt=10;$cnt>0;$cnt--) {
	    next unless $tmpfile = CGITempFile->new($seqno);
	    $tmp = $tmpfile->as_string;
	    last if defined($filehandle = Fh->new($param,$tmp,$PRIVATE_TEMPFILES));
            $seqno += int rand(100);
          }
          die "CGI open of tmpfile: $!\n" unless defined $filehandle;
	  $CGI::DefaultClass->binmode($filehandle) if $CGI::needs_binmode 
                     && defined fileno($filehandle);

	  my ($data);
	  local($\) = '';
          my $totalbytes;
          while (defined($data = $buffer->read)) {
              if (defined $self->{'.upload_hook'})
               {
                  $totalbytes += length($data);
                   &{$self->{'.upload_hook'}}($param ,$data, $totalbytes, $self->{'.upload_data'});
              }
              print $filehandle $data if ($self->{'use_tempfile'});
          }

	  # back up to beginning of file
	  seek($filehandle,0,0);

      ## Close the filehandle if requested this allows a multipart MIME
      ## upload to contain many files, and we won't die due to too many
      ## open file handles. The user can access the files using the hash
      ## below.
      close $filehandle if $CLOSE_UPLOAD_FILES;
	  $CGI::DefaultClass->binmode($filehandle) if $CGI::needs_binmode;

	  # Save some information about the uploaded file where we can get
	  # at it later.
	  # Use the typeglob as the key, as this is guaranteed to be
	  # unique for each filehandle.  Don't use the file descriptor as
	  # this will be re-used for each filehandle if the
	  # close_upload_files feature is used.
	  $self->{'.tmpfiles'}->{$$filehandle}= {
              hndl => $filehandle,
	      name => $tmpfile,
	      info => {%header},
	  };
	  push(@{$self->{param}{$param}},$filehandle);
      }
    }
    return $returnvalue;
}
END_OF_FUNC


'upload' =><<'END_OF_FUNC',
sub upload {
    my($self,$param_name) = self_or_default(@_);
    my @param = grep {ref($_) && defined(fileno($_))} $self->param($param_name);
    return unless @param;
    return wantarray ? @param : $param[0];
}
END_OF_FUNC

'tmpFileName' => <<'END_OF_FUNC',
sub tmpFileName {
    my($self,$filename) = self_or_default(@_);
    return $self->{'.tmpfiles'}->{$$filename}->{name} ?
	$self->{'.tmpfiles'}->{$$filename}->{name}->as_string
	    : '';
}
END_OF_FUNC

'uploadInfo' => <<'END_OF_FUNC',
sub uploadInfo {
    my($self,$filename) = self_or_default(@_);
    return $self->{'.tmpfiles'}->{$$filename}->{info};
}
END_OF_FUNC

'_set_values_and_labels' => <<'END_OF_FUNC',
sub _set_values_and_labels {
    my $self = shift;
    my ($v,$l,$n) = @_;
    $$l = $v if ref($v) eq 'HASH' && !ref($$l);
    return $self->param($n) if !defined($v);
    return $v if !ref($v);
    return ref($v) eq 'HASH' ? keys %$v : @$v;
}
END_OF_FUNC

'_set_attributes' => <<'END_OF_FUNC',
sub _set_attributes {
    my $self = shift;
    my($element, $attributes) = @_;
    return '' unless defined($attributes->{$element});
    $attribs = ' ';
    for my $attrib (keys %{$attributes->{$element}}) {
        (my $clean_attrib = $attrib) =~ s/^-//;
        $attribs .= "@{[lc($clean_attrib)]}=\"$attributes->{$element}{$attrib}\" ";
    }
    $attribs =~ s/ $//;
    return $attribs;
}
END_OF_FUNC

'_compile_all' => <<'END_OF_FUNC',
sub _compile_all {
    for (@_) {
	next if defined(&$_);
	$AUTOLOAD = "CGI::$_";
	_compile();
    }
}
END_OF_FUNC

);
END_OF_AUTOLOAD
;


package Fh;

use overload 
    '""'  => \&asString,
    'cmp' => \&compare,
    'fallback'=>1;

$FH='fh00000';

*Fh::AUTOLOAD = \&CGI::AUTOLOAD;

sub DESTROY {
    my $self = shift;
    close $self;
}

$AUTOLOADED_ROUTINES = '';      # prevent -w error
$AUTOLOADED_ROUTINES=<<'END_OF_AUTOLOAD';
%SUBS =  (
'asString' => <<'END_OF_FUNC',
sub asString {
    my $self = shift;
    # get rid of package name
    (my $i = $$self) =~ s/^\*(\w+::fh\d{5})+//; 
    $i =~ s/%(..)/ chr(hex($1)) /eg;
    return $i.$CGI::TAINTED;
}
END_OF_FUNC

'compare' => <<'END_OF_FUNC',
sub compare {
    my $self = shift;
    my $value = shift;
    return "$self" cmp $value;
}
END_OF_FUNC

'new'  => <<'END_OF_FUNC',
sub new {
    my($pack,$name,$file,$delete) = @_;
    _setup_symbols(@SAVED_SYMBOLS) if @SAVED_SYMBOLS;
    require Fcntl unless defined &Fcntl::O_RDWR;
    (my $safename = $name) =~ s/([':%])/ sprintf '%%%02X', ord $1 /eg;
    my $fv = ++$FH . $safename;
    my $ref = \*{"Fh::$fv"};

    # Note this same regex is also used elsewhere in the same file for CGITempFile::new
    $file =~ m!^([a-zA-Z0-9_ \'\":/.\$\\\+-]+)$! || return;
    my $safe = $1;
    sysopen($ref,$safe,Fcntl::O_RDWR()|Fcntl::O_CREAT()|Fcntl::O_EXCL(),0600) || return;
    unlink($safe) if $delete;
    CORE::delete $Fh::{$fv};
    return bless $ref,$pack;
}
END_OF_FUNC

'handle' => <<'END_OF_FUNC',
sub handle {
  my $self = shift;
  eval "require IO::Handle" unless IO::Handle->can('new_from_fd');
  return IO::Handle->new_from_fd(fileno $self,"<");
}
END_OF_FUNC

);
END_OF_AUTOLOAD

package MultipartBuffer;

use constant DEBUG => 0;

$INITIAL_FILLUNIT = 1024 * 4;
$TIMEOUT = 240*60;       # 4 hour timeout for big files
$SPIN_LOOP_MAX = 2000;  # bug fix for some Netscape servers
$CRLF=$CGI::CRLF;

*MultipartBuffer::AUTOLOAD = \&CGI::AUTOLOAD;

sub DESTROY {}

$AUTOLOADED_ROUTINES = '';      # prevent -w error
$AUTOLOADED_ROUTINES=<<'END_OF_AUTOLOAD';
%SUBS =  (

'new' => <<'END_OF_FUNC',
sub new {
    my($package,$interface,$boundary,$length) = @_;
    $FILLUNIT = $INITIAL_FILLUNIT;
    $CGI::DefaultClass->binmode($IN); # if $CGI::needs_binmode;  # just do it always

    # If the user types garbage into the file upload field,
    # then Netscape passes NOTHING to the server (not good).
    # We may hang on this read in that case. So we implement
    # a read timeout.  If nothing is ready to read
    # by then, we return.

    # Netscape seems to be a little bit unreliable
    # about providing boundary strings.
    my $boundary_read = 0;
    if ($boundary) {

	# Under the MIME spec, the boundary consists of the 
	# characters "--" PLUS the Boundary string

	# BUG: IE 3.01 on the Macintosh uses just the boundary -- not
	# the two extra hyphens.  We do a special case here on the user-agent!!!!
	$boundary = "--$boundary" unless CGI::user_agent('MSIE\s+3\.0[12];\s*Mac|DreamPassport');

    } else { # otherwise we find it ourselves
	my($old);
	($old,$/) = ($/,$CRLF); # read a CRLF-delimited line
	$boundary = <STDIN>;      # BUG: This won't work correctly under mod_perl
	$length -= length($boundary);
	chomp($boundary);               # remove the CRLF
	$/ = $old;                      # restore old line separator
        $boundary_read++;
    }

    my $self = {LENGTH=>$length,
		CHUNKED=>!$length,
		BOUNDARY=>$boundary,
		INTERFACE=>$interface,
		BUFFER=>'',
	    };

    $FILLUNIT = length($boundary)
	if length($boundary) > $FILLUNIT;

    my $retval = bless $self,ref $package || $package;

    # Read the preamble and the topmost (boundary) line plus the CRLF.
    unless ($boundary_read) {
      while ($self->read(0)) { }
    }
    die "Malformed multipart POST: data truncated\n" if $self->eof;

    return $retval;
}
END_OF_FUNC

'readHeader' => <<'END_OF_FUNC',
sub readHeader {
    my($self) = @_;
    my($end);
    my($ok) = 0;
    my($bad) = 0;

    local($CRLF) = "\015\012" if $CGI::OS eq 'VMS' || $CGI::EBCDIC;

    do {
	$self->fillBuffer($FILLUNIT);
	$ok++ if ($end = index($self->{BUFFER},"${CRLF}${CRLF}")) >= 0;
	$ok++ if $self->{BUFFER} eq '';
	$bad++ if !$ok && $self->{LENGTH} <= 0;
	# this was a bad idea
	# $FILLUNIT *= 2 if length($self->{BUFFER}) >= $FILLUNIT; 
    } until $ok || $bad;
    return () if $bad;

    #EBCDIC NOTE: translate header into EBCDIC, but watch out for continuation lines!

    my($header) = substr($self->{BUFFER},0,$end+2);
    substr($self->{BUFFER},0,$end+4) = '';
    my %return;

    if ($CGI::EBCDIC) {
      warn "untranslated header=$header\n" if DEBUG;
      $header = CGI::Util::ascii2ebcdic($header);
      warn "translated header=$header\n" if DEBUG;
    }

    # See RFC 2045 Appendix A and RFC 822 sections 3.4.8
    #   (Folding Long Header Fields), 3.4.3 (Comments)
    #   and 3.4.5 (Quoted-Strings).

    my $token = '[-\w!\#$%&\'*+.^_\`|{}~]';
    $header=~s/$CRLF\s+/ /og;		# merge continuation lines

    while ($header=~/($token+):\s+([^$CRLF]*)/mgox) {
        my ($field_name,$field_value) = ($1,$2);
	$field_name =~ s/\b(\w)/uc($1)/eg; #canonicalize
	$return{$field_name}=$field_value;
    }
    return %return;
}
END_OF_FUNC

'readBody' => <<'END_OF_FUNC',
sub readBody {
    my($self) = @_;
    my($data);
    my($returnval)='';

    #EBCDIC NOTE: want to translate returnval into EBCDIC HERE

    while (defined($data = $self->read)) {
	$returnval .= $data;
    }

    if ($CGI::EBCDIC) {
      warn "untranslated body=$returnval\n" if DEBUG;
      $returnval = CGI::Util::ascii2ebcdic($returnval);
      warn "translated body=$returnval\n"   if DEBUG;
    }
    return $returnval;
}
END_OF_FUNC

'read' => <<'END_OF_FUNC',
sub read {
    my($self,$bytes) = @_;

    # default number of bytes to read
    $bytes = $bytes || $FILLUNIT;

    # Fill up our internal buffer in such a way that the boundary
    # is never split between reads.
    $self->fillBuffer($bytes);

    my $boundary_start = $CGI::EBCDIC ? CGI::Util::ebcdic2ascii($self->{BOUNDARY})      : $self->{BOUNDARY};
    my $boundary_end   = $CGI::EBCDIC ? CGI::Util::ebcdic2ascii($self->{BOUNDARY}.'--') : $self->{BOUNDARY}.'--';

    # Find the boundary in the buffer (it may not be there).
    my $start = index($self->{BUFFER},$boundary_start);

    warn "boundary=$self->{BOUNDARY} length=$self->{LENGTH} start=$start\n" if DEBUG;

    # protect against malformed multipart POST operations
    die "Malformed multipart POST\n" unless $self->{CHUNKED} || ($start >= 0 || $self->{LENGTH} > 0);

    #EBCDIC NOTE: want to translate boundary search into ASCII here.

    # If the boundary begins the data, then skip past it
    # and return undef.
    if ($start == 0) {

	# clear us out completely if we've hit the last boundary.
	if (index($self->{BUFFER},$boundary_end)==0) {
	    $self->{BUFFER}='';
	    $self->{LENGTH}=0;
	    return undef;
	}

	# just remove the boundary.
	substr($self->{BUFFER},0,length($boundary_start))='';
        $self->{BUFFER} =~ s/^\012\015?//;
	return undef;
    }

    my $bytesToReturn;
    if ($start > 0) {           # read up to the boundary
        $bytesToReturn = $start-2 > $bytes ? $bytes : $start;
    } else {    # read the requested number of bytes
	# leave enough bytes in the buffer to allow us to read
	# the boundary.  Thanks to Kevin Hendrick for finding
	# this one.
	$bytesToReturn = $bytes - (length($boundary_start)+1);
    }

    my $returnval=substr($self->{BUFFER},0,$bytesToReturn);
    substr($self->{BUFFER},0,$bytesToReturn)='';
    
    # If we hit the boundary, remove the CRLF from the end.
    return ($bytesToReturn==$start)
           ? substr($returnval,0,-2) : $returnval;
}
END_OF_FUNC


'fillBuffer' => <<'END_OF_FUNC',
sub fillBuffer {
    my($self,$bytes) = @_;
    return unless $self->{CHUNKED} || $self->{LENGTH};

    my($boundaryLength) = length($self->{BOUNDARY});
    my($bufferLength) = length($self->{BUFFER});
    my($bytesToRead) = $bytes - $bufferLength + $boundaryLength + 2;
    $bytesToRead = $self->{LENGTH} if !$self->{CHUNKED} && $self->{LENGTH} < $bytesToRead;

    # Try to read some data.  We may hang here if the browser is screwed up.
    my $bytesRead = $self->{INTERFACE}->read_from_client(\$self->{BUFFER},
							 $bytesToRead,
							 $bufferLength);
    warn "bytesToRead=$bytesToRead, bufferLength=$bufferLength, buffer=$self->{BUFFER}\n" if DEBUG;
    $self->{BUFFER} = '' unless defined $self->{BUFFER};

    # An apparent bug in the Apache server causes the read()
    # to return zero bytes repeatedly without blocking if the
    # remote user aborts during a file transfer.  I don't know how
    # they manage this, but the workaround is to abort if we get
    # more than SPIN_LOOP_MAX consecutive zero reads.
    if ($bytesRead <= 0) {
	die  "CGI.pm: Server closed socket during multipart read (client aborted?).\n"
	    if ($self->{ZERO_LOOP_COUNTER}++ >= $SPIN_LOOP_MAX);
    } else {
	$self->{ZERO_LOOP_COUNTER}=0;
    }

    $self->{LENGTH} -= $bytesRead if !$self->{CHUNKED} && $bytesRead;
}
END_OF_FUNC


'eof' => <<'END_OF_FUNC'
sub eof {
    my($self) = @_;
    return 1 if (length($self->{BUFFER}) == 0)
		 && ($self->{LENGTH} <= 0);
    undef;
}
END_OF_FUNC

);
END_OF_AUTOLOAD

package CGITempFile;

sub find_tempdir {
  $SL = $CGI::SL;
  $MAC = $CGI::OS eq 'MACINTOSH';
  my ($vol) = $MAC ? MacPerl::Volumes() =~ /:(.*)/ : "";
  unless (defined $TMPDIRECTORY) {
    @TEMP=("${SL}usr${SL}tmp","${SL}var${SL}tmp",
	   "C:${SL}temp","${SL}tmp","${SL}temp",
	   "${vol}${SL}Temporary Items",
           "${SL}WWW_ROOT", "${SL}SYS\$SCRATCH",
	   "C:${SL}system${SL}temp");
    
    if( $CGI::OS eq 'WINDOWS' ){
         # PeterH: These evars may not exist if this is invoked within a service and untainting
         # is in effect - with 'use warnings' the undefined array entries causes Perl to die
         unshift(@TEMP,$ENV{TEMP}) if defined $ENV{TEMP};
         unshift(@TEMP,$ENV{TMP}) if defined $ENV{TMP};
         unshift(@TEMP,$ENV{WINDIR} . $SL . 'TEMP') if defined $ENV{WINDIR};
    }

    unshift(@TEMP,$ENV{'TMPDIR'}) if defined $ENV{'TMPDIR'};

    # this feature was supposed to provide per-user tmpfiles, but
    # it is problematic.
    #    unshift(@TEMP,(getpwuid($<))[7].'/tmp') if $CGI::OS eq 'UNIX';
    # Rob: getpwuid() is unfortunately UNIX specific. On brain dead OS'es this
    #    : can generate a 'getpwuid() not implemented' exception, even though
    #    : it's never called.  Found under DOS/Win with the DJGPP perl port.
    #    : Refer to getpwuid() only at run-time if we're fortunate and have  UNIX.
    # unshift(@TEMP,(eval {(getpwuid($>))[7]}).'/tmp') if $CGI::OS eq 'UNIX' and $> != 0;

    for (@TEMP) {
      do {$TMPDIRECTORY = $_; last} if -d $_ && -w _;
    }
  }
  $TMPDIRECTORY  = $MAC ? "" : "." unless $TMPDIRECTORY;
}

find_tempdir();

$MAXTRIES = 5000;

*CGITempFile::AUTOLOAD = \&CGI::AUTOLOAD;

sub DESTROY {
    my($self) = @_;
    $$self =~ m!^([a-zA-Z0-9_ \'\":/.\$\\~-]+)$! || return;
    my $safe = $1;             # untaint operation
    unlink $safe;              # get rid of the file
}

$AUTOLOADED_ROUTINES = '';      # prevent -w error
$AUTOLOADED_ROUTINES=<<'END_OF_AUTOLOAD';
%SUBS = (

'new' => <<'END_OF_FUNC',
sub new {
    my($package,$sequence) = @_;
    my $filename;
    unless (-w $TMPDIRECTORY) {
        $TMPDIRECTORY = undef;
        find_tempdir();
    }
    for (my $i = 0; $i < $MAXTRIES; $i++) {
	last if ! -f ($filename = sprintf("\%s${SL}CGItemp%d", $TMPDIRECTORY, $sequence++));
    }
    # check that it is a more-or-less valid filename
    # Note this same regex is also used elsewhere in the same file for Fh::new
    return unless $filename =~ m!^([a-zA-Z0-9_ \'\":/.\$\\\+-]+)$!;
    # this used to untaint, now it doesn't
    # $filename = $1;
    return bless \$filename;
}
END_OF_FUNC

'as_string' => <<'END_OF_FUNC'
sub as_string {
    my($self) = @_;
    return $$self;
}
END_OF_FUNC

);
END_OF_AUTOLOAD

package CGI;

if ($^W) {
    $CGI::CGI = '';
    $CGI::CGI=<<EOF;
    $CGI::VERSION;
    $MultipartBuffer::SPIN_LOOP_MAX;
    $MultipartBuffer::CRLF;
    $MultipartBuffer::TIMEOUT;
    $MultipartBuffer::INITIAL_FILLUNIT;
EOF
    ;
}

1;

__END__


