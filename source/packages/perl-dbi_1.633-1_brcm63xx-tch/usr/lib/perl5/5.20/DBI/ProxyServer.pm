

require 5.004;
use strict;

use RPC::PlServer 0.2001;
require DBI;
require Config;


package DBI::ProxyServer;




use vars qw($VERSION @ISA);

$VERSION = "0.3005";
@ISA = qw(RPC::PlServer DBI);


my %DEFAULT_SERVER_OPTIONS;
{
    my $o = \%DEFAULT_SERVER_OPTIONS;
    $o->{'chroot'}     = undef,		# To be used in the initfile,
    					# after loading the required
    					# DBI drivers.
    $o->{'clients'} =
	[ { 'mask' => '.*',
	    'accept' => 1,
	    'cipher' => undef
	    }
	  ];
    $o->{'configfile'} = '/etc/dbiproxy.conf' if -f '/etc/dbiproxy.conf';
    $o->{'debug'}      = 0;
    $o->{'facility'}   = 'daemon';
    $o->{'group'}      = undef;
    $o->{'localaddr'}  = undef;		# Bind to any local IP number
    $o->{'localport'}  = undef;         # Must set port number on the
					# command line.
    $o->{'logfile'}    = undef;         # Use syslog or EventLog.

    # XXX don't restrict methods that can be called (trust users once connected)
    $o->{'XXX_methods'}    = {
	'DBI::ProxyServer' => {
	    'Version' => 1,
	    'NewHandle' => 1,
	    'CallMethod' => 1,
	    'DestroyHandle' => 1
	    },
	'DBI::ProxyServer::db' => {
	    'prepare' => 1,
	    'commit' => 1,
	    'rollback' => 1,
	    'STORE' => 1,
	    'FETCH' => 1,
	    'func' => 1,
	    'quote' => 1,
	    'type_info_all' => 1,
	    'table_info' => 1,
	    'disconnect' => 1,
	    },
	'DBI::ProxyServer::st' => {
	    'execute' => 1,
	    'STORE' => 1,
	    'FETCH' => 1,
	    'func' => 1,
	    'fetch' => 1,
	    'finish' => 1
	    }
    };
    if ($Config::Config{'usethreads'} eq 'define') {
	$o->{'mode'} = 'threads';
    } elsif ($Config::Config{'d_fork'} eq 'define') {
	$o->{'mode'} = 'fork';
    } else {
	$o->{'mode'} = 'single';
    }
    # No pidfile by default, configuration must provide one if needed
    $o->{'pidfile'}    = 'none';
    $o->{'user'}       = undef;
};



sub Version {
    my $version = $DBI::ProxyServer::VERSION;
    "DBI::ProxyServer $version, Copyright (C) 1998, Jochen Wiedmann";
}



sub AcceptApplication {
    my $self = shift; my $dsn = shift;
    $dsn =~ /^dbi:\w+:/i;
}



sub AcceptVersion {
    my $self = shift; my $version = shift;
    require DBI;
    DBI::ProxyServer->init_rootclass();
    $DBI::VERSION >= $version;
}



sub AcceptUser {
    my $self = shift; my $user = shift; my $password = shift;
    return 0 if (!$self->SUPER::AcceptUser($user, $password));
    my $dsn = $self->{'application'};
    $self->Debug("Connecting to $dsn as $user");
    local $ENV{DBI_AUTOPROXY} = ''; # :-)
    $self->{'dbh'} = eval {
        DBI::ProxyServer->connect($dsn, $user, $password,
				  { 'PrintError' => 0, 
				    'Warn' => 0,
				    'RaiseError' => 1,
				    'HandleError' => sub {
				        my $err = $_[1]->err;
					my $state = $_[1]->state || '';
					$_[0] .= " [err=$err,state=$state]";
					return 0;
				    } })
    };
    if ($@) {
	$self->Error("Error while connecting to $dsn as $user: $@");
	return 0;
    }
    [1, $self->StoreHandle($self->{'dbh'}) ];
}


sub CallMethod {
    my $server = shift;
    my $dbh = $server->{'dbh'};
    # We could store the private_server attribute permanently in
    # $dbh. However, we'd have a reference loop in that case and
    # I would be concerned about garbage collection. :-(
    $dbh->{'private_server'} = $server;
    $server->Debug("CallMethod: => " . do { local $^W; join(",", @_)});
    my @result = eval { $server->SUPER::CallMethod(@_) };
    my $msg = $@;
    undef $dbh->{'private_server'};
    if ($msg) {
	$server->Debug("CallMethod died with: $@");
	die $msg;
    } else {
	$server->Debug("CallMethod: <= " . do { local $^W; join(",", @result) });
    }
    @result;
}


