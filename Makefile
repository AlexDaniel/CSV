test:		Text/CSV.pm
	prove -e 'perl6 -I.'	\
	    t/10_base.t		\
	    t/11_subclass.t	\
	    t/12_acc.t		\
	    t/15_flags.t	\
	    t/20_file.t		\
	    t/40_misc.t		\
	    t/41_null.t		\
	    t/55_combi.t

test-verbose:	Text/CSV.pm
	perl6 -I. t/10_base.t
	perl6 -I. t/11_subclass.t
	perl6 -I. t/12_acc.t
	perl6 -I. t/15_flags.t
	perl6 -I. t/20_file.t
	perl6 -I. t/40_misc.t
	perl6 -I. t/41_null.t
	perl6 -I. t/55_combi.t

Text/CSV.pm:
	@[ -d Text ] || ( mkdir Text ; ln -s ../test-t.pl Text/CSV.pm )

time:
	perl time.pl
