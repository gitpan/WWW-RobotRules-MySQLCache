package WWW::RobotRules::MySQLCache;

use 5.005;
use strict;
use warnings;

use DBI;
use WWW::RobotRules::Parser;
use Carp();
use LWP::Simple qw(head);
use DateTime::Format::Epoch;
use vars qw(@ISA $VERSION);
use Exporter;

@ISA = qw(Exporter);

	
use vars qw/%tables/;
# @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ); #do not export anything

$VERSION = '0.02';

sub new{
	my $class = shift;
	my $host = shift;
	my $user_name = shift;
	my $password = shift;
	my $database = shift;

	my $dsn = "dbi:mysql:database=$database:host=$host";
	my $dbConnection = DBI->connect($dsn, $user_name, $password) or die "Connection Error: $DBI::errstr\n";
	my $self = bless { db => $dbConnection}, $class;

	$self; 
}


sub create_db{
	my $self = shift;
	my $create_location = "CREATE TABLE location(robot_id integer PRIMARY KEY auto_increment not null, location varchar(255) not null, created_on datetime not null)";
	$self->{'db'}->do($create_location)  or die "Unable to create table `location`.";
	my $create_rules = "CREATE TABLE rules(robot_id integer not null, userAgent varchar(255) not null, rule_loc varchar(255) not null)";
        $self->{'db'}->do($create_rules) or die "Unable to create table `rules`";
	1;
}

sub load_db{
	#get last updated time
	#if not in database then add to it
	#if not updated, update it
	my $self = shift;
	my $url = shift;
	$url =~ s/\/$//;
	my $robot_url = $url . "/robots.txt";
  	my $parser = WWW::RobotRules::Parser->new;
	my $modified_time = $self->formatted_date_time($robot_url);
	my $select1 = $self->{'db'}->prepare("SELECT robot_id from location where location = '".$url."'")   or die "Couldn't prepare statement: " . $self->{'db'}->errstr;
	$select1->execute()  or die "Couldn't execute statement: " . $select1->errstr;
	my $select2 = $self->{'db'}->prepare("SELECT robot_id from location where location = '".$url."' and  created_on  = '".$modified_time."'")    or die "Couldn't prepare statement: " . $self->{'db'}->errstr;
	$select2->execute()  or die "Couldn't execute statement: " . $select2->errstr;
	my $rows1 = $select1->rows;
	my $rows2 = $select2->rows;
	my $robot_id;
	if($rows1 == 0){	
		my %rules = $parser->parse_uri($robot_url);
		my $insert = $self->{'db'}->prepare("INSERT into location (location,created_on) values ('$url','$modified_time')")    or die "Couldn't prepare statement: " . $self->{'db'}->errstr;
		#	print "INSERT into location (location,created_on) values ('".$url."','".$modified_time."')";
		$insert->execute() or die "Couldn't execute statement: " . $insert->errstr;
		my $select3 = $self->{'db'}->prepare("SELECT robot_id from location where location = '".$url."' and  created_on  = '".$modified_time."'")   or die "Couldn't prepare statement: " . $self->{'db'}->errstr;
		$select3->execute()  or die "Couldn't execute statement: " . $select3->errstr;
		if(my $row = $select3->fetchrow_hashref()){
			$robot_id = $row->{'robot_id'};
		}
		foreach (my ($key, $value) = each %rules) {
			foreach(@$value){
				my $insert_rules = $self->{'db'}->prepare("INSERT into rules VALUES($robot_id,'".$key."','".$_."')")   or die "Couldn't prepare statement: " . $self->{'db'}->errstr;
				#print "\nINSERT into rules VALUES($robot_id,'".$agent."','".$url.$_."')";#	print "\tINSERT into rules ($robot_id,'".$agent."','".$url.$_."')\n";
				$insert_rules->execute()  or die "Couldn't execute statement: " . $insert_rules->errstr;
			}
		}
	}
	elsif($rows2 == 0){
		my $row = $select1->fetchrow_hashref();
		$self->{'db'}->do("update location set created_on = '".$modified_time."' where robot_id = ".$row->{'robot_id'});
		$self->{'db'}->do("delete from rules where robot_id = ".$row->{'robot_id'});
		my %rules = $parser->parse_uri($robot_url);	
		foreach (my ($key, $value) = each %rules) {
			foreach(@$value){ 		   		
					my $insert_rules = $self->{'db'}->prepare("INSERT into rules VALUES(".$row->{'robot_id'}.",'".$key."','".$_."')")   or die "Couldn't prepare statement: " . $self->{'db'}->errstr;
					#print "\nINSERT into rules VALUES(".$row->{'robot_id'}.",'".$agent."','".$url.$_."')";
					$insert_rules->execute()  or die "Couldn't execute statement: " . $insert_rules->errstr;
			}
		}
		
	}
	else{	
			#do nothing
	}
} 

