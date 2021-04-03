

package DB_File::HASHINFO ;

require 5.00504;

use warnings;
use strict;
use Carp;
require Tie::Hash;
@DB_File::HASHINFO::ISA = qw(Tie::Hash);

sub new
{
    my $pkg = shift ;
    my %x ;
    tie %x, $pkg ;
    bless \%x, $pkg ;
}


sub TIEHASH
{
    my $pkg = shift ;

    bless { VALID => { 
		       	bsize	  => 1,
			ffactor	  => 1,
			nelem	  => 1,
			cachesize => 1,
			hash	  => 2,
			lorder	  => 1,
		     }, 
	    GOT   => {}
          }, $pkg ;
}


sub FETCH 
{  
    my $self  = shift ;
    my $key   = shift ;

    return $self->{GOT}{$key} if exists $self->{VALID}{$key}  ;

    my $pkg = ref $self ;
    croak "${pkg}::FETCH - Unknown element '$key'" ;
}


sub STORE 
{
    my $self  = shift ;
    my $key   = shift ;
    my $value = shift ;

    my $type = $self->{VALID}{$key};

    if ( $type )
    {
    	croak "Key '$key' not associated with a code reference" 
	    if $type == 2 && !ref $value && ref $value ne 'CODE';
        $self->{GOT}{$key} = $value ;
        return ;
    }
    
    my $pkg = ref $self ;
    croak "${pkg}::STORE - Unknown element '$key'" ;
}

sub DELETE 
{
    my $self = shift ;
    my $key  = shift ;

    if ( exists $self->{VALID}{$key} )
    {
        delete $self->{GOT}{$key} ;
        return ;
    }
    
    my $pkg = ref $self ;
    croak "DB_File::HASHINFO::DELETE - Unknown element '$key'" ;
}

sub EXISTS
{
    my $self = shift ;
    my $key  = shift ;

    exists $self->{VALID}{$key} ;
}

sub NotHere
{
    my $self = shift ;
    my $method = shift ;

    croak ref($self) . " does not define the method ${method}" ;
}

sub FIRSTKEY { my $self = shift ; $self->NotHere("FIRSTKEY") }
sub NEXTKEY  { my $self = shift ; $self->NotHere("NEXTKEY") }
sub CLEAR    { my $self = shift ; $self->NotHere("CLEAR") }

package DB_File::RECNOINFO ;

use warnings;
use strict ;

@DB_File::RECNOINFO::ISA = qw(DB_File::HASHINFO) ;

sub TIEHASH
{
    my $pkg = shift ;

    bless { VALID => { map {$_, 1} 
		       qw( bval cachesize psize flags lorder reclen bfname )
		     },
	    GOT   => {},
          }, $pkg ;
}

package DB_File::BTREEINFO ;

use warnings;
use strict ;

@DB_File::BTREEINFO::ISA = qw(DB_File::HASHINFO) ;

sub TIEHASH
{
    my $pkg = shift ;

    bless { VALID => { 
		      	flags	   => 1,
			cachesize  => 1,
			maxkeypage => 1,
			minkeypage => 1,
			psize	   => 1,
			compare	   => 2,
			prefix	   => 2,
			lorder	   => 1,
	    	     },
	    GOT   => {},
          }, $pkg ;
}


package DB_File ;

use warnings;
use strict;
our ($VERSION, @ISA, @EXPORT, $AUTOLOAD, $DB_BTREE, $DB_HASH, $DB_RECNO);
our ($db_version, $use_XSLoader, $splice_end_array_no_length, $splice_end_array, $Error);
use Carp;


$VERSION = "1.831" ;
$VERSION = eval $VERSION; # needed for dev releases

{
    local $SIG{__WARN__} = sub {$splice_end_array_no_length = join(" ",@_);};
    my @a =(1); splice(@a, 3);
    $splice_end_array_no_length = 
        ($splice_end_array_no_length =~ /^splice\(\) offset past end of array at /);
}      
{
    local $SIG{__WARN__} = sub {$splice_end_array = join(" ", @_);};
    my @a =(1); splice(@a, 3, 1);
    $splice_end_array = 
        ($splice_end_array =~ /^splice\(\) offset past end of array at /);
}      

$DB_BTREE = new DB_File::BTREEINFO ;
$DB_HASH  = new DB_File::HASHINFO ;
$DB_RECNO = new DB_File::RECNOINFO ;

require Tie::Hash;
require Exporter;
BEGIN {
    $use_XSLoader = 1 ;
    { local $SIG{__DIE__} ; eval { require XSLoader } ; }

    if ($@) {
        $use_XSLoader = 0 ;
        require DynaLoader;
        @ISA = qw(DynaLoader);
    }
}

