package pDrive::amazon;

our @ISA = qw(pDrive::CloudService);

use Fcntl;


# magic numbers
use constant IS_ROOT => 1;
use constant NOT_ROOT => 0;

use constant FOLDER_TITLE => 0;
use constant FOLDER_ROOT => 1;
use constant FOLDER_PARENT => 2;
use constant FOLDER_SUBFOLDER => 3;
use constant SERVICE => 'Amazon';


my $types = {'document' => ['doc','html'],'drawing' => 'png', 'presentation' => 'ppt', 'spreadsheet' => 'xls'};

sub new(*$) {

  	my $self = {_serviceapi => undef,
               _login_dbm => undef,
              _dbm => undef,
  			  _nextURL => '',
  			  _username => undef,
  			  _folders_dbm => undef,
  			  _db_checksum => undef,
  			  _db_fisi => undef};

  	my $class = shift;
  	bless $self, $class;
	$self->{_username} = shift;
	my $skipTest = shift;
	$skipTest = False; #override, we need metaURL, must test access


	$self->{_db_checksum} = 'acd.'.$self->{_username} . '.md5.db';
	$self->{_db_fisi} = 'acd.'.$self->{_username} . '.fisi.db';


  	# initialize web connections
  	$self->{_serviceapi} = pDrive::AmazonAPI->new(pDrive::Config->ACDCLIENT_ID,pDrive::Config->ACDCLIENT_SECRET);

  	my $loginsDBM = pDrive::DBM->new('./acd.'.$self->{_username}.'.db');
  	$self->{_login_dbm} = $loginsDBM;
  	my ($token,$refreshToken) = $loginsDBM->readLogin($self->{_username});

	#$self->{_folders_dbm} =  '';# -- skip checking for folder locally $loginsDBM->openDBMForUpdating( 'acd.'.$self->{_username} . '.folders.db');


	# no token defined
	if ($token eq '' or  $refreshToken  eq ''){
		my $code;
		my  $URL = 'https://www.amazon.com/ap/oa?client_id='.pDrive::Config->ACDCLIENT_ID.'&scope=clouddrive%3Aread_all%20clouddrive%3Awrite&response_type=code&redirect_uri=http://localhost';
		print STDOUT "visit $URL\n";
		print STDOUT 'Input Code:';
		$code = <>;
		$code =~ s%\n%%;
		print STDOUT "code = $code\n";
 	  	($token,$refreshToken) = $self->{_serviceapi}->getToken($code);
	  	$self->{_login_dbm}->writeLogin($self->{_username},$token,$refreshToken);
	}else{
		$self->{_serviceapi}->setToken($token,$refreshToken);
	}

	# token expired?
	if (!!($skipTest) and !($self->{_serviceapi}->testAccess())){
		# refresh token
 	 	($token,$refreshToken) = $self->{_serviceapi}->refreshToken();
		$self->{_serviceapi}->setToken($token,$refreshToken);
	  	$self->{_login_dbm}->writeLogin($self->{_username},$token,$refreshToken);
		$self->{_serviceapi}->testAccess();
	}
	return $self;

}




sub downloadFile(*$$$){

      my ($self,$path,$link,$updated) = @_;
      my $returnStatus;
      my $finalPath = pDrive::Config->LOCAL_PATH."/$path";

      pDrive::FileIO::traverseMKDIR($finalPath);
      print STDOUT "downloading $finalPath...";
      # a simple non-google-doc file
      $returnStatus = $self->{_serviceapi}->downloadFile($finalPath,$link,$updated);

}



sub createFolder(*$$){

	my $self = shift;
	my $path = shift;

	return $self->getFolderIDByPath($path, 1);

}

