#!/usr/bin/perl
#
#######################################################
###  Calomel.org web_access_sentry.pl  BEGIN
#######################################################

use Time::Local;

my %mon = qw/Jan 0 Feb 1 Mar 2 Apr 3 May  4 Jun  5
             Jul 6 Aug 7 Sep 8 Oct 9 Nov 10 Dec 11/;

# USER CONFIGURABLE OPTIONS - Web log target
my $log = '/var/log/web_server/access_log';

# USER CONFIGURABLE OPTIONS - email sender and recipients
my $return_addr = 'web_admin@your_hostname.com';
my $recipients = join ',',qw/
                 web_support@your_hostname.com
                 web_developers@your_hostname.com
                 /;
my $sendmail = "/usr/lib/sendmail -f$return_addr -t";

# USER CONFIGURABLE OPTIONS - Thresholds
# Choose some thresholds designed to separate the
# miscreants from the well-behaved web users.
my $max_requests_per_host = 2000;
my $max_bytes_per_host = 2_000_000_000;
my $max_errors_per_host = 200;
my $max_duplicate_urls_per_host = 120;

my %dns;

open LOG,$log or die "Could not open $log ($!)";

my $inode = (stat LOG)[1];

my @rec = ();
my $most_recent = $^T;

for(;;){        # Keep doing this until someone kills this process.

# USER CONFIGURABLE OPTIONS - Amount of time to watch the logs
  my $start = time - 600;               # Look at the past 10 minutes.

  @rec = grep $_->[0] >= $start, @rec;  # Remove any previously read log
                                        # records that are more than 10
                                        # minutes old.

  # Read and parse the next batch of access log records.
  while(<LOG>){

    my ($host, $ident_user, $auth_user, $day,$mon,$year, $hour,$min,$sec,
    $time_zone, $method, $url, $protocol, $status,
    $bytes, $referer, $agent) =
    /                 # regexp begins
    ^               # beginning-of-string anchor
    (\S+)           # assigned to $host
    \               # literal space
    (\S+)           # assigned to $ident_user
    \               # literal space
    (\S+)           # assigned to $auth_user
    \               # literal space
    \[              # literal left bracket
    (\d\d)          # assigned to $day
    \/              # literal solidus
    ([A-Z][a-z]{2}) # assigned to $mon
    \/              # literal solidus
    (\d{4})         # assigned to $year
    :               # literal colon
    (\d\d)          # assigned to $hour
    :               # literal colon
    (\d\d)          # assigned to $min
    :               # literal colon
    (\d\d)          # assigned to $sec
    \               # literal space
    ([^\]]+)        # assigned to $time_zone
    \]\ "           # literal string '] "'
    (\S+)           # assigned to $method
    \               # literal space
    (.+?)           # assigned to $url
    \               # literal space
    (\S+)           # assigned to $protocol
    "\              # literal string '" '
    (\S+)           # assigned to $status
    \               # literal space
    (\S+)           # assigned to $bytes
    \               # literal space
    "([^"]+)"       # assigned to $referer
    \               # literal space
    "([^"]+)"       # assigned to $agent
    $               # end-of-string anchor
    /x              # regexp ends, with x modifier
    or next;

# USER CONFIGURABLE OPTIONS - Ignore internal hosts
    $host eq '::1' and next; # Ignore Apache generated requests from localhost.
    $host =~ /^192\.168\./ and next;    # Ignore the local net example #1
    $host =~ /^10\.10\.10/ and next;    # Ignore another net example #2

    # Parse the $time_zone variable.
    my $tz = 0;
    my ($tzs,$tzh,$tzm) = $time_zone =~ /([\-+ ])(\d\d)(\d\d)/;
    if(defined $tzs){
      $tzs = $tzs eq '-' ? 1 : -1;
      $tz = $tzs * (3600*$tzh + 60*$tzm);
    }

    my $time = timegm($sec,$min,$hour,$day,$mon{$mon},$year-1900) + $tz;
    $most_recent = $time if $time > $most_recent;

    next if $time < $start;

    #         [  0  ,  1  ,  2 ,   3   ,   4  ]
    push @rec,[$time,$host,$url,$status,$bytes];
  }

  my $report;

