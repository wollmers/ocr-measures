#!perl

use strict;
use warnings;
use utf8;

use lib qw(
../lib/
/Users/helmut/github/ocr-hw/ocr-measures/lib
/Users/helmut/github/perl/Levenshtein-Simple/lib
);

use Getopt::Long  '2.32';
use Pod::Usage;

use Unicode::Normalize;
use OCR::Compare;

#use Data::Dumper;

our $VERSION = '0.05';

binmode(STDOUT,":encoding(UTF-8)");
binmode(STDERR,":encoding(UTF-8)");

#######################

my $verbose;
my $lines        = 1; # details aligned lines: 1=short,2=full
my $clean_words  = 0; # remove punctuation from words
my $word_matches = 1;
my $char_matches = 1;
my $match_table  = 1;
my $help         = 0;
my $man          = 0;

GetOptions(
    'lines|l'           => \$lines,
    'trim_words|t'      => \$clean_words,
    'word_matches|w'    => \$word_matches,
    'char_matches|c'    => \$char_matches,
    'match_table|m'     => \$match_table,
    'help|h'            => \$help,
    'man'               => \$man,
)
or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitval => 0, -verbose => 2) if $man;
# or die("Error in command line arguments\n");

# TODO:
# redirect and restore STDOUT
#   https://www.perl.com/article/45/2013/10/27/How-to-redirect-and-restore-STDOUT/#:~:text=STDOUT%20is%20the%20Perl%20filehandle,can%20be%20redirected%20and%20restored.
#   https://stackoverflow.com/questions/3807231/how-can-i-test-if-i-can-write-to-a-filehandle
#   https://stackoverflow.com/questions/16060919/alias-file-handle-to-stdout-in-perl
#######################
my $file1 = ''; # ground truth
my $file2 = '';

# $ARGV[0]\n";
if (@ARGV >= 1) {
    $file1 = $ARGV[0];
    if (@ARGV >= 2) {
        $file2 = $ARGV[1];
    }
}

pod2usage(1) unless ($file1 && $file2);

#my $reportfile = 'ocr-compare.txt';
my $reportfile =  $file2;
$reportfile    =~ s/\.txt$//;
$reportfile    .= '.diff.txt';

open(my $report_fh,">:encoding(UTF-8)",$reportfile) or die "cannot open $reportfile: $!";

print $report_fh $0,' Version ',$VERSION,"\n";
print $report_fh "\n";
print $report_fh 'Compare ground truth (GRT) against OCR text output:',"\n";
print $report_fh 'File 1 (GRT): ',$file1,"\n";
print $report_fh 'File 2 (OCR): ',$file2,"\n";
print $report_fh "\n";

open(my $in1,"<:encoding(UTF-8)",$file1) or die "cannot open $file1: $!";
open(my $in2,"<:encoding(UTF-8)",$file2) or die "cannot open $file2: $!";

my $nl = '¶';
chomp(my @lines = <$in1>);
my @lines1   = map { $_ =~ s/\s+$//; my $s = $_ . $nl; NFC($s); } grep {/./} @lines;
chomp(@lines = <$in2>);
my @lines2   = map { $_ =~ s/\s+$//; my $s = $_ . $nl; NFC($s); } grep {/./} @lines;

my $compare = OCR::Compare->new({
    'verbose'      => $verbose,
    'lines'        => $lines,
    'clean_words'  => $clean_words,   # remove punctuation from words
    'word_matches' => $word_matches,  # print word matches
    'char_matches' => $char_matches,  # print char matches
    'match_table'  => $match_table,   # print match table
    'nl'           => '¶',            # character for end of line
    'threshold'    => 0.5,            # similarity of lines
    'report_fh'    => $report_fh,     # file handle
});

$compare->compare(\@lines1, \@lines2);

close $report_fh;

__END__

=head1 NAME

ocr_compare.pl - compare ground truth against OCR output

=head1 SYNOPSIS

ocr_compare.pl [options] ground_truth_file ocrfile

 Options:
   -help            brief help message
   -man             full documentation

=head1 DESCRIPTION

B<This program> will read the given input file(s) and do something
useful with the contents thereof.

=head1 OPTIONS

=over 8

=item B<-help>

Prints a brief help message and exits.

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




