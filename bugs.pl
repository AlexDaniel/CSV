#!/pro/bin/perl

use 5.18.0;
use warnings;
use Term::ANSIColor;

sub usage
{
    my $err = shift and select STDERR;
    say "usage: $0 [--test]";
    exit $err;
    } # usage

use Getopt::Long qw(:config bundling);
GetOptions (
    "help|?"     => sub { usage (0); },
    "s|summary!" => \my $opt_s,
    ) or usage (1);

my $t = "t$$.pl";
my $e = "e$$.pl";
END { unlink $t, $e; }

$opt_s and say "Bug summary:";

my $title = "";
{   my $b = 1;
    sub title {
        $title = join " " => $b++, colored (["blue"], " @_");
        $opt_s or say "\n", $title;
        }
    }

sub test
{
    my ($re, $p) = @_;

    open my $fh, ">", $t or die "$t: $!\n";
    print $fh $p;
    close $fh;

    system "perl6 $t >$e 2>&1";
    my $E = do { local (@ARGV, $/) = $e; <> };
    (my $P = $E) =~ s{^}{  }gm;
    $P =~s/[\s\r\n]+\z//;
    my $fail = $E =~ $re;
    if ($opt_s) {
        my $color = $fail ? 31 : 32;
        (my $msg = $title) =~ s/34m/${color}m/g;
        say $msg;
        return;
        }
    printf "\n  --8<--- %s\n%s\n  -->8---\n", $fail
        ? colored (["red"  ], "BUG")
        : colored (["green"], "Fixed"), $P;
    } # test

{   title "[Scope]     of class variables, they do not work in regex";
    # Nil
    # Match.new(orig => "baz", from => 1, to => 2, ast => Any, list => ().list, hash => EnumMap.new())
    test (qr{
        \A Nil
        \n Match
        }x, <<'EOP');
      use v6;

      class c {
            has Str $.foo is rw = "a";

            method bar (Str $s) {
                return $s ~~ / $!foo /;
                }
            method bux (Str $s) {
                my $foo = $!foo;
                return $s ~~ / $foo /;
                }
            }

      c.new.bar("baz").perl.say;
      c.new.bux("baz").perl.say;
EOP
    }

{   title "[Operation] s{} fails on native type (int)";
    # bar
    # 000:
    # 1x
    # Cannot call 'subst-mutate'; none of these signatures match:
    #   in method subst-mutate at src/gen/m-CORE.setting:4255
    #   in sub foo at t.pl:7
    #   in block <unit> at t.pl:15
    test (qr{
        \A bar
        \n 000:
        \n 1x
        \n Cannot \s+ call \s+ 'subst-mutate'
        }x, <<'EOP');
      use v6;

      sub foo (*@y) {
          for @y {
              s{^(\d+)$} = sprintf "%03d:", $_;
              .say;
              }
          }

      foo("bar");
      foo("0");
      foo("1x");
      foo(0);
EOP
    }

{   title "[Scope]     Placeholder variables cannot be used in a method";
    # They work in sub but not in method
    # ===SORRY!=== Error while compiling t.pl
    # Placeholder variables cannot be used in a method
    # at t.pl:16
    test (qr{
        (?-x:Placeholder variables cannot be used in a method)
        }x, <<'EOP');
      use v6;

      class c {
          method foo (*@y) {
              for @y -> $y {
                  $y.say;
                  }
              }
          method bar () {
              for @_ -> $y {  # FAIL
                  $y.say;
                  }
              }
          }

      sub foo (*@y) {
          for @y -> $y {
              $y.say;
              }
          }
      sub bar () {
          for @_ ->$y {      # PASS
              $y.say;
              }
          }

      foo("bux");
      bar("bux");
      c.new.foo("bux");
      c.new.bar("bux");
EOP
    }

{   title "[Operation] ++ and += do not work on basic types";

    # Cannot assign to an immutable value
    #   in sub postfix:<++> at src/gen/m-CORE.setting:5082
    #   in block <unit> at t.pl:7
    test (qr{
        (?-x:Cannot assign to an immutable value)
        }x, <<'EOP');
  use v6;

  my int $foo = 1;

  $foo++;
EOP
    }

{   title "[Lists]     Nil in list is silently dropped";

    # Array.new("foo", 1, 2, "a", "", 3)
    test (qr{1, 2},
          q{my @x = ("foo",1,Nil,2,"a","",3); @x.perl.say});
    }

{   title "[Test]      Compare to undefined type";

    # Failed test at lib/Test.pm line 110
    # expected: something with undefine
    #      got: something with undefine
    test (qr{expected:},
          q{use Test;my Str $s;is($s, Str, "");});
    }
