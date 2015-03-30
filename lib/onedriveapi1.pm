package pDrive::OneDriveAPI1;

use HTTP::Cookies;
#use HTML::Form;
use URI;
use LWP::UserAgent;
use LWP;
use strict;

use constant IS_ROOT => 1;
use constant NOT_ROOT => 0;

use constant FOLDER_TITLE => 0;
use constant FOLDER_ROOT => 1;
use constant FOLDER_PARENT => 2;
use constant FOLDER_SUBFOLDER => 3;



sub new() {

	my $self = {_ident => "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; Q312461)",
              _ua => undef,
              _cookiejar => undef,
              _clientID => undef,
              _clientSecret => undef,
              _refreshToken  => undef,
              _token => undef};

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


  	$self->{_cookiejar} = HTTP::Cookies->new();
  	$self->{_ua}->cookie_jar($self->{_cookiejar});
	#  $self->{_ua}->max_redirect(0);
	#  $self->{_ua}->requests_redirectable([]);

  	$self->{_ua}->default_headers->push_header('Accept' => "image/gif, image/x-xbitmap, image/jpeg, image/pjpeg, application/x-shockwave-flash, application/vnd.ms-excel, application/vnd.ms-powerpoint, application/msword, application/xaml+xml, application/vnd.ms-xpsdocument, application/x-ms-xbap, application/x-ms-application, */*");
  	$self->{_ua}->default_headers->push_header('Accept-Language' => "en-us");
	  #$ua->default_headers->push_header('Connection' => "close");
  	$self->{_ua}->default_headers->push_header('Connection' => "keep-alive");
  	$self->{_ua}->default_headers->push_header('Keep-Alive' => "300");
	  #$cookie_jar->load();

  	return $self;

}

##
# multiple NIC cards:
# bind to a specific IP
##
sub bindIP(*$){

  my $self = shift;
  my $IP = shift;

  $self->{_ua}->local_address($IP);

}

#
# setTokens: access & refresh
##
sub setToken(*$$){
	my $self = shift;
	my $token = shift;
	my $refreshToken = shift;

	$self->{_refreshToken} = $refreshToken;
	$self->{_token} = $token;

}

#
# getTokens (writely and wise)
##
sub getToken(*$){
	my $self = shift;
	my $code = shift;

#	my  $URL = 'https://login.live.com/oauth20_authorize.srf?client_id='.$self->{_clientID} . '&scope=onedrive.readwrite+wl.offline_access&response_type=code&redirect_uri=https://login.live.com/oauth20_desktop.srf';
	my  $URL = 'https://login.live.com/oauth20_token.srf';
	my $req = new HTTP::Request POST => $URL;
	$req->content_type("application/x-www-form-urlencoded");
	$req->protocol('HTTP/1.1');
	$req->content('client_id='.$self->{_clientID}.'&redirect_uri=https://login.live.com/oauth20_desktop.srf&client_secret='.$self->{_clientSecret}.'&code='.$code.'&grant_type=authorization_code');
	my $res = $self->{_ua}->request($req);


	if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
 	 open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
 	 print LOG $req->as_string;
 	 print LOG $res->as_string;
 	 close(LOG);
	}

	my $token;
	my $refreshToken;
	if($res->is_success){
  		print STDOUT "success --> $URL\n\n";

	  	my $block = $res->as_string;

		($token) = $block =~ m%\"access_token\"\:\"([^\"]+)\"%;
		($refreshToken) = $block =~ m%\"refresh_token\"\:\"([^\"]+)\"%;

	}else{
		#print STDOUT $res->as_string;
		die ($res->as_string."error in loading page");}

	$self->{_token} = $token;
	$self->{_refreshToken} = $refreshToken;
	return ($token,$refreshToken);


}

sub getList(*$){

  my $self = shift;
  my $URL = shift;


my $req = new HTTP::Request GET => $URL;
$req->protocol('HTTP/1.1');
$req->header('Authorization' => 'bearer '.$self->{_token});
my $res = $self->{_ua}->request($req);

if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  print LOG $req->as_string;
  print LOG $res->as_string;
  close(LOG);
}

if($res->is_success){
  print STDOUT "success --> $URL\n\n";
  my $block = $res->as_string;

  while (my ($line) = $block =~ m%([^\n]*)\n%){

    $block =~ s%[^\n]*\n%%;

  }

}else{
#print STDOUT $res->as_string;
die($res->as_string."error in loading page");}

  return \$res->as_string;

}

