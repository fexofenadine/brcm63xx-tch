use strict;
package CPAN::Queue::Item;

sub new {
    my($class,@attr) = @_;
    my $self = bless { @attr }, $class;
    return $self;
}

sub as_string {
    my($self) = @_;
    $self->{qmod};
}

sub reqtype {
    my($self) = @_;
    $self->{reqtype};
}

sub optional {
    my($self) = @_;
    $self->{optional};
}

package CPAN::Queue;




use vars qw{ @All $VERSION };
$VERSION = "5.5002";

sub queue_item {
    my($class,@attr) = @_;
    my $item = "$class\::Item"->new(@attr);
    $class->qpush($item);
    return 1;
}

sub qpush {
    my($class,$obj) = @_;
    push @All, $obj;
    CPAN->debug(sprintf("in new All[%s]",
                        join("",map {sprintf " %s\[%s][%s]\n",$_->{qmod},$_->{reqtype},$_->{optional}} @All),
                       )) if $CPAN::DEBUG;
}

sub first {
    my $obj = $All[0];
    $obj;
}

sub delete_first {
    my($class,$what) = @_;
    my $i;
    for my $i (0..$#All) {
        if (  $All[$i]->{qmod} eq $what ) {
            splice @All, $i, 1;
            last;
        }
    }
    CPAN->debug(sprintf("after delete_first mod[%s] All[%s]",
                        $what,
                        join("",map {sprintf " %s\[%s][%s]\n",$_->{qmod},$_->{reqtype},$_->{optional}} @All)
                       )) if $CPAN::DEBUG;
}

sub jumpqueue {
    my $class = shift;
    my @what = @_;
    CPAN->debug(sprintf("before jumpqueue All[%s] what[%s]",
                        join("",map {sprintf " %s\[%s][%s]\n",$_->{qmod},$_->{reqtype},$_->{optional}} @All),
                        join("",map {sprintf " %s\[%s][%s]\n",$_->{qmod},$_->{reqtype},$_->{optional}} @what),
                       )) if $CPAN::DEBUG;
    unless (defined $what[0]{reqtype}) {
        # apparently it was not the Shell that sent us this enquiry,
        # treat it as commandline
        $what[0]{reqtype} = "c";
    }
    my $inherit_reqtype = $what[0]{reqtype} =~ /^(c|r)$/ ? "r" : "b";
  WHAT: for my $what_tuple (@what) {
        my($qmod,$reqtype,$optional) = @$what_tuple{qw(qmod reqtype optional)};
        if ($reqtype eq "r"
            &&
            $inherit_reqtype eq "b"
           ) {
            $reqtype = "b";
        }
        my $jumped = 0;
        for (my $i=0; $i<$#All;$i++) { #prevent deep recursion
            if ($All[$i]{qmod} eq $qmod) {
                $jumped++;
            }
        }
        # high jumped values are normal for popular modules when
        # dealing with large bundles: XML::Simple,
        # namespace::autoclean, UNIVERSAL::require
        CPAN->debug("qmod[$qmod]jumped[$jumped]") if $CPAN::DEBUG;
        my $obj = "$class\::Item"->new(
                                       qmod => $qmod,
                                       reqtype => $reqtype,
                                       optional => !! $optional,
                                      );
        unshift @All, $obj;
    }
    CPAN->debug(sprintf("after jumpqueue All[%s]",
                        join("",map {sprintf " %s\[%s][%s]\n",$_->{qmod},$_->{reqtype},$_->{optional}} @All)
                       )) if $CPAN::DEBUG;
}

sub exists {
    my($self,$what) = @_;
    my @all = map { $_->{qmod} } @All;
    my $exists = grep { $_->{qmod} eq $what } @All;
    # warn "in exists what[$what] all[@all] exists[$exists]";
    $exists;
}

sub delete {
    my($self,$mod) = @_;
    @All = grep { $_->{qmod} ne $mod } @All;
    CPAN->debug(sprintf("after delete mod[%s] All[%s]",
                        $mod,
                        join("",map {sprintf " %s\[%s][%s]\n",$_->{qmod},$_->{reqtype},$_->{optional}} @All)
                       )) if $CPAN::DEBUG;
}

sub nullify_queue {
    @All = ();
}

sub size {
    return scalar @All;
}

sub reqtype_of {
    my($self,$mod) = @_;
    my $best = "";
    for my $item (grep { $_->{qmod} eq $mod } @All) {
        my $c = $item->{reqtype};
        if ($c eq "c") {
            $best = $c;
            last;
        } elsif ($c eq "r") {
            $best = $c;
        } elsif ($c eq "b") {
            if ($best eq "") {
                $best = $c;
            }
        } else {
            die "Panic: in reqtype_of: reqtype[$c] seen, should never happen";
        }
    }
    return $best;
}

1;

__END__

