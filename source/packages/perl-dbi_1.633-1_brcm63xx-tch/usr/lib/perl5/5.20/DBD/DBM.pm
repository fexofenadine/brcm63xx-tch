require 5.008;
use strict;

package DBD::DBM;
use base qw( DBD::File );
use vars qw($VERSION $ATTRIBUTION $drh $methods_already_installed);
$VERSION     = '0.08';
$ATTRIBUTION = 'DBD::DBM by Jens Rehsack';

sub driver ($;$)
{
    my ( $class, $attr ) = @_;
    return $drh if ($drh);

    # do the real work in DBD::File
    #
    $attr->{Attribution} = 'DBD::DBM by Jens Rehsack';
    $drh = $class->SUPER::driver($attr);

    # install private methods
    #
    # this requires that dbm_ (or foo_) be a registered prefix
    # but you can write private methods before official registration
    # by hacking the $dbd_prefix_registry in a private copy of DBI.pm
    #
    unless ( $methods_already_installed++ )
    {
        DBD::DBM::st->install_method('dbm_schema');
    }

    return $drh;
}

sub CLONE
{
    undef $drh;
}

package DBD::DBM::dr;
$DBD::DBM::dr::imp_data_size = 0;
@DBD::DBM::dr::ISA           = qw(DBD::File::dr);



package DBD::DBM::db;
$DBD::DBM::db::imp_data_size = 0;
@DBD::DBM::db::ISA           = qw(DBD::File::db);

use Carp qw/carp/;

sub validate_STORE_attr
{
    my ( $dbh, $attrib, $value ) = @_;

    if ( $attrib eq "dbm_ext" or $attrib eq "dbm_lockfile" )
    {
        ( my $newattrib = $attrib ) =~ s/^dbm_/f_/g;
        carp "Attribute '$attrib' is depreciated, use '$newattrib' instead" if ($^W);
        $attrib = $newattrib;
    }

    return $dbh->SUPER::validate_STORE_attr( $attrib, $value );
}

sub validate_FETCH_attr
{
    my ( $dbh, $attrib ) = @_;

    if ( $attrib eq "dbm_ext" or $attrib eq "dbm_lockfile" )
    {
        ( my $newattrib = $attrib ) =~ s/^dbm_/f_/g;
        carp "Attribute '$attrib' is depreciated, use '$newattrib' instead" if ($^W);
        $attrib = $newattrib;
    }

    return $dbh->SUPER::validate_FETCH_attr($attrib);
}

sub set_versions
{
    my $this = $_[0];
    $this->{dbm_version} = $DBD::DBM::VERSION;
    return $this->SUPER::set_versions();
}

sub init_valid_attributes
{
    my $dbh = shift;

    # define valid private attributes
    #
    # attempts to set non-valid attrs in connect() or
    # with $dbh->{attr} will throw errors
    #
    # the attrs here *must* start with dbm_ or foo_
    #
    # see the STORE methods below for how to check these attrs
    #
    $dbh->{dbm_valid_attrs} = {
                                dbm_type           => 1,    # the global DBM type e.g. SDBM_File
                                dbm_mldbm          => 1,    # the global MLDBM serializer
                                dbm_cols           => 1,    # the global column names
                                dbm_version        => 1,    # verbose DBD::DBM version
                                dbm_store_metadata => 1,    # column names, etc.
                                dbm_berkeley_flags => 1,    # for BerkeleyDB
                                dbm_valid_attrs    => 1,    # DBD::DBM::db valid attrs
                                dbm_readonly_attrs => 1,    # DBD::DBM::db r/o attrs
                                dbm_meta           => 1,    # DBD::DBM public access for f_meta
                                dbm_tables         => 1,    # DBD::DBM public access for f_meta
                              };
    $dbh->{dbm_readonly_attrs} = {
                                   dbm_version        => 1,    # verbose DBD::DBM version
                                   dbm_valid_attrs    => 1,    # DBD::DBM::db valid attrs
                                   dbm_readonly_attrs => 1,    # DBD::DBM::db r/o attrs
                                   dbm_meta           => 1,    # DBD::DBM public access for f_meta
                                 };

    $dbh->{dbm_meta} = "dbm_tables";

    return $dbh->SUPER::init_valid_attributes();
}

sub init_default_attributes
{
    my ( $dbh, $phase ) = @_;

    $dbh->SUPER::init_default_attributes($phase);
    $dbh->{f_lockfile} = '.lck';

    return $dbh;
}

