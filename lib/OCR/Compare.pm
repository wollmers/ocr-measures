package OCR::Compare;

use strict;
use warnings;
use utf8;

use LCS;
use LCS::Tiny;
use LCS::BV;
use String::Similarity;
use LCS::Similar;

use Text::Levenshtein::BV;
use Levenshtein::Simple;

use charnames ':full';

use Data::Dumper;

our $VERSION = '0.04';

binmode(STDOUT,":encoding(UTF-8)");
binmode(STDERR,":encoding(UTF-8)");

my $lev = Levenshtein::Simple->new;

sub new {
    my ($class, $args) = @_;
    my $self = {
        'verbose'      => $args->{'verbose'}      || 0,
        'lines'        => $args->{'lines'}        || 0,   # print aligned lines: 1=short, 2=full
        'clean_words'  => $args->{'clean_words'}  || 0,   # remove punctuation from words
        'word_matches' => $args->{'word_matches'} || 0,   # print word matches
        'char_matches' => $args->{'char_matches'} || 0,   # print char matches
        'match_table'  => $args->{'match_table'}  || 1,   # print match table
        'nl'           => $args->{'nl'}           || '¶', # character for end of line
        'threshold'    => $args->{'threshold'}    || 0.5, # similarity of lines
        'report_fh'    => $args->{'report_fh'},           # file handle

        'stats' => {
            'lines' => {},
            'words' => {},
            'chars' => {},
        },
        'mismatches' => {
            'lines' => {},
            'words' => {},
            'chars' => {},
        },
    };
    return bless $self, $class;
}


sub compare {
    my ($self, $lines1, $lines2) = @_;

    my $compare = sub {
        my ($a,$b,$threshold) = @_;
        my $similarity = similarity($a,$b, $threshold);
        return $similarity if ($similarity >= $threshold);
        return 0;
    };

    my $lcs     = LCS::Similar->LCS($lines1, $lines2, $compare, $self->{'threshold'});
    my $aligned = LCS->lcs2align($lines1, $lines2, $lcs);

    for my $chunk (@$aligned) {
        $self->compare_line($chunk->[0],$chunk->[1]);
    }

    $self->finish_report();
}

sub finish_report {
    my ($self) = @_;

    my $report_fh = $self->{'report_fh'};

    $self->print_matches();

    $self->calc_stats('lines');
    $self->calc_stats('words');
    $self->calc_stats('chars');

    print $report_fh "\n";
    print $report_fh 'Summary:',"\n";
    print $report_fh "\n";
    $self->print_stats();
}

sub compare_line {
    my ($self, $line1, $line2) = @_;

    $self->add_stats('lines', _count_aligned([[$line1, $line2]]));

    #print STDERR 'lines: ',Dumper($self->{'stats'});

    my @words1 = $line1 =~ /(\S+)/g;
    my @words2 = $line2 =~ /(\S+)/g;

=pod
    my $words_aligned = LCS->lcs2align(
            \@words1,
            \@words2,
            #LCS::Tiny->LCS(\@words1,\@words2)
            LCS::BV->LCS(\@words1,\@words2)
    );
=cut
    my $words_aligned = $lev->ses2align(
            \@words1,
            \@words2,
            #LCS::Tiny->LCS(\@words1,\@words2)
            $lev->ses(\@words1,\@words2)
    );

    $self->add_stats('words', _count_aligned($words_aligned));
    $self->record_mismatches($words_aligned, 'words');

    my @chars1 = $line1 =~ m/(\X)/g; # graphemes
    my @chars2 = $line2 =~ m/(\X)/g; # graphemes
    my $chars_aligned;

if (1) {
        $chars_aligned = $lev->ses2align(
            \@chars1,
            \@chars2,
            $lev->ses(\@chars1, \@chars2)
        );
}

if (0) {
    if (@chars1 < 64) {
        $chars_aligned = LCS->lcs2align(
        #$chars_aligned = $lev->hunks2char(
            \@chars1,
            \@chars2,
            #LCS::Tiny->LCS(\@chars1,\@chars2)
            LCS::Similar->LCS(\@chars1, \@chars2, \&_confusable, 0.7)
            #$lev->ses(\@chars1, \@chars2)
        );
    }
    else {
        $chars_aligned = LCS->lcs2align(
            \@chars1,
            \@chars2,
            #LCS::Tiny->LCS(\@chars1,\@chars2)
            LCS::Similar->LCS(\@chars1, \@chars2, \&_confusable, 0.7)
            #Text::Levenshtein::BV->SES(\@chars1, \@chars2)
        );
    }
}

    #print STDERR '$chars_aligned: ',Dumper($chars_aligned);

    my ($matches, $inserts, $substitutions, $deletions) =
            _count_aligned($chars_aligned);
    $self->record_mismatches($chars_aligned, 'chars');

    my $is_equal = ($matches == @chars1 && $matches == @chars2);

    $self->add_stats('chars', ($matches, $inserts, $substitutions, $deletions));

    if ($self->{'lines'}) {
        my $accuracy = $matches / ($matches + $substitutions + $inserts + $deletions);
        $self->print_alignment($chars_aligned, $is_equal, $accuracy);
    }
}

