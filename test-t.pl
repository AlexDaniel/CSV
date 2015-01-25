use v6;
use Slang::Tuxic;

my $opt_v = %*ENV<PERL6_VERBOSE> // 1;
my $test  = qq{,1,ab,"cd","e"0f","g,h","nl\nz"0i""""3",\r\n};
my @rslt  = ("", "1", "ab", "cd", "e\c0f", "g,h", qq{nl\nz\c0i""3}, "");

sub progress (*@y) {
    my Str $x;
    @y[0] = @y[0].Str;  # Still a bug
    my $line = callframe (1).annotations<line>;
    for (@y) {
        #$opt_v > 9 and .say;
        s{^(\d+)$}   = sprintf "@%3d %3d -", $line, $_;
        s:g{"True,"} = "True, ";
        s:g{"new("}  = "new (";
        $x ~= .Str ~ " ";
        }
    $x.say;
    } # progress

class CSV::Field {

    has Bool $.is_quoted  is rw = False;
    has Bool $.undefined  is rw = True;
    has Str  $.text       is rw;

    has Bool $!is_binary  = False;
    has Bool $!is_utf8    = False;
    has Bool $!is_missing = False;
    has Bool $!analysed   = False;

    enum Type < NA INT NUM STR BOOL >;

    method add (Str $chunk) {
        $!text     ~= $chunk;
        $!undefined = False;
        } # add

    method set_quoted () {
        $!is_quoted = True;
        $!undefined = False;
        .add("");
        }

    method !analyse () {
        $!analysed and return;

        $!analysed = True;

        $!undefined || $!text eq Nil || $!text eq "" and
            return; # Default is False for both

        $!text ~~ m{^ <[ \x20 .. \x7E ]>+ $} or
            $!is_binary = True;

        $!text ~~ m{^ <[ \x00 .. \x7F ]>+ $} or
            $!is_utf8   = True;
        }

    method is_binary () {
        $!analysed or self!analyse;
        return $!is_binary;
        }

    method is_utf8 () {
        $!analysed or self!analyse;
        return $!is_utf8;
        }

    method is_missing () {
        $!analysed or self!analyse;
        return $!is_missing;
        }

    } # CSV::Field

class Text::CSV {

    has Str  $.eol                   is rw;         # = ($*IN.newline),
    has Str  $.sep                   is rw = ',';
    has Str  $.quo                   is rw = '"';
    has Str  $.esc                   is rw = '"';

    has Bool $.binary                is rw = True;  # default changed
    has Bool $.decode_utf8           is rw = True;
    has Bool $.auto_diag             is rw = False;
    has Bool $.diag_verbose          is rw = False;

    has Bool $.blank_is_undef        is rw = False;
    has Bool $.empty_is_undef        is rw = False;
    has Bool $.allow_whitespace      is rw = False;
    has Bool $.allow_loose_quotes    is rw = False;
    has Bool $.allow_loose_escapes   is rw = False;
    has Bool $.allow_unquoted_escape is rw = False;

    has Bool $.always_quote          is rw = False;
    has Bool $.quote_space           is rw = True;
    has Bool $.quote_null            is rw = True;
    has Bool $.quote_binary          is rw = True;
    has Bool $.keep_meta_info        is rw = False;
    has Bool $.verbatim              is rw = False; # Should die!

    has Int  $.record_number         is rw = 0;

    has @!error_input;

    has @!fields;
    has @!types;
    has @!callbacks;

    method sep (*@s) {
        @s.elems == 1 and $!sep = @s[0];
        return $!sep;
        }

    method sep_char (*@s) {
        @s.elems == 1 and $!sep = @s[0];
        return $!sep;
        }

    method quote (*@s) {
        @s.elems == 1 and $!quo = @s[0];
        return $!quo;
        }

    method quote_char (*@s) {
        @s.elems == 1 and $!quo = @s[0];
        return $!quo;
        }

    method escape (*@s) {
        @s.elems == 1 and $!esc = @s[0];
        return $!esc;
        }

    method escape_char (*@s) {
        @s.elems == 1 and $!esc = @s[0];
        return $!esc;
        }

    method !ready (CSV::Field $f) {
        defined $f.text or $f.undefined = True;
        if ($f.undefined) {
            $!blank_is_undef or $f.add ("");
            push @!fields, $f;
            return;
            }
        if ($f.text eq Nil || $f.text eq "") {
            if ($!empty_is_undef) {
                $f.undefined = True;
                $f.text      = Nil;
                }
            push @!fields, $f;
            return;
            }

        # Postpone all other field attributes like is_binary and is_utf8
        # till it is actually asked for
        push @!fields, $f;
        } # ready

    method fields () {
        return @!fields;
        } # fields

    method string () {
        @!fields or return;
        my Str $s = $!sep;
        my Str $q = $!quo;
        my Str $e = $!esc;
        #progress (0, @!fields.perl);
        my Str @f;
        for @!fields -> $f {
            if ($f.undefined) {
                @f.push ($!quote_null   ?? <""> !! "");
                next;
                }
            my $t = $f.text;
            if ($t eq "") {
                @f.push ($!always_quote ?? <""> !! "");
                next;
                }
            $t .= subst (/( $q | $e )/, { "$e$0" }, :g);
            $!always_quote
            ||                   $t ~~ / $e  | $s /
            || ($!quote_space && $t ~~ / " " | \t /)
                and $t = qq{"$t"};
            push @f, $t;
            }
        #progress (0, @f.perl);
        my Str $x = join $!sep, @f;
        #progress (1, $x);
        return $x;
        } # string

    method combine (*@f) {
        @!fields = ();
        for @f -> $f {
            my $cf = CSV::Field.new;
            defined $f and $cf.add ($f.Str);
            self!ready ($cf);
            }
        return True;
        }

    method parse (Str $buffer) {

        my     $field;
        my int $pos = 0;

        my sub parse_error (Str $reason, *@args) {
            my $msg = $reason.sprintf (@args);
            die "$msg\n$buffer\n" ~ ' ' x $pos ~ "^\n";
            }

        $!record_number++;
        $opt_v > 4 and progress ($!record_number, $buffer.perl);

        # A scoping bug in perl6 inhibits the use of $!eol inside the split
        #for $buffer.split (rx{ $!eol | $!sep | $!quo | $!esc }, :all).map (~*) -> Str $chunk {
        my     $eol = $!eol // rx{ \r\n | \r | \n };
        my Str $sep = $!sep;
        my Str $quo = $!quo;
        my Str $esc = $!esc;
        my $f = CSV::Field.new;

        @!fields = Nil;

        sub keep {
            self!ready ($f);
            $f = CSV::Field.new;
            } # add

#       my @ch = grep { .Str ne "" },
#           $buffer.split (rx{ $eol | $sep | $quo | $esc }, :all).map (~*);
        my @ch = $buffer.split (rx{ $eol | $sep | $quo | $esc }, :all).map: {
            if $_ ~~ Str {
                $_   if .chars;
                }
            else {
                .Str if .Bool;
                };
            };

        my int $skip = 0;
        my int $i    = -1;

        for @ch -> Str $chunk {
            $i = $i + 1;

            $opt_v > 2 && $i == 0 and progress ($i, @ch.perl);

            if ($skip) {
                # $skip-- fails:
                # Masak: there's wide agreement that that should work, but
                #  it's difficult to implement. here's (I think) why: usually
                #  the $value gets replaced by $value.pred and then put back
                #  into the variable's container. but natives have no
                #  containers, only the value itself.
                $skip = $skip - 1;      # $i-- barfs. IMHO a bug
                next;
                }

            $opt_v > 8 and progress ($i, "###", "'$chunk'\t", $f.perl);

            if ($chunk eq $sep) {
                $opt_v > 5 and progress ($i, "SEP");

                # ,1,"foo, 3",,bar,
                # ^           ^
                if ($f.undefined) {
                    $!blank_is_undef || $!empty_is_undef or
                        $f.add ("");
                    keep;
                    next;
                    }

                # ,1,"foo, 3",,bar,
                #        ^
                if ($f.is_quoted) {
                    $opt_v > 9 and progress ($i, "    inside quoted field ", @ch[$i..*-1].perl);
                    $f.add ($chunk);
                    next;
                    }

                # ,1,"foo, 3",,bar,
                #   ^        ^    ^
                keep;
                next;
                }

            if ($chunk eq $quo) {
                $opt_v > 5 and progress ($i, "QUO", $f.perl);

                # ,1,"foo, 3",,bar,\r\n
                #    ^
                if ($f.undefined) {
                    $opt_v > 9 and progress ($i, "    initial quote");
                    $f.set_quoted;
                    next;
                    }

                if ($f.is_quoted) {

                    $opt_v > 9 and progress ($i, "    inside quoted field ", @ch[$i..*-1].perl);
                    # ,1,"foo, 3"
                    #           ^
                    if ($i == @ch - 1) {
                        keep;
                        return @!fields;
                        }

                    my Str $next   = @ch[$i + 1] // Nil;
                    my int $omit   = 1;
                    my int $quoesc = 0;

                    # , 1 , "foo, 3" , , bar , "" \r\n
                    #               ^            ^
                    if ($!allow_whitespace && $next ~~ /^ \s+ $/) {
                        $next = @ch[$i + 2] // Nil;
                        $omit++;
                        }

                    $opt_v > 8 and progress ($i, "QUO", "next = $next");

                    # ,1,"foo, 3",,bar,\r\n
                    #           ^
                    if ($next eq $sep) {
                        $opt_v > 7 and progress ($i, "SEP");
                        $skip = $omit;
                        keep;
                        next;
                        }

                    # ,1,"foo, 3"\r\n
                    #           ^
                    # Nil can also indicate EOF
                    if ($next eq Nil || $next ~~ /^ $eol $/) {
                        keep;
                        return @!fields;
                        }

                    if (defined $esc and $esc eq $quo) {
                        $opt_v > 7 and progress ($i, "ESC", "($next)");

                        $quoesc = 1;

                        # ,1,"foo, 3"056",,bar,\r\n
                        #            ^
                        if (@ch[$i + 1] ~~  /^ "0"/) {  # cannot use $next
                            @ch[$i + 1] ~~ s{^ "0"} = "";
                            $opt_v > 8 and progress ($i, "Add NIL");
                            $f.add ("\c0");
                            next;
                            }

                        # ,1,"foo, 3""56",,bar,\r\n
                        #            ^
                        if (@ch[$i + 1] eq $quo) {
                            $skip = $omit;
                            $f.add ($chunk);
                            next;
                            }

                        if ($!allow_loose_escapes) {
                            # ,1,"foo, 3"56",,bar,\r\n
                            #            ^
                            next;
                            }
                        }

                    # No need to special-case \r

                    if ($quoesc == 1) {
                        # 1,"foo" ",3
                        #        ^
                        parse_error ("2023");
                        }
                    elsif ($!allow_loose_quotes) {
                        # ,1,"foo, 3"456",,bar,\r\n
                        #            ^
                        $f.add ($chunk);
                        next;
                        }
                    # Keep rest of @ch for hooks?
                    parse_error ("2011");
                    }

                # 1,foo "boo" d'uh,1
                #       ^
                if ($!allow_loose_quotes) {
                    $f.add ($chunk);
                    next;
                    }
                parse_error ("2034");
                }

            if ($chunk eq $esc) {
                $opt_v > 5 and progress ($i, "ESC", $f.perl);
                }

            if ($chunk ~~ rx{^ $eol $}) {
                $opt_v > 5 and progress ($i, "EOL");
                if ($f.is_quoted) {     # 1,"2\n3"
                    $f.add ($chunk);
                    next;
                    }
                keep;
                return @!fields;
                }

            $chunk ne "" and $f.add ($chunk);
            $pos += .chars;
            }

        keep;
        return @!fields;
        } # parse

    method getline () {
        return @!fields;
        } # getline
    }

sub MAIN () {

    my $csv_parser = Text::CSV.new;

    $opt_v > 1 and say $csv_parser.perl;
    $opt_v and progress (.perl) for $csv_parser.parse ($test);
    $opt_v and Qw { Expected: Str 1 ab cd e\0f g,h nl\nz\0i""3 Str }.say;

    my Int $sum = 0;
    for lines () :eager {
        my @r = $csv_parser.parse ($_);
        $sum += +@r;
        }
    $sum.say;
    }

1;