push @ISA, qw(Tie::Hash Exporter);
@EXPORT = qw(
        $DB_BTREE $DB_HASH $DB_RECNO 

	BTREEMAGIC
	BTREEVERSION
	DB_LOCK
	DB_SHMEM
	DB_TXN
	HASHMAGIC
	HASHVERSION
	MAX_PAGE_NUMBER
	MAX_PAGE_OFFSET
	MAX_REC_NUMBER
	RET_ERROR
	RET_SPECIAL
	RET_SUCCESS
	R_CURSOR
	R_DUP
	R_FIRST
	R_FIXEDLEN
	R_IAFTER
	R_IBEFORE
	R_LAST
	R_NEXT
	R_NOKEY
	R_NOOVERWRITE
	R_PREV
	R_RECNOSYNC
	R_SETCURSOR
	R_SNAPSHOT
	__R_UNUSED

);

sub AUTOLOAD {
    my($constname);
    ($constname = $AUTOLOAD) =~ s/.*:://;
    my ($error, $val) = constant($constname);
    Carp::croak $error if $error;
    no strict 'refs';
    *{$AUTOLOAD} = sub { $val };
    goto &{$AUTOLOAD};
}           


eval {
    # Make all Fcntl O_XXX constants available for importing
    require Fcntl;
    my @O = grep /^O_/, @Fcntl::EXPORT;
    Fcntl->import(@O);  # first we import what we want to export
    push(@EXPORT, @O);
};

if ($use_XSLoader)
  { XSLoader::load("DB_File", $VERSION)}
else
  { bootstrap DB_File $VERSION }

sub tie_hash_or_array
{
    my (@arg) = @_ ;
    my $tieHASH = ( (caller(1))[3] =~ /TIEHASH/ ) ;

    use File::Spec;
    $arg[1] = File::Spec->rel2abs($arg[1]) 
        if defined $arg[1] ;

    $arg[4] = tied %{ $arg[4] } 
	if @arg >= 5 && ref $arg[4] && $arg[4] =~ /=HASH/ && tied %{ $arg[4] } ;

    $arg[2] = O_CREAT()|O_RDWR() if @arg >=3 && ! defined $arg[2];
    $arg[3] = 0666               if @arg >=4 && ! defined $arg[3];

    # make recno in Berkeley DB version 2 (or better) work like 
    # recno in version 1.
    if ($db_version >= 4 and ! $tieHASH) {
        $arg[2] |= O_CREAT();
    }

    if ($db_version > 1 and defined $arg[4] and $arg[4] =~ /RECNO/ and 
	$arg[1] and ! -e $arg[1]) {
	open(FH, ">$arg[1]") or return undef ;
	close FH ;
	chmod $arg[3] ? $arg[3] : 0666 , $arg[1] ;
    }

    DoTie_($tieHASH, @arg) ;
}

sub TIEHASH
{
    tie_hash_or_array(@_) ;
}

sub TIEARRAY
{
    tie_hash_or_array(@_) ;
}

sub CLEAR 
{
    my $self = shift;
    my $key = 0 ;
    my $value = "" ;
    my $status = $self->seq($key, $value, R_FIRST());
    my @keys;
 
    while ($status == 0) {
        push @keys, $key;
        $status = $self->seq($key, $value, R_NEXT());
    }
    foreach $key (reverse @keys) {
        my $s = $self->del($key); 
    }
}

sub EXTEND { }

sub STORESIZE
{
    my $self = shift;
    my $length = shift ;
    my $current_length = $self->length() ;

    if ($length < $current_length) {
	my $key ;
        for ($key = $current_length - 1 ; $key >= $length ; -- $key)
	  { $self->del($key) }
    }
    elsif ($length > $current_length) {
        $self->put($length-1, "") ;
    }
}
 

