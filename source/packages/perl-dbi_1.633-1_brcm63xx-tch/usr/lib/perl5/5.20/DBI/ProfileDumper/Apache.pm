package DBI::ProfileDumper::Apache;

use strict;


our $VERSION = "2.014121";

our @ISA = qw(DBI::ProfileDumper);

use DBI::ProfileDumper;
use File::Spec;

my $initial_pid = $$;

use constant MP2 => ($ENV{MOD_PERL_API_VERSION} and $ENV{MOD_PERL_API_VERSION} == 2) ? 1 : 0;

my $server_root_dir;

if (MP2) {
    require Apache2::ServerUtil;
    $server_root_dir = Apache2::ServerUtil::server_root();
}
else {
    require Apache;
    $server_root_dir = eval { Apache->server_root_relative('') } || "/tmp";
}


sub _dirname {
    my $self = shift;
    return $self->{Dir} ||= $ENV{DBI_PROFILE_APACHE_LOG_DIR}
                        || File::Spec->catdir($server_root_dir, "logs");
}


sub filename {
    my $self = shift;
    my $filename = $self->SUPER::filename(@_);
    return $filename if not $filename; # not set yet

    # to be able to identify groups of profile files from the same set of
    # apache processes, we include the parent pid in the file name
    # as well as the pid.
    my $group_pid = ($$ eq $initial_pid) ? $$ : getppid();
    $filename .= ".$group_pid.$$";

    return $filename if File::Spec->file_name_is_absolute($filename);
    return File::Spec->catfile($self->_dirname, $filename);
}


sub flush_to_disk {
    my $self = shift;

    my $filename = $self->SUPER::flush_to_disk(@_);

    print STDERR ref($self)." pid$$ written to $filename\n"
        if $filename && not $self->{Quiet};

    return $filename;
}

1;
