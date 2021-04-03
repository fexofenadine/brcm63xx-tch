package DBI::DBD::Metadata;


use Exporter ();
use Carp;

use DBI;
use DBI::Const::GetInfoType qw(%GetInfoType);

@ISA = qw(Exporter);
@EXPORT = qw(write_getinfo_pm write_typeinfo_pm);

$VERSION = "2.014214";

use strict;


sub write_getinfo_pm
{
    my ($dsn, $user, $pass, $driver) = @_ ? @_ : @ARGV;
    my $dbh = DBI->connect($dsn, $user, $pass, {RaiseError=>1});
    $driver = "<foo>" unless defined $driver;

    print <<PERL;



package DBD::${driver}::db;         # This line can be removed once transferred.

    sub get_info {
        my(\$dbh, \$info_type) = \@_;
        require DBD::${driver}::GetInfo;
        my \$v = \$DBD::${driver}::GetInfo::info{int(\$info_type)};
        \$v = \$v->(\$dbh) if ref \$v eq 'CODE';
        return \$v;
    }



package DBD::${driver}::GetInfo;

use strict;
use DBD::${driver};


my \$sql_driver = '${driver}';
my \$sql_ver_fmt = '%02d.%02d.%04d';   # ODBC version string: ##.##.#####
my \$sql_driver_ver = sprintf \$sql_ver_fmt, split (/\\./, \$DBD::${driver}::VERSION);
PERL

my $kw_map = 0;
{
    local $\ = "\n";
    local $, = "\n";
    my ($kw) = $dbh->get_info($GetInfoType{SQL_KEYWORDS});
    if ($kw)
    {
        print "\nmy \@Keywords = qw(\n";
        print sort split /,/, $kw;
        print ");\n\n";
        print "sub sql_keywords {\n";
        print q%    return join ',', @Keywords;%;
        print "\n}\n\n";
        $kw_map = 1;
    }
}

    print <<'PERL';

sub sql_data_source_name {
    my $dbh = shift;
    return "dbi:$sql_driver:" . $dbh->{Name};
}

sub sql_user_name {
    my $dbh = shift;
    # CURRENT_USER is a non-standard attribute, probably undef
    # Username is a standard DBI attribute
    return $dbh->{CURRENT_USER} || $dbh->{Username};
}

PERL

	print "\nour \%info = (\n";
    foreach my $key (sort keys %GetInfoType)
    {
        my $num = $GetInfoType{$key};
        my $val = eval { $dbh->get_info($num); };
        if ($key eq 'SQL_DATA_SOURCE_NAME') {
            $val = '\&sql_data_source_name';
        }
        elsif ($key eq 'SQL_KEYWORDS') {
            $val = ($kw_map) ? '\&sql_keywords' : 'undef';
        }
        elsif ($key eq 'SQL_DRIVER_NAME') {
            $val = "\$INC{'DBD/$driver.pm'}";
        }
        elsif ($key eq 'SQL_DRIVER_VER') {
            $val = '$sql_driver_ver';
        }
        elsif ($key eq 'SQL_USER_NAME') {
            $val = '\&sql_user_name';
        }
        elsif (not defined $val) {
            $val = 'undef';
        }
        elsif ($val eq '') {
            $val = "''";
        }
        elsif ($val =~ /\D/) {
            $val =~ s/\\/\\\\/g;
            $val =~ s/'/\\'/g;
            $val = "'$val'";
        }
        printf "%s %5d => %-30s # %s\n", (($val eq 'undef') ? '#' : ' '), $num, "$val,", $key;
    }
	print ");\n\n1;\n\n__END__\n";
}





my %dbi_inv;
my %sql_type_inv;


sub inverse_hash
{
    my (%hash) = @_;
    my (%inv);
    foreach my $key (keys %hash)
    {
        my $val = $hash{$key};
        die "Double mapping for key value $val ($inv{$val}, $key)!"
            if (defined $inv{$val});
        $inv{$val} = $key;
    }
    return %inv;
}

