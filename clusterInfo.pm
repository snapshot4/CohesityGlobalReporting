#!/usr/bin/perl

#Author: Brian Doyle
#Name: clusterList.pm
#Description: This is meant to be a secured file containing the cluster information.

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
