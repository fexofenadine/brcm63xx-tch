
require 5.008;

use strict;
use warnings;

use DBI ();

package DBD::File;

use strict;
use warnings;

use base qw( DBI::DBD::SqlEngine );
use Carp;
use vars qw( @ISA $VERSION $drh );

$VERSION = "0.44";

$drh = undef;		# holds driver handle(s) once initialized

sub driver ($;$)
{
    my ($class, $attr) = @_;

    # Drivers typically use a singleton object for the $drh
    # We use a hash here to have one singleton per subclass.
    # (Otherwise DBD::CSV and DBD::DBM, for example, would
    # share the same driver object which would cause problems.)
    # An alternative would be to not cache the $drh here at all
    # and require that subclasses do that. Subclasses should do
    # their own caching, so caching here just provides extra safety.
    $drh->{$class} and return $drh->{$class};

    $attr ||= {};
    {	no strict "refs";
	unless ($attr->{Attribution}) {
	    $class eq "DBD::File" and
		$attr->{Attribution} = "$class by Jeff Zucker";
	    $attr->{Attribution} ||= ${$class . "::ATTRIBUTION"} ||
		"oops the author of $class forgot to define this";
	    }
	$attr->{Version} ||= ${$class . "::VERSION"};
	$attr->{Name} or ($attr->{Name} = $class) =~ s/^DBD\:\://;
	}

    $drh->{$class} = $class->SUPER::driver ($attr);

    # XXX inject DBD::XXX::Statement unless exists

    return $drh->{$class};
    } # driver

sub CLONE
{
    undef $drh;
    } # CLONE


package DBD::File::dr;

use strict;
use warnings;

use vars qw( @ISA $imp_data_size );

use Carp;

@DBD::File::dr::ISA           = qw( DBI::DBD::SqlEngine::dr );
$DBD::File::dr::imp_data_size = 0;

sub dsn_quote
{
    my $str = shift;
    ref     $str and return "";
    defined $str or  return "";
    $str =~ s/([;:\\])/\\$1/g;
    return $str;
    } # dsn_quote

sub default_table_source { "DBD::File::TableSource::FileSystem" }

sub connect
{
    my ($drh, $dbname, $user, $auth, $attr) = @_;

    # We do not (yet) care about conflicting attributes here
    # my $dbh = DBI->connect ("dbi:CSV:f_dir=test", undef, undef, { f_dir => "text" });
    # will test here that both test and text should exist
    if (my $attr_hash = (DBI->parse_dsn ($dbname))[3]) {
	if (defined $attr_hash->{f_dir} && ! -d $attr_hash->{f_dir}) {
	    my $msg = "No such directory '$attr_hash->{f_dir}";
	    $drh->set_err (2, $msg);
	    $attr_hash->{RaiseError} and croak $msg;
	    return;
	    }
	}
    if ($attr and defined $attr->{f_dir} && ! -d $attr->{f_dir}) {
	my $msg = "No such directory '$attr->{f_dir}";
	$drh->set_err (2, $msg);
	$attr->{RaiseError} and croak $msg;
	return;
	}

    return $drh->SUPER::connect ($dbname, $user, $auth, $attr);
    } # connect

sub disconnect_all
{
    } # disconnect_all

sub DESTROY
{
    undef;
    } # DESTROY


package DBD::File::db;

use strict;
use warnings;

use vars qw( @ISA $imp_data_size );

use Carp;
require File::Spec;
require Cwd;
use Scalar::Util qw( refaddr ); # in CORE since 5.7.3

@DBD::File::db::ISA           = qw( DBI::DBD::SqlEngine::db );
$DBD::File::db::imp_data_size = 0;

sub data_sources
{
    my ($dbh, $attr, @other) = @_;
    ref ($attr) eq "HASH" or $attr = {};
    exists $attr->{f_dir}        or $attr->{f_dir}        = $dbh->{f_dir};
    exists $attr->{f_dir_search} or $attr->{f_dir_search} = $dbh->{f_dir_search};
    return $dbh->SUPER::data_sources ($attr, @other);
    } # data_source

