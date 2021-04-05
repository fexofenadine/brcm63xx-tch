package ExtUtils::Constant;
use vars qw (@ISA $VERSION @EXPORT_OK %EXPORT_TAGS);
$VERSION = 0.23;


if ($] >= 5.006) {
  eval "use warnings; 1" or die $@;
}
use strict;
use Carp qw(croak cluck);

use Exporter;
use ExtUtils::Constant::Utils qw(C_stringify);
use ExtUtils::Constant::XS qw(%XS_Constant %XS_TypeSet);

@ISA = 'Exporter';

%EXPORT_TAGS = ( 'all' => [ qw(
	XS_constant constant_types return_clause memEQ_clause C_stringify
	C_constant autoload WriteConstants WriteMakefileSnippet
) ] );

@EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );


sub constant_types {
  ExtUtils::Constant::XS->header();
}

sub memEQ_clause {
  cluck "ExtUtils::Constant::memEQ_clause is deprecated";
  ExtUtils::Constant::XS->memEQ_clause({name=>$_[0], checked_at=>$_[1],
					indent=>$_[2]});
}

sub return_clause ($$) {
  cluck "ExtUtils::Constant::return_clause is deprecated";
  my $indent = shift;
  ExtUtils::Constant::XS->return_clause({indent=>$indent}, @_);
}

sub switch_clause {
  cluck "ExtUtils::Constant::switch_clause is deprecated";
  my $indent = shift;
  my $comment = shift;
  ExtUtils::Constant::XS->switch_clause({indent=>$indent, comment=>$comment},
					@_);
}

sub C_constant {
  my ($package, $subname, $default_type, $what, $indent, $breakout, @items)
    = @_;
  ExtUtils::Constant::XS->C_constant({package => $package, subname => $subname,
				      default_type => $default_type,
				      types => $what, indent => $indent,
				      breakout => $breakout}, @items);
}


sub XS_constant {
  my $package = shift;
  my $what = shift;
  my $XS_subname = shift;
  my $C_subname = shift;
  $XS_subname ||= 'constant';
  $C_subname ||= $XS_subname;

  if (!ref $what) {
    # Convert line of the form IV,UV,NV to hash
    $what = {map {$_ => 1} split /,\s*/, ($what)};
  }
  my $params = ExtUtils::Constant::XS->params ($what);
  my $type;

  my $xs = <<"EOT";
void
$XS_subname(sv)
    PREINIT:
	dXSTARG; /* Faster if we have it.  */
	dTARGET;
	STRLEN		len;
        int		type;
EOT

  if ($params->{IV}) {
    $xs .= "	IV		iv;\n";
  } else {
    $xs .= "	/* IV\t\tiv;\tUncomment this if you need to return IVs */\n";
  }
  if ($params->{NV}) {
    $xs .= "	NV		nv;\n";
  } else {
    $xs .= "	/* NV\t\tnv;\tUncomment this if you need to return NVs */\n";
  }
  if ($params->{PV}) {
    $xs .= "	const char	*pv;\n";
  } else {
    $xs .=
      "	/* const char\t*pv;\tUncomment this if you need to return PVs */\n";
  }

  $xs .= << 'EOT';
    INPUT:
	SV *		sv;
        const char *	s = SvPV(sv, len);
EOT
  if ($params->{''}) {
  $xs .= << 'EOT';
    INPUT:
	int		utf8 = SvUTF8(sv);
EOT
  }
  $xs .= << 'EOT';
    PPCODE:
EOT

  if ($params->{IV} xor $params->{NV}) {
    $xs .= << "EOT";
        /* Change this to $C_subname(aTHX_ s, len, &iv, &nv);
           if you need to return both NVs and IVs */
EOT
  }
  $xs .= "	type = $C_subname(aTHX_ s, len";
  $xs .= ', utf8' if $params->{''};
  $xs .= ', &iv' if $params->{IV};
  $xs .= ', &nv' if $params->{NV};
  $xs .= ', &pv' if $params->{PV};
  $xs .= ', &sv' if $params->{SV};
  $xs .= ");\n";

  # If anyone is insane enough to suggest a package name containing %
  my $package_sprintf_safe = $package;
  $package_sprintf_safe =~ s/%/%%/g;

  $xs .= << "EOT";
      /* Return 1 or 2 items. First is error message, or undef if no error.
           Second, if present, is found value */
        switch (type) {
        case PERL_constant_NOTFOUND:
          sv =
	    sv_2mortal(newSVpvf("%s is not a valid $package_sprintf_safe macro", s));
          PUSHs(sv);
          break;
        case PERL_constant_NOTDEF:
          sv = sv_2mortal(newSVpvf(
	    "Your vendor has not defined $package_sprintf_safe macro %s, used",
				   s));
          PUSHs(sv);
          break;
EOT

  foreach $type (sort keys %XS_Constant) {
    # '' marks utf8 flag needed.
    next if $type eq '';
    $xs .= "\t/* Uncomment this if you need to return ${type}s\n"
      unless $what->{$type};
    $xs .= "        case PERL_constant_IS$type:\n";
    if (length $XS_Constant{$type}) {
      $xs .= << "EOT";
          EXTEND(SP, 1);
          PUSHs(&PL_sv_undef);
          $XS_Constant{$type};
EOT
    } else {
      # Do nothing. return (), which will be correctly interpreted as
      # (undef, undef)
    }
    $xs .= "          break;\n";
    unless ($what->{$type}) {
      chop $xs; # Yes, another need for chop not chomp.
      $xs .= " */\n";
    }
  }
  $xs .= << "EOT";
        default:
          sv = sv_2mortal(newSVpvf(
	    "Unexpected return type %d while processing $package_sprintf_safe macro %s, used",
               type, s));
          PUSHs(sv);
        }
EOT

  return $xs;
}