sub get_dbm_versions
{
    my ( $dbh, $table ) = @_;
    $table ||= '';

    my $meta;
    my $class = $dbh->{ImplementorClass};
    $class =~ s/::db$/::Table/;
    $table and ( undef, $meta ) = $class->get_table_meta( $dbh, $table, 1 );
    $meta or ( $meta = {} and $class->bootstrap_table_meta( $dbh, $meta, $table ) );

    my $dver;
    my $dtype = $meta->{dbm_type};
    eval {
        $dver = $meta->{dbm_type}->VERSION();

        # *) when we're still alive here, everything went ok - no need to check for $@
        $dtype .= " ($dver)";
    };
    if ( $meta->{dbm_mldbm} )
    {
        $dtype .= ' + MLDBM';
        eval {
            $dver = MLDBM->VERSION();
            $dtype .= " ($dver)";    # (*)
        };
        eval {
            my $ser_class = "MLDBM::Serializer::" . $meta->{dbm_mldbm};
            my $ser_mod   = $ser_class;
            $ser_mod =~ s|::|/|g;
            $ser_mod .= ".pm";
            require $ser_mod;
            $dver = $ser_class->VERSION();
            $dtype .= ' + ' . $ser_class;    # (*)
            $dver and $dtype .= " ($dver)";  # (*)
        };
    }
    return sprintf( "%s using %s", $dbh->{dbm_version}, $dtype );
}


package DBD::DBM::st;
$DBD::DBM::st::imp_data_size = 0;
@DBD::DBM::st::ISA           = qw(DBD::File::st);

sub FETCH
{
    my ( $sth, $attr ) = @_;

    if ( $attr eq "NULLABLE" )
    {
        my @colnames = $sth->sql_get_colnames();

        # XXX only BerkeleyDB fails having NULL values for non-MLDBM databases,
        #     none accept it for key - but it requires more knowledge between
        #     queries and tables storage to return fully correct information
        $attr eq "NULLABLE" and return [ map { 0 } @colnames ];
    }

    return $sth->SUPER::FETCH($attr);
}    # FETCH

sub dbm_schema
{
    my ( $sth, $tname ) = @_;
    return $sth->set_err( $DBI::stderr, 'No table name supplied!' ) unless $tname;
    my $tbl_meta = $sth->{Database}->func( $tname, "f_schema", "get_sql_engine_meta" )
      or return $sth->set_err( $sth->{Database}->err(), $sth->{Database}->errstr() );
    return $tbl_meta->{$tname}->{f_schema};
}


package DBD::DBM::Statement;

@DBD::DBM::Statement::ISA = qw(DBD::File::Statement);

package DBD::DBM::Table;
use Carp;
use Fcntl;

@DBD::DBM::Table::ISA = qw(DBD::File::Table);

my $dirfext = $^O eq 'VMS' ? '.sdbm_dir' : '.dir';

my %reset_on_modify = (
                        dbm_type  => "dbm_tietype",
                        dbm_mldbm => "dbm_tietype",
                      );
__PACKAGE__->register_reset_on_modify( \%reset_on_modify );

my %compat_map = (
                   ( map { $_ => "dbm_$_" } qw(type mldbm store_metadata) ),
                   dbm_ext      => 'f_ext',
                   dbm_file     => 'f_file',
                   dbm_lockfile => ' f_lockfile',
                 );
__PACKAGE__->register_compat_map( \%compat_map );

sub bootstrap_table_meta
{
    my ( $self, $dbh, $meta, $table ) = @_;

    $meta->{dbm_type} ||= $dbh->{dbm_type} || 'SDBM_File';
    $meta->{dbm_mldbm} ||= $dbh->{dbm_mldbm} if ( $dbh->{dbm_mldbm} );
    $meta->{dbm_berkeley_flags} ||= $dbh->{dbm_berkeley_flags};

    defined $meta->{f_ext}
      or $meta->{f_ext} = $dbh->{f_ext};
    unless ( defined( $meta->{f_ext} ) )
    {
        my $ext;
        if ( $meta->{dbm_type} eq 'SDBM_File' or $meta->{dbm_type} eq 'ODBM_File' )
        {
            $ext = '.pag/r';
        }
        elsif ( $meta->{dbm_type} eq 'NDBM_File' )
        {
            # XXX NDBM_File on FreeBSD (and elsewhere?) may actually be Berkeley
            # behind the scenes and so create a single .db file.
            if ( $^O =~ /bsd/i or lc($^O) eq 'darwin' )
            {
                $ext = '.db/r';
            }
            elsif ( $^O eq 'SunOS' or $^O eq 'Solaris' or $^O eq 'AIX' )
            {
                $ext = '.pag/r';    # here it's implemented like dbm - just a bit improved
            }
            # else wrapped GDBM
        }
        defined($ext) and $meta->{f_ext} = $ext;
    }

    $self->SUPER::bootstrap_table_meta( $dbh, $meta, $table );
}

