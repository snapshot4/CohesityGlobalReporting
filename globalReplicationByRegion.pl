#!/usr/bin/perl
our $version=1.0.1;

# Author: Brian Doyle
# Name: globalSummaryByRegion.pl
# Description: This script was written for a Cohesity cluster to give better visibility into a large multisite deployment.  #
# 1.0.0 - Initial program creation showing num of success, failures, active and success rate.

# Modules
use strict;
use DBI; 
use REST::Client;
use JSON;
use Time::HiRes;
use clusterInfo;

# Global Variables
my $display=1; #(0-Standard Display, 1-HTML)
my $debug=0; #(0-No log messages, 1-Info messages, 2-Debug messages)
my $hoursAgo=96;
my %regions;
my $title="Global Cohesity Replication Report by Region";
my $regionFilter="*"; #Set to * (All) to do all regions, otherwise comma seperate the regions
my @clusters=clusterInfo::clusterList();

#Set Environment Variable to no verify certs
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;


# Sub Routines
sub getToken {
  foreach my $href (@clusters){
    my $cluster=$href->{'cluster'};
    my $username=$href->{'username'};
    my $password=$href->{'password'};
    my $domain=$href->{'domain'};
    printf "Getting Token for: $cluster\n" if ($debug>=1);
    my $client=REST::Client->new();
    $client->setHost("https://$cluster"); 
    $client->addHeader("Accept", "application/json", "Content-Type", "application/json");
    $client->POST('/irisservices/api/v1/public/accessTokens','{"domain" : "'.$domain.'","username" : "'.$username.'","password" : "'.$password.'"}');
    die $client->responseContent() if( $client->responseCode() >= 300 );
    my $response=decode_json($client->responseContent());
    printf "ResponseCode: ".$client->responseCode()."\n" if ($debug>=2);
    $href->{'tokenType'} = $response->{'tokenType'};
    $href->{'token'} = $response->{'accessToken'};
  }
}

sub getDbInfo {
  foreach my $href (@clusters){
    my $cluster=$href->{'cluster'};
    printf "Getting DB Info for Cluster: $cluster\n" if ($debug>=1);
    my $client=REST::Client->new();
    $client->setHost("https://$cluster"); 
    $client->addHeader("Accept", "application/json");
    $client->addHeader("Authorization", "$href->{'tokenType'} $href->{'token'}"); #Authorize request
    $client->GET('/irisservices/api/v1/public/postgres');
    my $response=decode_json($client->responseContent());
    $href->{'nodeId'}="$response->[0]->{'nodeId'}";
    $href->{'nodeIp'}="$response->[0]->{'nodeIp'}";
    $href->{'port'}="$response->[0]->{'port'}";
    $href->{'defaultUsername'}="$response->[0]->{'defaultUsername'}";
    $href->{'defaultPassword'}="$response->[0]->{'defaultPassword'}";
  }
}

sub printHeader {
  printf "\n                      $_[0] Report                     \n" if ($display==0);
  printf "Cluster\t\tTotal\tSuccess\tFailed\tActive\tDataRead\tLogicalTx\tPhysicalTx\n" if ($display==0);
  printf "<TABLE BORDER=1 ALIGN=center><TR BGCOLOR=lightgreen><TD ALIGN=center colspan='8'>$_[0] Report</TD></TR>" if ($display==1);
  printf "<TR BGCOLOR=lightgreen><TD>Cohesity Cluster</TD><TD>Total</TD><TD>Success</TD><TD>Failed</TD><TD>Active</TD><TD>Data Read(GB)</TD><TD>Logical Tx(GB)</TD><TD>Physical Tx(GB)</TD></TR>" if ($display==1);
}

