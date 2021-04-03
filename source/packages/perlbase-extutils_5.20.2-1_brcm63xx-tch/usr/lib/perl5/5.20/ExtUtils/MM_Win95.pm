package ExtUtils::MM_Win95;

use strict;

our $VERSION = '6.98';

require ExtUtils::MM_Win32;
our @ISA = qw(ExtUtils::MM_Win32);

use ExtUtils::MakeMaker::Config;



sub xs_c {
    my($self) = shift;
    return '' unless $self->needs_linking();
    '
.xs.c:
	$(XSUBPPRUN) $(XSPROTOARG) $(XSUBPPARGS) $*.xs > $*.c
	'
}



sub xs_cpp {
    my($self) = shift;
    return '' unless $self->needs_linking();
    '
.xs.cpp:
	$(XSUBPPRUN) $(XSPROTOARG) $(XSUBPPARGS) $*.xs > $*.cpp
	';
}


sub xs_o {
    my($self) = shift;
    return '' unless $self->needs_linking();
    '
.xs$(OBJ_EXT):
	$(XSUBPPRUN) $(XSPROTOARG) $(XSUBPPARGS) $*.xs > $*.c
	$(CCCMD) $(CCCDLFLAGS) -I$(PERL_INC) $(DEFINE) $*.c
	';
}



sub max_exec_len {
    my $self = shift;

    return $self->{_MAX_EXEC_LEN} ||= 1024;
}



sub os_flavor {
    my $self = shift;
    return ($self->SUPER::os_flavor, 'Win9x');
}




1;
