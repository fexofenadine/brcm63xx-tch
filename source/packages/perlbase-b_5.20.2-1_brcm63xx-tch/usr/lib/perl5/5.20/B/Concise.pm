package B::Concise;


use strict; # use #2
use warnings; # uses #3 and #4, since warnings uses Carp

use Exporter (); # use #5

our $VERSION   = "0.992";
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw( set_style set_style_standard add_callback
		     concise_subref concise_cv concise_main
		     add_style walk_output compile reset_sequence );
our %EXPORT_TAGS =
    ( io	=> [qw( walk_output compile reset_sequence )],
      style	=> [qw( add_style set_style_standard )],
      cb	=> [qw( add_callback )],
      mech	=> [qw( concise_subref concise_cv concise_main )],  );

use B qw(class ppname main_start main_root main_cv cstring svref_2object
	 SVf_IOK SVf_NOK SVf_POK SVf_IVisUV SVf_FAKE OPf_KIDS OPf_SPECIAL
	 CVf_ANON PAD_FAKELEX_ANON PAD_FAKELEX_MULTI SVf_ROK);

my %style =
  ("terse" =>
   ["(?(#label =>\n)?)(*(    )*)#class (#addr) #name (?([#targ])?) "
    . "#svclass~(?((#svaddr))?)~#svval~(?(label \"#coplabel\")?)\n",
    "(*(    )*)goto #class (#addr)\n",
    "#class pp_#name"],
   "concise" =>
   ["#hyphseq2 (*(   (x( ;)x))*)<#classsym> #exname#arg(?([#targarglife])?)"
    . "~#flags(?(/#private)?)(?(:#hints)?)(x(;~->#next)x)\n"
    , "  (*(    )*)     goto #seq\n",
    "(?(<#seq>)?)#exname#arg(?([#targarglife])?)"],
   "linenoise" =>
   ["(x(;(*( )*))x)#noise#arg(?([#targarg])?)(x( ;\n)x)",
    "gt_#seq ",
    "(?(#seq)?)#noise#arg(?([#targarg])?)"],
   "debug" =>
   ["#class (#addr)\n\top_next\t\t#nextaddr\n\t(?(op_other\t#otheraddr\n\t)?)"
    . "op_sibling\t#sibaddr\n\t"
    . "op_ppaddr\tPL_ppaddr[OP_#NAME]\n\top_type\t\t#typenum\n"
    . "\top_flags\t#flagval\n\top_private\t#privval\t#hintsval\n"
    . "(?(\top_first\t#firstaddr\n)?)(?(\top_last\t\t#lastaddr\n)?)"
    . "(?(\top_sv\t\t#svaddr\n)?)",
    "    GOTO #addr\n",
    "#addr"],
   "env" => [$ENV{B_CONCISE_FORMAT}, $ENV{B_CONCISE_GOTO_FORMAT},
	     $ENV{B_CONCISE_TREE_FORMAT}],
  );

our $stylename;		# selects current style from %style
my $order = "basic";	# how optree is walked & printed: basic, exec, tree

my ($format, $gotofmt, $treefmt);

my $base = 36;		# how <sequence#> is displayed
my $big_endian = 1;	# more <sequence#> display
my $tree_style = 0;	# tree-order details
my $banner = 1;		# print banner before optree is traversed
my $do_main = 0;	# force printing of main routine
my $show_src;		# show source code

our @callbacks;		# allow external management

set_style_standard("concise");

my $curcv;
my $cop_seq_base;

sub set_style {
    ($format, $gotofmt, $treefmt) = @_;
    #warn "set_style: deprecated, use set_style_standard instead\n"; # someday
    die "expecting 3 style-format args\n" unless @_ == 3;
}

sub add_style {
    my ($newstyle,@args) = @_;
    die "style '$newstyle' already exists, choose a new name\n"
	if exists $style{$newstyle};
    die "expecting 3 style-format args\n" unless @args == 3;
    $style{$newstyle} = [@args];
    $stylename = $newstyle; # update rendering state
}

sub set_style_standard {
    ($stylename) = @_; # update rendering state
    die "err: style '$stylename' unknown\n" unless exists $style{$stylename};
    set_style(@{$style{$stylename}});
}

sub add_callback {
    push @callbacks, @_;
}

our $walkHandle;	# public for your convenience
BEGIN { $walkHandle = \*STDOUT }

sub walk_output { # updates $walkHandle
    my $handle = shift;
    return $walkHandle unless $handle; # allow use as accessor

    if (ref $handle eq 'SCALAR') {
	require Config;
	die "no perlio in this build, can't call walk_output (\\\$scalar)\n"
	    unless $Config::Config{useperlio};
	# in 5.8+, open(FILEHANDLE,MODE,REFERENCE) writes to string
	open my $tmp, '>', $handle;	# but cant re-set existing STDOUT
	$walkHandle = $tmp;		# so use my $tmp as intermediate var
	return $walkHandle;
    }
    my $iotype = ref $handle;
    die "expecting argument/object that can print\n"
	unless $iotype eq 'GLOB' or $iotype and $handle->can('print');
    $walkHandle = $handle;
}

