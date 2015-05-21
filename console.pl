#
#

package pDrive;

use strict;
use Fcntl ':flock';

use FindBin;

# fetch hostname
use Sys::Hostname;
use constant HOSTNAME => hostname;


if (!(-e './config.cfg')){
  print STDOUT "no config file found... creating config.cfg\nYou will want to modify this file (including adding a username and password)\n";
  open(CONFIG, '>./config.cfg') or die ('cannot create config.cfg');
  print CONFIG <<EOF;
package pDrive::Config;

# must change these
use constant LOCAL_PATH => '/u01/pdrive/'; #where to download / upload from
use constant USERNAME => '';
use constant PASSWORD => '';

# configuration
use constant LOGFILE => '/tmp/pDrive.log';
use constant SAMPLE_LIST => 'samplelist.txt';

# when there is a new server version, save the current local as a "local_revision"
use constant REVISIONS => 1;


#for debugging
use constant DEBUG => 1;
use constant DEBUG_TRN => 1;
use constant DEBUG_LOG => '/tmp/debug.log';

#
# shouldn't need to change the values below:
#
use constant DBM_CONTAINER_FILE => LOCAL_PATH . '.pdrive.catalog.db';
use constant DBM_TYPE => 'DB_File';
use DB_File;


use constant APP_NAME => 'dmdgddperl';
1;
EOF
  close(CONFIG);
}

require './config.cfg';

use lib "$FindBin::Bin/../lib";
require 'lib/dbm.pm';
require 'lib/time.pm';
require 'lib/fileio.pm';
require 'lib/gdrive_drive.pm';
require 'lib/onedrive.pm';
require './lib/googledriveapi2.pm';
require './lib/onedriveapi1.pm';



my $filetype = {
'3gp' => 'video/3gpp',
'avi' => 'video/avi',
'mp4' => 'video/mp4',
'flv' => 'video/flv',
'mpeg' => 'video/mpeg',
'mpg' => 'video/mpeg',
'm4v' => 'video/mp4',
'pdf' => 'application/pdf'};



# magic numbers
use constant IS_ROOT => 1;
use constant NOT_ROOT => 0;

use constant FOLDER_TITLE => 0;
use constant FOLDER_ROOT => 1;
use constant FOLDER_PARENT => 2;
use constant FOLDER_SUBFOLDER => 3;

#use constant CHUNKSIZE => (256*1024);
#use constant CHUNKSIZE => 524288;
use constant CHUNKSIZE => (8*256*1024);

use Getopt::Std;
use constant USAGE => " usage: $0 [-c file.config]\n";

my %opt;
die (USAGE) unless (getopts ('c:u:p:',\%opt));

#die("missing parameter\n". USAGE) unless($opt{c} ne '');

#die("config file $opt{c} doesn't exit\n") unless (-e $opt{c});



######
#

=head1 NAME

  Scheduer Operator Script - see versioning at the end of the file

=head1 DESCRIPTION

  Main script that performs the Scheduler operator functionality.

=head2 Commands

=over

=item quit/exit

  Exit the operator script.

=back

=cut

#
###


use constant HELP => q{
 >authenticate <username> <password>
  authenticate with gdrive
 >resume
  Resume the Scheduler to allow the start of new jobs.
 >stop
  Stop and exit the Scheduler once the current jobs have finished.
 >help
  Displays the commands available.
 >quit/exits
  Exit the operator script.
};


my $currentURL;
my $nextURL;
my $driveListings;
my $createFileURL;
my $loggedInUser = '';
my $bindIP;
my @services;
my $currentService;
my $dbm = pDrive::DBM->new();

# scripted input
my $userInput;
if ($opt{c} ne ''){

	my $command = $opt{c};
    open ($userInput, "<".$command) or  die ('cannot read file list.dir');

}else{
	$userInput = *STDIN;
}

print STDERR '>';

