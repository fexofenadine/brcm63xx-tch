package B;
use strict;

require Exporter;
@B::ISA = qw(Exporter);


BEGIN {
    $B::VERSION = '1.48';
    @B::EXPORT_OK = ();

    # Our BOOT code needs $VERSION set, and will append to @EXPORT_OK.
    # Want our constants loaded before the compiler meets OPf_KIDS below, as
    # the combination of having the constant stay a Proxy Constant Subroutine
    # and its value being inlined saves a little over .5K

    require XSLoader;
    XSLoader::load();
}

push @B::EXPORT_OK, (qw(minus_c ppname save_BEGINs
			class peekop cast_I32 cstring cchar hash threadsv_names
			main_root main_start main_cv svref_2object opnumber
			sub_generation amagic_generation perlstring
			walkoptree_slow walkoptree walkoptree_exec walksymtable
			parents comppadlist sv_undef compile_stats timing_info
			begin_av init_av check_av end_av regex_padav dowarn
			defstash curstash warnhook diehook inc_gv @optype
			@specialsv_name unitcheck_av));

@B::SV::ISA = 'B::OBJECT';
@B::NULL::ISA = 'B::SV';
@B::PV::ISA = 'B::SV';
@B::IV::ISA = 'B::SV';
@B::NV::ISA = 'B::SV';
@B::RV::ISA = $] >= 5.011 ? 'B::IV' : 'B::SV';
@B::PVIV::ISA = qw(B::PV B::IV);
@B::PVNV::ISA = qw(B::PVIV B::NV);
@B::PVMG::ISA = 'B::PVNV';
@B::REGEXP::ISA = 'B::PVMG' if $] >= 5.011;
@B::INVLIST::ISA = 'B::PV'  if $] >= 5.019;
@B::PVLV::ISA = 'B::GV';
@B::BM::ISA = 'B::GV';
@B::AV::ISA = 'B::PVMG';
@B::GV::ISA = 'B::PVMG';
@B::HV::ISA = 'B::PVMG';
@B::CV::ISA = 'B::PVMG';
@B::IO::ISA = 'B::PVMG';
@B::FM::ISA = 'B::CV';

@B::OP::ISA = 'B::OBJECT';
@B::UNOP::ISA = 'B::OP';
@B::BINOP::ISA = 'B::UNOP';
@B::LOGOP::ISA = 'B::UNOP';
@B::LISTOP::ISA = 'B::BINOP';
@B::SVOP::ISA = 'B::OP';
@B::PADOP::ISA = 'B::OP';
@B::PVOP::ISA = 'B::OP';
@B::LOOP::ISA = 'B::LISTOP';
@B::PMOP::ISA = 'B::LISTOP';
@B::COP::ISA = 'B::OP';

@B::SPECIAL::ISA = 'B::OBJECT';

@B::optype = qw(OP UNOP BINOP LOGOP LISTOP PMOP SVOP PADOP PVOP LOOP COP);
@B::specialsv_name = qw(Nullsv &PL_sv_undef &PL_sv_yes &PL_sv_no
			(SV*)pWARN_ALL (SV*)pWARN_NONE (SV*)pWARN_STD);

{
    # Stop "-w" from complaining about the lack of a real B::OBJECT class
    package B::OBJECT;
}

sub B::GV::SAFENAME {
  my $name = (shift())->NAME;

  # The regex below corresponds to the isCONTROLVAR macro
  # from toke.c

  $name =~ s/^\c?/^?/
    or $name =~ s/^([\cA-\cZ\c\\c[\c]\c_\c^])/
                "^" .  chr( utf8::unicode_to_native( 64 ^ ord($1) ))/e;

  # When we say unicode_to_native we really mean ascii_to_native,
  # which matters iff this is a non-ASCII platform (EBCDIC).  '\c?' would
  # not have to be special cased, except for non-ASCII.

  return $name;
}

sub B::IV::int_value {
  my ($self) = @_;
  return (($self->FLAGS() & SVf_IVisUV()) ? $self->UVX : $self->IV);
}

sub B::NULL::as_string() {""}
*B::IV::as_string = \*B::IV::int_value;
*B::PV::as_string = \*B::PV::PV;

*B::IV::RV = \*B::PV::RV if $] > 5.012;

my $debug;
my $op_count = 0;
my @parents = ();

sub debug {
    my ($class, $value) = @_;
    $debug = $value;
    walkoptree_debug($value);
}

sub class {
    my $obj = shift;
    my $name = ref $obj;
    $name =~ s/^.*:://;
    return $name;
}

sub parents { \@parents }

sub peekop {
    my $op = shift;
    return sprintf("%s (0x%x) %s", class($op), $$op, $op->name);
}

sub walkoptree_slow {
    my($op, $method, $level) = @_;
    $op_count++; # just for statistics
    $level ||= 0;
    warn(sprintf("walkoptree: %d. %s\n", $level, peekop($op))) if $debug;
    $op->$method($level) if $op->can($method);
    if ($$op && ($op->flags & OPf_KIDS)) {
	my $kid;
	unshift(@parents, $op);
	for ($kid = $op->first; $$kid; $kid = $kid->sibling) {
	    walkoptree_slow($kid, $method, $level + 1);
	}
	shift @parents;
    }
    if (class($op) eq 'PMOP'
	&& ref($op->pmreplroot)
	&& ${$op->pmreplroot}
	&& $op->pmreplroot->isa( 'B::OP' ))
    {
	unshift(@parents, $op);
	walkoptree_slow($op->pmreplroot, $method, $level + 1);
	shift @parents;
    }
}