sub getSubFolderID(*$$){

	my $self = shift;
	my $folderName = shift;
	my $parentID = shift;

	if  ($parentID eq 'root' or $parentID eq ''){
		$parentID = $self->{_serviceapi}->getListRoot();
	}

	my $driveListings = $self->{_serviceapi}->getSubFolderID($parentID);
  	my $newDocuments = $self->{_serviceapi}->readDriveListings($driveListings);
  	foreach my $resourceID (sort keys %{$newDocuments}){
    	if (lc $$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}] eq lc $folderName){
    		print STDERR "returning $resourceID\n " if (pDrive::Config->DEBUG);
    		return $resourceID;
    	}
	}

	my $nextToken =  $self->{_serviceapi}->getNextURL($driveListings);
	print STDERR "more results $nextToken\n " if ($nextToken ne '' and pDrive::Config->DEBUG);
	while ($nextToken ne ''){
	my $driveListings = $self->{_serviceapi}->getSubFolderID($parentID, '', $nextToken);
  	my $newDocuments = $self->{_serviceapi}->readDriveListings($driveListings);
	$nextToken =  $self->{_serviceapi}->getNextURL($driveListings);

  	foreach my $resourceID (keys %{$newDocuments}){
    	if (lc $$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}] eq lc $folderName){
    		print STDERR "returning $resourceID\n " if (pDrive::Config->DEBUG);
    		return $resourceID;
    	}
	}
	}
	return '';

}

sub getFolderSize(*$$){

	my $self = shift;
	my $folderID = shift;
	my $tempDBM = shift;

	my $nextURL='';

	#last run failed to finish, attempt to continue where left
	my $driveListings;
	my $folderSize = 0;
	my $fileCount = 0;
	my $duplicateSize = 0;
	my $duplicateCount = 0;

	while (1){
		$driveListings = $self->{_serviceapi}->getSubFolderIDList($folderID, $nextURL);
  		$nextURL = $self->{_serviceapi}->getNextURL($driveListings);
  		my $newDocuments = $self->{_serviceapi}->readDriveListings($driveListings);


  		foreach my $resourceID (keys %{$newDocuments}){
	  			#	folder
  				 if  ($$newDocuments{$resourceID}[pDrive::DBM->D->{'server_fisi'}] eq ''){
			    	print STDERR "." if $self->{_realtime_updates};
  				 	($size, $count, $dSize, $dCount) = $self->getFolderSize($resourceID, $tempDBM);
			    	print STDERR "\b \b" if $self->{_realtime_updates};
  				 	$folderSize += $size;
  				 	$fileCount += $count + 1;
  				 	$duplicateSize += $dSize;
  				 	$duplicateCount += $dCount;
  			 	}else{
  			 		if ($$tempDBM{$$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}]} >= 1){
	  				 	$duplicateSize +=  $$newDocuments{$resourceID}[pDrive::DBM->D->{'size'}];
	  				 	$duplicateCount++;
	  				 	$$tempDBM{$$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}]}++;
  			 		}else{
	  				 	$folderSize +=  $$newDocuments{$resourceID}[pDrive::DBM->D->{'size'}];
	  				 	$fileCount++;
	  				 	$$tempDBM{$$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}]}++;
  			 		}
  				}

  		}

		#print STDOUT "next url " . $nextURL . "\n";
  		last if $nextURL eq '';
	}
	return ($folderSize,$fileCount, $duplicateSize, $duplicateCount);
}

sub getSubFolderIDList(*$$){

	my $self = shift;
	my $folderName = shift;
	my $URL = shift;

	if ($URL eq ''){
		$URL =   $self->{_serviceapi}->{_metaURL};
		$URL .= 'nodes/'.$folderName . '/children?';
	}

	my $driveListings = $self->{_serviceapi}->getList($URL);
  	my $newDocuments = $self->{_serviceapi}->readDriveListings($driveListings);
	#disabled???
	$self->{_nextURL} =  $self->{_serviceapi}->getNextURL($driveListings);
	#$self->updateMD5Hash($newDocuments);
	return $newDocuments;

}

