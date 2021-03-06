package pDrive::GoogleDriveAPI2;

our @ISA = qw(pDrive::CloudServiceAPI);

use LWP::UserAgent;
use LWP;
#use strict;
use IO::Handle;

use constant IS_ROOT => 1;
use constant NOT_ROOT => 0;

use constant FOLDER_TITLE => 0;
use constant FOLDER_ROOT => 1;
use constant FOLDER_PARENT => 2;
use constant FOLDER_SUBFOLDER => 3;

use constant API_URL => 'https://www.googleapis.com/drive/v2/';
use constant OAUTH2_URL => 'https://www.googleapis.com/oauth2/v3';
use constant OAUTH2_AUTH_OTHER => '&redirect_uri=urn:ietf:wg:oauth:2.0:oob';
use constant API_VER => 2;



sub new(*$$) {

	my $self = {_ident => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.104 Safari/537.36",
              _ua => undef,
              _cookiejar => undef,
              _clientID => undef,
              _clientSecret => undef,
              _refreshToken  => undef,
              _token => undef,
              _IP => undef,
              _oauthURL => OAUTH2_URL,
              _oauthOTHER => OAUTH2_AUTH_OTHER,
			  _iss => undef,
	          _key => undef,
			  _username => undef,
			  _serviceToken => undef
	};

  	my $class = shift;
  	bless $self, $class;
  	my $clientID = shift;
	my $clientSecret = shift;
	$self->{_clientID} = $clientID;
	$self->{_clientSecret} = $clientSecret;

  	######
  	#  Useragent
  	###

  	# this gets logged, so it should be representative

  	# Create a user agent object
  	$self->{_ua} = new LWP::UserAgent;	# call the constructor method for this object

  	$self->{_ua}->agent($self->{_ident});		# set the identity
  	$self->{_ua}->timeout(30);		# set the timeout


  	$self->{_ua}->default_headers->push_header('Accept' => "image/gif, image/x-xbitmap, image/jpeg, image/pjpeg, application/x-shockwave-flash, application/vnd.ms-excel, application/vnd.ms-powerpoint, application/msword, application/xaml+xml, application/vnd.ms-xpsdocument, application/x-ms-xbap, application/x-ms-application, */*");
  	$self->{_ua}->default_headers->push_header('Accept-Language' => "en-us");
  	#$ua->default_headers->push_header('Connection' => "close");
  	$self->{_ua}->default_headers->push_header('Connection' => "keep-alive");
  	$self->{_ua}->default_headers->push_header('Keep-Alive' => "300");
  	#$cookie_jar->load();

  	return $self;

}








#
# Test access (validating credentials)
##
sub testAccess(*){

  	my $self = shift;

	my $URL = API_URL . 'about';
	my $req = HTTP::Request->new(GET => $URL);

	$req->protocol('HTTP/1.1');
	$req->header('Authorization' => 'Bearer '.$self->{_token});
	my $res = $self->{_ua}->request($req);

	if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  		print LOG $req->as_string;
  		print LOG $res->as_string;
  		close(LOG);
	}

	if($res->is_success){
  		print STDOUT "success --> $URL\n\n";
  		return 1;

	}else{
		#	print STDOUT $res->as_string;
		return 0;}

}

#
# get list of the content in the Google Drive
##
sub getList(*$){

	my $self = shift;
	my $URL = shift;

	if ($URL eq ''){
		$URL =  API_URL . 'files?includeTeamDriveItems=true&supportsTeamDrives=true&maxResults=400&q=\'me\'+in+owners+and+trashed%3Dfalse&fields=nextLink%2Citems(kind%2Cid%2CmimeType%2Ctitle%2CfileSize%2CmodifiedDate%2CcreatedDate%2CdownloadUrl%2Cparents/parentLink%2Cmd5Checksum)';
	}


	return $self->generalGETdata($URL);


}

#
# get list of the content in the Google Drive
##
sub getListTeamDrives(*$){

	my $self = shift;
	my $URL = shift;

	if ($URL eq ''){
		$URL =  API_URL . 'teamdrives?maxResults=100';
	}


	return $self->generalGETdata($URL);


}



#
# get list of the content in the Google Drive
##
sub getTrash(*$){

	my $self = shift;
	my $URL = shift;

	if ($URL eq ''){
		$URL =  API_URL . 'files?includeTeamDriveItems=true&supportsTeamDrives=true&maxResults=400&q=trashed%3Dtrue&fields=nextLink%2Citems(kind%2Cid%2CmimeType%2Ctitle%2CfileSize%2CmodifiedDate%2CcreatedDate%2CdownloadUrl%2Cparents/parentLink%2Cmd5Checksum)';
	}


	return $self->generalGETdata($URL);


}

#
# get meta data for a file in the Google Drive
##
sub getFileMeta(*$){

	my $self = shift;
	my $fileID = shift;

	my $URL =  API_URL . 'files/'.$fileID.'?includeTeamDriveItems=true&supportsTeamDrives=true&fields=kind%2Cid%2CmimeType%2Ctitle%2CfileSize%2CmodifiedDate%2CcreatedDate%2CdownloadUrl%2Cparents/parentLink%2Cmd5Checksum';


	return $self->generalGETdata($URL);


}

#
# empty the trash
##
sub emptyTrash(*){

	my $self = shift;

	my $URL =  API_URL . 'files/trash';

	my $req = HTTP::Request->new(DELETE => $URL);

	$req->protocol('HTTP/1.1');
	$req->header('Authorization' => 'Bearer '.$self->{_token});
	my $res = $self->{_ua}->request($req);

	if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  		print LOG $req->as_string;
  		print LOG $res->as_string;
  		close(LOG);
	}

	if($res->is_success){
  		print STDOUT "emptied trashn";
  		return;

	}else{
		print STDOUT $req->as_string;
		print STDOUT $res->as_string;
		return;}




}

