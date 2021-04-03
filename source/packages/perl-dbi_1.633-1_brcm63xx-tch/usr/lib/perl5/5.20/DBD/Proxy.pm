
use strict;
use Carp;

require DBI;
DBI->require_version(1.0201);

use RPC::PlClient 0.2000; # XXX change to 0.2017 once it's released

{	package DBD::Proxy::RPC::PlClient;
    	@DBD::Proxy::RPC::PlClient::ISA = qw(RPC::PlClient);
	sub Call {
	    my $self = shift;
	    if ($self->{debug}) {
		my ($rpcmeth, $obj, $method, @args) = @_;
		local $^W; # silence undefs
		Carp::carp("Server $rpcmeth $method(@args)");
	    }
	    return $self->SUPER::Call(@_);
	}
}


package DBD::Proxy;

use vars qw($VERSION $drh %ATTR);

$VERSION = "0.2004";

$drh = undef;		# holds driver handle once initialised

%ATTR = (	# common to db & st, see also %ATTR in DBD::Proxy::db & ::st
    'Warn'	=> 'local',
    'Active'	=> 'local',
    'Kids'	=> 'local',
    'CachedKids' => 'local',
    'PrintError' => 'local',
    'RaiseError' => 'local',
    'HandleError' => 'local',
    'TraceLevel' => 'cached',
    'CompatMode' => 'local',
);

sub driver ($$) {
    if (!$drh) {
	my($class, $attr) = @_;

	$class .= "::dr";

	$drh = DBI::_new_drh($class, {
	    'Name' => 'Proxy',
	    'Version' => $VERSION,
	    'Attribution' => 'DBD::Proxy by Jochen Wiedmann',
	});
	$drh->STORE(CompatMode => 1); # disable DBI dispatcher attribute cache (for FETCH)
    }
    $drh;
}

sub CLONE {
    undef $drh;
}