sub getCreateURL(*$){

  my $self = shift;
  my $listing = shift;

  my ($URL) = $$listing =~ m%\<link\s+rel\=\'http\:\/\/schemas.google.com\/g\/2005\#resumable-create-media\'\s+type\=\'application\/atom\+xml\'\s+href\=\'([^\']+)\'\/\>%;

  return $URL;

}

sub getNextURL(*$){

  my $self = shift;
  my $listing = shift;

  my ($URL) = $$listing =~ m%\<link\s+rel\=\'next\'\s+type\=\'application\/atom\+xml\'\s+href\=\'([^\']+)\'\/\>%;
  print STDOUT 'NEXT URL = '.(defined $URL?$URL:'')."\n";
#exit(0);
  return $URL;

}

sub getListURL(*$){

  my $self = shift;
  my $timestamp = shift;

  if (defined $timestamp and $timestamp ne ''){
    return 'https://docs.google.com/feeds/default/private/full?showfolders=true&q=after:'.$timestamp;
  #  $listURL = 'https://docs.google.com/feeds/default/private/full?showfolders=true&q=after:2012-08-10';
  }else{
    return 'https://docs.google.com/feeds/default/private/full?showfolders=true';
  }

}


sub downloadFile(*$$$$$$){

  my $self = shift;
  my $URL = shift;
  my $path = shift;
  my $resourceID = shift;
  my $appendex = shift;
  my $timestamp = shift;


$path .= '.'.$resourceID if ($resourceID ne '');
$path .= $appendex if ($appendex ne '');

my $req = new HTTP::Request GET => $URL;
$req->protocol('HTTP/1.1');
if ($URL =~ m%\&exportFormat%){
  $req->header('Authorization' => 'GoogleLogin auth='.$self->{_authwise});
}else{
  $req->header('Authorization' => 'GoogleLogin auth='.$self->{_authwritely});
}
$req->header('GData-Version' => '3.0');
  $self->{_cookiejar}->add_cookie_header($req);
#my $res = $self->{_ua}->request($req);
my $res;
  open (FILE, "> ".pDrive::Config->LOCAL_PATH."/$path") or die ("Cannot save image file".pDrive::Config->LOCAL_PATH."/$path: $!\n");
  binmode(FILE);
  if ($URL =~ m%\&exportFormat%){
    $res = $self->{_ua}->get($URL,':content_cb' => \&downloadChunk,':read_size_hint' => 8192,'Authorization' => 'GoogleLogin auth='.$self->{_authwise},'GData-Version' => '3.0');
  }else{
    $res = $self->{_ua}->get($URL,':content_cb' => \&downloadChunk,':read_size_hint' => 8192,'Authorization' => 'GoogleLogin auth='.$self->{_authwritely},'GData-Version' => '3.0');
  }
  close(FILE);
  print STDOUT "saved\n";

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

if($res->is_success){
  print STDOUT "success --> $URL\n\n";

#removed (slups entire file into memory)
#  open (FILE, "> ".pDrive::Config->LOCAL_PATH."/$path") or die ("Cannot save image file".pDrive::Config->LOCAL_PATH."/$path: $!\n");
#  binmode(FILE);
#  print FILE $res->content;
#  close(FILE);
#  print STDOUT "saved\n";

  # set timestamp on file as server last updated timestamp
  utime $timestamp, $timestamp, pDrive::Config->LOCAL_PATH.'/'.$path;


#if (pDrive::Config->DEBUG){
#  open (LOG, '>'.pDrive::Config->DEBUG_LOG);
#  print LOG $req->as_string;
#  print LOG $res->as_string;
#  close(LOG);
#}

  return 1;
}else{

  if (0){
  my $block = $res->as_string;

  while (my ($line) = $block =~ m%([^\n]*)\n%){

    $block =~ s%[^\n]*\n%%;

    if ($line =~ m%^Location:%){
      ($URL) = $line =~ m%^Location:\s+(\S+)%;
      print STDERR "following location $URL\n";
      return $self->downloadFile($URL,$path,'','',$timestamp);
    }

  }
}

  print STDOUT $req->as_string;
  print STDOUT $res->as_string;
  return 0;
}


}