#
# get list of the content in the Google Drive
##
sub getFolderInfo(*$){

	my $self = shift;
	my $fileID = shift;

	my $URL =  API_URL . 'files/'.$fileID.'?includeTeamDriveItems=true&supportsTeamDrives=true&fields=title%2Cparents';

	my $retryCount = 0;
	while ($self->backoffDelay($retryCount)){
		my $req = HTTP::Request->new(GET => $URL);

		$req->protocol('HTTP/1.1');
		$req->header('Authorization' => 'Bearer '.$self->{_token});
		my $res = $self->{_ua}->request($req);

		if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  			open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  			print LOG $req->as_string;
  			print LOG $res->as_string;
  			close(LOG);
		}

		if($res->is_success){
  			print STDOUT "success --> $URL\n\n"  if (pDrive::Config->DEBUG);
  			my ($title) = $res->as_string =~ m%\"title\"\:\s?\"([^\"]+)\"%;
			my ($resourceID) = $res->as_string =~ m%\"parentLink\"\:\s?\"[^\"]+\/([^\"]+)\"%;
			my ($isRoot) = $res->as_string =~ m%\"isRoot\"\:\s?([^\s]+)%;
			if ($isRoot eq 'true' or ($title ne '' and $resourceID eq '')){
				return (0,$title,$resourceID);
			}else{
				return (1,$title,$resourceID);
			}
		}elsif ($res->code == 401){
 	 		my ($token,$refreshToken) = $self->refreshToken();
			$self->setToken($token,$refreshToken);
			print STDOUT "...refresh token and retrying...\n";
			$retryCount++;
		}elsif ($res->code == 404){
			print STDOUT "...file not found, skipping... ".__LINE__."\n";
			return (0, '','');
		}elsif ($res->code >= 500 and $res->code <= 505){
			print STDOUT $res->as_string;
			print STDOUT "...retrying (5xx error)...\n";
			$retryCount++;
		}else{
			print STDOUT $res->as_string;

			print STDOUT "...retrying (condition unknown)...: ".__LINE__."\n";
			$retryCount++;

			#		print STDOUT $res->as_string;
			#die($res->as_string."error in loading page");
		}
	}
}

#
# get the root ID for the Google Drive
##
sub getListRoot(*$){

	my $self = shift;
	my $URL = shift;

	if ($URL eq ''){
		$URL =  API_URL . 'files/root';
	}

	my $retryCount = 0;
	while ($self->backoffDelay($retryCount)){
		my $req = HTTP::Request->new(GET => $URL);

		$req->protocol('HTTP/1.1');
		$req->header('Authorization' => 'Bearer '.$self->{_token});
		my $res = $self->{_ua}->request($req);

		if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  			open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  			print LOG $req->as_string;
  			print LOG $res->as_string;
  			close(LOG);
		}

		if($res->is_success){
  			print STDOUT "success --> $URL\n\n"  if (pDrive::Config->DEBUG);
  			my $block = $res->as_string;
			my ($resourceID) = $block =~ m%\"kind\"\:\s+\"drive\#file\"\,\s+\"id\"\:\s?\"([^\"]+)\"%;
			return $resourceID;
		}elsif ($res->code == 401){
 	 		my ($token,$refreshToken) = $self->refreshToken();
			$self->setToken($token,$refreshToken);
			print STDOUT "...refresh token and retrying...\n";
			$retryCount++;
		}elsif ($res->code == 404){
			print STDOUT "...file not found, skipping... ".__LINE__."\n";
			return 0;

		}elsif ($res->code >= 500 and $res->code <= 505){
			print STDOUT $res->as_string;
			print STDOUT "...retrying...[50x error]\n";
			$retryCount++;

		}else{
			print STDOUT "...retrying...: ".__LINE__."\n";
			$retryCount++;
			#die($res->as_string."error in loading page");
		}
	}
  	return '';

}



# * for checksum tracking *
# get the list of changes
##
sub getChanges(*$$$$){

	my $self = shift;
	my $URL = shift;
	my $changeID = shift;
	my $teamdrive = shift;
	my $includeSubscribed = shift;

	if ($includeSubscribed){
		$includeSubscribed = '&includeSubscribed=true';

	}else{
		$includeSubscribed = '&includeSubscribed=false';

	}

	if ($URL eq '' and $teamdrive ne '' and $teamdrive ne 'all' and $changeID ne ''){
		$URL =  API_URL . 'changes?includeTeamDriveItems=true&supportsTeamDrives=true&teamDriveId='.$teamdrive.$includeSubscribed.'&includeDeleted=false&maxResults=400&startChangeId='.$changeID;
	}elsif ($URL eq '' and $teamdrive ne ''  and $teamdrive ne 'all'){
		$URL =  API_URL . 'changes?includeTeamDriveItems=true&supportsTeamDrives=true&teamDriveId='.$teamdrive.$includeSubscribed.'&includeDeleted=false&maxResults=400';
	}elsif ($URL eq '' and $teamdrive ne '' and $changeID ne ''){
		$URL =  API_URL . 'changes?includeTeamDriveItems=true&supportsTeamDrives=true'.$includeSubscribed.'&includeDeleted=false&maxResults=400&startChangeId='.$changeID;
	}elsif ($URL eq '' and $teamdrive ne ''){
		$URL =  API_URL . 'changes?includeTeamDriveItems=true&supportsTeamDrives=true'.$includeSubscribed.'&includeDeleted=false&maxResults=400';

	}elsif ($URL eq '' and $changeID ne ''){
		$URL =  API_URL . 'changes?includeDeleted=false'.$includeSubscribed.'&maxResults=400&startChangeId='.$changeID;

	}elsif ($URL eq ''){
		$URL =  API_URL . 'changes?includeDeleted=false'.$includeSubscribed.'&maxResults=400';
	}

	return $self->generalGETdata($URL);


}



#
# get the folderID for a subfolder
##
sub getSubFolderID(*$){

	my $self = shift;
	my $parentID = shift;
	my $folderName = shift;

	my $URL =  API_URL . 'files?includeTeamDriveItems=true&supportsTeamDrives=true&q=\''. $folderName.'\'+in+parents';

	return $self->generalGETdata($URL);

}

