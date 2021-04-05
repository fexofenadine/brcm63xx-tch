package TAP::Parser::Grammar;

use strict;
use warnings;

use TAP::Parser::ResultFactory   ();
use TAP::Parser::YAMLish::Reader ();

use base 'TAP::Object';


our $VERSION = '3.35';


sub _initialize {
    my ( $self, $args ) = @_;
    $self->{iterator} = $args->{iterator};    # TODO: accessor
    $self->{iterator} ||= $args->{stream};    # deprecated
    $self->{parser} = $args->{parser};        # TODO: accessor
    $self->set_version( $args->{version} || 12 );
    return $self;
}

my %language_for;

{

    # XXX the 'not' and 'ok' might be on separate lines in VMS ...
    my $ok  = qr/(?:not )?ok\b/;
    my $num = qr/\d+/;

    my %v12 = (
        version => {
            syntax  => qr/^TAP\s+version\s+(\d+)\s*\z/i,
            handler => sub {
                my ( $self, $line ) = @_;
                my $version = $1;
                return $self->_make_version_token( $line, $version, );
            },
        },
        plan => {
            syntax  => qr/^1\.\.(\d+)\s*(.*)\z/,
            handler => sub {
                my ( $self, $line ) = @_;
                my ( $tests_planned, $tail ) = ( $1, $2 );
                my $explanation = undef;
                my $skip        = '';

                if ( $tail =~ /^todo((?:\s+\d+)+)/ ) {
                    my @todo = split /\s+/, _trim($1);
                    return $self->_make_plan_token(
                        $line, $tests_planned, 'TODO',
                        '',    \@todo
                    );
                }
                elsif ( 0 == $tests_planned ) {
                    $skip = 'SKIP';

                    # If we can't match # SKIP the directive should be undef.
                    ($explanation) = $tail =~ /^#\s*SKIP\S*\s+(.*)/i;
                }
                elsif ( $tail !~ /^\s*$/ ) {
                    return $self->_make_unknown_token($line);
                }

                $explanation = '' unless defined $explanation;

                return $self->_make_plan_token(
                    $line, $tests_planned, $skip,
                    $explanation, []
                );

            },
        },

        # An optimization to handle the most common test lines without
        # directives.
        simple_test => {
            syntax  => qr/^($ok) \ ($num) (?:\ ([^#]+))? \z/x,
            handler => sub {
                my ( $self, $line ) = @_;
                my ( $ok, $num, $desc ) = ( $1, $2, $3 );

                return $self->_make_test_token(
                    $line, $ok, $num,
                    $desc
                );
            },
        },
        test => {
            syntax  => qr/^($ok) \s* ($num)? \s* (.*) \z/x,
            handler => sub {
                my ( $self, $line ) = @_;
                my ( $ok, $num, $desc ) = ( $1, $2, $3 );
                my ( $dir, $explanation ) = ( '', '' );
                if ($desc =~ m/^ ( [^\\\#]* (?: \\. [^\\\#]* )* )
                       \# \s* (SKIP|TODO) \b \s* (.*) $/ix
                  )
                {
                    ( $desc, $dir, $explanation ) = ( $1, $2, $3 );
                }
                return $self->_make_test_token(
                    $line, $ok, $num, $desc,
                    $dir,  $explanation
                );
            },
        },
        comment => {
            syntax  => qr/^#(.*)/,
            handler => sub {
                my ( $self, $line ) = @_;
                my $comment = $1;
                return $self->_make_comment_token( $line, $comment );
            },
        },
        bailout => {
            syntax  => qr/^\s*Bail out!\s*(.*)/,
            handler => sub {
                my ( $self, $line ) = @_;
                my $explanation = $1;
                return $self->_make_bailout_token(
                    $line,
                    $explanation
                );
            },
        },
    );

    my %v13 = (
        %v12,
        plan => {
            syntax  => qr/^1\.\.(\d+)(?:\s*#\s*SKIP\b(.*))?\z/i,
            handler => sub {
                my ( $self, $line ) = @_;
                my ( $tests_planned, $explanation ) = ( $1, $2 );
                my $skip
                  = ( 0 == $tests_planned || defined $explanation )
                  ? 'SKIP'
                  : '';
                $explanation = '' unless defined $explanation;
                return $self->_make_plan_token(
                    $line, $tests_planned, $skip,
                    $explanation, []
                );
            },
        },
        yaml => {
            syntax  => qr/^ (\s+) (---.*) $/x,
            handler => sub {
                my ( $self, $line ) = @_;
                my ( $pad, $marker ) = ( $1, $2 );
                return $self->_make_yaml_token( $pad, $marker );
            },
        },
        pragma => {
            syntax =>
              qr/^ pragma \s+ ( [-+] \w+ \s* (?: , \s* [-+] \w+ \s* )* ) $/x,
            handler => sub {
                my ( $self, $line ) = @_;
                my $pragmas = $1;
                return $self->_make_pragma_token( $line, $pragmas );
            },
        },
    );

    %language_for = (
        '12' => {
            tokens => \%v12,
        },
        '13' => {
            tokens => \%v13,
            setup  => sub {
                shift->{iterator}->handle_unicode;
            },
        },
    );
}



sub set_version {
    my $self    = shift;
    my $version = shift;

    if ( my $language = $language_for{$version} ) {
        $self->{version} = $version;
        $self->{tokens}  = $language->{tokens};

        if ( my $setup = $language->{setup} ) {
            $self->$setup();
        }

        $self->_order_tokens;
    }
    else {
        require Carp;
        Carp::croak("Unsupported syntax version: $version");
    }
}

sub _order_tokens {
    my $self = shift;

    my %copy = %{ $self->{tokens} };
    my @ordered_tokens = grep {defined}
      map { delete $copy{$_} } qw( simple_test test comment plan );
    push @ordered_tokens, values %copy;

    $self->{ordered_tokens} = \@ordered_tokens;
}



sub tokenize {
    my $self = shift;

    my $line = $self->{iterator}->next;
    unless ( defined $line ) {
        delete $self->{parser};    # break circular ref
        return;
    }

    my $token;

    for my $token_data ( @{ $self->{ordered_tokens} } ) {
        if ( $line =~ $token_data->{syntax} ) {
            my $handler = $token_data->{handler};
            $token = $self->$handler($line);
            last;
        }
    }

    $token = $self->_make_unknown_token($line) unless $token;

    return $self->{parser}->make_result($token);
}



sub token_types {
    my $self = shift;
    return keys %{ $self->{tokens} };
}



sub syntax_for {
    my ( $self, $type ) = @_;
    return $self->{tokens}->{$type}->{syntax};
}



sub handler_for {
    my ( $self, $type ) = @_;
    return $self->{tokens}->{$type}->{handler};
}

sub _make_version_token {
    my ( $self, $line, $version ) = @_;
    return {
        type    => 'version',
        raw     => $line,
        version => $version,
    };
}

sub _make_plan_token {
    my ( $self, $line, $tests_planned, $directive, $explanation, $todo ) = @_;

    if (   $directive eq 'SKIP'
        && 0 != $tests_planned
        && $self->{version} < 13 )
    {
        warn
          "Specified SKIP directive in plan but more than 0 tests ($line)\n";
    }

    return {
        type          => 'plan',
        raw           => $line,
        tests_planned => $tests_planned,
        directive     => $directive,
        explanation   => _trim($explanation),
        todo_list     => $todo,
    };
}

sub _make_test_token {
    my ( $self, $line, $ok, $num, $desc, $dir, $explanation ) = @_;
    return {
        ok          => $ok,

        # forcing this to be an integer (and not a string) reduces memory
        # consumption. RT #84939
        test_num    => ( defined $num ? 0 + $num : undef ),
        description => _trim($desc),
        directive   => ( defined $dir ? uc $dir : '' ),
        explanation => _trim($explanation),
        raw         => $line,
        type        => 'test',
    };
}

sub _make_unknown_token {
    my ( $self, $line ) = @_;
    return {
        raw  => $line,
        type => 'unknown',
    };
}

sub _make_comment_token {
    my ( $self, $line, $comment ) = @_;
    return {
        type    => 'comment',
        raw     => $line,
        comment => _trim($comment)
    };
}

sub _make_bailout_token {
    my ( $self, $line, $explanation ) = @_;
    return {
        type    => 'bailout',
        raw     => $line,
        bailout => _trim($explanation)
    };
}

sub _make_yaml_token {
    my ( $self, $pad, $marker ) = @_;

    my $yaml = TAP::Parser::YAMLish::Reader->new;

    my $iterator = $self->{iterator};

    # Construct a reader that reads from our input stripping leading
    # spaces from each line.
    my $leader = length($pad);
    my $strip  = qr{ ^ (\s{$leader}) (.*) $ }x;
    my @extra  = ($marker);
    my $reader = sub {
        return shift @extra if @extra;
        my $line = $iterator->next;
        return $2 if $line =~ $strip;
        return;
    };

    my $data = $yaml->read($reader);

    # Reconstitute input. This is convoluted. Maybe we should just
    # record it on the way in...
    chomp( my $raw = $yaml->get_raw );
    $raw =~ s/^/$pad/mg;

    return {
        type => 'yaml',
        raw  => $raw,
        data => $data
    };
}

sub _make_pragma_token {
    my ( $self, $line, $pragmas ) = @_;
    return {
        type    => 'pragma',
        raw     => $line,
        pragmas => [ split /\s*,\s*/, _trim($pragmas) ],
    };
}

sub _trim {
    my $data = shift;

    return '' unless defined $data;

    $data =~ s/^\s+//;
    $data =~ s/\s+$//;
    return $data;
}

1;