sub print_alignment {
    my ($self, $chars_aligned, $is_equal, $accuracy) = @_;

    my $report_fh = $self->{'report_fh'};

    if ($self->{'lines'} >= 1) {
        #my ($s1,$s2) =   $lev->align2strings($chars_aligned);
        my ($s1,$s2) =   LCS->align2strings($chars_aligned);
        if ($is_equal) {
            print $report_fh $s1,' ',sprintf('%0.3f',$accuracy),"\n";
            print $report_fh "\n";
        }
        else {
            print $report_fh $s1,"\n";
            print $report_fh _relation_aligned($chars_aligned),
                ' ',sprintf('%0.3f',$accuracy),"\n";
            print $report_fh $s2,"\n";
            print $report_fh "\n";
        }
    }
}

sub print_matches {
    my ($self) = @_;

    my $report_fh = $self->{'report_fh'};

	if ($self->{'word_matches'}) {
    	print $report_fh "\n";
    	print $report_fh 'Word mismatches:',"\n";
    	$self->print_mismatches('words',1);
	}

	if ($self->{'char_matches'}) {
    	print $report_fh "\n";
    	print $report_fh 'Character mismatches:',"\n";
    	$self->print_mismatches('chars',1);
	}

	if ($self->{'match_table'}) {
    	print $report_fh "\n";
    	print $report_fh 'Character match (confusion) table:',"\n";
    	$self->print_confusion_table('chars',1);
	}
}


###########################
sub print_mismatches {
    my ($self, $type, $suppress_matches) = @_;

    my $mismatches = $self->{'mismatches'}->{$type};

    my $report_fh = $self->{'report_fh'};

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

            print $report_fh '"',$token,'"',sprintf('%6s',$count);
            if ($type eq 'chars') {
                my $charcount = 0;
                for my $char (split(//,$token)) {
                    $charcount++;
                    my $charname = charnames::viacode(ord($char));
                    my $char_code = sprintf('U+%04X', ord($char));    # %04X or %04x
                    if ($charcount >= 2) {
                      print $report_fh "\n",'   ',sprintf('%6s',' ');
                    }
                    print $report_fh ' ',
                        sprintf('%9s', $char_code), ' ',$charname;
                }
            }
            print $report_fh "\n";
            for my $mismatch (sort keys %{$mismatches->{$token}}) {
                print $report_fh '  ','"',$mismatch,'"',
                sprintf('%6s',$mismatches->{$token}->{$mismatch}),
                ' (',sprintf('%0.4f',$mismatches->{$token}->{$mismatch}/$count),')';
                if ($type eq 'chars') {
                    my $charcount = 0;
                    for my $char (split(//,$mismatch)) {
                        $charcount++;
                        my $charname = charnames::viacode(ord($char));
                        my $char_code = sprintf('U+%04X', ord($char));    # %04X or %04x
                        if ($charcount >= 2) {
                            print $report_fh "\n",'       ',sprintf('%13s',' ');
                        }
                        print $report_fh ' ',
                            sprintf('%9s', $char_code), ' ',$charname;
                    }
                }
                print $report_fh "\n";
            }
        }
    }
}

sub print_confusion_table {
    my ($self, $type, $suppress_matches) = @_;

    my $mismatches = $self->{'mismatches'}->{$type};
    my $report_fh  = $self->{'report_fh'};

    print $report_fh 'GRT => OCR  ratio  errors   count',"\n";
    print $report_fh '---    --- ------ ------- -------',"\n";

    for my $token (sort keys %$mismatches) {
        my $count = 0;
        for my $mismatch (sort keys %{$mismatches->{$token}}) {
            $count += $mismatches->{$token}->{$mismatch};
        }
        unless ( exists $mismatches->{$token}->{$token}
            && $mismatches->{$token}->{$token} == $count
            && $suppress_matches) {

            for my $mismatch (sort keys %{$mismatches->{$token}}) {
                print $report_fh
                "'",sprintf('%1s',$token),"'",
                ' => ',
                "'",sprintf('%1s',$mismatch),"'",' ',
                sprintf('%0.4f',$mismatches->{$token}->{$mismatch}/$count),
                ' ',sprintf('%7s',$mismatches->{$token}->{$mismatch}),
                ' ',sprintf('%7s',$count),
                "\n"
                unless ($token eq $mismatch && $suppress_matches);
            }
        }
    }
}

