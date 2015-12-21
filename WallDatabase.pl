# WallDatabase.pl
use warnings;
use strict;
use DBI;
use DBD::SQLite;
use Getopt::Long;
use Digest::MD5;

# Command line variables
	# help
	# version
	# database file
	# add
	# edit
	
my ($help, $version, @add, @edit, $get, $DBFILE, $DATABASEHANDLE, $createdb,
	$wallpaperdir, $test, $random);

# Get command line options

GetOptions ('dbfile=s' => \$DBFILE,
			'help!' => \$help,
			'version!' => \$version,
			'add=s{1,}' => \@add,
			'edit=s{2,}' => \@edit,
			'get=s' => \$get,
			'random=s' => \$random,
			'createdb!' => \$createdb,
			'wallpaperdir|dir=s' => \$wallpaperdir,
			'test=s' => \$test);

# Display help

# Display version
print("Version 0.0\n") if ($version);

# Setup
useDatabase();

# Tests
if ($test && $test eq 'selectAllWallpapers') {
	selectAllWallpapers();
	exit(0);
} elsif ($test && $test eq 'selectAllTags') {
	print("Selecting all tags\n");
	selectAllTags();
	exit(0);
} elsif ($test && $test eq 'selectAllIsTagged') {
	print("Selecting all from IsTagged\n");
	selectAllIsTagged();
	exit(0);
}

# Main program

if (@add) {
	addWallpaper();
} elsif ($get) {
	getTagged();
}

# Set database file

sub useDatabase {
	# Check whether file exists
	# Connect to the database
	die("Database not specified.\n") unless $DBFILE;
	die("File not found.\n") unless (-f $DBFILE) || $createdb;
	$DATABASEHANDLE = DBI->connect("dbi:SQLite:dbname=$DBFILE")
		|| die("Cannot connect to database: $DBI::errstr");
	createDB() if $createdb;
}

# Create database

