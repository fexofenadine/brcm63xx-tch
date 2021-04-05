package HTML::Tree;


use HTML::TreeBuilder ();

use vars qw( $VERSION );
$VERSION = 3.23;


sub new {
  shift; unshift @_, 'HTML::TreeBuilder';
  goto &HTML::TreeBuilder::new;
}
sub new_from_file {
  shift; unshift @_, 'HTML::TreeBuilder';
  goto &HTML::TreeBuilder::new_from_file;
}
sub new_from_content {
  shift; unshift @_, 'HTML::TreeBuilder';
  goto &HTML::TreeBuilder::new_from_content;
}


1;
