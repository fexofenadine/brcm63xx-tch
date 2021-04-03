package Attribute::Handlers;
use 5.006;
use Carp;
use warnings;
use strict;
use vars qw($VERSION $AUTOLOAD);
$VERSION = '0.96'; # remember to update version in POD!

my %symcache;
sub findsym {
	my ($pkg, $ref, $type) = @_;
	return $symcache{$pkg,$ref} if $symcache{$pkg,$ref};
	$type ||= ref($ref);
	no strict 'refs';
        foreach my $sym ( values %{$pkg."::"} ) {
	    use strict;
	    next unless ref ( \$sym ) eq 'GLOB';
            return $symcache{$pkg,$ref} = \$sym
		if *{$sym}{$type} && *{$sym}{$type} == $ref;
	}
}

my %validtype = (
	VAR	=> [qw[SCALAR ARRAY HASH]],
        ANY	=> [qw[SCALAR ARRAY HASH CODE]],
        ""	=> [qw[SCALAR ARRAY HASH CODE]],
        SCALAR	=> [qw[SCALAR]],
        ARRAY	=> [qw[ARRAY]],
        HASH	=> [qw[HASH]],
        CODE	=> [qw[CODE]],
);
my %lastattr;
my @declarations;
my %raw;
my %phase;
my %sigil = (SCALAR=>'$', ARRAY=>'@', HASH=>'%');
my $global_phase = 0;
my %global_phases = (
	BEGIN	=> 0,
	CHECK	=> 1,
	INIT	=> 2,
	END	=> 3,
);
my @global_phases = qw(BEGIN CHECK INIT END);

sub _usage_AH_ {
	croak "Usage: use $_[0] autotie => {AttrName => TieClassName,...}";
}

my $qual_id = qr/^[_a-z]\w*(::[_a-z]\w*)*$/i;

sub import {
    my $class = shift @_;
    return unless $class eq "Attribute::Handlers";
    while (@_) {
	my $cmd = shift;
        if ($cmd =~ /^autotie((?:ref)?)$/) {
	    my $tiedata = ($1 ? '$ref, ' : '') . '@$data';
            my $mapping = shift;
	    _usage_AH_ $class unless ref($mapping) eq 'HASH';
	    while (my($attr, $tieclass) = each %$mapping) {
                $tieclass =~ s/^([_a-z]\w*(::[_a-z]\w*)*)(.*)/$1/is;
		my $args = $3||'()';
		_usage_AH_ $class unless $attr =~ $qual_id
		                 && $tieclass =~ $qual_id
		                 && eval "use base q\0$tieclass\0; 1";
	        if ($tieclass->isa('Exporter')) {
		    local $Exporter::ExportLevel = 2;
		    $tieclass->import(eval $args);
	        }
		$attr =~ s/__CALLER__/caller(1)/e;
		$attr = caller()."::".$attr unless $attr =~ /::/;
	        eval qq{
	            sub $attr : ATTR(VAR) {
			my (\$ref, \$data) = \@_[2,4];
			my \$was_arrayref = ref \$data eq 'ARRAY';
			\$data = [ \$data ] unless \$was_arrayref;
			my \$type = ref(\$ref)||"value (".(\$ref||"<undef>").")";
			 (\$type eq 'SCALAR')? tie \$\$ref,'$tieclass',$tiedata
			:(\$type eq 'ARRAY') ? tie \@\$ref,'$tieclass',$tiedata
			:(\$type eq 'HASH')  ? tie \%\$ref,'$tieclass',$tiedata
			: die "Can't autotie a \$type\n"
	            } 1
	        } or die "Internal error: $@";
	    }
        }
        else {
            croak "Can't understand $_"; 
        }
    }
}

BEGIN {
	my $delayed;
	sub Attribute::Handlers::_TEST_::MODIFY_CODE_ATTRIBUTES {
		$delayed = \&Attribute::Handlers::_TEST_::t != $_[1];
		return ();
	}
	sub Attribute::Handlers::_TEST_::t :T { }
	*_delayed_name_resolution = sub() { $delayed };
	undef &Attribute::Handlers::_TEST_::MODIFY_CODE_ATTRIBUTES;
	undef &Attribute::Handlers::_TEST_::t;
}

sub _resolve_lastattr {
	return unless $lastattr{ref};
	my $sym = findsym @lastattr{'pkg','ref'}
		or die "Internal error: $lastattr{pkg} symbol went missing";
	my $name = *{$sym}{NAME};
	warn "Declaration of $name attribute in package $lastattr{pkg} may clash with future reserved word\n"
		if $^W and $name !~ /[A-Z]/;
	foreach ( @{$validtype{$lastattr{type}}} ) {
		no strict 'refs';
		*{"$lastattr{pkg}::_ATTR_${_}_${name}"} = $lastattr{ref};
	}
	%lastattr = ();
}

