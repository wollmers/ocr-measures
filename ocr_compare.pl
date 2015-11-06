#!perl

use strict;
use warnings;
use utf8;

use LCS;
use LCS::Tiny;

use Data::Dumper;

binmode(STDOUT,":encoding(UTF-8)");
binmode(STDERR,":encoding(UTF-8)");

my $file1 = '../your/path/yourbook_page_0153_ocr.txt';
my $file2 = '../your/path/yourbook_page_0153_corr.txt'; # ground truth

my $suppress_equals = 0; # suppress details of equal lines

#my $file2 = 'isis_152_bhl.txt';

open(my $in1,"<:encoding(UTF-8)",$file1) or die "cannot open $file1: $!";
open(my $in2,"<:encoding(UTF-8)",$file2) or die "cannot open $file2: $!";

my $nl = '¶';
chomp(my @lines = <$in1>);
my @lines1 = map { $_ =~ s/\s+$//; my $s = $_ . $nl; $s} grep {/./} @lines;
chomp(@lines = <$in2>);
my @lines2 = map { $_ =~ s/\s+$//; my $s = $_ . $nl; $s} grep {/./} @lines;


my $stats = {};

my $lcs = LCS::Tiny->LCS(\@lines1,\@lines2);
my $aligned = LCS->lcs2align(\@lines1,\@lines2,$lcs);

my $count_aligned = [count_aligned($aligned)];

#print Dumper($count_aligned);
#exit;
$stats->{'lines'} = {};
$stats->{'words'} = {};
$stats->{'chars'} = {};

add_stats($stats->{'lines'}, count_aligned($aligned));

#print Dumper($stats);
#exit;

#exit;

for my $chunk (@$aligned) {
  my @words1 = $chunk->[0] =~ /(\S+)/g;
  my @words2 = $chunk->[1] =~ /(\S+)/g;
  my $words_aligned = LCS->lcs2align(
    \@words1,
    \@words2,
    LCS::Tiny->LCS(\@words1,\@words2)
  );
  add_stats($stats->{'words'}, count_aligned($words_aligned));

  my @chars1 = $chunk->[0] =~ /(.)/g;
  my @chars2 = $chunk->[1] =~ /(.)/g;
  my $chars_aligned = LCS->lcs2align(
    \@chars1,
    \@chars2,
    LCS::Tiny->LCS(\@chars1,\@chars2)
  );

  my ($matches, $inserts, $substitutions, $deletions) =
    count_aligned($chars_aligned);

  my $is_equal = ($matches == @chars1 && $matches == @chars1);

  unless ($suppress_equals && $is_equal) {
    # accuracy = matches/(matches+subs+inss+dels)
    my $accuracy = $matches / ($matches + $substitutions + $inserts + $deletions);

    add_stats($stats->{'chars'}, ($matches, $inserts, $substitutions, $deletions));

    my ($s1,$s2) =   LCS->align2strings($chars_aligned);
    print $s1,"\n";
    print relation_aligned($chars_aligned),' ',sprintf('%0.3f',$accuracy),"\n";
    print $s2,"\n";
    print "\n";
  }
}

calc_stats($stats->{'lines'});
calc_stats($stats->{'words'});
calc_stats($stats->{'chars'});

print_stats($stats);

sub relation_aligned {
  my $aligned = shift;

  my $line = '';

  my $match  = '|';
  my $delete = '-';
  my $insert = '+';
  my $subst  = '=';

  for my $chunk (@$aligned) {
    if ($chunk->[0] eq $chunk->[1])     { $line .= $match; }
    elsif (!$chunk->[0] && $chunk->[1]) { $line .= $delete; }
    elsif ($chunk->[0] && !$chunk->[1]) { $line .= $insert; }
    else                                { $line .= $subst; }
  }
  return $line;
}

sub count_aligned {
  my $aligned = shift;
  my ($matches, $inserts, $substitutions, $deletions) = (0,0,0,0);

  for my $chunk (@$aligned) {
    if ($chunk->[0] eq $chunk->[1])     { $matches++; }
    elsif (!$chunk->[0] && $chunk->[1]) { $deletions++;  }
    elsif ($chunk->[0] && !$chunk->[1]) { $inserts++; }
    else                                { $substitutions++; }
  }
  return ($matches, $inserts, $substitutions, $deletions);
}

sub add_stats {
  my $stats = shift;
  my $data = {};
  @$data{qw(matches inserts substitutions deletions)} = @_;
  #print Dumper($data);
  for my $key (keys %$data) {
    $stats->{$key} += $data->{$key};
  }
  #print Dumper($stats);
}

sub print_stats {
  my $stats = shift;
  my $columns = [qw(lines words chars)];
  my $lines = [
    {'items_ocr'     => {'label'=> 'items ocr:  ', 'mask' => '%6s'}},
    {'items_grt'     => {'label'=> 'items grt:  ', 'mask' => '%6s'}},
    {'matches'       => {'label'=> 'matches:    ', 'mask' => '%6s'}},
    {'edits'         => {'label'=> 'edits:      ', 'mask' => '%6s'}},
    {'substitutions' => {'label'=> ' subss:     ', 'mask' => '%6s'}},
    {'inserts'       => {'label'=> ' inserts:   ', 'mask' => '%6s'}},
    {'deletions'     => {'label'=> ' deletions: ', 'mask' => '%6s'}},
    {'precision'     => {'label'=> 'precision:  ', 'mask' => '%0.4f'}},
    {'recall'        => {'label'=> 'recall:     ', 'mask' => '%0.4f'}},
    {'accuracy'      => {'label'=> 'accuracy:   ', 'mask' => '%0.4f'}},
    {'f_score'       => {'label'=> 'f-score:    ', 'mask' => '%0.4f'}},

  ];

  print '             ',join('  ',@$columns),"\n";

  for my $line (@$lines) {
    my ($key) = (keys %$line);
    print $line->{$key}->{'label'};
    for my $column (@$columns) {
      print sprintf($line->{$key}->{'mask'},$stats->{$column}->{$key}),' ';
    }
    print "\n";
  }
}

sub calc_stats {
  my $stats = shift;

  my ($matches, $inserts, $substitutions, $deletions) =
     map { $stats->{$_} } qw(matches inserts substitutions deletions);

  $stats->{'items_ocr'} = ($matches + $inserts + $substitutions);
  $stats->{'items_grt'} = ($matches + $deletions + $substitutions);
  $stats->{'edits'} = ($inserts + $deletions + $substitutions);
  $stats->{'precision'} = $matches / ($matches + $substitutions + $inserts);
  $stats->{'recall'} = $matches / ($matches + $substitutions + $deletions);
  $stats->{'accuracy'} = $matches / ($matches + $substitutions + $inserts + $deletions);
  $stats->{'f_score'} =
    ( 2 * $stats->{'recall'} * $stats->{'precision'} )
      / ($stats->{'recall'} + $stats->{'precision'} );
}