# USER CONFIGURABLE OPTIONS - Report if no client access has been seen for 180 seconds
  my $seconds_since_last_request = time - $most_recent;
  if($seconds_since_last_request > 180){
    # If too much time has elapsed, then report that something may be wrong.
    my $elapsed = delta_time($seconds_since_last_request);
    $report .=
    "$elapsed have elapsed since the last logged request.\n";
  }

  # Accumulate the statistics for the most recent X minutes' worth of logs.
  my %requests_per_host;
  my %bytes_per_host;
  my %errors_per_host;
  my %duplicate_urls_per_host;
  foreach(@rec){
    $requests_per_host{$_->[1]}++;
    $bytes_per_host{$_->[1]} += $_->[4];
    $errors_per_host{$_->[1]}++ if $_->[3] =~ /^[45]/;
    $duplicate_urls_per_host{$_->[1]}{$_->[2]}++;
  }

  # Report on IP addresses that exceed predefined thresholds.
  foreach my $host (keys %requests_per_host){
    my $name;
    my $n;
    if($requests_per_host{$host} > $max_requests_per_host){
      if($requests_per_host{$host} > $max_requests_per_host){
        $name = dns($host);
        $n = add_commas($requests_per_host{$host});
        $report .=
        "$host$name made $n requests during the past 10 minutes.\n";
      }
    }
    if($bytes_per_host{$host} > $max_bytes_per_host){
      $name = dns($host);
      $n = add_commas($bytes_per_host{$host});
      $report .=
      "$host$name downloaded $n bytes during the past 10 minutes.\n";
    }
    if($errors_per_host{$host} > $max_errors_per_host){
      $name = dns($host);
      $n = add_commas($errors_per_host{$host});
      $report .=
      "$host$name generated $n errors during the past 10 minutes.\n";
    }
    foreach my $url (keys %{$duplicate_urls_per_host{$host}}){
      if($duplicate_urls_per_host{$host}{$url} > $max_duplicate_urls_per_host){

        next if $url =~ m#^/ICONS/#
        and     $duplicate_urls_per_host{$host}{$url} < 250;

        $name = dns($host);
        $n = add_commas($duplicate_urls_per_host{$host}{$url});
        $report .=
        "$host$name requested $url $n times during the past 10 minutes.\n";
      }
    }
  }

  if($report){
    open P,"|$sendmail" or die "Could not open pipe to $sendmail ($!)";

    print P
    "From: $return_addr\n",
    "To: $recipients\n",
    "Errors-To: $return_addr\n",
    "Subject: Report from calomel web access sentry\n",
    "\n",
    $report;

    close P or die "Error executing $sendmail ($!)";
  }

# USER CONFIGURABLE OPTIONS - time before the next log check and email alert
  sleep 120;

  if($inode != (stat $log)[1]){
    # If the inode number of the log file has changed, then assume that the
    # logs have been rotated and reopen the log file to pick up the new one.
    close LOG;
    open LOG,$log or die "Could not open $log ($!)";
    $inode = (stat LOG)[1];
  }
  else{
    # Otherwise just reset the end-of-file condition.
    seek LOG,0,1;
  }
}

sub dns{
  my $ip = shift;
  return $dns{$ip} if defined $dns{$ip} && $dns{$ip};
  my $lookup = `/usr/bin/host $ip 2>/dev/null`;
  my $name;

  if($lookup =~ /NXDOMAIN/
  or $lookup =~ /SERVFAIL/
  or $lookup =~ /timed out/
  ){
    $name = '';
  }
  else{
    $name = (split ' ',$lookup)[-1];
    $name =~ s/\.$//;
    $name = " ($name)";
  }
  $dns{$ip} = $name if $name;
  $name;
}

sub add_commas{
  # Add commas to a number string (e.g. 1357924683 => 1,357,924,683)
  my $num = reverse shift;
  $num =~ s/(...)/$1,/g;
  chop $num if $num =~ /,$/;
  reverse $num;
}

sub delta_time{
  my $sec = shift;
  my $day = int($sec/86400);
  $sec -= 86400 * $day;
  my $hour = int($sec/3600);
  $sec -= 3600 * $hour;
  my $min = int($sec/60);
  $sec -= 60 * $min;

  my %s;
  $s{d} = $day  == 1 ? '' : 's';
  $s{h} = $hour == 1 ? '' : 's';
  $s{m} = $min  == 1 ? '' : 's';
  $s{s} = $sec  == 1 ? '' : 's';

  my $interval;

  if($day > 0){
    $interval =
    "$day day$s{d} $hour hour$s{h} $min minute$s{m} and $sec second$s{s}";
  }
  elsif($hour > 0){
    $interval =
    "$hour hour$s{h} $min minute$s{m} and $sec second$s{s}";
  }
  elsif($min > 0){
    $interval =
    "$min minute$s{m} and $sec second$s{s}";
  }
  else{
    $interval = "$sec second$s{s}";
  }

  $interval;
}

#######################################################
###  Calomel.org  calomel_web_sentry.pl  END
#######################################################