sub set_versions
{
    my $dbh = shift;
    $dbh->{f_version} = $DBD::File::VERSION;

    return $dbh->SUPER::set_versions ();
    } # set_versions

sub init_valid_attributes
{
    my $dbh = shift;

    $dbh->{f_valid_attrs} = {
	f_version        => 1, # DBD::File version
	f_dir            => 1, # base directory
	f_dir_search     => 1, # extended search directories
	f_ext            => 1, # file extension
	f_schema         => 1, # schema name
	f_lock           => 1, # Table locking mode
	f_lockfile       => 1, # Table lockfile extension
	f_encoding       => 1, # Encoding of the file
	f_valid_attrs    => 1, # File valid attributes
	f_readonly_attrs => 1, # File readonly attributes
	};
    $dbh->{f_readonly_attrs} = {
	f_version        => 1, # DBD::File version
	f_valid_attrs    => 1, # File valid attributes
	f_readonly_attrs => 1, # File readonly attributes
	};

    return $dbh->SUPER::init_valid_attributes ();
    } # init_valid_attributes

sub init_default_attributes
{
    my ($dbh, $phase) = @_;

    # must be done first, because setting flags implicitly calls $dbdname::db->STORE
    $dbh->SUPER::init_default_attributes ($phase);

    # DBI::BD::SqlEngine::dr::connect will detect old-style drivers and
    # don't call twice
    unless (defined $phase) {
        # we have an "old" driver here
        $phase = defined $dbh->{sql_init_phase};
	$phase and $phase = $dbh->{sql_init_phase};
	}

    if (0 == $phase) {
	# f_ext should not be initialized
	# f_map is deprecated (but might return)
	$dbh->{f_dir} = Cwd::abs_path (File::Spec->curdir ());

	push @{$dbh->{sql_init_order}{90}}, "f_meta";

	# complete derived attributes, if required
	(my $drv_class = $dbh->{ImplementorClass}) =~ s/::db$//;
	my $drv_prefix = DBI->driver_prefix ($drv_class);
        if (exists $dbh->{$drv_prefix . "meta"} and !$dbh->{sql_engine_in_gofer}) {
            my $attr = $dbh->{$drv_prefix . "meta"};
            defined $dbh->{f_valid_attrs}{f_meta}
		and $dbh->{f_valid_attrs}{f_meta} = 1;

            $dbh->{f_meta} = $dbh->{$attr};
	    }
	}

    return $dbh;
    } # init_default_attributes

sub validate_FETCH_attr
{
    my ($dbh, $attrib) = @_;

    $attrib eq "f_meta" and $dbh->{sql_engine_in_gofer} and $attrib = "sql_meta";

    return $dbh->SUPER::validate_FETCH_attr ($attrib);
    } # validate_FETCH_attr

sub validate_STORE_attr
{
    my ($dbh, $attrib, $value) = @_;

    if ($attrib eq "f_dir" && defined $value) {
	-d $value or
	    return $dbh->set_err ($DBI::stderr, "No such directory '$value'");
	File::Spec->file_name_is_absolute ($value) or
	    $value = Cwd::abs_path ($value);
	}

    if ($attrib eq "f_ext") {
	$value eq "" || $value =~ m{^\.\w+(?:/[rR]*)?$} or
	    carp "'$value' doesn't look like a valid file extension attribute\n";
	}

    $attrib eq "f_meta" and $dbh->{sql_engine_in_gofer} and $attrib = "sql_meta";

    return $dbh->SUPER::validate_STORE_attr ($attrib, $value);
    } # validate_STORE_attr

