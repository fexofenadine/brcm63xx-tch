package App::Prove::State;

use strict;
use warnings;

use File::Find;
use File::Spec;
use Carp;

use App::Prove::State::Result;
use TAP::Parser::YAMLish::Reader ();
use TAP::Parser::YAMLish::Writer ();
use base 'TAP::Base';

BEGIN {
    __PACKAGE__->mk_methods('result_class');
}

use constant IS_WIN32 => ( $^O =~ /^(MS)?Win32$/ );
use constant NEED_GLOB => IS_WIN32;


our $VERSION = '3.30';



sub new {
    my $class = shift;
    my %args = %{ shift || {} };

    my $self = bless {
        select     => [],
        seq        => 1,
        store      => delete $args{store},
        extensions => ( delete $args{extensions} || ['.t'] ),
        result_class =>
          ( delete $args{result_class} || 'App::Prove::State::Result' ),
    }, $class;

    $self->{_} = $self->result_class->new(
        {   tests      => {},
            generation => 1,
        }
    );
    my $store = $self->{store};
    $self->load($store)
      if defined $store && -f $store;

    return $self;
}



sub extensions {
    my $self = shift;
    $self->{extensions} = shift if @_;
    return $self->{extensions};
}


sub results {
    my $self = shift;
    $self->{_} || $self->result_class->new;
}


sub commit {
    my $self = shift;
    if ( $self->{should_save} ) {
        $self->save;
    }
}


sub apply_switch {
    my $self = shift;
    my @opts = @_;

    my $last_gen      = $self->results->generation - 1;
    my $last_run_time = $self->results->last_run_time;
    my $now           = $self->get_time;

    my @switches = map { split /,/ } @opts;

    my %handler = (
        last => sub {
            $self->_select(
                limit => shift,
                where => sub { $_->generation >= $last_gen },
                order => sub { $_->sequence }
            );
        },
        failed => sub {
            $self->_select(
                limit => shift,
                where => sub { $_->result != 0 },
                order => sub { -$_->result }
            );
        },
        passed => sub {
            $self->_select(
                limit => shift,
                where => sub { $_->result == 0 }
            );
        },
        all => sub {
            $self->_select( limit => shift );
        },
        todo => sub {
            $self->_select(
                limit => shift,
                where => sub { $_->num_todo != 0 },
                order => sub { -$_->num_todo; }
            );
        },
        hot => sub {
            $self->_select(
                limit => shift,
                where => sub { defined $_->last_fail_time },
                order => sub { $now - $_->last_fail_time }
            );
        },
        slow => sub {
            $self->_select(
                limit => shift,
                order => sub { -$_->elapsed }
            );
        },
        fast => sub {
            $self->_select(
                limit => shift,
                order => sub { $_->elapsed }
            );
        },
        new => sub {
            $self->_select(
                limit => shift,
                order => sub { -$_->mtime }
            );
        },
        old => sub {
            $self->_select(
                limit => shift,
                order => sub { $_->mtime }
            );
        },
        fresh => sub {
            $self->_select(
                limit => shift,
                where => sub { $_->mtime >= $last_run_time }
            );
        },
        save => sub {
            $self->{should_save}++;
        },
        adrian => sub {
            unshift @switches, qw( hot all save );
        },
    );

    while ( defined( my $ele = shift @switches ) ) {
        my ( $opt, $arg )
          = ( $ele =~ /^([^:]+):(.*)/ )
          ? ( $1, $2 )
          : ( $ele, undef );
        my $code = $handler{$opt}
          || croak "Illegal state option: $opt";
        $code->($arg);
    }
    return;
}

sub _select {
    my ( $self, %spec ) = @_;
    push @{ $self->{select} }, \%spec;
}


sub get_tests {
    my $self    = shift;
    my $recurse = shift;
    my @argv    = @_;
    my %seen;

    my @selected = $self->_query;

    unless ( @argv || @{ $self->{select} } ) {
        @argv = $recurse ? '.' : 't';
        croak qq{No tests named and '@argv' directory not found}
          unless -d $argv[0];
    }

    push @selected, $self->_get_raw_tests( $recurse, @argv ) if @argv;
    return grep { !$seen{$_}++ } @selected;
}

sub _query {
    my $self = shift;
    if ( my @sel = @{ $self->{select} } ) {
        warn "No saved state, selection will be empty\n"
          unless $self->results->num_tests;
        return map { $self->_query_clause($_) } @sel;
    }
    return;
}