sub concise_subref {
    my($order, $coderef, $name) = @_;
    my $codeobj = svref_2object($coderef);

    return concise_stashref(@_)
	unless ref($codeobj) =~ '^B::(?:CV|FM)\z';
    concise_cv_obj($order, $codeobj, $name);
}

sub concise_stashref {
    my($order, $h) = @_;
    local *s;
    foreach my $k (sort keys %$h) {
	next unless defined $h->{$k};
	*s = $h->{$k};
	my $coderef = *s{CODE} or next;
	reset_sequence();
	print "FUNC: ", *s, "\n";
	my $codeobj = svref_2object($coderef);
	next unless ref $codeobj eq 'B::CV';
	eval { concise_cv_obj($order, $codeobj, $k) };
	warn "err $@ on $codeobj" if $@;
    }
}

*concise_cv = \&concise_subref;

sub concise_cv_obj {
    my ($order, $cv, $name) = @_;
    # name is either a string, or a CODE ref (copy of $cv arg??)

    $curcv = $cv;

    if (ref($cv->XSUBANY) =~ /B::(\w+)/) {
	print $walkHandle "$name is a constant sub, optimized to a $1\n";
	return;
    }
    if ($cv->XSUB) {
	print $walkHandle "$name is XS code\n";
	return;
    }
    if (class($cv->START) eq "NULL") {
	no strict 'refs';
	if (ref $name eq 'CODE') {
	    print $walkHandle "coderef $name has no START\n";
	}
	elsif (exists &$name) {
	    print $walkHandle "$name exists in stash, but has no START\n";
	}
	else {
	    print $walkHandle "$name not in symbol table\n";
	}
	return;
    }
    sequence($cv->START);
    if ($order eq "exec") {
	walk_exec($cv->START);
    }
    elsif ($order eq "basic") {
	# walk_topdown($cv->ROOT, sub { $_[0]->concise($_[1]) }, 0);
	my $root = $cv->ROOT;
	unless (ref $root eq 'B::NULL') {
	    walk_topdown($root, sub { $_[0]->concise($_[1]) }, 0);
	} else {
	    print $walkHandle "B::NULL encountered doing ROOT on $cv. avoiding disaster\n";
	}
    } else {
	print $walkHandle tree($cv->ROOT, 0);
    }
}

sub concise_main {
    my($order) = @_;
    sequence(main_start);
    $curcv = main_cv;
    if ($order eq "exec") {
	return if class(main_start) eq "NULL";
	walk_exec(main_start);
    } elsif ($order eq "tree") {
	return if class(main_root) eq "NULL";
	print $walkHandle tree(main_root, 0);
    } elsif ($order eq "basic") {
	return if class(main_root) eq "NULL";
	walk_topdown(main_root,
		     sub { $_[0]->concise($_[1]) }, 0);
    }
}

sub concise_specials {
    my($name, $order, @cv_s) = @_;
    my $i = 1;
    if ($name eq "BEGIN") {
	splice(@cv_s, 0, 8); # skip 7 BEGIN blocks in this file. NOW 8 ??
    } elsif ($name eq "CHECK") {
	pop @cv_s; # skip the CHECK block that calls us
    }
    for my $cv (@cv_s) {
	print $walkHandle "$name $i:\n";
	$i++;
	concise_cv_obj($order, $cv, $name);
    }
}

my $start_sym = "\e(0"; # "\cN" sometimes also works
my $end_sym   = "\e(B"; # "\cO" respectively

my @tree_decorations =
  (["  ", "--", "+-", "|-", "| ", "`-", "-", 1],
   [" ", "-", "+", "+", "|", "`", "", 0],
   ["  ", map("$start_sym$_$end_sym", "qq", "wq", "tq", "x ", "mq", "q"), 1],
   [" ", map("$start_sym$_$end_sym", "q", "w", "t", "x", "m"), "", 0],
  );

my @render_packs; # collect -stash=<packages>

sub compileOpts {
    # set rendering state from options and args
    my (@options,@args);
    if (@_) {
	@options = grep(/^-/, @_);
	@args = grep(!/^-/, @_);
    }
    for my $o (@options) {
	# mode/order
	if ($o eq "-basic") {
	    $order = "basic";
	} elsif ($o eq "-exec") {
	    $order = "exec";
	} elsif ($o eq "-tree") {
	    $order = "tree";
	}
	# tree-specific
	elsif ($o eq "-compact") {
	    $tree_style |= 1;
	} elsif ($o eq "-loose") {
	    $tree_style &= ~1;
	} elsif ($o eq "-vt") {
	    $tree_style |= 2;
	} elsif ($o eq "-ascii") {
	    $tree_style &= ~2;
	}
	# sequence numbering
	elsif ($o =~ /^-base(\d+)$/) {
	    $base = $1;
	} elsif ($o eq "-bigendian") {
	    $big_endian = 1;
	} elsif ($o eq "-littleendian") {
	    $big_endian = 0;
	}
	# miscellaneous, presentation
	elsif ($o eq "-nobanner") {
	    $banner = 0;
	} elsif ($o eq "-banner") {
	    $banner = 1;
	}
	elsif ($o eq "-main") {
	    $do_main = 1;
	} elsif ($o eq "-nomain") {
	    $do_main = 0;
	} elsif ($o eq "-src") {
	    $show_src = 1;
	}
	elsif ($o =~ /^-stash=(.*)/) {
	    my $pkg = $1;
	    no strict 'refs';
	    if (! %{$pkg.'::'}) {
		eval "require $pkg";
	    } else {
		require Config;
		if (!$Config::Config{usedl}
		    && keys %{$pkg.'::'} == 1
		    && $pkg->can('bootstrap')) {
		    # It is something that we're statically linked to, but hasn't
		    # yet been used.
		    eval "require $pkg";
		}
	    }
	    push @render_packs, $pkg;
	}
	# line-style options
	elsif (exists $style{substr($o, 1)}) {
	    $stylename = substr($o, 1);
	    set_style_standard($stylename);
	} else {
	    warn "Option $o unrecognized";
	}
    }
    return (@args);
}