sub uploadFolder(*$$){
	my $self = shift;
	my $localPath = shift;
	my $serverPath = shift;

    my ($folder) = $localPath =~ m%\/([^\/]+)$%;

#	if ($serverPath ne ''){
		$serverPath .= $folder;
#	}
  	print STDOUT "path = $localPath\n";
   	my @fileList = pDrive::FileIO::getFilesDir($localPath);

	print STDOUT "folder = $folder\n" if (pDrive::Config->DEBUG);

	#check server-cache for folder
	my $folderID =  '';# -- skip checking for folder locally $self->{_login_dbm}->findFolder($self->{_folders_dbm}, $serverPath);
	#folder doesn't exist, create it
	if ($folderID eq ''){
		$folderID = $self->getFolderIDByPath($localPath, 1);
	}


	print "resource ID = " . $folderID . "\n";

    for (my $i=0; $i <= $#fileList; $i++){

    	#empty file; skip
    	if (-z $fileList[$i]){
			next;
    	#folder
    	}elsif (-d $fileList[$i]){
	  		my $fileID = $self->uploadFolder($fileList[$i], $serverPath);
    	# file
    	}else{
    		my $process = 1;
    		#look for md5 file
    		for (my $j=0; $j <= $#fileList; $j++){
    			my $value = $fileList[$i];
    			my ($file,$md5) = $fileList[$j] =~ m%[^\/]+\/\.(.*?)\.([^\.]+)$%;
    			my ($currentFile) = $fileList[$i] =~ m%\/([^\/]+)$%;

    			if ($file eq $currentFile and $md5 ne ''){
    				tie(my %dbase, pDrive::Config->DBM_TYPE, $self->{_db_checksum} ,O_RDONLY, 0666) or die "can't open md5: $!";
    				if (  (defined $dbase{$md5.'_'} and $dbase{$md5.'_'} ne '') or (defined $dbase{$md5.'_0'} and $dbase{$md5.'_0'} ne '')){
    					$process = 0;
				    	#pDrive::masterLog("skipped file (checksum $md5 exists ".$dbase{$md5.'_0'}.") - $fileList[$i]\n");
    					last;
	    			}
    				untie(%dbase);
    			}
    		}
    		#calculate the fisi
			my ($fileName) = $fileList[$i] =~ m%\/([^\/]+)$%;
			my $fileSize = -s $fileList[$i];
 			my $fisi = pDrive::FileIO::getMD5String($fileName .$fileSize);
    		tie(my %dbase, pDrive::Config->DBM_TYPE, $self->{_db_fisi} ,O_RDONLY, 0666) or die "can't open fisi: $!";
    		if (  (defined $dbase{$fisi.'_'} and $dbase{$fisi.'_'} ne '') or (defined $dbase{$fisi.'_0'} and $dbase{$fisi.'_0'} ne '')){
    					$process = 0;
				    	#pDrive::masterLog("skipped file (fisi $fisi exists ".$dbase{$fisi.'_0'}.") - $fileList[$i]\n");
	    	}
    		untie(%dbase);
			if ($process){
				print STDOUT "Upload $fileList[$i]\n";
		  		my $fileID = $self->uploadFile($fileList[$i], $folderID);
    		}else{
				print STDOUT "SKIP $fileList[$i]\n";
	    	}
    	}
	  	print STDOUT "\n";
	}
}