sub uploadFile(*$$$$){

  my $self = shift;
  my $URL = shift;
  my $chunk = shift;
  my $chunkSize = shift;
  my $chunkRange = shift;
  my $filetype = shift;


my $req = new HTTP::Request PUT => $URL;
$req->protocol('HTTP/1.1');
$req->header('Authorization' => 'GoogleLogin auth='.$self->{_authwritely});
#$req->header('Authorization' => 'GoogleLogin auth='.$self->{_authwise});
$req->header('GData-Version' => '3.0');
$req->content_type($filetype);
$req->content_length($chunkSize);
$req->header('Content-Range' => $chunkRange);
$req->content($$chunk);
my $res = $self->{_ua}->request($req);


if($res->is_success or $res->code == 308){

  	my $block = $res->as_string;
	my ($resourceType,$resourceID);
	while (my ($line) = $block =~ m%([^\n]*)\n%){

		$block =~ s%[^\n]*\n%%;

	    if ($line =~ m%\<gd\:resourceId\>%){
	    	($resourceType,$resourceID) = $line =~ m%\<gd\:resourceId\>([^\:]*)\:?([^\<]*)\</gd:resourceId\>%;
	    }

	}


  return $resourceID;
}else{
  print STDERR "error";
  print STDOUT $req->headers_as_string;
  print STDOUT $res->as_string;
  return 0;
}


}



sub createFile(*$$$$){

	my $self = shift;
  	my $URL = shift;
  	my $fileSize = shift;
  	my $file = shift;
  	my $fileType = shift;


  	my $content = '<?xml version="1.0" encoding="UTF-8"?>
	<entry xmlns="http://www.w3.org/2005/Atom" xmlns:docs="http://schemas.google.com/docs/2007">
  	<title>'.$file.'</title>
	</entry>'."\n\n";

#  convert=false prevents plain/text from becoming docs
	my $req = new HTTP::Request POST => $URL.'?convert=false';
	$req->protocol('HTTP/1.1');
	$req->header('Authorization' => 'GoogleLogin auth='.$self->{_authwritely});
#	$req->header('Authorization' => 'GoogleLogin auth='.$self->{_authwise});
	$req->header('GData-Version' => '3.0');
#	$req->header('X-Upload-Content-Type' => 'application/pdf');
	$req->header('X-Upload-Content-Type' => $fileType);
	$req->header('X-Upload-Content-Length' => $fileSize);
	$req->content_length(length $content);
	$req->content_type('application/atom+xml');
	$req->content($content);

	my $res = $self->{_ua}->request($req);

	if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  		print LOG $req->as_string;
  		print LOG $res->as_string;
  		close(LOG);
	}

	if($res->is_success){
  		print STDOUT "success --> $URL\n\n";

  		my $block = $res->as_string;

  		while (my ($line) = $block =~ m%([^\n]*)\n%){

    		$block =~ s%[^\n]*\n%%;

#		    if ($line =~ m%\<gd\:resourceId\>%){
#		    	my ($resourceType,$resourceID) = $line =~ m%\<gd\:resourceId\>([^\:]*)\:?([^\<]*)\</gd:resourceId\>%;
#
#	      		return $resourceID;
 #   		}

		    if ($line =~ m%^Location:%){
      			($URL) = $line =~ m%^Location:\s+(\S+)%;
	      		return $URL;
    		}

  		}

	}else{
		print STDOUT $req->as_string;
  		print STDOUT $res->as_string;
  		return 0;
	}

}

sub createFolder(*$$){

	my $self = shift;
  	my $URL = shift;
  	my $folder = shift;


  	my $content = '<?xml version="1.0" encoding="UTF-8"?>
<entry xmlns="http://www.w3.org/2005/Atom">
  <category scheme="http://schemas.google.com/g/2005#kind"
      term="http://schemas.google.com/docs/2007#folder"/>
        		<title>'.$folder.'</title>
	</entry>'."\n\n";

	my $req = new HTTP::Request POST => $URL;
	$req->protocol('HTTP/1.1');
	$req->header('Authorization' => 'GoogleLogin auth='.$self->{_authwritely});
#	$req->header('Authorization' => 'GoogleLogin auth='.$self->{_authwise});
	$req->header('GData-Version' => '3.0');
	$req->content_length(length $content);
	$req->content_type('application/atom+xml');
	$req->content($content);

	my $res = $self->{_ua}->request($req);

	if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  		print LOG $req->as_string;
  		print LOG $res->as_string;
  		close(LOG);
	}

	if($res->is_success){
  		print STDOUT "success --> $URL\n\n";

  		my $block = $res->as_string;

  		while (my ($line) = $block =~ m%([^\n]*)\n%){

    		$block =~ s%[^\n]*\n%%;

		    if ($line =~ m%\<gd\:resourceId\>%){
		    	my ($resourceType,$resourceID) = $line =~ m%\<gd\:resourceId\>([^\:]*)\:?([^\<]*)\</gd:resourceId\>%;

	      		return $resourceID;
    		}

  		}

	}else{
		print STDOUT $req->as_string;
  		print STDOUT $res->as_string;
  		return 0;
	}

}

