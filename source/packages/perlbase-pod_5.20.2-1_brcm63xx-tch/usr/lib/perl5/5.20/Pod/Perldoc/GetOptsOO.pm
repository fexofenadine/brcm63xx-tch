package Pod::Perldoc::GetOptsOO;
use strict;

use vars qw($VERSION);
$VERSION = '3.23';

BEGIN { # Make a DEBUG constant ASAP
  *DEBUG = defined( &Pod::Perldoc::DEBUG )
   ? \&Pod::Perldoc::DEBUG
   : sub(){10};
}


sub getopts {
  my($target, $args, $truth) = @_;

  $args ||= \@ARGV;

  $target->aside(
    "Starting switch processing.  Scanning arguments [@$args]\n"
  ) if $target->can('aside');

  return unless @$args;

  $truth = 1 unless @_ > 2;

  DEBUG > 3 and print "   Truth is $truth\n";


  my $error_count = 0;

  while( @$args  and  ($_ = $args->[0]) =~ m/^-(.)(.*)/s ) {
    my($first,$rest) = ($1,$2);
    if ($_ eq '--') {	# early exit if "--"
      shift @$args;
      last;
    }
    if ($first eq '-' and $rest) {      # GNU style long param names
      ($first, $rest) = split '=', $rest, 2;
    }
    my $method = "opt_${first}_with";
    if( $target->can($method) ) {  # it's argumental
      if($rest eq '') {   # like -f bar
        shift @$args;
        $target->warn( "Option $first needs a following argument!\n" ) unless @$args;
        $rest = shift @$args;
      } else {            # like -fbar  (== -f bar)
        shift @$args;
      }

      DEBUG > 3 and print " $method => $rest\n";
      $target->$method( $rest );

    # Otherwise, it's not argumental...
    } else {

      if( $target->can( $method = "opt_$first" ) ) {
        DEBUG > 3 and print " $method is true ($truth)\n";
        $target->$method( $truth );

      # Otherwise it's an unknown option...

      } elsif( $target->can('handle_unknown_option') ) {
        DEBUG > 3
         and print " calling handle_unknown_option('$first')\n";

        $error_count += (
          $target->handle_unknown_option( $first ) || 0
        );

      } else {
        ++$error_count;
        $target->warn( "Unknown option: $first\n" );
      }

      if($rest eq '') {   # like -f
        shift @$args
      } else {            # like -fbar  (== -f -bar )
        DEBUG > 2 and print "   Setting args->[0] to \"-$rest\"\n";
        $args->[0] = "-$rest";
      }
    }
  }


  $target->aside(
    "Ending switch processing.  Args are [@$args] with $error_count errors.\n"
  ) if $target->can('aside');

  $error_count == 0;
}

1;

__END__

