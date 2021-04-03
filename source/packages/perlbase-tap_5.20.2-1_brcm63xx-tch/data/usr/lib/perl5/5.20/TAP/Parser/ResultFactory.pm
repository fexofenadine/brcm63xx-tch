package TAP::Parser::ResultFactory;

use strict;
use warnings;

use TAP::Parser::Result::Bailout ();
use TAP::Parser::Result::Comment ();
use TAP::Parser::Result::Plan    ();
use TAP::Parser::Result::Pragma  ();
use TAP::Parser::Result::Test    ();
use TAP::Parser::Result::Unknown ();
use TAP::Parser::Result::Version ();
use TAP::Parser::Result::YAML    ();

use base 'TAP::Object';



our $VERSION = '3.30';


sub make_result {
    my ( $proto, $token ) = @_;
    my $type = $token->{type};
    return $proto->class_for($type)->new($token);
}


our %CLASS_FOR = (
	plan    => 'TAP::Parser::Result::Plan',
	pragma  => 'TAP::Parser::Result::Pragma',
	test    => 'TAP::Parser::Result::Test',
	comment => 'TAP::Parser::Result::Comment',
	bailout => 'TAP::Parser::Result::Bailout',
	version => 'TAP::Parser::Result::Version',
	unknown => 'TAP::Parser::Result::Unknown',
	yaml    => 'TAP::Parser::Result::YAML',
);

sub class_for {
    my ( $class, $type ) = @_;

    # return target class:
    return $CLASS_FOR{$type} if exists $CLASS_FOR{$type};

    # or complain:
    require Carp;
    Carp::croak("Could not determine class for result type '$type'");
}

sub register_type {
    my ( $class, $type, $rclass ) = @_;

    # register it blindly, assume they know what they're doing
    $CLASS_FOR{$type} = $rclass;
    return $class;
}

1;