sub addFile(*$$){

	my $self = shift;
  	my $URL = shift;
  	my $file = shift;


  	my $content = '<?xml version="1.0" encoding="UTF-8"?>
<entry xmlns="http://www.w3.org/2005/Atom">
  <id>https://docs.google.com/feeds/default/private/full/file:'.$file.'</id>
</entry>'."\n\n";

	my $req = new HTTP::Request POST => $URL;
	$req->protocol('HTTP/1.1');
	$req->header('Authorization' => 'GoogleLogin auth='.$self->{_authwritely});
#	$req->header('Authorization' => 'GoogleLogin auth='.$self->{_authwise});
	$req->header('GData-Version' => '3.0');
	$req->content_length(length $content);
	$req->content_type('application/atom+xml');
	$req->content($content);

	my $res = $self->{_ua}->request($req);

	if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  		print LOG $req->as_string;
  		print LOG $res->as_string;
  		close(LOG);
	}

	if($res->is_success){
  		print STDOUT "success --> $URL\n\n";

  		my $block = $res->as_string;

  		while (my ($line) = $block =~ m%([^\n]*)\n%){

    		$block =~ s%[^\n]*\n%%;

		    if ($line =~ m%\<gd\:resourceId\>%){
		    	my ($resourceType,$resourceID) = $line =~ m%\<gd\:resourceId\>([^\:]*)\:?([^\<]*)\</gd:resourceId\>%;

	      		return $resourceID;
    		}

  		}

	}else{
		print STDOUT $req->as_string;
  		print STDOUT $res->as_string;
  		return 0;
	}

}


sub deleteFile(*$$){

	my $self = shift;
  	my $folderID = shift;
  	my $fileID = shift;

	my $req = new HTTP::Request DELETE => 'https://docs.google.com/feeds/default/private/full/folder%3A'.$folderID.'/contents/file%3A'.$fileID;
	$req->protocol('HTTP/1.1');
	$req->header('Authorization' => 'GoogleLogin auth='.$self->{_authwritely});
#	$req->header('Authorization' => 'GoogleLogin auth='.$self->{_authwise});
	$req->header('GData-Version' => '3.0');
	$req->header('If-Match' => '*');


	my $res = $self->{_ua}->request($req);

	if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  		open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  		print LOG $req->as_string;
  		print LOG $res->as_string;
  		close(LOG);
	}

	if($res->is_success){


  		my $block = $res->as_string;

  		while (my ($line) = $block =~ m%([^\n]*)\n%){

    		$block =~ s%[^\n]*\n%%;

		    if ($line =~ m%\<gd\:resourceId\>%){
		    	my ($resourceType,$resourceID) = $line =~ m%\<gd\:resourceId\>([^\:]*)\:?([^\<]*)\</gd:resourceId\>%;

	      		return $resourceID;
    		}

  		}

	}else{
		print STDOUT $req->as_string;
  		print STDOUT $res->as_string;
  		return 0;
	}

}

sub editFile(*$$$$){

  my $self = shift;
  my $URL = shift;
  my $fileSize = shift;
  my $file = shift;
  my $fileType = shift;
my $content = '';

#convert=false prevents plain/text from becoming docs
my $req = new HTTP::Request PUT => $URL.'?new-revision=true';
$req->protocol('HTTP/1.1');
$req->header('Authorization' => 'GoogleLogin auth='.$self->{_authwritely});
#$req->header('Authorization' => 'GoogleLogin auth='.$self->{_authwise});
$req->header('GData-Version' => '3.0');
#$req->header('X-Upload-Content-Type' => 'application/pdf');
$req->header('If-Match' => '*');
$req->content_type($fileType);
$req->content_length(length $content);
$req->header('X-Upload-Content-Type' => $fileType);
$req->header('X-Upload-Content-Length' => $fileSize);
$req->content('');
my $res = $self->{_ua}->request($req);


if (pDrive::Config->DEBUG and pDrive::Config->DEBUG_TRN){
  open (LOG, '>>'.pDrive::Config->DEBUG_LOG);
  print LOG $req->as_string;
  print LOG $res->as_string;
  close(LOG);
}

if($res->is_success){
  print STDOUT "success --> $URL\n\n";

  my $block = $res->as_string;

  while (my ($line) = $block =~ m%([^\n]*)\n%){

    $block =~ s%[^\n]*\n%%;

    if ($line =~ m%^Location:%){
      ($URL) = $line =~ m%^Location:\s+(\S+)%;
      return $URL;
    }

  }

}else{
  print STDOUT $req->as_string;
  print STDOUT $res->as_string;
  return 0;
}


}