sub fmt_value
{
    my ($num, $val) = @_;
    if (!defined $val)
    {
        $val = "undef";
    }
    elsif ($val !~ m/^[-+]?\d+$/)
    {
        # All the numbers in type_info_all are integers!
        # Anything that isn't an integer is a string.
        # Ensure that no double quotes screw things up.
        $val =~ s/"/\\"/g if ($val =~ m/"/o);
        $val = qq{"$val"};
    }
    elsif ($dbi_inv{$num} =~ m/^(SQL_)?DATA_TYPE$/)
    {
        # All numeric...
        $val = $sql_type_inv{$val}
            if (defined $sql_type_inv{$val});
    }
    return $val;
}

sub write_typeinfo_pm
{
    my ($dsn, $user, $pass, $driver) = @_ ? @_ : @ARGV;
    my $dbh = DBI->connect($dsn, $user, $pass, {AutoCommit=>1, RaiseError=>1});
    $driver = "<foo>" unless defined $driver;

    print <<PERL;



package DBD::${driver}::db;         # This line can be removed once transferred.

    sub type_info_all
    {
        my (\$dbh) = \@_;
        require DBD::${driver}::TypeInfo;
        return [ \@\$DBD::${driver}::TypeInfo::type_info_all ];
    }



package DBD::${driver}::TypeInfo;

{
    require Exporter;
    require DynaLoader;
    \@ISA = qw(Exporter DynaLoader);
    \@EXPORT = qw(type_info_all);
    use DBI qw(:sql_types);

PERL

    # Generate SQL type name mapping hashes.
	# See code fragment in DBI specification.
    my %sql_type_map;
    foreach (@{$DBI::EXPORT_TAGS{sql_types}})
    {
        no strict 'refs';
        $sql_type_map{$_} = &{"DBI::$_"}();
        $sql_type_inv{$sql_type_map{$_}} = $_;
    }
    #-DEBUG-# print_hash("sql_type_map", %sql_type_map);
    #-DEBUG-# print_hash("sql_type_inv", %sql_type_inv);

    my %dbi_map =
        (
            TYPE_NAME          =>  0,
            DATA_TYPE          =>  1,
            COLUMN_SIZE        =>  2,
            LITERAL_PREFIX     =>  3,
            LITERAL_SUFFIX     =>  4,
            CREATE_PARAMS      =>  5,
            NULLABLE           =>  6,
            CASE_SENSITIVE     =>  7,
            SEARCHABLE         =>  8,
            UNSIGNED_ATTRIBUTE =>  9,
            FIXED_PREC_SCALE   => 10,
            AUTO_UNIQUE_VALUE  => 11,
            LOCAL_TYPE_NAME    => 12,
            MINIMUM_SCALE      => 13,
            MAXIMUM_SCALE      => 14,
            SQL_DATA_TYPE      => 15,
            SQL_DATETIME_SUB   => 16,
            NUM_PREC_RADIX     => 17,
            INTERVAL_PRECISION => 18,
        );

    #-DEBUG-# print_hash("dbi_map", %dbi_map);

    %dbi_inv = inverse_hash(%dbi_map);

    #-DEBUG-# print_hash("dbi_inv", %dbi_inv);

    my $maxlen = 0;
    foreach my $key (keys %dbi_map)
    {
        $maxlen = length($key) if length($key) > $maxlen;
    }

    # Print the name/value mapping entry in the type_info_all array;
    my $fmt = "            \%-${maxlen}s => \%2d,\n";
    my $numkey = 0;
    my $maxkey = 0;
    print "    \$type_info_all = [\n        {\n";
    foreach my $i (sort { $a <=> $b } keys %dbi_inv)
    {
        printf($fmt, $dbi_inv{$i}, $i);
        $numkey++;
        $maxkey = $i;
    }
    print "        },\n";

    print STDERR "### WARNING - Non-dense set of keys ($numkey keys, $maxkey max key)\n"
        unless $numkey = $maxkey + 1;

    my $h = $dbh->type_info_all;
    my @tia = @$h;
    my %odbc_map = map { uc $_ => $tia[0]->{$_} } keys %{$tia[0]};
    shift @tia;     # Remove the mapping reference.
    my $numtyp = $#tia;

    #-DEBUG-# print_hash("odbc_map", %odbc_map);

    # In theory, the key/number mapping sequence for %dbi_map
    # should be the same as the one from the ODBC driver.  However, to
    # prevent the possibility of mismatches, and to deal with older
    # missing attributes or unexpected new ones, we chase back through
    # the %dbi_inv and %odbc_map hashes, generating @dbi_to_odbc
    # to map our new key number to the old one.
    # Report if @dbi_to_odbc is not an identity mapping.
    my @dbi_to_odbc;
    foreach my $num (sort { $a <=> $b } keys %dbi_inv)
    {
        # Find the name in %dbi_inv that matches this index number.
        my $dbi_key = $dbi_inv{$num};
        #-DEBUG-# print "dbi_key = $dbi_key\n";
        #-DEBUG-# print "odbc_key = $odbc_map{$dbi_key}\n";
        # Find the index in %odbc_map that has this key.
        $dbi_to_odbc[$num] = (defined $odbc_map{$dbi_key}) ? $odbc_map{$dbi_key} : undef;
    }

    # Determine the length of the longest formatted value in each field
    my @len;
    for (my $i = 0; $i <= $numtyp; $i++)
    {
        my @odbc_val = @{$tia[$i]};
        for (my $num = 0; $num <= $maxkey; $num++)
        {
            # Find the value of the entry in the @odbc_val array.
            my $val = (defined $dbi_to_odbc[$num]) ? $odbc_val[$dbi_to_odbc[$num]] : undef;
            $val = fmt_value($num, $val);
            #-DEBUG-# print "val = $val\n";
            $val = "$val,";
            $len[$num] = length($val) if !defined $len[$num] || length($val) > $len[$num];
        }
    }

    # Generate format strings to left justify each string in maximum field width.
    my @fmt;
    for (my $i = 0; $i <= $maxkey; $i++)
    {
        $fmt[$i] = "%-$len[$i]s";
        #-DEBUG-# print "fmt[$i] = $fmt[$i]\n";
    }

    # Format the data from type_info_all
    for (my $i = 0; $i <= $numtyp; $i++)
    {
        my @odbc_val = @{$tia[$i]};
        print "        [ ";
        for (my $num = 0; $num <= $maxkey; $num++)
        {
            # Find the value of the entry in the @odbc_val array.
            my $val = (defined $dbi_to_odbc[$num]) ? $odbc_val[$dbi_to_odbc[$num]] : undef;
            $val = fmt_value($num, $val);
            printf $fmt[$num], "$val,";
        }
        print " ],\n";
    }

    print "    ];\n\n    1;\n}\n\n__END__\n";

}

1;

__END__

