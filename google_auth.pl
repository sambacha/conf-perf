#!/usr/bin/perl -T

# Calomel.org -- google_auth_secret_generator.pl
#
# Generate 16 digit Base32 secret key for Google Authenticator. Additional
# system entropy is created by running extra key generations.

use strict;
use warnings;
use MIME::Base32 qw( RFC );

# while loop counter and seed variable.
my $count = 0;
my $seed = "";

# run a simple while loop to generate system entropy. Additional entropy might
# help since rand() is not the best random number collector, but good enough
# for this task. At the end of the run send the $seed to be base32 encoded.
while ($count <= int(rand(100000)) + int(rand(10000)) * int(rand(1000))) {
 # Randomly generate a 10 character seed string
 my @chars = ( "A" .. "Z", "a" .. "z", 0 .. 9, qw(! @ $ % ^ & *) );
 $seed = join("", @chars[ map { rand @chars } ( 1 .. 10 ) ]);
 $count++;
}

# encode the 10 character sudo random string into a base32 16 character string
# for use in the Google Authenticator app.
my $encoded = MIME::Base32::encode($seed);

# print the code
print "\nNumber of iterations for entropy:   $count\n";
print "Google Authenticator Secret Key :   $encoded\n\n";

#########  EOF #########
