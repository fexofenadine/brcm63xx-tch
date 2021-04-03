package HTML::Tagset;

use strict;


use vars qw( $VERSION );

$VERSION = '3.20';


use vars qw(
    $VERSION
    %emptyElement %optionalEndTag %linkElements %boolean_attr
    %isHeadElement %isBodyElement %isPhraseMarkup
    %is_Possible_Strict_P_Content
    %isHeadOrBodyElement
    %isList %isTableElement %isFormElement
    %isKnown %canTighten
    @p_closure_barriers
    %isCDATA_Parent
);


%emptyElement   = map {; $_ => 1 } qw(base link meta isindex
                                     img br hr wbr
                                     input area param
                                     embed bgsound spacer
                                     basefont col frame
                                     ~comment ~literal
                                     ~declaration ~pi
                                    );


%optionalEndTag = map {; $_ => 1 } qw(p li dt dd); # option th tr td);


%linkElements =
(
 'a'       => ['href'],
 'applet'  => ['archive', 'codebase', 'code'],
 'area'    => ['href'],
 'base'    => ['href'],
 'bgsound' => ['src'],
 'blockquote' => ['cite'],
 'body'    => ['background'],
 'del'     => ['cite'],
 'embed'   => ['pluginspage', 'src'],
 'form'    => ['action'],
 'frame'   => ['src', 'longdesc'],
 'iframe'  => ['src', 'longdesc'],
 'ilayer'  => ['background'],
 'img'     => ['src', 'lowsrc', 'longdesc', 'usemap'],
 'input'   => ['src', 'usemap'],
 'ins'     => ['cite'],
 'isindex' => ['action'],
 'head'    => ['profile'],
 'layer'   => ['background', 'src'],
 'link'    => ['href'],
 'object'  => ['classid', 'codebase', 'data', 'archive', 'usemap'],
 'q'       => ['cite'],
 'script'  => ['src', 'for'],
 'table'   => ['background'],
 'td'      => ['background'],
 'th'      => ['background'],
 'tr'      => ['background'],
 'xmp'     => ['href'],
);


%boolean_attr = (
  'area'   => 'nohref',
  'dir'    => 'compact',
  'dl'     => 'compact',
  'hr'     => 'noshade',
  'img'    => 'ismap',
  'input'  => { 'checked' => 1, 'readonly' => 1, 'disabled' => 1 },
  'menu'   => 'compact',
  'ol'     => 'compact',
  'option' => 'selected',
  'select' => 'multiple',
  'td'     => 'nowrap',
  'th'     => 'nowrap',
  'ul'     => 'compact',
);



%isPhraseMarkup = map {; $_ => 1 } qw(
  span abbr acronym q sub sup
  cite code em kbd samp strong var dfn strike
  b i u s tt small big 
  a img br
  wbr nobr blink
  font basefont bdo
  spacer embed noembed
);  # had: center, hr, table



%is_Possible_Strict_P_Content = (
 %isPhraseMarkup,
 %isFormElement,
 map {; $_ => 1} qw( object script map )
  # I've no idea why there's these latter exceptions.
  # I'm just following the HTML4.01 DTD.
);



%isHeadElement = map {; $_ => 1 }
 qw(title base link meta isindex script style object bgsound);


%isList         = map {; $_ => 1 } qw(ul ol dir menu);


%isTableElement = map {; $_ => 1 }
 qw(tr td th thead tbody tfoot caption col colgroup);


%isFormElement  = map {; $_ => 1 }
 qw(input select option optgroup textarea button label);


%isBodyElement = map {; $_ => 1 } qw(
  h1 h2 h3 h4 h5 h6
  p div pre plaintext address blockquote
  xmp listing
  center

  multicol
  iframe ilayer nolayer
  bgsound

  hr
  ol ul dir menu li
  dl dt dd
  ins del
  
  fieldset legend
  
  map area
  applet param object
  isindex script noscript
  table
  center
  form
 ),
 keys %isFormElement,
 keys %isPhraseMarkup,   # And everything phrasal
 keys %isTableElement,
;



%isHeadOrBodyElement = map {; $_ => 1 }
  qw(script isindex style object map area param noscript bgsound);
  # i.e., if we find 'script' in the 'body' or the 'head', don't freak out.



%isKnown = (%isHeadElement, %isBodyElement,
  map{; $_=>1 }
   qw( head body html
       frame frameset noframes
       ~comment ~pi ~directive ~literal
));
 # that should be all known tags ever ever



%canTighten = %isKnown;
delete @canTighten{
  keys(%isPhraseMarkup), 'input', 'select',
  'xmp', 'listing', 'plaintext', 'pre',
};
  # xmp, listing, plaintext, and pre  are untightenable, and
  #   in a really special way.
@canTighten{'hr','br'} = (1,1);
 # exceptional 'phrasal' things that ARE subject to tightening.




@p_closure_barriers = qw(
  li blockquote
  ul ol menu dir
  dl dt dd
  td th tr table caption
  div
 );



%isCDATA_Parent = map {; $_ => 1 }
  qw(script style  xmp listing plaintext);





1;