sub generalGETdata(*$){
	my $self = shift;
	my $URL = shift;

	my $retryCount = 0;
	while ($self->backoffDelay($retryCount)){
		my $req = HTTP::Request->new(GET => $URL);

		$req->protocol('HTTP/1.1');
		$req->header('Authorization' => 'Bearer '.$self->{_token});
		my $res = $self->{_ua}->request($req);

		if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  			open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  			print LOG $req->as_string;
  			print LOG $res->as_string;
  			close(LOG);
		}

		if($res->is_success){
  			return \$res->as_string;

		}elsif ($res->code == 401){
 	 		my ($token,$refreshToken) = $self->refreshToken();
			$self->setToken($token,$refreshToken);
			print STDOUT "...refresh token and retrying...\n";
			$retryCount++;
		}elsif ($res->code == 403){
			sleep(10);
			print STDOUT "...retrying...\n";
			$retryCount++;
		}elsif ($res->code == 404){
			print STDOUT "...file not found, skipping... ".__LINE__."\n";
			return

		}elsif ($res->code >= 500 and $res->code <= 505){
			print STDOUT $res->as_string;
			print STDOUT "...retrying...[50x error]\n";
			$retryCount++;
		}else{
			print STDOUT "...retrying...: ".__LINE__."\n";
			$retryCount++;

		}
	}


}

#
# get the folderID for a subfolder
##
sub getSubFolderIDList(*$$){

	my $self = shift;
	my $URL = shift;
	my $folderName = shift;

	if ($URL eq ''){
		$URL =  API_URL .'files?includeTeamDriveItems=true&supportsTeamDrives=true&q=\''. $folderName.'\'+in+parents&fields=nextLink%2Citems(kind%2Cid%2CmimeType%2Ctitle%2CfileSize%2CmodifiedDate%2CcreatedDate%2CdownloadUrl%2Cparents/parentLink%2Cmd5Checksum)';
	}
	#my $URL = 'https://www.googleapis.com/drive/v2/files?q=\''. $folderName.'\'+in+parents';

	return $self->generalGETdata($URL);

}


#
# get the folderID for a subfolder
##
sub getFolderList(*$$){

	my $self = shift;
	my $folderID = shift;
	my $URL = shift;

	if ($URL eq ''){
		$URL =  API_URL .'files?includeTeamDriveItems=true&supportsTeamDrives=true&q=\''. $folderID.'\'+in+parents&fields=nextLink%2Citems(kind%2Cid%2CmimeType%2Ctitle%2CfileSize%2CmodifiedDate%2CcreatedDate%2CdownloadUrl%2Cparents/parentLink%2Cmd5Checksum)';
	}
	#my $URL = 'https://www.googleapis.com/drive/v2/files?q=\''. $folderName.'\'+in+parents';

	return $self->generalGETdata($URL);

}

#
# get the next page URL
##
sub getNextURL(**){

 	my $self = shift;
  	my $listing = shift;
	my ($URL) = $$listing =~ m%\"nextLink\"\:\s?\"([^\"]+)\"%;
	return $URL;
}


#
# get the next change ID
##
sub getChangeID(**){

 	my $self = shift;
  	my $listing = shift;
	my ($largestChangeId) = $$listing =~ m%\"largestChangeId\"\:\s?\"([^\"]+)\"%;
	return $largestChangeId;
}




sub downloadFile(*$$$){

	my $self = shift;
  	my $path = shift;
  	my $URL = shift;
  	my $timestamp = shift;
    print STDERR "URL = $URL $self->{_token} $path\n";
    if (defined($self->{_IP})){
    	`wget -c --bind-address=$self->{_IP} --header="Authorization: Bearer $self->{_token}" "$URL" -O "$path"`;
    }else{
    	`wget -c --header="Authorization: Bearer $self->{_token}" "$URL" -O "$path"`;
    }
    return;
	my $retryCount = 0;
	while ($self->backoffDelay($retryCount)){

		my $req = HTTP::Request->new(GET => $URL);

		$req->protocol('HTTP/1.1');
		$req->header('Authorization' => 'Bearer '.$self->{_token});
		my $res = $self->{_ua}->request($req, $path);
	 	if ($res->is_success) {
     		print STDOUT "ok\n";
     		return 1;
		}elsif ($res->code == 401 or $res->code == 403){

 	 		my ($token,$refreshToken) = $self->refreshToken();
			$self->setToken($token,$refreshToken);
			print STDOUT "...refresh token and retrying...\n";
			$retryCount++;
		}elsif ($res->code == 404){
			print STDOUT "...file not found, skipping... ".__LINE__."\n";
			return 1;

		}elsif ($res->code >= 500 and $res->code <= 505){
			print STDOUT $res->as_string;
			print STDOUT "...retrying...[50x error]\n";
			$retryCount++;
  		}  else {
			print STDOUT "...retrying...: ".__LINE__."\n";
			$retryCount++;
  		}
	}
#  	open (FILE, "> ".$path) or die ("Cannot save image file".$path.": $!\n");
 # 	FILE->autoflush;
  #	binmode(FILE);
  #  $res = $self->{_ua}->get($URL,':content_cb' => \&downloadChunk,':read_size_hint' => 8192,'Authorization' => 'Bearer '.$self->{_token});
#	close(FILE);
 # 	print STDOUT "saved\n";


 	 # set timestamp on file as server last updated timestamp
 	#utime $timestamp, $timestamp, pDrive::Config->LOCAL_PATH.'/'.$path;


# reduce memory consumption from slurping the entire download file in memory
#downloadChunk adapted from: http://www.perlmonks.org/?node_id=953833
# all rights reserved from original author
sub downloadChunk {
  	my ($data) = @_;

  	# write the $data to a filehandle or whatever should happen
  	# with it here.
  	print FILE $data;
}
###



}


