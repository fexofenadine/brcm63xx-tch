package App::Cpan;

use strict;
use warnings;
use vars qw($VERSION);

use if $] < 5.008 => "IO::Scalar";

$VERSION = '1.62';


use autouse Carp => qw(carp croak cluck);
use CPAN ();
use Config;
use autouse Cwd => qw(cwd);
use autouse 'Data::Dumper' => qw(Dumper);
use File::Spec::Functions;
use File::Basename;
use Getopt::Std;

use constant TRUE  => 1;
use constant FALSE => 0;


use constant HEY_IT_WORKED              =>   0;
use constant I_DONT_KNOW_WHAT_HAPPENED  =>   1; # 0b0000_0001
use constant ITS_NOT_MY_FAULT           =>   2;
use constant THE_PROGRAMMERS_AN_IDIOT   =>   4;
use constant A_MODULE_FAILED_TO_INSTALL =>   8;


BEGIN { # most of this should be in methods
use vars qw( @META_OPTIONS $Default %CPAN_METHODS @CPAN_OPTIONS  @option_order
	%Method_table %Method_table_index );

@META_OPTIONS = qw( h v V I g G C A D O l L a r p P j: J w T);

$Default = 'default';

%CPAN_METHODS = ( # map switches to method names in CPAN::Shell
	$Default => 'install',
	'c'      => 'clean',
	'f'      => 'force',
	'i'      => 'install',
	'm'      => 'make',
	't'      => 'test',
	'u'      => 'upgrade',
	);
@CPAN_OPTIONS = grep { $_ ne $Default } sort keys %CPAN_METHODS;

@option_order = ( @META_OPTIONS, @CPAN_OPTIONS );


sub NO_ARGS   () { 0 }
sub ARGS      () { 1 }
sub GOOD_EXIT () { 0 }

%Method_table = (

	# options that do their thing first, then exit
	h =>  [ \&_print_help,        NO_ARGS, GOOD_EXIT, 'Printing help'                ],
	v =>  [ \&_print_version,     NO_ARGS, GOOD_EXIT, 'Printing version'             ],
	V =>  [ \&_print_details,     NO_ARGS, GOOD_EXIT, 'Printing detailed version'    ],

	# options that affect other options
	j =>  [ \&_load_config,          ARGS, GOOD_EXIT, 'Use specified config file'    ],
	J =>  [ \&_dump_config,       NO_ARGS, GOOD_EXIT, 'Dump configuration to stdout' ],
	F =>  [ \&_lock_lobotomy,     NO_ARGS, GOOD_EXIT, 'Turn off CPAN.pm lock files'  ],
	I =>  [ \&_load_local_lib,    NO_ARGS, GOOD_EXIT, 'Loading local::lib'           ],
    w =>  [ \&_turn_on_warnings,  NO_ARGS, GOOD_EXIT, 'Turning on warnings'          ],
    T =>  [ \&_turn_off_testing,  NO_ARGS, GOOD_EXIT, 'Turning off testing'          ],

	# options that do their one thing
	g =>  [ \&_download,          NO_ARGS, GOOD_EXIT, 'Download the latest distro'        ],
	G =>  [ \&_gitify,            NO_ARGS, GOOD_EXIT, 'Down and gitify the latest distro' ],

	C =>  [ \&_show_Changes,         ARGS, GOOD_EXIT, 'Showing Changes file'         ],
	A =>  [ \&_show_Author,          ARGS, GOOD_EXIT, 'Showing Author'               ],
	D =>  [ \&_show_Details,         ARGS, GOOD_EXIT, 'Showing Details'              ],
	O =>  [ \&_show_out_of_date,  NO_ARGS, GOOD_EXIT, 'Showing Out of date'          ],
	l =>  [ \&_list_all_mods,     NO_ARGS, GOOD_EXIT, 'Listing all modules'          ],

	L =>  [ \&_show_author_mods,     ARGS, GOOD_EXIT, 'Showing author mods'          ],
	a =>  [ \&_create_autobundle, NO_ARGS, GOOD_EXIT, 'Creating autobundle'          ],
	p =>  [ \&_ping_mirrors,      NO_ARGS, GOOD_EXIT, 'Pinging mirrors'              ],
	P =>  [ \&_find_good_mirrors, NO_ARGS, GOOD_EXIT, 'Finding good mirrors'         ],

	r =>  [ \&_recompile,         NO_ARGS, GOOD_EXIT, 'Recompiling'                  ],
	u =>  [ \&_upgrade,           NO_ARGS, GOOD_EXIT, 'Running `make test`'          ],

	c =>  [ \&_default,              ARGS, GOOD_EXIT, 'Running `make clean`'         ],
	f =>  [ \&_default,              ARGS, GOOD_EXIT, 'Installing with force'        ],
	i =>  [ \&_default,              ARGS, GOOD_EXIT, 'Running `make install`'       ],
   'm' => [ \&_default,              ARGS, GOOD_EXIT, 'Running `make`'               ],
	t =>  [ \&_default,              ARGS, GOOD_EXIT, 'Running `make test`'          ],
	);

%Method_table_index = (
	code        => 0,
	takes_args  => 1,
	exit_value  => 2,
	description => 3,
	);
}



