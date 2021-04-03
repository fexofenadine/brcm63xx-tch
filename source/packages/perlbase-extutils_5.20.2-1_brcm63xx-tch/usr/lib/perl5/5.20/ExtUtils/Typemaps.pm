package ExtUtils::Typemaps;
use 5.006001;
use strict;
use warnings;
our $VERSION = '3.24';

require ExtUtils::ParseXS;
require ExtUtils::ParseXS::Constants;
require ExtUtils::Typemaps::InputMap;
require ExtUtils::Typemaps::OutputMap;
require ExtUtils::Typemaps::Type;



sub new {
  my $class = shift;
  my %args = @_;

  if (defined $args{file} and defined $args{string}) {
    die("Cannot handle both 'file' and 'string' arguments to constructor");
  }

  my $self = bless {
    file            => undef,
    %args,
    typemap_section => [],
    typemap_lookup  => {},
    input_section   => [],
    input_lookup    => {},
    output_section  => [],
    output_lookup   => {},
  } => $class;

  $self->_init();

  return $self;
}

sub _init {
  my $self = shift;
  if (defined $self->{string}) {
    $self->_parse(\($self->{string}), $self->{lineno_offset}, $self->{fake_filename});
    delete $self->{string};
  }
  elsif (defined $self->{file} and -e $self->{file}) {
    open my $fh, '<', $self->{file}
      or die "Cannot open typemap file '"
             . $self->{file} . "' for reading: $!";
    local $/ = undef;
    my $string = <$fh>;
    $self->_parse(\$string, $self->{lineno_offset}, $self->{file});
  }
}



sub file {
  $_[0]->{file} = $_[1] if @_ > 1;
  $_[0]->{file}
}


sub add_typemap {
  my $self = shift;
  my $type;
  my %args;

  if ((@_ % 2) == 1) {
    my $orig = shift;
    $type = $orig->new();
    %args = @_;
  }
  else {
    %args = @_;
    my $ctype = $args{ctype};
    die("Need ctype argument") if not defined $ctype;
    my $xstype = $args{xstype};
    die("Need xstype argument") if not defined $xstype;

    $type = ExtUtils::Typemaps::Type->new(
      xstype      => $xstype,
      'prototype' => $args{'prototype'},
      ctype       => $ctype,
    );
  }

  if ($args{skip} and $args{replace}) {
    die("Cannot use both 'skip' and 'replace'");
  }

  if ($args{replace}) {
    $self->remove_typemap(ctype => $type->ctype);
  }
  elsif ($args{skip}) {
    return() if exists $self->{typemap_lookup}{$type->ctype};
  }
  else {
    $self->validate(typemap_xstype => $type->xstype, ctype => $type->ctype);
  }

  # store
  push @{$self->{typemap_section}}, $type;
  # remember type for lookup, too.
  $self->{typemap_lookup}{$type->tidy_ctype} = $#{$self->{typemap_section}};

  return 1;
}


sub add_inputmap {
  my $self = shift;
  my $input;
  my %args;

  if ((@_ % 2) == 1) {
    my $orig = shift;
    $input = $orig->new();
    %args = @_;
  }
  else {
    %args = @_;
    my $xstype = $args{xstype};
    die("Need xstype argument") if not defined $xstype;
    my $code = $args{code};
    die("Need code argument") if not defined $code;

    $input = ExtUtils::Typemaps::InputMap->new(
      xstype => $xstype,
      code   => $code,
    );
  }

  if ($args{skip} and $args{replace}) {
    die("Cannot use both 'skip' and 'replace'");
  }

  if ($args{replace}) {
    $self->remove_inputmap(xstype => $input->xstype);
  }
  elsif ($args{skip}) {
    return() if exists $self->{input_lookup}{$input->xstype};
  }
  else {
    $self->validate(inputmap_xstype => $input->xstype);
  }

  # store
  push @{$self->{input_section}}, $input;
  # remember type for lookup, too.
  $self->{input_lookup}{$input->xstype} = $#{$self->{input_section}};

  return 1;
}