while (my $input = <$userInput>){

	if($input =~ m%^exit%i or$input =~ m%^quit%i){
  		last;
  	}elsif($input =~ m%^help%i or $input =~ m%\?%i){
    	print STDERR HELP;

	###
	# os-tools
	###
  	# run system os commands
  	}elsif($input =~ m%^run\s[^\n]+\n%i){

    	my ($os_command) = $input =~ m%^run\s([^\n]+)\n%;
    	print STDOUT "running $os_command\n";
    	print STDOUT `$os_command`;
  	##
	# bind to IP address
	###
  	}elsif($input =~ m%^bind\s[^\s]+%i){
    	my ($IP) = $input =~ m%^bind\s([^\s]+)%i;
    	$bindIP = $IP . ' - ';

		for (my $i=0;$i <= $#services;$i++){
			if (defined $services[$i]){
				$services[$i]->bindIP($IP);
				$loggedInUser .= ', ' if $i > 1;
				$loggedInUser .= $i. '. ' . $services[$i]->{_username};
			}
		}

    # scan local dir
  	}elsif($input =~ m%^scan dir\s[^\n]+\n%i){
    	my ($dir) = $input =~ m%^scan dir\s([^\n]+)\n%;
    	print STDOUT "directory = $dir\n";
    	pDrive::FileIO::scanDir($dir);

  	}elsif($input =~ m%^load gd\s\d+\s([^\s]+)%i){
    	my ($account,$login) = $input =~ m%^load gd\s(\d+)\s([^\s]+)%i;
		#my ($dbase,$folders) = $dbm->readHash();
		$services[$account] = pDrive::gDrive->new($login);
		$currentService = $account;

		$loggedInUser = $bindIP;
		for (my $i=0;$i <= $#services;$i++){
			if (defined $services[$i]){
				$loggedInUser .= ', ' if $i > 1;
				if ($currentService == $i){
					$loggedInUser .= '*'.$i. '*. ' . $services[$i]->{_username};
				}else{
					$loggedInUser .= $i. '. ' . $services[$i]->{_username};
				}

			}
		}

  	}elsif($input =~ m%^load od\s\d+\s([^\s]+)%i){
    	my ($account,$login) = $input =~ m%^load od\s(\d+)\s([^\s]+)%i;
		#my ($dbase,$folders) = $dbm->readHash();
		$services[$account] = pDrive::oneDrive->new($login);
		$currentService = $account;

		$loggedInUser = $bindIP;
		for (my $i=0;$i <= $#services;$i++){
			if (defined $services[$i]){
				$loggedInUser .= ', ' if $i > 1;
				if ($currentService == $i){
					$loggedInUser .= '*'.$i. '*. ' . $services[$i]->{_username};
				}else{
					$loggedInUser .= $i. '. ' . $services[$i]->{_username};
				}

			}
		}

	###
	# local-hash helpers
	###
	# dump the local-hash
  	}elsif($input =~ m%^dump dbm\s\S+%i){
    	my ($db) = $input =~ m%^dump dbm\s(\S+)\n%;
    	$dbm->printHash($db);

	# update the  the key
  	}elsif($input =~ m%^update dbm key\s\S+\s\S+\s\S+%i){
    	my ($db, $filter, $filterChange) = $input =~ m%^update dbm key\s(\S+)\s(\S+)\s(\S+)\n%;
    	$dbm->updateHashKey($db, $filter, $filterChange);



	# retrieve the datestamp for the last updated filr from the local-hash
  	#}elsif($input =~ m%^get last updated%i){
    	#my $maxTimestamp = $dbm->getLastUpdated($dbase);
    	#print STDOUT "maximum timestamp = ".$$maxTimestamp[pDrive::Time->A_DATE]." ".$$maxTimestamp[pDrive::Time->A_TIMESTAMP]."\n";


	# load MD5 with account data
  	}elsif($input =~ m%^get drive list all%i){
    	my $listURL;
    	($driveListings) = $services[$currentService]->getListAll();

  	}elsif($input =~ m%^set changeid%i){
    	my ($changeID) = $input =~ m%^set changeid\s([^\s]+)%i;
    	$services[$currentService]->updateChange($changeID);
		print STDOUT "changeID set to " . $changeID . "\n";

	# load MD5 with all changes
  	}elsif($input =~ m%^get changes%i){
    	my ($driveListings) = $services[$currentService]->getChangesAll();

	# load MD5 with account data of first page of results
  	}elsif($input =~ m%^get drive list%i){
    	my $listURL;
    	my ($driveListings) = $services[$currentService]->getList();

	# return the id to the root folder
  	}elsif($input =~ m%^get root id%i){
    	my ($rootID) = $services[$currentService]->getListRoot();

	# sync the entire drive in source current source with all other sources
  	}elsif($input =~ m%^sync drive%i){
    	#my ($rootID) = $services[$currentService]->getListRoot();
    	syncDrive();

	}elsif($input =~ m%^dump md5%i){
		my $dbase = $dbm->openDBM($services[$currentService]->{_db_checksum});
		$dbm->dumpHash($dbase);
		$dbm->closeDBM($dbase);

	}elsif($input =~ m%^count  dbm%i){
		my $dbase = $dbm->openDBM($services[$currentService]->{_db_checksum});
		my $count = $dbm->countHash($dbase);
		print STDOUT "hash size is records = " . $count . "\n";
		$dbm->closeDBM($dbase);
	#
  	}elsif($input =~ m%^get changeid%i){
		my $dbase = $dbm->openDBM($services[$currentService]->{_db_checksum});
		$dbm->findKey($dbase,'LAST_CHANGE');
		$dbm->closeDBM($dbase);


  	}elsif($input =~ m%^search md5%i){
    	my ($filtermd5) = $input =~ m%^search md5\s([^\s]+)%i;

		my $dbase = $dbm->openDBM($services[$currentService]->{_db_checksum});
		my $value = $dbm->findKey($dbase,$filtermd5);
		$dbm->closeDBM($dbase);
		print STDOUT "complete\n";


  	}elsif($input =~ m%^search file%i){
	    my ($filtermd5) = $input =~ m%^search file\s([^\s]+)%i;

		my $dbase = $dbm->openDBM($services[$currentService]->{_db_checksum});
		my $value = $dbm->findValue($dbase,$filtermd5);
		$dbm->closeDBM($dbase);
		print STDOUT "complete\n";


 	}elsif($input =~ m%^get download list%i){
  		my %sortedDocuments;
    	my $listURL;
    	$listURL = 'https://docs.google.com/feeds/default/private/full?showfolders=true';

   		while(1){

   			($driveListings) = $services[$currentService]->getList($listURL);

  			my $nextlistURL = $services[$currentService]->getNextURL($driveListings);
  			$nextlistURL =~ s%\&amp\;%\&%g;
  			$nextlistURL =~ s%\%3A%\:%g;

	    	$listURL = $nextlistURL;



  			($createFileURL) = $services[$currentService]->getCreateURL($driveListings) if ($createFileURL eq '');
  			my %newDocuments = $services[$currentService]->readDriveListings($driveListings);

  			foreach my $resourceID (keys %newDocuments){
		    	$sortedDocuments{$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}]} = $newDocuments{$resourceID}[pDrive::DBM->D->{'server_link'}];
	  		}
	  		last if ($listURL eq '');

  		}

  		open(OUTPUT, '>' . pDrive::Config->TMP_PATH . '/download.list') or die ('Cannot save to ' . pDrive::Config->TMP_PATH . '/download.list');
  		foreach my $resourceID (sort keys %sortedDocuments){
	    	print STDOUT $sortedDocuments{$resourceID}. "\t".$resourceID. "\n";
	#    	print OUTPUT $resourceID. "\n" . $sortedDocuments{$resourceID} . "\n";
    		print OUTPUT $resourceID. "\n" ;
  		}
  		close(OUTPUT);

	#	download only all mine documents
 	#
 	}elsif($input =~ m%^download mine%i){
  		my %sortedDocuments;
    	my $listURL;
    	$listURL = 'https://docs.google.com/feeds/default/private/full/-/mine';

   		while(1){

   			($driveListings) = $services[$currentService]->getList($listURL);

  			my $nextlistURL = $services[$currentService]->getNextURL($driveListings);
  			$nextlistURL =~ s%\&amp\;%\&%g;
  			$nextlistURL =~ s%\%3A%\:%g;

	    	$listURL = $nextlistURL;


  			($createFileURL) = $services[$currentService]->getCreateURL($driveListings) if ($createFileURL eq '');
	  		my %newDocuments = $services[$currentService]->readDriveListings($driveListings);

	  		foreach my $resourceID (keys %newDocuments){
			    $sortedDocuments{$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}]} = $newDocuments{$resourceID}[pDrive::DBM->D->{'server_link'}];
		  	}
		  	last if ($listURL eq '');

  		}

  		foreach my $resourceID (sort keys %sortedDocuments){
	    	print STDOUT $sortedDocuments{$resourceID}. "\t".$resourceID. "\n";
	    	$services[$currentService]->downloadFile($sortedDocuments{$resourceID},'./'.$resourceID,'','','');
  		}

 	}elsif($input =~ m%^download all%i){
  		my %sortedDocuments;
    	my $listURL;
    	$listURL = 'https://docs.google.com/feeds/default/private/full?showfolders=true';

   		while(1){

   			($driveListings) = $services[$currentService]->getList($listURL);

  			my $nextlistURL = $services[$currentService]->getNextURL($driveListings);
  			$nextlistURL =~ s%\&amp\;%\&%g;
  			$nextlistURL =~ s%\%3A%\:%g;

	    	$listURL = $nextlistURL;

	  		($createFileURL) = $services[$currentService]->getCreateURL($driveListings) if ($createFileURL eq '');
  			my %newDocuments = $services[$currentService]->readDriveListings($driveListings);

  			foreach my $resourceID (keys %newDocuments){
		    	$sortedDocuments{$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}]} = $newDocuments{$resourceID}[pDrive::DBM->D->{'server_link'}];
	  		}
	  		last if ($listURL eq '');

  		}

  		foreach my $resourceID (sort keys %sortedDocuments){
	    	print STDOUT $sortedDocuments{$resourceID}. "\t".$resourceID. "\n";
	    	$services[$currentService]->downloadFile($sortedDocuments{$resourceID},'./'.$resourceID,'','','');
  		}


	}elsif($input =~ m%^create dir\s[^\n]+\n%i){
    	my ($dir) = $input =~ m%^create dir\s([^\n]+)\n%;

  		my $folderID = $services[$currentService]->createFolder('https://docs.google.com/feeds/default/private/full/folder%3Aroot/contents',$dir);
    	print "resource ID = " . $folderID . "\n";


	}elsif($input =~ m%^create folder%i){
    	my ($folder) = $input =~ m%^create folder\s([^\n]+)\n%;

	  	my $folderID = $services[$currentService]->createFolder($folder);
	    print "resource ID = " . $folderID . "\n";


	# remote upload using URL (OneDrive))
	}elsif($input =~ m%^upload url%i){
    	my ($filename,$URL) = $input =~ m%^upload url \"([^\"]+)\" ([^\n]+)\n%;
		my $statusURL = $services[$currentService]->uploadRemoteFile($URL,'',$filename);
		print STDOUT $statusURL . "\n";

	}elsif($input =~ m%^upload dir list%i){
    	my ($list) = $input =~ m%^upload dir list\s([^\n]+)\n%;

		open (LIST, '<./'.$list) or  die ('cannot read file ./'.$list);
    	while (my $line = <LIST>){
		my ($dir,$folder,$filetype) = $line =~ m%([^\t]+)\t([^\t]+)\t([^\n]+)\n%;
      	print STDOUT "folder = $folder, type = $filetype\n";

      	if ($folder eq ''){
	        print STDOUT "no files\n";
        	next;
      	}
  		$services[$currentService]->uploadFolder($dir . '/'. $folder, '');

    }


  }elsif($input =~ m%^upload dir\s[^\n]+\n%i){

    my ($dir) = $input =~ m%^upload dir\s([^\n]+)\n%;
    my ($folder) = $dir =~ m%\/([^\/]+)$%;
    print STDOUT "directory = $dir\n";
    my @fileList = pDrive::FileIO::getFilesDir($dir);

    print STDOUT "folder = $folder\n";
  	my $folderID = $services[$currentService]->createFolder('https://docs.google.com/feeds/default/private/full/folder%3Aroot/contents',$folder);
    print "resource ID = " . $folderID . "\n";

    for (my $i=0; $i <= $#fileList; $i++){
		print STDOUT $fileList[$i] . "\n";

    	my ($fileName) = $fileList[$i] =~ m%\/([^\/]+)$%;

  		my $fileSize =  -s $fileList[$i];
  		my $filetype = 'application/octet-stream';
  		print STDOUT "file size for $fileList[$i] is $fileSize of type $filetype\n" if (pDrive::Config->DEBUG);

  		my $uploadURL = $services[$currentService]->createFile($createFileURL,$fileSize,$fileName,$filetype);


  		my $chunkNumbers = int($fileSize/(CHUNKSIZE))+1;
		my $pointerInFile=0;
  		print STDOUT "file number is $chunkNumbers\n" if (pDrive::Config->DEBUG);
  		open(INPUT, "<".$fileList[$i]) or die ('cannot read file '.$fileList[$i]);

  		binmode(INPUT);

  		print STDERR 'uploading chunks [' . $chunkNumbers.  "]...";
  		my $fileID=0;
  		for (my $i=0; $i < $chunkNumbers; $i++){
		    my $chunkSize = CHUNKSIZE;
		    my $chunk;
    		if ($i == $chunkNumbers-1){
      			$chunkSize = $fileSize - $pointerInFile;
    		}

    		sysread INPUT, $chunk, CHUNKSIZE;
    		print STDERR $i;
    		my $status=0;
    		my $retrycount=0;
    		while ($status eq '0' and $retrycount < 5){
			    $status = $services[$currentService]->uploadFile($uploadURL,\$chunk,$chunkSize,'bytes '.$pointerInFile.'-'.($i == $chunkNumbers-1? $fileSize-1: ($pointerInFile+$chunkSize-1)).'/'.$fileSize,$filetype);
      			print STDOUT $status . "\n";
	      		if ($status eq '0'){
        			print STDERR "retry\n";
        			sleep (5);
        			$retrycount++;
      			}

    		}
    		pDrive::masterLog("retry failed $fileList[$i]\n") if ($retrycount >= 5);

    		$fileID=$status;
		    $pointerInFile += $chunkSize;
  		}
  		close(INPUT);
  	    $services[$currentService]->addFile('https://docs.google.com/feeds/default/private/full/folder%3A'.$folderID.'/contents',$fileID);
  	    $services[$currentService]->deleteFile('root',$fileID);

  		print STDOUT "\n";
    }

  }elsif($input =~ m%^set listurl%i){


    my ($parameter) = $input =~ m%^set listurl\s+(\S+)%i;
    if ($parameter ne ''){
      $currentURL = 'https://docs.google.com/feeds/default/private/full?showfolders=true&q=after:'.$parameter;
    }else{
      $currentURL = 'https://docs.google.com/feeds/default/private/full?showfolders=true';
    }
    print STDOUT "list list URL = $currentURL\n";



  }elsif($input =~ m%^get current%i){

    my ($driveListings) = $services[$currentService]->getList($currentURL);

    ($nextURL) = $services[$currentService]->getNextURL($driveListings);
    $nextURL =~ s%\&amp\;%\&%g;
    $nextURL =~ s%\%3A%\:%g;
    $nextURL .= '&showfolders=true' if ($nextURL ne '' and !($nextURL =~ m%showfolders%));


    print STDOUT "next list URL = $nextURL\n";

  }

  if ($loggedInUser ne ''){
	print STDERR $loggedInUser.'>';
  }else{
	print STDERR '>';
  }

}