sub _stupid_interface_hack_for_non_rtfmers
	{
	no warnings 'uninitialized';
	shift @ARGV if( $ARGV[0] eq 'install' and @ARGV > 1 )
	}

sub _process_options
	{
	my %options;

	push @ARGV, grep $_, split /\s+/, $ENV{CPAN_OPTS} || '';

	# if no arguments, just drop into the shell
	if( 0 == @ARGV ) { CPAN::shell(); exit 0 }
	else
		{
		Getopt::Std::getopts(
		  join( '', @option_order ), \%options );
		 \%options;
		}
	}

sub _process_setup_options
	{
	my( $class, $options ) = @_;

	if( $options->{j} )
		{
		$Method_table{j}[ $Method_table_index{code} ]->( $options->{j} );
		delete $options->{j};
		}
	else
		{
		# this is what CPAN.pm would do otherwise
		local $CPAN::Be_Silent = 1;
		CPAN::HandleConfig->load(
			# be_silent  => 1, deprecated
			write_file => 0,
			);
		}

	foreach my $o ( qw(F I w T) )
		{
		next unless exists $options->{$o};
		$Method_table{$o}[ $Method_table_index{code} ]->( $options->{$o} );
		delete $options->{$o};
		}

	if( $options->{o} )
		{
		my @pairs = map { [ split /=/, $_, 2 ] } split /,/, $options->{o};
		foreach my $pair ( @pairs )
			{
			my( $setting, $value ) = @$pair;
			$CPAN::Config->{$setting} = $value;
		#	$logger->debug( "Setting [$setting] to [$value]" );
			}
		delete $options->{o};
		}

	my $option_count = grep { $options->{$_} } @option_order;
	no warnings 'uninitialized';
	$option_count -= $options->{'f'}; # don't count force

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
	# if there are no options, set -i (this line fixes RT ticket 16915)
	$options->{i}++ unless $option_count;
	}



my $logger;

sub run
	{
	my $class = shift;

	my $return_value = HEY_IT_WORKED; # assume that things will work

	$logger = $class->_init_logger;
	$logger->debug( "Using logger from @{[ref $logger]}" );

	$class->_hook_into_CPANpm_report;
	$logger->debug( "Hooked into output" );

	$class->_stupid_interface_hack_for_non_rtfmers;
	$logger->debug( "Patched cargo culting" );

	my $options = $class->_process_options;
	$logger->debug( "Options are @{[Dumper($options)]}" );

	$class->_process_setup_options( $options );

	OPTION: foreach my $option ( @option_order )
		{
		next unless $options->{$option};

		my( $sub, $takes_args, $description ) =
			map { $Method_table{$option}[ $Method_table_index{$_} ] }
			qw( code takes_args );

		unless( ref $sub eq ref sub {} )
			{
			$return_value = THE_PROGRAMMERS_AN_IDIOT;
			last OPTION;
			}

		$logger->info( "$description -- ignoring other arguments" )
			if( @ARGV && ! $takes_args );

		$return_value = $sub->( \ @ARGV, $options );

		last;
		}

	return $return_value;
	}

{
package
  Local::Null::Logger; # hide from PAUSE

sub new { bless \ my $x, $_[0] }
sub AUTOLOAD { 1 }
sub DESTROY { 1 }
}

