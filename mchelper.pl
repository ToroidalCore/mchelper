#!/usr/bin/perl -w

use strict;
use IPC::Open2;
use POSIX qw(setsid);
use File::Pid;
use IO::Select;

####################################################################################################
# Basic configuration variables - change these for your system!
my $log = "/tmp/mchelper.log";
my $pidfilename = "/tmp/mchelper.pid";
my $minecraftsrvpath = "/var/minecraft/mchelper/";
my $minecraftsrvexe = "minecraft_server.1.7.10.jar";
my $java = "/usr/bin/java";
####################################################################################################

#Set to 1 to log to the console, in addition to the logfile
my $debug = 0;

my $mccmd = $java . " -Xmx1024M -Xms1024M -jar " . $minecraftsrvpath . $minecraftsrvexe . " nogui"; 
my $alive = 1;
my $pidfile;

$SIG{INT} = $SIG{TERM} = $SIG{HUP} = \&signalHandler;

#logmsg("Path: $mccmd");

#Make the program a deamon
daemon();

####################################################################################################
# Start the main logic of the program

#First, chdir to the working directory, so the server can run
chdir($minecraftsrvpath);

#Some variables
my ($mcspid, $mcread, $mcwrite);

#Use open2 to start the server with read/write file handles
#Wrap in eval to catch errors
eval {
	$mcspid = open2($mcread, $mcwrite, $mccmd);
};
if($@) {
	if ($@ =~ /^open2/) {
		logmsg("Warning: open2 failed: $!\n$@");
		return;
	}
	die;
}

logmsg("Minecraft server started with pid: $mcspid");

#Use select to multiplex our single filehandle so the loop doesn't block
my $select = IO::Select->new();
$select->add($mcread);

#Main loop
while($alive) {
	#Temp variable for logging
	my $con;
	
	#Handles ready for reading
	my @ready = $select->can_read(0.25);

	#Loop through handles (probably just one) and log what they have to say
	foreach(@ready) {
		$con = <$_>;
		if($con) {
			chomp($con);
			logmsg("$con");
		}
	}
	#sleep(1);
}

#When the loop is done, remove the pid file
if(defined($pidfile)) {
	$pidfile->remove();
}

####################################################################################################

sub daemon {
	chdir("/") || logmsg("Can't chdir to /: $!") && die("Can't chdir to /: $!");
	open(STDIN, "/dev/null") || logmsg("Can't open /dev/null for reading: $!") && die("Can't open /dev/null for reading: $!");
	open(STDOUT, ">>", "/dev/null") || logmsg("Can't open /dev/null for writing: $!") && die("Can't open /dev/null for writing: $!");
	open(STDERR, ">>", "/dev/null") || logmsg("Can't open /dev/null for writing: $!") && die("Can't open /dev/null for writing: $!");
	
	my $pid = fork();
	
	if($pid > 0) {
		#We're the parent
		logmsg("Forked with child PID $pid.");
		exit(0);
	}
	elsif($pid == 0) {
		#We're the child
		setsid() || logmsg("Can't start a new session: $!") && die("Can't start a new session: $!");
		
		$pidfile = File::Pid->new( { file => '/tmp/mchelper.pid' }, );
		if(!$pidfile->write()) {
			logmsg("Could not write pidfile: $!");
		}
	}
	else {
		#Error
		logmsg("Could not fork: $!");
		exit(1)
	}
}

sub signalHandler {
	logmsg("Stopping server");
	print $mcwrite "/stop\n";
	$alive = 0;
}

sub logmsg {
	#Partly taken from
	#http://jeredsutton.com/2010/07/18/simple-perl-logging-subroutine/
	
	my $msg = shift;
	if($debug) {
		print "$msg\n";
	}

	my ($logsec,$logmin,$loghour,$logmday,$logmon,$logyear,$logwday,$logyday,$logisdst)=localtime(time);
   my $logtimestamp = sprintf("%4d-%02d-%02d %02d:%02d:%02d",$logyear+1900,$logmon+1,$logmday,$loghour,$logmin,$logsec);
   my $fh;
	open($fh, ">>", "$log");
	print $fh $logtimestamp . " - " . $msg . "\n";
	close($fh);
}

END {

}