# scripted input
if ($opt{c} ne ''){
	close($userInput);
}

exit(0);

sub masterLog($){

  my $event = shift;

  my $timestamp = pDrive::Time::getTimestamp(time, 'YYYYMMDDhhmmss');
#  my $datestamp = substr($timestamp, 0, 8);

  print STDERR $event . "\n" if (pDrive::Config->DEBUG);
  open (SYSTEMLOG, '>>' . pDrive::Config->LOGFILE) or die('Cannot access application log ' . pDrive::Config->LOGFILE);
  print SYSTEMLOG HOSTNAME . ' (' . $$ . ') - ' . $timestamp . ' -  ' . $event . "\n";
  close (SYSTEMLOG);

}

sub syncDrive(){

	my $nextURL = '';
	while (1){
		my $newDocuments =  $services[$currentService]->getList($nextURL);
  		#my $newDocuments =  $services[$currentService]->readDriveListings($driveListings);
  		foreach my $resourceID (keys $newDocuments){
			print STDOUT "downloading " . $$newDocuments{$resourceID}[pDrive::DBM->D->{'server_link'}] . "\n";
	    	$services[$currentService]->downloadFile($resourceID,$$newDocuments{$resourceID}[pDrive::DBM->D->{'server_link'}],$$newDocuments{$resourceID}[pDrive::DBM->D->{'published'}]);

	  	}
  		$nextURL =  $services[$currentService]->getNextURL($driveListings);
		#$self->updateMD5Hash($newDocuments);
		print STDOUT "next url " . $nextURL . "\n";
  		last if $nextURL eq '';
  		last;
	}
	#print STDOUT $$driveListings . "\n";

}
__END__

=head1 AUTHORS

=over

=item * 2012.09 - initial - Dylan Durdle

=back
