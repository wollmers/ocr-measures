#!perl

use strict;
use warnings;
use utf8;

use LCS;
use LCS::Tiny;
use String::Similarity;
use LCS::Similar;

use Getopt::Long  '2.32';
use Pod::Usage;

use Data::Dumper;

our $VERSION = '0.02';

binmode(STDOUT,":encoding(UTF-8)");
binmode(STDERR,":encoding(UTF-8)");

my $file1 = '';
my $file2 = ''; # ground truth

#######################

my $verbose;
my $lines = 0; 			# details aligned lines: 1=short,2=full
my $clean_words = 1;    # remove punctuation from words
my $word_matches = 0;
my $char_matches = 0;
my $match_table  = 0;
my $help = 0;
my $man = 0;

GetOptions(
  'lines|l'           => \$lines,
  'trim_words|t'      => \$clean_words,
  'word_matches|w'    => \$word_matches,
  'char_matches|c'    => \$char_matches,
  'match_table|m'     => \$match_table,
  'help|h'			  => \$help,
  'man'			      => \$man,
)
or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitval => 0, -verbose => 2) if $man;
# or die("Error in command line arguments\n");

#######################

# $ARGV[0]\n";
if (@ARGV >= 1) {
  $file1 = $ARGV[0];
  if (@ARGV >= 2) {
    $file2 = $ARGV[1];
  }
}

pod2usage(1) unless ($file1 && $file2);

print $0,' Version ',$VERSION,"\n";
print "\n";
print 'Compare OCR text output against ground truth (GRT):',"\n";
print 'File 1 (OCR): ',$file1,"\n";
print 'File 2 (GRT): ',$file2,"\n";
print "\n";

open(my $in1,"<:encoding(UTF-8)",$file1) or die "cannot open $file1: $!";
open(my $in2,"<:encoding(UTF-8)",$file2) or die "cannot open $file2: $!";

