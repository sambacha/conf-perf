#!/usr/bin/perl -T

# Calomel.org 
#    ssh_gatekeeper.pl
#    version 0.18
#

# ssh_gatekeeper is used to add a second authentication method to interactive
# ssh log in. The script is called by sshd_config's ForceCommand directive
# after the user provides the correct password, ssh key or ssh key with pass
# phrase. The user is required to enter the PIN from Google Authenticator or a
# custom string _before_ being awarded a valid shell on the system. Any other
# attempt to break out of the script or give an incorrect answer will kill this
# processes and sever the ssh connection. Full logging of all connections are
# sent to syslogd.

use strict;
use warnings;
use POSIX qw(strftime);
use Sys::Syslog qw( :DEFAULT setlogsock);

# catch all attempts to exit the script and force an exit.
$SIG{'INT' } = 'abort_exit';
$SIG{'HUP' } = 'abort_exit';
$SIG{'ABRT'} = 'abort_exit';
$SIG{'QUIT'} = 'abort_exit';
$SIG{'TRAP'} = 'abort_exit';
$SIG{'STOP'} = 'abort_exit';

# User options
###################################################################

# Option: What greeting string do you want to display to the user when they
# attempt to log in ? "\n" are new line characters.
 my $greeting = "\n\n   Intelligence is the ability to adapt to change.\n\n\n";

# Option: Which authentication method do you want to use? The options are
# "google" for google authenticator and "custom" for a string you make yourself
# in the custom_string subroutine found below.
#my $authentication = "custom";
 my $authentication = "google";

# Option: if you are using Google Authenticator you have two options. You can
# read a file in the user's home directory for the secret key or, if you are
# the only user using this script, you can just put your secret key here. If
# this script is being used for more then one user put the string "multi-user"
# for the $secretkey and the script will read the file
# $home/.google_authenticator . The .google_authenticator file should
# contain a single line with only the secret key and the permissions should be
# no more then 400 for security. If multi-user is chosen and the
# .google_authenticator file does not exist the script will exit and drop the
# connection. If you are the only user of this script and you want to put your
# secret key here then no external file will be read.
#my $secretkey="multi-user";
 my $secretkey="JJUEEUDOIJAFCZCC";

# Option: Do you want to append any characters to the end of your password?
# This option is for the truly paranoid and makes the password a lot harder to
# crack. For example, Google Authenticator has 6 numerical digits. You can
# append more characters to the end in case someone gets hold of your secret
# key. Then the attacker would still need to know your appended string. If the
# Google Authenticator code was 123456 and we added "0.0,8-" our true password
# would be "1234560.0,8-" . Again, if the GA code is "456789" the password
# would be "4567890.0,8-" . You can add any of the following safe characters in
# any combination: a-z A-Z 0-9 . , - + = # :
#my $additional_pass_chars = "0.0,8-";
 my $additional_pass_chars = "";

# Option: Exactly how many characters are in your password? Set the minimum and
# maximum amount of characters allowed in the password. Remember, if you added
# extra characters to the $additional_pass_chars option you need to add that
# number to the total. For example, Google Authenticator has 6 digits. So we
# would enter a minimum of at least 6. If we added six(6) characters to
# $additional_pass_chars then the total would be 12 (6+6=12) and we would need
# to make sure the length maximum was at least 12. We recommend using a 12
# character password or greater.
 my $pasword_length_min = 6;
 my $pasword_length_max = 24;

# Option: Some protocols can not use two factor authentication because they
# need a clean shell environment. rsync, scp and sftp (sshfs uses sftp) are
# part of this exception. Also, if you try to pass a command with ssh then the
# extra command will be denied. For example, if you "ssh user@machine ls" to do
# a non-interactive ls on the remote machine you will be denied unless you add
# "ls" as a clean command. WARNING: you can also do an "ls -la" and even "ls
# -la;rm -rf *" since ls is still the primary command. Be careful about what
# you allow. If you do not use a protocol, remove it. If you wanted to be
# sneaky you could make an executable script in the $PATH called something like
# "AA" on the server that does nothing. Then add "AA" to our clean protocols
# list.  You could then do an ssh user@machine "AA;ls -al". This would execute
# AA, which does nothing, and then ls -la.  The difference is no one would ever
# pass your system the AA command since it is not a common program. Sort of a
# non-interactive command pass-through with AA pass the password. You must
# enter the protocol as a string the same way the sshd server will execute the
# command. This means rsync is just "rsync. sftp is actually the full path to
# the sftp-server binary.
#my @clean_protocols = ("rsync","/usr/lib/openssh/sftp-server","scp","ls", "AA");
 my @clean_protocols = ("rsync","/usr/libexec/sftp-server");

