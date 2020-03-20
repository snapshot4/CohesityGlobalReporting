#!/usr/bin/perl

#Author: Brian Doyle
#Name: clusterList.pm
#Description: This is meant to be a secured file containing the cluster information.

package clusterInfo;

sub clusterList {
  my @clusters = (
    {
      'cluster'		=>	'',
      'username'	=>	'',
      'password'	=>	'',
      'domain'		=>	'',
      'databaseName'	=>	'',
      'region'		=>	'',
    },
  );
}

1;
