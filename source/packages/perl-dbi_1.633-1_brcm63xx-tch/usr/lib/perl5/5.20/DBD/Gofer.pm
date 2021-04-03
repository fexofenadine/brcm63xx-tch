{
    package DBD::Gofer;

    use strict;

    require DBI;
    require DBI::Gofer::Request;
    require DBI::Gofer::Response;
    require Carp;

    our $VERSION = "0.015327";




    # attributes we'll allow local STORE
    our %xxh_local_store_attrib = map { $_=>1 } qw(
        Active
        CachedKids
        Callbacks
        DbTypeSubclass
        ErrCount Executed
        FetchHashKeyName
        HandleError HandleSetErr
        InactiveDestroy
        AutoInactiveDestroy
        PrintError PrintWarn
        Profile
        RaiseError
        RootClass
        ShowErrorStatement
        Taint TaintIn TaintOut
        TraceLevel
        Warn
        dbi_quote_identifier_cache
        dbi_connect_closure
        dbi_go_execute_unique
    );
    our %xxh_local_store_attrib_if_same_value = map { $_=>1 } qw(
        Username
        dbi_connect_method
    );

    our $drh = undef;    # holds driver handle once initialized
    our $methods_already_installed;

    sub driver{
        return $drh if $drh;

        DBI->setup_driver('DBD::Gofer');

        unless ($methods_already_installed++) {
            my $opts = { O=> 0x0004 }; # IMA_KEEP_ERR
            DBD::Gofer::db->install_method('go_dbh_method', $opts);
            DBD::Gofer::st->install_method('go_sth_method', $opts);
            DBD::Gofer::st->install_method('go_clone_sth',  $opts);
            DBD::Gofer::db->install_method('go_cache',      $opts);
            DBD::Gofer::st->install_method('go_cache',      $opts);
        }

        my($class, $attr) = @_;
        $class .= "::dr";
        ($drh) = DBI::_new_drh($class, {
            'Name' => 'Gofer',
            'Version' => $VERSION,
            'Attribution' => 'DBD Gofer by Tim Bunce',
        });

        $drh;
    }


    sub CLONE {
        undef $drh;
    }


    sub go_cache {
        my $h = shift;
        $h->{go_cache} = shift if @_;
        # return handle's override go_cache, if it has one
        return $h->{go_cache} if defined $h->{go_cache};
        # or else the transports default go_cache
        return $h->{go_transport}->{go_cache};
    }


    sub set_err_from_response { # set error/warn/info and propagate warnings
        my $h = shift;
        my $response = shift;
        if (my $warnings = $response->warnings) {
            warn $_ for @$warnings;
        }
        my ($err, $errstr, $state) = $response->err_errstr_state;
        # Only set_err() if there's an error else leave the current values
        # (The current values will normally be set undef by the DBI dispatcher
        # except for methods marked KEEPERR such as ping.)
        $h->set_err($err, $errstr, $state) if defined $err;
        return undef;
    }


    sub install_methods_proxy {
        my ($installed_methods) = @_;
        while ( my ($full_method, $attr) = each %$installed_methods ) {
            # need to install both a DBI dispatch stub and a proxy stub
            # (the dispatch stub may be already here due to local driver use)

            DBI->_install_method($full_method, "", $attr||{})
                unless defined &{$full_method};

            # now install proxy stubs on the driver side
            $full_method =~ m/^DBI::(\w\w)::(\w+)$/
                or die "Invalid method name '$full_method' for install_method";
            my ($type, $method) = ($1, $2);
            my $driver_method = "DBD::Gofer::${type}::${method}";
            next if defined &{$driver_method};
            my $sub;
            if ($type eq 'db') {
                $sub = sub { return shift->go_dbh_method(undef, $method, @_) };
            }
            else {
                $sub = sub { shift->set_err($DBI::stderr, "Can't call \$${type}h->$method when using DBD::Gofer"); return; };
            }
            no strict 'refs';
            *$driver_method = $sub;
        }
    }
}


