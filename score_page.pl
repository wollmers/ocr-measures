#!perl

use strict;
use warnings;
use utf8;

use String::Similarity;
# $similarity = similarity $string1, $string2, $limit;


my @files = @ARGV;

#qw(
#mybook_152.deu-frak+deu_corr.txt
#mybook_152.deu+deu-frak_3.04.txt
#mybook_152_bhl.txt
#);

binmode(STDOUT,":encoding(UTF-8)");
binmode(STDERR,":encoding(UTF-8)");

my $pieces_all = 0;
my $word_all = 0;
my $crap_all = 0;

my $lookup = 1;

my $prefix  = qr/ [\(]? [='"-]? /xms;
my $suffix  = qr/ [='"\.]? [\)]? [,\.;:!?]? | [=-] /xms;
my $LETTER  = qr/ [A-ZÏËÖÜÄÉÈČÁÀÆŒ]/xms;
my $letter  = qr/ [a-zïëöüäåéèčáàæœﬁꝛßſú]/xms;
my $punctuation = qr/[.;:!?=-]/xms;
my $numeric = qr/ \d+ | \d+[).] | [+-]\d+ (?: [\/\.]\d+ )? /xms;
my $word    = qr/ (?: $LETTER | $letter ) (?: $letter )* (?: [=-] (?: $LETTER | $letter ) (?: $letter)* )* /xms;
my $sane    = qr/ (?: (?: $prefix )? $word (?: $suffix)? ) | $numeric (?: $suffix)? | $punctuation /xms;

my $dicts = {
  'fra_10K' => {
	'file' => '/Users/helmut/github/ocr/ocr-dicts/fra_10K.txt',
  },
  'eng_10K' => {
	'file' => '/Users/helmut/github/ocr/ocr-dicts/eng_10K.txt',
  },
  'deu_10K' => {
    'file' => '/Users/helmut/github/ocr/ocr-dicts/deu_10K.txt',
  },
  'deu__1M' => {
	'file' => '/Users/helmut/github/ocr/ocr-dicts/deu__1M.txt',
  },
  'deu_18_' => {
	'file' => '/Users/helmut/github/ocr/ocr-dicts/deu_18_.txt',
  },
  'lat_10K' => {
	'file' => '/Users/helmut/github/ocr/ocr-dicts/lat_10K.txt',
  },
  'lat__1M' => {
    'file' => '/Users/helmut/github/ocr/ocr-dicts/lat__1M.txt',
  },
  'authors' => {
    'file' => '/Users/helmut/github/ocr/ocr-dicts/authors.txt',
  },
  'lat_taxa' => {
    'file' => '/Users/helmut/github/ocr/ocr-dicts/lat_taxa.txt',
  },
};

my $dict_similar = [qw(
deu_18*
deu_10K
eng_10K
lat_10K
authors
lat_taxa
)];

if ($lookup) {
for my $dict (keys %{$dicts}) {
  open(my $dict_in,"<:encoding(UTF-8)",$dicts->{$dict}->{'file'})
    or die "cannot open $dicts->{$dict}->{'file'}: $!";

  while (my $line = <$dict_in>) {
    chomp $line;
    #my $keyword = $line =~ m/($word)/g;
    $dicts->{$dict}->{'dict'}->{$line}++;
  }
}

print 'used dicts: ', "\n";
for my $dict (sort keys %{$dicts}) {
  print '   ',$dict,': ',sprintf('%8s',scalar(keys %{$dicts->{$dict}->{'dict'}})), "\n";
}
}

my $existing_count = 0;
my $lookup_count = 0;

for my $file (@files) {
  score_file($file);
}

sub dict_lookup {
  my $keyword = shift;
  #$lookup_count++;
  my @matches;
  return @matches unless $lookup;
  #$keyword =~ s/(?: $prefix )? ($word) (?: $suffix)? /$1/xms;
  for my $dict (sort keys %{$dicts}) {
    if (exists $dicts->{$dict}->{'dict'}->{$keyword}) {
      #$existing_count++;
      push @matches,$dict;
      return @matches;
      #return $keyword;
    }
  }
  return @matches;
}

# TODO: cache queries and results
# TODO: confusables, record differences
# TODO: use limit
# TODO: plugins for non-bruteforce dicts
sub dict_similar {
  my $keyword = shift;
  #$lookup_count++;
  my @matches;
  return @matches unless $lookup;
  #$keyword =~ s/(?: $prefix )? ($word) (?: $suffix)? /$1/xms;
  for my $dict (@$dict_similar) {
    for my $word (keys %{$dicts->{$dict}->{'dict'}} ) {
      if (similarity($keyword,$word) >= 0.7) {
          push @matches,$dict;
          return @matches;
      }
    }
  }
  return @matches;
}

sub score_file {
  my $file = shift;

  my $pieces_count = 0;
  my $word_count = 0;
  my $crap_count = 0;
  my $dict_count = 0;
  my $dict_matches = {};
  my $crap_similar = 0;
  my $words_similar = 0;

  open(my $in,"<:encoding(UTF-8)",$file) or die "cannot open $file: $!";

  while (my $line = <$in>) {
    chomp $line;
    my @pieces = split(m/\s+/,$line);
    $pieces_count += scalar @pieces;

    for my $piece (@pieces) {
      if ($piece =~ m/^$sane$/) {
        $word_count++;
        my @matches = dict_lookup($piece);
        if (@matches) {
          $dict_count++;
          my $dict = shift @matches;
          #for my $dict (@matches) {
          $dict_matches->{$dict}++;
          #}
        }
        else {
          my @similar = dict_similar($piece);
          if (@similar) {
            $words_similar++;
          }
          #print $piece, "\n";
        }
      }
      else {
        $crap_count++;
        my @similar = dict_similar($piece);
        if (@similar) {
          $crap_similar++;
        }
        print $piece, "\n";
      }
    }
  }
  print "\n";
  print '*** file: ',$file, "\n";
  print 'tokens:     ',sprintf('%6s',$pieces_count), "\n";
  print 'crap:       ',sprintf('%6s',$crap_count), ' (',sprintf('%0.2f',($crap_count/$pieces_count)), ")\n";
  print '    sim .7: ',sprintf('%6s',$crap_similar), ' (',sprintf('%0.2f',($crap_similar/$pieces_count)), ")\n";
  print 'words:      ',sprintf('%6s',$word_count), ' (',sprintf('%0.2f',($word_count/$pieces_count)), ")\n";
  print 'in dicts:   ',sprintf('%6s',$dict_count), ' (',sprintf('%0.2f',($dict_count/$pieces_count)), ")\n";
  print '    sim .7: ',sprintf('%6s',$words_similar), ' (',sprintf('%0.2f',($words_similar/$pieces_count)), ")\n";
  for my $dict_name (sort keys %$dict_matches) {
    print '   ',$dict_name,': ',sprintf('%6s',$dict_matches->{$dict_name}), ' (',sprintf('%0.2f',($dict_matches->{$dict_name}/$pieces_count)), ")\n";
  }

}

#for my $key (sort { $words->{$b} <=> $words->{$a}} keys %$words) {
#  print $key,"\t",$words->{$key},"\n";
#}