###################################################################

# declare global variables, redefine PATH for safety and open syslog logging
# socket.
my $code="invalid_code";
my $code_attempt="invalid_code_attempt";
$ENV{PATH} = "/bin:/usr/bin:/usr/local/bin";
setlogsock('unix');

# collect and untaint environment values. It is very important we scrub the
# environmental variables so a bad user can not send illegal commands into our
# script. If you run the script and it logs abort_exit in /var/log/messages
# output then the script could have exited on one of the following lines. Each
# line only allow certain characters from each environmental variable. Illegal
# characters will make the script abort_exit.
my $ssh_orig = "";
my $username  = "$1" if ($ENV{LOGNAME} =~ m/^([a-zA-Z0-9\_\-]+)$/ or &abort_exit);
my $ssh_conn  = "$1" if ($ENV{SSH_CONNECTION} =~ m/^([0-9\. ]+)$/ or &abort_exit);
my $usershell = "$1" if ($ENV{SHELL} =~ m/^([a-zA-Z\/]+)$/ or &abort_exit);
my $home  = "$1" if ($ENV{HOME} =~ m/^([a-zA-Z0-9\_\-\/]+)$/ or &abort_exit);
if (defined($ENV{SSH_ORIGINAL_COMMAND}))
   { $ssh_orig  = "$1" if ($ENV{SSH_ORIGINAL_COMMAND} =~ m/^([a-zA-Z0-9\_\/\~\-\. ]+)$/ or &abort_exit); }

# SSH standard interactive access with two factor authentication. The following
# function is for interactive SSH when the user just want to log into the
# machine. You can choose the authentication method and the sub routines will
# be called farther below in the script.
if ( ! defined $ENV{SSH_ORIGINAL_COMMAND} ) {
    &user_login_attempt;
    &google_authenticator if ( $authentication eq "google");
    &custom_string        if ( $authentication eq "custom");
    &validate_input;
}