{   package DBD::Gofer::dr; # ====== DRIVER ======

    $imp_data_size = 0;
    use strict;

    sub connect_cached {
        my ($drh, $dsn, $user, $auth, $attr)= @_;
        $attr ||= {};
        return $drh->SUPER::connect_cached($dsn, $user, $auth, {
            (%$attr),
            go_connect_method => $attr->{go_connect_method} || 'connect_cached',
        });
    }


    sub connect {
        my($drh, $dsn, $user, $auth, $attr)= @_;
        my $orig_dsn = $dsn;

        # first remove dsn= and everything after it
        my $remote_dsn = ($dsn =~ s/;?\bdsn=(.*)$// && $1)
            or return $drh->set_err($DBI::stderr, "No dsn= argument in '$orig_dsn'");

        if ($attr->{go_bypass}) { # don't use DBD::Gofer for this connection
            # useful for testing with DBI_AUTOPROXY, e.g., t/03handle.t
            return DBI->connect($remote_dsn, $user, $auth, $attr);
        }

        my %go_attr;
        # extract any go_ attributes from the connect() attr arg
        for my $k (grep { /^go_/ } keys %$attr) {
            $go_attr{$k} = delete $attr->{$k};
        }
        # then override those with any attributes embedded in our dsn (not remote_dsn)
        for my $kv (grep /=/, split /;/, $dsn, -1) {
            my ($k, $v) = split /=/, $kv, 2;
            $go_attr{ "go_$k" } = $v;
        }

        if (not ref $go_attr{go_policy}) { # if not a policy object already
            my $policy_class = $go_attr{go_policy} || 'classic';
            $policy_class = "DBD::Gofer::Policy::$policy_class"
                unless $policy_class =~ /::/;
            _load_class($policy_class)
                or return $drh->set_err($DBI::stderr, "Can't load $policy_class: $@");
            # replace policy name in %go_attr with policy object
            $go_attr{go_policy} = eval { $policy_class->new(\%go_attr) }
                or return $drh->set_err($DBI::stderr, "Can't instanciate $policy_class: $@");
        }
        # policy object is left in $go_attr{go_policy} so transport can see it
        my $go_policy = $go_attr{go_policy};

        if ($go_attr{go_cache} and not ref $go_attr{go_cache}) { # if not a cache object already
            my $cache_class = $go_attr{go_cache};
            $cache_class = "DBI::Util::CacheMemory" if $cache_class eq '1';
            _load_class($cache_class)
                or return $drh->set_err($DBI::stderr, "Can't load $cache_class $@");
            $go_attr{go_cache} = eval { $cache_class->new() }
                or $drh->set_err(0, "Can't instanciate $cache_class: $@"); # warning
        }

        # delete any other attributes that don't apply to transport
        my $go_connect_method = delete $go_attr{go_connect_method};

        my $transport_class = delete $go_attr{go_transport}
            or return $drh->set_err($DBI::stderr, "No transport= argument in '$orig_dsn'");
        $transport_class = "DBD::Gofer::Transport::$transport_class"
            unless $transport_class =~ /::/;
        _load_class($transport_class)
            or return $drh->set_err($DBI::stderr, "Can't load $transport_class: $@");
        my $go_transport = eval { $transport_class->new(\%go_attr) }
            or return $drh->set_err($DBI::stderr, "Can't instanciate $transport_class: $@");

        my $request_class = "DBI::Gofer::Request";
        my $go_request = eval {
            my $go_attr = { %$attr };
            # XXX user/pass of fwd server vs db server ? also impact of autoproxy
            if ($user) {
                $go_attr->{Username} = $user;
                $go_attr->{Password} = $auth;
            }
            # delete any attributes we can't serialize (or don't want to)
            delete @{$go_attr}{qw(Profile HandleError HandleSetErr Callbacks)};
            # delete any attributes that should only apply to the client-side
            delete @{$go_attr}{qw(RootClass DbTypeSubclass)};

            $go_connect_method ||= $go_policy->connect_method($remote_dsn, $go_attr) || 'connect';
            $request_class->new({
                dbh_connect_call => [ $go_connect_method, $remote_dsn, $user, $auth, $go_attr ],
            })
        } or return $drh->set_err($DBI::stderr, "Can't instanciate $request_class: $@");

        my ($dbh, $dbh_inner) = DBI::_new_dbh($drh, {
            'Name' => $dsn,
            'USER' => $user,
            go_transport => $go_transport,
            go_request => $go_request,
            go_policy => $go_policy,
        });

        # mark as inactive temporarily for STORE. Active not set until connected() called.
        $dbh->STORE(Active => 0);

        # should we ping to check the connection
        # and fetch dbh attributes
        my $skip_connect_check = $go_policy->skip_connect_check($attr, $dbh);
        if (not $skip_connect_check) {
            if (not $dbh->go_dbh_method(undef, 'ping')) {
                return undef if $dbh->err; # error already recorded, typically
                return $dbh->set_err($DBI::stderr, "ping failed");
            }
        }

        return $dbh;
    }

    sub _load_class { # return true or false+$@
        my $class = shift;
        (my $pm = $class) =~ s{::}{/}g;
        $pm .= ".pm";
        return 1 if eval { require $pm };
        delete $INC{$pm}; # shouldn't be needed (perl bug?) and assigning undef isn't enough
        undef; # error in $@
    }

}


{   package DBD::Gofer::db; # ====== DATABASE ======
    $imp_data_size = 0;
    use strict;
    use Carp qw(carp croak);

    my %dbh_local_store_attrib = %DBD::Gofer::xxh_local_store_attrib;

    sub connected {
        shift->STORE(Active => 1);
    }

    sub go_dbh_method {
        my $dbh = shift;
        my $meta = shift;
        # @_ now contains ($method_name, @args)

        my $request = $dbh->{go_request};
        $request->init_request([ wantarray, @_ ], $dbh);
        ++$dbh->{go_request_count};

        my $go_policy = $dbh->{go_policy};
        my $dbh_attribute_update = $go_policy->dbh_attribute_update();
        $request->dbh_attributes( $go_policy->dbh_attribute_list() )
            if $dbh_attribute_update eq 'every'
            or $dbh->{go_request_count}==1;

        $request->dbh_last_insert_id_args($meta->{go_last_insert_id_args})
            if $meta->{go_last_insert_id_args};

        my $transport = $dbh->{go_transport}
            or return $dbh->set_err($DBI::stderr, "Not connected (no transport)");

        local $transport->{go_cache} = $dbh->{go_cache}
            if defined $dbh->{go_cache};

        my ($response, $retransmit_sub) = $transport->transmit_request($request);
        $response ||= $transport->receive_response($request, $retransmit_sub);
        $dbh->{go_response} = $response
            or die "No response object returned by $transport";

        die "response '$response' returned by $transport is not a response object"
            unless UNIVERSAL::isa($response,"DBI::Gofer::Response");

        if (my $dbh_attributes = $response->dbh_attributes) {

            # XXX installed_methods piggybacks on dbh_attributes for now
            if (my $installed_methods = delete $dbh_attributes->{dbi_installed_methods}) {
                DBD::Gofer::install_methods_proxy($installed_methods)
                    if $dbh->{go_request_count}==1;
            }

            # XXX we don't STORE here, we just stuff the value into the attribute cache
            $dbh->{$_} = $dbh_attributes->{$_}
                for keys %$dbh_attributes;
        }

        my $rv = $response->rv;
        if (my $resultset_list = $response->sth_resultsets) {
            # dbh method call returned one or more resultsets
            # (was probably a metadata method like table_info)
            #
            # setup an sth but don't execute/forward it
            my $sth = $dbh->prepare(undef, { go_skip_prepare_check => 1 });
            # set the sth response to our dbh response
            (tied %$sth)->{go_response} = $response;
            # setup the sth with the results in our response
            $sth->more_results;
            # and return that new sth as if it came from original request
            $rv = [ $sth ];
        }
        elsif (!$rv) { # should only occur for major transport-level error
            #carp("no rv in response { @{[ %$response ]} }");
            $rv = [ ];
        }

        DBD::Gofer::set_err_from_response($dbh, $response);

        return (wantarray) ? @$rv : $rv->[0];
    }


    # Methods that should be forwarded but can be cached
    for my $method (qw(
        tables table_info column_info primary_key_info foreign_key_info statistics_info
        data_sources type_info_all get_info
        parse_trace_flags parse_trace_flag
        func
    )) {
        my $policy_name = "cache_$method";
        my $super_name  = "SUPER::$method";
        my $sub = sub {
            my $dbh = shift;
            my $rv;

            # if we know the remote side doesn't override the DBI's default method
            # then we might as well just call the DBI's default method on the client
            # (which may, in turn, call other methods that are forwarded, like get_info)
            if ($dbh->{dbi_default_methods}{$method} && $dbh->{go_policy}->skip_default_methods()) {
                $dbh->trace_msg("    !! $method: using local default as remote method is also default\n");
                return $dbh->$super_name(@_);
            }

            my $cache;
            my $cache_key;
            if (my $cache_it = $dbh->{go_policy}->$policy_name(undef, $dbh, @_)) {
                $cache = $dbh->{go_meta_cache} ||= {}; # keep separate from go_cache
                $cache_key = sprintf "%s_wa%d(%s)", $policy_name, wantarray||0,
                    join(",\t", map { # XXX basic but sufficient for now
                         !ref($_)            ? DBI::neat($_,1e6)
                        : ref($_) eq 'ARRAY' ? DBI::neat_list($_,1e6,",\001")
                        : ref($_) eq 'HASH'  ? do { my @k = sort keys %$_; DBI::neat_list([@k,@{$_}{@k}],1e6,",\002") }
                        : do { warn "unhandled argument type ($_)"; $_ }
                    } @_);
                if ($rv = $cache->{$cache_key}) {
                    $dbh->trace_msg("$method(@_) returning previously cached value ($cache_key)\n",4);
                    my @cache_rv = @$rv;
                    # if it's an sth we have to clone it
                    $cache_rv[0] = $cache_rv[0]->go_clone_sth if UNIVERSAL::isa($cache_rv[0],'DBI::st');
                    return (wantarray) ? @cache_rv : $cache_rv[0];
                }
            }

            $rv = [ (wantarray)
                ?       ($dbh->go_dbh_method(undef, $method, @_))
                : scalar $dbh->go_dbh_method(undef, $method, @_)
            ];

            if ($cache) {
                $dbh->trace_msg("$method(@_) caching return value ($cache_key)\n",4);
                my @cache_rv = @$rv;
                # if it's an sth we have to clone it
                #$cache_rv[0] = $cache_rv[0]->go_clone_sth
                #   if UNIVERSAL::isa($cache_rv[0],'DBI::st');
                $cache->{$cache_key} = \@cache_rv
                    unless UNIVERSAL::isa($cache_rv[0],'DBI::st'); # XXX cloning sth not yet done
            }

            return (wantarray) ? @$rv : $rv->[0];
        };
        no strict 'refs';
        *$method = $sub;
    }


    # Methods that can use the DBI defaults for some situations/drivers
    for my $method (qw(
        quote quote_identifier
    )) {    # XXX keep DBD::Gofer::Policy::Base in sync
        my $policy_name = "locally_$method";
        my $super_name  = "SUPER::$method";
        my $sub = sub {
            my $dbh = shift;

            # if we know the remote side doesn't override the DBI's default method
            # then we might as well just call the DBI's default method on the client
            # (which may, in turn, call other methods that are forwarded, like get_info)
            if ($dbh->{dbi_default_methods}{$method} && $dbh->{go_policy}->skip_default_methods()) {
                $dbh->trace_msg("    !! $method: using local default as remote method is also default\n");
                return $dbh->$super_name(@_);
            }

            # false:    use remote gofer
            # 1:        use local DBI default method
            # code ref: use the code ref
            my $locally = $dbh->{go_policy}->$policy_name($dbh, @_);
            if ($locally) {
                return $locally->($dbh, @_) if ref $locally eq 'CODE';
                return $dbh->$super_name(@_);
            }
            return $dbh->go_dbh_method(undef, $method, @_); # propagate context
        };
        no strict 'refs';
        *$method = $sub;
    }


    # Methods that should always fail
    for my $method (qw(
        begin_work commit rollback
    )) {
        no strict 'refs';
        *$method = sub { return shift->set_err($DBI::stderr, "$method not available with DBD::Gofer") }
    }


    sub do {
        my ($dbh, $sql, $attr, @args) = @_;
        delete $dbh->{Statement}; # avoid "Modification of non-creatable hash value attempted"
        $dbh->{Statement} = $sql; # for profiling and ShowErrorStatement
        my $meta = { go_last_insert_id_args => $attr->{go_last_insert_id_args} };
        return $dbh->go_dbh_method($meta, 'do', $sql, $attr, @args);
    }

    sub ping {
        my $dbh = shift;
        return $dbh->set_err('', "can't ping while not connected") # info
            unless $dbh->SUPER::FETCH('Active');
        my $skip_ping = $dbh->{go_policy}->skip_ping();
        return ($skip_ping) ? 1 : $dbh->go_dbh_method(undef, 'ping', @_);
    }

    sub last_insert_id {
        my $dbh = shift;
        my $response = $dbh->{go_response} or return undef;
        return $response->last_insert_id;
    }

    sub FETCH {
        my ($dbh, $attrib) = @_;

        # FETCH is effectively already cached because the DBI checks the
        # attribute cache in the handle before calling FETCH
        # and this FETCH copies the value into the attribute cache

        # forward driver-private attributes (except ours)
        if ($attrib =~ m/^[a-z]/ && $attrib !~ /^go_/) {
            my $value = $dbh->go_dbh_method(undef, 'FETCH', $attrib);
            $dbh->{$attrib} = $value; # XXX forces caching by DBI
            return $dbh->{$attrib} = $value;
        }

        # else pass up to DBI to handle
        return $dbh->SUPER::FETCH($attrib);
    }

    sub STORE {
        my ($dbh, $attrib, $value) = @_;
        if ($attrib eq 'AutoCommit') {
            croak "Can't enable transactions when using DBD::Gofer" if !$value;
            return $dbh->SUPER::STORE($attrib => ($value) ? -901 : -900);
        }
        return $dbh->SUPER::STORE($attrib => $value)
            # we handle this attribute locally
            if $dbh_local_store_attrib{$attrib}
            # or it's a private_ (application) attribute
            or $attrib =~ /^private_/
            # or not yet connected (ie being called by DBI->connect)
            or not $dbh->FETCH('Active');

        return $dbh->SUPER::STORE($attrib => $value)
            if $DBD::Gofer::xxh_local_store_attrib_if_same_value{$attrib}
            && do { # values are the same
                my $crnt = $dbh->FETCH($attrib);
                local $^W;
                (defined($value) ^ defined($crnt))
                    ? 0 # definedness differs
                    : $value eq $crnt;
            };

        # dbh attributes are set at connect-time - see connect()
        carp("Can't alter \$dbh->{$attrib} after handle created with DBD::Gofer") if $dbh->FETCH('Warn');
        return $dbh->set_err($DBI::stderr, "Can't alter \$dbh->{$attrib} after handle created with DBD::Gofer");
    }

    sub disconnect {
        my $dbh = shift;
        $dbh->{go_transport} = undef;
        $dbh->STORE(Active => 0);
    }

    sub prepare {
        my ($dbh, $statement, $attr)= @_;

        return $dbh->set_err($DBI::stderr, "Can't prepare when disconnected")
            unless $dbh->FETCH('Active');

        $attr = { %$attr } if $attr; # copy so we can edit

        my $policy     = delete($attr->{go_policy}) || $dbh->{go_policy};
        my $lii_args   = delete $attr->{go_last_insert_id_args};
        my $go_prepare = delete($attr->{go_prepare_method})
                      || $dbh->{go_prepare_method}
                      || $policy->prepare_method($dbh, $statement, $attr)
                      || 'prepare'; # e.g. for code not using placeholders
        my $go_cache = delete $attr->{go_cache};
        # set to undef if there are no attributes left for the actual prepare call
        $attr = undef if $attr and not %$attr;

        my ($sth, $sth_inner) = DBI::_new_sth($dbh, {
            Statement => $statement,
            go_prepare_call => [ 0, $go_prepare, $statement, $attr ],
            # go_method_calls => [], # autovivs if needed
            go_request => $dbh->{go_request},
            go_transport => $dbh->{go_transport},
            go_policy => $policy,
            go_last_insert_id_args => $lii_args,
            go_cache => $go_cache,
        });
        $sth->STORE(Active => 0); # XXX needed? It should be the default

        my $skip_prepare_check = $policy->skip_prepare_check($attr, $dbh, $statement, $attr, $sth);
        if (not $skip_prepare_check) {
            $sth->go_sth_method() or return undef;
        }

        return $sth;
    }

    sub prepare_cached {
        my ($dbh, $sql, $attr, $if_active)= @_;
        $attr ||= {};
        return $dbh->SUPER::prepare_cached($sql, {
            %$attr,
            go_prepare_method => $attr->{go_prepare_method} || 'prepare_cached',
        }, $if_active);
    }

    *go_cache = \&DBD::Gofer::go_cache;
}


{   package DBD::Gofer::st; # ====== STATEMENT ======
    $imp_data_size = 0;
    use strict;

    my %sth_local_store_attrib = (%DBD::Gofer::xxh_local_store_attrib, NUM_OF_FIELDS => 1);

    sub go_sth_method {
        my ($sth, $meta) = @_;

        if (my $ParamValues = $sth->{ParamValues}) {
            my $ParamAttr = $sth->{ParamAttr};
            # XXX the sort here is a hack to work around a DBD::Sybase bug
            # but only works properly for params 1..9
            # (reverse because of the unshift)
            my @params = reverse sort keys %$ParamValues;
            if (@params > 9 && ($sth->{Database}{go_dsn}||'') =~ /dbi:Sybase/) {
                # if more than 9 then we need to do a proper numeric sort
                # also warn to alert user of this issue
                warn "Sybase param binding order hack in use";
                @params = sort { $b <=> $a } @params;
            }
            for my $p (@params) {
                # unshift to put binds before execute call
                unshift @{ $sth->{go_method_calls} },
                    [ 'bind_param', $p, $ParamValues->{$p}, $ParamAttr->{$p} ];
            }
        }

        my $dbh = $sth->{Database} or die "panic";
        ++$dbh->{go_request_count};

        my $request = $sth->{go_request};
        $request->init_request($sth->{go_prepare_call}, $sth);
        $request->sth_method_calls(delete $sth->{go_method_calls})
            if $sth->{go_method_calls};
        $request->sth_result_attr({}); # (currently) also indicates this is an sth request

        $request->dbh_last_insert_id_args($meta->{go_last_insert_id_args})
            if $meta->{go_last_insert_id_args};

        my $go_policy = $sth->{go_policy};
        my $dbh_attribute_update = $go_policy->dbh_attribute_update();
        $request->dbh_attributes( $go_policy->dbh_attribute_list() )
            if $dbh_attribute_update eq 'every'
            or $dbh->{go_request_count}==1;

        my $transport = $sth->{go_transport}
            or return $sth->set_err($DBI::stderr, "Not connected (no transport)");

        local $transport->{go_cache} = $sth->{go_cache}
            if defined $sth->{go_cache};

        my ($response, $retransmit_sub) = $transport->transmit_request($request);
        $response ||= $transport->receive_response($request, $retransmit_sub);
        $sth->{go_response} = $response
            or die "No response object returned by $transport";
        $dbh->{go_response} = $response; # mainly for last_insert_id

        if (my $dbh_attributes = $response->dbh_attributes) {
            # XXX we don't STORE here, we just stuff the value into the attribute cache
            $dbh->{$_} = $dbh_attributes->{$_}
                for keys %$dbh_attributes;
            # record the values returned, so we know that we have fetched
            # values are which we have fetched (see dbh->FETCH method)
            $dbh->{go_dbh_attributes_fetched} = $dbh_attributes;
        }

        my $rv = $response->rv; # may be undef on error
        if ($response->sth_resultsets) {
            # setup first resultset - including sth attributes
            $sth->more_results;
        }
        else {
            $sth->STORE(Active => 0);
            $sth->{go_rows} = $rv;
        }
        # set error/warn/info (after more_results as that'll clear err)
        DBD::Gofer::set_err_from_response($sth, $response);

        return $rv;
    }


    sub bind_param {
        my ($sth, $param, $value, $attr) = @_;
        $sth->{ParamValues}{$param} = $value;
        $sth->{ParamAttr}{$param}   = $attr
            if defined $attr; # attr is sticky if not explicitly set
        return 1;
    }


    sub execute {
        my $sth = shift;
        $sth->bind_param($_, $_[$_-1]) for (1..@_);
        push @{ $sth->{go_method_calls} }, [ 'execute' ];
        my $meta = { go_last_insert_id_args => $sth->{go_last_insert_id_args} };
        return $sth->go_sth_method($meta);
    }


    sub more_results {
        my $sth = shift;

        $sth->finish;

        my $response = $sth->{go_response} or do {
            # e.g., we haven't sent a request yet (ie prepare then more_results)
            $sth->trace_msg("    No response object present", 3);
            return;
        };

        my $resultset_list = $response->sth_resultsets
            or return $sth->set_err($DBI::stderr, "No sth_resultsets");

        my $meta = shift @$resultset_list
            or return undef; # no more result sets
        #warn "more_results: ".Data::Dumper::Dumper($meta);

        # pull out the special non-attributes first
        my ($rowset, $err, $errstr, $state)
            = delete @{$meta}{qw(rowset err errstr state)};

        # copy meta attributes into attribute cache
        my $NUM_OF_FIELDS = delete $meta->{NUM_OF_FIELDS};
        $sth->STORE('NUM_OF_FIELDS', $NUM_OF_FIELDS);
        # XXX need to use STORE for some?
        $sth->{$_} = $meta->{$_} for keys %$meta;

        if (($NUM_OF_FIELDS||0) > 0) {
            $sth->{go_rows}           = ($rowset) ? @$rowset : -1;
            $sth->{go_current_rowset} = $rowset;
            $sth->{go_current_rowset_err} = [ $err, $errstr, $state ]
                if defined $err;
            $sth->STORE(Active => 1) if $rowset;
        }

        return $sth;
    }


    sub go_clone_sth {
        my ($sth1) = @_;
        # clone an (un-fetched-from) sth - effectively undoes the initial more_results
        # not 100% so just for use in caching returned sth e.g. table_info
        my $sth2 = $sth1->{Database}->prepare($sth1->{Statement}, { go_skip_prepare_check => 1 });
        $sth2->STORE($_, $sth1->{$_}) for qw(NUM_OF_FIELDS Active);
        my $sth2_inner = tied %$sth2;
        $sth2_inner->{$_} = $sth1->{$_} for qw(NUM_OF_PARAMS FetchHashKeyName);
        die "not fully implemented yet";
        return $sth2;
    }


    sub fetchrow_arrayref {
        my ($sth) = @_;
        my $resultset = $sth->{go_current_rowset} || do {
            # should only happen if fetch called after execute failed
            my $rowset_err = $sth->{go_current_rowset_err}
                || [ 1, 'no result set (did execute fail)' ];
            return $sth->set_err( @$rowset_err );
        };
        return $sth->_set_fbav(shift @$resultset) if @$resultset;
        $sth->finish;     # no more data so finish
        return undef;
    }
    *fetch = \&fetchrow_arrayref; # alias


    sub fetchall_arrayref {
        my ($sth, $slice, $max_rows) = @_;
        my $resultset = $sth->{go_current_rowset} || do {
            # should only happen if fetch called after execute failed
            my $rowset_err = $sth->{go_current_rowset_err}
                || [ 1, 'no result set (did execute fail)' ];
            return $sth->set_err( @$rowset_err );
        };
        my $mode = ref($slice) || 'ARRAY';
        return $sth->SUPER::fetchall_arrayref($slice, $max_rows)
            if ref($slice) or defined $max_rows;
        $sth->finish;     # no more data after this so finish
        return $resultset;
    }


    sub rows {
        return shift->{go_rows};
    }


    sub STORE {
        my ($sth, $attrib, $value) = @_;

        return $sth->SUPER::STORE($attrib => $value)
            if $sth_local_store_attrib{$attrib} # handle locally
            # or it's a private_ (application) attribute
            or $attrib =~ /^private_/;

        # otherwise warn but do it anyway
        # this will probably need refining later
        my $msg = "Altering \$sth->{$attrib} won't affect proxied handle";
        Carp::carp($msg) if $sth->FETCH('Warn');

        # XXX could perhaps do
        #   push @{ $sth->{go_method_calls} }, [ 'STORE', $attrib, $value ]
        #       if not $sth->FETCH('Executed');
        # but how to handle repeat executions? How to we know when an
        # attribute is being set to affect the current resultset or the
        # next execution?
        # Could just always use go_method_calls I guess.

        # do the store locally anyway, just in case
        $sth->SUPER::STORE($attrib => $value);

        return $sth->set_err($DBI::stderr, $msg);
    }

    # sub bind_param_array
    # we use DBI's default, which sets $sth->{ParamArrays}{$param} = $value
    # and calls bind_param($param, undef, $attr) if $attr.

    sub execute_array {
        my $sth = shift;
        my $attr = shift;
        $sth->bind_param_array($_, $_[$_-1]) for (1..@_);
        push @{ $sth->{go_method_calls} }, [ 'execute_array', $attr ];
        return $sth->go_sth_method($attr);
    }

    *go_cache = \&DBD::Gofer::go_cache;
}

1;

__END__

