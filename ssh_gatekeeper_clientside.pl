#!/usr/bin/perl -T

# Calomel.org google_auth_pin.pl
#
# The google_auth_pin.pl script will print out the six(6) digit pin using the
# current date and your Google Authenticator secret key. This is the same
# calculation done by the phone app.

use strict;
use warnings;
use POSIX qw(strftime);
use Sys::Syslog qw( :DEFAULT setlogsock);
use Time::Local;
use MIME::Base32;
use Digest::HMAC_SHA1 qw(hmac_sha1);

# declare global variable
my $code = "";

# the secret key of the machine you are connecting to
my $secretkey="JJUEEUDOIJAFCZCC";

# Calculate the valid PIN using the secret key and current date. The result in
# $code will match the 6 digit pin from the Google Authenticator phone app.
   my $tm = int(time/30);
   $secretkey=MIME::Base32::decode_rfc3548($secretkey);
   my $b=pack("q>",$tm);
   my $hm=hmac_sha1($b,$secretkey);
   my $offset=ord(substr($hm,length($hm)-1,1)) & 0x0F;
   my $truncatedHash=substr($hm,$offset,4);
   $code=unpack("L>",$truncatedHash);
   $code=$code & 0x7FFFFFFF;
   $code%=1000000;
   $code = join( "", "0", $code) if (length($code) == 5);

# print out the six(6) digit pin to the command line.
   print "\nGoogle Authenticator PIN: $code\n\n";

#########  EOF #########
