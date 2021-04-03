
package CPAN::Mirrors;
use strict;
use vars qw($VERSION $urllist $silent);
$VERSION = "1.9601";

use Carp;
use FileHandle;
use Fcntl ":flock";
use Net::Ping ();


sub new {
    my ($class, $file) = @_;
    croak "CPAN::Mirrors->new requires a filename" unless defined $file;
    croak "The file [$file] was not found" unless -e $file;

    my $self = bless {
        mirrors      => [],
        geography    => {},
    }, $class;

    $self->parse_mirrored_by( $file );

    return $self;
}

sub parse_mirrored_by {
    my ($self, $file) = @_;
    my $handle = FileHandle->new;
    $handle->open($file)
        or croak "Couldn't open $file: $!";
    flock $handle, LOCK_SH;
    $self->_parse($file,$handle);
    flock $handle, LOCK_UN;
    $handle->close;
}


sub continents {
    my ($self) = @_;
    return keys %{$self->{geography}};
}


sub countries {
    my ($self, @continents) = @_;
    @continents = $self->continents unless @continents;
    my @countries;
    for my $c (@continents) {
        push @countries, keys %{ $self->{geography}{$c} };
    }
    return @countries;
}


sub mirrors {
    my ($self, @countries) = @_;
    return @{$self->{mirrors}} unless @countries;
    my %wanted = map { $_ => 1 } @countries;
    my @found;
    for my $m (@{$self->{mirrors}}) {
        push @found, $m if exists $wanted{$m->country};
    }
    return @found;
}


sub get_mirrors_by_countries { &mirrors }


sub get_mirrors_by_continents {
    my ($self, $continents ) = @_;
    $continents = [ $continents ] unless ref $continents;

    eval {
        $self->mirrors( $self->get_countries_by_continents( @$continents ) );
        };
    }


sub get_countries_by_continents { &countries }


sub default_mirror { 'http://www.cpan.org/' }


sub best_mirrors {
    my ($self, %args) = @_;
    my $how_many      = $args{how_many} || 1;
    my $callback      = $args{callback};
    my $verbose       = defined $args{verbose} ? $args{verbose} : 0;
    my $continents    = $args{continents} || [];
       $continents    = [$continents] unless ref $continents;

    # Old Net::Ping did not do timings at all
    my $min_version = '2.13';
    unless( Net::Ping->VERSION gt $min_version ) {
        carp sprintf "Net::Ping version is %s (< %s). Returning %s",
            Net::Ping->VERSION, $min_version, $self->default_mirror;
        return $self->default_mirror;
    }

    my $seen = {};

    if ( ! @$continents ) {
        print "Searching for the best continent ...\n" if $verbose;
        my @best_continents = $self->find_best_continents(
            seen     => $seen,
            verbose  => $verbose,
            callback => $callback,
            );

        # Only add enough continents to find enough mirrors
        my $count = 0;
        for my $continent ( @best_continents ) {
            push @$continents, $continent;
            $count += $self->mirrors( $self->countries($continent) );
            last if $count >= $how_many;
        }
    }

    print "Scanning " . join(", ", @$continents) . " ...\n" if $verbose;

    my $trial_mirrors = $self->get_n_random_mirrors_by_continents( 3 * $how_many, $continents->[0] );

    my $timings = $self->get_mirrors_timings( $trial_mirrors, $seen, $callback );
    return [] unless @$timings;

    $how_many = @$timings if $how_many > @$timings;

    return wantarray ? @{$timings}[0 .. $how_many-1] : $timings->[0];
}


sub get_n_random_mirrors_by_continents {
    my( $self, $n, $continents ) = @_;
    $n ||= 3;
    $continents = [ $continents ] unless ref $continents;

    if ( $n <= 0 ) {
        return wantarray ? () : [];
    }

    my @long_list = $self->get_mirrors_by_continents( $continents );

    if ( $n eq '*' or $n > @long_list ) {
        return wantarray ? @long_list : \@long_list;
    }

    @long_list = map  {$_->[0]}
                 sort {$a->[1] <=> $b->[1]}
                 map  {[$_, rand]} @long_list;

    splice @long_list, $n; # truncate

    \@long_list;
}


