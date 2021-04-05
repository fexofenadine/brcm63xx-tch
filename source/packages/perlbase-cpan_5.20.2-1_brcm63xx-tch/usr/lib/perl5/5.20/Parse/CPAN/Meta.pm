use 5.008001;
use strict;
package Parse::CPAN::Meta;
our $VERSION = '1.4414'; # VERSION

use Exporter;
use Carp 'croak';

our @ISA = qw/Exporter/;
our @EXPORT_OK = qw/Load LoadFile/;

sub load_file {
  my ($class, $filename) = @_;

  my $meta = _slurp($filename);

  if ($filename =~ /\.ya?ml$/) {
    return $class->load_yaml_string($meta);
  }
  elsif ($filename =~ /\.json$/) {
    return $class->load_json_string($meta);
  }
  else {
    $class->load_string($meta); # try to detect yaml/json
  }
}

sub load_string {
  my ($class, $string) = @_;
  if ( $string =~ /^---/ ) { # looks like YAML
    return $class->load_yaml_string($string);
  }
  elsif ( $string =~ /^\s*\{/ ) { # looks like JSON
    return $class->load_json_string($string);
  }
  else { # maybe doc-marker-free YAML
    return $class->load_yaml_string($string);
  }
}

sub load_yaml_string {
  my ($class, $string) = @_;
  my $backend = $class->yaml_backend();
  my $data = eval { no strict 'refs'; &{"$backend\::Load"}($string) };
  croak $@ if $@;
  return $data || {}; # in case document was valid but empty
}

sub load_json_string {
  my ($class, $string) = @_;
  my $data = eval { $class->json_backend()->new->decode($string) };
  croak $@ if $@;
  return $data || {};
}

sub yaml_backend {
  if (! defined $ENV{PERL_YAML_BACKEND} ) {
    _can_load( 'CPAN::Meta::YAML', 0.011 )
      or croak "CPAN::Meta::YAML 0.011 is not available\n";
    return "CPAN::Meta::YAML";
  }
  else {
    my $backend = $ENV{PERL_YAML_BACKEND};
    _can_load( $backend )
      or croak "Could not load PERL_YAML_BACKEND '$backend'\n";
    $backend->can("Load")
      or croak "PERL_YAML_BACKEND '$backend' does not implement Load()\n";
    return $backend;
  }
}

sub json_backend {
  if (! $ENV{PERL_JSON_BACKEND} or $ENV{PERL_JSON_BACKEND} eq 'JSON::PP') {
    _can_load( 'JSON::PP' => 2.27103 )
      or croak "JSON::PP 2.27103 is not available\n";
    return 'JSON::PP';
  }
  else {
    _can_load( 'JSON' => 2.5 )
      or croak  "JSON 2.5 is required for " .
                "\$ENV{PERL_JSON_BACKEND} = '$ENV{PERL_JSON_BACKEND}'\n";
    return "JSON";
  }
}

sub _slurp {
  require Encode;
  open my $fh, "<:raw", "$_[0]" ## no critic
    or die "can't open $_[0] for reading: $!";
  my $content = do { local $/; <$fh> };
  $content = Encode::decode('UTF-8', $content, Encode::PERLQQ());
  return $content;
}
  
sub _can_load {
  my ($module, $version) = @_;
  (my $file = $module) =~ s{::}{/}g;
  $file .= ".pm";
  return 1 if $INC{$file};
  return 0 if exists $INC{$file}; # prior load failed
  eval { require $file; 1 }
    or return 0;
  if ( defined $version ) {
    eval { $module->VERSION($version); 1 }
      or return 0;
  }
  return 1;
}

sub LoadFile ($) {
  return Load(_slurp(shift));
}

sub Load ($) {
  require CPAN::Meta::YAML;
  my $object = eval { CPAN::Meta::YAML::Load(shift) };
  croak $@ if $@;
  return $object;
}

1;

__END__