sub autoload {
  my ($module, $compat_version, $autoloader) = @_;
  $compat_version ||= $];
  croak "Can't maintain compatibility back as far as version $compat_version"
    if $compat_version < 5;
  my $func = "sub AUTOLOAD {\n"
  . "    # This AUTOLOAD is used to 'autoload' constants from the constant()\n"
  . "    # XS function.";
  $func .= "  If a constant is not found then control is passed\n"
  . "    # to the AUTOLOAD in AutoLoader." if $autoloader;


  $func .= "\n\n"
  . "    my \$constname;\n";
  $func .=
    "    our \$AUTOLOAD;\n"  if ($compat_version >= 5.006);

  $func .= <<"EOT";
    (\$constname = \$AUTOLOAD) =~ s/.*:://;
    croak "&${module}::constant not defined" if \$constname eq 'constant';
    my (\$error, \$val) = constant(\$constname);
EOT

  if ($autoloader) {
    $func .= <<'EOT';
    if ($error) {
	if ($error =~  /is not a valid/) {
	    $AutoLoader::AUTOLOAD = $AUTOLOAD;
	    goto &AutoLoader::AUTOLOAD;
	} else {
	    croak $error;
	}
    }
EOT
  } else {
    $func .=
      "    if (\$error) { croak \$error; }\n";
  }

  $func .= <<'END';
    {
	no strict 'refs';
	# Fixed between 5.005_53 and 5.005_61
	    *$AUTOLOAD = sub { $val };
    }
    goto &$AUTOLOAD;
}

END

  return $func;
}



sub WriteMakefileSnippet {
  my %args = @_;
  my $indent = $args{INDENT} || 2;

  my $result = <<"EOT";
ExtUtils::Constant::WriteConstants(
                                   NAME         => '$args{NAME}',
                                   NAMES        => \\\@names,
                                   DEFAULT_TYPE => '$args{DEFAULT_TYPE}',
EOT
  foreach (qw (C_FILE XS_FILE)) {
    next unless exists $args{$_};
    $result .= sprintf "                                   %-12s => '%s',\n",
      $_, $args{$_};
  }
  $result .= <<'EOT';
                                );
EOT

  $result =~ s/^/' 'x$indent/gem;
  return ExtUtils::Constant::XS->dump_names({default_type=>$args{DEFAULT_TYPE},
					     indent=>$indent,},
					    @{$args{NAMES}})
    . $result;
}


sub WriteConstants {
  my %ARGS =
    ( # defaults
     C_FILE =>       'const-c.inc',
     XS_FILE =>      'const-xs.inc',
     XS_SUBNAME =>   'constant',
     DEFAULT_TYPE => 'IV',
     @_);

  $ARGS{C_SUBNAME} ||= $ARGS{XS_SUBNAME}; # No-one sane will have C_SUBNAME eq '0'

  croak "Module name not specified" unless length $ARGS{NAME};

  # Do this before creating (empty) files, in case it fails:
  require ExtUtils::Constant::ProxySubs if $ARGS{PROXYSUBS};

  my $c_fh = $ARGS{C_FH};
  if (!$c_fh) {
      if ($] <= 5.008) {
	  # We need these little games, rather than doing things
	  # unconditionally, because we're used in core Makefile.PLs before
	  # IO is available (needed by filehandle), but also we want to work on
	  # older perls where undefined scalars do not automatically turn into
	  # anonymous file handles.
	  require FileHandle;
	  $c_fh = FileHandle->new();
      }
      open $c_fh, ">$ARGS{C_FILE}" or die "Can't open $ARGS{C_FILE}: $!";
  }

  my $xs_fh = $ARGS{XS_FH};
  if (!$xs_fh) {
      if ($] <= 5.008) {
	  require FileHandle;
	  $xs_fh = FileHandle->new();
      }
      open $xs_fh, ">$ARGS{XS_FILE}" or die "Can't open $ARGS{XS_FILE}: $!";
  }

  # As this subroutine is intended to make code that isn't edited, there's no
  # need for the user to specify any types that aren't found in the list of
  # names.
  
  if ($ARGS{PROXYSUBS}) {
      $ARGS{C_FH} = $c_fh;
      $ARGS{XS_FH} = $xs_fh;
      ExtUtils::Constant::ProxySubs->WriteConstants(%ARGS);
  } else {
      my $types = {};

      print $c_fh constant_types(); # macro defs
      print $c_fh "\n";

      # indent is still undef. Until anyone implements indent style rules with
      # it.
      foreach (ExtUtils::Constant::XS->C_constant({package => $ARGS{NAME},
						   subname => $ARGS{C_SUBNAME},
						   default_type =>
						       $ARGS{DEFAULT_TYPE},
						       types => $types,
						       breakout =>
						       $ARGS{BREAKOUT_AT}},
						  @{$ARGS{NAMES}})) {
	  print $c_fh $_, "\n"; # C constant subs
      }
      print $xs_fh XS_constant ($ARGS{NAME}, $types, $ARGS{XS_SUBNAME},
				$ARGS{C_SUBNAME});
  }

  close $c_fh or warn "Error closing $ARGS{C_FILE}: $!" unless $ARGS{C_FH};
  close $xs_fh or warn "Error closing $ARGS{XS_FILE}: $!" unless $ARGS{XS_FH};
}

1;
__END__