sub uploadFTPFolder(*$$){
	my $self = shift;
	my $localPath = shift;
	my $serverPath = shift;

    my ($folder) = $localPath =~ m%\/([^\/]+)$%;

#	if ($serverPath ne ''){
		$serverPath .= $folder;
#	}
  	print STDOUT "path = $localPath\n";
   	my @fileList = pDrive::FileIO::getFilesDir($localPath);

	print STDOUT "folder = $folder\n" if (pDrive::Config->DEBUG);

	#check server-cache for folder
	my $folderID =  '';# -- skip checking for folder locally $self->{_login_dbm}->findFolder($self->{_folders_dbm}, $serverPath);
	#folder doesn't exist, create it
	if ($folderID eq ''){
		$folderID = $self->getFolderIDByPath($localPath, 1);
	}


	print "resource ID = " . $folderID . "\n";

    for (my $i=0; $i <= $#fileList; $i++){

    	#empty file; skip
    	if (-z $fileList[$i]){
			next;
    	#folder
    	}elsif (-d $fileList[$i]){
	  		my $fileID = $self->uploadFolder($fileList[$i], $serverPath);
    	# file
    	}else{

	    	#check if file is updating
	    	my $fileSize = -s $fileList[$i];
	    	sleep 5;
	    	if ($fileSize != -s $fileList[$i] or $fileSize == 0 ){
				print STDOUT "SKIP $fileList[$i], still increasing or 0 byte file\n";
				next;
	    	}
    		my $process = 1;
    		#look for md5 file
    		for (my $j=0; $j <= $#fileList; $j++){
    			my $value = $fileList[$i];
    			my ($file,$md5) = $fileList[$j] =~ m%[^\/]+\/\.(.*?)\.([^\.]+)$%;
    			my ($currentFile) = $fileList[$i] =~ m%\/([^\/]+)$%;

    			if ($file eq $currentFile and $md5 ne ''){
    				tie(my %dbase, pDrive::Config->DBM_TYPE, $self->{_db_checksum} ,O_RDONLY, 0666) or die "can't open md5: $!";
    				if (  (defined $dbase{$md5.'_'} and $dbase{$md5.'_'} ne '') or (defined $dbase{$md5.'_0'} and $dbase{$md5.'_0'} ne '')){
    					$process = 0;
				    	#pDrive::masterLog("skipped file (checksum $md5 exists ".$dbase{$md5.'_0'}.") - $fileList[$i]\n");
    					last;
	    			}
    				untie(%dbase);
    			}
    		}
    		#calculate the fisi
			my ($fileName) = $fileList[$i] =~ m%\/([^\/]+)$%;
			my $fileSize = -s $fileList[$i];
 			my $fisi = pDrive::FileIO::getMD5String($fileName .$fileSize);
    		tie(my %dbase, pDrive::Config->DBM_TYPE, $self->{_db_fisi} ,O_RDONLY, 0666) or die "can't open fisi: $!";
    		if (  (defined $dbase{$fisi.'_'} and $dbase{$fisi.'_'} ne '') or (defined $dbase{$fisi.'_0'} and $dbase{$fisi.'_0'} ne '')){
    					$process = 0;
				    	#pDrive::masterLog("skipped file (fisi $fisi exists ".$dbase{$fisi.'_0'}.") - $fileList[$i]\n");
	    	}
    		untie(%dbase);
			if ($process){
				print STDOUT "Upload $fileList[$i]\n";
		  		my $fileID = $self->uploadFile($fileList[$i], $folderID);
    		}else{
				print STDOUT "SKIP $fileList[$i]\n";
	    	}
    	}
	  	print STDOUT "\n";
	}
}


sub createUploadListForFolder(*$$$$){
	my $self = shift;
	my $localPath = shift;
	my $serverPath = shift;
	my $parentFolder = shift;
	my $listHandler = shift;

    my ($folder) = $localPath =~ m%\/([^\/]+)$%;

#	if ($serverPath ne ''){
		$serverPath .= $folder;
#	}
  	print STDOUT "path = $localPath\n";
   	my @fileList = pDrive::FileIO::getFilesDir($localPath);

	print STDOUT "folder = $folder\n" if (pDrive::Config->DEBUG);

	#check server-cache for folder
	my $folderID =  '';# -- skip checking for folder locally $self->{_login_dbm}->findFolder($self->{_folders_dbm}, $serverPath);
	#folder doesn't exist, create it
	if ($folderID eq ''){
		#*** validate it truly doesn't exist on the server before creating
		#this is the parent?
		if ($parentFolder eq ''){
			#look at the root
			#get root's children, look for folder as child
			$folderID = $self->getSubFolderID($folder,'root');
		}else{
			#look at the parent
			#get parent's children, look for folder as child
			$folderID = $self->getSubFolderID($folder,$parentFolder);
		}
		if ($folderID eq '' and $parentFolder ne ''){
			$folderID = $self->createFolder($folder, $parentFolder);
		}elsif ($folderID eq '' and  $parentFolder eq ''){
			$folderID = $self->createFolder($folder, 'root');
		}
		#--skip $self->{_login_dbm}->addFolder($self->{_folders_dbm}, $serverPath, $folderID) if ($folderID ne '');
	}



	print "resource ID = " . $folderID . "\n";

    for (my $i=0; $i <= $#fileList; $i++){

    	#empty file; skip
    	if (-z $fileList[$i]){
			next;
    	#folder
    	}elsif (-d $fileList[$i]){
	  		my $fileID = $self->createUploadListForFolder($fileList[$i], $serverPath, $folderID, $listHandler);
    	# file
    	}else{
    		my $process = 1;
    		#look for md5 file
    		for (my $j=0; $j <= $#fileList; $j++){
    			my $value = $fileList[$i];
    			my ($file,$md5) = $fileList[$j] =~ m%[^\/]+\/\.(.*?)\.([^\.]+)$%;
    			my ($currentFile) = $fileList[$i] =~ m%\/([^\/]+)$%;

    			if ($file eq $currentFile and $md5 ne ''){
    				tie(my %dbase, pDrive::Config->DBM_TYPE, $self->{_db_checksum} ,O_RDONLY, 0666) or die "can't open md5: $!";
    				if (  (defined $dbase{$md5.'_'} and $dbase{$md5.'_'} ne '') or (defined $dbase{$md5.'_0'} and $dbase{$md5.'_0'} ne '')){
    					$process = 0;
    					last;
	    			}
    				untie(%dbase);
    			}
    		}
			if ($process){
				print STDOUT "Upload $fileList[$i]\n";
				print {$listHandler} "$fileList[$i]	$folderID\n";

    		}else{
				print STDOUT "SKIP $fileList[$i]\n";
	    	}
    	}
	  	print STDOUT "\n";
	}
}