sub uploadFile(*$$$$){

	my $self = shift;
  	my $URL = shift;
  	my $chunk = shift;
  	my $chunkSize = shift;
  	my $chunkRange = shift;
  	my $filetype = shift;
 	my $resourceID = 0;

	my $retryCount = 0;
	while ($self->backoffDelay($retryCount)){
		my $req = HTTP::Request->new(PUT => $URL);

		$req->protocol('HTTP/1.1');
		$req->header('Authorization' => 'Bearer '.$self->{_token});
		$req->content_type($filetype);
		$req->content_length($chunkSize);
		$req->header('Content-Range' => $chunkRange);
		$req->content($$chunk);
		my $res = $self->{_ua}->request($req);


		if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  			open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  			print LOG $req->headers_as_string;
  			print LOG $res->as_string;
  			close(LOG);
		}

		if($res->is_success or $res->code == 308){

  			my $block = $res->as_string;
			my ($resourceType,$resourceID,$md5,$title);

			while (my ($line) = $block =~ m%([^\n]*)\n%){
				$block =~ s%[^\n]*\n%%;
		    	if ($line =~ m%\"id\"%){
		    		($resourceID) = $line =~ m%\"id\"\:\s?\"([^\"]+)\"%;

	    		}

			}
			my @results =  ($resourceID,$md5,$title);
			return \@results;
			return $resourceID;
		}elsif ($res->code == 401){
 			my ($token,$refreshToken) = $self->refreshToken();
			$self->setToken($token,$refreshToken);
			print STDOUT "...refresh token and retrying...\n";
			$retryCount++;
		}elsif ($res->code == 403){
			print STDOUT "Daily limit exceeded ".__LINE__."\n";
			return -1;
		}elsif ($res->code == 404){
			print STDOUT "...file not found, skipping... ".__LINE__."\n";
			return -1;

		}elsif ($res->code >= 500 and $res->code <= 505){
			print STDOUT $res->as_string;
			print STDOUT "...retrying...[50x error]\n";
			$retryCount++;
		}else{
			print STDOUT "...retrying...c\n";
			$retryCount++;
		}
	}

}


#
# Create a file
##
sub createFile(*$$$$$){

	my $self = shift;
  	my $URL = shift;
  	my $fileSize = shift;
  	my $file = shift;
  	my $fileType = shift;
	my $folder = shift;


  	my $content = '{
  		"title": "'.$file. '",
  		"parents": [{
    		"kind": "drive#fileLink",
    		"id": "'.$folder.'"
  		}]
		}'."\n\n";

	my $retryCount = 0;
	while ($self->backoffDelay($retryCount)){
		# convert=false prevents plain/text from becoming docs
		my $req = HTTP::Request->new(POST => $URL);

		$req->protocol('HTTP/1.1');
		$req->header('Authorization' => 'Bearer '.$self->{_token});
		$req->header('X-Upload-Content-Type' => $fileType);
		$req->header('X-Upload-Content-Length' => $fileSize);
		$req->content_length(length $content);
		$req->content_type('application/json');
		$req->content($content);

		my $res = $self->{_ua}->request($req);

		if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  			open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  			print LOG $req->as_string;
  			print LOG $res->as_string;
  			close(LOG);
		}

		if($res->is_success){
  			print STDOUT "success --> $URL\n\n"  if (pDrive::Config->DEBUG);

	  		my $block = $res->as_string;

  			while (my ($line) = $block =~ m%([^\n]*)\n%){

    			$block =~ s%[^\n]*\n%%;

			    if ($line =~ m%^Location:%){
    	  			($URL) = $line =~ m%^Location:\s+(\S+)%;
	    	  		return $URL;
    			}

  			}
		}elsif ($res->code == 401){
 	 		my ($token,$refreshToken) = $self->refreshToken();
			$self->setToken($token,$refreshToken);
			print STDOUT "...refresh token and retrying...\n";
			$retryCount++;
		}elsif ($res->code == 404){
			print STDOUT "...file not found, skipping... ".__LINE__."\n";
			return '';
		}elsif ($res->code == 403){
			print STDOUT "Daily limit exceeded ".__LINE__."\n";
			return -1;
		}elsif ($res->code >= 500 and $res->code <= 505){
			print STDOUT $res->as_string;
			print STDOUT "...retrying... [50x error]\n";
			$retryCount++;
		}else{
			print STDOUT "...retrying...: ".__LINE__."\n";
			$retryCount++;

		}
	}

}


#
# Copy a file using Google server's copy method
# - can copy a file from one account (optional - including directory) and can rename in process
# - can be used to copy a file ID without directory or filename information
##
sub copyFile(*$$$){

	my $self = shift;
  	my $fileID = shift;

	my $URL = API_URL  . 'files/' . $fileID . '/copy?includeTeamDriveItems=true&supportsTeamDrives=true';

  	#optional
  	my $fileName = shift;
	my $folder = shift;
	my $createDate = shift;

	my $content = '';

	#remove \ from filename
	$fileName =~ s%\\%%g;

	#copying a file with directory and filename
	if ($folder ne '' and $fileName ne '' and $createDate ne ''){
  		$content = '{
  			"title": "'.$fileName. '",
  			"modifiedDate": "'.$createDate.'",
  			"parents": [{
    		"kind": "drive#fileLink",
    		"id": "'.$folder.'"
  			}]
			}'."\n\n";
	#copying a file with directory but no filename
	}elsif ($folder ne '' and $fileName ne ''){
  		$content = '{
  			"title": "'.$fileName. '",
  			"parents": [{
    		"kind": "drive#fileLink",
    		"id": "'.$folder.'"
  			}]
			}'."\n\n";
	#copying a file with directory but no filename
	}elsif ($folder ne ''){
  		$content = '{
  			"parents": [{
    		"kind": "drive#fileLink",
    		"id": "'.$folder.'"
  			}]
			}'."\n\n";
	}elsif ($folder ne ''){
  		$content = '{
  			"parents": [{
    		"kind": "drive#fileLink",
    		"id": "'.$folder.'"
  			}]
			}'."\n\n";
	}


	my $retryCount = 0;
	while ($self->backoffDelay($retryCount)){

		my $req = HTTP::Request->new(POST => $URL);

		$req->protocol('HTTP/1.1');
		$req->header('Authorization' => 'Bearer '.$self->{_token});
		$req->content_length(length $content);
		$req->content_type('application/json');
		$req->content($content);

		my $res = $self->{_ua}->request($req);

		if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
	  		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  			print LOG $req->as_string;
  			print LOG $res->as_string;
  			close(LOG);
		}

		if($res->is_success){
  			print STDOUT "success --> $URL\n\n"  if (pDrive::Config->DEBUG);
			return 1;

		}elsif ($res->code == 401){
	 	 	my ($token,$refreshToken) = $self->refreshToken();
			$self->setToken($token,$refreshToken);
			$retryCount++;
		#daily limit exceeded
		}elsif ($res->code == 403){
			print STDOUT "Daily limit exceeded  ".__LINE__."\n";
			print STDOUT "...refresh token and retrying...\n";
			return -1;
		#not accessible to user
		}elsif ($res->code == 404){
			print STDOUT "Not accessibble to user, download-upload instead of copy\n";
			return -2;
		}elsif ($res->code == 404){
			print STDOUT "...file not found, skipping... ".__LINE__."\n";
			return -2;

		}elsif ($res->code >= 500 and $res->code <= 505){
			print STDOUT $res->as_string;
			print STDOUT "...retrying......[50x error]\n";
			$retryCount++;
		}else{
			print STDOUT "...retrying...: ".__LINE__."\n";
			$retryCount++;

		}
	}
}