sub _init_logger
	{
	my $log4perl_loaded = eval "require Log::Log4perl; 1";

    unless( $log4perl_loaded )
        {
        $logger = Local::Null::Logger->new;
        return $logger;
        }

	my $LEVEL = $ENV{CPANSCRIPT_LOGLEVEL} || 'INFO';

	Log::Log4perl::init( \ <<"HERE" );
log4perl.rootLogger=$LEVEL, A1
log4perl.appender.A1=Log::Log4perl::Appender::Screen
log4perl.appender.A1.layout=PatternLayout
log4perl.appender.A1.layout.ConversionPattern=%m%n
HERE

	$logger = Log::Log4perl->get_logger( 'App::Cpan' );
	}

 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

sub _default
	{
	my( $args, $options ) = @_;

	my $switch = '';

	# choose the option that we're going to use
	# we'll deal with 'f' (force) later, so skip it
	foreach my $option ( @CPAN_OPTIONS )
		{
		next if $option eq 'f';
		next unless $options->{$option};
		$switch = $option;
		last;
		}

	# 1. with no switches, but arguments, use the default switch (install)
	# 2. with no switches and no args, start the shell
	# 3. With a switch but no args, die! These switches need arguments.
	   if( not $switch and     @$args ) { $switch = $Default;  }
	elsif( not $switch and not @$args ) { return CPAN::shell() }
	elsif(     $switch and not @$args )
		{ die "Nothing to $CPAN_METHODS{$switch}!\n"; }

	# Get and check the method from CPAN::Shell
	my $method = $CPAN_METHODS{$switch};
	die "CPAN.pm cannot $method!\n" unless CPAN::Shell->can( $method );

	# call the CPAN::Shell method, with force if specified
	my $action = do {
		if( $options->{f} ) { sub { CPAN::Shell->force( $method, @_ ) } }
		else                { sub { CPAN::Shell->$method( @_ )        } }
		};

	# How do I handle exit codes for multiple arguments?
	my $errors = 0;

	foreach my $arg ( @$args )
		{
		_clear_cpanpm_output();
		$action->( $arg );

		$errors += defined _cpanpm_output_indicates_failure();
		}

	$errors ? I_DONT_KNOW_WHAT_HAPPENED : HEY_IT_WORKED;
	}



BEGIN {
my $scalar = '';

sub _hook_into_CPANpm_report
	{
	no warnings 'redefine';

	*CPAN::Shell::myprint = sub {
		my($self,$what) = @_;
		$scalar .= $what;
		$self->print_ornamented($what,
			$CPAN::Config->{colorize_print}||'bold blue on_white',
			);
		};

	*CPAN::Shell::mywarn = sub {
		my($self,$what) = @_;
		$scalar .= $what;
		$self->print_ornamented($what,
			$CPAN::Config->{colorize_warn}||'bold red on_white'
			);
		};

	}

sub _clear_cpanpm_output { $scalar = '' }

sub _get_cpanpm_output   { $scalar }

my @skip_lines = (
	qr/^\QWarning \(usually harmless\)/,
	qr/\bwill not store persistent state\b/,
	qr(//hint//),
	qr/^\s+reports\s+/,
	);

sub _get_cpanpm_last_line
	{
	my $fh;
	if ($] < 5.008) {
		$fh = IO::Scalar->new(\ $scalar);
        } else {
		eval q{open $fh, "<", \\ $scalar;};
        }

	my @lines = <$fh>;

    # This is a bit ugly. Once we examine a line, we have to
    # examine the line before it and go through all of the same
    # regexes. I could do something fancy, but this works.
    REGEXES: {
	foreach my $regex ( @skip_lines )
		{
		if( $lines[-1] =~ m/$regex/ )
            {
            pop @lines;
            redo REGEXES; # we have to go through all of them for every line!
            }
		}
	}

    $logger->debug( "Last interesting line of CPAN.pm output is:\n\t$lines[-1]" );

	$lines[-1];
	}
}

BEGIN {
my $epic_fail_words = join '|',
	qw( Error stop(?:ping)? problems force not unsupported fail(?:ed)? );

sub _cpanpm_output_indicates_failure
	{
	my $last_line = _get_cpanpm_last_line();

	my $result = $last_line =~ /\b(?:$epic_fail_words)\b/i;
	$result || ();
	}
}

sub _cpanpm_output_indicates_success
	{
	my $last_line = _get_cpanpm_last_line();

	my $result = $last_line =~ /\b(?:\s+-- OK|PASS)\b/;
	$result || ();
	}

sub _cpanpm_output_is_vague
	{
	return FALSE if
		_cpanpm_output_indicates_failure() ||
		_cpanpm_output_indicates_success();

	return TRUE;
	}

