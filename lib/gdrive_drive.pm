package pDrive::gDrive;


# magic numbers
use constant IS_ROOT => 1;
use constant NOT_ROOT => 0;

use constant FOLDER_TITLE => 0;
use constant FOLDER_ROOT => 1;
use constant FOLDER_PARENT => 2;
use constant FOLDER_SUBFOLDER => 3;


#my $types = {'document' => ['doc','html'],'drawing' => 'png', 'pdf' => 'pdf','presentation' => 'ppt', 'spreadsheet' => 'xls'};
my $types = {'document' => ['doc','html'],'drawing' => 'png', 'presentation' => 'ppt', 'spreadsheet' => 'xls'};
#my $types = {'document' => ['doc','html'],'drawing' => 'png', 'presentation' => 'ppt', 'spreadsheet' => 'xls'};

sub new(*$$) {

  	my $self = {_gdrive => undef,
              _listURL => undef,
               _login_dbm => undef,
              _dbm => undef};

  	my $class = shift;
  	bless $self, $class;
	my $username = pDrive::Config->USERNAME;


  	# initialize web connections
  	$self->{_gdrive} = pDrive::GoogleDriveAPI2->new(pDrive::Config->CLIENT_ID,pDrive::Config->CLIENT_SECRET);

  	my $loginsDBM = pDrive::DBM->new('/tmp/test.db');
#  	my $loginsDBM = pDrive::DBM->new(pDrive::Config->DBM_LOGIN_FILE);
  	$self->{_login_dbm} = $loginsDBM;
  	my ($token,$refreshToken) = $loginsDBM->readLogin($username);

	# no token defined
	if ($token eq '' or  $refreshToken  eq ''){
		my $code;
		my  $URL = 'https://accounts.google.com/o/oauth2/auth?scope=drive.readonly&redirect_uri=urn:ietf:wg:oauth:2.0:oob&response_type=code&client_id='.pDrive::Config->CLIENT_ID;
		print STDOUT "visit $URL\n";
		print STDOUT 'Input Code:';
		$code = <>;
		print STDOUT "code = $code\n";
 	  	($token,$refreshToken) = $self->{_gdrive}->getToken($code);
	  	$self->{_login_dbm}->writeLogin($username,$token,$refreshToken);
	}else{
		$self->{_gdrive}->setToken($token,$refreshToken);
	}

	# token expired?
	if (!($self->{_gdrive}->testAccess())){
		# refresh token
 	 	($token,$refreshToken) = $self->{_gdrive}->refreshToken();
	  	$self->{_login_dbm}->writeLogin($username,$token,$refreshToken);
	}
	return $self;

}


sub uploadFile(*$$){

	my $self = shift;
	my $file = shift;
	my $URL = shift;

	# get filesize
	my $fileSize = -s $file;

	open(INPUT, "<".$file) or die ('cannot read file '.$file);
	binmode(INPUT);
	my $fileContents;

  	# - don't slurp the entire file
	#my $fileContents = do { local $/; <INPUT> };
	#my $fileSize = length $fileContents;
	print STDOUT "file size for $file is $fileSize\n" if (pDrive::Config->DEBUG);

	# create file on server
	my $uploadURL = $self->{_gdrive}->createFile($URL,$fileSize);

	# calculate the number of chunks
	my $chunkNumbers = int($fileSize/(CHUNKSIZE))+1;
	my $pointerInFile=0;
	print STDOUT "file number is $chunkNumbers\n" if (pDrive::Config->DEBUG);
	for (my $i=0; $i < $chunkNumbers; $i++){
		my $chunkSize = CHUNKSIZE;
    	my $chunk;
    	if ($i == $chunkNumbers-1){
      		$chunkSize = $fileSize - $pointerInFile;
    	}
	# read chunk from file
    read INPUT, $chunk, $chunkSize;

   	# - don't slurp the entire file
	#$chunk = substr($fileContents, $pointerInFile, $chunkSize);

    print STDOUT 'uploading chunk ' . $i.  "\n";
    $self->{_gdrive}->uploadFile($uploadURL,\$chunk,$chunkSize,'bytes '.$pointerInFile.'-'.($i == $chunkNumbers-1? $fileSize-1: ($pointerInFile+$chunkSize-1)).'/'.$fileSize);
    print STDOUT 'next location = '.$uploadURL."\n";
    $pointerInFile += $chunkSize;

  }
  close(INPUT);

}

sub traverseFolder($){

  my $resourceID = shift;

  for (my $i=FOLDER_SUBFOLDER; $i <= $#{${$folders}{$resourceID}}; $i++){

    print STDOUT "\t $$folders{$$folders{$resourceID}[$i]}[FOLDER_TITLE]\n";

    if ( $#{${$folders}{${$folders}{$resourceID}}} >= FOLDER_SUBFOLDER ){
      &traverseFolder($$folders{$resourceID}[$i]);
    }

  }

}


