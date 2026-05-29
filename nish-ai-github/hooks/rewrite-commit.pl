#!/usr/bin/env perl
# Collapse a `git commit` to a subject-only commit when it carries a body or a
# Co-Authored-By trailer. Reads the full command as the first argument; prints
# "<subject>\x1e<rewritten command>" when it can confidently rewrite, nothing
# otherwise. The rewrite keeps everything before `git commit` (e.g. a
# `git add -A &&` prefix) so staging is preserved.
use strict;
use warnings;

my $cmd = $ARGV[0] // '';

# Split at the first `git commit`; keep everything before it.
$cmd =~ /(.*?\bgit\s+commit\b)(.*)/s or exit 0;
my ($head, $rest) = ($1, $2);

# Find the first message flag. No `-m`/`--message` (e.g. `-F file`) → cannot rewrite.
$rest =~ /(-m\b|--message\b)/ or exit 0;
my $struct  = $`;          # structural flags between `git commit` and the message
my $msgpart = $& . $';     # the message portion, from the first flag onward

my ($subject, $extra, $tail) = ('', 0, '');

if ($msgpart =~ /^(?:-m|--message)\s+"\$\(\s*cat\s*<<-?\s*(['"]?)(\w+)\1\s*\n(.*?)\n[ \t]*\2[ \t]*\n?[ \t]*\)"(.*)$/s) {
  # Form A: heredoc — -m "$(cat <<'EOF' … EOF )"
  my $content = $3;
  $tail = $4;
  my @lines = split /\n/, $content, -1;
  $subject = $lines[0] // '';
  $extra = ( grep { /\S/ } @lines[1 .. $#lines] ) ? 1 : 0;
  $extra ||= ( $content =~ /co-authored-by/i ) ? 1 : 0;
} else {
  # Form B: one or more -m "…"/'…' tokens, values may themselves be multi-line.
  my $r = $msgpart;
  my @vals;
  while ($r =~ s/^\s*(?:-m|--message)\s+(?:"([^"]*)"|'([^']*)')//s) {
    push @vals, defined $1 ? $1 : $2;
  }
  @vals or exit 0;
  $tail = $r;
  my @first = split /\n/, $vals[0], -1;
  $subject = $first[0] // '';
  $extra  = ( @vals  > 1 && grep { /\S/ } @vals[1 .. $#vals] )   ? 1 : 0;
  $extra ||= ( @first > 1 && grep { /\S/ } @first[1 .. $#first] ) ? 1 : 0;
  $extra ||= ( join("\n", @vals) =~ /co-authored-by/i )          ? 1 : 0;
}

$extra or exit 0;             # nothing to strip → let the validator's normal flow handle it
$tail =~ /\S/ and exit 0;     # structure after the message (e.g. `&& git push`) → too risky
$subject =~ /\S/ or exit 0;   # empty subject → let normal validation handle it

(my $esc = $subject) =~ s/([\\"\$`])/\\$1/g;   # escape for a double-quoted shell string
(my $s = $struct) =~ s/\s+$//;
print $subject . "\x1e" . $head . $s . ' -m "' . $esc . '"';