sub add_outputmap {
  my $self = shift;
  my $output;
  my %args;

  if ((@_ % 2) == 1) {
    my $orig = shift;
    $output = $orig->new();
    %args = @_;
  }
  else {
    %args = @_;
    my $xstype = $args{xstype};
    die("Need xstype argument") if not defined $xstype;
    my $code = $args{code};
    die("Need code argument") if not defined $code;

    $output = ExtUtils::Typemaps::OutputMap->new(
      xstype => $xstype,
      code   => $code,
    );
  }

  if ($args{skip} and $args{replace}) {
    die("Cannot use both 'skip' and 'replace'");
  }

  if ($args{replace}) {
    $self->remove_outputmap(xstype => $output->xstype);
  }
  elsif ($args{skip}) {
    return() if exists $self->{output_lookup}{$output->xstype};
  }
  else {
    $self->validate(outputmap_xstype => $output->xstype);
  }

  # store
  push @{$self->{output_section}}, $output;
  # remember type for lookup, too.
  $self->{output_lookup}{$output->xstype} = $#{$self->{output_section}};

  return 1;
}


sub add_string {
  my $self = shift;
  my %args = @_;
  die("Need 'string' argument") if not defined $args{string};

  # no, this is not elegant.
  my $other = ExtUtils::Typemaps->new(string => $args{string});
  $self->merge(typemap => $other);
}


sub remove_typemap {
  my $self = shift;
  my $ctype;
  if (@_ > 1) {
    my %args = @_;
    $ctype = $args{ctype};
    die("Need ctype argument") if not defined $ctype;
    $ctype = tidy_type($ctype);
  }
  else {
    $ctype = $_[0]->tidy_ctype;
  }

  return $self->_remove($ctype, $self->{typemap_section}, $self->{typemap_lookup});
}


sub remove_inputmap {
  my $self = shift;
  my $xstype;
  if (@_ > 1) {
    my %args = @_;
    $xstype = $args{xstype};
    die("Need xstype argument") if not defined $xstype;
  }
  else {
    $xstype = $_[0]->xstype;
  }
  
  return $self->_remove($xstype, $self->{input_section}, $self->{input_lookup});
}


sub remove_outputmap {
  my $self = shift;
  my $xstype;
  if (@_ > 1) {
    my %args = @_;
    $xstype = $args{xstype};
    die("Need xstype argument") if not defined $xstype;
  }
  else {
    $xstype = $_[0]->xstype;
  }
  
  return $self->_remove($xstype, $self->{output_section}, $self->{output_lookup});
}

sub _remove {
  my $self   = shift;
  my $rm     = shift;
  my $array  = shift;
  my $lookup = shift;

  # Just fetch the index of the item from the lookup table
  my $index = $lookup->{$rm};
  return() if not defined $index;

  # Nuke the item from storage
  splice(@$array, $index, 1);

  # Decrement the storage position of all items thereafter
  foreach my $key (keys %$lookup) {
    if ($lookup->{$key} > $index) {
      $lookup->{$key}--;
    }
  }
  return();
}


sub get_typemap {
  my $self = shift;
  die("Need named parameters, got uneven number") if @_ % 2;

  my %args = @_;
  my $ctype = $args{ctype};
  die("Need ctype argument") if not defined $ctype;
  $ctype = tidy_type($ctype);

  my $index = $self->{typemap_lookup}{$ctype};
  return() if not defined $index;
  return $self->{typemap_section}[$index];
}


sub get_inputmap {
  my $self = shift;
  die("Need named parameters, got uneven number") if @_ % 2;

  my %args = @_;
  my $xstype = $args{xstype};
  my $ctype  = $args{ctype};
  die("Need xstype or ctype argument")
    if not defined $xstype
    and not defined $ctype;
  die("Need xstype OR ctype arguments, not both")
    if defined $xstype and defined $ctype;

  if (defined $ctype) {
    my $tm = $self->get_typemap(ctype => $ctype);
    $xstype = $tm && $tm->xstype;
    return() if not defined $xstype;
  }

  my $index = $self->{input_lookup}{$xstype};
  return() if not defined $index;
  return $self->{input_section}[$index];
}