sub main {
    my $server = DBI::ProxyServer->new(\%DEFAULT_SERVER_OPTIONS, \@_);
    $server->Bind();
}



package DBI::ProxyServer::dr;

@DBI::ProxyServer::dr::ISA = qw(DBI::dr);


package DBI::ProxyServer::db;

@DBI::ProxyServer::db::ISA = qw(DBI::db);

sub prepare {
    my($dbh, $statement, $attr, $params, $proto_ver) = @_;
    my $server = $dbh->{'private_server'};
    if (my $client = $server->{'client'}) {
	if ($client->{'sql'}) {
	    if ($statement =~ /^\s*(\S+)/) {
		my $st = $1;
		if (!($statement = $client->{'sql'}->{$st})) {
		    die "Unknown SQL query: $st";
		}
	    } else {
		die "Cannot parse restricted SQL statement: $statement";
	    }
	}
    }
    my $sth = $dbh->SUPER::prepare($statement, $attr);
    my $handle = $server->StoreHandle($sth);

    if ( $proto_ver and $proto_ver > 1 ) {
      $sth->{private_proxyserver_described} = 0;
      return $handle;

    } else {
      # The difference between the usual prepare and ours is that we implement
      # a combined prepare/execute. The DBD::Proxy driver doesn't call us for
      # prepare. Only if an execute happens, then we are called with method
      # "prepare". Further execute's are called as "execute".
      my @result = $sth->execute($params);
      my ($NAME, $TYPE);
      my $NUM_OF_FIELDS = $sth->{NUM_OF_FIELDS};
      if ($NUM_OF_FIELDS) {	# is a SELECT
	$NAME = $sth->{NAME};
	$TYPE = $sth->{TYPE};
      }
      ($handle, $NUM_OF_FIELDS, $sth->{'NUM_OF_PARAMS'},
       $NAME, $TYPE, @result);
    }
}

sub table_info {
    my $dbh = shift;
    my $sth = $dbh->SUPER::table_info();
    my $numFields = $sth->{'NUM_OF_FIELDS'};
    my $names = $sth->{'NAME'};
    my $types = $sth->{'TYPE'};

    # We wouldn't need to send all the rows at this point, instead we could
    # make use of $rsth->fetch() on the client as usual.
    # The problem is that some drivers (namely DBD::ExampleP, DBD::mysql and
    # DBD::mSQL) are returning foreign sth's here, thus an instance of
    # DBI::st and not DBI::ProxyServer::st. We could fix this by permitting
    # the client to execute method DBI::st, but I don't like this.
    my @rows;
    while (my ($row) = $sth->fetch()) {
        last unless defined $row;
	push(@rows, [@$row]);
    }
    ($numFields, $names, $types, @rows);
}


package DBI::ProxyServer::st;

@DBI::ProxyServer::st::ISA = qw(DBI::st);

sub execute {
    my $sth = shift; my $params = shift; my $proto_ver = shift;
    my @outParams;
    if ($params) {
	for (my $i = 0;  $i < @$params;) {
	    my $param = $params->[$i++];
	    if (!ref($param)) {
		$sth->bind_param($i, $param);
	    }
	    else {	
		if (!ref(@$param[0])) {#It's not a reference
		    $sth->bind_param($i, @$param);
		}
		else {
		    $sth->bind_param_inout($i, @$param);
		    my $ref = shift @$param;
		    push(@outParams, $ref);
		}
	    }
	}
    }
    my $rows = $sth->SUPER::execute();
    if ( $proto_ver and $proto_ver > 1 and not $sth->{private_proxyserver_described} ) {
      my ($NAME, $TYPE);
      my $NUM_OF_FIELDS = $sth->{NUM_OF_FIELDS};
      if ($NUM_OF_FIELDS) {	# is a SELECT
	$NAME = $sth->{NAME};
	$TYPE = $sth->{TYPE};
      }
      $sth->{private_proxyserver_described} = 1;
      # First execution, we ship back description.
      return ($rows, $NUM_OF_FIELDS, $sth->{'NUM_OF_PARAMS'}, $NAME, $TYPE, @outParams);
    }
    ($rows, @outParams);
}

sub fetch {
    my $sth = shift; my $numRows = shift || 1;
    my($ref, @rows);
    while ($numRows--  &&  ($ref = $sth->SUPER::fetch())) {
	push(@rows, [@$ref]);
    }
    @rows;
}


1;


__END__