sub proxy_set_err {
  my ($h,$errmsg) = @_;
  my ($err, $state) = ($errmsg =~ s/ \[err=(.*?),state=(.*?)\]//)
	? ($1, $2) : (1, ' ' x 5);
  return $h->set_err($err, $errmsg, $state);
}

package DBD::Proxy::dr; # ====== DRIVER ======

$DBD::Proxy::dr::imp_data_size = 0;

sub connect ($$;$$) {
    my($drh, $dsn, $user, $auth, $attr)= @_;
    my($dsnOrig) = $dsn;

    my %attr = %$attr;
    my ($var, $val);
    while (length($dsn)) {
	if ($dsn =~ /^dsn=(.*)/) {
	    $attr{'dsn'} = $1;
	    last;
	}
	if ($dsn =~ /^(.*?);(.*)/) {
	    $var = $1;
	    $dsn = $2;
	} else {
	    $var = $dsn;
	    $dsn = '';
	}
	if ($var =~ /^(.*?)=(.*)/) {
	    $var = $1;
	    $val = $2;
	    $attr{$var} = $val;
	}
    }

    my $err = '';
    if (!defined($attr{'hostname'})) { $err .= " Missing hostname."; }
    if (!defined($attr{'port'}))     { $err .= " Missing port."; }
    if (!defined($attr{'dsn'}))      { $err .= " Missing remote dsn."; }

    # Create a cipher object, if requested
    my $cipherRef = undef;
    if ($attr{'cipher'}) {
	$cipherRef = eval { $attr{'cipher'}->new(pack('H*',
							$attr{'key'})) };
	if ($@) { $err .= " Cannot create cipher object: $@."; }
    }
    my $userCipherRef = undef;
    if ($attr{'userkey'}) {
	my $cipher = $attr{'usercipher'} || $attr{'cipher'};
	$userCipherRef = eval { $cipher->new(pack('H*', $attr{'userkey'})) };
	if ($@) { $err .= " Cannot create usercipher object: $@."; }
    }

    return DBD::Proxy::proxy_set_err($drh, $err) if $err; # Returns undef

    my %client_opts = (
		       'peeraddr'	=> $attr{'hostname'},
		       'peerport'	=> $attr{'port'},
		       'socket_proto'	=> 'tcp',
		       'application'	=> $attr{dsn},
		       'user'		=> $user || '',
		       'password'	=> $auth || '',
		       'version'	=> $DBD::Proxy::VERSION,
		       'cipher'	        => $cipherRef,
		       'debug'		=> $attr{debug}   || 0,
		       'timeout'	=> $attr{timeout} || undef,
		       'logfile'	=> $attr{logfile} || undef
		      );
    # Options starting with 'proxy_rpc_' are forwarded to the RPC layer after
    # stripping the prefix.
    while (my($var,$val) = each %attr) {
	if ($var =~ s/^proxy_rpc_//) {
	    $client_opts{$var} = $val;
	}
    }
    # Create an RPC::PlClient object.
    my($client, $msg) = eval { DBD::Proxy::RPC::PlClient->new(%client_opts) };

    return DBD::Proxy::proxy_set_err($drh, "Cannot log in to DBI::ProxyServer: $@")
	if $@; # Returns undef
    return DBD::Proxy::proxy_set_err($drh, "Constructor didn't return a handle: $msg")
	unless ($msg =~ /^((?:\w+|\:\:)+)=(\w+)/); # Returns undef

    $msg = RPC::PlClient::Object->new($1, $client, $msg);

    my $max_proto_ver;
    my ($server_ver_str) = eval { $client->Call('Version') };
    if ( $@ ) {
      # Server denies call, assume legacy protocol.
      $max_proto_ver = 1;
    } else {
      # Parse proxy server version.
      my ($server_ver_num) = $server_ver_str =~ /^DBI::ProxyServer\s+([\d\.]+)/;
      $max_proto_ver = $server_ver_num >= 0.3 ? 2 : 1;
    }
    my $req_proto_ver;
    if ( exists $attr{proxy_lazy_prepare} ) {
      $req_proto_ver = ($attr{proxy_lazy_prepare} == 0) ? 2 : 1;
      return DBD::Proxy::proxy_set_err($drh, 
                 "DBI::ProxyServer does not support synchronous statement preparation.")
	if $max_proto_ver < $req_proto_ver;
    }

    # Switch to user specific encryption mode, if desired
    if ($userCipherRef) {
	$client->{'cipher'} = $userCipherRef;
    }

    # create a 'blank' dbh
    my $this = DBI::_new_dbh($drh, {
	    'Name' => $dsnOrig,
	    'proxy_dbh' => $msg,
	    'proxy_client' => $client,
	    'RowCacheSize' => $attr{'RowCacheSize'} || 20,
	    'proxy_proto_ver' => $req_proto_ver || 1
   });

    foreach $var (keys %attr) {
	if ($var =~ /proxy_/) {
	    $this->{$var} = $attr{$var};
	}
    }
    $this->SUPER::STORE('Active' => 1);

    $this;
}


sub DESTROY { undef }


package DBD::Proxy::db; # ====== DATABASE ======

$DBD::Proxy::db::imp_data_size = 0;


sub commit;
sub rollback;
sub ping;

use vars qw(%ATTR $AUTOLOAD);

%ATTR = (	# see also %ATTR in DBD::Proxy::st
    %DBD::Proxy::ATTR,
    RowCacheSize => 'inherited',
    #AutoCommit => 'cached',
    'FetchHashKeyName' => 'cached',
    Statement => 'local',
    Driver => 'local',
    dbi_connect_closure => 'local',
    Username => 'local',
);

sub AUTOLOAD {
    my $method = $AUTOLOAD;
    $method =~ s/(.*::(.*)):://;
    my $class = $1;
    my $type = $2;
    #warn "AUTOLOAD of $method (class=$class, type=$type)";
    my %expand = (
        'method' => $method,
        'class' => $class,
        'type' => $type,
        'call' => "$method(\@_)",
        # XXX was trying to be smart but was tripping up over the DBI's own
        # smartness. Disabled, but left here in case there are issues.
    #   'call' => (UNIVERSAL::can("DBI::_::$type", $method)) ? "$method(\@_)" : "func(\@_, '$method')",
    );

    my $method_code = q{
        package ~class~;
        sub ~method~ {
            my $h = shift;
            local $@;
            my @result = wantarray
                ? eval {        $h->{'proxy_~type~h'}->~call~ }
                : eval { scalar $h->{'proxy_~type~h'}->~call~ };
            return DBD::Proxy::proxy_set_err($h, $@) if $@;
            return wantarray ? @result : $result[0];
        }
    };
    $method_code =~ s/\~(\w+)\~/$expand{$1}/eg;
    local $SIG{__DIE__} = 'DEFAULT';
    my $err = do { local $@; eval $method_code.2; $@ };
    die $err if $err;
    goto &$AUTOLOAD;
}

sub DESTROY {
    my $dbh = shift;
    local $@ if $@;	# protect $@
    $dbh->disconnect if $dbh->SUPER::FETCH('Active');
}


sub connected { } # client-side not server-side, RT#75868

sub disconnect ($) {
    my ($dbh) = @_;

    # Sadly the Proxy too-often disagrees with the backend database
    # on the subject of 'Active'.  In the short term, I'd like the
    # Proxy to ease up and let me decide when it's proper to go over
    # the wire.  This ultimately applies to finish() as well.
    #return unless $dbh->SUPER::FETCH('Active');

    # Drop database connection at remote end
    my $rdbh = $dbh->{'proxy_dbh'};
    if ( $rdbh ) {
        local $SIG{__DIE__} = 'DEFAULT';
        local $@;
	eval { $rdbh->disconnect() } ;
        DBD::Proxy::proxy_set_err($dbh, $@) if $@;
    }
    
    # Close TCP connect to remote
    # XXX possibly best left till DESTROY? Add a config attribute to choose?
    #$dbh->{proxy_client}->Disconnect(); # Disconnect method requires newer PlRPC module
    $dbh->{proxy_client}->{socket} = undef; # hack

    $dbh->SUPER::STORE('Active' => 0);
    1;
}


sub STORE ($$$) {
    my($dbh, $attr, $val) = @_;
    my $type = $ATTR{$attr} || 'remote';

    if ($attr eq 'TraceLevel') {
	warn("TraceLevel $val");
	my $pc = $dbh->{proxy_client} || die;
	$pc->{logfile} ||= 1; # XXX hack
	$pc->{debug} = ($val && $val >= 4);
	$pc->Debug("$pc debug enabled") if $pc->{debug};
    }

    if ($attr =~ /^proxy_/  ||  $type eq 'inherited') {
	$dbh->{$attr} = $val;
	return 1;
    }

    if ($type eq 'remote' ||  $type eq 'cached') {
        local $SIG{__DIE__} = 'DEFAULT';
	local $@;
	my $result = eval { $dbh->{'proxy_dbh'}->STORE($attr => $val) };
	return DBD::Proxy::proxy_set_err($dbh, $@) if $@; # returns undef
	$dbh->SUPER::STORE($attr => $val) if $type eq 'cached';
	return $result;
    }
    return $dbh->SUPER::STORE($attr => $val);
}

sub FETCH ($$) {
    my($dbh, $attr) = @_;
    # we only get here for cached attribute values if the handle is in CompatMode
    # otherwise the DBI dispatcher handles the FETCH itself from the attribute cache.
    my $type = $ATTR{$attr} || 'remote';

    if ($attr =~ /^proxy_/  ||  $type eq 'inherited'  || $type eq 'cached') {
	return $dbh->{$attr};
    }

    return $dbh->SUPER::FETCH($attr) unless $type eq 'remote';

    local $SIG{__DIE__} = 'DEFAULT';
    local $@;
    my $result = eval { $dbh->{'proxy_dbh'}->FETCH($attr) };
    return DBD::Proxy::proxy_set_err($dbh, $@) if $@;
    return $result;
}

sub prepare ($$;$) {
    my($dbh, $stmt, $attr) = @_;
    my $sth = DBI::_new_sth($dbh, {
				   'Statement' => $stmt,
				   'proxy_attr' => $attr,
				   'proxy_cache_only' => 0,
				   'proxy_params' => [],
				  }
			   );
    my $proto_ver = $dbh->{'proxy_proto_ver'};
    if ( $proto_ver > 1 ) {
      $sth->{'proxy_attr_cache'} = {cache_filled => 0};
      my $rdbh = $dbh->{'proxy_dbh'};
      local $SIG{__DIE__} = 'DEFAULT';
      local $@;
      my $rsth = eval { $rdbh->prepare($sth->{'Statement'}, $sth->{'proxy_attr'}, undef, $proto_ver) };
      return DBD::Proxy::proxy_set_err($sth, $@) if $@;
      return DBD::Proxy::proxy_set_err($sth, "Constructor didn't return a handle: $rsth")
	unless ($rsth =~ /^((?:\w+|\:\:)+)=(\w+)/);
    
      my $client = $dbh->{'proxy_client'};
      $rsth = RPC::PlClient::Object->new($1, $client, $rsth);
      
      $sth->{'proxy_sth'} = $rsth;
      # If statement is a positioned update we do not want any readahead.
      $sth->{'RowCacheSize'} = 1 if $stmt =~ /\bfor\s+update\b/i;
    # Since resources are used by prepared remote handle, mark us active.
    $sth->SUPER::STORE(Active => 1);
    }
    $sth;
}

sub quote {
    my $dbh = shift;
    my $proxy_quote = $dbh->{proxy_quote} || 'remote';

    return $dbh->SUPER::quote(@_)
	if $proxy_quote eq 'local' && @_ == 1;

    # For the common case of only a single argument
    # (no $data_type) we could learn and cache the behaviour.
    # Or we could probe the driver with a few test cases.
    # Or we could add a way to ask the DBI::ProxyServer
    # if $dbh->can('quote') == \&DBI::_::db::quote.
    # Tim
    #
    # Sounds all *very* smart to me. I'd rather suggest to
    # implement some of the typical quote possibilities
    # and let the user set
    #    $dbh->{'proxy_quote'} = 'backslash_escaped';
    # for example.
    # Jochen
    local $SIG{__DIE__} = 'DEFAULT';
    local $@;
    my $result = eval { $dbh->{'proxy_dbh'}->quote(@_) };
    return DBD::Proxy::proxy_set_err($dbh, $@) if $@;
    return $result;
}

sub table_info {
    my $dbh = shift;
    my $rdbh = $dbh->{'proxy_dbh'};
    #warn "table_info(@_)";
    local $SIG{__DIE__} = 'DEFAULT';
    local $@;
    my($numFields, $names, $types, @rows) = eval { $rdbh->table_info(@_) };
    return DBD::Proxy::proxy_set_err($dbh, $@) if $@;
    my ($sth, $inner) = DBI::_new_sth($dbh, {
        'Statement' => "SHOW TABLES",
	'proxy_params' => [],
	'proxy_data' => \@rows,
	'proxy_attr_cache' => { 
		'NUM_OF_PARAMS' => 0, 
		'NUM_OF_FIELDS' => $numFields, 
		'NAME' => $names, 
		'TYPE' => $types,
		'cache_filled' => 1
		},
    	'proxy_cache_only' => 1,
    });
    $sth->SUPER::STORE('NUM_OF_FIELDS' => $numFields);
    $inner->{NAME} = $names;
    $inner->{TYPE} = $types;
    $sth->SUPER::STORE('Active' => 1); # already execute()'d
    $sth->{'proxy_rows'} = @rows;
    return $sth;
}

sub tables {
    my $dbh = shift;
    #warn "tables(@_)";
    return $dbh->SUPER::tables(@_);
}


sub type_info_all {
    my $dbh = shift;
    local $SIG{__DIE__} = 'DEFAULT';
    local $@;
    my $result = eval { $dbh->{'proxy_dbh'}->type_info_all(@_) };
    return DBD::Proxy::proxy_set_err($dbh, $@) if $@;
    return $result;
}


package DBD::Proxy::st; # ====== STATEMENT ======

$DBD::Proxy::st::imp_data_size = 0;

use vars qw(%ATTR);

%ATTR = (	# see also %ATTR in DBD::Proxy::db
    %DBD::Proxy::ATTR,
    'Database' => 'local',
    'RowsInCache' => 'local',
    'RowCacheSize' => 'inherited',
    'NULLABLE' => 'cache_only',
    'NAME' => 'cache_only',
    'TYPE' => 'cache_only',
    'PRECISION' => 'cache_only',
    'SCALE' => 'cache_only',
    'NUM_OF_FIELDS' => 'cache_only',
    'NUM_OF_PARAMS' => 'cache_only'
);

*AUTOLOAD = \&DBD::Proxy::db::AUTOLOAD;

sub execute ($@) {
    my $sth = shift;
    my $params = @_ ? \@_ : $sth->{'proxy_params'};

    # new execute, so delete any cached rows from previous execute
    undef $sth->{'proxy_data'};
    undef $sth->{'proxy_rows'};

    my $rsth = $sth->{proxy_sth};
    my $dbh = $sth->FETCH('Database');
    my $proto_ver = $dbh->{proxy_proto_ver};

    my ($numRows, @outData);

    local $SIG{__DIE__} = 'DEFAULT';
    local $@;
    if ( $proto_ver > 1 ) {
      ($numRows, @outData) = eval { $rsth->execute($params, $proto_ver) };
      return DBD::Proxy::proxy_set_err($sth, $@) if $@;
      
      # Attributes passed back only on the first execute() of a statement.
      unless ($sth->{proxy_attr_cache}->{cache_filled}) {
	my ($numFields, $numParams, $names, $types) = splice(@outData, 0, 4); 
	$sth->{'proxy_attr_cache'} = {
				      'NUM_OF_FIELDS' => $numFields,
				      'NUM_OF_PARAMS' => $numParams,
				      'NAME'          => $names,
				      'cache_filled'  => 1
				     };
	$sth->SUPER::STORE('NUM_OF_FIELDS' => $numFields);
	$sth->SUPER::STORE('NUM_OF_PARAMS' => $numParams);
      }

    }
    else {
      if ($rsth) {
	($numRows, @outData) = eval { $rsth->execute($params, $proto_ver) };
	return DBD::Proxy::proxy_set_err($sth, $@) if $@;

      }
      else {
	my $rdbh = $dbh->{'proxy_dbh'};
	
	# Legacy prepare is actually prepare + first execute on the server.
        ($rsth, @outData) =
	  eval { $rdbh->prepare($sth->{'Statement'},
				$sth->{'proxy_attr'}, $params, $proto_ver) };
	return DBD::Proxy::proxy_set_err($sth, $@) if $@;
	return DBD::Proxy::proxy_set_err($sth, "Constructor didn't return a handle: $rsth")
	  unless ($rsth =~ /^((?:\w+|\:\:)+)=(\w+)/);
	
	my $client = $dbh->{'proxy_client'};
	$rsth = RPC::PlClient::Object->new($1, $client, $rsth);

	my ($numFields, $numParams, $names, $types) = splice(@outData, 0, 4);
	$sth->{'proxy_sth'} = $rsth;
        $sth->{'proxy_attr_cache'} = {
	    'NUM_OF_FIELDS' => $numFields,
	    'NUM_OF_PARAMS' => $numParams,
	    'NAME'          => $names
        };
	$sth->SUPER::STORE('NUM_OF_FIELDS' => $numFields);
	$sth->SUPER::STORE('NUM_OF_PARAMS' => $numParams);
	$numRows = shift @outData;
      }
    }
    # Always condition active flag.
    $sth->SUPER::STORE('Active' => 1) if $sth->FETCH('NUM_OF_FIELDS'); # is SELECT
    $sth->{'proxy_rows'} = $numRows;
    # Any remaining items are output params.
    if (@outData) {
	foreach my $p (@$params) {
	    if (ref($p->[0])) {
		my $ref = shift @outData;
		${$p->[0]} = $$ref;
	    }
	}
    }

    $sth->{'proxy_rows'} || '0E0';
}

sub fetch ($) {
    my $sth = shift;

    my $data = $sth->{'proxy_data'};

    $sth->{'proxy_rows'} = 0 unless defined $sth->{'proxy_rows'};

    if(!$data || !@$data) {
	return undef unless $sth->SUPER::FETCH('Active');

	my $rsth = $sth->{'proxy_sth'};
	if (!$rsth) {
	    die "Attempt to fetch row without execute";
	}
	my $num_rows = $sth->FETCH('RowCacheSize') || 20;
	local $SIG{__DIE__} = 'DEFAULT';
	local $@;
	my @rows = eval { $rsth->fetch($num_rows) };
	return DBD::Proxy::proxy_set_err($sth, $@) if $@;
	unless (@rows == $num_rows) {
	    undef $sth->{'proxy_data'};
	    # server side has already called finish
	    $sth->SUPER::STORE(Active => 0);
	}
	return undef unless @rows;
	$sth->{'proxy_data'} = $data = [@rows];
    }
    my $row = shift @$data;

    $sth->SUPER::STORE(Active => 0) if ( $sth->{proxy_cache_only} and !@$data );
    $sth->{'proxy_rows'}++;
    return $sth->_set_fbav($row);
}
*fetchrow_arrayref = \&fetch;

sub rows ($) {
    my $rows = shift->{'proxy_rows'};
    return (defined $rows) ? $rows : -1;
}

sub finish ($) {
    my($sth) = @_;
    return 1 unless $sth->SUPER::FETCH('Active');
    my $rsth = $sth->{'proxy_sth'};
    $sth->SUPER::STORE('Active' => 0);
    return 0 unless $rsth; # Something's out of sync
    my $no_finish = exists($sth->{'proxy_no_finish'})
 	? $sth->{'proxy_no_finish'}
	: $sth->FETCH('Database')->{'proxy_no_finish'};
    unless ($no_finish) {
        local $SIG{__DIE__} = 'DEFAULT';
	local $@;
	my $result = eval { $rsth->finish() };
	return DBD::Proxy::proxy_set_err($sth, $@) if $@;
	return $result;
    }
    1;
}

sub STORE ($$$) {
    my($sth, $attr, $val) = @_;
    my $type = $ATTR{$attr} || 'remote';

    if ($attr =~ /^proxy_/  ||  $type eq 'inherited') {
	$sth->{$attr} = $val;
	return 1;
    }

    if ($type eq 'cache_only') {
	return 0;
    }

    if ($type eq 'remote' || $type eq 'cached') {
	my $rsth = $sth->{'proxy_sth'}  or  return undef;
        local $SIG{__DIE__} = 'DEFAULT';
	local $@;
	my $result = eval { $rsth->STORE($attr => $val) };
	return DBD::Proxy::proxy_set_err($sth, $@) if ($@);
	return $result if $type eq 'remote'; # else fall through to cache locally
    }
    return $sth->SUPER::STORE($attr => $val);
}

sub FETCH ($$) {
    my($sth, $attr) = @_;

    if ($attr =~ /^proxy_/) {
	return $sth->{$attr};
    }

    my $type = $ATTR{$attr} || 'remote';
    if ($type eq 'inherited') {
	if (exists($sth->{$attr})) {
	    return $sth->{$attr};
	}
	return $sth->FETCH('Database')->{$attr};
    }

    if ($type eq 'cache_only'  &&
	    exists($sth->{'proxy_attr_cache'}->{$attr})) {
	return $sth->{'proxy_attr_cache'}->{$attr};
    }

    if ($type ne 'local') {
	my $rsth = $sth->{'proxy_sth'}  or  return undef;
        local $SIG{__DIE__} = 'DEFAULT';
	local $@;
	my $result = eval { $rsth->FETCH($attr) };
	return DBD::Proxy::proxy_set_err($sth, $@) if $@;
	return $result;
    }
    elsif ($attr eq 'RowsInCache') {
	my $data = $sth->{'proxy_data'};
	$data ? @$data : 0;
    }
    else {
	$sth->SUPER::FETCH($attr);
    }
}

sub bind_param ($$$@) {
    my $sth = shift; my $param = shift;
    $sth->{'proxy_params'}->[$param-1] = [@_];
}
*bind_param_inout = \&bind_param;

sub DESTROY {
    my $sth = shift;
    $sth->finish if $sth->SUPER::FETCH('Active');
}


1;


__END__