my $nl = '¶';
chomp(my @lines = <$in1>);
my @lines1 = map { $_ =~ s/\s+$//; my $s = $_ . $nl; $s} grep {/./} @lines;
chomp(@lines = <$in2>);
my @lines2 = map { $_ =~ s/\s+$//; my $s = $_ . $nl; $s} grep {/./} @lines;


my $stats = {};

my $compare = sub {
  my ($a,$b,$threshold) = @_;
  my $similarity = similarity($a,$b);
  return $similarity if ($similarity >= $threshold);
  return 0;
};

my $lcs = LCS::Similar->LCS(\@lines1,\@lines2,$compare,0.5);
my $aligned = LCS->lcs2align(\@lines1,\@lines2,$lcs);

#print Dumper($aligned);

my $count_aligned = [count_aligned($aligned)];

#print Dumper($count_aligned);
#exit;
$stats->{'lines'} = {};
$stats->{'words'} = {};
$stats->{'chars'} = {};

add_stats($stats->{'lines'}, count_aligned($aligned));

my $word_mismatches = {};
my $char_mismatches = {};

for my $chunk (@$aligned) {
  my @words1 = $chunk->[0] =~ /(\S+)/g;
  my @words2 = $chunk->[1] =~ /(\S+)/g;
  my $words_aligned = LCS->lcs2align(
    \@words1,
    \@words2,
    LCS::Tiny->LCS(\@words1,\@words2)
  );
  add_stats($stats->{'words'}, count_aligned($words_aligned));
  record_mismatches($words_aligned, $word_mismatches, $clean_words);

  my @chars1 = $chunk->[0] =~ /(.)/g;
  my @chars2 = $chunk->[1] =~ /(.)/g;
  my $chars_aligned = LCS->lcs2align(
    \@chars1,
    \@chars2,
    #LCS::Tiny->LCS(\@chars1,\@chars2)
    LCS::Similar->LCS(\@chars1,\@chars2,\&confusable,0.7)
  );

  my ($matches, $inserts, $substitutions, $deletions) =
    count_aligned($chars_aligned);
  record_mismatches($chars_aligned, $char_mismatches);

  my $is_equal = ($matches == @chars1 && $matches == @chars2);

  my $accuracy = $matches / ($matches + $substitutions + $inserts + $deletions);
  add_stats($stats->{'chars'}, ($matches, $inserts, $substitutions, $deletions));

  if ($lines >= 1) {
    my ($s1,$s2) =   LCS->align2strings($chars_aligned);
    if ($is_equal) {
      print $s1,' ',sprintf('%0.3f',$accuracy),"\n";
      print "\n";
    }

    else {
      print $s1,"\n";
      print relation_aligned($chars_aligned),' ',sprintf('%0.3f',$accuracy),"\n";
      print $s2,"\n";
      print "\n";
    }

  }
}

if ($word_matches) {
  print "\n";
  print 'Word mismatches:',"\n";
  print_mismatches($word_mismatches,1);
}

if ($char_matches) {
  print "\n";
  print 'Character mismatches:',"\n";
  print_mismatches($char_mismatches,1);
}

if ($match_table) {
  print "\n";
  print 'Character match (confusion) table:',"\n";
  print_confusion_table($char_mismatches,1);
}

calc_stats($stats->{'lines'});
calc_stats($stats->{'words'});
calc_stats($stats->{'chars'});

print "\n";
print 'Summary:',"\n";
print "\n";
print_stats($stats);

###########################
sub print_mismatches {
  my ($mismatches, $suppress_matches) = @_;
  for my $token (sort keys %$mismatches) {
    my $count = 0;
    for my $mismatch (sort keys %{$mismatches->{$token}}) {
      $count += $mismatches->{$token}->{$mismatch};
    }
    #unless ( scalar(keys %{$mismatches->{$token}}) == 1
    #  ## && shift(keys %{$mismatches->{$token}}) eq $token
    #  && $suppress_matches) {
    unless ( exists $mismatches->{$token}->{$token}
      && $mismatches->{$token}->{$token} == $count
      && $suppress_matches) {

      print '"',$token,'"',sprintf('%6s',$count),"\n";
      for my $mismatch (sort keys %{$mismatches->{$token}}) {
        print '  ','"',$mismatch,'"',
          sprintf('%6s',$mismatches->{$token}->{$mismatch}),
          ' (',sprintf('%0.4f',$mismatches->{$token}->{$mismatch}/$count),')',
          "\n";
      }
    }
  }
}

sub print_confusion_table {
  my ($mismatches, $suppress_matches) = @_;
  for my $token (sort keys %$mismatches) {
    my $count = 0;
    for my $mismatch (sort keys %{$mismatches->{$token}}) {
      $count += $mismatches->{$token}->{$mismatch};
    }
    unless ( exists $mismatches->{$token}->{$token}
      && $mismatches->{$token}->{$token} == $count
      && $suppress_matches) {

      for my $mismatch (sort keys %{$mismatches->{$token}}) {
        print $token,' ',$mismatch,' ',
          sprintf('%0.4f',$mismatches->{$token}->{$mismatch}/$count),
          "\n"
          unless ($token eq $mismatch && $suppress_matches);
      }
    }
  }
}

sub confusable {
  my ($a, $b, $threshold) = @_;

  $a //= '';
  $b //= '';
  $threshold //= 0.7;

  return 1 if ($a eq $b);
  return 1 if (!$a && !$b);

  my $map = {
    'e' => 'c',
    'c' => 'e',
    'm' => 'n',
    'n' => 'm',
    'i' => 't',
    't' => 'i',
    't' => 'f',
    'f' => 't',
    'ſ' => 'j',
    'j' => 'ſ',
    's' => 'f',
    'f' => 's',
    't' => 'l',
    'l' => 't',
    'c' => '&',
    '&' => 'c',
    'u' => 'n',
    'n' => 'u',
    'h' => 'l',
    'l' => 'h',
  };

  return $threshold if (exists $map->{$a} && $map->{$a} eq $b);
}

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

sub record_mismatches {
  my ($aligned, $mismatches, $clean_words) = @_;

  for my $chunk (@$aligned) {
    #if ($chunk->[0] && $chunk->[1] && $chunk->[0] ne $chunk->[1]) {
    my $token1 = $chunk->[0];
    my $token2 = $chunk->[1];

    my $prefix  = qr/ [\(\)\[\]='",;:!?\.]+ /xms;
    my $suffix  = qr/ [\(\)\[\]='",;:!?¶]+ /xms;

    # TODO: better definition of word characters
    if ($clean_words) {
      $token1 =~ s/^$prefix//;
      $token1 =~ s/$suffix$//;
      $token2 =~ s/^$prefix//;
      $token2 =~ s/$suffix$//;
    }

    if ($token1 && $token2) {
      $mismatches->{$token2}->{$token1}++;
    }
  }
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
  $stats->{'precision'} = (($matches + $substitutions + $inserts) > 0 ) ?
    ($matches / ($matches + $substitutions + $inserts)) : 0;
  $stats->{'recall'} = (($matches + $substitutions + $deletions) > 0 ) ?
    ($matches / ($matches + $substitutions + $deletions)) : 0;
  $stats->{'accuracy'} = (($matches + $substitutions + $inserts + $deletions) > 0 ) ?
    ($matches / ($matches + $substitutions + $inserts + $deletions)) : 0;
  $stats->{'f_score'} = (($stats->{'recall'} + $stats->{'precision'}) > 0 ) ?
    (( 2 * $stats->{'recall'} * $stats->{'precision'} )
      / ($stats->{'recall'} + $stats->{'precision'} )) : 0;
}

__END__

=head1 NAME

ocr_compare.pl - compare OCR output against ground truth

=head1 SYNOPSIS

ocr_compare.pl [options] ocrfile ground_truh_file

 Options:
   -help            brief help message
   -man             full documentation

=head1 DESCRIPTION

B<This program> will read the given input file(s) and do something
useful with the contents thereof.

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-lines>, B<-l>

Print alignment of lines. Default: off.

=item B<-trim_words>, B<-t>

Trim punctuation characters at start and end of words. Default: on.

=item B<-word_matches>, B<-w>

Report mismatches of words with frequencies. Default: off.

=item B<-char_matches>, B<-c>

Report mismatches of chars with frequencies. Default: off.

=item B<-match_table>, B<-m>

Output character mismatches usable as confusion matrix. Default: off.

=back

=cut