sub get_f_versions
{
    my ($dbh, $table) = @_;

    my $class = $dbh->{ImplementorClass};
    $class =~ s/::db$/::Table/;
    my $dver;
    my $dtype = "IO::File";
    eval {
	$dver = IO::File->VERSION ();

	# when we're still alive here, everything went ok - no need to check for $@
	$dtype .= " ($dver)";
	};

    my $f_encoding;
    if ($table) {
	my $meta;
	$table and (undef, $meta) = $class->get_table_meta ($dbh, $table, 1);
	$meta and $meta->{f_encoding} and $f_encoding = $meta->{f_encoding};
	} # if ($table)
    $f_encoding ||= $dbh->{f_encoding};

    $f_encoding and $dtype .= " + " . $f_encoding . " encoding";

    return sprintf "%s using %s", $dbh->{f_version}, $dtype;
    } # get_f_versions


package DBD::File::st;

use strict;
use warnings;

use vars qw( @ISA $imp_data_size );

@DBD::File::st::ISA           = qw( DBI::DBD::SqlEngine::st );
$DBD::File::st::imp_data_size = 0;

my %supported_attrs = (
    TYPE      => 1,
    PRECISION => 1,
    NULLABLE  => 1,
    );

sub FETCH
{
    my ($sth, $attr) = @_;

    if ($supported_attrs{$attr}) {
	my $stmt = $sth->{sql_stmt};

	if (exists $sth->{ImplementorClass} &&
	    exists $sth->{sql_stmt} &&
	    $sth->{sql_stmt}->isa ("SQL::Statement")) {

	    # fill overall_defs unless we know
	    unless (exists $sth->{f_overall_defs} && ref $sth->{f_overall_defs}) {
		my $types = $sth->{Database}{Types};
		unless ($types) { # Fetch types only once per database
		    if (my $t = $sth->{Database}->type_info_all ()) {
			foreach my $i (1 .. $#$t) {
			    $types->{uc $t->[$i][0]}   = $t->[$i][1];
			    $types->{$t->[$i][1]} ||= uc $t->[$i][0];
			    }
			}
		    # sane defaults
		    for ([  0, ""		],
			 [  1, "CHAR"		],
			 [  4, "INTEGER"	],
			 [ 12, "VARCHAR"	],
			 ) {
			$types->{$_->[0]} ||= $_->[1];
			$types->{$_->[1]} ||= $_->[0];
			}
		    $sth->{Database}{Types} = $types;
		    }
		my $all_meta =
		    $sth->{Database}->func ("*", "table_defs", "get_sql_engine_meta");
		foreach my $tbl (keys %$all_meta) {
		    my $meta = $all_meta->{$tbl};
		    exists $meta->{table_defs} && ref $meta->{table_defs} or next;
		    foreach (keys %{$meta->{table_defs}{columns}}) {
			my $field_info = $meta->{table_defs}{columns}{$_};
			if (defined $field_info->{data_type} &&
				    $field_info->{data_type} !~ m/^[0-9]+$/) {
			    $field_info->{type_name} = uc $field_info->{data_type};
			    $field_info->{data_type} = $types->{$field_info->{type_name}} || 0;
			    }
			$field_info->{type_name} ||= $types->{$field_info->{data_type}} || "CHAR";
			$sth->{f_overall_defs}{$_} = $field_info;
			}
		    }
		}

	    my @colnames = $sth->sql_get_colnames ();

	    $attr eq "TYPE"      and
		return [ map { $sth->{f_overall_defs}{$_}{data_type}   || 12 }
			    @colnames ];

	    $attr eq "TYPE_NAME" and
		return [ map { $sth->{f_overall_defs}{$_}{type_name}   || "VARCHAR" }
			    @colnames ];

	    $attr eq "PRECISION" and
		return [ map { $sth->{f_overall_defs}{$_}{data_length} || 0 }
			    @colnames ];

	    $attr eq "NULLABLE"  and
		return [ map { ( grep { $_ eq "NOT NULL" }
			    @{ $sth->{f_overall_defs}{$_}{constraints} || [] })
			       ? 0 : 1 }
			    @colnames ];
	    }
	}

    return $sth->SUPER::FETCH ($attr);
    } # FETCH


package DBD::File::TableSource::FileSystem;

use strict;
use warnings;

use IO::Dir;

@DBD::File::TableSource::FileSystem::ISA = "DBI::DBD::SqlEngine::TableSource";