sub formatted_date_time{
	my $self = shift;
	my $url = shift;
	my ($content_type, $document_length, $modified_time, $expires, $server) = LWP::Simple::head($url);
	my $dt = DateTime->new( year => 1970, month => 1, day => 1 );
        my $formatter = DateTime::Format::Epoch->new(
                      epoch          => $dt,
                      unit           => 'seconds',
                      type           => 'int',    # or 'float', 'bigint'
                      skip_leap_seconds => 1,
                      start_at       => 0,
                      local_epoch    => undef,
                  );
	my $time = $formatter->parse_datetime( $modified_time );
	$time =~ s/T/ /g;
	$time;
}

sub  is_present{
	my $self = shift;
	my $location = shift;
	$location =~ s/\/$//;
	my $modified_time = $self->formatted_date_time($location."/robots.txt");
	my $string = "SELECT * from location where location = '$location' and created_on = '".$modified_time."'";
        my $search = $self->{'db'}->prepare($string)   or die "Couldn't prepare statement: " . $self->{'db'}->errstr;
	my $result;
	$search->execute()  or die "Couldn't execute statement: " . $search->errstr;
	if($search->rows == 0){
                $result = 0;
        }
        else{
                $result = 1;
        }
	$result;

}

sub is_allowed{
	my $self = shift;
	my $user_agent = shift;
	my $url = shift;
	my $allowed_flag = 1;
	$url =~ m|(\w+)://([^/:]+)(:\d+)?/(.*)|;
	my $protocol = $1;
	my $domain_name = $2;
	my $port = ($3) ? $3 : '';
	my $uri = "/" . $4;
	#print $uri."\n";
	#print "\n".$protocol.'://'.$domain_name.$port;
	my $query = "select rules.* from rules,location where (location REGEXP '".$protocol."://".$domain_name.$port."' OR location REGEXP '".$protocol."://www.".$domain_name.$port."')and rules.robot_id = location.robot_id  and (userAgent = '*' or userAgent = '".$user_agent."')";
	#print "\n".$query."\n";
	my $site = $self->{db}->prepare($query)   or die "Couldn't prepare statement: " . $self->{'db'}->errstr;
	$site->execute()  or die "Couldn't execute statement: " . $site->errstr;
	my $row;
	while($row = $site->fetchrow_hashref()){
		if(index($uri,$row->{'rule_loc'}) >=0) {
			$allowed_flag = 0;
			last;
		}
	}	
	#select from rules where userAgent = myUserAgent or *
	#loop through results for $uri =~ /^ruleLocation;
		#if match, break, return 0
	$allowed_flag;	
}

1;
__END__

=head1 NAME

	WWW::RobotRules::MySQLCache - Perl extension for maintaining a robots.txt in a MySQL database

=head1 SYNOPSIS

  use WWW::RobotRules::MySQLCache;
  
  my $rulesDB = WWW::RobotRules::MySQLCache->new($host,$username,$password,$database);
  
  $rulesDB->create_db(); # if a database needs to be created.
  
  if(### your check of robots_txt is present for a server###)
  	$rulesDB->load_db($location);
  
  my $file_present = is_present($location);

  my $flag = $rulesDB->is_allowed($user_agent,$url_or_folder);
  #OR
  if($rulesDB->is_allowed($user_agent,$url)){
  	#crawl $url
  }
  #OR
  if($rulesDB->is_allowed($user_agent,$folder)){
        #crawl $folder
  }

=head1 DESCRIPTION

	One can store multiple parsed robots.txt rules in a MySQL database. 

	It uses DBI and WWW::RobotRules::Parser to fetch robots.txt and extract rules and 
        LWP::Simple to test freshness of a robots.txt file.


=head1  METHODS
  
=head2 my $rulesDB = new($databaseServer,$username,$password,$database);

	Database connection parameters (Same as used in DBI).
		1. database server to connect to.
		2. username
		3. password
		4. database to be used.


=head2 create_db();

	Creates 2 tables:
		1: location: Stores location of robots.txt.
		2: rules: Stores rules extracted from robots.txt file(s).  

=head2  load_db($location);

	Loads rules from a robots.txt if we don't have them in the database.
	If the copy of robots.txt in database is not consistent with the one 
        just fetched from the server, the database is updated.
	

=head2 my $file_present = is_present($location);

	Checks if a particular robots.txt is present or not. 
	Returns 0 if 
		a) $location/robots.txt does not exists database OR
		b) $location/robots.txt is not a recently updated file 
	Returns 1 otherwise.

=head2  my $trueOrFalse = is_allowed($user_agent, $url_or_folder);

	Checks of a userAgent is allowed to fetch a url or access pages in a folder.

	Returns 1(allowed) or 0(disallowed).


=head1 SEE ALSO


DBI, WWW::RobotRules::Parser, WWW::LWP::Simple

=head1 AUTHOR

A. M. Patwa, E<lt>patwa DOT ankur -AT- gmail DOT  comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by A. M. Patwa

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
