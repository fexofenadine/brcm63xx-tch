package Locale::Codes::Constants;

use strict;
use warnings;

require Exporter;


our($VERSION,@ISA,@EXPORT);
our(%ALL_CODESETS);

$VERSION='3.30';
@ISA     = qw(Exporter);
@EXPORT  = qw(LOCALE_CODE_ALPHA_2
              LOCALE_CODE_ALPHA_3
              LOCALE_CODE_NUMERIC
              LOCALE_CODE_DOM

              LOCALE_LANG_ALPHA_2
              LOCALE_LANG_ALPHA_3
              LOCALE_LANG_TERM

              LOCALE_CURR_ALPHA
              LOCALE_CURR_NUMERIC

              LOCALE_SCRIPT_ALPHA
              LOCALE_SCRIPT_NUMERIC

              LOCALE_LANGEXT_ALPHA

              LOCALE_LANGVAR_ALPHA

              LOCALE_LANGFAM_ALPHA

              %ALL_CODESETS
            );


use constant LOCALE_CODE_ALPHA_2    => 'alpha-2';
use constant LOCALE_CODE_ALPHA_3    => 'alpha-3';
use constant LOCALE_CODE_NUMERIC    => 'numeric';
use constant LOCALE_CODE_DOM        => 'dom';

$ALL_CODESETS{'country'} = {
                            'default'  => 'alpha-2',
                            'codesets' => { 'alpha-2'  => ['lc'],
                                            'alpha-3'  => ['lc'],
                                            'numeric'  => ['numeric',3],
                                            'dom'      => ['lc'],
                                          }
                           };

use constant LOCALE_LANG_ALPHA_2    => 'alpha-2';
use constant LOCALE_LANG_ALPHA_3    => 'alpha-3';
use constant LOCALE_LANG_TERM       => 'term';

$ALL_CODESETS{'language'} = {
                             'default'  => 'alpha-2',
                             'codesets' => { 'alpha-2'  => ['lc'],
                                             'alpha-3'  => ['lc'],
                                             'term'     => ['lc'],
                                           }
                            };

use constant LOCALE_CURR_ALPHA      => 'alpha';
use constant LOCALE_CURR_NUMERIC    => 'num';

$ALL_CODESETS{'currency'} = {
                             'default'  => 'alpha',
                             'codesets' => { 'alpha'  => ['uc'],
                                             'num'    => ['numeric',3],
                                           }
                            };

use constant LOCALE_SCRIPT_ALPHA    => 'alpha';
use constant LOCALE_SCRIPT_NUMERIC  => 'num';

$ALL_CODESETS{'script'} = {
                           'default'  => 'alpha',
                           'codesets' => { 'alpha'  => ['ucfirst'],
                                           'num'    => ['numeric',3],
                                         }
                          };

use constant LOCALE_LANGEXT_ALPHA   => 'alpha';

$ALL_CODESETS{'langext'} = {
                           'default'  => 'alpha',
                           'codesets' => { 'alpha'  => ['lc'],
                                         }
                          };

use constant LOCALE_LANGVAR_ALPHA   => 'alpha';

$ALL_CODESETS{'langvar'} = {
                           'default'  => 'alpha',
                           'codesets' => { 'alpha'  => ['lc'],
                                         }
                          };

use constant LOCALE_LANGFAM_ALPHA   => 'alpha';

$ALL_CODESETS{'langfam'} = {
                           'default'  => 'alpha',
                           'codesets' => { 'alpha'  => ['lc'],
                                         }
                          };

1;