sub _turn_on_warnings {
	carp "Warnings are implemented yet";
	return HEY_IT_WORKED;
	}

sub _turn_off_testing {
	$logger->debug( 'Trusting test report history' );
	$CPAN::Config->{trust_test_report_history} = 1;
	return HEY_IT_WORKED;
	}

sub _print_help
	{
	$logger->info( "Use perldoc to read the documentation" );
	exec "perldoc $0";
	}

sub _print_version # -v
	{
	$logger->info(
		"$0 script version $VERSION, CPAN.pm version " . CPAN->VERSION );

	return HEY_IT_WORKED;
	}

sub _print_details # -V
	{
	_print_version();

	_check_install_dirs();

	$logger->info( '-' x 50 . "\nChecking configured mirrors..." );
	foreach my $mirror ( @{ $CPAN::Config->{urllist} } ) {
		_print_ping_report( $mirror );
		}

	$logger->info( '-' x 50 . "\nChecking for faster mirrors..." );

	{
	require CPAN::Mirrors;

      if ( $CPAN::Config->{connect_to_internet_ok} ) {
        $CPAN::Frontend->myprint(qq{Trying to fetch a mirror list from the Internet\n});
        eval { CPAN::FTP->localize('MIRRORED.BY',File::Spec->catfile($CPAN::Config->{keep_source_where},'MIRRORED.BY'),3,1) }
          or $CPAN::Frontend->mywarn(<<'HERE');
We failed to get a copy of the mirror list from the Internet.
You will need to provide CPAN mirror URLs yourself.
HERE
        $CPAN::Frontend->myprint("\n");
      }

	my $mirrors   = CPAN::Mirrors->new(  );
	$mirrors->parse_mirrored_by( File::Spec->catfile($CPAN::Config->{keep_source_where},'MIRRORED.BY') );
	my @continents = $mirrors->find_best_continents;

	my @mirrors   = $mirrors->get_mirrors_by_continents( $continents[0] );
	my @timings   = $mirrors->get_mirrors_timings( \@mirrors );

	foreach my $timing ( @timings ) {
		$logger->info( sprintf "%s (%0.2f ms)",
			$timing->hostname, $timing->rtt );
		}
	}

	return HEY_IT_WORKED;
	}

sub _check_install_dirs
	{
	my $makepl_arg   = $CPAN::Config->{makepl_arg};
	my $mbuildpl_arg = $CPAN::Config->{mbuildpl_arg};

	my @custom_dirs;
	# PERL_MM_OPT
	push @custom_dirs,
		$makepl_arg   =~ m/INSTALL_BASE\s*=\s*(\S+)/g,
		$mbuildpl_arg =~ m/--install_base\s*=\s*(\S+)/g;

	if( @custom_dirs ) {
		foreach my $dir ( @custom_dirs ) {
			_print_inc_dir_report( $dir );
			}
		}

	# XXX: also need to check makepl_args, etc

	my @checks = (
		[ 'core',         [ grep $_, @Config{qw(installprivlib installarchlib)}      ] ],
		[ 'vendor',       [ grep $_, @Config{qw(installvendorlib installvendorarch)} ] ],
		[ 'site',         [ grep $_, @Config{qw(installsitelib installsitearch)}     ] ],
		[ 'PERL5LIB',     _split_paths( $ENV{PERL5LIB} ) ],
		[ 'PERLLIB',      _split_paths( $ENV{PERLLIB} )  ],
		);

	$logger->info( '-' x 50 . "\nChecking install dirs..." );
	foreach my $tuple ( @checks ) {
		my( $label ) = $tuple->[0];

		$logger->info( "Checking $label" );
		$logger->info( "\tno directories for $label" ) unless @{ $tuple->[1] };
		foreach my $dir ( @{ $tuple->[1] } ) {
			_print_inc_dir_report( $dir );
			}
		}

	}

sub _split_paths
	{
	[ map { _expand_filename( $_ ) } split /$Config{path_sep}/, $_[0] || '' ];
	}



sub _expand_filename
	{
    my( $path ) = @_;
    no warnings 'uninitialized';
    $logger->debug( "Expanding path $path\n" );
    $path =~ s{\A~([^/]+)?}{
		_home_of( $1 || $> ) || "~$1"
    	}e;
    return $path;
	}

sub _home_of
	{
	require User::pwent;
    my( $user ) = @_;
    my $ent = User::pwent::getpw($user) or return;
    return $ent->dir;
	}

