package DBD::Gofer::Policy::rush;


use strict;
use warnings;

our $VERSION = "0.010088";

use base qw(DBD::Gofer::Policy::Base);

__PACKAGE__->create_policy_subs({

    # always use connect_cached on server
    connect_method => 'connect_cached',

    # use same methods on server as is called on client
    # (because code not using placeholders would bloat the sth cache)
    prepare_method => '',

    # Skipping the connect check is fast, but it also skips
    # fetching the remote dbh attributes!
    # Make sure that your application doesn't need access to dbh attributes.
    skip_connect_check => 1,

    # most code doesn't rely on sth attributes being set after prepare
    skip_prepare_check => 1,

    # we're happy to use local method if that's the same as the remote
    skip_default_methods => 1,

    # ping is almost meaningless for DBD::Gofer and most transports anyway
    skip_ping => 1,

    # don't update dbh attributes at all
    # XXX actually we currently need dbh_attribute_update for skip_default_methods to work
    # and skip_default_methods is more valuable to us than the cost of dbh_attribute_update
    dbh_attribute_update => 'none', # actually means 'first' currently
    #dbh_attribute_list => undef,

    # we'd like to set locally_* but can't because drivers differ

    # in a rush assume metadata doesn't change
    cache_tables => 1,
    cache_table_info => 1,
    cache_column_info => 1,
    cache_primary_key_info => 1,
    cache_foreign_key_info => 1,
    cache_statistics_info => 1,
    cache_get_info => 1,
});


1;