sub getPath($$$){

  my ($folders,$resourceID,@parentArray) = @_;

  if (containsFolder($resourceID,@parentArray)){

    print STDOUT "cyclical error $$folders{$resourceID}[FOLDER_TITLE]\n";
    return '';

  }
  # end of recurrsion -- root
  if (defined $resourceID and defined $$folders{$resourceID}[FOLDER_ROOT] and $$folders{$resourceID}[FOLDER_ROOT] == IS_ROOT){

    $parentArray[$#parentArray+1] = $resourceID;
    return '/'.$$folders{$resourceID}[FOLDER_TITLE].'/';

  }elsif (defined $resourceID and defined $$folders{$resourceID}[FOLDER_PARENT] and $$folders{$resourceID}[FOLDER_PARENT] eq ''){
    return '/';

  } else{

    $parentArray[$#parentArray+1] = $resourceID;
    if (defined $resourceID and defined $$folders{$resourceID}[FOLDER_TITLE]){
      return &getPath($folders,$$folders{$resourceID}[FOLDER_PARENT],@parentArray) . $$folders{$resourceID}[FOLDER_TITLE].'/';
    }else{
      return '/';
    }

  }

}


sub containsFolder($$){
  my ($resourceID,@parentArray) = @_;

  for (my $i=0; $i <= $#parentArray; $i++){
    return 1 if $resourceID eq $parentArray[$i];
  }

  return 0;

}





sub downloadFile(*$$$$$$*){

      my ($self,$path,$link,$updated,$resourceType,$resourceID,$dbase,$updatedList) = @_;
      print STDOUT "downloading $path...\n";
      my $returnStatus;
      my $finalPath = $path;

      pDrive::FileIO::traverseMKDIR(pDrive::Config->LOCAL_PATH."/$path");

      # a simple non-google-doc file
      if ($types->{$resourceType} eq ''){
        my $appendex='';
        print STDOUT 'download using writely - '. $resourceType . $types->{$resourceType} if (pDrive::Config->DEBUG);
        if (scalar (keys %{${$dbase}{$path}}) > 1){
          $appendex .= '.'.$resourceID;
          $finalPath .= '.'.$resourceID;
        }
        if (pDrive::Config->REVISIONS and defined $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_revision'}] and $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_revision'}] ne ''){
          $appendex .= '.(local_revision_'.$$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_revision'}].')';
          $finalPath .= '.(local_revision_'.$$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_revision'}].')';
        }

        $returnStatus = $self->{_gdrive}->downloadFile($link,$path,'',$appendex,$updated);
      # a google-doc file
      }else{
        print STDOUT 'download using '.$types->{$resourceType}.' wise - '. $resourceType  if (pDrive::Config->DEBUG);


        # are there multiple filetypes noted for the export?
        if (ref($types->{$resourceType}) eq 'ARRAY'){
          for (my $i=0; $i <= $#{$types->{$resourceType}}; $i++){
            my $appendex='';
            if (scalar (keys %{${$dbase}{$path}}) > 1){
              $appendex .= '.'.$resourceID;
              $finalPath .= '.'.$resourceID;
            }
            if (pDrive::Config->REVISIONS and $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_revision'}] ne ''){
              $appendex .= '.local_revision_'.$$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_revision'}];
              $finalPath .= '.local_revision_'.$$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_revision'}];
            }
#wise
            $returnStatus = $self->{_gdrive}->downloadFile($link.'&exportFormat='.$types->{$resourceType}[$i],$path,$types->{$resourceType}[$i],$appendex,$updated);
          }
        }else{
          my $appendex='';
          if (scalar (keys %{${$dbase}{$path}}) > 1){
            $appendex .= '.'.$resourceID;
            $finalPath .= '.'.$resourceID;
          }
          if (pDrive::Config->REVISIONS and $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_revision'}] ne ''){
            $appendex .= '.(local_revision_'.$$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_revision'}].')';
            $finalPath .= '.(local_revision_'.$$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_revision'}].')';
          }
#wise
          $returnStatus = $self->{_gdrive}->downloadFile($link.'&exportFormat='.$types->{$resourceType},$path,$types->{$resourceType},$appendex,$updated);
        }

        #ignore export if fails; just try to download
        # noticed some spreadsheets in XLSX will fail with exportFormat, but download fine (and in XSLX otherwise)
        if ($returnStatus == 0){
          my $appendex='';
          if (scalar (keys %{${$dbase}{$path}}) > 1){
            $appendex .= '.'.$resourceID;
            $finalPath .= '.'.$resourceID;
          }
          if (pDrive::Config->REVISIONS and $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_revision'}] ne ''){
            $appendex .= '.(local_revision_'.$$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_revision'}].')';
            $finalPath .= '.(local_revision_'.$$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_revision'}].')';
          }