sub AUTOLOAD {
	return if $AUTOLOAD =~ /::DESTROY$/;
	my ($class) = $AUTOLOAD =~ m/(.*)::/g;
	$AUTOLOAD =~ m/_ATTR_(.*?)_(.*)/ or
	    croak "Can't locate class method '$AUTOLOAD' via package '$class'";
	croak "Attribute handler '$2' doesn't handle $1 attributes";
}

my $builtin = qr/lvalue|method|locked|unique|shared/;

sub _gen_handler_AH_() {
	return sub {
	    _resolve_lastattr if _delayed_name_resolution;
	    my ($pkg, $ref, @attrs) = @_;
	    my (undef, $filename, $linenum) = caller 2;
	    foreach (@attrs) {
		my ($attr, $data) = /^([a-z_]\w*)(?:[(](.*)[)])?$/is or next;
		if ($attr eq 'ATTR') {
			no strict 'refs';
			$data ||= "ANY";
			$raw{$ref} = $data =~ s/\s*,?\s*RAWDATA\s*,?\s*//;
			$phase{$ref}{BEGIN} = 1
				if $data =~ s/\s*,?\s*(BEGIN)\s*,?\s*//;
			$phase{$ref}{INIT} = 1
				if $data =~ s/\s*,?\s*(INIT)\s*,?\s*//;
			$phase{$ref}{END} = 1
				if $data =~ s/\s*,?\s*(END)\s*,?\s*//;
			$phase{$ref}{CHECK} = 1
				if $data =~ s/\s*,?\s*(CHECK)\s*,?\s*//
				|| ! keys %{$phase{$ref}};
			# Added for cleanup to not pollute next call.
			(%lastattr = ()),
			croak "Can't have two ATTR specifiers on one subroutine"
				if keys %lastattr;
			croak "Bad attribute type: ATTR($data)"
				unless $validtype{$data};
			%lastattr=(pkg=>$pkg,ref=>$ref,type=>$data);
			_resolve_lastattr unless _delayed_name_resolution;
		}
		else {
			my $type = ref $ref;
			my $handler = $pkg->can("_ATTR_${type}_${attr}");
			next unless $handler;
		        my $decl = [$pkg, $ref, $attr, $data,
				    $raw{$handler}, $phase{$handler}, $filename, $linenum];
			foreach my $gphase (@global_phases) {
			    _apply_handler_AH_($decl,$gphase)
				if $global_phases{$gphase} <= $global_phase;
			}
			if ($global_phase != 0) {
				# if _gen_handler_AH_ is being called after 
				# CHECK it's for a lexical, so make sure
				# it didn't want to run anything later
			
				local $Carp::CarpLevel = 2;
				carp "Won't be able to apply END handler"
					if $phase{$handler}{END};
			}
			else {
				push @declarations, $decl
			}
		}
		$_ = undef;
	    }
	    return grep {defined && !/$builtin/} @attrs;
	}
}

{
    no strict 'refs';
    *{"Attribute::Handlers::UNIVERSAL::MODIFY_${_}_ATTRIBUTES"} =
	_gen_handler_AH_ foreach @{$validtype{ANY}};
}
push @UNIVERSAL::ISA, 'Attribute::Handlers::UNIVERSAL'
       unless grep /^Attribute::Handlers::UNIVERSAL$/, @UNIVERSAL::ISA;

sub _apply_handler_AH_ {
	my ($declaration, $phase) = @_;
	my ($pkg, $ref, $attr, $data, $raw, $handlerphase, $filename, $linenum) = @$declaration;
	return unless $handlerphase->{$phase};
	# print STDERR "Handling $attr on $ref in $phase with [$data]\n";
	my $type = ref $ref;
	my $handler = "_ATTR_${type}_${attr}";
	my $sym = findsym($pkg, $ref);
	$sym ||= $type eq 'CODE' ? 'ANON' : 'LEXICAL';
	no warnings;
	if (!$raw && defined($data)) {
	    if ($data ne '') {
		my $evaled = eval("package $pkg; no warnings; no strict;
				   local \$SIG{__WARN__}=sub{die}; [$data]");
		$data = $evaled unless $@;
	    }
	    else { $data = undef }
	}
	$pkg->$handler($sym,
		       (ref $sym eq 'GLOB' ? *{$sym}{ref $ref}||$ref : $ref),
		       $attr,
		       $data,
		       $phase,
		       $filename,
		       $linenum,
		      );
	return 1;
}

{
        no warnings 'void';
        CHECK {
                $global_phase++;
                _resolve_lastattr if _delayed_name_resolution;
                foreach my $decl (@declarations) {
                        _apply_handler_AH_($decl, 'CHECK');
                }
        }

        INIT {
                $global_phase++;
                foreach my $decl (@declarations) {
                        _apply_handler_AH_($decl, 'INIT');
                }
        }
}

END {
        $global_phase++;
        foreach my $decl (@declarations) {
                _apply_handler_AH_($decl, 'END');
        }
}

1;
__END__

