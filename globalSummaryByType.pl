#!/usr/bin/perl
our $version=1.0.0;

# Author: Brian Doyle
# Name: globalSummaryBySite.pl
# Description: This script was written for a Cohesity cluster to give better visibility into a large multisite deployment.  #
# 1.0.0 - Initial program creation showing num of success, failures, active and success rate.

# Modules
use strict;
use DBI; 
use REST::Client;
use JSON;
use Time::HiRes;

# Global Variables
my $display=1; #(0-Standard Display, 1-HTML)
my $debug=0; #(0-No log messages, 1-Info messages, 2-Debug messages)
my $hoursAgo=24;
my %types;
my $title="Global Cohesity Report by JobType";
my @clusters = (
  {
    'cluster'		=>	'', 
    'username'		=>	'',
    'password'		=>	'',
    'domain'		=>	'LOCAL',
    'databaseName'	=>	'postgres',
  },
);

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
  printf "Cluster\t\tTotal\tSuccess\tFailed\tSuccess Rate\n" if ($display==0);
  printf "<TABLE BORDER=1 ALIGN=center><TR BGCOLOR=lightgreen><TD ALIGN=center colspan='5'>$_[0] Report</TD></TR>" if ($display==1);
  printf "<TR BGCOLOR=lightgreen><TD>Cohesity Cluster</TD><TD>Total</TD><TD>Success</TD><TD>Failed</TD><TD>Success Rate</TD></TR>" if ($display==1);
}

sub dbConnect {
  my $hoursAgoUsecs=($hoursAgo*3600000000);
  my $curTime=time*1000*1000;
  print "$curTime\n" if ($debug>=2);
  my $startTimeUsecs=($curTime-$hoursAgoUsecs);
  print "$startTimeUsecs\n" if ($debug>=2);
  foreach my $href (@clusters){
    print "Connecting to Database $href->{'databaseName'}\n" if ($debug>=2);
    my $dbh = DBI -> connect("dbi:Pg:dbname=$href->{'databaseName'};host=$href->{'nodeIp'};port=$href->{'port'}",$href->{'defaultUsername'},$href->{'defaultPassword'}) or die $DBI::errstr;
    my $sql = "SELECT SUM(total_num_entities), SUM(success_num_entities), SUM(failure_num_entities), env_name, cluster_name
               FROM reporting.protection_job_runs, reporting.protection_jobs, reporting.environment_types, reporting.cluster
               WHERE start_time_usecs >= $startTimeUsecs 
               AND reporting.protection_jobs.job_id=reporting.protection_job_runs.job_id 
               AND reporting.cluster.cluster_id=reporting.protection_job_runs.cluster_id
               AND reporting.protection_jobs.source_env_type=reporting.environment_types.env_id
               GROUP BY env_name,cluster_name
               ORDER BY cluster_name
              ";
    my $sth = $dbh->prepare($sql);
    print "Executing Query\n" if ($debug>=2);
    $sth->execute() or die DBI::errstr;
    while (my @row=$sth->fetchrow_array){
        $types{$row[3]}{$row[4]}="$row[0],$row[1],$row[2]";
        #printf "$row[4]\t$row[0]\t$row[1]\t$row[2]\t\t$row[3]\t$row[5]\n" if ($display==0);
    }
    $sth->finish();
  }
}

sub printReport {
  printf "<HTML><HEAD></HEAD><BODY><Center><H1>$title</H1></CENTER>" if ($display==1);
  foreach my $type (sort keys %types){
    printHeader($type);
    foreach my $clusterName (sort keys %{$types{$type}}){
      print "TEST: $type $clusterName $types{$type}{$clusterName}\n" if ($debug>=2); 
      my @cols=split(',', $types{$type}{$clusterName});
      my $successRate=(($cols[1]/$cols[0])*100);
      printf "$clusterName\t\t$cols[0]\t$cols[1]\t$cols[2]\t%2.1f%\n",$successRate if ($display==0);
      printf "<TR><TD>$clusterName</TD><TD ALIGN=center>$cols[0]</TD><TD ALIGN=center>$cols[1]</TD><TD ALIGN=center>$cols[2]</TD><TD ALIGN=right>%2.1f%</TD></TR>",$successRate if ($display==1);
    }  
    printf "</TABLE><br/>\n" if ($display==1);
  } 
  printf "</BODY></HTML>\n" if ($display==1);
}



# Main
getToken();
getDbInfo();
dbConnect();
printReport();