#wise
          $returnStatus = $self->{_gdrive}->downloadFile($link,$path,$types->{$resourceType},$appendex,$updated);
        }
      }

      # successful?  update the db
      if ($returnStatus == 1){

        $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_updated'}] = $updated;
        $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'server_updated'}] = $updated;
        $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_md5'}] = pDrive::FileIO::getMD5(pDrive::Config->LOCAL_PATH.'/'.$finalPath);

        if ($$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_md5'}] ne $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'server_md5'}]){
          print STDOUT "MD5 check failed!!!\n";
          pDrive::masterLog("$finalPath $resourceID - MD5 check failed -- $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_md5'}] - $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'server_md5'}]");
        }

        if (pDrive::Config->REVISIONS){
          $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_revision'}]++;
        }
#        $updatedList[$#updatedList++] = $path;
        if ($#{$updatedList} >= 0){
          $$updatedList[$#{$updatedList}++] = $path;
        }else{
          $$updatedList[0] = $path;
        }

        $self->{_dbm}->writeValueContainerHash($path,$resourceID,$dbase);
      }elsif($returnStatus == 0){
        #TBD
      }
}


sub isNewResourceID($*){
  my ($resourceID,$dbase) = @_;

  if (not defined $resourceID or $$dbase{$resourceID} eq ''){
    return 1;
  }else{
    return 0;
  }
}

sub getPathResourceID($*){

  my ($resourceID,$dbase) = @_;

  return $$dbase{$resourceID};

}


sub createFolder(*$){

	my $self = shift;
	my $folder = shift;

	return $self->{_gdrive}->createFolder('https://www.googleapis.com/drive/v2/files?fields=id',$folder);

}

sub getList(**){

	my $self = shift;
	my $folders = shift;
	my $driveListings = $self->{_gdrive}->getList('');


  	my $newDocuments = $self->{_gdrive}->readDriveListings($driveListings,$folders);

  	foreach my $resourceID (keys $newDocuments){
    	print STDOUT 'new document -> '.$$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}] . ', '. $$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}] . "\n";
	}

	#print STDOUT $$driveListings . "\n";
	print STDOUT "next url " . $self->{_gdrive}->getNextURL($driveListings) . "\n";
	$self->updateMD5Hash($newDocuments);
}


sub getListAll(**){

	my $self = shift;
	my $folders = shift;

	my $nextURL = '';
	while (1){
		my $driveListings = $self->{_gdrive}->getList($nextURL);
  		my $newDocuments = $self->{_gdrive}->readDriveListings($driveListings,$folders);
  		$nextURL = $self->{_gdrive}->getNextURL($driveListings);
		$self->updateMD5Hash($newDocuments);
		print STDOUT "next url " . $nextURL . "\n";
  		last if $nextURL eq '';
	}
	#print STDOUT $$driveListings . "\n";

}

sub updateMD5Hash(**){

	my $self = shift;
	my $newDocuments = shift;

pDrive::Config->DBM_TYPE;
use Fcntl;
print STDOUT "new document = $newDocuments\n";
	my $count=0;
	tie(my %dbase, pDrive::Config->DBM_TYPE, '/tmp/md5.db' ,O_RDWR|O_CREAT, 0666) or die "can't open md5: $!";
	foreach my $resourceID (keys $newDocuments){
		next if $$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}] eq '';
		for (my $i; 1; $i++){
			# if MD5 exists,
			if (defined $dbase{$$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}].'_'. $i}){
				# validate it is the same file, if so, skip, otherwise move onto another md5 slot
				if  ($dbase{$$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}].'_'. $i}  eq $resourceID){
					print STDOUT "skipped\n";
					last;
				}else{
					#move onto next slot
				}
			#	create
			}else{
				$dbase{$$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}].'_'. $i} = $resourceID;
				print STDOUT "created\n";
				last;
			}
		}
	}
	untie(%dbase);

}