#
# get list of the content in the Google Drive
##
sub getFolderInfo(*$){

	my $self = shift;
	my $id = shift;

	my $hasMore=1;
	my $title;
	my $path = -1;
	while ($hasMore){
		print STDOUT "ID = $id\n" if (pDrive::Config->DEBUG);

		($hasMore, $title,$id) = $self->{_serviceapi}->getFolderInfo($id);
		if ($path == -1){
			$path = $title;
		}else{
			$path = $title  . '/' . $path;
		}
#	    	print STDOUT "path = $path, title = $title, id = $id\n";
	}
	return $path;
}

sub uploadFile(*$$$){

	my $self = shift;
	my $file = shift;
	my $folder = shift;
	my $fileName = shift;


	print STDOUT $file . "\n";

  	my $fileSize =  -s $file;
  	return 0 if $fileSize == 0;
  	print STDOUT "file size for $file ($fileName)  is $fileSize to folder $folder\n" if (pDrive::Config->DEBUG);

	my $status = $self->{_serviceapi}->uploadFile($file,$folder, $fileName);
	print STDOUT "\r"  . $status;

}

sub getList(*){

	my $self = shift;
	my $driveListings = $self->{_serviceapi}->getList($self->{_nextURL});
  	my $newDocuments = $self->{_serviceapi}->readDriveListings($driveListings);

#  	foreach my $resourceID (keys $newDocuments){
 #   	print STDOUT 'new document -> '.$$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}] . ', '. $$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}] . "\n";
#	}

	#print STDOUT $$driveListings . "\n";
	#disabled???
	$self->{_nextURL} =  $self->{_serviceapi}->getNextURL($driveListings);
	#$self->updateMD5Hash($newDocuments);
	return $newDocuments;
}


sub getListRoot(*){

	my $self = shift;
	print STDOUT "root = " . $self->{_serviceapi}->getListRoot('') . "\n";

}

sub getListAll(*){

	my $self = shift;

	my $nextToken = '';
	while (1){
		my $driveListings = $self->{_serviceapi}->getList('', $nextToken);
  		my $newDocuments = $self->{_serviceapi}->readDriveListings($driveListings);
  		$nextToken = $self->{_serviceapi}->getNextURL($driveListings);
		$self->updateMD5Hash($newDocuments);
		print STDOUT "next url " . $nextToken . "\n";
  		last if $nextToken eq '';
	}

}


sub readDriveListings(**){

	my $self = shift;
	my $driveListings = shift;
	return $self->{_serviceapi}->readDriveListings($driveListings);

}

sub getChangesAll(*){

	my $self = shift;
	my $changeID;
    if (tie(my %dbase, pDrive::Config->DBM_TYPE, $self->{_db_checksum} ,O_RDONLY, 0666)){
    	$changeID = $dbase{'LAST_CHANGE'};
    	print STDOUT "changeID = " . $changeID . "\n";
    	untie(%dbase);
    }

	my $driveListings = $self->{_serviceapi}->getChanges($changeID);

	$changeID = $self->{_serviceapi}->getChangeID($driveListings);
	print STDOUT "new changeID = " . $changeID . "\n";
  	my $newDocuments = $self->{_serviceapi}->readChangeListings($driveListings);
	$self->updateMD5Hash($newDocuments);
	$self->updateChange($changeID);

}