sub get_mirrors_timings {
    my( $self, $mirror_list, $seen, $callback ) = @_;

    $seen = {} unless defined $seen;
    croak "The mirror list argument must be an array reference"
        unless ref $mirror_list eq ref [];
    croak "The seen argument must be a hash reference"
        unless ref $seen eq ref {};
    croak "callback must be a subroutine"
        if( defined $callback and ref $callback ne ref sub {} );

    my $timings = [];
    for my $m ( @$mirror_list ) {
        $seen->{$m->hostname} = $m;
        next unless eval{ $m->http };

        if( $self->_try_a_ping( $seen, $m, ) ) {
            my $ping = $m->ping;
            next unless defined $ping;
            push @$timings, $m;
            $callback->( $m ) if $callback;
        }
        else {
            push @$timings, $seen->{$m->hostname}
                if defined $seen->{$m->hostname}->rtt;
        }
    }

    my @best = sort {
           if( defined $a->rtt and defined $b->rtt )     {
            $a->rtt <=> $b->rtt
            }
        elsif( defined $a->rtt and ! defined $b->rtt )   {
            return -1;
            }
        elsif( ! defined $a->rtt and defined $b->rtt )   {
            return 1;
            }
        elsif( ! defined $a->rtt and ! defined $b->rtt ) {
            return 0;
            }

        } @$timings;

    return wantarray ? @best : \@best;
}


sub find_best_continents {
    my ($self, %args) = @_;

    $args{n}     ||=  3;
    $args{verbose} = 0 unless defined $args{verbose};
    $args{seen}    = {} unless defined $args{seen};
    croak "The seen argument must be a hash reference"
        unless ref $args{seen} eq ref {};
    $args{ping_cache_limit} = 24 * 60 * 60
        unless defined $args{ping_cache_time};
    croak "callback must be a subroutine"
        if( defined $args{callback} and ref $args{callback} ne ref sub {} );

    my %medians;
    CONT: for my $c ( $self->continents ) {
        print "Testing $c\n" if $args{verbose};
        my @mirrors = $self->mirrors( $self->countries($c) );

        next CONT unless @mirrors;
        my $n = (@mirrors < $args{n}) ? @mirrors : $args{n};

        my @tests;
        my $tries = 0;
        RANDOM: while ( @mirrors && @tests < $n && $tries++ < 15 ) {
            my $m = splice( @mirrors, int(rand(@mirrors)), 1 );
           if( $self->_try_a_ping( $args{seen}, $m, $args{ping_cache_limit} ) ) {
                $self->get_mirrors_timings( [ $m ], @args{qw(seen callback)} );
                next RANDOM unless defined $args{seen}{$m->hostname}->rtt;
            }
            printf "\t%s -> %0.2f ms\n",
                $m->hostname,
                join ' ', 1000 * $args{seen}{$m->hostname}->rtt
                    if $args{verbose};

            push @tests, $args{seen}{$m->hostname}->rtt;
        }

        my $median = $self->_get_median_ping_time( \@tests, $args{verbose} );
        $medians{$c} = $median if defined $median;
    }

    my @best_cont = sort { $medians{$a} <=> $medians{$b} } keys %medians;

    if ( $args{verbose} ) {
        print "Median result by continent:\n";
        for my $c ( @best_cont ) {
            printf( "  %4d ms  %s\n", int($medians{$c}*1000+.5), $c );
        }
    }

    return wantarray ? @best_cont : $best_cont[0];
}

sub _try_a_ping {
    my ($self, $seen, $mirror, $ping_cache_limit ) = @_;

    ( ! exists $seen->{$mirror->hostname} )
        or
    (
    ! defined $seen->{$mirror->hostname}->rtt
        or
    time - $seen->{$mirror->hostname}->rtt > $ping_cache_limit
    )
}