sub data_sources
{
    my ($class, $drh, $attr) = @_;
    my $dir = $attr && exists $attr->{f_dir}
	? $attr->{f_dir}
	: File::Spec->curdir ();
    defined $dir or return; # Stream-based databases do not have f_dir
    unless (-d $dir && -r $dir && -x $dir) {
	$drh->set_err ($DBI::stderr, "Cannot use directory $dir from f_dir");
	return;
	}
    my %attrs;
    $attr and %attrs = %$attr;
    delete $attrs{f_dir};
    my $dsn_quote = $drh->{ImplementorClass}->can ("dsn_quote");
    my $dsnextra = join ";", map { $_ . "=" . &{$dsn_quote} ($attrs{$_}) } keys %attrs;
    my @dir = ($dir);
    $attr->{f_dir_search} && ref $attr->{f_dir_search} eq "ARRAY" and
	push @dir, grep { -d $_ } @{$attr->{f_dir_search}};
    my @dsns;
    foreach $dir (@dir) {
	my $dirh = IO::Dir->new ($dir);
	unless (defined $dirh) {
	    $drh->set_err ($DBI::stderr, "Cannot open directory $dir: $!");
	    return;
	    }

	my ($file, %names, $driver);
	$driver = $drh->{ImplementorClass} =~ m/^dbd\:\:([^\:]+)\:\:/i ? $1 : "File";

	while (defined ($file = $dirh->read ())) {
	    my $d = File::Spec->catdir ($dir, $file);
	    # allow current dir ... it can be a data_source too
	    $file ne File::Spec->updir () && -d $d and
		push @dsns, "DBI:$driver:f_dir=" . &{$dsn_quote} ($d) . ($dsnextra ? ";$dsnextra" : "");
	    }
	}
    return @dsns;
    } # data_sources

sub avail_tables
{
    my ($self, $dbh) = @_;

    my $dir = $dbh->{f_dir};
    defined $dir or return;	# Stream based db's cannot be queried for tables

    my %seen;
    my @tables;
    my @dir = ($dir);
    $dbh->{f_dir_search} && ref $dbh->{f_dir_search} eq "ARRAY" and
	push @dir, grep { -d $_ } @{$dbh->{f_dir_search}};
    foreach $dir (@dir) {
	my $dirh = IO::Dir->new ($dir);

	unless (defined $dirh) {
	    $dbh->set_err ($DBI::stderr, "Cannot open directory $dir: $!");
	    return;
	    }

	my $class = $dbh->FETCH ("ImplementorClass");
	$class =~ s/::db$/::Table/;
	my ($file, %names);
	my $schema = exists $dbh->{f_schema}
	    ? defined $dbh->{f_schema} && $dbh->{f_schema} ne ""
		? $dbh->{f_schema} : undef
	    : eval { getpwuid ((stat $dir)[4]) }; # XXX Win32::pwent
	while (defined ($file = $dirh->read ())) {
	    my ($tbl, $meta) = $class->get_table_meta ($dbh, $file, 0, 0) or next; # XXX
	    # $tbl && $meta && -f $meta->{f_fqfn} or next;
	    $seen{defined $schema ? $schema : "\0"}{$dir}{$tbl}++ or
		push @tables, [ undef, $schema, $tbl, "TABLE", "FILE" ];
	    }
	$dirh->close () or
	    $dbh->set_err ($DBI::stderr, "Cannot close directory $dir: $!");
	}

    return @tables;
    } # avail_tables


package DBD::File::DataSource::Stream;

use strict;
use warnings;

use Carp;

@DBD::File::DataSource::Stream::ISA = "DBI::DBD::SqlEngine::DataSource";

my $locking = eval {
    my $fh;
    my $nulldevice = File::Spec->devnull ();
    open $fh, ">", $nulldevice or croak "Can't open $nulldevice: $!";
    flock $fh, 0;
    close $fh;
    1;
    };