sub updateDocuments(***){

	my $self = shift;
	my $folders = shift;
	my $newDocuments = shift;


my $count=0;
foreach my $resourceID (keys %newDocuments){


  my @parentArray = (0);
  my $path =  &getPath($folders,$newDocuments{$resourceID}[pDrive::DBM->D->{'parent'}]).$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}];

  print STDOUT "path = $path\n";

    # never existed with this path
    if ($$dbase{$path}{$resourceID}[pDrive::DBM->D->{'server_updated'}] eq ''){
      print STDOUT "new $path $resourceID".pDrive::DBM->D->{'server_updated'}." ".$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}]."\n";
      # never existed before - new file
      if (pDrive::gDrive::isNewResourceID($resourceID, \%resourceIDHash)){

        # save file information
        #$$dbase{$path}{$resourceID}[pDrive::DBM->D->{'server_updated'}] = $newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}];
        $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'server_link'}] = $newDocuments{$resourceID}[pDrive::DBM->D->{'server_link'}];
        $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'server_edit'}] = $newDocuments{$resourceID}[pDrive::DBM->D->{'server_edit'}];
        $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'server_md5'}] = $newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}];
        $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'type'}] = $newDocuments{$resourceID}[pDrive::DBM->D->{'type'}];
        $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'published'}] = $newDocuments{$resourceID}[pDrive::DBM->D->{'published'}];
        $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'title'}] = $newDocuments{$resourceID}[pDrive::DBM->D->{'title'}];

        # file exists locally
        if ($$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_updated'}] eq '' and -e pDrive::Config->LOCAL_PATH.'/'.$path){

          my $md5 = pDrive::FileIO::getMD5(pDrive::Config->LOCAL_PATH.'/'.$path);
          #is it the same as the server? -- skip file
          if ($newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}] eq $md5 and $md5 ne '0'){
            print STDOUT 'skipping (found file on local)'. "\n" if (pDrive::Config->DEBUG);
            $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_updated'}] = $newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}];
            $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'server_updated'}] = $newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}];
            $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_md5'}] = $md5;
        if ($#{$updatedList} >= 0){
          $updatedList[$#{$updatedList}++] = $path;
        }else{
          $updatedList[0] = $path;
        }
            $count++;
          #download the file -- potential conflict
          }else{
            print STDOUT 'potential conflict'  . "\n" if (pDrive::Config->DEBUG);
            pDrive::masterLog("$path $resourceID - potential conflict -- $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_md5'}] - $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'server_md5'}]");
            eval {
            $self->downloadFile($path,$newDocuments{$resourceID}[pDrive::DBM->D->{'server_link'}],$newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}],$newDocuments{$resourceID}[pDrive::DBM->D->{'type'}],$resourceID,$dbase,\@updatedList);
            1;
            } or do {
              pDrive::masterLog("$path $resourceID - download failedlict -- $@");
            };

          }
        # download file
        }elsif ($$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_updated'}] eq '' or $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'server_updated'}] eq ''or pDrive::Time::isNewerTimestamp($newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}],$$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_updated'}])){
          eval {
          $self->downloadFile($path,$newDocuments{$resourceID}[pDrive::DBM->D->{'server_link'}],$newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}],$newDocuments{$resourceID}[pDrive::DBM->D->{'type'}],$resourceID,$dbase,\@updatedList);
            1;
            } or do {
              pDrive::masterLog("$path $resourceID - download failedlict -- $@");
            };
          $count++;
        }
      }else{
        print STDOUT "existed\n";
      }

    # file missing local db information only
#   }elsif($$dbase{$path}{$resourceID}[pDrive::DBM->D->{'local_updated'}] ne ''){

    # file is newer on the server; download
    }elsif (pDrive::Time::isNewerTimestamp($newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}],${$dbase}{$path}{$resourceID}[pDrive::DBM->D->{'local_updated'}])){
      print STDOUT "newer on server ".$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}]."\n";
      $$dbase{$path}{$resourceID}[pDrive::DBM->D->{'server_md5'}] = $newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}];
      $self->downloadFile($path,$newDocuments{$resourceID}[pDrive::DBM->D->{'server_link'}],$newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}],$newDocuments{$resourceID}[pDrive::DBM->D->{'type'}],$resourceID,$dbase,\@updatedList);
      $count++;
    # file is newer on the local; upload
    }elsif (pDrive::Time::isNewerTimestamp(${$dbase}{$path}{$resourceID}[pDrive::DBM->D->{'local_updated'}],$newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}])){
      print STDOUT "newer on local ".$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}]."\n";
      $self->downloadFile($path,$newDocuments{$resourceID}[pDrive::DBM->D->{'server_link'}],$newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}],$newDocuments{$resourceID}[pDrive::DBM->D->{'type'}],$resourceID,$dbase,\@updatedList);
      $count++;

    }

  $self->{_dbm}->writeHash($dbase,$folders) if ($count % 20==0);

}
$self->{_dbm}->writeHash($dbase,$folders);

# new values to post to db
if ($#updatedList >= 0){
  print STDOUT "updating values DB\n" if (pDrive::Config->DEBUG);
  $self->{_dbm}->writeHash($dbase,$folders);
}
} ####



1;