sub gatherData{
  print "Connecting to Database $_[1]\n" if ($debug>=2);
  my $hoursAgoUsecs=($hoursAgo*3600000000);
  my $curTime=time*1000*1000;
  print "$curTime\n" if ($debug>=2);
  my $startTimeUsecs=($curTime-$hoursAgoUsecs);
  print "$startTimeUsecs\n" if ($debug>=2);
  my ($active,$success,$failed,$size,$delta,$cluster);
  foreach my $href (@clusters){
    my $cluster=$href->{'cluster'};
    my $dbh = DBI -> connect("dbi:Pg:dbname=$href->{'databaseName'};host=$href->{'nodeIp'};port=$href->{'port'}",$href->{'defaultUsername'},$href->{'defaultPassword'}) or die $DBI::errstr;
    #while(my @rows=$sth->fetchrow_array){
      my $sth=$dbh->prepare("SELECT schema_version FROM reporting.schemaflag");
      $sth->execute();
      my $schemaVersion=$sth->fetch()->[0];
      print "Schema Version: $schemaVersion\n" if($debug>=2);
      if($schemaVersion==3){
        $active="SELECT COUNT(status) FROM reporting.protection_job_run_replications WHERE start_time_usecs >= $startTimeUsecs AND status = 2";
        $success="SELECT COUNT(status) FROM reporting.protection_job_run_replications WHERE start_time_usecs >= $startTimeUsecs AND status = 1";
        $failed="SELECT COUNT(status) FROM reporting.protection_job_run_replications WHERE start_time_usecs >= $startTimeUsecs AND status = 3";
        $size="SELECT SUM(logical_size_bytes_transferred), SUM(physical_size_bytes_transferred) FROM reporting.protection_job_run_replications WHERE start_time_usecs >= $startTimeUsecs";
        $delta="SELECT SUM(source_delta_size_bytes) FROM reporting.protection_job_runs WHERE start_time_usecs >= $startTimeUsecs";
        $cluster="SELECT cluster_name as COL2 FROM reporting.cluster";
      } else {
        $active="SELECT COUNT(status) FROM reporting.protection_job_run_replications WHERE start_time_usecs >= $startTimeUsecs AND status = 1";
        $success="SELECT COUNT(status) FROM reporting.protection_job_run_replications WHERE start_time_usecs >= $startTimeUsecs AND status = 4";
        $failed="SELECT COUNT(status) FROM reporting.protection_job_run_replications WHERE start_time_usecs >= $startTimeUsecs AND status = 6";
        $size="SELECT SUM(logical_size_bytes_transferred) as COL1, SUM(physical_size_bytes_transferred) as COL2 FROM reporting.protection_job_run_replications WHERE start_time_usecs >= $startTimeUsecs";
        $delta="SELECT SUM(source_delta_size_bytes) FROM reporting.protection_job_runs WHERE start_time_usecs >= $startTimeUsecs";
        $cluster="SELECT cluster_name FROM reporting.cluster";
      }
      $sth = $dbh->prepare($active);
      $sth->execute() or die DBI::errstr;
      my $activeJobs=$sth->fetch()->[0];
      if($activeJobs==""){ $activeJobs=0; }
      $sth->finish();
      $sth = $dbh->prepare($success);
      $sth->execute() or die DBI::errstr;
      my $successJobs=$sth->fetch()->[0];
      if($successJobs==""){ $successJobs=0; }
      $sth->finish();
      $sth = $dbh->prepare($failed);
      $sth->execute() or die DBI::errstr;
      my $failedJobs=$sth->fetch()->[0];
      if($failedJobs==""){ $failedJobs=0; }
      $sth->finish();
      $sth = $dbh->prepare($size);
      $sth->execute() or die DBI::errstr;
      my ($logicalSize,$physicalSize)=(0,0);
      while(my @rows=$sth->fetchrow_array){
        $logicalSize=$rows[0];
        $physicalSize=$rows[1];
        if($logicalSize==""){ $logicalSize=0; }
        if($physicalSize==""){ $physicalSize=0; }
      }
      $sth->finish();
      $sth = $dbh->prepare($delta);
      $sth->execute() or die DBI::errstr;
      my $deltaSize=$sth->fetch()->[0];
      if($deltaSize==""){ $deltaSize=0; }
      $sth->finish();
      $sth = $dbh->prepare($cluster);
      $sth->execute() or die DBI::errstr;
      my $cluster=$sth->fetch()->[0];
      $sth->finish();
      my $totalJobs=$failedJobs+$successJobs;
      $regions{$href->{'region'}}{$cluster}="$totalJobs,$successJobs,$failedJobs,$activeJobs,$deltaSize,$logicalSize,$physicalSize";
      #print "ROW=$href->{'region'}\t$rows[3]\t\t$rows[0]\t$rows[1]\t$activeJobs\t$rows[2]\t$rows[4]\n" if ($debug>=2);
    #}
    $dbh->disconnect();
  }
}

sub printReport {
  printf "<HTML><HEAD></HEAD><BODY><Center><H1>$title</H1></CENTER>" if ($display==1);
  foreach my $region (sort keys %regions){
    if($regionFilter eq "*" || index($regionFilter, $region) != -1){
      printHeader($region);
      foreach my $clusterName (sort keys %{$regions{$region}}){
        print "TEST: $region $clusterName $regions{$region}{$clusterName}\n" if ($debug>=2); 
        my @cols=split(',', $regions{$region}{$clusterName});
        my $delta=int($cols[4]/1024/1024/1024);
        my $logical=int($cols[5]/1024/1024/1024);
        my $physical=int($cols[6]/1024/1024/1024);
        $delta=reverse($delta);
        $logical=reverse($logical);
        $physical=reverse($physical);
        $delta=~s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
        $logical=~s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
        $physical=~s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
        $delta=reverse($delta);
        $logical=reverse($logical);
        $physical=reverse($physical);
        printf "$clusterName\t\t$cols[0]\t$cols[1]\t$cols[2]\t$cols[3]\t$cols[4]\t\t$cols[5]\t$cols[6]\n" if ($display==0);
        printf "<TR><TD>$clusterName</TD><TD ALIGN=center>$cols[0]</TD><TD ALIGN=center>$cols[1]</TD><TD ALIGN=center>$cols[2]</TD><TD ALIGN=center>$cols[3]</TD><TD ALIGN=right>$delta</TD><TD ALIGN=right>$logical</TD><TD ALIGN=right>$physical</TD></TR>"if ($display==1);
      }
    }  
    printf "</TABLE><br/>\n" if ($display==1);
  } 
  printf "</BODY></HTML>\n" if ($display==1);
}



# Main
getToken();
getDbInfo();
gatherData();
printReport();