sub compile {
    my (@args) = compileOpts(@_);
    return sub {
	my @newargs = compileOpts(@_); # accept new rendering options
	warn "disregarding non-options: @newargs\n" if @newargs;

	for my $objname (@args) {
	    next unless $objname; # skip null args to avoid noisy responses

	    if ($objname eq "BEGIN") {
		concise_specials("BEGIN", $order,
				 B::begin_av->isa("B::AV") ?
				 B::begin_av->ARRAY : ());
	    } elsif ($objname eq "INIT") {
		concise_specials("INIT", $order,
				 B::init_av->isa("B::AV") ?
				 B::init_av->ARRAY : ());
	    } elsif ($objname eq "CHECK") {
		concise_specials("CHECK", $order,
				 B::check_av->isa("B::AV") ?
				 B::check_av->ARRAY : ());
	    } elsif ($objname eq "UNITCHECK") {
		concise_specials("UNITCHECK", $order,
				 B::unitcheck_av->isa("B::AV") ?
				 B::unitcheck_av->ARRAY : ());
	    } elsif ($objname eq "END") {
		concise_specials("END", $order,
				 B::end_av->isa("B::AV") ?
				 B::end_av->ARRAY : ());
	    }
	    else {
		# convert function names to subrefs
		if (ref $objname) {
		    print $walkHandle "B::Concise::compile($objname)\n"
			if $banner;
		    concise_subref($order, ($objname)x2);
		    next;
		} else {
		    $objname = "main::" . $objname unless $objname =~ /::/;
		    no strict 'refs';
		    my $glob = \*$objname;
		    unless (*$glob{CODE} || *$glob{FORMAT}) {
			print $walkHandle "$objname:\n" if $banner;
			print $walkHandle "err: unknown function ($objname)\n";
			return;
		    }
		    if (my $objref = *$glob{CODE}) {
			print $walkHandle "$objname:\n" if $banner;
			concise_subref($order, $objref, $objname);
		    }
		    if (my $objref = *$glob{FORMAT}) {
			print $walkHandle "$objname (FORMAT):\n"
			    if $banner;
			concise_subref($order, $objref, $objname);
		    }
		}
	    }
	}
	for my $pkg (@render_packs) {
	    no strict 'refs';
	    concise_stashref($order, \%{$pkg.'::'});
	}

	if (!@args or $do_main or @render_packs) {
	    print $walkHandle "main program:\n" if $do_main;
	    concise_main($order);
	}
	return @args;	# something
    }
}

my %labels;
my $lastnext;	# remembers op-chain, used to insert gotos

my %opclass = ('OP' => "0", 'UNOP' => "1", 'BINOP' => "2", 'LOGOP' => "|",
	       'LISTOP' => "@", 'PMOP' => "/", 'SVOP' => "\$", 'GVOP' => "*",
	       'PVOP' => '"', 'LOOP' => "{", 'COP' => ";", 'PADOP' => "#");