our $map = {
	'a' => [qw(à aͤ s)],
	'b' => [qw(d h v)],
    'c' => [qw(e &)],
	'd' => [qw(c)],
	'e' => [qw(c)],
	'é' => [qw(e ë ẽ c)],
	'ê' => [qw(è)],
	'f' => [qw(t ſ s)],
    'i' => [qw(t)],
	'j' => [qw(ſ)],
	'k' => [qw(h)],
	'l' => [qw(h t ü ſ)],
    'm' => [qw(n)],
	'n' => [qw(u g m y)],
	'oͤ' => [qw(o ö)],
	'r' => [qw(c i î t)],
	's' => [qw(S oͤ)],
    't' => [qw(i f l r)],
    'u' => [qw(u᷑ n)],
	'ü' => [qw(ũ i l t u ũ)],
    'w' => [qw(V)],
    'x' => [qw(z)],
    'y' => [qw(p)],
    'ſ' => [qw(f i j l { )],

	'D' => [qw(B)],
	'E' => [qw(B)],
	'H' => [qw(B I S)],
	'I' => [qw(J)],
	'J' => [qw(j)],
    'L' => [qw(T)],
    'M' => [qw(N)],
    'R' => [qw(K)],

	',' => [qw(.)],
	'-' => [qw(—)],
	';' => [qw(3)],
	'⸗' => [qw(—)],

	'1' => [qw(4)],
	'3' => [qw(2 8)],
	'5' => [qw(6)],

};

our $confusables;

sub get_map {

	return $confusables if (defined $confusables);

	for my $char1 (keys %$map) {
		for my $char2 ( @{$map->{$char1}} ) {
			$confusables->{$char1}->{$char2} = 1;
			$confusables->{$char2}->{$char1} = 1;
		}
	}
    return $confusables;
}

sub _confusable {
    my ($a, $b, $threshold) = @_;

    #$a //= '';
    #$b //= '';
    #$threshold //= 0.7;

    return 1 if ($a eq $b);
    return 1 if (!$a && !$b);

    my $map = get_map();

    #return $threshold if (exists $map->{$a} && $map->{$a} eq $b);
    return $threshold if (exists $map->{$a}->{$b});
}

sub _relation_aligned {
    my $aligned = shift;

    my $line = '';

    my $match  = '|';
    my $delete = '-';
    my $insert = '+';
    my $subst  = '~';

    for my $chunk (@$aligned) {
        if    ($chunk->[0]  eq $chunk->[1])  { $line .= $match; }
        elsif (!$chunk->[0] && $chunk->[1])  { $line .= $insert; }
        elsif ($chunk->[0]  && !$chunk->[1]) { $line .= $delete; }
        else                                 { $line .= $subst; }
    }
    return $line;
}

sub _count_aligned {
    my $aligned = shift;
    my ($matches, $inserts, $substitutions, $deletions) = (0,0,0,0);

    for my $chunk (@$aligned) {
        if    ($chunk->[0]  eq $chunk->[1])  { $matches++; }
        elsif (!$chunk->[0] && $chunk->[1])  { $inserts++;  }   # TODO: !length($chunk->[0])
        elsif ($chunk->[0]  && !$chunk->[1]) { $deletions++; }  # TODO: !length($chunk->[1])
        else                                 { $substitutions++; }
    }
    return ($matches, $inserts, $substitutions, $deletions);
}

sub record_mismatches {
    my ($self, $aligned, $type) = @_;

    my $mismatches = $self->{'mismatches'}->{$type};

    for my $chunk (@$aligned) {
        #if ($chunk->[0] && $chunk->[1] && $chunk->[0] ne $chunk->[1]) {
        my $token1 = $chunk->[0];
        my $token2 = $chunk->[1];

        #my $prefix  = qr/ [\(\)\[\]='",;:!?\.]+ /xms;
        #my $suffix  = qr/ [\(\)\[\]='",;:!?¶ ]+ /xms;

        # TODO: better definition of word characters
        if ($self->{'clean_words'}) {
            my $prefix  = qr/ [\(\)\[\]='",;:!?\.]+ /xms;
            my $suffix  = qr/ [\(\)\[\]='",;:!?¶ ]+ /xms;

            $token1 =~ s/^$prefix//;
            $token1 =~ s/$suffix$//;
            $token2 =~ s/^$prefix//;
            $token2 =~ s/$suffix$//;
        }

        if ($token1 eq '') { $token1 = '_' }
        if ($token2 eq '') { $token2 = '_' }
        #if ($token1 && $token2) {
            $mismatches->{$token1}->{$token2}++;
        #}
    }
}

sub add_stats {
    my $self  = shift;
    my $type  = shift;

    my $stats = $self->{'stats'}->{$type};

    my $data  = {};
    @$data{qw(matches inserts substitutions deletions)} = @_;
    #print Dumper($data);
    for my $key (keys %$data) {
        $stats->{$key} += $data->{$key};
    }
    #print STDERR 'data: ',Dumper($data);
}

sub print_stats {
    my $self    = shift;
    my $stats   = $self->{'stats'};

    my $report_fh = $self->{'report_fh'};

    my $columns = [qw(lines words chars)];
    my $lines = [
        {'items_ocr'     => {'label'=> 'items ocr:  ', 'mask' => '%7s',    'comment' => 'matches + inserts + substitutions'}},
        {'items_grt'     => {'label'=> 'items grt:  ', 'mask' => '%7s',    'comment' => 'matches + deletions + substitutions'}},
        {'matches'       => {'label'=> 'matches:    ', 'mask' => '%7s',    'comment' => 'matches'}},
        {'edits'         => {'label'=> 'edits:      ', 'mask' => '%7s',    'comment' => 'inserts + deletions + substitutions'}},
        {'substitutions' => {'label'=> ' subss:     ', 'mask' => '%7s',    'comment' => 'substitutions'}},
        {'inserts'       => {'label'=> ' inserts:   ', 'mask' => '%7s',    'comment' => 'inserts'}},
        {'deletions'     => {'label'=> ' deletions: ', 'mask' => '%7s',    'comment' => 'deletions'}},
        {'precision'     => {'label'=> 'precision:  ', 'mask' => ' %0.4f', 'comment' => 'matches / (matches + substitutions + inserts)'}},
        {'recall'        => {'label'=> 'recall:     ', 'mask' => ' %0.4f', 'comment' => 'matches / (matches + substitutions + deletions)'}},
        {'accuracy'      => {'label'=> 'accuracy:   ', 'mask' => ' %0.4f', 'comment' => 'matches / (matches + substitutions + inserts + deletions)'}},
        {'f_score'       => {'label'=> 'f-score:    ', 'mask' => ' %0.4f', 'comment' => '( 2 * recall * precision ) / ( recall + precision )'}},
        {'error'         => {'label'=> 'error rate: ', 'mask' => ' %0.4f', 'comment' => '( inserts + deletions + substitutions ) / (items grt )'}},
    ];

  print $report_fh '              ',join('   ',@$columns),"\n";

  for my $line (@$lines) {
      my ($key) = (keys %$line);
      print $report_fh $line->{$key}->{'label'};
      for my $column (@$columns) {
          print $report_fh sprintf($line->{$key}->{'mask'},$stats->{$column}->{$key}),' ';
      }
      print $report_fh $line->{$key}->{'comment'};
      print $report_fh "\n";
  }
}

sub calc_stats {
    my ($self, $type)    = @_;
    my $stats   = $self->{'stats'}->{$type};

    my ($matches, $inserts, $substitutions, $deletions) =
        map { $stats->{$_} } qw(matches inserts substitutions deletions);

    $stats->{'items_ocr'} = ($matches + $inserts + $substitutions);
    $stats->{'items_grt'} = ($matches + $deletions + $substitutions);
    $stats->{'edits'} = ($inserts + $deletions + $substitutions);
    $stats->{'precision'} = (($matches + $substitutions + $inserts) > 0 ) ?
        ($matches / ($matches + $substitutions + $inserts)) : 0;
    $stats->{'recall'}    = (($matches + $substitutions + $deletions) > 0 ) ?
        ($matches / ($matches + $substitutions + $deletions)) : 0;
    $stats->{'accuracy'}  = (($matches + $substitutions + $inserts + $deletions) > 0 ) ?
        ($matches / ($matches + $substitutions + $inserts + $deletions)) : 0;
    $stats->{'f_score'}   = (($stats->{'recall'} + $stats->{'precision'}) > 0 ) ?
        (
            ( 2 * $stats->{'recall'} * $stats->{'precision'} )
            / ($stats->{'recall'} + $stats->{'precision'} )
        ) : 0;
    $stats->{'error'}     = ($inserts + $deletions + $substitutions)
        / ($stats->{'items_grt'});
}

1;

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




