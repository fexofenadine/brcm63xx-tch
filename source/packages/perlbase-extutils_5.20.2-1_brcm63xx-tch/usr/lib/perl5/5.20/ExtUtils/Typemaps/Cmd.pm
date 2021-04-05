package ExtUtils::Typemaps::Cmd;
use 5.006001;
use strict;
use warnings;
our $VERSION = '3.24';

use ExtUtils::Typemaps;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(embeddable_typemap);
our %EXPORT_TAGS = (all => \@EXPORT);

sub embeddable_typemap {
  my @tms = @_;

  # Get typemap objects
  my @tm_objs = map [$_, _intuit_typemap_source($_)], @tms;

  # merge or short-circuit
  my $final_tm;
  if (@tm_objs == 1) {
    # just one, merge would be pointless
    $final_tm = shift(@tm_objs)->[1];
  }
  else {
    # multiple, need merge
    $final_tm = ExtUtils::Typemaps->new;
    foreach my $other_tm (@tm_objs) {
      my ($tm_ident, $tm_obj) = @$other_tm;
      eval {
        $final_tm->merge(typemap => $tm_obj);
        1
      } or do {
        my $err = $@ || 'Zombie error';
        die "Failed to merge typ";
      }
    }
  }

  # stringify for embedding
  return $final_tm->as_embedded_typemap();
}

sub _load_module {
  my $name = shift;
  return eval "require $name; 1";
}

SCOPE: {
  my %sources = (
    module => sub {
      my $ident = shift;
      my $tm;
      if (/::/) { # looks like FQ module name, try that first
        foreach my $module ($ident, "ExtUtils::Typemaps::$ident") {
          if (_load_module($module)) {
            eval { $tm = $module->new }
              and return $tm;
          }
        }
      }
      else {
        foreach my $module ("ExtUtils::Typemaps::$ident", "$ident") {
          if (_load_module($module)) {
            eval { $tm = $module->new }
              and return $tm;
          }
        }
      }
      return();
    },
    file => sub {
      my $ident = shift;
      return unless -e $ident and -r _;
      return ExtUtils::Typemaps->new(file => $ident);
    },
  );
  # Try to find typemap either from module or file
  sub _intuit_typemap_source {
    my $identifier = shift;

    my @locate_attempts;
    if ($identifier =~ /::/ || $identifier !~ /[^\w_]/) {
      @locate_attempts = qw(module file);
    }
    else {
      @locate_attempts = qw(file module);
    }

    foreach my $source (@locate_attempts) {
      my $tm = $sources{$source}->($identifier);
      return $tm if defined $tm;
    }

    die "Unable to find typemap for '$identifier': "
        . "Tried to load both as file or module and failed.\n";
  }
} # end SCOPE


1;

