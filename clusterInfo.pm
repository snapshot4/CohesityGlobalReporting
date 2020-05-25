#!/usr/bin/perl

#Author: Brian Doyle
#Name: clusterList.pm
#Description: This is meant to be a secured file containing the cluster information.
#Instructions: Create a readonly user in the Cohesity UI and use that in the below configurations.  
# Next run [iris_cli custom_reporting db] at the Cohesity command line, this will provide the database name.

package clusterInfo;

sub clusterList {
  my @clusters = (
    {
      'cluster'		=>	'myclustername1.cluster.com',
      'username'	=>	'readonly',
      'password'	=>	'somepassword',
      'domain'		=>	'local',
      'databaseName'	=>	'postgres',
      'region'		=>	'Prod',
    },
    {
      'cluster'		=>	'myclustername2.cluster.com',
      'username'	=>	'readonly',
      'password'	=>	'somepassword',
      'domain'		=>	'local',
      'databaseName'	=>	'postgres',
      'region'		=>	'DR',
    },
  );
}

1;
