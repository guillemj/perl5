#!./perl

BEGIN {
    unshift @INC, 't';
    require Config;
    if (($Config::Config{'extensions'} !~ /\bB\b/) ){
        print "1..0 # Skip -- Perl configured without B module\n";
        exit 0;
    }
}

use warnings;
use strict;
use Test::More;

my $tests = 25; # not counting those in the __DATA__ section

use B::Deparse;
my $deparse = B::Deparse->new();
isa_ok($deparse, 'B::Deparse', 'instantiate a B::Deparse object');
my %deparse;

$/ = "\n####\n";
while (<DATA>) {
    chomp;
    $tests ++;
    # This code is pinched from the t/lib/common.pl for TODO.
    # It's not clear how to avoid duplication
    my %meta = (context => '');
    foreach my $what (qw(skip todo context options)) {
	s/^#\s*\U$what\E\s*(.*)\n//m and $meta{$what} = $1;
	# If the SKIP reason starts ? then it's taken as a code snippet to
	# evaluate. This provides the flexibility to have conditional SKIPs
	if ($meta{$what} && $meta{$what} =~ s/^\?//) {
	    my $temp = eval $meta{$what};
	    if ($@) {
		die "# In \U$what\E code reason:\n# $meta{$what}\n$@";
	    }
	    $meta{$what} = $temp;
	}
    }

    s/^\s*#\s*(.*)$//mg;
    my $desc = $1;
    die "Missing name in test $_" unless defined $desc;

    if ($meta{skip}) {
	# Like this to avoid needing a label SKIP:
	Test::More->builder->skip($meta{skip});
	next;
    }

    my ($input, $expected);
    if (/(.*)\n>>>>\n(.*)/s) {
	($input, $expected) = ($1, $2);
    }
    else {
	($input, $expected) = ($_, $_);
    }

    # parse options if necessary
    my $deparse = $meta{options}
	? $deparse{$meta{options}} ||=
	    new B::Deparse split /,/, $meta{options}
	: $deparse;

    my $coderef = eval "$meta{context};\n" . <<'EOC' . "sub {$input}";
# Tell B::Deparse about our ambient pragmas
my ($hint_bits, $warning_bits, $hinthash);
BEGIN {
    ($hint_bits, $warning_bits, $hinthash) = ($^H, ${^WARNING_BITS}, \%^H);
}
$deparse->ambient_pragmas (
    hint_bits    => $hint_bits,
    warning_bits => $warning_bits,
    '%^H'        => $hinthash,
);
EOC

    if ($@) {
	is($@, "", "compilation of $desc");
    }
    else {
	my $deparsed = $deparse->coderef2text( $coderef );
	my $regex = $expected;
	$regex =~ s/(\S+)/\Q$1/g;
	$regex =~ s/\s+/\\s+/g;
	$regex = '^\{\s*' . $regex . '\s*\}$';

	local $::TODO = $meta{todo};
        like($deparsed, qr/$regex/, $desc);
    }
}

# Reset the ambient pragmas
{
    my ($b, $w, $h);
    BEGIN {
        ($b, $w, $h) = ($^H, ${^WARNING_BITS}, \%^H);
    }
    $deparse->ambient_pragmas (
        hint_bits    => $b,
        warning_bits => $w,
        '%^H'        => $h,
    );
}

use constant 'c', 'stuff';
is((eval "sub ".$deparse->coderef2text(\&c))->(), 'stuff',
   'the subroutine generated by use constant deparses');

my $a = 0;
is($deparse->coderef2text(sub{(-1) ** $a }), "{\n    (-1) ** \$a;\n}",
   'anon sub capturing an external lexical');

use constant cr => ['hello'];
my $string = "sub " . $deparse->coderef2text(\&cr);
my $val = (eval $string)->() or diag $string;
is(ref($val), 'ARRAY', 'constant array references deparse');
is($val->[0], 'hello', 'and return the correct value');

my $path = join " ", map { qq["-I$_"] } @INC;

$a = `$^X $path "-MO=Deparse" -anlwi.bak -e 1 2>&1`;
$a =~ s/-e syntax OK\n//g;
$a =~ s/.*possible typo.*\n//;	   # Remove warning line
$a =~ s/.*-i used with no filenames.*\n//;	# Remove warning line
$a =~ s{\\340\\242}{\\s} if (ord("\\") == 224); # EBCDIC, cp 1047 or 037
$a =~ s{\\274\\242}{\\s} if (ord("\\") == 188); # $^O eq 'posix-bc'
$b = quotemeta <<'EOF';
BEGIN { $^I = ".bak"; }
BEGIN { $^W = 1; }
BEGIN { $/ = "\n"; $\ = "\n"; }
LINE: while (defined($_ = <ARGV>)) {
    chomp $_;
    our(@F) = split(' ', $_, 0);
    '???';
}
EOF
$b =~ s/our\\\(\\\@F\\\)/our[( ]\@F\\)?/; # accept both our @F and our(@F)
like($a, qr/$b/,
   'command line flags deparse as BEGIN blocks setting control variables');

$a = `$^X $path "-MO=Deparse" -e "use constant PI => 4" 2>&1`;
$a =~ s/-e syntax OK\n//g;
is($a, "use constant ('PI', 4);\n",
   "Proxy Constant Subroutines must not show up as (incorrect) prototypes");

#Re: perlbug #35857, patch #24505
#handle warnings::register-ed packages properly.
package B::Deparse::Wrapper;
use strict;
use warnings;
use warnings::register;
sub getcode {
   my $deparser = B::Deparse->new();
   return $deparser->coderef2text(shift);
}

package Moo;
use overload '0+' => sub { 42 };

package main;
use strict;
use warnings;
use constant GLIPP => 'glipp';
use constant PI => 4;
use constant OVERLOADED_NUMIFICATION => bless({}, 'Moo');
use Fcntl qw/O_TRUNC O_APPEND O_EXCL/;
BEGIN { delete $::Fcntl::{O_APPEND}; }
use POSIX qw/O_CREAT/;
sub test {
   my $val = shift;
   my $res = B::Deparse::Wrapper::getcode($val);
   like($res, qr/use warnings/,
	'[perl #35857] [PATCH] B::Deparse doesnt handle warnings register properly');
}
my ($q,$p);
my $x=sub { ++$q,++$p };
test($x);
eval <<EOFCODE and test($x);
   package bar;
   use strict;
   use warnings;
   use warnings::register;
   package main;
   1
EOFCODE

