#!/usr/bin/perl
use warnings;
use strict;
use CGI qw/param/;
use File::Copy;
use DBI;




# DHCP server script v0.14
#
# Script runs every 10 minutes, looking for changes in dhcp database 
# and applying them to the corresponding dhcp files.
#
# Changes on the following may be needed
# variables $dhcpFILE and $dhcpBACKUP on script in lines 275 and 276,
# 
# In order to run script type the following in command /<path>/<to>/<script>/dhcp_server_script_v014.pl 1
# Where the ‘1’ will initialize the loop. 


my $USAGE = "\nDHCP Server script v0.14 usage:\n\n In order to run script put the following
 in console:\n\n\tperl /<path>/<to>/<script>/dhcp_server_script_v014.pl 1\n";
 
#gets the parameter from command (1 expected)
  my ( $run ) = @ARGV;
  if ( not defined $run or $run =! 1){ #If no parameter given, or parameter different to 1
  print $USAGE; }
  #run script if parameter given is 1
  
  
  while (defined $run == 1) { #script starts running
  
 my $i = 0; #iterator to be used in all loops 
 
 # opens up configuration file to get mysql variables 
 my @CFG; 
 my $cfg_file = "dhcp_server_script_v013.cfg"; #cfg file with configurable variables
  
  open(CFG, "< $cfg_file") or die "Could not open $cfg_file : $!"; 
  
  while(<CFG>){ 
  next if (/^#/); 
  chomp; 
  my $var = (split(/: /))[1]; #splits and get value after :
  
  if (defined $var){
     
	$CFG[$i] = $var;
	$i++;
	}
	 
  } 
 
close(CFG);  
  
  
#  Global Variables
########  MYSQL database variables ######  
my $database =  $CFG[0];                #
my $hostname =  $CFG[1];                #
my $tablename = $CFG[2];                #   			                
my $user =      $CFG[3];			    #
my $pw =        $CFG[4];                #
my $port =      $CFG[5];                #
my $history_table = "dhcpentry_history";#	                
my $dsn = "DBI:mysql:database=" . $database . "
                     host=" . $hostname . " 
					 port=" . $port; 			
	                                    #
#####query execution variables###########							
my $sth;								#								
###### dhcp variables ###################
my $dhcpFILE;                           #
my $dhcpBACKUP;							#
my $dhcp_filename;   					#
my $dhcpdconf;							#
my $macAddr;							#
my $IP;									#
my $vlanId;								#
my $dhcpFile;							#
my $hostQuery;							#	
my $mac;								#
##### MySQL columns arrays ##############
 my @dhcpHost 		= 	();				#
 my @actionID		= 	();				#
 my @vlanID 		= 	();				#
 my @locationID 	= 	();				#
 my @dhcpMac 		= 	();				#
 my @dhcpNewMac 	= 	();				#
 my @dhcpIP 		= 	();				#
 my @dhcpFilename 	= 	();				#
 my @dhcpUser       = 	();				#
 my @hostID       	= 	();				#
 my @hostNum       	= 	();				#
 my @hostBname      = 	();				#
 my @hostRoom       = 	();				#
 my @hostPosition   = 	();				#
 my @hostComments   = 	();		        #
 my @dhcp_conf_file =   ();             #
###### Linux Terminal variables #########
 my $PID;                               #
 my $killPID;                           # 
 my $process;                           #
 my $restart_string;                    #
#########################################
 my $SLEEPTIME = 600;

# MySQL queries
  my $DELETION_QUERY; 
  my $sql = "SELECT * FROM $database.$tablename INNER JOIN 
                 $database.location ON $tablename.locationid = location.id 
                 ORDER BY location.id;"; #Query to get data from dhcpentry and location tables
 


###-------------------------FUNCTIONS-------------------------###

  #Transform an integer into IP address format
  sub dec2ip ($) {
    return join '.' => map { ($_[0] >> 8*(3-$_)) % 256 } 0 .. 3;
  }

  #function to write into dhcp_history table
  sub insertHistory
  { 
  my($dbh, $actionid, $vlanid, $locationid, $mac, $newmac, $ip, $filename, $user) = @_;


  my $historyQuery = "INSERT INTO $database.$history_table (actionid, vlanid, locationid, mac, newmac, ip, filename, timestamp, user) 
                     VALUES ('$actionid', '$vlanid', '$locationid', '$mac', '$newmac', INET_ATON('$ip'),
                             '$filename', NOW(), '$user');";
							 
  $dbh->do($historyQuery);						 
  }
  
  
  #checks for mac length then convert into mac format.
  sub macFormat
  {
  my ($mac) = @_;

  my $macSIZE = length $mac;
  if ( $macSIZE == 12 ){
 
  substr($mac,  2, 0) = ':';
  substr($mac,  5, 0) = ':';
  substr($mac,  8, 0) = ':';
  substr($mac, 11, 0) = ':';
  substr($mac, 14, 0) = ':';

  return $mac;
  } else {
  print "$mac has not the correct format\n";
  $mac = "FORMAT_NOT_CORRECT";
   }
  }
  
  
  sub countDown
  {
  my ($countD) = @_;
  
  			print "||| time until next iteration: |||\n ";

$| = 1; #disable output buffering

my $start_time = time;
my $end_time = $start_time + $countD;

	
for (;;) {
    my $time = time;
    last if ($time >= $end_time);

    printf("\r%02d:%02d:%02d",
        ($end_time - $time) / (1*60),
        ($end_time - $time) / 60%60,
        ($end_time - $time) % 60, 
    );
 
  
}  
print "\n\n";
  }



# Call the subroutine

  
 

###--------------------END OF FUNCTIONS-----------------------###

  
  
##################################################################
#   |	|	|	|	|	|	|	|	|	|	|	|	|	|	|	|#	
#   |	|	|  	|	|	|  	PROGRAM STARTS  |	|   |	|	|	|#
#	|	|	|	|	|	|	|	|	|	|	|	|	|	|	|	|#
##################################################################
                   
# Connect to database
my $dbh = DBI->connect($dsn, $user, $pw)
   or die "Connection Error: $DBI::errstr\n";

# Delete data older than 35 days in dhcpentry_history table
 my $DELETION_BY_TIME_QUERY = "DELETE FROM $history_table WHERE timestamp < NOW() - INTERVAL 35 DAY;"; 
$dbh->do($DELETION_BY_TIME_QUERY);


  #prepare and execute sql to get data from dhcp and location tables
    $sth = $dbh->prepare($sql);
    $sth->execute
    or die "SQL Error: $DBI::errstr\n";

 #putting extracted data into arrays
 $i = 0; #reset iterator
 while (my @row = $sth->fetchrow_array) 
 {
 
 $actionID[$i]      =  $row[0];
 $vlanID[$i]        =  $row[1];
 $locationID[$i]    =  $row[2];
 $dhcpMac[$i]       =  $row[3];
 $dhcpNewMac[$i]    =  $row[4];
 $dhcpIP[$i]        =  dec2ip($row[5]);
 $dhcpFilename[$i]  =  $row[6];
 $dhcpUser[$i]      =  $row[7];
 $hostID[$i]        =  $row[8];
 $hostNum[$i]       =  $row[9];
 $hostBname[$i]     =  $row[10];
 $hostRoom[$i]      =  $row[11];
 $hostPosition[$i]  =  $row[12];
 $hostComments[$i]  =  $row[13];
 


 #send dhcpentry data to dhcp_history table
 insertHistory($dbh, $actionID[$i], $vlanID[$i], $locationID[$i], $dhcpMac[$i], $dhcpNewMac[$i],
              $dhcpIP[$i], $dhcpFilename[$i], $dhcpUser[$i]); 
 
 $i++; 
  }
  
  #if actionID[0] is undefined, mysql action column is empty
  #no addition to the database was made
  if (not defined $actionID[0]) {
     print " No changes have been committed since last iteration\n\n";
	 }


  $i = 0; #iterator reset to 0

  #check for building name from location table and builds hostname according to data
  foreach my $index ( @hostBname ) 
  {
	if (defined $index){
	$dhcpHost[$i] = $index.$hostRoom[$i]."_".$hostPosition[$i];
	$i++;
  } else {
	$dhcpHost[$i] = "";
	     }
  }

  $i = 0; #iterator reset to 0

#starts main loop
  foreach my $actioner ( @actionID ) 
  {
 
 ################## DHCP file paths. Replace path to the one needed ######################
 $dhcpFILE = "/Users/Carlos_Silva/Desktop/$vlanID[$i]/$vlanID[$i].conf";                 #
 $dhcpBACKUP = "C:/Users/Carlos_Silva/Desktop/$vlanID[$i]/$vlanID[$i]BACKUP.conf";       #
 #########################################################################################
 
 copy( $dhcpFILE, $dhcpBACKUP) or die "File $dhcpFILE was not copied : $!"; #copy from file to backup
 print "$dhcpFILE backup created\n";
 
 #open dhcp file in a temporal handler for reading purposes, and stores it into a variable
 open (DHCP_FILE1, "< $dhcpFILE")  or  die "Can not read dhcp.conf file $dhcpFILE : $!";
 my @dhcp_file = <DHCP_FILE1>;
 close (DHCP_FILE1); #closes temporal handler
 
 #opens into handler for writing purposes then join into one line and split into different arrays of the file
 open (DHCP_FILE, "> $dhcpFILE")  or  die "Can not read dhcp.conf file $dhcpFILE : $!";
 my $content = join('', @dhcp_file);
 chomp($content);
 my @dhcpContent = split(/}/,$content);
 
 #print @dhcpContent;
  

       # for each action, is going to loop the entire file according to their vlanid
       foreach my $line ( @dhcpContent ) 
       {


		if ( $dhcpHost[$i] ne "" and $line !~ /^\s*$/ ) #if dhcpHost is not empty and line not a white space
		{


#  Actions menu
#     1 = add
#     2 = remove
#     3 = replace

		if ( defined $actionID[$i] ){
		$DELETION_QUERY = "DELETE FROM `$database`.`$tablename` WHERE `mac`='$dhcpMac[$i]';";

	#look to match the dhcp host coming from DB with the one in file.
    #if matches, does modifications, if doesn't	prints dhcp chunk as it comes, until match is found.
   if ( $actionID[$i] == 3 )
   {

        if ( $line =~ m/host $dhcpHost[$i]/ ) 
	    {
		      
			     if ($line =~ m/hardware ethernet (\w+:\w+:\w+:\w+:\w+:\w+)/)
			     {
				
			      $macAddr = $1;
				  $mac = macFormat($dhcpNewMac[$i]);
		 		
		    	  $line =~ s/$macAddr/$mac/g;
			
			     }
			
			     if($line =~ m/fixed-address ([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/)
     		     {
 				  $IP = $1.'.'.$2.'.'.$3.'.'.$4;
				  $line =~ s/$IP/$dhcpIP[$i]/g;	
			     }

			
			 if ($line =~ m/filename (.*?)\s/)
			 {
				$dhcp_filename = $1;
				$line =~ s/$dhcp_filename/$dhcpFilename[$i]/g;	
				 
		
			 }
			 print DHCP_FILE $line."}";
			 print "Host entry $dhcpHost[$i] was modified successfully in $vlanID[$i].conf\n\n";
			 $dbh->do($DELETION_QUERY);
			 #$i = $i+1;
		 } else {
		 
		    if ( defined $line ) {
		  print DHCP_FILE $line."}";
	   
		                         }
		
		        }
	 } 
	 
	 
	 
	 
	#Match dhcp from db with the one in file.
	#if matches, prints nothing in file (erasing the dhcp host); 
	#if doesn't match, prints the dhcp as it comes from the file
	elsif ( $actionID[$i] == 2)
	{
	   if ( $line =~ m/host $dhcpHost[$i]/ ) 
	    {
		print "Host entry $dhcpHost[$i] was deleted successfully from $vlanID[$i].conf\n\n";
		#do nothing, erasing the dhcp entry.
		
		} elsif ( defined $line and $line !~ /^\s*$/ ) {
		 
				print DHCP_FILE $line."}";
	    }
		 $dbh->do($DELETION_QUERY);
		
	}
	#prints dhcp as it comes, avoiding putting additions in the middle of the file
	elsif ( $actionID[$i] == 1)
	{
     if ( defined $line and $line !~ /^\s*$/ ) {    #if line has not white spaces 
         
			print DHCP_FILE $line."}";
	}

	} 
		}
				}
				   }
			  
								
									
				 
	 #Different addition loop, separated to ensure that dhcp additions goes to the end of the file
	  if ( $actionID[$i] == 1 ) 
	{
	
 	 $DELETION_QUERY = "DELETE FROM `$database`.`$tablename` WHERE `mac`='$dhcpMac[$i]';";
    $mac = macFormat($dhcpMac[$i]);
    print DHCP_FILE "\nhost ".$dhcpHost[$i]."\n{\nhardware ethernet $mac; \nfixed-address $dhcpIP[$i]; \nfilename $dhcpFilename[$i];\n} ";
    print "Host entry $dhcpHost[$i] was added successfully to the file $vlanID[$i].conf\n\n";
	$dbh->do($DELETION_QUERY); #delete query from dhcpentry

    }
	
                #Get proccess ID
				$PID = qx(pgrep -f $vlanID[$i]);
				 $killPID = "kill -9 $PID";
				 #kill process
				 system($killPID);
				  
				  $process = qx(ps x | grep $vlanID[$i]);
				#if string matches with executable
				if ($process =~ (m/(\/usr\/sbin.*)/)) {
						
						 $restart_string = "$1";
						 #restart process
						system ($restart_string);
												      }
			 
				 
				 close (DHCP_FILE);
				 $i++;
				    }
		countDown($SLEEPTIME);  




}