no warnings 'qw'; # "Possible attempt to put comments..."; use #7
my @linenoise =
  qw'#  () sc (  @? 1  $* gv *{ m$ m@ m% m? p/ *$ $  $# & a& pt \\ s\\ rf bl
     `  *? <> ?? ?/ r/ c/ // qr s/ /c y/ =  @= C  sC Cp sp df un BM po +1 +I
     -1 -I 1+ I+ 1- I- ** *  i* /  i/ %$ i% x  +  i+ -  i- .  "  << >> <  i<
     >  i> <= i, >= i. == i= != i! <? i? s< s> s, s. s= s! s? b& b^ b| -0 -i
     !  ~  a2 si cs rd sr e^ lg sq in %x %o ab le ss ve ix ri sf FL od ch cy
     uf lf uc lc qm @  [f [  @[ eh vl ky dl ex %  ${ @{ uk pk st jn )  )[ a@
     a% sl +] -] [- [+ so rv GS GW MS MW .. f. .f && || ^^ ?: &= |= -> s{ s}
     v} ca wa di rs ;; ;  ;d }{ {  }  {} f{ it {l l} rt }l }n }r dm }g }e ^o
     ^c ^| ^# um bm t~ u~ ~d DB db ^s se ^g ^r {w }w pf pr ^O ^K ^R ^W ^d ^v
     ^e ^t ^k t. fc ic fl .s .p .b .c .l .a .h g1 s1 g2 s2 ?. l? -R -W -X -r
     -w -x -e -o -O -z -s -M -A -C -S -c -b -f -d -p -l -u -g -k -t -T -B cd
     co cr u. cm ut r. l@ s@ r@ mD uD oD rD tD sD wD cD f$ w$ p$ sh e$ k$ g3
     g4 s4 g5 s5 T@ C@ L@ G@ A@ S@ Hg Hc Hr Hw Mg Mc Ms Mr Sg Sc So rq do {e
     e} {t t} g6 G6 6e g7 G7 7e g8 G8 8e g9 G9 9e 6s 7s 8s 9s 6E 7E 8E 9E Pn
     Pu GP SP EP Gn Gg GG SG EG g0 c$ lk t$ ;s n> // /= CO';

my $chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

sub op_flags { # common flags (see BASOP.op_flags in op.h)
    my($x) = @_;
    my(@v);
    push @v, "v" if ($x & 3) == 1;
    push @v, "s" if ($x & 3) == 2;
    push @v, "l" if ($x & 3) == 3;
    push @v, "K" if $x & 4;
    push @v, "P" if $x & 8;
    push @v, "R" if $x & 16;
    push @v, "M" if $x & 32;
    push @v, "S" if $x & 64;
    push @v, "*" if $x & 128;
    return join("", @v);
}

sub base_n {
    my $x = shift;
    return "-" . base_n(-$x) if $x < 0;
    my $str = "";
    do { $str .= substr($chars, $x % $base, 1) } while $x = int($x / $base);
    $str = reverse $str if $big_endian;
    return $str;
}

my %sequence_num;
my $seq_max = 1;

sub reset_sequence {
    # reset the sequence
    %sequence_num = ();
    $seq_max = 1;
    $lastnext = 0;
}

sub seq {
    my($op) = @_;
    return "-" if not exists $sequence_num{$$op};
    return base_n($sequence_num{$$op});
}

sub walk_topdown {
    my($op, $sub, $level) = @_;
    $sub->($op, $level);
    if ($op->flags & OPf_KIDS) {
	for (my $kid = $op->first; $$kid; $kid = $kid->sibling) {
	    walk_topdown($kid, $sub, $level + 1);
	}
    }
    if (class($op) eq "PMOP") {
	my $maybe_root = $op->pmreplroot;
	if (ref($maybe_root) and $maybe_root->isa("B::OP")) {
	    # It really is the root of the replacement, not something
	    # else stored here for lack of space elsewhere
	    walk_topdown($maybe_root, $sub, $level + 1);
	}
    }
}

sub walklines {
    my($ar, $level) = @_;
    for my $l (@$ar) {
	if (ref($l) eq "ARRAY") {
	    walklines($l, $level + 1);
	} else {
	    $l->concise($level);
	}
    }
}

sub walk_exec {
    my($top, $level) = @_;
    my %opsseen;
    my @lines;
    my @todo = ([$top, \@lines]);
    while (@todo and my($op, $targ) = @{shift @todo}) {
	for (; $$op; $op = $op->next) {
	    last if $opsseen{$$op}++;
	    push @$targ, $op;
	    my $name = $op->name;
	    if (class($op) eq "LOGOP") {
		my $ar = [];
		push @$targ, $ar;
		push @todo, [$op->other, $ar];
	    } elsif ($name eq "subst" and $ {$op->pmreplstart}) {
		my $ar = [];
		push @$targ, $ar;
		push @todo, [$op->pmreplstart, $ar];
	    } elsif ($name =~ /^enter(loop|iter)$/) {
		$labels{${$op->nextop}} = "NEXT";
		$labels{${$op->lastop}} = "LAST";
		$labels{${$op->redoop}} = "REDO";
	    }
	}
    }
    walklines(\@lines, 0);
}

sub sequence {
    my($op) = @_;
    my $oldop = 0;
    return if class($op) eq "NULL" or exists $sequence_num{$$op};
    for (; $$op; $op = $op->next) {
	last if exists $sequence_num{$$op};
	my $name = $op->name;
	if ($name =~ /^(null|scalar|lineseq|scope)$/) {
	    next if $oldop and $ {$op->next};
	} else {
	    $sequence_num{$$op} = $seq_max++;
	    if (class($op) eq "LOGOP") {
		my $other = $op->other;
		$other = $other->next while $other->name eq "null";
		sequence($other);
	    } elsif (class($op) eq "LOOP") {
		my $redoop = $op->redoop;
		$redoop = $redoop->next while $redoop->name eq "null";
		sequence($redoop);
		my $nextop = $op->nextop;
		$nextop = $nextop->next while $nextop->name eq "null";
		sequence($nextop);
		my $lastop = $op->lastop;
		$lastop = $lastop->next while $lastop->name eq "null";
		sequence($lastop);
	    } elsif ($name eq "subst" and $ {$op->pmreplstart}) {
		my $replstart = $op->pmreplstart;
		$replstart = $replstart->next while $replstart->name eq "null";
		sequence($replstart);
	    }
	}
	$oldop = $op;
    }
}

sub fmt_line {    # generate text-line for op.
    my($hr, $op, $text, $level) = @_;

    $_->($hr, $op, \$text, \$level, $stylename) for @callbacks;

    return '' if $hr->{SKIP};	# suppress line if a callback said so
    return '' if $hr->{goto} and $hr->{goto} eq '-';	# no goto nowhere

    # spec: (?(text1#varText2)?)
    $text =~ s/\(\?\(([^\#]*?)\#(\w+)([^\#]*?)\)\?\)/
	$hr->{$2} ? $1.$hr->{$2}.$3 : ""/eg;

    # spec: (x(exec_text;basic_text)x)
    $text =~ s/\(x\((.*?);(.*?)\)x\)/$order eq "exec" ? $1 : $2/egs;

    # spec: (*(text)*)
    $text =~ s/\(\*\(([^;]*?)\)\*\)/$1 x $level/egs;

    # spec: (*(text1;text2)*)
    $text =~ s/\(\*\((.*?);(.*?)\)\*\)/$1 x ($level - 1) . $2 x ($level>0)/egs;

    # convert #Var to tag=>val form: Var\t#var
    $text =~ s/\#([A-Z][a-z]+)(\d+)?/\t\u$1\t\L#$1$2/gs;

    # spec: #varN
    $text =~ s/\#([a-zA-Z]+)(\d+)/sprintf("%-$2s", $hr->{$1})/eg;

    $text =~ s/\#([a-zA-Z]+)/$hr->{$1}/eg;	# populate #var's
    $text =~ s/[ \t]*~+[ \t]*/ /g;		# squeeze tildes

    $text = "# $hr->{src}\n$text" if $show_src and $hr->{src};

    chomp $text;
    return "$text\n" if $text ne "" and $order ne "tree";
    return $text; # suppress empty lines
}

our %priv; # used to display each opcode's BASEOP.op_private values

$priv{$_}{128} = "LVINTRO"
  for qw(pos substr vec threadsv gvsv rv2sv rv2hv rv2gv rv2av rv2arylen
         aelem helem aslice hslice padsv padav padhv enteriter entersub
         padrange pushmark);
$priv{$_}{64} = "REFC" for qw(leave leavesub leavesublv leavewrite);
$priv{$_}{128} = "LV" for qw(leave leaveloop);
@{$priv{aassign}}{32,64} = qw(STATE COMMON);
@{$priv{sassign}}{32,64,128} = qw(STATE BKWARD CV2GV);
$priv{$_}{64} = "RTIME" for qw(match subst substcont qr);
@{$priv{$_}}{1,2,4,8,16,64} = qw(<UTF >UTF IDENT SQUASH DEL COMPL GROWS)
  for qw(trans transr);
$priv{repeat}{64} = "DOLIST";
$priv{leaveloop}{64} = "CONT";
@{$priv{$_}}{32,64,96} = qw(DREFAV DREFHV DREFSV)
  for qw(rv2gv rv2sv padsv aelem helem);
$priv{$_}{16} = "STATE" for qw(padav padhv padsv);
@{$priv{rv2gv}}{4,16} = qw(NOINIT FAKE);
@{$priv{entersub}}{1,4,16,32,64} = qw(INARGS TARG DBG DEREF);
@{$priv{rv2cv}}{1,8,128} = qw(CONST AMPER NO());
$priv{gv}{32} = "EARLYCV";
$priv{$_}{16} = "LVDEFER" for qw(aelem helem);
$priv{$_}{16} = "OURINTR" for qw(gvsv rv2sv rv2av rv2hv r2gv enteriter);
$priv{$_}{8} = "LVSUB"
  for qw(rv2av rv2gv rv2hv padav padhv aelem helem aslice hslice
         av2arylen keys rkeys substr pos vec);
$priv{$_}{4} = "SLICEWARN"
  for qw(rv2hv rv2av padav padhv hslice aslice);
@{$priv{$_}}{32,64} = qw(BOOL BOOL?) for qw(rv2hv padhv);
$priv{substr}{16} = "REPL1ST";
$priv{$_}{16} = "TARGMY"
  for map(($_,"s$_"), qw(chop chomp)),
      map(($_,"i_$_"), qw(postinc postdec multiply divide modulo add
                          subtract negate)),
      qw(pow concat stringify left_shift right_shift bit_and bit_xor
         bit_or complement atan2 sin cos rand exp log sqrt int hex oct
         abs length index rindex sprintf ord chr crypt quotemeta join
         push unshift flock chdir chown chroot unlink chmod utime rename
         link symlink mkdir rmdir wait waitpid system exec kill getppid
         getpgrp setpgrp getpriority setpriority time sleep);
$priv{$_}{4} = "REVERSED" for qw(enteriter iter);
@{$priv{const}}{2,4,8,16,64} = qw(NOVER SHORT STRICT ENTERED BARE);
$priv{$_}{64} = "LINENUM" for qw(flip flop);
$priv{list}{64} = "GUESSED";
$priv{delete}{64} = "SLICE";
$priv{exists}{64} = "SUB";
@{$priv{sort}}{1,2,4,8,16,32,64} = qw(NUM INT REV INPLACE DESC QSORT STABLE);
$priv{reverse}{8} = "INPLACE";
$priv{threadsv}{64} = "SVREFd";
@{$priv{$_}}{16,32,64,128} = qw(INBIN INCR OUTBIN OUTCR)
  for qw(open backtick);
$priv{$_}{32} = "HUSH" for qw(nextstate dbstate);
$priv{$_}{2} = "FTACCESS"
  for qw(ftrread ftrwrite ftrexec fteread ftewrite fteexec);
@{$priv{entereval}}{2,4,8,16} = qw(HAS_HH UNI BYTES COPHH);
@{$priv{$_}}{4,8,16} = qw(FTSTACKED FTSTACKING FTAFTERt)
  for qw(ftrread ftrwrite ftrexec fteread ftewrite fteexec ftis fteowned
         ftrowned ftzero ftsize ftmtime ftatime ftctime ftsock ftchr
         ftblk ftfile ftdir ftpipe ftlink ftsuid ftsgid ftsvtx fttty
         fttext ftbinary);
$priv{$_}{2} = "GREPLEX"
  for qw(mapwhile mapstart grepwhile grepstart);
$priv{$_}{128} = "+1" for qw(caller wantarray runcv);
@{$priv{coreargs}}{1,2,64,128} = qw(DREF1 DREF2 $MOD MARK);
$priv{$_}{128} = "UTF" for qw(last redo next goto dump);
$priv{split}{128} = "IMPLIM";

our %hints; # used to display each COP's op_hints values

@hints{2,512,1024,32,64,128} = ('$', '&', '*', 'x$', 'x&', 'x*');
@hints{1,4,8,16} = ('i', 'l', 'b');
@hints{256,131072,262144,524288} = ('{','%','<','>');
@hints{4096,8192,16384,32768,65536} = ('I', 'F', 'B', 'S', 'R');
@hints{1048576,2097152} = ('T', 'E');
@hints{4194304,8388608} = ('X', 'U');

sub _flags {
    my($hash, $x) = @_;
    my @s;
    for my $flag (sort {$b <=> $a} keys %$hash) {
	if ($hash->{$flag} and $x & $flag and $x >= $flag) {
	    $x -= $flag;
	    push @s, $hash->{$flag};
	}
    }
    push @s, $x if $x;
    return join(",", @s);
}

sub private_flags {
    my($name, $x) = @_;
    _flags($priv{$name}, $x);
}

sub hints_flags {
    my($x) = @_;
    _flags(\%hints, $x);
}

sub concise_sv {
    my($sv, $hr, $preferpv) = @_;
    $hr->{svclass} = class($sv);
    $hr->{svclass} = "UV"
      if $hr->{svclass} eq "IV" and $sv->FLAGS & SVf_IVisUV;
    Carp::cluck("bad concise_sv: $sv") unless $sv and $$sv;
    $hr->{svaddr} = sprintf("%#x", $$sv);
    if ($hr->{svclass} eq "GV" && $sv->isGV_with_GP()) {
	my $gv = $sv;
	my $stash = $gv->STASH;
	if (class($stash) eq "SPECIAL") {
	    $stash = "<none>";
	}
	else {
	    $stash = $stash->NAME;
	}
	if ($stash eq "main") {
	    $stash = "";
	} else {
	    $stash = $stash . "::";
	}
	$hr->{svval} = "*$stash" . $gv->SAFENAME;
	return "*$stash" . $gv->SAFENAME;
    } else {
	if ($] >= 5.011) {
	    while (class($sv) eq "IV" && $sv->FLAGS & SVf_ROK) {
		$hr->{svval} .= "\\";
		$sv = $sv->RV;
	    }
	} else {
	    while (class($sv) eq "RV") {
		$hr->{svval} .= "\\";
		$sv = $sv->RV;
	    }
	}
	if (class($sv) eq "SPECIAL") {
	    $hr->{svval} .= ["Null", "sv_undef", "sv_yes", "sv_no"]->[$$sv];
	} elsif ($preferpv
	      && ($sv->FLAGS & SVf_POK || class($sv) eq "REGEXP")) {
	    $hr->{svval} .= cstring($sv->PV);
	} elsif ($sv->FLAGS & SVf_NOK) {
	    $hr->{svval} .= $sv->NV;
	} elsif ($sv->FLAGS & SVf_IOK) {
	    $hr->{svval} .= $sv->int_value;
	} elsif ($sv->FLAGS & SVf_POK || class($sv) eq "REGEXP") {
	    $hr->{svval} .= cstring($sv->PV);
	} elsif (class($sv) eq "HV") {
	    $hr->{svval} .= 'HASH';
	}

	$hr->{svval} = 'undef' unless defined $hr->{svval};
	my $out = $hr->{svclass};
	return $out .= " $hr->{svval}" ; 
    }
}

my %srclines;

sub fill_srclines {
    my $fullnm = shift;
    if ($fullnm eq '-e') {
	$srclines{$fullnm} = [ $fullnm, "-src not supported for -e" ];
	return;
    }
    open (my $fh, '<', $fullnm)
	or warn "# $fullnm: $!, (chdirs not supported by this feature yet)\n"
	and return;
    my @l = <$fh>;
    chomp @l;
    unshift @l, $fullnm; # like @{_<$fullnm} in debug, array starts at 1
    $srclines{$fullnm} = \@l;
}

sub concise_op {
    my ($op, $level, $format) = @_;
    my %h;
    $h{exname} = $h{name} = $op->name;
    $h{NAME} = uc $h{name};
    $h{class} = class($op);
    $h{extarg} = $h{targ} = $op->targ;
    $h{extarg} = "" unless $h{extarg};
    if ($h{name} eq "null" and $h{targ}) {
	# targ holds the old type
	$h{exname} = "ex-" . substr(ppname($h{targ}), 3);
	$h{extarg} = "";
    } elsif ($op->name =~ /^leave(sub(lv)?|write)?$/) {
	# targ potentially holds a reference count
	if ($op->private & 64) {
	    my $refs = "ref" . ($h{targ} != 1 ? "s" : "");
	    $h{targarglife} = $h{targarg} = "$h{targ} $refs";
	}
    } elsif ($h{targ}) {
	my $count = $h{name} eq 'padrange' ? ($op->private & 127) : 1;
	my (@targarg, @targarglife);
	for my $i (0..$count-1) {
	    my ($targarg, $targarglife);
	    my $padname = (($curcv->PADLIST->ARRAY)[0]->ARRAY)[$h{targ}+$i];
	    if (defined $padname and class($padname) ne "SPECIAL") {
		$targarg  = $padname->PVX;
		if ($padname->FLAGS & SVf_FAKE) {
		    # These changes relate to the jumbo closure fix.
		    # See changes 19939 and 20005
		    my $fake = '';
		    $fake .= 'a'
			if $padname->PARENT_FAKELEX_FLAGS & PAD_FAKELEX_ANON;
		    $fake .= 'm'
			if $padname->PARENT_FAKELEX_FLAGS & PAD_FAKELEX_MULTI;
		    $fake .= ':' . $padname->PARENT_PAD_INDEX
			if $curcv->CvFLAGS & CVf_ANON;
		    $targarglife = "$targarg:FAKE:$fake";
		}
		else {
		    my $intro = $padname->COP_SEQ_RANGE_LOW - $cop_seq_base;
		    my $finish = int($padname->COP_SEQ_RANGE_HIGH) - $cop_seq_base;
		    $finish = "end" if $finish == 999999999 - $cop_seq_base;
		    $targarglife = "$targarg:$intro,$finish";
		}
	    } else {
		$targarglife = $targarg = "t" . ($h{targ}+$i);
	    }
	    push @targarg,     $targarg;
	    push @targarglife, $targarglife;
	}
	$h{targarg}     = join '; ', @targarg;
	$h{targarglife} = join '; ', @targarglife;
    }
    $h{arg} = "";
    $h{svclass} = $h{svaddr} = $h{svval} = "";
    if ($h{class} eq "PMOP") {
	my $extra = '';
	my $precomp = $op->precomp;
	if (defined $precomp) {
	    $precomp = cstring($precomp); # Escape literal control sequences
 	    $precomp = "/$precomp/";
	} else {
	    $precomp = "";
	}
	if ($op->name eq 'subst') {
	    if (class($op->pmreplstart) ne "NULL") {
		undef $lastnext;
		$extra = " replstart->" . seq($op->pmreplstart);
	    }
	}
	elsif ($op->name eq 'pushre') {
	    # with C<@stash_array = split(/pat/, str);>,
	    #  *stash_array is stored in /pat/'s pmreplroot.
	    my $gv = $op->pmreplroot;
	    if (!ref($gv)) {
		# threaded: the value is actually a pad offset for where
		# the GV is kept (op_pmtargetoff)
		if ($gv) {
		    $gv = (($curcv->PADLIST->ARRAY)[1]->ARRAY)[$gv]->NAME;
		}
	    }
	    else {
		# unthreaded: its a GV (if it exists)
		$gv = (ref($gv) eq "B::GV") ? $gv->NAME : undef;
	    }
	    $extra = " => \@$gv" if $gv;
	}
	$h{arg} = "($precomp$extra)";
    } elsif ($h{class} eq "PVOP" and $h{name} !~ '^transr?\z') {
	$h{arg} = '("' . $op->pv . '")';
	$h{svval} = '"' . $op->pv . '"';
    } elsif ($h{class} eq "COP") {
	my $label = $op->label;
	$h{coplabel} = $label;
	$label = $label ? "$label: " : "";
	my $loc = $op->file;
	my $pathnm = $loc;
	$loc =~ s[.*/][];
	my $ln = $op->line;
	$loc .= ":$ln";
	my($stash, $cseq) = ($op->stash->NAME, $op->cop_seq - $cop_seq_base);
	$h{arg} = "($label$stash $cseq $loc)";
	if ($show_src) {
	    fill_srclines($pathnm) unless exists $srclines{$pathnm};
	    # Would love to retain Jim's use of // but this code needs to be
	    # portable to 5.8.x
	    my $line = $srclines{$pathnm}[$ln];
	    $line = "-src unavailable under -e" unless defined $line;
	    $h{src} = "$ln: $line";
	}
    } elsif ($h{class} eq "LOOP") {
	$h{arg} = "(next->" . seq($op->nextop) . " last->" . seq($op->lastop)
	  . " redo->" . seq($op->redoop) . ")";
    } elsif ($h{class} eq "LOGOP") {
	undef $lastnext;
	$h{arg} = "(other->" . seq($op->other) . ")";
	$h{otheraddr} = sprintf("%#x", $ {$op->other});
    }
    elsif ($h{class} eq "SVOP" or $h{class} eq "PADOP") {
	unless ($h{name} eq 'aelemfast' and $op->flags & OPf_SPECIAL) {
	    my $idx = ($h{class} eq "SVOP") ? $op->targ : $op->padix;
	    my $preferpv = $h{name} eq "method_named";
	    if ($h{class} eq "PADOP" or !${$op->sv}) {
		my $sv = (($curcv->PADLIST->ARRAY)[1]->ARRAY)[$idx];
		$h{arg} = "[" . concise_sv($sv, \%h, $preferpv) . "]";
		$h{targarglife} = $h{targarg} = "";
	    } else {
		$h{arg} = "(" . concise_sv($op->sv, \%h, $preferpv) . ")";
	    }
	}
    }
    $h{seq} = $h{hyphseq} = seq($op);
    $h{seq} = "" if $h{seq} eq "-";
    $h{opt} = $op->opt;
    $h{label} = $labels{$$op};
    $h{next} = $op->next;
    $h{next} = (class($h{next}) eq "NULL") ? "(end)" : seq($h{next});
    $h{nextaddr} = sprintf("%#x", $ {$op->next});
    $h{sibaddr} = sprintf("%#x", $ {$op->sibling});
    $h{firstaddr} = sprintf("%#x", $ {$op->first}) if $op->can("first");
    $h{lastaddr} = sprintf("%#x", $ {$op->last}) if $op->can("last");

    $h{classsym} = $opclass{$h{class}};
    $h{flagval} = $op->flags;
    $h{flags} = op_flags($op->flags);
    $h{privval} = $op->private;
    $h{private} = private_flags($h{name}, $op->private);
    if ($op->folded) {
      $h{private} &&= "$h{private},";
      $h{private} .= "FOLD";
    }
    if ($op->can("hints")) {
      $h{hintsval} = $op->hints;
      $h{hints} = hints_flags($h{hintsval});
    } else {
      $h{hintsval} = $h{hints} = '';
    }
    $h{addr} = sprintf("%#x", $$op);
    $h{typenum} = $op->type;
    $h{noise} = $linenoise[$op->type];

    return fmt_line(\%h, $op, $format, $level);
}

sub B::OP::concise {
    my($op, $level) = @_;
    if ($order eq "exec" and $lastnext and $$lastnext != $$op) {
	# insert a 'goto' line
	my $synth = {"seq" => seq($lastnext), "class" => class($lastnext),
		     "addr" => sprintf("%#x", $$lastnext),
		     "goto" => seq($lastnext), # simplify goto '-' removal
	     };
	print $walkHandle fmt_line($synth, $op, $gotofmt, $level+1);
    }
    $lastnext = $op->next;
    print $walkHandle concise_op($op, $level, $format);
}

sub b_terse {
    my($op, $level) = @_;

    # This isn't necessarily right, but there's no easy way to get
    # from an OP to the right CV. This is a limitation of the
    # ->terse() interface style, and there isn't much to do about
    # it. In particular, we can die in concise_op if the main pad
    # isn't long enough, or has the wrong kind of entries, compared to
    # the pad a sub was compiled with. The fix for that would be to
    # make a backwards compatible "terse" format that never even
    # looked at the pad, just like the old B::Terse. I don't think
    # that's worth the effort, though.
    $curcv = main_cv unless $curcv;

    if ($order eq "exec" and $lastnext and $$lastnext != $$op) {
	# insert a 'goto'
	my $h = {"seq" => seq($lastnext), "class" => class($lastnext),
		 "addr" => sprintf("%#x", $$lastnext)};
	print # $walkHandle
	    fmt_line($h, $op, $style{"terse"}[1], $level+1);
    }
    $lastnext = $op->next;
    print # $walkHandle 
	concise_op($op, $level, $style{"terse"}[0]);
}

sub tree {
    my $op = shift;
    my $level = shift;
    my $style = $tree_decorations[$tree_style];
    my($space, $single, $kids, $kid, $nokid, $last, $lead, $size) = @$style;
    my $name = concise_op($op, $level, $treefmt);
    if (not $op->flags & OPf_KIDS) {
	return $name . "\n";
    }
    my @lines;
    for (my $kid = $op->first; $$kid; $kid = $kid->sibling) {
	push @lines, tree($kid, $level+1);
    }
    my $i;
    for ($i = $#lines; substr($lines[$i], 0, 1) eq " "; $i--) {
	$lines[$i] = $space . $lines[$i];
    }
    if ($i > 0) {
	$lines[$i] = $last . $lines[$i];
	while ($i-- > 1) {
	    if (substr($lines[$i], 0, 1) eq " ") {
		$lines[$i] = $nokid . $lines[$i];
	    } else {
		$lines[$i] = $kid . $lines[$i];
	    }
	}
	$lines[$i] = $kids . $lines[$i];
    } else {
	$lines[0] = $single . $lines[0];
    }
    return("$name$lead" . shift @lines,
           map(" " x (length($name)+$size) . $_, @lines));
}





 #^ smallest OP sequence number should be 1
 #                         ^ smallest COP sequence number should be 1


my $cop_seq_mnum = $^O eq 'MacOS' ? 12 : 11;
$cop_seq_base = svref_2object(eval 'sub{0;}')->START->cop_seq + $cop_seq_mnum;

1;

__END__