# Exotic sub declarations
$a = `$^X $path "-MO=Deparse" -e "sub ::::{}sub ::::::{}" 2>&1`;
$a =~ s/-e syntax OK\n//g;
is($a, <<'EOCODG', "sub :::: and sub ::::::");
sub :::: {
    
}
sub :::::: {
    
}
EOCODG

# [perl #117311]
$a = `$^X $path "-MO=Deparse,-l" -e "map{ eval(0) }()" 2>&1`;
$a =~ s/-e syntax OK\n//g;
is($a, <<'EOCODH', "[perl #117311] [PATCH] -l option ('#line ...') does not emit ^Ls in the output");
#line 1 "-e"
map {
#line 1 "-e"
eval 0;} ();
EOCODH

# [perl #33752]
{
  my $code = <<"EOCODE";
{
    our \$\x{1e1f}\x{14d}\x{14d};
}
EOCODE
  my $deparsed
   = $deparse->coderef2text(eval "sub { our \$\x{1e1f}\x{14d}\x{14d} }" );
  s/$ \n//x for $deparsed, $code;
  is $deparsed, $code, 'our $funny_Unicode_chars';
}

# [perl #62500]
$a =
  `$^X $path "-MO=Deparse" -e "BEGIN{*CORE::GLOBAL::require=sub{1}}" 2>&1`;
$a =~ s/-e syntax OK\n//g;
is($a, <<'EOCODF', "CORE::GLOBAL::require override causing panick");
sub BEGIN {
    *CORE::GLOBAL::require = sub {
        1;
    }
    ;
}
EOCODF

# [perl #91384]
$a =
  `$^X $path "-MO=Deparse" -e "BEGIN{*Acme::Acme:: = *Acme::}" 2>&1`;
like($a, qr/-e syntax OK/,
    "Deparse does not hang when traversing stash circularities");

# [perl #93990]
@] = ();
is($deparse->coderef2text(sub{ print "foo@{]}" }),
q<{
    print "foo@{]}";
}>, 'curly around to interpolate "@{]}"');
is($deparse->coderef2text(sub{ print "foo@{-}" }),
q<{
    print "foo@-";
}>, 'no need to curly around to interpolate "@-"');

# Strict hints in %^H are mercilessly suppressed
$a =
  `$^X $path "-MO=Deparse" -e "use strict; print;" 2>&1`;
unlike($a, qr/BEGIN/,
    "Deparse does not emit strict hh hints");

# ambient_pragmas should not mess with strict settings.
SKIP: {
    skip "requires 5.11", 1 unless $] >= 5.011;
    eval q`
	BEGIN {
	    # Clear out all hints
	    %^H = ();
	    $^H = 0;
	    new B::Deparse -> ambient_pragmas(strict => 'all');
	}
	use 5.011;  # should enable strict
	ok !eval '$do_noT_create_a_variable_with_this_name = 1',
	  'ambient_pragmas do not mess with compiling scope';
   `;
}

# multiple statements on format lines
$a = `$^X $path "-MO=Deparse" -e "format =" -e "\@" -e "x();z()" -e. 2>&1`;
$a =~ s/-e syntax OK\n//g;
is($a, <<'EOCODH', 'multiple statements on format lines');
format STDOUT =
@
x(); z()
.
EOCODH

# CORE::format
$a = readpipe qq`$^X $path "-MO=Deparse" -e "use feature q|:all|;`
             .qq` my sub format; CORE::format =" -e. 2>&1`;
like($a, qr/CORE::format/, 'CORE::format when lex format sub is in scope');

# literal big chars under 'use utf8'
is($deparse->coderef2text(sub{ use utf8; /€/; }),
'{
    /\x{20ac}/;
}',
"qr/euro/");

# STDERR when deparsing sub calls
# For a short while the output included 'While deparsing'
$a = `$^X $path "-MO=Deparse" -e "foo()" 2>&1`;
$a =~ s/-e syntax OK\n//g;
is($a, <<'EOCODI', 'no extra output when deparsing foo()');
foo();
EOCODI

# CORE::no
$a = readpipe qq`$^X $path "-MO=Deparse" -Xe `
             .qq`"use feature q|:all|; my sub no; CORE::no less" 2>&1`;
like($a, qr/my sub no;\n\(\);\nCORE::no less;/,
    'CORE::no after my sub no');

# CORE::use
$a = readpipe qq`$^X $path "-MO=Deparse" -Xe `
             .qq`"use feature q|:all|; my sub use; CORE::use less" 2>&1`;
like($a, qr/my sub use;\n\(\);\nCORE::use less;/,
    'CORE::use after my sub use');

# CORE::__DATA__
$a = readpipe qq`$^X $path "-MO=Deparse" -Xe `
             .qq`"use feature q|:all|; my sub __DATA__; `
             .qq`CORE::__DATA__" 2>&1`;
like($a, qr/my sub __DATA__;\n\(\);\nCORE::__DATA__/,
    'CORE::__DATA__ after my sub __DATA__');


done_testing($tests);