sub _get_default_inc
	{
	require Config;

	[ @Config::Config{ _vars() }, '.' ];
	}

sub _vars {
	qw(
	installarchlib
	installprivlib
	installsitearch
	installsitelib
	);
	}

sub _ping_mirrors {
	my $urls   = $CPAN::Config->{urllist};
	require URI;

	foreach my $url ( @$urls ) {
		my( $obj ) = URI->new( $url );
		next unless _is_pingable_scheme( $obj );
		my $host = $obj->host;
		_print_ping_report( $obj );
		}

	}

sub _is_pingable_scheme {
	my( $uri ) = @_;

	$uri->scheme eq 'file'
	}

sub _find_good_mirrors {
	require CPAN::Mirrors;

	my $mirrors = CPAN::Mirrors->new;
	my $file = do {
		my $file = 'MIRRORED.BY';
		my $local_path = File::Spec->catfile(
			$CPAN::Config->{keep_source_where}, $file );

		if( -e $local_path ) { $local_path }
		else {
			require CPAN::FTP;
			CPAN::FTP->localize( $file, $local_path, 3, 1 );
			$local_path;
			}
		};

	$mirrors->parse_mirrored_by( $file );

	my @mirrors = $mirrors->best_mirrors(
		how_many   => 3,
		verbose    => 1,
		);

	foreach my $mirror ( @mirrors ) {
		next unless eval { $mirror->can( 'http' ) };
		_print_ping_report( $mirror->http );
		}

	}

sub _print_inc_dir_report
	{
	my( $dir ) = shift;

	my $writeable = -w $dir ? '+' : '!!! (not writeable)';
	$logger->info( "\t$writeable $dir" );
	return -w $dir;
	}

sub _print_ping_report
	{
	my( $mirror ) = @_;

	my $rtt = eval { _get_ping_report( $mirror ) };

	$logger->info(
		sprintf "\t%s (%4d ms) %s", $rtt  ? '+' : '!',  $rtt * 1000, $mirror
		);
	}

sub _get_ping_report
	{
	require URI;
	my( $mirror ) = @_;
	my( $url ) = ref $mirror ? $mirror : URI->new( $mirror ); #XXX
	require Net::Ping;

	my $ping = Net::Ping->new( 'tcp', 1 );

	if( $url->scheme eq 'file' ) {
		return -e $url->file;
		}

    my( $port ) = $url->port;

    return unless $port;

    if ( $ping->can('port_number') ) {
        $ping->port_number($port);
    	}
    else {
        $ping->{'port_num'} = $port;
    	}

    $ping->hires(1) if $ping->can( 'hires' );
    my( $alive, $rtt ) = eval{ $ping->ping( $url->host ) };
	$alive ? $rtt : undef;
	}

sub _load_local_lib # -I
	{
	$logger->debug( "Loading local::lib" );

	my $rc = eval { require local::lib; 1; };
	unless( $rc ) {
		$logger->die( "Could not load local::lib" );
		}

	local::lib->import;

	return HEY_IT_WORKED;
	}

sub _create_autobundle
	{
	$logger->info(
		"Creating autobundle in $CPAN::Config->{cpan_home}/Bundle" );

	CPAN::Shell->autobundle;

	return HEY_IT_WORKED;
	}

sub _recompile
	{
	$logger->info( "Recompiling dynamically-loaded extensions" );

	CPAN::Shell->recompile;

	return HEY_IT_WORKED;
	}

sub _upgrade
	{
	$logger->info( "Upgrading all modules" );

	CPAN::Shell->upgrade();

	return HEY_IT_WORKED;
	}

sub _load_config # -j
	{
	my $file = shift || '';

	# should I clear out any existing config here?
	$CPAN::Config = {};
	delete $INC{'CPAN/Config.pm'};
	croak( "Config file [$file] does not exist!\n" ) unless -e $file;

	my $rc = eval "require '$file'";

	# CPAN::HandleConfig::require_myconfig_or_config looks for this
	$INC{'CPAN/MyConfig.pm'} = 'fake out!';

	# CPAN::HandleConfig::load looks for this
	$CPAN::Config_loaded = 'fake out';

	croak( "Could not load [$file]: $@\n") unless $rc;

	return HEY_IT_WORKED;
	}