sub get_outputmap {
  my $self = shift;
  die("Need named parameters, got uneven number") if @_ % 2;

  my %args = @_;
  my $xstype = $args{xstype};
  my $ctype  = $args{ctype};
  die("Need xstype or ctype argument")
    if not defined $xstype
    and not defined $ctype;
  die("Need xstype OR ctype arguments, not both")
    if defined $xstype and defined $ctype;

  if (defined $ctype) {
    my $tm = $self->get_typemap(ctype => $ctype);
    $xstype = $tm && $tm->xstype;
    return() if not defined $xstype;
  }

  my $index = $self->{output_lookup}{$xstype};
  return() if not defined $index;
  return $self->{output_section}[$index];
}


sub write {
  my $self = shift;
  my %args = @_;
  my $file = defined $args{file} ? $args{file} : $self->file();
  die("write() needs a file argument (or set the file name of the typemap using the 'file' method)")
    if not defined $file;

  open my $fh, '>', $file
    or die "Cannot open typemap file '$file' for writing: $!";
  print $fh $self->as_string();
  close $fh;
}


sub as_string {
  my $self = shift;
  my $typemap = $self->{typemap_section};
  my @code;
  push @code, "TYPEMAP\n";
  foreach my $entry (@$typemap) {
    # type kind proto
    # /^(.*?\S)\s+(\S+)\s*($ExtUtils::ParseXS::Constants::PrototypeRegexp*)$/o
    push @code, $entry->ctype . "\t" . $entry->xstype
              . ($entry->proto ne '' ? "\t".$entry->proto : '') . "\n";
  }

  my $input = $self->{input_section};
  if (@$input) {
    push @code, "\nINPUT\n";
    foreach my $entry (@$input) {
      push @code, $entry->xstype, "\n", $entry->code, "\n";
    }
  }

  my $output = $self->{output_section};
  if (@$output) {
    push @code, "\nOUTPUT\n";
    foreach my $entry (@$output) {
      push @code, $entry->xstype, "\n", $entry->code, "\n";
    }
  }
  return join '', @code;
}


sub as_embedded_typemap {
  my $self = shift;
  my $string = $self->as_string;

  my @ident_cand = qw(END_TYPEMAP END_OF_TYPEMAP END);
  my $icand = 0;
  my $cand_suffix = "";
  while ($string =~ /^\Q$ident_cand[$icand]$cand_suffix\E\s*$/m) {
    $icand++;
    if ($icand == @ident_cand) {
      $icand = 0;
      ++$cand_suffix;
    }
  }

  my $marker = "$ident_cand[$icand]$cand_suffix";
  return "TYPEMAP: <<$marker;\n$string\n$marker\n";
}


sub merge {
  my $self = shift;
  my %args = @_;

  if (exists $args{typemap} and exists $args{file}) {
    die("Need {file} OR {typemap} argument. Not both!");
  }
  elsif (not exists $args{typemap} and not exists $args{file}) {
    die("Need {file} or {typemap} argument!");
  }

  my @params;
  push @params, 'replace' => $args{replace} if exists $args{replace};
  push @params, 'skip' => $args{skip} if exists $args{skip};

  my $typemap = $args{typemap};
  if (not defined $typemap) {
    $typemap = ref($self)->new(file => $args{file}, @params);
  }

  # FIXME breaking encapsulation. Add accessor code.
  foreach my $entry (@{$typemap->{typemap_section}}) {
    $self->add_typemap( $entry, @params );
  }

  foreach my $entry (@{$typemap->{input_section}}) {
    $self->add_inputmap( $entry, @params );
  }

  foreach my $entry (@{$typemap->{output_section}}) {
    $self->add_outputmap( $entry, @params );
  }

  return 1;
}


