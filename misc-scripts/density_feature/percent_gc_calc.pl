#!/usr/bin/perl -w

#
# Ignore file anme this should calculate the gene count for a chromosome (X)
#


use strict;

#use dbi;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::DBSQL::SliceAdaptor;
use Bio::EnsEMBL::DBSQL::DensityFeatureAdaptor;
use Bio::EnsEMBL::DBSQL::DensityTypeAdaptor;
use Bio::EnsEMBL::Slice;
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DensityType;
use Bio::EnsEMBL::DensityFeature;

my $host = '127.0.0.1';
my $user = 'ensadmin';
my $pass = 'ensembl';
my $dbname = 'homo_sapiens_core_20_34';
my $port = '5050';

my $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $host,
					    -user => $user,
					    -port => $port,
					    -pass => $pass,
					    -dbname => $dbname);



my $block_size = 1e6;


#
# Get the adaptors needed;
#

my $slice_adaptor = $db->get_SliceAdaptor();
my $dfa = $db->get_DensityFeatureAdaptor();
my $dta = $db->get_DensityTypeAdaptor();
my $aa  = $db->get_AnalysisAdaptor();


#
# Create new analysis object for density calculation.
#

my $analysis = new Bio::EnsEMBL::Analysis (-program     => "percent_gc_calc.pl",
					   -database    => "ensembl",
					   -gff_source  => "percent_gc_calc.pl",
					   -gff_feature => "density",
					   -logic_name  => "PercentGC");
 
$aa->store($analysis);

print "New analysis : ".$analysis->dbID." at ".$analysis->created."\n";

#
# Create new density type.
#

my $dt = Bio::EnsEMBL::DensityType->new(-analysis   => $analysis,
					-block_size => $block_size,
					-value_type => 'ratio');

$dta->store($dt);

print "New density type : ".$dt->dbID."\n";

foreach my $chrom (qw(X Y)){
  print "creating density feature for chromosome $chrom with block size of $block_size\n";

  my $slice = $slice_adaptor->fetch_by_region('chromosome',$chrom);
  
  my $start = $slice->start();
  my $end = ($start + $block_size)-1;
  my $term = $slice->start+$slice->length;
  
  my @density_features=();
  while($start < $term){
    my $sub_slice = $slice_adaptor->fetch_by_region('chromosome',$chrom,$start,$end);

    my $gc = $sub_slice->get_base_count()->{'%gc'};
    print STDERR $start."\n";
    push @density_features, Bio::EnsEMBL::DensityFeature->new(-seq_region    => $slice,
							     -start         => $start,
							     -end           => $end,
							     -density_type  => $dt,
							     -density_value => $gc);

    $start = $end+1;
    $end   = ($start + $block_size)-1;
  }
  $dfa->store(@density_features);
  print scalar @density_features;
  print_features(\@density_features);
}







#
# helper to draw an ascii representation of the density features
#
sub print_features {
  my $features = shift;

  return if(!@$features);

  my $sum = 0;
  my $length = 0;
#  my $type = $features->[0]->{'density_type'}->value_type();

  print("\n");
  my $max=0;
  foreach my $f (@$features) {
    if($f->density_value() > $max){
      $max=$f->density_value();
    }
  }
  foreach my $f (@$features) {
    my $i=1;
    for(; $i< ($f->density_value()/$max)*40; $i++){
      print "*";
    }
    for(my $j=$i;$j<40;$j++){
      print " ";
    }
    print "  ".$f->density_value()."\t".$f->start()."\n";
  }
#  my $avg = undef;
#  $avg = $sum/$length if($length < 0);
#  print("Sum=$sum, Length=$length, Avg/Base=$sum");
}




  