sub updateMD5Hash(**){

	my $self = shift;
	my $newDocuments = shift;

	my $createdCountMD5=0;
	my $skippedCountMD5=0;
	my $createdCountFISI=0;
	my $skippedCountFISI=0;
	tie(my %dbase, pDrive::Config->DBM_TYPE, $self->{_db_checksum} ,O_RDWR|O_CREAT, 0666) or die "can't open md5: $!";
	foreach my $resourceID (keys %{$newDocuments}){
		next if $$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}] eq '';
		for (my $i=0; 1; $i++){
			# if MD5 exists,
			if (defined $dbase{$$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}].'_'. $i}){
				# validate it is the same file, if so, skip, otherwise move onto another md5 slot
				if  ($dbase{$$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}].'_'. $i}  eq $resourceID){
					$skippedCountMD5++;
					last;
				}else{
					#move onto next slot
				}
			#	create
			}else{
				$dbase{$$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}].'_'. $i} = $resourceID;
				$createdCountMD5++;
				last;
			}
		}
	}
	untie(%dbase);
	tie( %dbase, pDrive::Config->DBM_TYPE, $self->{_db_fisi} ,O_RDWR|O_CREAT, 0666) or die "can't open fisi: $!";
	foreach my $resourceID (keys %{$newDocuments}){
		next if $$newDocuments{$resourceID}[pDrive::DBM->D->{'server_fisi'}] eq '';
		for (my $i=0; 1; $i++){
			# if MD5 exists,
			if (defined $dbase{$$newDocuments{$resourceID}[pDrive::DBM->D->{'server_fisi'}].'_'. $i}){
				# validate it is the same file, if so, skip, otherwise move onto another md5 slot
				if  ($dbase{$$newDocuments{$resourceID}[pDrive::DBM->D->{'server_fisi'}].'_'. $i}  eq $resourceID){
					$skippedCountFISI++;
					last;
				}else{
					#move onto next slot
				}
			#	create
			}else{
				$dbase{$$newDocuments{$resourceID}[pDrive::DBM->D->{'server_fisi'}].'_'. $i} = $resourceID;
				$createdCountFISI++;
				last;
			}
		}
	}
	untie(%dbase);
	print STDOUT "MD5: created = $createdCountMD5, skipped = $skippedCountMD5\n";
	print STDOUT "FISI: created = $createdCountFISI, skipped = $skippedCountFISI\n";


}




sub getFolderIDByPath(*$$){

	my $self = shift;
	my $path = shift;
	my $doCreate = shift;

	my $parentFolder= '';
	my $folderID;

	#remove double // occurrences (make single /)
	$path =~ s%\/\/%\/%g;

	my $serverPath = '';
	while(my ($folder) = $path =~ m%^\/?([^\/]+)%){

    	$path =~ s%^\/?[^\/]+%%;
		$serverPath .= $folder;

		#check server-cache for folder
		$folderID =  '';# -- skip checking for folder locally $self->{_login_dbm}->findFolder($self->{_folders_dbm}, $serverPath);
		#	folder doesn't exist, create it
		if ($folderID eq ''){
			#*** validate it truly doesn't exist on the server before creating
			#this is the parent?
			if ($parentFolder eq ''){
				#look at the root
				#	get root's children, look for folder as child
				$folderID = $self->getSubFolderID($folder,'root');
				$parentFolder =$folderID if ($folderID ne '');
			}else{
				#look at the parent
				#get parent's children, look for folder as child
				$folderID = $self->getSubFolderID($folder,$parentFolder);
				$parentFolder =$folderID if ($folderID ne '');
			}

			if ($folderID eq '' and $parentFolder ne ''){
				$folderID =$self->{_serviceapi}->createFolder($folder, $parentFolder) if $doCreate;
				$parentFolder =$folderID if ($folderID ne '');
			}elsif ($folderID eq '' and  $parentFolder eq ''){
				$folderID = $self->{_serviceapi}->createFolder($folder, '') if $doCreate;
				$parentFolder =$folderID if ($folderID ne '');
			}
			#	$self->{_login_dbm}->addFolder($self->{_folders_dbm}, $serverPath, $folderID) if ($folderID ne '');
		}

	}
	return $folderID;

}


1;

