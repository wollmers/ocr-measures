# NAME

ocr\_compare.pl - compare OCR output against ground truth

# SYNOPSIS

ocr\_compare.pl \[options\] ocrfile ground\_truh\_file

    Options:
      -help            brief help message
      -man             full documentation

# DESCRIPTION

**This program** will read the given input file(s) and do something
useful with the contents thereof.

# OPTIONS

- **-help**

    Print a brief help message and exits.

- **-man**

    Prints the manual page and exits.

- **-lines**, **-l**

    Print alignment of lines. Default: off.

- **-trim\_words**, **-t**

    Trim punctuation characters at start and end of words. Default: on.

- **-word\_matches**, **-w**

    Report mismatches of words with frequencies. Default: off.

- **-char\_matches**, **-c**

    Report mismatches of chars with frequencies. Default: off.

- **-match\_table**, **-m**

    Output character mismatches usable as confusion matrix. Default: off.