#
# Rename a file
##
sub renameFile(*$$){

	my $self = shift;
  	my $fileID = shift;

	my $URL = API_URL  . 'files/' . $fileID. '?includeTeamDriveItems=true&supportsTeamDrives=true';

  	my $fileName = shift;

	my $content ='{
  			"title": "'.$fileName. '"
			}'."\n\n";

	my $retryCount = 0;
	while ($self->backoffDelay($retryCount)){

		my $req = HTTP::Request->new(PUT => $URL);

		$req->protocol('HTTP/1.1');
		$req->header('Authorization' => 'Bearer '.$self->{_token});
		$req->content_length(length $content);
		$req->content_type('application/json');
		$req->content($content);

		my $res = $self->{_ua}->request($req);

		if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
	  		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  			print LOG $req->as_string;
  			print LOG $res->as_string;
  			close(LOG);
		}

		if($res->is_success){
  			print STDOUT "success --> $URL\n\n"  if (pDrive::Config->DEBUG);
			return 1;

		}elsif ($res->code == 401){
	 	 	my ($token,$refreshToken) = $self->refreshToken();
			$self->setToken($token,$refreshToken);
			print STDOUT "...refresh token and retrying...\n";
			$retryCount++;
		}elsif ($res->code == 404){
			print STDOUT "...file not found, skipping... ".__LINE__."\n";
			return 1;

		}elsif ($res->code >= 500 and $res->code <= 505){
			print STDOUT $res->as_string;
			print STDOUT "...retrying...[50x error]\n";
			$retryCount++;
		}else{
			print STDOUT "...retrying...: ".__LINE__."\n";
			$retryCount++;

		}
	}
}


#
# Create a folder
##
sub createFolder(*$$$){

	my $self = shift;
  	my $URL = shift;
  	my $folder = shift;
  	my $parentFolder = shift;


  	my $content = '{
  		"title": "'.$folder. '",
  		"mimeType": "application/vnd.google-apps.folder"';
  	$content .= ' ,"parents": [{"id":"'.$parentFolder.'"}]' if $parentFolder ne '';
	$content .= '}'."\n\n";

	my $retryCount = 0;
	while ($self->backoffDelay($retryCount)){
		my $req = HTTP::Request->new(POST => $URL);

		$req->protocol('HTTP/1.1');
		$req->header('Authorization' => 'Bearer '.$self->{_token});
		$req->content_length(length $content);
		$req->content_type('application/json');
		$req->content($content);

		my $res = $self->{_ua}->request($req);

		if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
	  		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  			print LOG $req->as_string;
  			print LOG $res->as_string;
  			close(LOG);
		}

		if($res->is_success){
  			print STDOUT "success --> $URL\n\n"  if (pDrive::Config->DEBUG);

  			my $block = $res->as_string;

  			while (my ($line) = $block =~ m%([^\n]*)\n%){

    			$block =~ s%[^\n]*\n%%;

		    	if ($line =~ m%\"id\"%){
		    		my ($resourceID) = $line =~ m%\"id\"\:\s?\"([^\"]+)\"%;
	      			return $resourceID;
    			}

  			}
		}elsif ($res->code == 401){
 	 		my ($token,$refreshToken) = $self->refreshToken();
			$self->setToken($token,$refreshToken);
			print STDOUT "...refresh token and retrying...\n";
			$retryCount++;
		}elsif ($res->code == 404){
			print STDOUT "...file not found, skipping... ".__LINE__."\n";
			return 0;

		}elsif ($res->code >= 500 and $res->code <= 505){
			print STDOUT $res->as_string;
			print STDOUT "...retrying...[50x error]\n";
			$retryCount++;
		}else{
			print STDOUT "...retrying...: ".__LINE__."\n";
			$retryCount++;
		}
	}
}


#
# Add a file to a folder
# * needs updating*
##
sub addFile(*$$){

	my $self = shift;
  	my $URL = shift;
  	my $file = shift;

	return; #not implemented

}


#
# Move a file from one folder to another
# * needs updating*
##
sub moveFile(*$$$){

	my $self = shift;
  	my $file = shift;
  	my $toFolder = shift;
  	my $fromFolder = shift;

	my $URL = API_URL . 'files/'.$file . '?includeTeamDriveItems=true&supportsTeamDrives=true&modifiedDateBehavior=noChange&';

	$URL .=  'addParents=' . $toFolder;

	if ($fromFolder ne ''){
		$URL .=  '&removeParents='.$fromFolder;
	}

	my $retryCount = 0;
		while ($self->backoffDelay($retryCount)){
			my $req = HTTP::Request->new(PUT => $URL);

			$req->protocol('HTTP/1.1');
			$req->header('Authorization' => 'Bearer '.$self->{_token});
			$req->content_length(0);

			my $res = $self->{_ua}->request($req);

			if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
		  		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
		  		print LOG $req->as_string;
		  		print LOG $res->as_string;
		  		close(LOG);
			}

			if($res->is_success or $res->code == 308){

	  			my $block = $res->as_string;
				my ($resourceType,$resourceID);
				while (my ($line) = $block =~ m%([^\n]*)\n%){
					$block =~ s%[^\n]*\n%%;

			    	if ($line =~ m%\"id\"%){
			    		my ($resourceID) = $line =~ m%\"id\"\:\s?\"([^\"]+)\"%;
		      			return $resourceID;
		    		}

				}

				return $resourceID;
			}elsif ($res->code == 401){
	 			my ($token,$refreshToken) = $self->refreshToken();
				$self->setToken($token,$refreshToken);
				print STDOUT "...refresh token and retrying...\n";
				$retryCount++;
			}elsif ($res->code == 404){
				print STDOUT "...file not found, skipping... ".__LINE__."\n";
				return 0;

			}elsif ($res->code >= 500 and $res->code <= 505){
				print STDOUT $res->as_string;
				print STDOUT "...retrying...[50x error]\n";
				$retryCount++;
			}else{
				print STDOUT "...retrying...: ".__LINE__."\n";
				$retryCount++;
			}
		}


	return;

}