sub complete_table_name
{
    my ($self, $meta, $file, $respect_case) = @_;

    my $tbl = $file;
    if (!$respect_case and $meta->{sql_identifier_case} == 1) { # XXX SQL_IC_UPPER
        $tbl = uc $tbl;
	}
    elsif (!$respect_case and $meta->{sql_identifier_case} == 2) { # XXX SQL_IC_LOWER
        $tbl = lc $tbl;
	}

    $meta->{f_fqfn} = undef;
    $meta->{f_fqbn} = undef;
    $meta->{f_fqln} = undef;

    $meta->{table_name} = $tbl;

    return $tbl;
    } # complete_table_name

sub apply_encoding
{
    my ($self, $meta, $fn) = @_;
    defined $fn or $fn = "file handle " . fileno ($meta->{fh});
    if (my $enc = $meta->{f_encoding}) {
	binmode $meta->{fh}, ":encoding($enc)" or
	    croak "Failed to set encoding layer '$enc' on $fn: $!";
	}
    else {
	binmode $meta->{fh} or croak "Failed to set binary mode on $fn: $!";
	}
    } # apply_encoding

sub open_data
{
    my ($self, $meta, $attrs, $flags) = @_;

    $flags->{dropMode} and croak "Can't drop a table in stream";
    my $fn = "file handle " . fileno ($meta->{f_file});

    if ($flags->{createMode} || $flags->{lockMode}) {
	$meta->{fh} = IO::Handle->new_from_fd (fileno ($meta->{f_file}), "w+") or
	    croak "Cannot open $fn for writing: $! (" . ($!+0) . ")";
	}
    else {
	$meta->{fh} = IO::Handle->new_from_fd (fileno ($meta->{f_file}), "r") or
	    croak "Cannot open $fn for reading: $! (" . ($!+0) . ")";
	}

    if ($meta->{fh}) {
	$self->apply_encoding ($meta, $fn);
	} # have $meta->{$fh}

    if ($self->can_flock && $meta->{fh}) {
	my $lm = defined $flags->{f_lock}
		      && $flags->{f_lock} =~ m/^[012]$/
		       ? $flags->{f_lock}
		       : $flags->{lockMode} ? 2 : 1;
	if ($lm == 2) {
	    flock $meta->{fh}, 2 or croak "Cannot obtain exclusive lock on $fn: $!";
	    }
	elsif ($lm == 1) {
	    flock $meta->{fh}, 1 or croak "Cannot obtain shared lock on $fn: $!";
	    }
	# $lm = 0 is forced no locking at all
	}
    } # open_data

sub can_flock { $locking }

package DBD::File::DataSource::File;

use strict;
use warnings;

@DBD::File::DataSource::File::ISA = "DBD::File::DataSource::Stream";

use Carp;

my $fn_any_ext_regex = qr/\.[^.]*/;

