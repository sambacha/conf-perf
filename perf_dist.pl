#!/usr/bin/perl 

use strict;
use warnings;

## Calomel.org .:. https://calomel.org
##   name     : calomel_http_log_distribution_performance.pl
##   version  : 0.01

##   usage: ./calomel_http_log_distribution_performance.pl log_lines regex1 regex2 regex3

# description: the script will parse the logs and collect the web server
# distribution times at the end of the log line. It will then count the number
# of requests completed per time frame in 0.1 second increments. The last step
# is to display the results in an ASCII graph on the command line. 

## which log file do you want to watch?
  my $log = "/var/log/nginx/access.log";

## user defined number of log lines to tail 
  my $lines = 10000;
  $lines = $ARGV[0] if ((defined$ARGV[0]) && ($ARGV[0] =~ /^[+-]?\d+$/));

## declair the user defined search string #1
  my $search1 = "";
  $search1 = $ARGV[1] if defined($ARGV[1]);

## declair the user defined search string #2
  my $search2 = "";
  $search2 = $ARGV[2] if defined($ARGV[2]);

## declair the user defined search string #3
  my $search3 = "";
  $search3 = $ARGV[3] if defined($ARGV[3]);

## do you want to debug the scripts output ? on=1 and off=0
  my $debug_mode = 0;

## declair some internal variables and the hash of the time values
  my ( $distime );
  my %seconds = ();

## clear the environment and set our path
$ENV{ENV} ="";
$ENV{PATH} = "/bin:/usr/bin:/usr/local/bin";

## open the log file. we are using the system binary tail which is smart enough
## to follow rotating logs. We could have used File::Tail, but tail is easier.
  open(LOG,"tail -$lines $log |") || die "Failed!\n";

  while(<LOG>) {
       ## process log line if it reports a successful file distribution and if it includes
       ## the optional user defined search string.
       if ( ($_ =~ m/( 200 )/) && ($_ =~ m/$search1/) && ($_ =~ m/$search2/) && ($_ =~ m/$search3/) ) {

         ## extract the distribution time and round to tenths of a second. If the last value
         ## of the log line is NOT a number an error will print for every bad line.
          $distime = sprintf("%.1f",(split ' ')[-1]);

         ## initialize the hits value to avoid warning messages.
         $seconds{ $distime }{ 'hits' } = 0 if not defined $seconds{ $distime }{ 'hits' };

         ## increment the hits counter for every time value.
          $seconds{ $distime }{ 'hits' } = $seconds{ $distime }->{ 'hits' } + 1;

         ## DEBUG: show detailed output
         if ( $debug_mode == 1 ) {
           print $_;
           print "search1: $search1 search2: $search2 search3: $search3  dist time: $distime  hits: $seconds{ $distime }{ 'hits' }\n";
         }
       }
  }

## declair some constants for the ASCII graph.
use constant MAX     => 50;
use constant Height  => 30;
use constant Indent  => 7;
use constant Periods => 96;

## Enter the data collected from the logs into a Data array we can graph from
my @Data;
my $Element = 0;
my $TenthSec = 0.0;
while($Element < Periods)
   {
   $Data[$Element] = 0;
   $Data[$Element] = $seconds{ sprintf("%.1f",$TenthSec) }{ 'hits' } if length($seconds{  sprintf("%.1f",$TenthSec) }{ 'hits' } //= '');
   $TenthSec=$TenthSec + 0.1;
   $Element++;;
   }

## Print out the ASCII graph by calling the ASCII_Graph method.
print "\n   .:.  Calomel Webserver Distribution Performance Statistics\n\n";
print "         Log lines: $lines, Search string(s): $search1 $search2 $search3\n";
print(ASCII_Graph(Height, Indent, Periods, @Data));
print "\n\n\n";

## This is the method to make the ASCII graph from the Data array. Special 
## thanks to the Perl Monks site for the examples. This is an array of 96 values
## which represent 0.0 to 9.0 seconds. Though you will have requests which take
## longer then 9 seconds to serve, this should be exception. Google for example
## use page load times in their Google Pagerank, so if your site takes longer then
## a few seconds to load you will not be ranked very high compared to your competition.
sub ASCII_Graph
{
   my ($Height, $Indent, $Periods, @Data) = @_;
   my $HighestValue = 0;
   my @Rows = ();
   for my $Period (0 .. $Periods - 1) { $HighestValue = $HighestValue > $Data[$Period] ? $HighestValue : $Data[$Period]; }
   my $Scale = $HighestValue > $Height ? ( $HighestValue / $Height ) : 1;
   for my $Row (0 .. $Height) {
      if($Row % 2) { $Rows[$Row] = sprintf("%" . ($Indent - 1) ."d ", $Row * $Scale) . ($Row % 5 == 0 ? '_' : '.') x $Periods; }
      else { $Rows[$Row] = sprintf("%" . ($Indent - 1) ."s ", ' ') . ($Row % 5 == 0 ? '_' : '.') x $Periods; }
      for my $Period (0 .. $Periods - 1) {
         if ($Data[$Period] / $Scale > $Row) {
            substr($Rows[$Row], $Period + $Indent, 1) = '|';
            }
         }
      }

   return(join( "\n", reverse( @Rows ), ' Time: ' . '|^^^^' x ( $Periods / 5 ), ' ' x $Indent . '0   0.5  1.0  1.5  2.0  2.5  3.0  3.5  4.0  4.5  4.6  5.0  5.5  6.0  6.5  7.0  7.5  8.0  8.5  9.0'));
}
#### EOF ####