sub compile_stats {
    return "Total number of OPs processed: $op_count\n";
}

sub timing_info {
    my ($sec, $min, $hr) = localtime;
    my ($user, $sys) = times;
    sprintf("%02d:%02d:%02d user=$user sys=$sys",
	    $hr, $min, $sec, $user, $sys);
}

my %symtable;

sub clearsym {
    %symtable = ();
}

sub savesym {
    my ($obj, $value) = @_;
    $symtable{sprintf("sym_%x", $$obj)} = $value;
}

sub objsym {
    my $obj = shift;
    return $symtable{sprintf("sym_%x", $$obj)};
}

sub walkoptree_exec {
    my ($op, $method, $level) = @_;
    $level ||= 0;
    my ($sym, $ppname);
    my $prefix = "    " x $level;
    for (; $$op; $op = $op->next) {
	$sym = objsym($op);
	if (defined($sym)) {
	    print $prefix, "goto $sym\n";
	    return;
	}
	savesym($op, sprintf("%s (0x%lx)", class($op), $$op));
	$op->$method($level);
	$ppname = $op->name;
	if ($ppname =~
	    /^(d?or(assign)?|and(assign)?|mapwhile|grepwhile|entertry|range|cond_expr)$/)
	{
	    print $prefix, uc($1), " => {\n";
	    walkoptree_exec($op->other, $method, $level + 1);
	    print $prefix, "}\n";
	} elsif ($ppname eq "match" || $ppname eq "subst") {
	    my $pmreplstart = $op->pmreplstart;
	    if ($$pmreplstart) {
		print $prefix, "PMREPLSTART => {\n";
		walkoptree_exec($pmreplstart, $method, $level + 1);
		print $prefix, "}\n";
	    }
	} elsif ($ppname eq "substcont") {
	    print $prefix, "SUBSTCONT => {\n";
	    walkoptree_exec($op->other->pmreplstart, $method, $level + 1);
	    print $prefix, "}\n";
	    $op = $op->other;
	} elsif ($ppname eq "enterloop") {
	    print $prefix, "REDO => {\n";
	    walkoptree_exec($op->redoop, $method, $level + 1);
	    print $prefix, "}\n", $prefix, "NEXT => {\n";
	    walkoptree_exec($op->nextop, $method, $level + 1);
	    print $prefix, "}\n", $prefix, "LAST => {\n";
	    walkoptree_exec($op->lastop,  $method, $level + 1);
	    print $prefix, "}\n";
	} elsif ($ppname eq "subst") {
	    my $replstart = $op->pmreplstart;
	    if ($$replstart) {
		print $prefix, "SUBST => {\n";
		walkoptree_exec($replstart, $method, $level + 1);
		print $prefix, "}\n";
	    }
	}
    }
}

sub walksymtable {
    my ($symref, $method, $recurse, $prefix) = @_;
    my $sym;
    my $ref;
    my $fullname;
    no strict 'refs';
    $prefix = '' unless defined $prefix;
    foreach my $sym ( sort keys %$symref ) {
        $ref= $symref->{$sym};
        $fullname = "*main::".$prefix.$sym;
	if ($sym =~ /::$/) {
	    $sym = $prefix . $sym;
	    if (svref_2object(\*$sym)->NAME ne "main::" && $sym ne "<none>::" && &$recurse($sym)) {
               walksymtable(\%$fullname, $method, $recurse, $sym);
	    }
	} else {
           svref_2object(\*$fullname)->$method();
	}
    }
}

{
    package B::Section;
    my $output_fh;
    my %sections;

    sub new {
	my ($class, $section, $symtable, $default) = @_;
	$output_fh ||= FileHandle->new_tmpfile;
	my $obj = bless [-1, $section, $symtable, $default], $class;
	$sections{$section} = $obj;
	return $obj;
    }

    sub get {
	my ($class, $section) = @_;
	return $sections{$section};
    }

    sub add {
	my $section = shift;
	while (defined($_ = shift)) {
	    print $output_fh "$section->[1]\t$_\n";
	    $section->[0]++;
	}
    }

    sub index {
	my $section = shift;
	return $section->[0];
    }

    sub name {
	my $section = shift;
	return $section->[1];
    }

    sub symtable {
	my $section = shift;
	return $section->[2];
    }

    sub default {
	my $section = shift;
	return $section->[3];
    }

    sub output {
	my ($section, $fh, $format) = @_;
	my $name = $section->name;
	my $sym = $section->symtable || {};
	my $default = $section->default;

	seek($output_fh, 0, 0);
	while (<$output_fh>) {
	    chomp;
	    s/^(.*?)\t//;
	    if ($1 eq $name) {
		s{(s\\_[0-9a-f]+)} {
		    exists($sym->{$1}) ? $sym->{$1} : $default;
		}ge;
		printf $fh $format, $_;
	    }
	}
    }
}

1;

__END__