sub fixServerMD5(**){
  my $self = shift;
  my $memoryHash = shift;

}

sub readDriveListings(***){

my $self = shift;
my $driveListings = shift;
my $folders = shift;
my %newDocuments;

my $count=0;

  $$driveListings =~ s%\</entry\>%\n\</entry\>%g;

  while ($$driveListings =~ m%\<entry[^\>]+[^\n]+\n\</entry\>%){

    my ($entry) = $$driveListings =~ m%\<entry[^\>]+([^\n]+)\n\</entry\>%;
    $$driveListings =~ s%\<entry[^\>]+[^\n]+\n\</entry\>%\.%;


    my ($title) = $entry =~ m%\<title\>([^\<]+)\</title\>%;
    my ($updated) = $entry =~ m%\<updated\>([^\<]+)\</updated\>%;
    my ($published) = $entry =~ m%\<published\>([^\<]+)\</published\>%;
    my ($resourceType,$resourceID) = $entry =~ m%\<gd\:resourceId\>([^\:]*)\:?([^\<]*)\</gd:resourceId\>%;
    my ($downloadURL) = $entry =~ m%\<content type\=\'[^\']+\' src\=\'([^\']+)\'/\>%;
    my ($parentID,$folder) = $entry =~ m@\#parent\' type\=\'application/atom\+xml\' href\=\'[^\%]+\%3A([^\']+)\' title\=\'([^\']+)\'/\>@;
    my ($editURL) = $entry =~ m%\<link\s+rel\=\'http\:\/\/schemas.google.com\/g\/2005\#resumable-edit-media\'\s+type\=\'application\/atom\+xml\'\s+href\=\'([^\']+)\'\/\>%;
    my ($md5) = $entry =~ m%\<docs\:md5Checksum\>([^\<]+)\<\/docs\:md5Checksum\>%;

    # is a folder
    if ($resourceType eq 'folder'){

      # save the title
      $$folders{$resourceID}[FOLDER_TITLE] = $title;

      # is not a root folder
      if (defined $folder and $folder ne ''){

        $$folders{$resourceID}[FOLDER_ROOT] = NOT_ROOT;
        $$folders{$resourceID}[FOLDER_PARENT] = $parentID;

        # add the resourceID to the parent directory
        if ($#{${$folders}{$parentID}} >= FOLDER_SUBFOLDER){

          $$folders{$parentID}[$#{${$folders}{$parentID}}+1] = $resourceID;

        }else{

          $$folders{$parentID}[FOLDER_SUBFOLDER] = $resourceID;

        }

      # is a root folder
      }else{

        $$folders{$resourceID}[FOLDER_ROOT] = IS_ROOT;

      }
      print STDOUT 'folder = '.(defined $title? $title:'').' '. (defined $resourceID? $resourceID:'').' *'.(defined $parentID? $parentID: '')."  \n";

    }else{

      $updated =~ s%\D+%%g;
      ($updated) = $updated =~ m%^(\d{14})%;
      $newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}] = pDrive::Time::getEPOC($updated);
#      $newDocuments{$resourceID}[pDrive::DBM->D->{'server_updated'}] = $updated;

      $newDocuments{$resourceID}[pDrive::DBM->D->{'server_link'}] = $downloadURL;
      $newDocuments{$resourceID}[pDrive::DBM->D->{'server_edit'}] = $editURL;
      $newDocuments{$resourceID}[pDrive::DBM->D->{'server_md5'}] = $md5;
      $newDocuments{$resourceID}[pDrive::DBM->D->{'type'}] = $resourceType;
      $newDocuments{$resourceID}[pDrive::DBM->D->{'parent'}] = $parentID;
      $newDocuments{$resourceID}[pDrive::DBM->D->{'title'}] = $title;
      $newDocuments{$resourceID}[pDrive::DBM->D->{'published'}] = $published;
    }
    $count++;

  }


print STDOUT "entries = $count\n";
return %newDocuments;
}

1;