sub complete_table_name
{
    my ($self, $meta, $file, $respect_case, $file_is_table) = @_;

    $file eq "." || $file eq ".."	and return; # XXX would break a possible DBD::Dir

    # XXX now called without proving f_fqfn first ...
    my ($ext, $req) = ("", 0);
    if ($meta->{f_ext}) {
	($ext, my $opt) = split m{/}, $meta->{f_ext};
	if ($ext && $opt) {
	    $opt =~ m/r/i and $req = 1;
	    }
	}

    # (my $tbl = $file) =~ s/$ext$//i;
    my ($tbl, $basename, $dir, $fn_ext, $user_spec_file, $searchdir);
    if ($file_is_table and defined $meta->{f_file}) {
	$tbl = $file;
	($basename, $dir, $fn_ext) = File::Basename::fileparse ($meta->{f_file}, $fn_any_ext_regex);
	$file = $basename . $fn_ext;
	$user_spec_file = 1;
	}
    else {
	($basename, $dir, undef) = File::Basename::fileparse ($file, $ext);
	# $dir is returned with trailing (back)slash. We just need to check
	# if it is ".", "./", or ".\" or "[]" (VMS)
	if ($dir =~ m{^(?:[.][/\\]?|\[\])$} && ref $meta->{f_dir_search} eq "ARRAY") {
	    foreach my $d ($meta->{f_dir}, @{$meta->{f_dir_search}}) {
		my $f = File::Spec->catdir ($d, $file);
		-f $f or next;
		$searchdir = Cwd::abs_path ($d);
		$dir = "";
		last;
		}
	    }
	$file = $tbl = $basename;
	$user_spec_file = 0;
	}

    if (!$respect_case and $meta->{sql_identifier_case} == 1) { # XXX SQL_IC_UPPER
        $basename = uc $basename;
        $tbl = uc $tbl;
	}
    elsif (!$respect_case and $meta->{sql_identifier_case} == 2) { # XXX SQL_IC_LOWER
        $basename = lc $basename;
        $tbl = lc $tbl;
	}

    unless (defined $searchdir) {
	$searchdir = File::Spec->file_name_is_absolute ($dir)
	    ? ($dir =~ s{/$}{}, $dir)
	    : Cwd::abs_path (File::Spec->catdir ($meta->{f_dir}, $dir));
	}
    -d $searchdir or
	croak "-d $searchdir: $!";

    $searchdir eq $meta->{f_dir} and
	$dir = "";

    unless ($user_spec_file) {
	$file_is_table and $file = "$basename$ext";

	# Fully Qualified File Name
	my $cmpsub;
	if ($respect_case) {
	    $cmpsub = sub {
		my ($fn, undef, $sfx) = File::Basename::fileparse ($_, $fn_any_ext_regex);
		$^O eq "VMS" && $sfx eq "." and
		    $sfx = ""; # no extension turns up as a dot
		$fn eq $basename and
		    return (lc $sfx eq lc $ext or !$req && !$sfx);
		return 0;
		}
	    }
	else {
	    $cmpsub = sub {
		my ($fn, undef, $sfx) = File::Basename::fileparse ($_, $fn_any_ext_regex);
		$^O eq "VMS" && $sfx eq "." and
		    $sfx = "";  # no extension turns up as a dot
		lc $fn eq lc $basename and
		    return (lc $sfx eq lc $ext or !$req && !$sfx);
		return 0;
		}
	    }

	my @f;
	{   my $dh = IO::Dir->new ($searchdir) or croak "Can't open '$searchdir': $!";
	    @f = sort { length $b <=> length $a }
		 grep { &$cmpsub ($_) }
		 $dh->read ();
	    $dh->close () or croak "Can't close '$searchdir': $!";
	    }
	@f > 0 && @f <= 2 and $file = $f[0];
	!$respect_case && $meta->{sql_identifier_case} == 4 and # XXX SQL_IC_MIXED
	    ($tbl = $file) =~ s/$ext$//i;

	my $tmpfn = $file;
	if ($ext && $req) {
            # File extension required
            $tmpfn =~ s/$ext$//i or return;
            }
	}

    my $fqfn = File::Spec->catfile ($searchdir, $file);
    my $fqbn = File::Spec->catfile ($searchdir, $basename);

    $meta->{f_fqfn} = $fqfn;
    $meta->{f_fqbn} = $fqbn;
    defined $meta->{f_lockfile} && $meta->{f_lockfile} and
	$meta->{f_fqln} = $meta->{f_fqbn} . $meta->{f_lockfile};

    $dir && !$user_spec_file  and $tbl = File::Spec->catfile ($dir, $tbl);
    $meta->{table_name} = $tbl;

    return $tbl;
    } # complete_table_name

