package DBI::ProfileDumper;
use strict;


use DBI::Profile;

our @ISA = ("DBI::Profile");

our $VERSION = "2.015325";

use Carp qw(croak);
use Fcntl qw(:flock);
use Symbol;

my $HAS_FLOCK = (defined $ENV{DBI_PROFILE_FLOCK})
    ? $ENV{DBI_PROFILE_FLOCK}
    : do { local $@; eval { flock STDOUT, 0; 1 } };

my $program_header;


sub new {
    my $pkg = shift;
    my $self = $pkg->SUPER::new(
        LockFile => $HAS_FLOCK,
        @_,
    );

    # provide a default filename
    $self->filename("dbi.prof") unless $self->filename;

    DBI->trace_msg("$self: @{[ %$self ]}\n",0)
        if $self->{Trace} && $self->{Trace} >= 2;

    return $self;
}


sub filename {
    my $self = shift;
    $self->{File} = shift if @_;
    my $filename = $self->{File};
    $filename = $filename->($self) if ref($filename) eq 'CODE';
    return $filename;
}


sub flush_to_disk {
    my $self = shift;
    my $class = ref $self;
    my $filename = $self->filename;
    my $data = $self->{Data};

    if (1) { # make an option
        if (not $data or ref $data eq 'HASH' && !%$data) {
            DBI->trace_msg("flush_to_disk skipped for empty profile\n",0) if $self->{Trace};
            return undef;
        }
    }

    my $fh = gensym;
    if (($self->{_wrote_header}||'') eq $filename) {
        # append more data to the file
        # XXX assumes that Path hasn't changed
        open($fh, ">>", $filename)
          or croak("Unable to open '$filename' for $class output: $!");
    } else {
        # create new file (or overwrite existing)
        if (-f $filename) {
            my $bak = $filename.'.prev';
            unlink($bak);
            rename($filename, $bak)
                or warn "Error renaming $filename to $bak: $!\n";
        }
        open($fh, ">", $filename)
          or croak("Unable to open '$filename' for $class output: $!");
    }
    # lock the file (before checking size and writing the header)
    flock($fh, LOCK_EX) if $self->{LockFile};
    # write header if file is empty - typically because we just opened it
    # in '>' mode, or perhaps we used '>>' but the file had been truncated externally.
    if (-s $fh == 0) {
        DBI->trace_msg("flush_to_disk wrote header to $filename\n",0) if $self->{Trace};
        $self->write_header($fh);
        $self->{_wrote_header} = $filename;
    }

    my $lines = $self->write_data($fh, $self->{Data}, 1);
    DBI->trace_msg("flush_to_disk wrote $lines lines to $filename\n",0) if $self->{Trace};

    close($fh)  # unlocks the file
        or croak("Error closing '$filename': $!");

    $self->empty();


    return $filename;
}


sub write_header {
    my ($self, $fh) = @_;

    # isolate us against globals which effect print
    local($\, $,);

    # $self->VERSION can return undef during global destruction
    my $version = $self->VERSION || $VERSION;

    # module name and version number
    print $fh ref($self)." $version\n";

    # print out Path (may contain CODE refs etc)
    my @path_words = map { escape_key($_) } @{ $self->{Path} || [] };
    print $fh "Path = [ ", join(', ', @path_words), " ]\n";

    # print out $0 and @ARGV
    if (!$program_header) {
        # XXX should really quote as well as escape
        $program_header = "Program = "
            . join(" ", map { escape_key($_) } $0, @ARGV)
            . "\n";
    }
    print $fh $program_header;

    # all done
    print $fh "\n";
}


sub write_data {
    my ($self, $fh, $data, $level) = @_;

    # XXX it's valid for $data to be an ARRAY ref, i.e., Path is empty.
    # produce an empty profile for invalid $data
    return 0 unless $data and UNIVERSAL::isa($data,'HASH');

    # isolate us against globals which affect print
    local ($\, $,);

    my $lines = 0;
    while (my ($key, $value) = each(%$data)) {
        # output a key
        print $fh "+ $level ". escape_key($key). "\n";
        if (UNIVERSAL::isa($value,'ARRAY')) {
            # output a data set for a leaf node
            print $fh "= ".join(' ', @$value)."\n";
            $lines += 1;
        } else {
            # recurse through keys - this could be rewritten to use a
            # stack for some small performance gain
            $lines += $self->write_data($fh, $value, $level + 1);
        }
    }
    return $lines;
}


sub escape_key {
    my $key = shift;
    $key =~ s!\\!\\\\!g;
    $key =~ s!\n!\\n!g;
    $key =~ s!\r!\\r!g;
    $key =~ s!\0!!g;
    return $key;
}


sub on_destroy {
    shift->flush_to_disk();
}

1;