sub is_empty {
  my $self = shift;

  return @{ $self->{typemap_section} } == 0
      && @{ $self->{input_section} } == 0
      && @{ $self->{output_section} } == 0;
}


sub list_mapped_ctypes {
  my $self = shift;
  return sort keys %{ $self->{typemap_lookup} };
}


sub _get_typemap_hash {
  my $self = shift;
  my $lookup  = $self->{typemap_lookup};
  my $storage = $self->{typemap_section};

  my %rv;
  foreach my $ctype (keys %$lookup) {
    $rv{$ctype} = $storage->[ $lookup->{$ctype} ]->xstype;
  }

  return \%rv;
}


sub _get_inputmap_hash {
  my $self = shift;
  my $lookup  = $self->{input_lookup};
  my $storage = $self->{input_section};

  my %rv;
  foreach my $xstype (keys %$lookup) {
    $rv{$xstype} = $storage->[ $lookup->{$xstype} ]->code;

    # Squash trailing whitespace to one line break
    # This isn't strictly necessary, but makes the output more similar
    # to the original ExtUtils::ParseXS.
    $rv{$xstype} =~ s/\s*\z/\n/;
  }

  return \%rv;
}



sub _get_outputmap_hash {
  my $self = shift;
  my $lookup  = $self->{output_lookup};
  my $storage = $self->{output_section};

  my %rv;
  foreach my $xstype (keys %$lookup) {
    $rv{$xstype} = $storage->[ $lookup->{$xstype} ]->code;

    # Squash trailing whitespace to one line break
    # This isn't strictly necessary, but makes the output more similar
    # to the original ExtUtils::ParseXS.
    $rv{$xstype} =~ s/\s*\z/\n/;
  }

  return \%rv;
}


sub _get_prototype_hash {
  my $self = shift;
  my $lookup  = $self->{typemap_lookup};
  my $storage = $self->{typemap_section};

  my %rv;
  foreach my $ctype (keys %$lookup) {
    $rv{$ctype} = $storage->[ $lookup->{$ctype} ]->proto || '$';
  }

  return \%rv;
}



sub validate {
  my $self = shift;
  my %args = @_;

  if ( exists $args{ctype}
       and exists $self->{typemap_lookup}{tidy_type($args{ctype})} )
  {
    die("Multiple definition of ctype '$args{ctype}' in TYPEMAP section");
  }

  if ( exists $args{inputmap_xstype}
       and exists $self->{input_lookup}{$args{inputmap_xstype}} )
  {
    die("Multiple definition of xstype '$args{inputmap_xstype}' in INPUTMAP section");
  }

  if ( exists $args{outputmap_xstype}
       and exists $self->{output_lookup}{$args{outputmap_xstype}} )
  {
    die("Multiple definition of xstype '$args{outputmap_xstype}' in OUTPUTMAP section");
  }

  return 1;
}


sub clone {
  my $proto = shift;
  my %args = @_;

  my $self;
  if ($args{shallow}) {
    $self = bless( {
      %$proto,
      typemap_section => [@{$proto->{typemap_section}}],
      typemap_lookup  => {%{$proto->{typemap_lookup}}},
      input_section   => [@{$proto->{input_section}}],
      input_lookup    => {%{$proto->{input_lookup}}},
      output_section  => [@{$proto->{output_section}}],
      output_lookup   => {%{$proto->{output_lookup}}},
    } => ref($proto) );
  }
  else {
    $self = bless( {
      %$proto,
      typemap_section => [map $_->new, @{$proto->{typemap_section}}],
      typemap_lookup  => {%{$proto->{typemap_lookup}}},
      input_section   => [map $_->new, @{$proto->{input_section}}],
      input_lookup    => {%{$proto->{input_lookup}}},
      output_section  => [map $_->new, @{$proto->{output_section}}],
      output_lookup   => {%{$proto->{output_lookup}}},
    } => ref($proto) );
  }

  return $self;
}