sub SPLICE
{
    my $self = shift;
    my $offset = shift;
    if (not defined $offset) {
	warnings::warnif('uninitialized', 'Use of uninitialized value in splice');
	$offset = 0;
    }

    my $has_length = @_;
    my $length = @_ ? shift : 0;
    # Carping about definedness comes _after_ the OFFSET sanity check.
    # This is so we get the same error messages as Perl's splice().
    # 

    my @list = @_;

    my $size = $self->FETCHSIZE();
    
    # 'If OFFSET is negative then it start that far from the end of
    # the array.'
    # 
    if ($offset < 0) {
	my $new_offset = $size + $offset;
	if ($new_offset < 0) {
	    die "Modification of non-creatable array value attempted, "
	      . "subscript $offset";
	}
	$offset = $new_offset;
    }

    if (not defined $length) {
	warnings::warnif('uninitialized', 'Use of uninitialized value in splice');
	$length = 0;
    }

    if ($offset > $size) {
 	$offset = $size;
	warnings::warnif('misc', 'splice() offset past end of array')
            if $has_length ? $splice_end_array : $splice_end_array_no_length;
    }

    # 'If LENGTH is omitted, removes everything from OFFSET onward.'
    if (not defined $length) {
	$length = $size - $offset;
    }

    # 'If LENGTH is negative, leave that many elements off the end of
    # the array.'
    # 
    if ($length < 0) {
	$length = $size - $offset + $length;

	if ($length < 0) {
	    # The user must have specified a length bigger than the
	    # length of the array passed in.  But perl's splice()
	    # doesn't catch this, it just behaves as for length=0.
	    # 
	    $length = 0;
	}
    }

    if ($length > $size - $offset) {
	$length = $size - $offset;
    }

    # $num_elems holds the current number of elements in the database.
    my $num_elems = $size;

    # 'Removes the elements designated by OFFSET and LENGTH from an
    # array,'...
    # 
    my @removed = ();
    foreach (0 .. $length - 1) {
	my $old;
	my $status = $self->get($offset, $old);
	if ($status != 0) {
	    my $msg = "error from Berkeley DB on get($offset, \$old)";
	    if ($status == 1) {
		$msg .= ' (no such element?)';
	    }
	    else {
		$msg .= ": error status $status";
		if (defined $! and $! ne '') {
		    $msg .= ", message $!";
		}
	    }
	    die $msg;
	}
	push @removed, $old;

	$status = $self->del($offset);
	if ($status != 0) {
	    my $msg = "error from Berkeley DB on del($offset)";
	    if ($status == 1) {
		$msg .= ' (no such element?)';
	    }
	    else {
		$msg .= ": error status $status";
		if (defined $! and $! ne '') {
		    $msg .= ", message $!";
		}
	    }
	    die $msg;
	}

	-- $num_elems;
    }

    # ...'and replaces them with the elements of LIST, if any.'
    my $pos = $offset;
    while (defined (my $elem = shift @list)) {
	my $old_pos = $pos;
	my $status;
	if ($pos >= $num_elems) {
	    $status = $self->put($pos, $elem);
	}
	else {
	    $status = $self->put($pos, $elem, $self->R_IBEFORE);
	}

	if ($status != 0) {
	    my $msg = "error from Berkeley DB on put($pos, $elem, ...)";
	    if ($status == 1) {
		$msg .= ' (no such element?)';
	    }
	    else {
		$msg .= ", error status $status";
		if (defined $! and $! ne '') {
		    $msg .= ", message $!";
		}
	    }
	    die $msg;
	}

	die "pos unexpectedly changed from $old_pos to $pos with R_IBEFORE"
	  if $old_pos != $pos;

	++ $pos;
	++ $num_elems;
    }

    if (wantarray) {
	# 'In list context, returns the elements removed from the
	# array.'
	# 
	return @removed;
    }
    elsif (defined wantarray and not wantarray) {
	# 'In scalar context, returns the last element removed, or
	# undef if no elements are removed.'
	# 
	if (@removed) {
	    my $last = pop @removed;
	    return "$last";
	}
	else {
	    return undef;
	}
    }
    elsif (not defined wantarray) {
	# Void context
    }
    else { die }
}
sub ::DB_File::splice { &SPLICE }

sub find_dup
{
    croak "Usage: \$db->find_dup(key,value)\n"
        unless @_ == 3 ;
 
    my $db        = shift ;
    my ($origkey, $value_wanted) = @_ ;
    my ($key, $value) = ($origkey, 0);
    my ($status) = 0 ;

    for ($status = $db->seq($key, $value, R_CURSOR() ) ;
         $status == 0 ;
         $status = $db->seq($key, $value, R_NEXT() ) ) {

        return 0 if $key eq $origkey and $value eq $value_wanted ;
    }

    return $status ;
}

sub del_dup
{
    croak "Usage: \$db->del_dup(key,value)\n"
        unless @_ == 3 ;
 
    my $db        = shift ;
    my ($key, $value) = @_ ;
    my ($status) = $db->find_dup($key, $value) ;
    return $status if $status != 0 ;

    $status = $db->del($key, R_CURSOR() ) ;
    return $status ;
}

sub get_dup
{
    croak "Usage: \$db->get_dup(key [,flag])\n"
        unless @_ == 2 or @_ == 3 ;
 
    my $db        = shift ;
    my $key       = shift ;
    my $flag	  = shift ;
    my $value 	  = 0 ;
    my $origkey   = $key ;
    my $wantarray = wantarray ;
    my %values	  = () ;
    my @values    = () ;
    my $counter   = 0 ;
    my $status    = 0 ;
 
    # iterate through the database until either EOF ($status == 0)
    # or a different key is encountered ($key ne $origkey).
    for ($status = $db->seq($key, $value, R_CURSOR()) ;
	 $status == 0 and $key eq $origkey ;
         $status = $db->seq($key, $value, R_NEXT()) ) {
 
        # save the value or count number of matches
        if ($wantarray) {
	    if ($flag)
                { ++ $values{$value} }
	    else
                { push (@values, $value) }
	}
        else
            { ++ $counter }
     
    }
 
    return ($wantarray ? ($flag ? %values : @values) : $counter) ;
}


sub STORABLE_freeze
{
    my $type = ref shift;
    croak "Cannot freeze $type object\n";
}

sub STORABLE_thaw
{
    my $type = ref shift;
    croak "Cannot thaw $type object\n";
}



1;
__END__