sub _dump_config # -J
	{
	my $args = shift;
	require Data::Dumper;

	my $fh = $args->[0] || \*STDOUT;

	local $Data::Dumper::Sortkeys = 1;
	my $dd = Data::Dumper->new(
		[$CPAN::Config],
		['$CPAN::Config']
		);

	print $fh $dd->Dump, "\n1;\n__END__\n";

	return HEY_IT_WORKED;
	}

sub _lock_lobotomy # -F
	{
	no warnings 'redefine';

	*CPAN::_flock    = sub { 1 };
	*CPAN::checklock = sub { 1 };

	return HEY_IT_WORKED;
	}

sub _download
	{
	my $args = shift;

	local $CPAN::DEBUG = 1;

	my %paths;

	foreach my $module ( @$args )
		{
		$logger->info( "Checking $module" );
		my $path = CPAN::Shell->expand( "Module", $module )->cpan_file;

		$logger->debug( "Inst file would be $path\n" );

		$paths{$module} = _get_file( _make_path( $path ) );
		}

	return \%paths;
	}

sub _make_path { join "/", qw(authors id), $_[0] }

sub _get_file
	{
	my $path = shift;

	my $loaded = eval "require LWP::Simple; 1;";
	croak "You need LWP::Simple to use features that fetch files from CPAN\n"
		unless $loaded;

	my $file = substr $path, rindex( $path, '/' ) + 1;
	my $store_path = catfile( cwd(), $file );
	$logger->debug( "Store path is $store_path" );

	foreach my $site ( @{ $CPAN::Config->{urllist} } )
		{
		my $fetch_path = join "/", $site, $path;
		$logger->debug( "Trying $fetch_path" );
	    last if LWP::Simple::getstore( $fetch_path, $store_path );
		}

	return $store_path;
	}

sub _gitify
	{
	my $args = shift;

	my $loaded = eval "require Archive::Extract; 1;";
	croak "You need Archive::Extract to use features that gitify distributions\n"
		unless $loaded;

	my $starting_dir = cwd();

	foreach my $module ( @$args )
		{
		$logger->info( "Checking $module" );
		my $path = CPAN::Shell->expand( "Module", $module )->cpan_file;

		my $store_paths = _download( [ $module ] );
		$logger->debug( "gitify Store path is $store_paths->{$module}" );
		my $dirname = dirname( $store_paths->{$module} );

		my $ae = Archive::Extract->new( archive => $store_paths->{$module} );
		$ae->extract( to => $dirname );

		chdir $ae->extract_path;

		my $git = $ENV{GIT_COMMAND} || '/usr/local/bin/git';
		croak "Could not find $git"    unless -e $git;
		croak "$git is not executable" unless -x $git;

		# can we do this in Pure Perl?
		system( $git, 'init'    );
		system( $git, qw( add . ) );
		system( $git, qw( commit -a -m ), 'initial import' );
		}

	chdir $starting_dir;

	return HEY_IT_WORKED;
	}

sub _show_Changes
	{
	my $args = shift;

	foreach my $arg ( @$args )
		{
		$logger->info( "Checking $arg\n" );

		my $module = eval { CPAN::Shell->expand( "Module", $arg ) };
		my $out = _get_cpanpm_output();

		next unless eval { $module->inst_file };
		#next if $module->uptodate;

		( my $id = $module->id() ) =~ s/::/\-/;

		my $url = "http://search.cpan.org/~" . lc( $module->userid ) . "/" .
			$id . "-" . $module->cpan_version() . "/";

		#print "URL: $url\n";
		_get_changes_file($url);
		}

	return HEY_IT_WORKED;
	}

sub _get_changes_file
	{
	croak "Reading Changes files requires LWP::Simple and URI\n"
		unless eval "require LWP::Simple; require URI; 1";

    my $url = shift;

    my $content = LWP::Simple::get( $url );
    $logger->info( "Got $url ..." ) if defined $content;
	#print $content;

	my( $change_link ) = $content =~ m|<a href="(.*?)">Changes</a>|gi;

	my $changes_url = URI->new_abs( $change_link, $url );
 	$logger->debug( "Change link is: $changes_url" );

	my $changes =  LWP::Simple::get( $changes_url );

	print $changes;

	return HEY_IT_WORKED;
	}

sub _show_Author
	{
	my $args = shift;

	foreach my $arg ( @$args )
		{
		my $module = CPAN::Shell->expand( "Module", $arg );
		unless( $module )
			{
			$logger->info( "Didn't find a $arg module, so no author!" );
			next;
			}

		my $author = CPAN::Shell->expand( "Author", $module->userid );

		next unless $module->userid;

		printf "%-25s %-8s %-25s %s\n",
			$arg, $module->userid, $author->email, $author->name;
		}

	return HEY_IT_WORKED;
	}

