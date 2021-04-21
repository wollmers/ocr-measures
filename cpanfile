requires 'perl', '5.01000';

requires 'LCS',                '0.00';
requires 'LCS::Tiny',          '0.00';
requires 'LCS::BV',            '0.00';
requires 'String::Similarity', '0.00';
requires 'LCS::Similar',       '0.00';
requires 'Getopt::Long',       '2.32';
requires 'Pod::Usage',         '0.00';
requires 'Text::Levenshtein::BV', '0.00';

on test => sub {
  requires 'Test::More',       '0.88';
  requires 'Test::More::UTF8', '0.00';
};

on 'develop' => sub {
  requires 'Test::Pod::Coverage';
  requires 'Test::Pod',  '1.00';
  requires 'Encode',     '0.00';
};