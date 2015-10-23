#!/usr/local/bin/perl
use warnings;
use strict;
use File::Basename;
use List::Util qw(first);
#####################################################
# Version: v0.1
# Author: Rajesh Patidar rajbtpatidar@gmail.com
# This tool converts the vcf files generated by MuTect/Platypus/Strelka/HaplotypeCaller/UnifiedGenotyper to a human readable as well as annovar comfertable input file.
# This is dependent on annovar provided convertor: "/usr/local/apps/ANNOVAR/current/convert2annovar.pl"
# How to run:
# 		$0 <vcf FILE Name> >File.txt
#
#####################################################
#my $convert2annovar="/usr/local/apps/ANNOVAR/2015-03-22/convert2annovar.pl";
my $CALLER = "caller";
my $input = "$ARGV[0]";
my $idx_normal="0";
my $fname = basename("$input");
my $sname = $fname;
my $LIST  = `grep -m 1 -P "^#CHR" $input |cut -f 10-1000000`;
chop($LIST);
my @NSAMPLES =split("\t", $LIST);
$sname =~ s/\..*$//;
####
# For files generated at Meltzer Lab. Naming convention is Normal_vs_Tumor
if($sname =~ /(.*)_vs_(.*)/){
	$sname = $2;
}
############################
#
# load file as module instead of hard coded path 
# 
#
############################
#`/usr/local/lmod/lmod/lmod/libexec/lmod perl "annovar/2015-03-22"`;
sub module {
	eval `/usr/local/lmod/lmod/lmod/libexec/lmod perl @_`;
	if($@) {
		use Carp;
		confess "module-error: $@\n";
	}
	return 1;
}
module("load annovar/2015-03-22");
my $convert2annovar="`echo \$ANNOVAR_HOME`/convert2annovar.pl";
###########################
#
# Get the caller name from the VCF header
#   and get some tumor index for Mutect
#
############################

open (VAR, $input)or die "Error: cannot read variant file $input: $!\n";
while (<VAR>) {
	chomp;
	if (m/^##/) {
		if($_ =~ /##content=strelka somatic snv calls/i){
			$CALLER = "STRELKA_S";
		}
		elsif($_ =~ /##content=strelka somatic indel calls/){
			$CALLER = "STRELKA_I";
		}
		elsif($_ =~ /MuTect/i){
			$CALLER = "MuTect";
			if($#NSAMPLES eq  1){
				if ($NSAMPLES[0] =~ /$sname/){
					$idx_normal = 1;
				}
				
			}
			else{
				print STDERR "Does not look like a 2 sample MuTect File\n";
				print STDERR "Samples found:\n";
				print STDERR join("\n", "@NSAMPLES")."\n"
			}
		}
		elsif($_ =~ /Platypus/i){
			$CALLER = "Platypus";
		}
		elsif($_ =~ /HaplotypeCaller/i or $_ =~ /VQSR/i or $_ =~ /UnifiedGenotyper/i){ # If VQSR is ran on vcf file the HaplotypeCaller tag get taken out by GATK
			$CALLER = "GATK";
		}
		elsif($_ =~ /freeBayes/){
			$CALLER = "freeBayes";
		}
		elsif($_ =~ /VarScan2/){
			$CALLER = "varscan";
		}
		elsif($_ =~ /##source=bam2mpg/){
			$CALLER = "bam2mpg";
		}
	}
	else{
		last;
	}
	
}
close VAR;

