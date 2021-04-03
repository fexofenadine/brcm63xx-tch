package App::Prove::State::Result::Test;

use strict;
use warnings;


our $VERSION = '3.30';


my %methods = (
    name           => { method => 'name' },
    elapsed        => { method => 'elapsed', default => 0 },
    gen            => { method => 'generation', default => 1 },
    last_pass_time => { method => 'last_pass_time', default => undef },
    last_fail_time => { method => 'last_fail_time', default => undef },
    last_result    => { method => 'result', default => 0 },
    last_run_time  => { method => 'run_time', default => undef },
    last_todo      => { method => 'num_todo', default => 0 },
    mtime          => { method => 'mtime', default => undef },
    seq            => { method => 'sequence', default => 1 },
    total_passes   => { method => 'total_passes', default => 0 },
    total_failures => { method => 'total_failures', default => 0 },
    parser         => { method => 'parser' },
);

while ( my ( $key, $description ) = each %methods ) {
    my $default = $description->{default};
    no strict 'refs';
    *{ $description->{method} } = sub {
        my $self = shift;
        if (@_) {
            $self->{$key} = shift;
            return $self;
        }
        return $self->{$key} || $default;
    };
}


sub new {
    my ( $class, $arg_for ) = @_;
    $arg_for ||= {};
    bless $arg_for => $class;
}


sub raw {
    my $self = shift;
    my %raw  = %$self;

    # this is backwards-compatibility hack and is not guaranteed.
    delete $raw{name};
    delete $raw{parser};
    return \%raw;
}

1;