sub open_data
{
    my ($self, $meta, $attrs, $flags) = @_;

    defined $meta->{f_fqfn} && $meta->{f_fqfn} ne "" or croak "No filename given";

    my ($fh, $fn);
    unless ($meta->{f_dontopen}) {
	$fn = $meta->{f_fqfn};
	if ($flags->{createMode}) {
	    -f $meta->{f_fqfn} and
		croak "Cannot create table $attrs->{table}: Already exists";
	    $fh = IO::File->new ($fn, "a+") or
		croak "Cannot open $fn for writing: $! (" . ($!+0) . ")";
	    }
	else {
	    unless ($fh = IO::File->new ($fn, ($flags->{lockMode} ? "r+" : "r"))) {
		croak "Cannot open $fn: $! (" . ($!+0) . ")";
		}
	    }

	$meta->{fh} = $fh;

	if ($fh) {
	    $fh->seek (0, 0) or
		croak "Error while seeking back: $!";

	    $self->apply_encoding ($meta);
	    }
	}
    if ($meta->{f_fqln}) {
	$fn = $meta->{f_fqln};
	if ($flags->{createMode}) {
	    -f $fn and
		croak "Cannot create table lock at '$fn' for $attrs->{table}: Already exists";
	    $fh = IO::File->new ($fn, "a+") or
		croak "Cannot open $fn for writing: $! (" . ($!+0) . ")";
	    }
	else {
	    unless ($fh = IO::File->new ($fn, ($flags->{lockMode} ? "r+" : "r"))) {
		croak "Cannot open $fn: $! (" . ($!+0) . ")";
		}
	    }

	$meta->{lockfh} = $fh;
	}

    if ($self->can_flock && $fh) {
	my $lm = defined $flags->{f_lock}
		      && $flags->{f_lock} =~ m/^[012]$/
		       ? $flags->{f_lock}
		       : $flags->{lockMode} ? 2 : 1;
	if ($lm == 2) {
	    flock $fh, 2 or croak "Cannot obtain exclusive lock on $fn: $!";
	    }
	elsif ($lm == 1) {
	    flock $fh, 1 or croak "Cannot obtain shared lock on $fn: $!";
	    }
	# $lm = 0 is forced no locking at all
	}
    } # open_data


package DBD::File::Statement;

use strict;
use warnings;

@DBD::File::Statement::ISA = qw( DBI::DBD::SqlEngine::Statement );


package DBD::File::Table;

use strict;
use warnings;

use Carp;
require IO::File;
require File::Basename;
require File::Spec;
require Cwd;
require Scalar::Util;

@DBD::File::Table::ISA = qw( DBI::DBD::SqlEngine::Table );


if (eval { require Params::Util; }) {
    Params::Util->import ("_HANDLE");
    }
else {
    # taken but modified from Params::Util ...
    *_HANDLE = sub {
	# It has to be defined, of course
	defined $_[0] or return;

	# Normal globs are considered to be file handles
	ref $_[0] eq "GLOB" and return $_[0];

	# Check for a normal tied filehandle
	# Side Note: 5.5.4's tied () and can () doesn't like getting undef
	tied ($_[0]) and tied ($_[0])->can ("TIEHANDLE") and return $_[0];

	# There are no other non-object handles that we support
	Scalar::Util::blessed ($_[0]) or return;

	# Check for a common base classes for conventional IO::Handle object
	$_[0]->isa ("IO::Handle")  and return $_[0];

	# Check for tied file handles using Tie::Handle
	$_[0]->isa ("Tie::Handle") and return $_[0];

	# IO::Scalar is not a proper seekable, but it is valid is a
	# regular file handle
	$_[0]->isa ("IO::Scalar")  and return $_[0];

	# Yet another special case for IO::String, which refuses (for now
	# anyway) to become a subclass of IO::Handle.
	$_[0]->isa ("IO::String")  and return $_[0];

	# This is not any sort of object we know about
	return;
	};
    }


sub file2table
{
    my ($self, $meta, $file, $file_is_table, $respect_case) = @_;

    return $meta->{sql_data_source}->complete_table_name ($meta, $file, $respect_case, $file_is_table);
    } # file2table