##############################
#
# Process the data and write to screen
#
##############################
print STDERR " It looks like a $CALLER vcf file\n";
if($CALLER eq "varscan"){
	#GT:GQ:DP:RD:AD:FREQ:DP4 0/1:.:30:14:16:53.33%:3,11,0,16
	`perl $convert2annovar --format vcf4old --includeinfo $input 2>/dev/null | cut -f 1-5,11-10000 > /scratch/$sname.vs 2>/scratch/.err_$sname.vs`;
	print "Chr\tStart\tEnd\tRef\tAlt\tQUAL\tFILTER\tINFO\tSampleName\tNormal.GT\tTotalCoverage\tRefCoverage\tVarCoverage\tVariant Allele Freq\tTumor.GT\tTotalCoverage\tRefCoverage\tVarCoverage\tVariant Allele Freq\n";
	open(FH, "/scratch/$sname.vs");
	while (<FH>){
		chomp;
		my @field=split(/\t/,$_);
		my ($chr, $start, $end, $ref, $alt, $qual, $filter, $info, $format, $Normal, $Tumor) = @field;
		print "$chr\t$start\t$end\t$ref\t$alt\t$qual\t$filter\t$info\t$sname";
		foreach ($Normal, $Tumor){
                        my @out = VARSCAN_S($format, $_);
                        print "\t`$out[0]\t$out[1]\t$out[2]\t$out[3]\t$out[4]";
                }
                print "\n";
	}
	close FH;
	`rm -rf /scratch/$sname.vs /scratch/.err_$sname.vs`;

}
elsif($CALLER eq "MuTect"){
	open(FH, $input);
	while(<FH>){
		chomp;
		if($_ =~ /##/){next;}
		my @field=split(/\t/,$_);
		my ($chr, $start, $ID, $ref, $alt, $quality_score, $filter, $info, $format, @sample) = @field;
		my ($end) = ($start);
		if ($chr =~ /^#CHR/i) {         #format specification line
			print "Chr\tStart\tEnd\tRef\tAlt\tQUAL\tFILTER\tINFO\tSampleName\tNormal.GT\tTotalCoverage\tRefCoverage\tVarCoverage\tVariant Allele Freq\tTumor.GT\tTotalCoverage\tRefCoverage\tVarCoverage\tVariant Allele Freq\n";
			next;
        	}
		print "$chr\t$start\t$end\t$ref\t$alt\t$quality_score\t$filter\t$info\t$sname\t";
		my $Normal;
		my $Tumor;
		if ($idx_normal eq '0'){
			$Normal = $sample[0];
			$Tumor = $sample[1];
		}
		elsif($idx_normal eq '1'){
			$Normal = $sample[1];
			$Tumor = $sample[0];
		}
		my @normal = split(":", $Normal);
		my @tumor = split(":", $Tumor);

		my ($idx_GT, $idx_AD, $idx_DP, $idx_FA) = formatMuTect($format);
		$normal[$idx_AD] =~ s/,/\t/g;
		$tumor[$idx_AD] =~ s/,/\t/g;
		print "$normal[$idx_GT]\t$normal[$idx_DP]\t$normal[$idx_AD]\t$normal[$idx_FA]\t";
		print "$tumor[$idx_GT]\t$tumor[$idx_DP]\t$tumor[$idx_AD]\t$tumor[$idx_FA]\n";
	}
	close(FH);
}
elsif($CALLER eq "STRELKA_S"){
	`perl $convert2annovar --format vcf4old --includeinfo $input 2>/dev/null | cut -f 1-5,11-10000 > /scratch/$sname.s 2>/scratch/.err_$sname.s`;
	print "Chr\tStart\tEnd\tRef\tAlt\tQUAL\tFILTER\tINFO\tSampleName\tNormal.GT\tTotalCoverage\tRefCoverage\tVarCoverage\tVariant Allele Freq\tTumor.GT\tTotalCoverage\tRefCoverage\tVarCoverage\tVariant Allele Freq\n";
	open(FH, "/scratch/$sname.s");
	while (<FH>){
		chomp;
		my @field=split(/\t/,$_);
		my ($chr, $start, $end, $ref, $alt, $qual, $filter, $info, $format, $Normal, $Tumor) = @field;
		print "$chr\t$start\t$end\t$ref\t$alt\t$qual\t$filter\t$info\t$sname\t";
		my (@format) = split(":", $format);
		my ($idx_A, $idx_C , $idx_G, $idx_T);
		if( !defined($idx_A) ) {
			$idx_A = first { $format[$_] eq 'AU' } 0..$#format;
		}
		if( !defined($idx_C) ) {
			$idx_C = first { $format[$_] eq 'CU' } 0..$#format;
		}

		if( !defined($idx_G) ) {
			$idx_G = first { $format[$_] eq 'GU' } 0..$#format;
		}

		if( !defined($idx_T) ) {
			$idx_T = first { $format[$_] eq 'TU' } 0..$#format;
		}

		my @normal =  split(":", $Normal);
		my @tumor =  split(":", $Tumor);
		my @refT; 
		my @refN;
		my @altT;
		my @altN;
		if ($ref =~ /A/){
			@refT = split(",", $tumor[$idx_A]);
			@refN = split(",", $normal[$idx_A]);
		}
		elsif($ref =~ /C/){
			@refT = split(",", $tumor[$idx_C]);
			@refN = split(",", $normal[$idx_C]);
		}
		elsif($ref =~ /G/){
			@refT = split(",", $tumor[$idx_G]);
			@refN = split(",", $normal[$idx_G]);
		}
		elsif($ref =~ /T/){
			@refT = split(",", $tumor[$idx_T]);
			@refN = split(",", $normal[$idx_T]);
		}

		if ($alt =~ /A/){
			@altT = split(",", $tumor[$idx_A]);
			@altN = split(",", $normal[$idx_A]);
		}
		elsif($alt =~ /C/){
			@altT = split(",", $tumor[$idx_C]);
			@altN = split(",", $normal[$idx_C]);
		}
		elsif($alt =~ /G/){
			@altT = split(",", $tumor[$idx_G]);
			@altN = split(",", $normal[$idx_G]);
		}
		elsif($alt =~ /T/){
			@altT = split(",", $tumor[$idx_T]);
			@altN = split(",", $normal[$idx_T]);
		}
		my $totalN = $refN[0] + $altN[0];

		my $vafN = 0;
		if( $totalN > 0 ) {
			$vafN  = sprintf ("%.2f", ($altN[0] /$totalN));
		}
		my $totalT = $refT[0] + $altT[0];

		my $vafT = 0;
		if( $totalT > 0 ) {
			$vafT   = sprintf ("%.2f", ($altT[0] /$totalT));
		}
		print "NA\t$totalN\t$refN[0]\t$altN[0]\t$vafN\tNA\t$totalT\t$refT[0]\t$altT[0]\t$vafT\n";
	}
	close FH;
	`rm -rf /scratch/$sname.s /scratch/.err_$sname.s`;
}
elsif($CALLER eq 'STRELKA_I'){
	`perl $convert2annovar --format vcf4old --includeinfo $input 2>/dev/null| cut -f 1-5,11-1000 > /scratch/$sname.i 2>/scratch/.err_$sname.i`;
	print "Chr\tStart\tEnd\tRef\tAlt\tQUAL\tFILTER\tINFO\tSampleName\tNormal.GT\tTotalCoverage\tRefCoverage\tVarCoverage\tVariant Allele Freq\tTumor.GT\tTotalCoverage\tRefCoverage\tVarCoverage\tVariant Allele Freq\n";
	open(FH, "/scratch/$sname.i");
	while (<FH>){
		chomp;
		my @field=split(/\t/,$_);
		my ($chr, $start, $end, $ref, $alt, $qual, $filter, $info, $format, $Normal, $Tumor) = @field;
		print "$chr\t$start\t$end\t$ref\t$alt\t$qual\t$filter\t$info\t$sname\t";
		my (@format) = split(":", $format);
		my ($DPindex, $TIRindex);
		if( !defined($DPindex) ) {
			$DPindex = first { $format[$_] eq 'DP' } 0..$#format;
		}
		if( !defined($TIRindex) ) {
			$TIRindex = first { $format[$_] eq 'TIR' } 0..$#format;
		}

		my @normal =  split(":", $Normal);
		my @tumor =  split(":", $Tumor);

		my $totalN = $normal[$DPindex];
		my @altN = split(",", $normal[$TIRindex]);
		my $refN = $totalN - $altN[0];
		my $vafN =0;
		if($altN[0] >0){
			$vafN = sprintf ("%.2f", ($altN[0] / $totalN));
		}
		my $totalT = $tumor[$DPindex];
		my @altT = split(",", $tumor[$TIRindex]);
		my $refT = $totalT - $altT[0];
		my $vafT =0;
		if($altT[0] >0){
			$vafT = sprintf ("%.2f", ($altT[0] / $totalT));
		}

		print "NA\t$totalN\t$refN\t$altN[0]\t$vafN\tNA\t$totalT\t$refT\t$altT[0]\t$vafT\n";
	}
	close FH;
	`rm -rf /scratch/$sname.i /scratch/.err_$sname.i`;
}
elsif($CALLER eq 'Platypus'){
	`perl $convert2annovar --format vcf4old --includeinfo $input 2>/dev/null| cut -f 1-5,11-10000 > /scratch/$sname.p 2>/scratch/.err_$sname.p`;
        print "Chr\tStart\tEnd\tRef\tAlt\tQUAL\tFILTER\tINFO\tSampleName";
        foreach(@NSAMPLES){
                print "\t$_.GT\tTotalCoverage\tRefCoverage\tVarCoverage\tVariant Allele Freq";
        }
        print "\n";
	open (FH, "/scratch/$sname.p");
	while(<FH>){
		chomp;
		my ($chr, $start, $end, $ref, $alt, $qual, $filter, $info, $format, @samples) = split("\t", $_);
		print "$chr\t$start\t$end\t$ref\t$alt\t$qual\t$filter\t$info\t$sname";
		foreach (@samples){
			my @out = Platypus($format, $_);
			print "\t`$out[0]\t$out[1]\t$out[2]\t$out[3]\t$out[4]";
		}
		print "\n";
		
	}	
	close FH;
	`rm -rf /scratch/$sname.p /scratch/.err_$sname.p`;
}
elsif($CALLER eq 'GATK'){
#	print "perl $convert2annovar --format vcf4old --includeinfo $input 2>/dev/null| cut -f 1-5,11-10000 > /scratch/$sname.g 2>/scratch/.err_$sname.g\n\n";
#	system("perl $convert2annovar --format vcf4old --includeinfo $input 2>/dev/null| cut -f 1-5,11-10000 > /scratch/$sname.g 2>/scratch/.err_$sname.g") == 0 
#		or die "system perl $convert2annovar --format vcf4old --includeinfo $input 2>/dev/null| cut -f 1-5,11-10000 > /scratch/$sname.g 2>/scratch/.err_$sname.g failed: $?";
	`perl $convert2annovar --format vcf4old --includeinfo $input 2>/dev/null| cut -f 1-5,11-10000 > /scratch/$sname.g 2>/scratch/.err_$sname.g`;
	print "Chr\tStart\tEnd\tRef\tAlt\tQUAL\tFILTER\tINFO\tSampleName";
	foreach(@NSAMPLES){
		print "\t$_.GT\tTotalCoverage\tRefCoverage\tVarCoverage\tVariant Allele Freq";
	}
	print "\n";
	open(FH, "/scratch/$sname.g");
	while(<FH>){
		chomp;
		my ($chr, $start, $end, $ref, $alt, $qual, $filter, $info, $format, @samples) = split("\t", $_);
		print "$chr\t$start\t$end\t$ref\t$alt\t$qual\t$filter\t$info\t$sname";
		foreach (@samples){
			my @out = GATK($format, $_);
			print "\t`$out[0]\t$out[1]\t$out[2]\t$out[3]\t$out[4]";
		}
		print "\n";
	}
	close FH;
	`rm -rf /scratch/$sname.g /scratch/.err_$sname.g`;
}
elsif($CALLER eq 'freeBayes'){
	`perl $convert2annovar --format vcf4old --includeinfo $input 2>/dev/null| cut -f 1-5,11-10000 > /scratch/$sname.fb 2>/scratch/.err_$sname.fb`;
	print "Chr\tStart\tEnd\tRef\tAlt\tQUAL\tFILTER\tINFO\tSampleName";
	foreach(@NSAMPLES){
		print "\t$_.GT\tTotalCoverage\tRefCoverage\tVarCoverage\tVariant Allele Freq";
	}
	print "\n";
	open(FH, "/scratch/$sname.fb");
	while(<FH>){
		chomp;
		my ($chr, $start, $end, $ref, $alt, $qual, $filter, $info, $format, @samples) = split("\t", $_);
		print "$chr\t$start\t$end\t$ref\t$alt\t$qual\t$filter\t$info\t$sname";
		foreach (@samples){
			my @out = FREEBAYES($format, $_);
			print "\t`$out[0]\t$out[1]\t$out[2]\t$out[3]\t$out[4]";
		}
		print "\n";
	}
	close FH;
	`rm -rf /scratch/$sname.fb /scratch/.err_$sname.fb`;	

}
elsif($CALLER eq 'bam2mpg'){
	`perl $convert2annovar --format vcf4old --includeinfo $input 2>/dev/null| cut -f 1-5,11-10000 > /scratch/$sname.mpg 2>/scratch/.err_$sname.mpg`;
	print "Chr\tStart\tEnd\tRef\tAlt\tQUAL\tFILTER\tINFO\tSampleName\t$sname.GT\tTotalCoverage\tRefCoverage\tVarCoverage\tVariant Allele Freq\n";
	open(FH, "/scratch/$sname.mpg");
	while(<FH>){
		chomp;
		my ($chr, $start, $end, $ref, $alt, $qual, $filter, $info, $format, $samples) = split("\t", $_);
		if($qual >=10){
			print "$chr\t$start\t$end\t$ref\t$alt\t$qual\t$filter\t$info\t$sname";
			my @out = BAM2MPG($format, $samples);
			print "\t`$out[0]\t$out[1]\t$out[2]\t$out[3]\t$out[4]\n";
		}
	}
	close FH;
	`rm -rf /scratch/$sname.mpg 2>/scratch/.err_$sname.mpg`;
}
else{
	print STDERR "This vcf file is not supproted.\n";
	print STDERR "Can not determine the type of VCF file\n";
	exit $!;
}



########################################
#				       #
#		Subroutines	       #	
#				       #	
########################################
sub VARSCAN_S{
	#GT:GQ:DP:RD:AD:FREQ:DP4 0/1:.:30:14:16:53.33%:3,11,0,16
	my ($form, $sample) = @_;
	my @format =  split(":", $form);
	if($sample =~ /^\.\/\.$/){
                return (0, 0, 0, 0, 0);
        }
	my @arr = split(":", $sample);
	my $vaf = 0;
	my $idx_GT = first { $format[$_] eq 'GT' } 0..$#format;
	my $idx_DP = first { $format[$_] eq 'DP' } 0..$#format;
	my $idx_RD = first { $format[$_] eq 'RD' } 0..$#format;
	my $idx_AD = first { $format[$_] eq 'AD' } 0..$#format;
	my $idx_FREQ = first { $format[$_] eq 'FREQ' } 0..$#format;
	$arr[$idx_FREQ] =~ s/%//g;
	return($arr[$idx_GT], $arr[$idx_DP], $arr[$idx_RD], $arr[$idx_AD], ($arr[$idx_FREQ]/100));
}
sub GATK{
	my ($form, $sample) = @_;
	my @format =  split(":", $form);
	if($sample =~ /^\.\/\.$/){
                return (0, 0, 0, 0, 0);
        }
	my @arr = split(":", $sample);
	my $vaf = 0;
	my $idx_GT = first { $format[$_] eq 'GT' } 0..$#format;
	my $idx_AD = first { $format[$_] eq 'AD' } 0..$#format;
	my $idx_DP = first { $format[$_] eq 'DP' } 0..$#format;
	if(defined $idx_GT and defined $idx_AD and defined $idx_DP){
		my @AD = split(",", $arr[$idx_AD]);
		if($#AD eq '1' and $AD[1] >=1 and $arr[$idx_DP] >=1){
			$vaf = sprintf("%.2f", $AD[1]/$arr[$idx_DP]);
			return($arr[$idx_GT], $arr[$idx_DP], $AD[0], $AD[1], $vaf);			
		}
		else{
			return($arr[$idx_GT], $arr[$idx_DP], $arr[$idx_AD], $arr[$idx_AD], $vaf);
		}
	}
	else{
		return($sample, "NA", "NA", "NA", "NA");
	}
}
sub FREEBAYES{
	my ($form, $sample) = @_;
	if($sample =~ /^\.$/){
		return (0, 0, 0, 0, 0);
	}
	my @format =  split(":", $form);
	my @arr = split(":", $sample);
	my $vaf = 0;
	my $idx_GT = first { $format[$_] eq 'GT' } 0..$#format;
	my $idx_DP = first { $format[$_] eq 'DP' } 0..$#format;
	my $idx_RO = first { $format[$_] eq 'RO' } 0..$#format;
	my $idx_AO = first { $format[$_] eq 'AO' } 0..$#format;
	if(defined $idx_GT and defined $idx_DP and defined $idx_RO and defined $idx_AO and $arr[$idx_AO] !~ /,/ and $arr[$idx_AO] >=1){
		$vaf = sprintf("%.2f", $arr[$idx_AO]/$arr[$idx_DP]);
		return ($arr[$idx_GT], $arr[$idx_DP], $arr[$idx_RO], $arr[$idx_AO], $vaf);
	}
	else{
		return ($arr[$idx_GT], $arr[$idx_DP], $arr[$idx_RO], $arr[$idx_AO], $vaf);
	}
}
sub BAM2MPG{
	my ($form, $sample) = @_;
	if($sample =~ /^\.$/){
		return (0, 0, 0, 0, 0);
	}
	my @format =  split(":", $form);
	my @arr = split(":", $sample);
	my $vaf = 0;
	my $idx_GT = first { $format[$_] eq 'GT' } 0..$#format;
	my $idx_DP = first { $format[$_] eq 'DP' } 0..$#format;
	my $idx_AD = first { $format[$_] eq 'AD' } 0..$#format;
	if(defined $idx_GT and defined $idx_AD and defined $idx_DP){
		my @AD = split(",", $arr[$idx_AD]);
		if($#AD eq '1' and $AD[1] >=1 and $arr[$idx_DP] >=1){
			$vaf = sprintf("%.2f", $AD[1]/$arr[$idx_DP]);
			return($arr[$idx_GT], $arr[$idx_DP], $AD[0], $AD[1], $vaf);
		}
		else{
			return($arr[$idx_GT], $arr[$idx_DP], $arr[$idx_AD], $arr[$idx_AD], $vaf);
		}
	}
	else{
		return($sample, "NA", "NA", "NA", "NA");
	}
}
sub Platypus{
	my ($form, $sample) = @_;
	my @arr = split(":", $sample);
	my @format =  split(":", $form);
	my $idx_GT = first { $format[$_] eq 'GT' } 0..$#format;
	my $idx_NR = first { $format[$_] eq 'NR' } 0..$#format;
	my $idx_NV = first { $format[$_] eq 'NV' } 0..$#format;
	my $vaf = 0;
	my $total =0;
	if($arr[$idx_NR] !~ /,/ and $arr[$idx_NV] !~ /,/){
		$total = $arr[$idx_NR] + $arr[$idx_NV];
		if($arr[$idx_NV] >0){
			$vaf =sprintf ("%.2f", ($arr[$idx_NV]/$total));
		}
	}
	return($arr[$idx_GT] ,$total, $arr[$idx_NR], $arr[$idx_NV], $vaf);
}
# Sub for getting index
sub formatMuTect{
	my ($FORMAT) = @_;
	my ($GT, $AD, $DP, $FA);
	my @format =  split(":", $FORMAT);
	if( !defined($GT) ) {
		$GT = first { $format[$_] eq 'GT' } 0..$#format;
	}
	if( !defined($AD) ) {
		$AD = first { $format[$_] eq 'AD' } 0..$#format;
	}
	if( !defined($DP) ) {
		$DP = first { $format[$_] eq 'DP' } 0..$#format;
	}
	if( !defined($FA) ) {
		$FA = first { $format[$_] eq 'FA' } 0..$#format;
	}
	return($GT, $AD, $DP, $FA);

}