#
# Delete  a file given resource ID
# ** skips trash, deletes permanently
#
##
sub deleteFile(*$){

	my $self = shift;
  	my $resourceID = shift;

	my $URL = API_URL . 'files/'.$resourceID.'?includeTeamDriveItems=true&supportsTeamDrives=true';
	my $req = HTTP::Request->new(DELETE => $URL);

	$req->protocol('HTTP/1.1');
	$req->header('Authorization' => 'Bearer '.$self->{_token});
	my $res = $self->{_ua}->request($req);

	if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  		print LOG $req->as_string;
  		print LOG $res->as_string;
  		close(LOG);
	}

	if($res->is_success){
  		print STDOUT "deleted file $resourceID\n\n";
  		return;

	}else{
		print STDOUT $req->as_string;
		print STDOUT $res->as_string;
		return;}

}


#
# Trash  a file/folder given resource ID
#
##
sub trashFile(*$){

	my $self = shift;
  	my $resourceID = shift;

	my $URL = API_URL . 'files/'.$resourceID. '/trash?includeTeamDriveItems=true&supportsTeamDrives=true';
	my $req = HTTP::Request->new(POST => $URL);

	$req->protocol('HTTP/1.1');
	$req->header('Authorization' => 'Bearer '.$self->{_token});
	my $content = '';
	$req->content_length(length $content);
	$req->content_type('application/json');
	$req->content($content);

	my $res = $self->{_ua}->request($req);

	if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  		print LOG $req->as_string;
  		print LOG $res->as_string;
  		close(LOG);
	}

	if($res->is_success){
  		print STDOUT "trashed file $resourceID\n\n";
  		return;

	}else{
		print STDOUT $res->as_string;
		return;}

}

#
# Untrash  a file/folder given resource ID
#
##
sub untrashFile(*$){

	my $self = shift;
  	my $resourceID = shift;

	my $URL = API_URL . 'files/'.$resourceID. '/untrash?includeTeamDriveItems=true&supportsTeamDrives=true';
	my $req = HTTP::Request->new(POST => $URL);

	$req->protocol('HTTP/1.1');
	$req->header('Authorization' => 'Bearer '.$self->{_token});
	my $content = '';
	$req->content_length(length $content);
	$req->content_type('application/json');
	$req->content($content);

	my $res = $self->{_ua}->request($req);

	if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  		print LOG $req->as_string;
  		print LOG $res->as_string;
  		close(LOG);
	}

	if($res->is_success){
  		print STDOUT "untrashed file $resourceID\n\n";
  		return;

	}else{
		print STDOUT $req->as_string;
		print STDOUT $res->as_string;
		return;}

}

