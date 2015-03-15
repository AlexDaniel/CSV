# ex:se inputtab=tab autotab:

.PHONY:         test test-verbose profile time
.PRECIOUS:      test-t.pl

Text/CSV.pm:
	@[ -d Text ] || ( mkdir Text ; ln -s ../test-t.pl Text/CSV.pm )

test:		Text/CSV.pm
	@perl bugs.pl -s
	prove -e 'perl6 -I.' t

test-verbose:	Text/CSV.pm
	perl6 -I. t/10_base.t
	perl6 -I. t/12_acc.t
	perl6 -I. t/15_flags.t
	perl6 -I. t/16_methods.t
	perl6 -I. t/20_file.t
	perl6 -I. t/21_combine.t
	perl6 -I. t/22_print.t
	perl6 -I. t/40_misc.t
	perl6 -I. t/41_null.t
	perl6 -I. t/50_utf8.t
	perl6 -I. t/55_combi.t
	perl6 -I. t/60_samples.t
	perl6 -I. t/65_allow.t
	perl6 -I. t/77_getall.t
	perl6 -I. t/78_fragment.t
	perl6 -I. t/79_callbacks.t
	perl6 -I. t/81_subclass.t
	perl6 -I. t/82_subclass.t

profile:
	perl6 -I. --profile test-t.pl < /tmp/hello.csv
	mv profile-[0-9]* profile.html

time:
	perl time.pl
