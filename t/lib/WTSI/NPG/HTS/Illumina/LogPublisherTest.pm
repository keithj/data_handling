package WTSI::NPG::HTS::Illumina::LogPublisherTest;

use strict;
use warnings;

use Carp;
use English qw[-no_match_vars];
use Log::Log4perl;
use Test::More;
use File::Temp qw(tempdir);
use File::Copy::Recursive qw(dircopy);
use File::Spec;
use Readonly;

use base qw[WTSI::NPG::HTS::Test];

use WTSI::NPG::iRODS;
use WTSI::NPG::iRODS::Metadata qw[$ID_RUN];
use WTSI::NPG::HTS::Illumina::LogPublisher;

Log::Log4perl::init('./etc/log4perl_tests.conf');

my $pid          = $PID;
my $test_counter = 0;
my $data_path    = 't/data/log_publisher';

my $irods_tmp_coll;

sub setup_test : Test(setup) {
  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);

  $irods_tmp_coll =
    $irods->add_collection("RunPublisherTest.$pid.$test_counter");
  $test_counter++;
}

sub teardown_test : Test(teardown) {
  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);
  $irods->remove_collection($irods_tmp_coll);
}

sub publish_logs : Test(12) {
  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);
  my $runfolder_path1 = "$data_path/100818_IL32_10371";
  my $pub1 = WTSI::NPG::HTS::Illumina::LogPublisher->new
    (irods           => $irods,
     runfolder_path  => $runfolder_path1,
     id_run          => 999,
     dest_collection => "$irods_tmp_coll/publish_logs_given_id_run");

  my $log_archive1 = $pub1->publish_logs;
  ok($log_archive1, 'Log archive created given an id_run');

  my $obj1 = WTSI::NPG::HTS::DataObject->new($irods, $log_archive1);
  is_deeply($obj1->get_avu($ID_RUN),
            {attribute => $ID_RUN,
             value     => 999}, "$ID_RUN metadata is present");

  # Test inferring of the id_run by using the fake runfolder used to
  # test the RunPublisher
  my $runfolder_path2 =
    "t/data/illumina/sequence/150910_HS40_17550_A_C75BCANXX";

  # The tracking database handle must be specified, otherwise when
  # the tracking schema file exists in .npg folder it tries to retrieve
  # the db credentials from it and connect to the database defined there.
  # By setting it to 'undef', the code avoids the database route.
  my $pub2 = WTSI::NPG::HTS::Illumina::LogPublisher->new
    (irods                => $irods,
     runfolder_path       => $runfolder_path2,
     npg_tracking_schema  => undef,
     dest_collection      => "$irods_tmp_coll/publish_logs_inferred_id_run");

  my $log_archive2 = $pub2->publish_logs;
  ok($log_archive2, 'Log archive created given a runfolder path');

  my $obj2 = WTSI::NPG::HTS::DataObject->new($irods, $log_archive2);
  is_deeply($obj2->get_avu($ID_RUN),
            {attribute => $ID_RUN,
             value     => 17550}, "Inferred $ID_RUN metadata is present");

  # Test that the pipeline central, postqc and product release logs are archived together with the others
  Readonly::Scalar my $LOGS_COUNT => 43;
  my @log_files =
    ('_software_npg_20241107_bin_npg_pipeline_central_17550_20241101-132705-1566962201.definitions.json',
      '_software_npg_20241107_bin_npg_pipeline_post_qc_review_17550_20241104-124525-1544617117.definitions.json',
      '_software_npg_20241107_bin_npg_pipeline_central_17550_20241101-132705-1566962201.log',
      '_software_npg_20241107_bin_npg_pipeline_post_qc_review_17550_20241104-124525-1544617117.log',
      'product_release_20241101-132705-1247165951.yml',
      'product_release_20241104-124525-1500421497.yml');
  my $temp_dir = tempdir(CLEANUP => 1);
  my $rf_name = '151211_HX3_18448_B_HHH55CCXX';
  my $runfolder_path3 = File::Spec->catfile($temp_dir, $rf_name);
  my $bam_basecall_folder3 = 
    File::Spec->catfile( $runfolder_path3, 'Data/Intensities/BAM_basecalls_20151214-085833');
  dircopy("t/data/illumina/sequence/$rf_name", $runfolder_path3);
  for my $log (@log_files) {
    open my $handle, '>', File::Spec->catfile($bam_basecall_folder3, $log)
      or die "error while creating test logs $log";
    close $handle or die "error while closing test logs $log";
  }
  my $pub3 = WTSI::NPG::HTS::Illumina::LogPublisher->new
    (irods           => $irods,
     runfolder_path  => $runfolder_path3,
     id_run          => 18448,
     dest_collection => "$irods_tmp_coll/publish_logs_pipecentral_qcpost");

  my $log_archive3 = $pub3->publish_logs;
  ok($log_archive3, 'Log archive with pipeline central and post qc logs created');

  my $cmd_count_out = `iget $log_archive3 - | tar tJ | wc -l`;
  ok(int($cmd_count_out) == $LOGS_COUNT, 'Correct number of files in the log archive');

  my $cmd_list_out = `iget $log_archive3 - | tar tJ`;
  for my $log (@log_files) {
    ok(grep(/$log/, $cmd_list_out), "$log in archive file");
  }
}

1;