#
# Parse the drive listings
##
sub readDriveListings(**){

	my $self = shift;
	my $driveListings = shift;
	my %newDocuments;

	my $count=0;

  	$$driveListings =~ s%\n%%g;
#  	while ($$driveListings =~ m%\{\s+\"kind\"\:.*?\}\,\s+\{%){ # [^\}]+

  	while ($$driveListings =~ m%\{\s+\"kind\"\:.*?\}\,\s+\{% or $$driveListings =~ m%\{\s+\"kind\"\:.*?\}\s*\]\s*\}% or $$driveListings =~ m%\{\s+\"kind\"\:.*?\}$%){ # [^\}]+

    	my ($entry) = $$driveListings =~ m%\{\s+\"kind\"\:(.*?)\}\,\s\s\{%;

		if ($entry eq ''){
    		($entry) = $$driveListings =~ m%\{\s+\"kind\"\:(.*?)\}\s*\]\s*\}%;
    		if ($entry eq ''){
	    		($entry) = $$driveListings =~ m%\{\s+\"kind\"\:(.*?)\}$%;

    			$$driveListings =~ s%\{\s+\"kind\"\:(.*?)\}$%%;

    		}else{
    			$$driveListings =~ s%\{\s+\"kind\"\:(.*?)\}\s*\]\s*\}%%;
    		}

		}else{
    		$$driveListings =~ s%\{\s+\"kind\"\:(.*?)\}\,\s+%%;
		}


    	my ($title) = $entry =~ m%\"title\"\:\s?\"([^\"]+)\"%;
    	#remove leading spaces from filename (causes issues with fisi)
    	$title =~ s%^\s+%%g;
    	#remove trailing spaces from filename (causes issues with fisi)
    	$title =~ s%\s+$%%g;

		my ($updated) = $entry =~ m%\"modifiedDate\"\:\s?\"([^\"]+)\"%;
		my ($published) = $entry =~ m%\"createdDate\"\:\s?\"([^\"]+)\"%;
		my ($resourceType) = $entry =~ m%\"mimeType\"\:\s?\"([^\"]+)\"%;
		my ($resourceID) = $entry =~ m%\"id\"\:\s?\"([^\"]+)\"%;
		my ($downloadURL) = $entry =~ m%\"downloadUrl\"\:\s?\"([^\"]+)\"%;
		my ($parentID) = $entry =~ m%\"parentLink\"\:\s?\"([^\"]+)\"%;
		my ($md5) = $entry =~ m%\"md5Checksum\"\:\s?\"([^\"]+)\"%;
		my ($fileSize) = $entry =~ m%\"fileSize\"\:\s?\"([^\"]+)\"%;
		my ($resolution) = $entry =~ m%\"height\"\:\s?(\d+),%;
		my ($duration) = $entry =~ m%\"durationMillis\"\:\s?\"([^\"]+)\"%;

	    # 	is a folder
	    if ($resourceType eq 'folder' or $resourceType eq 'application/vnd.google-apps.folder'){


		      # is a root folder
#			}else{

#        		$$folders{$resourceID}[FOLDER_ROOT] = IS_ROOT;

 #     		}

  			$newDocuments{$resourceID}[pDrive::DBM->D->{'server_fisi'}] = '';
      		$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}] = $title;

    	}else{

      		$updated =~ s%\D+%%g;
      		($updated) = $updated =~ m%^(\d{14})%;
#      		$newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}] = pDrive::Time::getEPOC($updated);
			#      $newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}] = $updated;

      		$newDocuments{$resourceID}[pDrive::DBM->D->{'server_link'}] = $downloadURL;
#      		$newDocuments{$resourceID}[pDrive::DBM->D->{'server_edit'}] = $editURL;
      		$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}] = $md5;
      		$newDocuments{$resourceID}[pDrive::DBM->D->{'type'}] = $resourceType;

      		($parentID) = $parentID =~ m%\/([^\/]+)$%;
      		$newDocuments{$resourceID}[pDrive::DBM->D->{'parent'}] = $parentID;

      		$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}] = $title;
      		$newDocuments{$resourceID}[pDrive::DBM->D->{'published'}] = $published;
      		$newDocuments{$resourceID}[pDrive::DBM->D->{'size'}] = $fileSize;

      		$title =~ s/\+//g; #remove +s in title for fisi)
  			$newDocuments{$resourceID}[pDrive::DBM->D->{'server_fisi'}] = pDrive::FileIO::getMD5String($title .$fileSize);
  			$newDocuments{$resourceID}[pDrive::DBM->D->{'resolution'}] = $resolution;
  			$newDocuments{$resourceID}[pDrive::DBM->D->{'duration'}] = int($duration/60000);
    	}
    	$count++;
  	}

	return \%newDocuments;
}

#
# Parse the drive listings
##
sub readSingleDriveListings(**){

	my $self = shift;
	my $driveListings = shift;
	my %newDocuments;

	my $count=0;

  	$$driveListings =~ s%\n%%g;
	#print $$driveListings;
#  	while ($$driveListings =~ m%\{\s+\"kind\"\:.*?\}\,\s+\{%){ # [^\}]+
  	while ($$driveListings =~ m%\{\s+\"kind\"\:.*?\}%){ # [^\}]+

    	my ($entry) = $$driveListings =~ m%\{\s+\"kind\"\:(.*?)\}%;
    	$$driveListings =~ s%\{\s+\"kind\"\:(.*?)\}%%;

    	my ($title) = $entry =~ m%\"title\"\:\s?\"([^\"]+)\"%;
    	#remove leading spaces from filename (causes issues with fisi)
    	$title =~ s%^\s+%%g;
    	#remove trailing spaces from filename (causes issues with fisi)
    	$title =~ s%\s+$%%g;

		my ($updated) = $entry =~ m%\"modifiedDate\"\:\s?\"([^\"]+)\"%;
		my ($published) = $entry =~ m%\"createdDate\"\:\s?\"([^\"]+)\"%;
		my ($resourceType) = $entry =~ m%\"mimeType\"\:\s?\"([^\"]+)\"%;
		my ($resourceID) = $entry =~ m%\"id\"\:\s?\"([^\"]+)\"%;
		my ($downloadURL) = $entry =~ m%\"downloadUrl\"\:\s?\"([^\"]+)\"%;
		my ($parentID) = $entry =~ m%\"parentLink\"\:\s?\"([^\"]+)\"%;
		my ($md5) = $entry =~ m%\"md5Checksum\"\:\s?\"([^\"]+)\"%;
		my ($fileSize) = $entry =~ m%\"fileSize\"\:\s?\"([^\"]+)\"%;
		my ($resolution) = $entry =~ m%\"height\"\:\s?(\d+),%;
		my ($duration) = $entry =~ m%\"durationMillis\"\:\s?\"([^\"]+)\"%;

	    # 	is a folder
	    if ($resourceType eq 'folder' or $resourceType eq 'application/vnd.google-apps.folder'){


		      # is a root folder
#			}else{

#        		$$folders{$resourceID}[FOLDER_ROOT] = IS_ROOT;

 #     		}

  			$newDocuments{$resourceID}[pDrive::DBM->D->{'server_fisi'}] = '';
      		$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}] = $title;

    	}else{

      		$updated =~ s%\D+%%g;
      		($updated) = $updated =~ m%^(\d{14})%;
#      		$newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}] = pDrive::Time::getEPOC($updated);
			#      $newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}] = $updated;

      		$newDocuments{$resourceID}[pDrive::DBM->D->{'server_link'}] = $downloadURL;
#      		$newDocuments{$resourceID}[pDrive::DBM->D->{'server_edit'}] = $editURL;
      		$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}] = $md5;
      		$newDocuments{$resourceID}[pDrive::DBM->D->{'type'}] = $resourceType;

      		($parentID) = $parentID =~ m%\/([^\/]+)$%;
      		$newDocuments{$resourceID}[pDrive::DBM->D->{'parent'}] = $parentID;

      		$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}] = $title;
      		$newDocuments{$resourceID}[pDrive::DBM->D->{'published'}] = $published;
      		$newDocuments{$resourceID}[pDrive::DBM->D->{'size'}] = $fileSize;

      		$title =~ s/\+//g; #remove +s in title for fisi)
  			$newDocuments{$resourceID}[pDrive::DBM->D->{'server_fisi'}] = pDrive::FileIO::getMD5String($title .$fileSize);
  			$newDocuments{$resourceID}[pDrive::DBM->D->{'resolution'}] = $resolution;
  			$newDocuments{$resourceID}[pDrive::DBM->D->{'duration'}] = int($duration/60000);

    	}
    	$count++;
  	}

	return \%newDocuments;
}