__DATA__
# TODO [perl #120950] This succeeds when run a 2nd time
# y/uni/code/
tr/\x{345}/\x{370}/;
####
# y/uni/code/  [perl #120950] This 2nd instance succeeds
tr/\x{345}/\x{370}/;
####
# A constant
1;
####
# Constants in a block
# CONTEXT no warnings;
{
    '???';
    2;
}
####
# Lexical and simple arithmetic
my $test;
++$test and $test /= 2;
>>>>
my $test;
$test /= 2 if ++$test;
####
# list x
-((1, 2) x 2);
####
# lvalue sub
{
    my $test = sub : lvalue {
	my $x;
    }
    ;
}
####
# method
{
    my $test = sub : method {
	my $x;
    }
    ;
}
####
# block with continue
{
    234;
}
continue {
    123;
}
####
# lexical and package scalars
my $x;
print $main::x;
####
# lexical and package arrays
my @x;
print $main::x[1];
####
# lexical and package hashes
my %x;
$x{warn()};
####
# our (LIST)
our($foo, $bar, $baz);
####
# CONTEXT { package Dog } use feature "state";
# variables with declared classes
my Dog $spot;
our Dog $spotty;
state Dog $spotted;
my Dog @spot;
our Dog @spotty;
state Dog @spotted;
my Dog %spot;
our Dog %spotty;
state Dog %spotted;
my Dog ($foo, @bar, %baz);
our Dog ($phoo, @barr, %bazz);
state Dog ($fough, @barre, %bazze);
####
# local our
local our $rhubarb;
local our($rhu, $barb);
####
# <>
my $foo;
$_ .= <ARGV> . <$foo>;
####
# \x{}
my $foo = "Ab\x{100}\200\x{200}\237Cd\000Ef\x{1000}\cA\x{2000}\cZ";
####
# s///e
s/x/'y';/e;
s/x/$a;/e;
s/x/complex_expression();/e;
####
# block
{ my $x; }
####
# while 1
while (1) { my $k; }
####
# trailing for
my ($x,@a);
$x=1 for @a;
>>>>
my($x, @a);
$x = 1 foreach (@a);
####
# 2 arguments in a 3 argument for
for (my $i = 0; $i < 2;) {
    my $z = 1;
}
####
# 3 argument for
for (my $i = 0; $i < 2; ++$i) {
    my $z = 1;
}
####
# 3 argument for again
for (my $i = 0; $i < 2; ++$i) {
    my $z = 1;
}
####
# 3-argument for with inverted condition
for (my $i; not $i;) {
    die;
}
for (my $i; not $i; ++$i) {
    die;
}
for (my $a; not +($1 || 2) ** 2;) {
    die;
}
Something_to_put_the_loop_in_void_context();
####
# while/continue
my $i;
while ($i) { my $z = 1; } continue { $i = 99; }
####
# foreach with my
foreach my $i (1, 2) {
    my $z = 1;
}
####
# OPTIONS -p
# foreach with my under -p
foreach my $i (1) {
    die;
}
####
# foreach
my $i;
foreach $i (1, 2) {
    my $z = 1;
}
####
# foreach, 2 mys
my $i;
foreach my $i (1, 2) {
    my $z = 1;
}
####
# foreach with our
foreach our $i (1, 2) {
    my $z = 1;
}
####
# foreach with my and our
my $i;
foreach our $i (1, 2) {
    my $z = 1;
}
####
# foreach with state
# CONTEXT use feature "state";
foreach state $i (1, 2) {
    state $z = 1;
}
####
# reverse sort
my @x;
print reverse sort(@x);
####
# sort with cmp
my @x;
print((sort {$b cmp $a} @x));
####
# reverse sort with block
my @x;
print((reverse sort {$b <=> $a} @x));
####
# foreach reverse
our @a;
print $_ foreach (reverse @a);
####
# foreach reverse (not inplace)
our @a;
print $_ foreach (reverse 1, 2..5);
####
# bug #38684
our @ary;
@ary = split(' ', 'foo', 0);
####
# Split to our array
our @array = split(//, 'foo', 0);
####
# Split to my array
my @array  = split(//, 'foo', 0);
####
# bug #40055
do { () }; 
####
# bug #40055
do { my $x = 1; $x }; 
####
# <20061012113037.GJ25805@c4.convolution.nl>
my $f = sub {
    +{[]};
} ;
####
# bug #43010
'!@$%'->();
####
# bug #43010
::();
####
# bug #43010
'::::'->();
####
# bug #43010
&::::;
####
# [perl #77172]
package rt77172;
sub foo {} foo & & & foo;
>>>>
package rt77172;
foo(&{&} & foo());
####
# variables as method names
my $bar;
'Foo'->$bar('orz');
'Foo'->$bar('orz') = 'a stranger stranger than before';
####
# constants as method names
'Foo'->bar('orz');
####
# constants as method names without ()
'Foo'->bar;
####
# [perl #47359] "indirect" method call notation
our @bar;
foo{@bar}+1,->foo;
(foo{@bar}+1),foo();
foo{@bar}1 xor foo();
>>>>
our @bar;
(foo { @bar } 1)->foo;
(foo { @bar } 1), foo();
foo { @bar } 1 xor foo();
####
# SKIP ?$] < 5.010 && "say not implemented on this Perl version"
# CONTEXT use feature ':5.10';
# say
say 'foo';
####
# SKIP ?$] < 5.010 && "say not implemented on this Perl version"
# CONTEXT use 5.10.0;
# say in the context of use 5.10.0
say 'foo';
####
# SKIP ?$] < 5.010 && "say not implemented on this Perl version"
# say with use 5.10.0
use 5.10.0;
say 'foo';
>>>>
no feature;
use feature ':5.10';
say 'foo';
####
# SKIP ?$] < 5.010 && "say not implemented on this Perl version"
# say with use feature ':5.10';
use feature ':5.10';
say 'foo';
>>>>
use feature 'say', 'state', 'switch';
say 'foo';
####
# SKIP ?$] < 5.010 && "say not implemented on this Perl version"
# CONTEXT use feature ':5.10';
# say with use 5.10.0 in the context of use feature
use 5.10.0;
say 'foo';
>>>>
no feature;
use feature ':5.10';
say 'foo';
####
# SKIP ?$] < 5.010 && "say not implemented on this Perl version"
# CONTEXT use 5.10.0;
# say with use feature ':5.10' in the context of use 5.10.0
use feature ':5.10';
say 'foo';
>>>>
say 'foo';
####
# SKIP ?$] < 5.015 && "__SUB__ not implemented on this Perl version"
# CONTEXT use feature ':5.15';
# __SUB__
__SUB__;
####
# SKIP ?$] < 5.015 && "__SUB__ not implemented on this Perl version"
# CONTEXT use 5.15.0;
# __SUB__ in the context of use 5.15.0
__SUB__;
####
# SKIP ?$] < 5.015 && "__SUB__ not implemented on this Perl version"
# __SUB__ with use 5.15.0
use 5.15.0;
__SUB__;
>>>>
no feature;
use feature ':5.16';
__SUB__;
####
# SKIP ?$] < 5.015 && "__SUB__ not implemented on this Perl version"
# __SUB__ with use feature ':5.15';
use feature ':5.15';
__SUB__;
>>>>
use feature 'current_sub', 'evalbytes', 'fc', 'say', 'state', 'switch', 'unicode_strings', 'unicode_eval';
__SUB__;
####
# SKIP ?$] < 5.015 && "__SUB__ not implemented on this Perl version"
# CONTEXT use feature ':5.15';
# __SUB__ with use 5.15.0 in the context of use feature
use 5.15.0;
__SUB__;
>>>>
no feature;
use feature ':5.16';
__SUB__;
####
# SKIP ?$] < 5.015 && "__SUB__ not implemented on this Perl version"
# CONTEXT use 5.15.0;
# __SUB__ with use feature ':5.15' in the context of use 5.15.0
use feature ':5.15';
__SUB__;
>>>>
__SUB__;
####
# SKIP ?$] < 5.010 && "state vars not implemented on this Perl version"
# CONTEXT use feature ':5.10';
# state vars
state $x = 42;
####
# SKIP ?$] < 5.010 && "state vars not implemented on this Perl version"
# CONTEXT use feature ':5.10';
# state var assignment
{
    my $y = (state $x = 42);
}
####
# SKIP ?$] < 5.010 && "state vars not implemented on this Perl version"
# CONTEXT use feature ':5.10';
# state vars in anonymous subroutines
$a = sub {
    state $x;
    return $x++;
}
;
####
# SKIP ?$] < 5.011 && 'each @array not implemented on this Perl version'
# each @array;
each @ARGV;
each @$a;
####
# SKIP ?$] < 5.011 && 'each @array not implemented on this Perl version'
# keys @array; values @array
keys @$a if keys @ARGV;
values @ARGV if values @$a;
####
# Anonymous arrays and hashes, and references to them
my $a = {};
my $b = \{};
my $c = [];
my $d = \[];
####
# SKIP ?$] < 5.010 && "smartmatch and given/when not implemented on this Perl version"
# CONTEXT use feature ':5.10'; no warnings 'experimental::smartmatch';
# implicit smartmatch in given/when
given ('foo') {
    when ('bar') { continue; }
    when ($_ ~~ 'quux') { continue; }
    default { 0; }
}
####
# conditions in elsifs (regression in change #33710 which fixed bug #37302)
if ($a) { x(); }
elsif ($b) { x(); }
elsif ($a and $b) { x(); }
elsif ($a or $b) { x(); }
else { x(); }
####
# interpolation in regexps
my($y, $t);
/x${y}z$t/;
####
# TODO new undocumented cpan-bug #33708
# cpan-bug #33708
%{$_ || {}}
####
# TODO hash constants not yet fixed
# cpan-bug #33708
use constant H => { "#" => 1 }; H->{"#"}
####
# TODO optimized away 0 not yet fixed
# cpan-bug #33708
foreach my $i (@_) { 0 }
####
# tests with not, not optimized
my $c;
x() unless $a;
x() if not $a and $b;
x() if $a and not $b;
x() unless not $a and $b;
x() unless $a and not $b;
x() if not $a or $b;
x() if $a or not $b;
x() unless not $a or $b;
x() unless $a or not $b;
x() if $a and not $b and $c;
x() if not $a and $b and not $c;
x() unless $a and not $b and $c;
x() unless not $a and $b and not $c;
x() if $a or not $b or $c;
x() if not $a or $b or not $c;
x() unless $a or not $b or $c;
x() unless not $a or $b or not $c;
####
# tests with not, optimized
my $c;
x() if not $a;
x() unless not $a;
x() if not $a and not $b;
x() unless not $a and not $b;
x() if not $a or not $b;
x() unless not $a or not $b;
x() if not $a and not $b and $c;
x() unless not $a and not $b and $c;
x() if not $a or not $b or $c;
x() unless not $a or not $b or $c;
x() if not $a and not $b and not $c;
x() unless not $a and not $b and not $c;
x() if not $a or not $b or not $c;
x() unless not $a or not $b or not $c;
x() unless not $a or not $b or not $c;
>>>>
my $c;
x() unless $a;
x() if $a;
x() unless $a or $b;
x() if $a or $b;
x() unless $a and $b;
x() if $a and $b;
x() if not $a || $b and $c;
x() unless not $a || $b and $c;
x() if not $a && $b or $c;
x() unless not $a && $b or $c;
x() unless $a or $b or $c;
x() if $a or $b or $c;
x() unless $a and $b and $c;
x() if $a and $b and $c;
x() unless not $a && $b && $c;
####
# tests that should be constant folded
x() if 1;
x() if GLIPP;
x() if !GLIPP;
x() if GLIPP && GLIPP;
x() if !GLIPP || GLIPP;
x() if do { GLIPP };
x() if do { no warnings 'void'; 5; GLIPP };
x() if do { !GLIPP };
if (GLIPP) { x() } else { z() }
if (!GLIPP) { x() } else { z() }
if (GLIPP) { x() } elsif (GLIPP) { z() }
if (!GLIPP) { x() } elsif (GLIPP) { z() }
if (GLIPP) { x() } elsif (!GLIPP) { z() }
if (!GLIPP) { x() } elsif (!GLIPP) { z() }
if (!GLIPP) { x() } elsif (!GLIPP) { z() } elsif (GLIPP) { t() }
if (!GLIPP) { x() } elsif (!GLIPP) { z() } elsif (!GLIPP) { t() }
if (!GLIPP) { x() } elsif (!GLIPP) { z() } elsif (!GLIPP) { t() }
>>>>
x();
x();
'???';
x();
x();
x();
x();
do {
    '???'
};
do {
    x()
};
do {
    z()
};
do {
    x()
};
do {
    z()
};
do {
    x()
};
'???';
do {
    t()
};
'???';
!1;
####
# TODO constant deparsing has been backed out for 5.12
# XXXTODO ? $Config::Config{useithreads} && "doesn't work with threads"
# tests that shouldn't be constant folded
# It might be fundamentally impossible to make this work on ithreads, in which
# case the TODO should become a SKIP
x() if $a;
if ($a == 1) { x() } elsif ($b == 2) { z() }
if (do { foo(); GLIPP }) { x() }
if (do { $a++; GLIPP }) { x() }
>>>>
x() if $a;
if ($a == 1) { x(); } elsif ($b == 2) { z(); }
if (do { foo(); GLIPP }) { x(); }
if (do { ++$a; GLIPP }) { x(); }
####
# TODO constant deparsing has been backed out for 5.12
# tests for deparsing constants
warn PI;
####
# TODO constant deparsing has been backed out for 5.12
# tests for deparsing imported constants
warn O_TRUNC;
####
# TODO constant deparsing has been backed out for 5.12
# tests for deparsing re-exported constants
warn O_CREAT;
####
# TODO constant deparsing has been backed out for 5.12
# tests for deparsing imported constants that got deleted from the original namespace
warn O_APPEND;
####
# TODO constant deparsing has been backed out for 5.12
# XXXTODO ? $Config::Config{useithreads} && "doesn't work with threads"
# tests for deparsing constants which got turned into full typeglobs
# It might be fundamentally impossible to make this work on ithreads, in which
# case the TODO should become a SKIP
warn O_EXCL;
eval '@Fcntl::O_EXCL = qw/affe tiger/;';
warn O_EXCL;
####
# TODO constant deparsing has been backed out for 5.12
# tests for deparsing of blessed constant with overloaded numification
warn OVERLOADED_NUMIFICATION;
####
# strict
no strict;
print $x;
use strict 'vars';
print $main::x;
use strict 'subs';
print $main::x;
use strict 'refs';
print $main::x;
no strict 'vars';
$x;
####
# TODO Subsets of warnings could be encoded textually, rather than as bitflips.
# subsets of warnings
no warnings 'deprecated';
my $x;
####
# TODO Better test for CPAN #33708 - the deparsed code has different behaviour
# CPAN #33708
use strict;
no warnings;

foreach (0..3) {
    my $x = 2;
    {
	my $x if 0;
	print ++$x, "\n";
    }
}
####
# no attribute list
my $pi = 4;
####
# SKIP ?$] > 5.013006 && ":= is now a syntax error"
# := treated as an empty attribute list
no warnings;
my $pi := 4;
>>>>
no warnings;
my $pi = 4;
####
# : = empty attribute list
my $pi : = 4;
>>>>
my $pi = 4;
####
# in place sort
our @a;
my @b;
@a = sort @a;
@b = sort @b;
();
####
# in place reverse
our @a;
my @b;
@a = reverse @a;
@b = reverse @b;
();
####
# #71870 Use of uninitialized value in bitwise and B::Deparse
my($r, $s, @a);
@a = split(/foo/, $s, 0);
$r = qr/foo/;
@a = split(/$r/, $s, 0);
();
####
# package declaration before label
{
    package Foo;
    label: print 123;
}
####
# shift optimisation
shift;
>>>>
shift();
####
# shift optimisation
shift @_;
####
# shift optimisation
pop;
>>>>
pop();
####
# shift optimisation
pop @_;
####
#[perl #20444]
"foo" =~ (1 ? /foo/ : /bar/);
"foo" =~ (1 ? y/foo// : /bar/);
"foo" =~ (1 ? y/foo//r : /bar/);
"foo" =~ (1 ? s/foo// : /bar/);
>>>>
'foo' =~ ($_ =~ /foo/);
'foo' =~ ($_ =~ tr/fo//);
'foo' =~ ($_ =~ tr/fo//r);
'foo' =~ ($_ =~ s/foo//);
####
# The fix for [perl #20444] broke this.
'foo' =~ do { () };
####
# [perl #81424] match against aelemfast_lex
my @s;
print /$s[1]/;
####
# /$#a/
print /$#main::a/;
####
# [perl #91318] /regexp/applaud
print /a/a, s/b/c/a;
print /a/aa, s/b/c/aa;
print /a/p, s/b/c/p;
print /a/l, s/b/c/l;
print /a/u, s/b/c/u;
{
    use feature "unicode_strings";
    print /a/d, s/b/c/d;
}
{
    use re "/u";
    print /a/d, s/b/c/d;
}
{
    use 5.012;
    print /a/d, s/b/c/d;
}
>>>>
print /a/a, s/b/c/a;
print /a/aa, s/b/c/aa;
print /a/p, s/b/c/p;
print /a/l, s/b/c/l;
print /a/u, s/b/c/u;
{
    use feature 'unicode_strings';
    print /a/d, s/b/c/d;
}
{
    BEGIN { $^H{'reflags'}         = '0';
	    $^H{'reflags_charset'} = '2'; }
    print /a/d, s/b/c/d;
}
{
    no feature;
    use feature ':5.12';
    print /a/d, s/b/c/d;
}
####
# [perl #119807] s//\(3)/ge should not warn when deparsed (\3 warns)
s/foo/\(3);/eg;
####
# y///r
tr/a/b/r;
####
# [perl #90898]
<a,>;
####
# [perl #91008]
# CONTEXT no warnings 'experimental::autoderef';
each $@;
keys $~;
values $!;
####
# readpipe with complex expression
readpipe $a + $b;
####
# aelemfast
$b::a[0] = 1;
####
# aelemfast for a lexical
my @a;
$a[0] = 1;
####
# feature features without feature
# CONTEXT no warnings 'experimental::smartmatch';
CORE::state $x;
CORE::say $x;
CORE::given ($x) {
    CORE::when (3) {
        continue;
    }
    CORE::default {
        CORE::break;
    }
}
CORE::evalbytes '';
() = CORE::__SUB__;
() = CORE::fc $x;
####
# feature features when feature has been disabled by use VERSION
# CONTEXT no warnings 'experimental::smartmatch';
use feature (sprintf(":%vd", $^V));
use 1;
CORE::state $x;
CORE::say $x;
CORE::given ($x) {
    CORE::when (3) {
        continue;
    }
    CORE::default {
        CORE::break;
    }
}
CORE::evalbytes '';
() = CORE::__SUB__;
>>>>
CORE::state $x;
CORE::say $x;
CORE::given ($x) {
    CORE::when (3) {
        continue;
    }
    CORE::default {
        CORE::break;
    }
}
CORE::evalbytes '';
() = CORE::__SUB__;
####
# (the above test with CONTEXT, and the output is equivalent but different)
# CONTEXT use feature ':5.10'; no warnings 'experimental::smartmatch';
# feature features when feature has been disabled by use VERSION
use feature (sprintf(":%vd", $^V));
use 1;
CORE::state $x;
CORE::say $x;
CORE::given ($x) {
    CORE::when (3) {
        continue;
    }
    CORE::default {
        CORE::break;
    }
}
CORE::evalbytes '';
() = CORE::__SUB__;
>>>>
no feature;
use feature ':default';
CORE::state $x;
CORE::say $x;
CORE::given ($x) {
    CORE::when (3) {
        continue;
    }
    CORE::default {
        CORE::break;
    }
}
CORE::evalbytes '';
() = CORE::__SUB__;
####
# SKIP ?$] < 5.017004 && "lexical subs not implemented on this Perl version"
# lexical subroutines and keywords of the same name
# CONTEXT use feature 'lexical_subs', 'switch'; no warnings 'experimental';
my sub default;
my sub else;
my sub elsif;
my sub for;
my sub foreach;
my sub given;
my sub if;
my sub m;
my sub no;
my sub package;
my sub q;
my sub qq;
my sub qr;
my sub qx;
my sub require;
my sub s;
my sub sub;
my sub tr;
my sub unless;
my sub until;
my sub use;
my sub when;
my sub while;
CORE::default { die; }
CORE::if ($1) { die; }
CORE::if ($1) { die; }
CORE::elsif ($1) { die; }
CORE::else { die; }
CORE::for (die; $1; die) { die; }
CORE::foreach $_ (1 .. 10) { die; }
die CORE::foreach (1);
CORE::given ($1) { die; }
CORE::m[/];
CORE::m?/?;
CORE::package foo;
CORE::no strict;
() = (CORE::q['], CORE::qq["$_], CORE::qr//, CORE::qx[`]);
CORE::require 1;
CORE::s///;
() = CORE::sub { die; } ;
CORE::tr///;
CORE::unless ($1) { die; }
CORE::until ($1) { die; }
die CORE::until $1;
CORE::use strict;
CORE::when ($1 ~~ $2) { die; }
CORE::while ($1) { die; }
die CORE::while $1;
####
# Feature hints
use feature 'current_sub', 'evalbytes';
print;
use 1;
print;
use 5.014;
print;
no feature 'unicode_strings';
print;
>>>>
use feature 'current_sub', 'evalbytes';
print $_;
no feature;
use feature ':default';
print $_;
no feature;
use feature ':5.12';
print $_;
no feature 'unicode_strings';
print $_;
####
# $#- $#+ $#{%} etc.
my @x;
@x = ($#{`}, $#{~}, $#{!}, $#{@}, $#{$}, $#{%}, $#{^}, $#{&}, $#{*});
@x = ($#{(}, $#{)}, $#{[}, $#{{}, $#{]}, $#{}}, $#{'}, $#{"}, $#{,});
@x = ($#{<}, $#{.}, $#{>}, $#{/}, $#{?}, $#{=}, $#+, $#{\}, $#{|}, $#-);
@x = ($#{;}, $#{:});
####
# ${#} interpolated
# It's a known TODO that warnings are deparsed as bits, not textually.
no warnings;
() = "${#}a";
####
# [perl #86060] $( $| $) in regexps need braces
/${(}/;
/${|}/;
/${)}/;
/${(}${|}${)}/;
####
# ()[...]
my(@a) = ()[()];
####
# sort(foo(bar))
# sort(foo(bar)) is interpreted as sort &foo(bar)
# sort foo(bar) is interpreted as sort foo bar
# parentheses are not optional in this case
print sort(foo('bar'));
>>>>
print sort(foo('bar'));
####
# substr assignment
substr(my $a, 0, 0) = (foo(), bar());
$a++;
####
# This following line works around an unfixed bug that we are not trying to 
# test for here:
# CONTEXT BEGIN { $^H{a} = "b"; delete $^H{a} } # make %^H localised
# hint hash
BEGIN { $^H{'foo'} = undef; }
{
 BEGIN { $^H{'bar'} = undef; }
 {
  BEGIN { $^H{'baz'} = undef; }
  {
   print $_;
  }
  print $_;
 }
 print $_;
}
BEGIN { $^H{q[']} = '('; }
print $_;
####
# This following line works around an unfixed bug that we are not trying to 
# test for here:
# CONTEXT BEGIN { $^H{a} = "b"; delete $^H{a} } # make %^H localised
# hint hash changes that serialise the same way with sort %hh
BEGIN { $^H{'a'} = 'b'; }
{
 BEGIN { $^H{'b'} = 'a'; delete $^H{'a'}; }
 print $_;
}
print $_;
####
# [perl #47361] do({}) and do +{} (variants of do-file)
do({});
do +{};
sub foo::do {}
package foo;
CORE::do({});
CORE::do +{};
>>>>
do({});
do({});
package foo;
CORE::do({});
CORE::do({});
####
# [perl #77096] functions that do not follow the llafr
() = (return 1) + time;
() = (return ($1 + $2) * $3) + time;
() = (return ($a xor $b)) + time;
() = (do 'file') + time;
() = (do ($1 + $2) * $3) + time;
() = (do ($1 xor $2)) + time;
() = (goto 1) + 3;
() = (require 'foo') + 3;
() = (require foo) + 3;
() = (CORE::dump 1) + 3;
() = (last 1) + 3;
() = (next 1) + 3;
() = (redo 1) + 3;
() = (-R $_) + 3;
() = (-W $_) + 3;
() = (-X $_) + 3;
() = (-r $_) + 3;
() = (-w $_) + 3;
() = (-x $_) + 3;
####
# [perl #97476] not() *does* follow the llafr
$_ = ($a xor not +($1 || 2) ** 2);
####
# Precedence conundrums with argument-less function calls
() = (eof) + 1;
() = (return) + 1;
() = (return, 1);
() = warn;
() = warn() + 1;
() = setpgrp() + 1;
####
# loopexes have assignment prec
() = (CORE::dump a) | 'b';
() = (goto a) | 'b';
() = (last a) | 'b';
() = (next a) | 'b';
() = (redo a) | 'b';
####
# [perl #63558] open local(*FH)
open local *FH;
pipe local *FH, local *FH;
####
# [perl #91416] open "string"
open 'open';
open '####';
open '^A';
open "\ca";
>>>>
open *open;
open '####';
open '^A';
open *^A;
####
# "string"->[] ->{}
no strict 'vars';
() = 'open'->[0]; #aelemfast
() = '####'->[0];
() = '^A'->[0];
() = "\ca"->[0];
() = 'a::]b'->[0];
() = 'open'->[$_]; #aelem
() = '####'->[$_];
() = '^A'->[$_];
() = "\ca"->[$_];
() = 'a::]b'->[$_];
() = 'open'->{0}; #helem
() = '####'->{0};
() = '^A'->{0};
() = "\ca"->{0};
() = 'a::]b'->{0};
>>>>
no strict 'vars';
() = $open[0];
() = '####'->[0];
() = '^A'->[0];
() = $^A[0];
() = 'a::]b'->[0];
() = $open[$_];
() = '####'->[$_];
() = '^A'->[$_];
() = $^A[$_];
() = 'a::]b'->[$_];
() = $open{'0'};
() = '####'->{'0'};
() = '^A'->{'0'};
() = $^A{'0'};
() = 'a::]b'->{'0'};
####
# [perl #74740] -(f()) vs -f()
$_ = -(f());
####
# require <binop>
require 'a' . $1;
####
#[perl #30504] foreach-my postfix/prefix difference
$_ = 'foo' foreach my ($foo1, $bar1, $baz1);
foreach (my ($foo2, $bar2, $baz2)) { $_ = 'foo' }
foreach my $i (my ($foo3, $bar3, $baz3)) { $i = 'foo' }
>>>>
$_ = 'foo' foreach (my($foo1, $bar1, $baz1));
foreach $_ (my($foo2, $bar2, $baz2)) {
    $_ = 'foo';
}
foreach my $i (my($foo3, $bar3, $baz3)) {
    $i = 'foo';
}
####
#[perl #108224] foreach with continue block
foreach (1 .. 3) { print } continue { print "\n" }
foreach (1 .. 3) { } continue { }
foreach my $i (1 .. 3) { print $i } continue { print "\n" }
foreach my $i (1 .. 3) { } continue { }
>>>>
foreach $_ (1 .. 3) {
    print $_;
}
continue {
    print "\n";
}
foreach $_ (1 .. 3) {
    ();
}
continue {
    ();
}
foreach my $i (1 .. 3) {
    print $i;
}
continue {
    print "\n";
}
foreach my $i (1 .. 3) {
    ();
}
continue {
    ();
}
####
# file handles
no strict;
my $mfh;
open F;
open *F;
open $fh;
open $mfh;
open 'a+b';
select *F;
select F;
select $f;
select $mfh;
select 'a+b';
####
# 'my' works with padrange op
my($z, @z);
my $m1;
$m1 = 1;
$z = $m1;
my $m2 = 2;
my($m3, $m4);
($m3, $m4) = (1, 2);
@z = ($m3, $m4);
my($m5, $m6) = (1, 2);
my($m7, undef, $m8) = (1, 2, 3);
@z = ($m7, undef, $m8);
($m7, undef, $m8) = (1, 2, 3);
####
# 'our/local' works with padrange op
our($z, @z);
our $o1;
no strict;
local $o11;
$o1 = 1;
local $o1 = 1;
$z = $o1;
$z = local $o1;
our $o2 = 2;
our($o3, $o4);
($o3, $o4) = (1, 2);
local($o3, $o4) = (1, 2);
@z = ($o3, $o4);
@z = local($o3, $o4);
our($o5, $o6) = (1, 2);
our($o7, undef, $o8) = (1, 2, 3);
@z = ($o7, undef, $o8);
@z = local($o7, undef, $o8);
($o7, undef, $o8) = (1, 2, 3);
local($o7, undef, $o8) = (1, 2, 3);
####
# 'state' works with padrange op
no strict;
use feature 'state';
state($z, @z);
state $s1;
$s1 = 1;
$z = $s1;
state $s2 = 2;
state($s3, $s4);
($s3, $s4) = (1, 2);
@z = ($s3, $s4);
# assignment of state lists isn't implemented yet
#state($s5, $s6) = (1, 2);
#state($s7, undef, $s8) = (1, 2, 3);
#@z = ($s7, undef, $s8);
($s7, undef, $s8) = (1, 2, 3);
####
# anon lists with padrange
my($a, $b);
my $c = [$a, $b];
my $d = {$a, $b};
####
# slices with padrange
my($a, $b);
my(@x, %y);
@x = @x[$a, $b];
@x = @y{$a, $b};
####
# binops with padrange
my($a, $b, $c);
$c = $a cmp $b;
$c = $a + $b;
$a += $b;
$c = $a - $b;
$a -= $b;
$c = my $a1 cmp $b;
$c = my $a2 + $b;
$a += my $b1;
$c = my $a3 - $b;
$a -= my $b2;
####
# 'x' with padrange
my($a, $b, $c, $d, @e);
$c = $a x $b;
$a x= $b;
@e = ($a) x $d;
@e = ($a, $b) x $d;
@e = ($a, $b, $c) x $d;
@e = ($a, 1) x $d;
####
# @_ with padrange
my($a, $b, $c) = @_;
####
# SKIP ?$] < 5.017004 && "lexical subs not implemented on this Perl version"
# TODO unimplemented in B::Deparse; RT #116553
# lexical subroutine
use feature 'lexical_subs';
no warnings "experimental::lexical_subs";
my sub f {}
print f();
####
# SKIP ?$] < 5.017004 && "lexical subs not implemented on this Perl version"
# TODO unimplemented in B::Deparse; RT #116553
# lexical "state" subroutine
use feature 'state', 'lexical_subs';
no warnings 'experimental::lexical_subs';
state sub f {}
print f();
####
# SKIP ?$] < 5.017004 && "lexical subs not implemented on this Perl version"
# TODO unimplemented in B::Deparse; RT #116553
# lexical subroutine scoping
# CONTEXT use feature 'lexical_subs'; no warnings 'experimental::lexical_subs';
{
  {
    my sub a { die; }
    {
      foo();
      my sub b;
      b();
      main::b();
      my $b;
      sub b { $b }
    }
  }
  b();
}
####
# Elements of %# should not be confused with $#{ array }
() = ${#}{'foo'};
####
# [perl #121050] Prototypes with whitespace
sub _121050(\$ \$) { }
_121050($a,$b);
sub _121050empty( ) {}
() = _121050empty() + 1;
>>>>
_121050 $a, $b;
() = _121050empty + 1;
####
# ensure aelemfast works in the range -128..127 and that there's no
# funky edge cases
my $x;
no strict 'vars';
$x = $a[-256] + $a[-255] + $a[-129] + $a[-128] + $a[-127] + $a[-1] + $a[0];
$x = $a[1] + $a[126] + $a[127] + $a[128] + $a[255] + $a[256];
my @b;
$x = $b[-256] + $b[-255] + $b[-129] + $b[-128] + $b[-127] + $b[-1] + $b[0];
$x = $b[1] + $b[126] + $b[127] + $b[128] + $b[255] + $b[256];
####
# 'm' must be preserved in m??
m??;
####
# \(@array) and \(..., (@array), ...)
my(@array, %hash, @a, @b, %c, %d);
() = \(@array);
() = \(%hash);
() = \(@a, (@b), (%c), %d);
() = \(@Foo::array);
() = \(%Foo::hash);
() = \(@Foo::a, (@Foo::b), (%Foo::c), %Foo::d);
####
# subs synonymous with keywords
main::our();
main::pop();
state();
use feature 'state';
main::state();
####
# lvalue references
# CONTEXT use feature "state", 'refaliasing', 'lexical_subs'; no warnings 'experimental';
our $x;
\$x = \$x;
my $m;
\$m = \$x;
\my $n = \$x;
(\$x) = @_;
\($x) = @_;
\($m) = @_;
(\$m) = @_;
\my($p) = @_;
(\my $r) = @_;
\($x, my $a) = @{[\$x, \$x]};
(\$x, \my $b) = @{[\$x, \$x]};
\local $x = \3;
\local($x) = \3;
\state $c = \3;
\state($d) = \3;
\our $e = \3;
\our($f) = \3;
\$_[0] = foo();
\($_[1]) = foo();
my @a;
\$a[0] = foo();
\($a[1]) = foo();
\local($a[1]) = foo();
\@a[0,1] = foo();
\(@a[2,3]) = foo();
\local @a[0,1] = (\$a)x2;
\$_{a} = foo();
\($_{b}) = foo();
my %h;
\$h{a} = foo();
\($h{b}) = foo();
\local $h{a} = \$x;
\local($h{b}) = \$x;
\@h{'a','b'} = foo();
\(@h{2,3}) = foo();
\local @h{'a','b'} = (\$x)x2;
\@_ = foo();
\@a = foo();
(\@_) = foo();
(\@a) = foo();
\my @c = foo();
(\my @d) = foo();
\(@_) = foo();
\(@a) = foo();
\my(@g) = foo();
\local @_ = \@_;
(\local @_) = \@_;
\state @e = [1..3];
\state(@f) = \3;
\our @i = [1..3];
\our(@h) = \3;
\%_ = foo();
\%h = foo();
(\%_) = foo();
(\%h) = foo();
\my %c = foo();
(\my %d) = foo();
\local %_ = \%h;
(\local %_) = \%h;
\state %y = {1,2};
\our %z = {1,2};
(\our %zz) = {1,2};
\&a = foo();
(\&a) = foo();
\(&a) = foo();
{
  my sub a;
  \&a = foo();
  (\&a) = foo();
  \(&a) = foo();
}
(\$_, $_) = \(1, 2);
$_ == 3 ? \$_ : $_ = \3;
$_ == 3 ? \$_ : \$x = \3;
\($_ == 3 ? $_ : $x) = \3;
for \my $topic (\$1, \$2) {
    die;
}
for \state $topic (\$1, \$2) {
    die;
}
for \our $topic (\$1, \$2) {
    die;
}
for \$_ (\$1, \$2) {
    die;
}
for \my @a ([1,2], [3,4]) {
    die;
}
for \state @a ([1,2], [3,4]) {
    die;
}
for \our @a ([1,2], [3,4]) {
    die;
}
for \@_ ([1,2], [3,4]) {
    die;
}
for \my %a ({5,6}, {7,8}) {
    die;
}
for \our %a ({5,6}, {7,8}) {
    die;
}
for \state %a ({5,6}, {7,8}) {
    die;
}
for \%_ ({5,6}, {7,8}) {
    die;
}
{
    my sub a;
    for \&a (sub { 9; }, sub { 10; }) {
        die;
    }
}
for \&a (sub { 9; }, sub { 10; }) {
    die;
}
>>>>
our $x;
\$x = \$x;
my $m;
\$m = \$x;
\my $n = \$x;
(\$x) = @_;
(\$x) = @_;
(\$m) = @_;
(\$m) = @_;
(\my $p) = @_;
(\my $r) = @_;
(\$x, \my $a) = @{[\$x, \$x];};
(\$x, \my $b) = @{[\$x, \$x];};
\local $x = \3;
(\local $x) = \3;
\state $c = \3;
(\state $d) = \3;
\our $e = \3;
(\our $f) = \3;
\$_[0] = foo();
(\$_[1]) = foo();
my @a;
\$a[0] = foo();
(\$a[1]) = foo();
(\local $a[1]) = foo();
(\@a[0, 1]) = foo();
(\@a[2, 3]) = foo();
(\local @a[0, 1]) = (\$a) x 2;
\$_{'a'} = foo();
(\$_{'b'}) = foo();
my %h;
\$h{'a'} = foo();
(\$h{'b'}) = foo();
\local $h{'a'} = \$x;
(\local $h{'b'}) = \$x;
(\@h{'a', 'b'}) = foo();
(\@h{2, 3}) = foo();
(\local @h{'a', 'b'}) = (\$x) x 2;
\@_ = foo();
\@a = foo();
(\@_) = foo();
(\@a) = foo();
\my @c = foo();
(\my @d) = foo();
(\(@_)) = foo();
(\(@a)) = foo();
(\(my @g)) = foo();
\local @_ = \@_;
(\local @_) = \@_;
\state @e = [1..3];
(\(state @f)) = \3;
\our @i = [1..3];
(\(our @h)) = \3;
\%_ = foo();
\%h = foo();
(\%_) = foo();
(\%h) = foo();
\my %c = foo();
(\my %d) = foo();
\local %_ = \%h;
(\local %_) = \%h;
\state %y = {1, 2};
\our %z = {1, 2};
(\our %zz) = {1, 2};
\&a = foo();
(\&a) = foo();
(\&a) = foo();
{
  my sub a;
  \&a = foo();
  (\&a) = foo();
  (\&a) = foo();
}
(\$_, $_) = \(1, 2);
$_ == 3 ? \$_ : $_ = \3;
$_ == 3 ? \$_ : \$x = \3;
($_ == 3 ? \$_ : \$x) = \3;
foreach \my $topic (\$1, \$2) {
    die;
}
foreach \state $topic (\$1, \$2) {
    die;
}
foreach \our $topic (\$1, \$2) {
    die;
}
foreach \$_ (\$1, \$2) {
    die;
}
foreach \my @a ([1, 2], [3, 4]) {
    die;
}
foreach \state @a ([1, 2], [3, 4]) {
    die;
}
foreach \our @a ([1, 2], [3, 4]) {
    die;
}
foreach \@_ ([1, 2], [3, 4]) {
    die;
}
foreach \my %a ({5, 6}, {7, 8}) {
    die;
}
foreach \our %a ({5, 6}, {7, 8}) {
    die;
}
foreach \state %a ({5, 6}, {7, 8}) {
    die;
}
foreach \%_ ({5, 6}, {7, 8}) {
    die;
}
{
    my sub a;
    foreach \&a (sub { 9; } , sub { 10; } ) {
        die;
    }
}
foreach \&a (sub { 9; } , sub { 10; } ) {
    die;
}
####
# join $foo, pos
my $foo;
$_ = join $foo, pos
>>>>
my $foo;
$_ = join('???', pos $_);
