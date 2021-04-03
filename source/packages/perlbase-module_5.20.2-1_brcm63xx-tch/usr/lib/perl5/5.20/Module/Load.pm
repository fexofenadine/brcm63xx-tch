package Module::Load;

$VERSION = '0.32';

use strict;
use warnings;
use File::Spec ();

sub import {
    my $who = _who();
    my $h; shift;

    {   no strict 'refs';

        @_ or (
            *{"${who}::load"} = \&load, # compat to prev version
            *{"${who}::autoload"} = \&autoload,
            return
        );

        map { $h->{$_} = () if defined $_ } @_;

        (exists $h->{none} or exists $h->{''})
            and shift, last;

        ((exists $h->{autoload} and shift,1) or (exists $h->{all} and shift))
            and *{"${who}::autoload"} = \&autoload;

        ((exists $h->{load} and shift,1) or exists $h->{all})
            and *{"${who}::load"} = \&load;

        ((exists $h->{load_remote} and shift,1) or exists $h->{all})
            and *{"${who}::load_remote"} = \&load_remote;

        ((exists $h->{autoload_remote} and shift,1) or exists $h->{all})
            and *{"${who}::autoload_remote"} = \&autoload_remote;

    }

}

sub load(*;@){
    goto &_load;
}

sub autoload(*;@){
    unshift @_, 'autoimport';
    goto &_load;
}

sub load_remote($$;@){
    my ($dst, $src, @exp) = @_;

    eval "package $dst;Module::Load::load('$src', qw/@exp/);";
    $@ && die "$@";
}

sub autoload_remote($$;@){
    my ($dst, $src, @exp) = @_;

    eval "package $dst;Module::Load::autoload('$src', qw/@exp/);";
    $@ && die "$@";
}

sub _load{
    my $autoimport = $_[0] eq 'autoimport' and shift;
    my $mod = shift or return;
    my $who = _who();

    if( _is_file( $mod ) ) {
        require $mod;
    } else {
        LOAD: {
            my $err;
            for my $flag ( qw[1 0] ) {
                my $file = _to_file( $mod, $flag);
                eval { require $file };
                $@ ? $err .= $@ : last LOAD;
            }
            die $err if $err;
        }
    }

    ### This addresses #41883: Module::Load cannot import
    ### non-Exporter module. ->import() routines weren't
    ### properly called when load() was used.

    {   no strict 'refs';
        my $import;

    ((@_ or $autoimport) and (
        $import = $mod->can('import')
        ) and (
        unshift(@_, $mod),
        goto &$import,
        return
        )
    );
    }

}

sub _to_file{
    local $_    = shift;
    my $pm      = shift || '';

    ## trailing blanks ignored by default. [rt #69886]
    my @parts = split /::|'/, $_, -1;
    ## make sure that we can't hop out of @INC
    shift @parts if @parts && !$parts[0];

    ### because of [perl #19213], see caveats ###
    my $file = $^O eq 'MSWin32'
                    ? join "/", @parts
                    : File::Spec->catfile( @parts );

    $file   .= '.pm' if $pm;

    ### on perl's before 5.10 (5.9.5@31746) if you require
    ### a file in VMS format, it's stored in %INC in VMS
    ### format. Therefor, better unixify it first
    ### Patch in reply to John Malmbergs patch (as mentioned
    ### above) on p5p Tue 21 Aug 2007 04:55:07
    $file = VMS::Filespec::unixify($file) if $^O eq 'VMS';

    return $file;
}

sub _who { (caller(1))[0] }

sub _is_file {
    local $_ = shift;
    return  /^\./               ? 1 :
            /[^\w:']/           ? 1 :
            undef
    #' silly bbedit..
}


1;

__END__