sub _query_clause {
    my ( $self, $clause ) = @_;
    my @got;
    my $results = $self->results;
    my $where = $clause->{where} || sub {1};

    # Select
    for my $name ( $results->test_names ) {
        next unless -f $name;
        local $_ = $results->test($name);
        push @got, $name if $where->();
    }

    # Sort
    if ( my $order = $clause->{order} ) {
        @got = map { $_->[0] }
          sort {
                 ( defined $b->[1] <=> defined $a->[1] )
              || ( ( $a->[1] || 0 ) <=> ( $b->[1] || 0 ) )
          } map {
            [   $_,
                do { local $_ = $results->test($_); $order->() }
            ]
          } @got;
    }

    if ( my $limit = $clause->{limit} ) {
        @got = splice @got, 0, $limit if @got > $limit;
    }

    return @got;
}

sub _get_raw_tests {
    my $self    = shift;
    my $recurse = shift;
    my @argv    = @_;
    my @tests;

    # Do globbing on Win32.
    if (NEED_GLOB) {
        eval "use File::Glob::Windows";    # [49732]
        @argv = map { glob "$_" } @argv;
    }
    my $extensions = $self->{extensions};

    for my $arg (@argv) {
        if ( '-' eq $arg ) {
            push @argv => <STDIN>;
            chomp(@argv);
            next;
        }

        push @tests,
            sort -d $arg
          ? $recurse
              ? $self->_expand_dir_recursive( $arg, $extensions )
              : map { glob( File::Spec->catfile( $arg, "*$_" ) ) }
              @{$extensions}
          : $arg;
    }
    return @tests;
}

sub _expand_dir_recursive {
    my ( $self, $dir, $extensions ) = @_;

    my @tests;
    my $ext_string = join( '|', map {quotemeta} @{$extensions} );

    find(
        {   follow      => 1,      #21938
            follow_skip => 2,
            wanted      => sub {
                -f 
                  && /(?:$ext_string)$/
                  && push @tests => $File::Find::name;
              }
        },
        $dir
    );
    return @tests;
}



sub observe_test {

    my ( $self, $test_info, $parser ) = @_;
    my $name = $test_info->[0];
    my $fail = scalar( $parser->failed ) + ( $parser->has_problems ? 1 : 0 );
    my $todo = scalar( $parser->todo );
    my $start_time = $parser->start_time;
    my $end_time   = $parser->end_time,

      my $test = $self->results->test($name);

    $test->sequence( $self->{seq}++ );
    $test->generation( $self->results->generation );

    $test->run_time($end_time);
    $test->result($fail);
    $test->num_todo($todo);
    $test->elapsed( $end_time - $start_time );

    $test->parser($parser);

    if ($fail) {
        $test->total_failures( $test->total_failures + 1 );
        $test->last_fail_time($end_time);
    }
    else {
        $test->total_passes( $test->total_passes + 1 );
        $test->last_pass_time($end_time);
    }
}


sub save {
    my ($self) = @_;

    my $store = $self->{store} or return;
    $self->results->last_run_time( $self->get_time );

    my $writer = TAP::Parser::YAMLish::Writer->new;
    local *FH;
    open FH, ">$store" or croak "Can't write $store ($!)";
    $writer->write( $self->results->raw, \*FH );
    close FH;
}


sub load {
    my ( $self, $name ) = @_;
    my $reader = TAP::Parser::YAMLish::Reader->new;
    local *FH;
    open FH, "<$name" or croak "Can't read $name ($!)";

    # XXX this is temporary
    $self->{_} = $self->result_class->new(
        $reader->read(
            sub {
                my $line = <FH>;
                defined $line && chomp $line;
                return $line;
            }
        )
    );

    # $writer->write( $self->{tests} || {}, \*FH );
    close FH;
    $self->_regen_seq;
    $self->_prune_and_stamp;
    $self->results->generation( $self->results->generation + 1 );
}

sub _prune_and_stamp {
    my $self = shift;

    my $results = $self->results;
    my @tests   = $self->results->tests;
    for my $test (@tests) {
        my $name = $test->name;
        if ( my @stat = stat $name ) {
            $test->mtime( $stat[9] );
        }
        else {
            $results->remove($name);
        }
    }
}

sub _regen_seq {
    my $self = shift;
    for my $test ( $self->results->tests ) {
        $self->{seq} = $test->sequence + 1
          if defined $test->sequence && $test->sequence >= $self->{seq};
    }
}

1;