sub tidy_type {
  local $_ = shift;

  # for templated C++ types, do some bit of flawed canonicalization
  # wrt. templates at least
  if (/[<>]/) {
    s/\s*([<>])\s*/$1/g;
    s/>>/> >/g;
  }

  # rationalise any '*' by joining them into bunches and removing whitespace
  s#\s*(\*+)\s*#$1#g;
  s#(\*+)# $1 #g ;

  # trim leading & trailing whitespace
  s/^\s+//; s/\s+$//;

  # change multiple whitespace into a single space
  s/\s+/ /g;

  $_;
}



sub _parse {
  my $self = shift;
  my $stringref = shift;
  my $lineno_offset = shift;
  $lineno_offset = 0 if not defined $lineno_offset;
  my $filename = shift;
  $filename = '<string>' if not defined $filename;

  my $replace = $self->{replace};
  my $skip    = $self->{skip};
  die "Can only replace OR skip" if $replace and $skip;
  my @add_params;
  push @add_params, replace => 1 if $replace;
  push @add_params, skip    => 1 if $skip;

  # TODO comments should round-trip, currently ignoring
  # TODO order of sections, multiple sections of same type
  # Heavily influenced by ExtUtils::ParseXS
  my $section = 'typemap';
  my $lineno = $lineno_offset;
  my $junk = "";
  my $current = \$junk;
  my @input_expr;
  my @output_expr;
  while ($$stringref =~ /^(.*)$/gcm) {
    local $_ = $1;
    ++$lineno;
    chomp;
    next if /^\s*#/;
    if (/^INPUT\s*$/) {
      $section = 'input';
      $current = \$junk;
      next;
    }
    elsif (/^OUTPUT\s*$/) {
      $section = 'output';
      $current = \$junk;
      next;
    }
    elsif (/^TYPEMAP\s*$/) {
      $section = 'typemap';
      $current = \$junk;
      next;
    }
    
    if ($section eq 'typemap') {
      my $line = $_;
      s/^\s+//; s/\s+$//;
      next if $_ eq '' or /^#/;
      my($type, $kind, $proto) = /^(.*?\S)\s+(\S+)\s*($ExtUtils::ParseXS::Constants::PrototypeRegexp*)$/o
        or warn("Warning: File '$filename' Line $lineno '$line' TYPEMAP entry needs 2 or 3 columns\n"),
           next;
      # prototype defaults to '$'
      $proto = '$' unless $proto;
      warn("Warning: File '$filename' Line $lineno '$line' Invalid prototype '$proto'\n")
        unless _valid_proto_string($proto);
      $self->add_typemap(
        ExtUtils::Typemaps::Type->new(
          xstype => $kind, proto => $proto, ctype => $type
        ),
        @add_params
      );
    } elsif (/^\s/) {
      s/\s+$//;
      $$current .= $$current eq '' ? $_ : "\n".$_;
    } elsif ($_ eq '') {
      next;
    } elsif ($section eq 'input') {
      s/\s+$//;
      push @input_expr, {xstype => $_, code => ''};
      $current = \$input_expr[-1]{code};
    } else { # output section
      s/\s+$//;
      push @output_expr, {xstype => $_, code => ''};
      $current = \$output_expr[-1]{code};
    }

  } # end while lines

  foreach my $inexpr (@input_expr) {
    $self->add_inputmap( ExtUtils::Typemaps::InputMap->new(%$inexpr), @add_params );
  }
  foreach my $outexpr (@output_expr) {
    $self->add_outputmap( ExtUtils::Typemaps::OutputMap->new(%$outexpr), @add_params );
  }

  return 1;
}

sub _valid_proto_string {
  my $string = shift;
  if ($string =~ /^$ExtUtils::ParseXS::Constants::PrototypeRegexp+$/o) {
    return $string;
  }

  return 0 ;
}

sub _escape_backslashes {
  my $string = shift;
  $string =~ s[\\][\\\\]g;
  $string;
}


1;

