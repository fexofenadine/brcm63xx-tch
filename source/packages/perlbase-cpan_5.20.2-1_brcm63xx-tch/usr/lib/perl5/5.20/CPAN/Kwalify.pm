

use strict;

package CPAN::Kwalify;
use vars qw($VERSION $VAR1);
$VERSION = "5.50";

use File::Spec ();

my %vcache = ();

my $schema_loaded = {};

sub _validate {
    my($schema_name,$data,$abs,$y) = @_;
    my $yaml_module = CPAN->_yaml_module;
    if (
        $CPAN::META->has_inst($yaml_module)
        &&
        $CPAN::META->has_inst("Kwalify")
       ) {
        my $load = UNIVERSAL::can($yaml_module,"Load");
        unless ($schema_loaded->{$schema_name}) {
            eval {
                my $schema_yaml = yaml($schema_name);
                $schema_loaded->{$schema_name} = $load->($schema_yaml);
            };
            if ($@) {
                # we know that YAML.pm 0.62 cannot parse the schema,
                # so we try a fallback
                my $content = do {
                    my $path = __FILE__;
                    $path =~ s/\.pm$//;
                    $path = File::Spec->catfile($path, "$schema_name.dd");
                    local *FH;
                    open FH, $path or die "Could not open '$path': $!";
                    local $/;
                    <FH>;
                };
                $VAR1 = undef;
                eval $content;
                if (my $err = $@) {
                    die "parsing of '$schema_name.dd' failed: $err";
                }
                $schema_loaded->{$schema_name} = $VAR1;
            }
        }
    }
    if (my $schema = $schema_loaded->{$schema_name}) {
        my $mtime = (stat $abs)[9];
        for my $k (keys %{$vcache{$abs}}) {
            delete $vcache{$abs}{$k} unless $k eq $mtime;
        }
        return if $vcache{$abs}{$mtime}{$y}++;
        eval { Kwalify::validate($schema, $data) };
        if (my $err = $@) {
            my $info = {}; yaml($schema_name, info => $info);
            die "validation of distropref '$abs'[$y] against schema '$info->{path}' failed: $err";
        }
    }
}

sub _clear_cache {
    %vcache = ();
}

sub yaml {
    my($schema_name, %opt) = @_;
    my $content = do {
        my $path = __FILE__;
        $path =~ s/\.pm$//;
        $path = File::Spec->catfile($path, "$schema_name.yml");
        if ($opt{info}) {
            $opt{info}{path} = $path;
        }
        local *FH;
        open FH, $path or die "Could not open '$path': $!";
        local $/;
        <FH>;
    };
    return $content;
}

1;


