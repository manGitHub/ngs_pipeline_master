#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use 5.010;

local $SIG{__WARN__} = sub {
        my $message =shift;
        die $message;
};

#system("awk 'BEGIN {FS="\t"} $(NF-8)>=20 && $(NF-3)>=20 && $(NF)>=0.1 {print $1, $2, $3, $(NF-10), $(NF-9), $(NF-8), $(NF-5), $(NF-4), $(NF-3), $NF}' $ARGV[0]");
#awk 'BEGIN {FS="\t"} $200>=20 && $205>=20 && $208>=0.1 {print $1, $2, $3, $198, $199, $200, $203, $204, $205, $208}' NCI0338_T1D_E.MuTect.annotated.txt | wc -l

my($ann_var, $intervals, $tcov, $ncov, $vaf) = @ARGV;
my $fname = basename("$ann_var");
$fname =~ s/\..*$//;
my @name = split /_/, $fname;

#Calculate total base pairs covered by bed file.
open(INTERVAL, $intervals) or die "Could not open $intervals: $!\n";
my $total_bp = 0;
while(<INTERVAL>) {
	my @int = split /\t/;
	$total_bp += $int[2] - $int[1];
}
print "Total bases in $intervals bed file\t$total_bp\n";

open(IN, $ann_var) or die "Could not open $ann_var: $!\n";
my $header = <IN>;
my $count = 0;
while(<IN>) {
	my @fields = split /\t/;
	$count++ if($fields[199] >= $ncov && $fields[204] >= $tcov && $fields[207] >= $vaf); 
}

print "Mutation burden\t", $count, "\n";
print "Mutation burden per megabase\t";
printf("%.3f", ($count/$total_bp)*1000000);
print "\n";	 
