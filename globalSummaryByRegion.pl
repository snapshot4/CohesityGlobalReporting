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
my $hoursAgo=24;
my %regions;
my $title="Global Cohesity Report by Region";
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
  printf "Cluster\t\tTotal\tSuccess\tFailed\tActive\tSuccess Rate\tSize(GB)\n" if ($display==0);
  printf "<TABLE BORDER=1 ALIGN=center><TR BGCOLOR=lightgreen><TD ALIGN=center colspan='7'>$_[0] Report</TD></TR>" if ($display==1);
  printf "<TR BGCOLOR=lightgreen><TD>Cohesity Cluster</TD><TD>Total</TD><TD>Success</TD><TD>Failed</TD><TD>Active</TD><TD>Success Rate</TD><TD>Size(GB)</TD></TR>" if ($display==1);
}

sub gatherData{
  print "Connecting to Database $_[1]\n" if ($debug>=2);
  my $hoursAgoUsecs=($hoursAgo*3600000000);
  my $curTime=time*1000*1000;
  print "$curTime\n" if ($debug>=2);
  my $startTimeUsecs=($curTime-$hoursAgoUsecs);
  print "$startTimeUsecs\n" if ($debug>=2);
  foreach my $href (@clusters){
    my $dbh = DBI -> connect("dbi:Pg:dbname=$href->{'databaseName'};host=$href->{'nodeIp'};port=$href->{'port'}",$href->{'defaultUsername'},$href->{'defaultPassword'}) or die $DBI::errstr;
    # Gather Total Jobs Information
    my $sql = "SELECT SUM(total_num_entities), SUM(success_num_entities), SUM(failure_num_entities), cluster_name, SUM(source_delta_size_bytes)
               FROM reporting.protection_job_runs, reporting.protection_jobs, reporting.cluster
               WHERE start_time_usecs >= $startTimeUsecs 
               AND reporting.protection_jobs.job_id=reporting.protection_job_runs.job_id 
               AND reporting.cluster.cluster_id=reporting.protection_job_runs.cluster_id
               GROUP BY cluster_name
               ORDER BY cluster_name
              ";
    my $sth = $dbh->prepare($sql);
    print "Executing Query\n" if ($debug>=2);
    $sth->execute() or die DBI::errstr;
    while(my @rows=$sth->fetchrow_array){
      my $sth=$dbh->prepare("SELECT schema_version FROM reporting.schemaflag");
      $sth->execute();
      my $schemaVersion=$sth->fetch()->[0];
      print "Schema Version: $schemaVersion\n" if($debug>=2);
      if($schemaVersion==3){
        $sql="SELECT COUNT(status) FROM reporting.protection_job_runs WHERE start_time_usecs >= $startTimeUsecs AND status = 2";
      } else {
        $sql="SELECT COUNT(status) FROM reporting.protection_job_runs WHERE start_time_usecs >= $startTimeUsecs AND status = 1";
      }
      $sth = $dbh->prepare($sql);
      $sth->execute() or die DBI::errstr;
      my $activeJobs=$sth->fetch()->[0];
      $sth->finish();
      $regions{$href->{'region'}}{$rows[3]}="$rows[0],$rows[1],$rows[2],$activeJobs,$rows[4]";
      print "ROW=$href->{'region'}\t$href->{'cluster'}\t\t$rows[0]\t$rows[1]\t$activeJobs\t$rows[2]\t$rows[4]\n" if ($debug>=2);
    }
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
        my $successRate=(($cols[1]/$cols[0])*100);
        my $size=int($cols[4]/1024/1024/1024);
        $size=~s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
        printf "$clusterName\t\t$cols[0]\t$cols[1]\t$cols[2]\t$cols[3]\t%2.1f%,\t\t$cols[4]\n",$successRate if ($display==0);
        printf "<TR><TD>$clusterName</TD><TD ALIGN=center>$cols[0]</TD><TD ALIGN=center>$cols[1]</TD><TD ALIGN=center>$cols[2]</TD><TD ALIGN=center>$cols[3]</TD><TD ALIGN=right>%2.1f%</TD><TD ALIGN=right>$size</TD></TR>",$successRate if ($display==1);
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