# @clean_protocols access like rsync, scp, sftp, and sshfs. If the user passes
# a command to ssh (like ssh user@machine ls) or uses another protocol through
# SSH this function will be run. We carefully separate the command shell of the
# user and allow any of our pre-defined @clean_protocols.
if ( defined $ENV{SSH_ORIGINAL_COMMAND} ) {
 my @scp_argv = split /[ \t]+/, $ssh_orig;
 foreach (@clean_protocols) {
  if ( $scp_argv[0] eq "$_") {

     # Sanitize rsync so a sneaky user can not use rsync as a tunnel to execute
     # system commands. rsync is for coping files only.
     if ( ( "rsync" eq "$_") && ($ssh_orig =~ /[\&\(\{\;\<\`\|]/ ) ) {
            &logger("DENIED","dirty rsync: $ssh_orig");
            &clean_exit;
     }

     # Log the connection and allow the @clean_protocols to run in a shell
     &logger("ACCEPT","clean_protocol: $_");
     system("$usershell", "-c", "$ssh_orig");
     &clean_exit;
  }
 }
     # deny the connection if the previous checks have failed
     &logger("DENIED","UN_clean_protocol: $ssh_orig");
     &clean_exit;
}

sub user_login_attempt {
    local $SIG{ ALRM } = sub { &clean_exit; };

    # The user has this many seconds to complete the authentication process
    # or we kill the connection. No lollygagging.
    alarm 60;

    # The personal greeting when a user attempts to authenticate
    print $greeting;

    # WARNING: This is the only time we ask the remote user for input. STDIN is
    # completely untrusted and must be validate and checked. Use stty to not
    # echo the password from the user and accept their input.
    system("/bin/stty", "-echo");
    chomp($code_attempt = <STDIN>) or &abort_exit;

    # The password we will accept is between $pasword_length_min and
    # $pasword_length_max length and may only consist of alphanumeric, comma,
    # dash, plus, equal, pound, colon and period characters. All other input
    # aborts the script and never awards a shell. If the input is validated the
    # script considers the string untainted.
    my $inputlength = length($code_attempt);
    if ( $inputlength < $pasword_length_min || $inputlength > $pasword_length_max ) {
       &logger("DENIED","bad pass length: $inputlength characters");
       &clean_exit;
    } elsif ( $code_attempt !~ m/^([a-zA-Z0-9\,\-\+\=\#\:\.]+)$/ ) {
       &logger("DENIED","invalid password characters");
       &clean_exit;
    } else {
       # Accept the user's now untainted input.
       $code_attempt = "$1"
    }
    alarm 0;
}

sub google_authenticator {

    # Delay module loading until the user sends valid input. There is no need
    # to load modules if the user fails the input sanity checks. You will need
    # these three modules installed on the sshd server machine in order to use
    # the Google Authenticator feature. They are all available through FreeBSD
    # ports or Ubuntu's apt-get.
    eval "
        use Time::Local;
        use MIME::Base32;
        use Digest::HMAC_SHA1 qw(hmac_sha1);
    ";

    # For multi-user systems the private 16 digit secret key is read from the
    # file in the user's home directory. Do not share this the key with anyone
    # and make sure the permissions on the file are no more then 400. This key
    # is the exact same string you put into the Google Authenticator phone or
    # tablet app. If you defined your secret key in the options above this
    # statement is not run.
    if ( $secretkey eq "multi-user" ) {
        $secretkey = do {
        local $/ = undef;
        open my $file, "<", "$home/.google_authenticator" or &abort_exit;
        <$file>;
      };
    }

    # Calculate the valid PIN using the secret key and current date. The result
    # in $code will match the 6 digit pin from the Google Authenticator phone
    # app.
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

      # Take the google PIN number of 6 digits and add the
      # additional_pass_chars option if we defined it in the options section.
      $code = join( "", $code, $additional_pass_chars);
}

sub custom_string {

      # Instead of using Google Authenticator, define some random string which
      # could even include the time or date to make the code more random and
      # difficult to guess. For example, lets make the password string
      # "m,56Wed--" when the Date and time are "Wed May  1 14:56:22 EDT 2033".
      # Use the local time of the machine to collect the minute and day using
      # "%M%a" which is "56Wed". Then use the join function to add "m," to the
      # date string "56Wed" and the final "--" string. This way you have a
      # password which changes every minute and you can deduce on the fly using
      # any moderately accurate time source.
      my $date_string = strftime "%M%a", localtime;
      $code = join( "", "m,", $date_string, "--", $additional_pass_chars);
}

# Validate the user input and, if correct, reward a shell 
sub validate_input {
    if ( $code eq $code_attempt ) {
       # turn command line echo back on so the logged in user can see what they are typing.
       system("/bin/stty", "echo");

       # log the successful shell being awarded
       &logger("ACCEPT","interactive ssh");

       # Award a shell to the user, using their preferred shell, and exit the
       # script when they log out of the machine. If this script is killed for
       # any reason also kill the user's shell.
       setpgrp $$, 0;
       system("$usershell", "--login");
       END {kill 15, -$$}
       &clean_exit;

    } else {
       # log the failed attempt
       &logger("DENIED","bad password");
       # DEBUG: log the user attempted password and the actual password.
      #&logger("DENIED","input: $code_attempt valid: $code");
       &clean_exit;
    }
}

# global logger to send data to syslogd. We accept two(2) arguments. First is
# the message about ACCEPT or DENIED access. The Second argument is extra
# information for the end of the log line like "bad password".
sub logger {
    openlog($0,'pid','$username');
    syslog('info', "$_[0] $username from $ssh_conn $_[1]");
    closelog;
}

# If the user or script exits normally the script will pass an exit code of
# zero(0).
sub clean_exit {
    &logger("EXIT  ","clean exit");
    exit(0);
}

# This is the final catch all exit routine and passes an exit code of one(1).
sub abort_exit {
    &logger("ABORT ","caught bad script exit: $ssh_orig");
    exit(1);
}
&abort_exit;

#########  EOF #########
