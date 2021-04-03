package DBI::Profile;



use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION);
use Exporter ();
use UNIVERSAL ();
use Carp;

use DBI qw(dbi_time dbi_profile dbi_profile_merge_nodes dbi_profile_merge);

$VERSION = "2.015065";

@ISA = qw(Exporter);
@EXPORT = qw(
    DBIprofile_Statement
    DBIprofile_MethodName
    DBIprofile_MethodClass
    dbi_profile
    dbi_profile_merge_nodes
    dbi_profile_merge
    dbi_time
);
@EXPORT_OK = qw(
    format_profile_thingy
);

use constant DBIprofile_Statement	=> '!Statement';
use constant DBIprofile_MethodName	=> '!MethodName';
use constant DBIprofile_MethodClass	=> '!MethodClass';

our $ON_DESTROY_DUMP = sub { DBI->trace_msg(shift, 0) };
our $ON_FLUSH_DUMP   = sub { DBI->trace_msg(shift, 0) };

sub new {
    my $class = shift;
    my $profile = { @_ };
    return bless $profile => $class;
}


sub _auto_new {
    my $class = shift;
    my ($arg) = @_;

    # This sub is called by DBI internals when a non-hash-ref is
    # assigned to the Profile attribute. For example
    #	dbi:mysql(RaiseError=>1,Profile=>!Statement:!MethodName/DBIx::MyProfile/arg1:arg2):dbname
    # This sub works out what to do and returns a suitable hash ref.

    $arg =~ s/^DBI::/2\/DBI::/
        and carp "Automatically changed old-style DBI::Profile specification to $arg";

    # it's a path/module/k1:v1:k2:v2:... list
    my ($path, $package, $args) = split /\//, $arg, 3;
    my @args = (defined $args) ? split(/:/, $args, -1) : ();
    my @Path;

    for my $element (split /:/, $path) {
        if (DBI::looks_like_number($element)) {
            my $reverse = ($element < 0) ? ($element=-$element, 1) : 0;
            my @p;
            # a single "DBI" is special-cased in format()
            push @p, "DBI"			if $element & 0x01;
            push @p, DBIprofile_Statement	if $element & 0x02;
            push @p, DBIprofile_MethodName	if $element & 0x04;
            push @p, DBIprofile_MethodClass	if $element & 0x08;
            push @p, '!Caller2'            	if $element & 0x10;
            push @Path, ($reverse ? reverse @p : @p);
        }
        elsif ($element =~ m/^&(\w.*)/) {
            my $name = "DBI::ProfileSubs::$1"; # capture $1 early
            require DBI::ProfileSubs;
            my $code = do { no strict; *{$name}{CODE} };
            if (defined $code) {
                push @Path, $code;
            }
            else {
                warn "$name: subroutine not found\n";
                push @Path, $element;
            }
        }
        else {
            push @Path, $element;
        }
    }

    eval "require $package" if $package; # silently ignores errors
    $package ||= $class;

    return $package->new(Path => \@Path, @args);
}


sub empty {             # empty out profile data
    my $self = shift;
    DBI->trace_msg("profile data discarded\n",0) if $self->{Trace};
    $self->{Data} = undef;
}

sub filename {          # baseclass method, see DBI::ProfileDumper
    return undef;
}

sub flush_to_disk {     # baseclass method, see DBI::ProfileDumper & DashProfiler::Core
    my $self = shift;
    return unless $ON_FLUSH_DUMP;
    return unless $self->{Data};
    my $detail = $self->format();
    $ON_FLUSH_DUMP->($detail) if $detail;
}


sub as_node_path_list {
    my ($self, $node, $path) = @_;
    # convert the tree into an array of arrays
    # from
    #   {key1a}{key2a}[node1]
    #   {key1a}{key2b}[node2]
    #   {key1b}{key2a}{key3a}[node3]
    # to
    #   [ [node1], 'key1a', 'key2a' ]
    #   [ [node2], 'key1a', 'key2b' ]
    #   [ [node3], 'key1b', 'key2a', 'key3a' ]

    $node ||= $self->{Data} or return;
    $path ||= [];
    if (ref $node eq 'HASH') {    # recurse
        $path = [ @$path, undef ];
        return map {
            $path->[-1] = $_;
            ($node->{$_}) ? $self->as_node_path_list($node->{$_}, $path) : ()
        } sort keys %$node;
    }
    return [ $node, @$path ];
}


