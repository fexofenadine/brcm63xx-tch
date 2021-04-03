package ExtUtils::MM_BeOS;

use strict;


use ExtUtils::MakeMaker::Config;
use File::Spec;
require ExtUtils::MM_Any;
require ExtUtils::MM_Unix;

our @ISA = qw( ExtUtils::MM_Any ExtUtils::MM_Unix );
our $VERSION = '6.98';



sub os_flavor {
    return('BeOS');
}


sub init_linker {
    my($self) = shift;

    $self->{PERL_ARCHIVE} ||=
      File::Spec->catdir('$(PERL_INC)',$Config{libperl});
    $self->{PERL_ARCHIVE_AFTER} ||= '';
    $self->{EXPORT_LIST}  ||= '';
}

