#!/bin/sh

time perl  csv-easy-xs.pl < /tmp/hello.csv
time perl  csv-easy-pp.pl < /tmp/hello.csv
time perl  csv-test-xs.pl < /tmp/hello.csv
time perl  csv-test-pp.pl < /tmp/hello.csv
time perl  csv-pegex.pl   < /tmp/hello.csv
time perl6 csv.pl         < /tmp/hello.csv
time perl6 csv_gram.pl    < /tmp/hello.csv
time perl6 test.pl        < /tmp/hello.csv
time perl6 test-t.pl      < /tmp/hello.csv