sub as_text {
    my ($self, $args_ref) = @_;
    my $separator = $args_ref->{separator} || " > ";
    my $format_path_element = $args_ref->{format_path_element}
        || "%s"; # or e.g., " key%2$d='%s'"
    my $format    = $args_ref->{format}
        || '%1$s: %11$fs / %10$d = %2$fs avg (first %12$fs, min %13$fs, max %14$fs)'."\n";

    my @node_path_list = $self->as_node_path_list(undef, $args_ref->{path});

    $args_ref->{sortsub}->(\@node_path_list) if $args_ref->{sortsub};

    my $eval = "qr/".quotemeta($separator)."/";
    my $separator_re = eval($eval) || quotemeta($separator);
    #warn "[$eval] = [$separator_re]";
    my @text;
    my @spare_slots = (undef) x 7;
    for my $node_path (@node_path_list) {
        my ($node, @path) = @$node_path;
        my $idx = 0;
        for (@path) {
            s/[\r\n]+/ /g;
            s/$separator_re/ /g;
            ++$idx;
            if ($format_path_element eq "%s") {
              $_ = sprintf $format_path_element, $_;
            } else {
              $_ = sprintf $format_path_element, $_, $idx;
            }
        }
        push @text, sprintf $format,
            join($separator, @path),                  # 1=path
            ($node->[0] ? $node->[1]/$node->[0] : 0), # 2=avg
            @spare_slots,
            @$node; # 10=count, 11=dur, 12=first_dur, 13=min, 14=max, 15=first_called, 16=last_called
    }
    return @text if wantarray;
    return join "", @text;
}


sub format {
    my $self = shift;
    my $class = ref($self) || $self;

    my $prologue = "$class: ";
    my $detail = $self->format_profile_thingy(
	$self->{Data}, 0, "    ",
	my $path = [],
	my $leaves = [],
    )."\n";

    if (@$leaves) {
	dbi_profile_merge_nodes(my $totals=[], @$leaves);
	my ($count, $time_in_dbi, undef, undef, undef, $t1, $t2) = @$totals;
	(my $progname = $0) =~ s:.*/::;
	if ($count) {
	    $prologue .= sprintf "%fs ", $time_in_dbi;
	    my $perl_time = ($DBI::PERL_ENDING) ? time() - $^T : $t2-$t1;
	    $prologue .= sprintf "%.2f%% ", $time_in_dbi/$perl_time*100 if $perl_time;
	    my @lt = localtime(time);
	    my $ts = sprintf "%d-%02d-%02d %02d:%02d:%02d",
		1900+$lt[5], $lt[4]+1, @lt[3,2,1,0];
	    $prologue .= sprintf "(%d calls) $progname \@ $ts\n", $count;
	}
	if (@$leaves == 1 && ref($self->{Data}) eq 'HASH' && $self->{Data}->{DBI}) {
	    $detail = "";	# hide the "DBI" from DBI_PROFILE=1
	}
    }
    return ($prologue, $detail) if wantarray;
    return $prologue.$detail;
}


sub format_profile_leaf {
    my ($self, $thingy, $depth, $pad, $path, $leaves) = @_;
    croak "format_profile_leaf called on non-leaf ($thingy)"
	unless UNIVERSAL::isa($thingy,'ARRAY');

    push @$leaves, $thingy if $leaves;
    my ($count, $total_time, $first_time, $min, $max, $first_called, $last_called) = @$thingy;
    return sprintf "%s%fs\n", ($pad x $depth), $total_time
	if $count <= 1;
    return sprintf "%s%fs / %d = %fs avg (first %fs, min %fs, max %fs)\n",
	($pad x $depth), $total_time, $count, $count ? $total_time/$count : 0,
	$first_time, $min, $max;
}


sub format_profile_branch {
    my ($self, $thingy, $depth, $pad, $path, $leaves) = @_;
    croak "format_profile_branch called on non-branch ($thingy)"
	unless UNIVERSAL::isa($thingy,'HASH');
    my @chunk;
    my @keys = sort keys %$thingy;
    while ( @keys ) {
	my $k = shift @keys;
	my $v = $thingy->{$k};
	push @$path, $k;
	push @chunk, sprintf "%s'%s' =>\n%s",
	    ($pad x $depth), $k,
	    $self->format_profile_thingy($v, $depth+1, $pad, $path, $leaves);
	pop @$path;
    }
    return join "", @chunk;
}


sub format_profile_thingy {
    my ($self, $thingy, $depth, $pad, $path, $leaves) = @_;
    return "undef" if not defined $thingy;
    return $self->format_profile_leaf(  $thingy, $depth, $pad, $path, $leaves)
	if UNIVERSAL::isa($thingy,'ARRAY');
    return $self->format_profile_branch($thingy, $depth, $pad, $path, $leaves)
	if UNIVERSAL::isa($thingy,'HASH');
    return "$thingy\n";
}


sub on_destroy {
    my $self = shift;
    return unless $ON_DESTROY_DUMP;
    return unless $self->{Data};
    my $detail = $self->format();
    $ON_DESTROY_DUMP->($detail) if $detail;
    $self->{Data} = undef;
}

sub DESTROY {
    my $self = shift;
    local $@;
    DBI->trace_msg("profile data DESTROY\n",0)
        if (($self->{Trace}||0) >= 2);
    eval { $self->on_destroy };
    if ($@) {
        chomp $@;
        my $class = ref($self) || $self;
        DBI->trace_msg("$class on_destroy failed: $@", 0);
    }
}

1;

