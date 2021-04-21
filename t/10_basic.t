#!perl
use 5.008;

use strict;
use warnings;
use utf8;

use lib qw(../lib/);

use Test::More;
use Test::Deep;
#cmp_deeply([],any());

use LCS;

use Data::Dumper;

my $class = 'OCR::Compare';

use_ok($class);

my $object = new_ok($class);

#bless @_
#  ? @_ > 1
#    ? {@_}
#    : {%{$_[0]}}
#  : {},
#ref $class || $class;

if (0) {
  ok($class->new());
  ok($class->new(1,2));
  ok($class->new({}));
  ok($class->new({a => 1}));
  ok($class->new());

  ok($object->new());
  ok($object->new(1,2));
  ok($object->new({}));
  ok($object->new({a => 1}));
  ok($object->new());
}

done_testing;