#
# Parse the change listings
##
sub readChangeListings(**){

	my $self = shift;
	my $driveListings = shift;
	my %newDocuments;

	my $count=0;

  	$$driveListings =~ s%\n%%g;
	#print $$driveListings;
#  	while ($$driveListings =~ m%\{\s+\"kind\"\:.*?\}\,\s+\{%){ # [^\}]+
#  	while ($$driveListings =~ m%\{\s+\"kind\"\:\s+\"drive\#file\"\,\s+\"id\"\:\s+\"[^\"]+\".*?\"md5Checksum\"\:\s+\"[^\"]+\"\s+% ){
	while ($$driveListings =~ m%\{\s+\"kind\"\:\s+\"drive\#file\"\,\s+\"id\"\:\s+\"[^\"]+\".*?\"quotaBytesUsed\"\:\s+\"[^\"]+\"% ){

    	my ($resourceID,$md5) = $$driveListings =~ m%\{\s+\"kind\"\:\s+\"drive\#file\"\,\s+\"id\"\:\s+\"([^\"]+)\".*?\"md5Checksum\"\:\s+\"([^\"]+)\"%;
    	my ($title) = $$driveListings =~ m%\"title\"\:\s?\"([^\"]+)\"%;
		my ($fileSize) = $$driveListings =~ m%\"fileSize\"\:\s?\"([^\"]+)\"%;

		$$driveListings =~ s%\{\s+\"kind\"\:\s+\"drive\#file\"\,\s+\"id\"\:\s+\"[^\"]+\".*?\"quotaBytesUsed\"\:\s+\"[^\"]+\"%%;

 		if (pDrive::Config->DEBUG){
	 		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
	 	 	print LOG 'title = '. $title . "\t\t\t" . $md5 . "\n";
	 	 	close(LOG);
 		}
    	next if $md5 eq '';
#		$$driveListings =~ s%drive\#file%%;

  		$newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}] = $md5;
   		$newDocuments{$resourceID}[pDrive::DBM->D->{'title'}] = $title;
    	#remove leading spaces from filename (causes issues with fisi)
    	$title =~ s%^\s+%%g;
    	#remove trailing spaces from filename (causes issues with fisi)
    	$title =~ s%\s+$%%g;

  		$newDocuments{$resourceID}[pDrive::DBM->D->{'size'}] = $fileSize;
		$newDocuments{$resourceID}[pDrive::DBM->D->{'server_fisi'}] = pDrive::FileIO::getMD5String($title .$fileSize);

    	$count++;
  	}

	return \%newDocuments;
}

#
# Test access (validating credentials)
##
sub testServiceAccess(*){

  	my $self = shift;

	my $URL = API_URL . 'about';
	my $req = HTTP::Request->new(GET => $URL);

	$req->protocol('HTTP/1.1');
	$req->header('Authorization' => 'Bearer '.$self->{_serviceToken});
	my $res = $self->{_ua}->request($req);

	if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  		print LOG $req->as_string;
  		print LOG $res->as_string;
  		close(LOG);
	}

	if($res->is_success){
  		print STDOUT "success --> $URL\n\n";
  		return 1;

	}else{
		#	print STDOUT $res->as_string;
		return 0;}


}
sub setService(*$$){
	my $self = shift;
	my $ISS = shift;
	my $KEY = shift;
	$self->{_iss} = $ISS;
	$self->{_key} = $KEY;
}

sub setUsername(*$$){
	my $self = shift;
	my $username = shift;
	$self->{_username} = $username;
}


#
# setSerivceTokens: service access token
##
sub setServiceToken(*$){
	my $self = shift;
	my $serviceToken = shift;

	$self->{_serviceToken} = $serviceToken;
	$self->{_token} = $serviceToken;
	$self->{_refreshToken} = '';


}


#
# getTokens
##
sub getServiceToken(*$){
	my $self = shift;
	my $username = shift;


	my  $URL = 'https://accounts.google.com/o/oauth2/token';


	use if pDrive::Config->ALLOW_SERVICE, JSON;
	use if pDrive::Config->ALLOW_SERVICE,JSON::WebToken;


	my $time = time;

	my $jwt;
	if ($username ne 'self'){
	 $jwt = JSON::WebToken->encode(
    {
        # your service account id here
        iss   => $self->{_iss},
        scope => 'https://www.googleapis.com/auth/drive',# https://www.googleapis.com/auth/drive.appdata',
        aud   => 'https://accounts.google.com/o/oauth2/token',
        exp   => $time + 3600,
        iat   => $time,
        # To access the google admin sdk with a service account
        # the service account must act on behalf of an account
        # that has admin privileges on the domain
        # Otherwise the token will be returned but API calls
        # will generate a 403
        prn => $username,
    },
    $self->{_key},
    'RS256',
    { typ => 'JWT' }
);
	}else{
			$jwt = JSON::WebToken->encode(
    {
        # your service account id here
        iss   => $self->{_iss},
        scope => 'https://www.googleapis.com/auth/drive',# https://www.googleapis.com/auth/drive.appdata',
        aud   => 'https://accounts.google.com/o/oauth2/token',
        exp   => $time + 3600,
        iat   => $time,
        # To access the google admin sdk with a service account
        # the service account must act on behalf of an account
        # that has admin privileges on the domain
        # Otherwise the token will be returned but API calls
        # will generate a 403
    },
    $self->{_key},
    'RS256',
    { typ => 'JWT' }
);
	}

	my $req = HTTP::Request->new(POST => $URL);

	$req->content_type("application/x-www-form-urlencoded");
	$req->protocol('HTTP/1.1');
	$req->content('grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion='.$jwt);
	my $res = $self->{_ua}->request($req);


	if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
 	 open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
	 print LOG 'iss = '. $self->{_iss}."\n";
	 print LOG 'username = '. $self->{_username}."\n";
 	 print LOG $req->as_string;
 	 print LOG $res->as_string;
 	 close(LOG);
	}

	my $token;
	if($res->is_success){
  		print STDOUT "success --> $URL\n\n";

	  	my $block = $res->as_string;

		($token) = $block =~ m%\"access_token\"\s?\:\s?\"([^\"]+)\"%;
		if ($token ne ''){
			$self->{_serviceToken} = $token;
			return ($self->{_serviceToken},'');
		}

	}else{
		#print STDOUT $res->as_string;
		die ($res->as_string."error in loading page");}

	die ("can't find token");


}


1;

