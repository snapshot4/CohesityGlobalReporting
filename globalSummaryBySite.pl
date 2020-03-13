#!/usr/bin/perl
our $version=1.0.2;

# Author: Brian Doyle
# Name: globalSummaryBySite.pl
# Description: This script was written for a Cohesity cluster to give better visibility into a large multisite deployment.  #
# 1.0.0 - Initial program creation showing num of success, failures, active and success rate.
# 1.0.1 - Added debug to assist if problems arise in script.
# 1.0.2 - Added display variable to output to display as tab seperated or in HTML format.

# Modules
use strict;
use DBI;
use REST::Client;
use JSON;
use Time::HiRes;

# Global Variables
my $display=0; #(0-Standard Display, 1-HTML)
my $debug=0; #(0-No log messages, 1-Info messages, 2-Debug messages)
my $hoursAgo=24;
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

sub dbConnect {
  my $hoursAgoUsecs=($hoursAgo*3600000000);
  my $curTime=time*1000*1000;
  print "$curTime\n" if ($debug>=2);
  my $startTimeUsecs=($curTime-$hoursAgoUsecs);
  print "$startTimeUsecs\n" if ($debug>=2);
  printf "Cluster\t\tTotal\tSuccess\tFailed\tSuccess Rate\n" if ($display==0);
  printf "<HTML><HEAD></HEAD><BODY><TABLE BORDER=1 ALIGN=center><TR BGCOLOR=lightgreen><TD>Cohesity Cluster</TD><TD>Total</TD><TD>Success</TD><TD>Failed</TD><TD>Success Rate</TD></TR>" if ($display==1);
  foreach my $href (@clusters){
    print "Connecting to Database $href->{'databaseName'}\n" if ($debug>=2);
    my $dbh = DBI -> connect("dbi:Pg:dbname=$href->{'databaseName'};host=$href->{'nodeIp'};port=$href->{'port'}",$href->{'defaultUsername'},$href->{'defaultPassword'}) or die $DBI::errstr;
    my $sql = "SELECT SUM(total_num_entities), SUM(success_num_entities), SUM(failure_num_entities) FROM reporting.protection_job_runs WHERE start_time_usecs >= $startTimeUsecs";
    my $sth = $dbh->prepare($sql);
    print "Executing Query\n" if ($debug>=2);
    $sth->execute() or die DBI::errstr;
    while (my @row=$sth->fetchrow_array){
      my $successRate=(($row[1]/$row[0])*100);
      printf "$href->{'cluster'}\t$row[0]\t$row[1]\t$row[2]\t%2.1f%\n",$successRate if ($display==0);
      printf "<TR><TD>$href->{'cluster'}</TD><TD ALIGN=center>$row[0]</TD><TD ALIGN=center>$row[1]</TD><TD ALIGN=center>$row[2]</TD><TD ALIGN=right>%2.1f%</TD></TR>",$successRate if ($display==1);
    }
    $sth->finish();
  }
  printf "</TABLE></BODY></HTML>\n" if ($display==1);
}




# Main
getToken();
getDbInfo();
dbConnect();