sub _get_median_ping_time {
    my ($self, $tests, $verbose ) = @_;

    my @sorted = sort { $a <=> $b } @$tests;

    my $median = do {
           if ( @sorted == 0 ) { undef }
        elsif ( @sorted == 1 ) { $sorted[0] }
        elsif ( @sorted % 2 )  { $sorted[ int(@sorted / 2) ] }
        else {
            my $mid_high = int(@sorted/2);
            ($sorted[$mid_high-1] + $sorted[$mid_high])/2;
        }
    };

    printf "\t-->median time: %0.2f ms\n", $median * 1000 if $verbose;

    return $median;
}

sub _parse {
    my ($self, $file, $handle) = @_;
    my $output = $self->{mirrors};
    my $geo    = $self->{geography};

    local $/ = "\012";
    my $line = 0;
    my $mirror = undef;
    while ( 1 ) {
        # Next line
        my $string = <$handle>;
        last if ! defined $string;
        $line = $line + 1;

        # Remove the useless lines
        chomp( $string );
        next if $string =~ /^\s*$/;
        next if $string =~ /^\s*#/;

        # Hostname or property?
        if ( $string =~ /^\s/ ) {
            # Property
            unless ( $string =~ /^\s+(\w+)\s+=\s+\"(.*)\"$/ ) {
                croak("Invalid property on line $line");
            }
            my ($prop, $value) = ($1,$2);
            $mirror ||= {};
            if ( $prop eq 'dst_location' ) {
                my (@location,$continent,$country);
                @location = (split /\s*,\s*/, $value)
                    and ($continent, $country) = @location[-1,-2];
                $continent =~ s/\s\(.*//;
                $continent =~ s/\W+$//; # if Jarkko doesn't know latitude/longitude
                $geo->{$continent}{$country} = 1 if $continent && $country;
                $mirror->{continent} = $continent || "unknown";
                $mirror->{country} = $country || "unknown";
            }
            elsif ( $prop eq 'dst_http' ) {
                $mirror->{http} = $value;
            }
            elsif ( $prop eq 'dst_ftp' ) {
                $mirror->{ftp} = $value;
            }
            elsif ( $prop eq 'dst_rsync' ) {
                $mirror->{rsync} = $value;
            }
            else {
                $prop =~ s/^dst_//;
                $mirror->{$prop} = $value;
            }
        } else {
            # Hostname
            unless ( $string =~ /^([\w\.-]+)\:\s*$/ ) {
                croak("Invalid host name on line $line");
            }
            my $current = $mirror;
            $mirror     = { hostname => "$1" };
            if ( $current ) {
                push @$output, CPAN::Mirrored::By->new($current);
            }
        }
    }
    if ( $mirror ) {
        push @$output, CPAN::Mirrored::By->new($mirror);
    }

    return;
}


package CPAN::Mirrored::By;
use strict;
use Net::Ping   ();

sub new {
    my($self,$arg) = @_;
    $arg ||= {};
    bless $arg, $self;
}
sub hostname  { shift->{hostname}    }
sub continent { shift->{continent}   }
sub country   { shift->{country}     }
sub http      { shift->{http}  || '' }
sub ftp       { shift->{ftp}   || '' }
sub rsync     { shift->{rsync} || '' }
sub rtt       { shift->{rtt}         }
sub ping_time { shift->{ping_time}   }

sub url {
    my $self = shift;
    return $self->{http} || $self->{ftp};
}

sub ping {
    my $self = shift;

    my $ping = Net::Ping->new($^O eq 'VMS' ? 'icmp' : 'tcp', 1);
    my ($proto) = $self->url =~ m{^([^:]+)};
    my $port = $proto eq 'http' ? 80 : 21;
    return unless $port;

    if ( $ping->can('port_number') ) {
        $ping->port_number($port);
    }
    else {
        $ping->{'port_num'} = $port;
    }

    $ping->hires(1) if $ping->can('hires');
    my ($alive,$rtt) = $ping->ping($self->hostname);

    $self->{rtt} = $alive ? $rtt : undef;
    $self->{ping_time} = time;

    $self->rtt;
}


1;