sub _show_Details
	{
	my $args = shift;

	foreach my $arg ( @$args )
		{
		my $module = CPAN::Shell->expand( "Module", $arg );
		my $author = CPAN::Shell->expand( "Author", $module->userid );

		next unless $module->userid;

		print "$arg\n", "-" x 73, "\n\t";
		print join "\n\t",
			$module->description ? $module->description : "(no description)",
			$module->cpan_file,
			$module->inst_file,
			'Installed: ' . $module->inst_version,
			'CPAN:      ' . $module->cpan_version . '  ' .
				($module->uptodate ? "" : "Not ") . "up to date",
			$author->fullname . " (" . $module->userid . ")",
			$author->email;
		print "\n\n";

		}

	return HEY_IT_WORKED;
	}

sub _show_out_of_date
	{
	my @modules = CPAN::Shell->expand( "Module", "/./" );

	printf "%-40s  %6s  %6s\n", "Module Name", "Local", "CPAN";
	print "-" x 73, "\n";

	foreach my $module ( @modules )
		{
		next unless $module->inst_file;
		next if $module->uptodate;
		printf "%-40s  %.4f  %.4f\n",
			$module->id,
			$module->inst_version ? $module->inst_version : '',
			$module->cpan_version;
		}

	return HEY_IT_WORKED;
	}

sub _show_author_mods
	{
	my $args = shift;

	my %hash = map { lc $_, 1 } @$args;

	my @modules = CPAN::Shell->expand( "Module", "/./" );

	foreach my $module ( @modules )
		{
		next unless exists $hash{ lc $module->userid };
		print $module->id, "\n";
		}

	return HEY_IT_WORKED;
	}

sub _list_all_mods # -l
	{
	require File::Find;

	my $args = shift;


	my $fh = \*STDOUT;

	INC: foreach my $inc ( @INC )
		{
		my( $wanted, $reporter ) = _generator();
		File::Find::find( { wanted => $wanted }, $inc );

		my $count = 0;
		FILE: foreach my $file ( @{ $reporter->() } )
			{
			my $version = _parse_version_safely( $file );

			my $module_name = _path_to_module( $inc, $file );
			next FILE unless defined $module_name;

			print $fh "$module_name\t$version\n";

			#last if $count++ > 5;
			}
		}

	return HEY_IT_WORKED;
	}

sub _generator
	{
	my @files = ();

	sub { push @files,
		File::Spec->canonpath( $File::Find::name )
		if m/\A\w+\.pm\z/ },
	sub { \@files },
	}

sub _parse_version_safely # stolen from PAUSE's mldistwatch, but refactored
	{
	my( $file ) = @_;

	local $/ = "\n";
	local $_; # don't mess with the $_ in the map calling this

	return unless open FILE, "<$file";

	my $in_pod = 0;
	my $version;
	while( <FILE> )
		{
		chomp;
		$in_pod = /^=(?!cut)/ ? 1 : /^=cut/ ? 0 : $in_pod;
		next if $in_pod || /^\s*#/;

		next unless /([\$*])(([\w\:\']*)\bVERSION)\b.*\=/;
		my( $sigil, $var ) = ( $1, $2 );

		$version = _eval_version( $_, $sigil, $var );
		last;
		}
	close FILE;

	return 'undef' unless defined $version;

	return $version;
	}

sub _eval_version
	{
	my( $line, $sigil, $var ) = @_;

        # split package line to hide from PAUSE
	my $eval = qq{
		package
                  ExtUtils::MakeMaker::_version;

		local $sigil$var;
		\$$var=undef; do {
			$line
			}; \$$var
		};

	my $version = do {
		local $^W = 0;
		no strict;
		eval( $eval );
		};

	return $version;
	}

sub _path_to_module
	{
	my( $inc, $path ) = @_;
	return if length $path< length $inc;

	my $module_path = substr( $path, length $inc );
	$module_path =~ s/\.pm\z//;

	# XXX: this is cheating and doesn't handle everything right
	my @dirs = grep { ! /\W/ } File::Spec->splitdir( $module_path );
	shift @dirs;

	my $module_name = join "::", @dirs;

	return $module_name;
	}

1;