sub createDB {
	# Create tables
	
	# Wallpaper table
		# ID
		# filename
		# MD5 hash
		
	$DATABASEHANDLE->do("CREATE TABLE Wallpaper
							(ID INTEGER PRIMARY KEY,
							filename TEXT,
							md5 TEXT);");
	
	# Tag table
		# ID
		# tag name
		
	$DATABASEHANDLE->do("CREATE TABLE Tag
							(ID INTEGER PRIMARY KEY,
							tag TEXT);");
		
	# IsTagged table
		# Wallpaper ID
		# Tag ID
	
	$DATABASEHANDLE->do("CREATE TABLE IsTagged
							(wallpaper INTEGER,
							tag INTEGER,
							FOREIGN KEY(wallpaper) REFERENCES Wallpaper(ID),
							FOREIGN KEY(tag) REFERENCES Tag(ID))");
}

# Add wallpaper to database

sub addWallpaper {
	# Arguments:
		# filename
		# list of tags
	#print("add: @add\n"); # debug
	my $wallpaper = shift @add;
	my @tags = @add;
	# Beware of list flattening
	#print("Tags: @tags"); # debug
	# Check whether the file exists
	die("File does not exist.\n") unless (-e $wallpaper) or (-e "$wallpaperdir$wallpaper");
	if (not -e $wallpaper) {
		$wallpaper = $wallpaperdir . $wallpaper;
	}
	# MD5 hash it
	open (my $fh, "<", $wallpaper) or die("Cannot open file: $!");
	binmode($fh);
	my $md5 = Digest::MD5->new;
	while (<$fh>) {
		$md5->add($_);
	}
	close($fh);
	my $hash = $md5->hexdigest;
	# Check whether the Wallpaper is already in the database
	my $wallpaperid;
	my $quoted = $DATABASEHANDLE->quote($wallpaper); # debug
	# print("$quoted\n"); # debug
	my $sth = $DATABASEHANDLE->prepare("SELECT * FROM Wallpaper WHERE Wallpaper.filename = ?");
	$sth->execute($quoted);
	my $row = $sth->fetchall_arrayref();
	if (not @$row) {
		# Add it to the database
		# SQLite should automatically AUTOINCREMENT the ID if given a NULL value
		my $sth = $DATABASEHANDLE->prepare("INSERT INTO Wallpaper VALUES (NULL, ?, ?);");
		$sth->execute($quoted, $hash);
		$wallpaperid = $DATABASEHANDLE->last_insert_id(undef, undef, "Wallpaper", undef);
		#print("Wallpaper ID from last_insert_id call: $wallpaperid\n"); # debug
	} else {
		$wallpaperid = @$row[0]->[0];
		#print("Wallpaper ID from SELECT statement: $wallpaperid\n"); # debug
	}
	# Add tags to the database
	foreach my $tag (@tags) {
		# Make $tag lowercase to prevent stupid duplicates
		$tag = lc($tag);
		# Check if the tag already exists
		#print("$tag\n"); # debug
		my $sth = $DATABASEHANDLE->prepare("SELECT * FROM Tag WHERE Tag.tag = ?");
		$sth->execute($tag);
		my $row = $sth->fetchall_arrayref();
		die("SELECT failed") if not defined $row;
		#print("$row", @$row, "@$row", $row->[0], "\n"); # debug
		if (not @$row) {
			$DATABASEHANDLE->do("INSERT INTO Tag VALUES (NULL, '$tag');");
		}
	}
	# Add relationship between tags and filename to the database
	foreach my $tag (@tags) {
		# get the Tag.ID
		my $sth = $DATABASEHANDLE->prepare("SELECT Tag.ID FROM Tag WHERE Tag.tag = ?");
		$sth->execute($tag);
		my $row = $sth->fetchall_arrayref();
		my $tagid = $row->[0]->[0];
		#print("$tagid\n"); # debug
		# check whether there already exists a relationship
		#	between the Wallpaper.ID and that Tag.ID
		$row = $DATABASEHANDLE->selectall_arrayref("SELECT * FROM IsTagged 
								WHERE IsTagged.wallpaper = $wallpaperid
								AND IsTagged.tag = $tagid");
		# if not, add it
		unless ($row->[0]) {
			$DATABASEHANDLE->do("INSERT INTO IsTagged VALUES
								($wallpaperid, $tagid)");
		}
	}
}

# Delete wallpaper from database

sub deleteWallpaper {
	# Arguments:
		# filename
	# Check whether the file exists
	# Check file against MD5 hash
	# Remove the filename from the database
	# Remove relationships between removed wallpaper and its tags from the database
	# Remove tags which are not referenced by any wallpaper in the database
}

# Edit tags of wallpaper in database

sub editTags {
	# Arguments:
		# filename
		# list of tags
	# Remove tags that start with a "-"
		# for example, "-nature"
	# Add tags that start with a "+"
		# for example, "+anime"
}

# List all wallpapers corresponding to a tag

sub getTagged {
	my $tag = $get;
	my $sth = $DATABASEHANDLE->prepare("SELECT Wallpaper.filename
										FROM Wallpaper, IsTagged, Tag
										WHERE Wallpaper.ID = IsTagged.wallpaper
										AND Tag.ID = IsTagged.tag
										AND Tag.tag = ?");
	$sth->execute($tag);
	my $row = $sth->fetchall_arrayref();
	foreach my $wallpaper (@$row) {
		print("@$wallpaper\n");
	}
}

# Get one random wallpaper that corresponds to a tag

# List all wallpapers

sub selectAllWallpapers {
	my $row = $DATABASEHANDLE->selectall_arrayref("SELECT * FROM Wallpaper");
	die("Nothing in Wallpaper table.") if ($row eq "0E0");
	foreach (@$row) {
		print("@$_\n");
	}
}

# List all tags

sub selectAllTags {
	my $row = $DATABASEHANDLE->selectall_arrayref("SELECT * FROM Tag");
	die("Nothing in Tag table.") if ($row eq "0E0");
	foreach (@$row) {
		print("@$_\n");
	}
}

# List all entries in IsTagged

sub selectAllIsTagged {
	my $row = $DATABASEHANDLE->selectall_arrayref("SELECT * FROM IsTagged");
	die("Nothing in IsTagged table.") if ($row eq "0E0");
	foreach (@$row) {
		print("@$_\n");
	}
}

### Musings on database schema:
# I don't know whether I want to use INTEGER IDs for my tables
# because they are not absolutely helpful, and they do not 
# maintain consistency with BCNF.
# So I know Wallpaper needs a filename and an MD5 hash, but both
# of them are minimal superkeys, so there is really no need for
# an INTEGER ID.
# For Tag, it only exists to have a name and an ID, both of which
# determine the other.
# So I could really do without a Tag table, and just have an IsTagged
# table with a Wallpaper ID and a tag name.
# I will keep it the inefficient way until I'm sure I will not need
# to extend the functionality.