sub bootstrap_table_meta
{
    my ($self, $dbh, $meta, $table, @other) = @_;

    $self->SUPER::bootstrap_table_meta ($dbh, $meta, $table, @other);

    exists  $meta->{f_dir}        or $meta->{f_dir}        = $dbh->{f_dir};
    exists  $meta->{f_dir_search} or $meta->{f_dir_search} = $dbh->{f_dir_search};
    defined $meta->{f_ext}        or $meta->{f_ext}        = $dbh->{f_ext};
    defined $meta->{f_encoding}   or $meta->{f_encoding}   = $dbh->{f_encoding};
    exists  $meta->{f_lock}       or $meta->{f_lock}       = $dbh->{f_lock};
    exists  $meta->{f_lockfile}   or $meta->{f_lockfile}   = $dbh->{f_lockfile};
    defined $meta->{f_schema}     or $meta->{f_schema}     = $dbh->{f_schema};

    defined $meta->{f_open_file_needed} or
	$meta->{f_open_file_needed} = $self->can ("open_file") != DBD::File::Table->can ("open_file");

    defined ($meta->{sql_data_source}) or
	$meta->{sql_data_source} = _HANDLE ($meta->{f_file})
	                         ? "DBD::File::DataSource::Stream"
				 : "DBD::File::DataSource::File";
    } # bootstrap_table_meta

sub get_table_meta ($$$$;$)
{
    my ($self, $dbh, $table, $file_is_table, $respect_case) = @_;

    my $meta = $self->SUPER::get_table_meta ($dbh, $table, $respect_case, $file_is_table);
    $table = $meta->{table_name};
    return unless $table;

    return ($table, $meta);
    } # get_table_meta

my %reset_on_modify = (
    f_file       => [ "f_fqfn", "sql_data_source" ],
    f_dir        =>   "f_fqfn",
    f_dir_search => [],
    f_ext        =>   "f_fqfn",
    f_lockfile   =>   "f_fqfn", # forces new file2table call
    );

__PACKAGE__->register_reset_on_modify (\%reset_on_modify);

my %compat_map = map { $_ => "f_$_" } qw( file ext lock lockfile );

__PACKAGE__->register_compat_map (\%compat_map);


sub open_file
{
    my ($className, $meta, $attrs, $flags) = @_;

    return $className->SUPER::open_data ($meta, $attrs, $flags);
    } # open_file

sub open_data
{
    my ($className, $meta, $attrs, $flags) = @_;

    # compat to 0.38 .. 0.40 API
    $meta->{f_open_file_needed}
	? $className->open_file ($meta, $attrs, $flags)
	: $className->SUPER::open_data ($meta, $attrs, $flags);

    return;
    } # open_data


sub drop ($)
{
    my ($self, $data) = @_;
    my $meta = $self->{meta};
    # We have to close the file before unlinking it: Some OS'es will
    # refuse the unlink otherwise.
    $meta->{fh} and $meta->{fh}->close ();
    $meta->{lockfh} and $meta->{lockfh}->close ();
    undef $meta->{fh};
    undef $meta->{lockfh};
    $meta->{f_fqfn} and unlink $meta->{f_fqfn}; # XXX ==> sql_data_source
    $meta->{f_fqln} and unlink $meta->{f_fqln}; # XXX ==> sql_data_source
    delete $data->{Database}{sql_meta}{$self->{table}};
    return 1;
    } # drop

sub seek ($$$$)
{
    my ($self, $data, $pos, $whence) = @_;
    my $meta = $self->{meta};
    if ($whence == 0 && $pos == 0) {
	$pos = defined $meta->{first_row_pos} ? $meta->{first_row_pos} : 0;
	}
    elsif ($whence != 2 || $pos != 0) {
	croak "Illegal seek position: pos = $pos, whence = $whence";
	}

    $meta->{fh}->seek ($pos, $whence) or
	croak "Error while seeking in " . $meta->{f_fqfn} . ": $!";
    } # seek

sub truncate ($$)
{
    my ($self, $data) = @_;
    my $meta = $self->{meta};
    $meta->{fh}->truncate ($meta->{fh}->tell ()) or
	croak "Error while truncating " . $meta->{f_fqfn} . ": $!";
    return 1;
    } # truncate

sub DESTROY
{
    my $self = shift;
    my $meta = $self->{meta};
    $meta->{fh} and $meta->{fh}->close ();
    $meta->{lockfh} and $meta->{lockfh}->close ();
    undef $meta->{fh};
    undef $meta->{lockfh};
    } # DESTROY

1;

__END__

