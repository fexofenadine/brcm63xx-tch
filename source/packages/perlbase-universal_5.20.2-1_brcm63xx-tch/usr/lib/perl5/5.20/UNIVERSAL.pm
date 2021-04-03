package UNIVERSAL;

our $VERSION = '1.11';

require Exporter;
@EXPORT_OK = qw(isa can VERSION);

sub import {
    return unless $_[0] eq __PACKAGE__;
    return unless @_ > 1;
    require warnings;
    warnings::warnif(
      'deprecated',
      'UNIVERSAL->import is deprecated and will be removed in a future perl',
    );
    goto &Exporter::import;
}

1;
__END__