sub init_table_meta
{
    my ( $self, $dbh, $meta, $table ) = @_;

    $meta->{f_dontopen} = 1;

    unless ( defined( $meta->{dbm_tietype} ) )
    {
        my $tie_type = $meta->{dbm_type};
        $INC{"$tie_type.pm"} or require "$tie_type.pm";
        $tie_type eq 'BerkeleyDB' and $tie_type = 'BerkeleyDB::Hash';

        if ( $meta->{dbm_mldbm} )
        {
            $INC{"MLDBM.pm"} or require "MLDBM.pm";
            $meta->{dbm_usedb} = $tie_type;
            $tie_type = 'MLDBM';
        }

        $meta->{dbm_tietype} = $tie_type;
    }

    unless ( defined( $meta->{dbm_store_metadata} ) )
    {
        my $store = $dbh->{dbm_store_metadata};
        defined($store) or $store = 1;
        $meta->{dbm_store_metadata} = $store;
    }

    unless ( defined( $meta->{col_names} ) )
    {
        defined( $dbh->{dbm_cols} ) and $meta->{col_names} = $dbh->{dbm_cols};
    }

    $self->SUPER::init_table_meta( $dbh, $meta, $table );
}

sub open_data
{
    my ( $className, $meta, $attrs, $flags ) = @_;
    $className->SUPER::open_data( $meta, $attrs, $flags );

    unless ( $flags->{dropMode} )
    {
        # TIEING
        #
        # XXX allow users to pass in a pre-created tied object
        #
        my @tie_args;
        if ( $meta->{dbm_type} eq 'BerkeleyDB' )
        {
            my $DB_CREATE = BerkeleyDB::DB_CREATE();
            my $DB_RDONLY = BerkeleyDB::DB_RDONLY();
            my %tie_flags;
            if ( my $f = $meta->{dbm_berkeley_flags} )
            {
                defined( $f->{DB_CREATE} ) and $DB_CREATE = delete $f->{DB_CREATE};
                defined( $f->{DB_RDONLY} ) and $DB_RDONLY = delete $f->{DB_RDONLY};
                %tie_flags = %$f;
            }
            my $open_mode = $flags->{lockMode} || $flags->{createMode} ? $DB_CREATE : $DB_RDONLY;
            @tie_args = (
                          -Filename => $meta->{f_fqbn},
                          -Flags    => $open_mode,
                          %tie_flags
                        );
        }
        else
        {
            my $open_mode = O_RDONLY;
            $flags->{lockMode}   and $open_mode = O_RDWR;
            $flags->{createMode} and $open_mode = O_RDWR | O_CREAT | O_TRUNC;

            @tie_args = ( $meta->{f_fqbn}, $open_mode, 0666 );
        }

        if ( $meta->{dbm_mldbm} )
        {
            $MLDBM::UseDB      = $meta->{dbm_usedb};
            $MLDBM::Serializer = $meta->{dbm_mldbm};
        }

        $meta->{hash} = {};
        my $tie_class = $meta->{dbm_tietype};
        eval { tie %{ $meta->{hash} }, $tie_class, @tie_args };
        $@ and croak "Cannot tie(\%h $tie_class @tie_args): $@";
        -f $meta->{f_fqfn} or croak( "No such file: '" . $meta->{f_fqfn} . "'" );
    }

    unless ( $flags->{createMode} )
    {
        my ( $meta_data, $schema, $col_names );
        if ( $meta->{dbm_store_metadata} )
        {
            $meta_data = $col_names = $meta->{hash}->{"_metadata \0"};
            if ( $meta_data and $meta_data =~ m~<dbd_metadata>(.+)</dbd_metadata>~is )
            {
                $schema = $col_names = $1;
                $schema    =~ s~.*<schema>(.+)</schema>.*~$1~is;
                $col_names =~ s~.*<col_names>(.+)</col_names>.*~$1~is;
            }
        }
        $col_names ||= $meta->{col_names} || [ 'k', 'v' ];
        $col_names = [ split /,/, $col_names ] if ( ref $col_names ne 'ARRAY' );
        if ( $meta->{dbm_store_metadata} and not $meta->{hash}->{"_metadata \0"} )
        {
            $schema or $schema = '';
            $meta->{hash}->{"_metadata \0"} =
                "<dbd_metadata>"
              . "<schema>$schema</schema>"
              . "<col_names>"
              . join( ",", @{$col_names} )
              . "</col_names>"
              . "</dbd_metadata>";
        }

        $meta->{schema}    = $schema;
        $meta->{col_names} = $col_names;
    }
}

sub drop ($$)
{
    my ( $self, $data ) = @_;
    my $meta = $self->{meta};
    $meta->{hash} and untie %{ $meta->{hash} };
    $self->SUPER::drop($data);
    # XXX extra_files
    -f $meta->{f_fqbn} . $dirfext
      and $meta->{f_ext} eq '.pag/r'
      and unlink( $meta->{f_fqbn} . $dirfext );
    return 1;
}

sub fetch_row ($$)
{
    my ( $self, $data ) = @_;
    my $meta = $self->{meta};
    # fetch with %each
    #
    my @ary = each %{ $meta->{hash} };
          $meta->{dbm_store_metadata}
      and $ary[0]
      and $ary[0] eq "_metadata \0"
      and @ary = each %{ $meta->{hash} };

    my ( $key, $val ) = @ary;
    unless ($key)
    {
        delete $self->{row};
        return;
    }
    my @row = ( ref($val) eq 'ARRAY' ) ? ( $key, @$val ) : ( $key, $val );
    $self->{row} = @row ? \@row : undef;
    return wantarray ? @row : \@row;
}

sub insert_new_row ($$$)
{
    my ( $self, $data, $row_aryref ) = @_;
    my $meta   = $self->{meta};
    my $ncols  = scalar( @{ $meta->{col_names} } );
    my $nitems = scalar( @{$row_aryref} );
    $ncols == $nitems
      or croak "You tried to insert $nitems, but table is created with $ncols columns";

    my $key = shift @$row_aryref;
    my $exists;
    eval { $exists = exists( $meta->{hash}->{$key} ); };
    $exists and croak "Row with PK '$key' already exists";

    $meta->{hash}->{$key} = $meta->{dbm_mldbm} ? $row_aryref : $row_aryref->[0];

    return 1;
}

sub push_names ($$$)
{
    my ( $self, $data, $row_aryref ) = @_;
    my $meta = $self->{meta};

    # some sanity checks ...
    my $ncols = scalar(@$row_aryref);
    $ncols < 2 and croak "At least 2 columns are required for DBD::DBM tables ...";
    !$meta->{dbm_mldbm}
      and $ncols > 2
      and croak "Without serializing with MLDBM only 2 columns are supported, you give $ncols";
    $meta->{col_names} = $row_aryref;
    return unless $meta->{dbm_store_metadata};

    my $stmt      = $data->{sql_stmt};
    my $col_names = join( ',', @{$row_aryref} );
    my $schema    = $data->{Database}->{Statement};
    $schema =~ s/^[^\(]+\((.+)\)$/$1/s;
    $schema = $stmt->schema_str() if ( $stmt->can('schema_str') );
    $meta->{hash}->{"_metadata \0"} =
        "<dbd_metadata>"
      . "<schema>$schema</schema>"
      . "<col_names>$col_names</col_names>"
      . "</dbd_metadata>";
}

sub fetch_one_row ($$;$)
{
    my ( $self, $key_only, $key ) = @_;
    my $meta = $self->{meta};
    $key_only and return $meta->{col_names}->[0];
    exists $meta->{hash}->{$key} or return;
    my $val = $meta->{hash}->{$key};
    $val = ( ref($val) eq 'ARRAY' ) ? $val : [$val];
    my $row = [ $key, @$val ];
    return wantarray ? @{$row} : $row;
}

sub delete_one_row ($$$)
{
    my ( $self, $data, $aryref ) = @_;
    my $meta = $self->{meta};
    delete $meta->{hash}->{ $aryref->[0] };
}

sub update_one_row ($$$)
{
    my ( $self, $data, $aryref ) = @_;
    my $meta = $self->{meta};
    my $key  = shift @$aryref;
    defined $key or return;
    my $row = ( ref($aryref) eq 'ARRAY' ) ? $aryref : [$aryref];
    $meta->{hash}->{$key} = $meta->{dbm_mldbm} ? $row : $row->[0];
}

sub update_specific_row ($$$$)
{
    my ( $self, $data, $aryref, $origary ) = @_;
    my $meta   = $self->{meta};
    my $key    = shift @$origary;
    my $newkey = shift @$aryref;
    return unless ( defined $key );
    $key eq $newkey or delete $meta->{hash}->{$key};
    my $row = ( ref($aryref) eq 'ARRAY' ) ? $aryref : [$aryref];
    $meta->{hash}->{$newkey} = $meta->{dbm_mldbm} ? $row : $row->[0];
}

sub DESTROY ($)
{
    my $self = shift;
    my $meta = $self->{meta};
    $meta->{hash} and untie %{ $meta->{hash} };

    $self->SUPER::DESTROY();
}


sub truncate ($$)
{
    # my ( $self, $data ) = @_;
    return 1;
}

sub seek ($$$$)
{
    # my ( $self, $data, $pos, $whence ) = @_;
    return 1;
}


1;
__END__

