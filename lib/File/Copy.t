#!./perl -w

BEGIN {
   if( $ENV{PERL_CORE} ) {
        chdir 't' if -d 't';
        @INC = '../lib';
    }
}

use strict;
use warnings;

use Test::More;

my $TB = Test::More->builder;

plan tests => 459;

# We're going to override rename() later on but Perl has to see an override
# at compile time to honor it.
BEGIN { *CORE::GLOBAL::rename = sub { CORE::rename($_[0], $_[1]) }; }


use File::Copy qw(copy move cp);
use Config;


foreach my $code ("copy()", "copy('arg')", "copy('arg', 'arg', 'arg', 'arg')",
                  "move()", "move('arg')", "move('arg', 'arg', 'arg')"
                 )
{
    eval $code;
    like $@, qr/^Usage: /, "'$code' is a usage error";
}


for my $cross_partition_test (0..1) {
  {
    # Simulate a cross-partition copy/move by forcing rename to
    # fail.
    no warnings 'redefine';
    *CORE::GLOBAL::rename = sub { 0 } if $cross_partition_test;
  }

  # First we create a file
  open(F, ">file-$$") or die $!;
  binmode F; # for DOSISH platforms, because test 3 copies to stdout
  printf F "ok\n";
  close F;

  copy "file-$$", "copy-$$";

  open(F, "copy-$$") or die $!;
  my $foo = <F>;
  close(F);

  is -s "file-$$", -s "copy-$$", 'copy(fn, fn): files of the same size';

  is $foo, "ok\n", 'copy(fn, fn): same contents';

  print("# next test checks copying to STDOUT\n");
  binmode STDOUT unless $^O eq 'VMS'; # Copy::copy works in binary mode
  # This outputs "ok" so its a test.
  copy "copy-$$", \*STDOUT;
  $TB->current_test($TB->current_test + 1);
  unlink "copy-$$" or die "unlink: $!";

  open(F,"file-$$");
  copy(*F, "copy-$$");
  open(R, "copy-$$") or die "open copy-$$: $!"; $foo = <R>; close(R);
  is $foo, "ok\n", 'copy(*F, fn): same contents';
  unlink "copy-$$" or die "unlink: $!";

  open(F,"file-$$");
  copy(\*F, "copy-$$");
  close(F) or die "close: $!";
  open(R, "copy-$$") or die; $foo = <R>; close(R) or die "close: $!";
  is $foo, "ok\n", 'copy(\*F, fn): same contents';
  unlink "copy-$$" or die "unlink: $!";

  require IO::File;
  my $fh = IO::File->new(">copy-$$") or die "Cannot open copy-$$:$!";
  binmode $fh or die $!;
  copy("file-$$",$fh);
  $fh->close or die "close: $!";
  open(R, "copy-$$") or die; $foo = <R>; close(R);
  is $foo, "ok\n", 'copy(fn, io): same contents';
  unlink "copy-$$" or die "unlink: $!";

  require FileHandle;
  $fh = FileHandle->new(">copy-$$") or die "Cannot open copy-$$:$!";
  binmode $fh or die $!;
  copy("file-$$",$fh);
  $fh->close;
  open(R, "copy-$$") or die $!; $foo = <R>; close(R);
  is $foo, "ok\n", 'copy(fn, fh): same contents';
  unlink "file-$$" or die "unlink: $!";

  ok !move("file-$$", "copy-$$"), "move on missing file";
  ok -e "copy-$$",                '  target still there';

  # Doesn't really matter what time it is as long as its not now.
  my $time = 1000000000;
  utime( $time, $time, "copy-$$" );

  # Recheck the mtime rather than rely on utime in case we're on a
  # system where utime doesn't work or there's no mtime at all.
  # The destination file will reflect the same difficulties.
  my $mtime = (stat("copy-$$"))[9];

  ok move("copy-$$", "file-$$"), 'move';
  ok -e "file-$$",              '  destination exists';
  ok !-e "copy-$$",              '  source does not';
  open(R, "file-$$") or die $!; $foo = <R>; close(R);
  is $foo, "ok\n", 'contents preserved';

  TODO: {
    local $TODO = 'mtime only preserved on ODS-5 with POSIX dates and DECC$EFS_FILE_TIMESTAMPS enabled' if $^O eq 'VMS';

    my $dest_mtime = (stat("file-$$"))[9];
    is $dest_mtime, $mtime,
      "mtime preserved by copy()". 
      ($cross_partition_test ? " while testing cross-partition" : "");
  }

  # trick: create lib/ if not exists - not needed in Perl core
  unless (-d 'lib') { mkdir 'lib' or die $!; }
  copy "file-$$", "lib";
  open(R, "lib/file-$$") or die $!; $foo = <R>; close(R);
  is $foo, "ok\n", 'copy(fn, dir): same contents';
  unlink "lib/file-$$" or die "unlink: $!";

  # Do it twice to ensure copying over the same file works.
  copy "file-$$", "lib";
  open(R, "lib/file-$$") or die $!; $foo = <R>; close(R);
  is $foo, "ok\n", 'copy over the same file works';
  unlink "lib/file-$$" or die "unlink: $!";

  { 
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= join '', @_ };
    ok copy("file-$$", "file-$$"), 'copy(fn, fn) succeeds';

    like $warnings, qr/are identical/, 'but warns';
    ok -s "file-$$", 'contents preserved';
  }

  move "file-$$", "lib";
  open(R, "lib/file-$$") or die "open lib/file-$$: $!"; $foo = <R>; close(R);
  is $foo, "ok\n", 'move(fn, dir): same contents';
  ok !-e "file-$$", 'file moved indeed';
  unlink "lib/file-$$" or die "unlink: $!";

  SKIP: {
    skip "Testing symlinks", 3 unless $Config{d_symlink};

    open(F, ">file-$$") or die $!;
    print F "dummy content\n";
    close F;
    symlink("file-$$", "symlink-$$") or die $!;

    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= join '', @_ };
    ok !copy("file-$$", "symlink-$$"), 'copy to itself (via symlink) fails';

    like $warnings, qr/are identical/, 'emits a warning';
    ok !-z "file-$$", 
      'rt.perl.org 5196: copying to itself would truncate the file';

    unlink "symlink-$$" or die $!;
    unlink "file-$$" or die $!;
  }

  SKIP: {
    skip "Testing hard links", 3 
         if !$Config{d_link} or $^O eq 'MSWin32' or $^O eq 'cygwin';

    open(F, ">file-$$") or die $!;
    print F "dummy content\n";
    close F;
    link("file-$$", "hardlink-$$") or die $!;

    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= join '', @_ };
    ok !copy("file-$$", "hardlink-$$"), 'copy to itself (via hardlink) fails';

    like $warnings, qr/are identical/, 'emits a warning';
    ok ! -z "file-$$",
      'rt.perl.org 5196: copying to itself would truncate the file';

    unlink "hardlink-$$" or die $!;
    unlink "file-$$" or die $!;
  }

  open(F, ">file-$$") or die $!;
  binmode F;
  print F "this is file\n";
  close F;

  my $copy_msg = "this is copy\n";
  open(F, ">copy-$$") or die $!;
  binmode F;
  print F $copy_msg;
  close F;

  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, join '', @_ };

  # pie-$$ so that we force a non-constant, else the numeric conversion (of 0)
  # is cached and we don't get a warning the second time round
  is eval { copy("file-$$", "copy-$$", "pie-$$"); 1 }, undef,
    "a bad buffer size fails to copy";
  like $@, qr/Bad buffer size for copy/, "with a helpful error message";
  unless (is scalar @warnings, 1, "There is 1 warning") {
    diag $_ foreach @warnings;
  }

  is -s "copy-$$", length $copy_msg, "but does not truncate the destination";
  open(F, "copy-$$") or die $!;
  $foo = <F>;
  close(F);
  is $foo, $copy_msg, "nor change the destination's contents";

  unlink "file-$$" or die $!;
  unlink "copy-$$" or die $!;
}


SKIP: {
    my @tests = (
        [0000,  0777,  0777,  0777],
        [0000,  0751,  0751,  0644],
        [0022,  0777,  0755,  0206],
        [0022,  0415,  0415,  0666],
        [0077,  0777,  0700,  0333],
        [0027,  0755,  0750,  0251],
        [0777,  0751,  0000,  0215],
    );

    my $skips = @tests * 6 * 8;

    skip "-- Copy preserves RMS defaults, not POSIX permissions.", $skips
          if $^O eq 'VMS';
    skip "Copy doesn't set file permissions correctly on Win32.",  $skips
          if $^O eq "MSWin32";

    # Just a sub to get better failure messages.
    sub __ ($) {
        my $perm   = shift;
        my $id     = 07000 & $perm;
           $id   >>= 9;
        $perm     &= 0777;
        my @chunks = map {(qw [--- --x -w- -wx r-- r-x rw- rwx]) [$_]}
                     split // => sprintf "%03o" => $perm;
        if ($id & 4) {$chunks [0] =~ s/(.)$/$1 eq '-' ? 'S' : 's'/e;}
        if ($id & 2) {$chunks [1] =~ s/(.)$/$1 eq '-' ? 'S' : 's'/e;}
        if ($id & 1) {$chunks [2] =~ s/(.)$/$1 eq '-' ? 'T' : 't'/e;}
        join "" => @chunks;
    }
    # Testing permission bits.
    my $src   = "file-$$";
    my $copy1 = "copy1-$$";
    my $copy2 = "copy2-$$";
    my $copy3 = "copy3-$$";
    my $copy4 = "copy4-$$";
    my $copy5 = "copy5-$$";
    my $copy6 = "copy6-$$";

    open my $fh => ">", $src   or die $!;
    close   $fh                or die $!;

    open    $fh => ">", $copy3 or die $!;
    close   $fh                or die $!;

    open    $fh => ">", $copy6 or die $!;
    close   $fh                or die $!;

    my $old_mask = umask;
    foreach my $test (@tests) {
        foreach my $id (0 .. 7) {
            my ($umask, $s_perm, $c_perm1, $c_perm3) = @$test;
            # Make sure the copies doesn't exist.
            ! -e $_ or unlink $_ or die $! for $copy1, $copy2, $copy4, $copy5;

            $s_perm  |= $id << 9;
            $c_perm1 |= $id << 9;
            diag(sprintf "Src permission: %04o; umask %03o\n", $s_perm, $umask)
                unless ($ENV{PERL_CORE});

	    # Test that we can actually set a file to the correct permission.
	    # Slightly convoluted, because some operating systems will let us
	    # set a directory, but not a file. These should all work:
	    mkdir $copy1 or die "Can't mkdir $copy1: $!";
	    chmod $s_perm, $copy1
		or die sprintf "Can't chmod %o $copy1: $!", $s_perm;
	    rmdir $copy1
		or die sprintf "Can't rmdir $copy1: $!";
	    open my $fh0, '>', $copy1 or die "Can't open $copy1: $!";
	    close $fh0 or die "Can't close $copy1: $!";
	    unless (chmod $s_perm, $copy1) {
		$TB->skip(sprintf "Can't chmod $copy1 to %o: $!", $s_perm)
		    for 1..6;
		next;
	    }
            my $perm0 = (stat $copy1) [2] & 07777;
	    unless ($perm0 == $s_perm) {
		$TB->skip(sprintf "chmod %o $copy1 lies - we actually get %o",
			  $s_perm, $perm0)
		    for 1..6;
		next;
	    }
	    unlink $copy1 or die "Can't unlink $copy1: $!";

            (umask $umask) // die $!;
            chmod $s_perm  => $src   or die sprintf "$!: $src => %o", $s_perm;
            chmod $c_perm3 => $copy3 or die $!;
            chmod $c_perm3 => $copy6 or die $!;

            open my $fh => "<", $src or die $!;

            copy ($src, $copy1);
            copy ($fh,  $copy2);
            copy ($src, $copy3);
            cp   ($src, $copy4);
            cp   ($fh,  $copy5);
            cp   ($src, $copy6);

            my $permdef = 0666 & ~$umask;
            my $perm1 = (stat $copy1) [2] & 07777;
            my $perm2 = (stat $copy2) [2] & 07777;
            my $perm3 = (stat $copy3) [2] & 07777;
            my $perm4 = (stat $copy4) [2] & 07777;
            my $perm5 = (stat $copy5) [2] & 07777;
            my $perm6 = (stat $copy6) [2] & 07777;
            is (__$perm1, __$permdef, "Permission bits set correctly");
            is (__$perm2, __$permdef, "Permission bits set correctly");
            is (__$perm4, __$c_perm1, "Permission bits set correctly");
            is (__$perm5, __$c_perm1, "Permission bits set correctly");
            TODO: {
                local $TODO = 'Permission bits inconsistent under cygwin'
                   if $^O eq 'cygwin';
                is (__$perm3, __$c_perm3, "Permission bits not modified");
                is (__$perm6, __$c_perm3, "Permission bits not modified");
            }
        }
    }
    umask $old_mask or die $!;

    # Clean up.
    ! -e $_ or unlink $_ or die $! for $src, $copy1, $copy2, $copy3,
                                             $copy4, $copy5, $copy6;
}

{
    package Crash;
    # a package overloaded suspiciously like IO::Scalar
    use overload '""' => sub { ${$_[0]} };
    use overload 'bool' => sub { 1 };
    sub new {
	my ($class, $name) = @_;
	bless \$name, $class;
    }

    package Zowie;
    # a different package overloaded suspiciously like IO::Scalar
    use overload '""' => sub { ${$_[0]} };
    use overload 'bool' => sub { 1 };
    sub new {
	my ($class, $name) = @_;
	bless \$name, $class;
    }
}
{
    my $object = Crash->new('whack_eth');
    my %what = (plain => "$object",
		object1 => $object,
		object2 => Zowie->new('whack_eth'),
		object2 => Zowie->new('whack_eth'),
	       );

    my @warnings;
    local $SIG{__WARN__} = sub {
	push @warnings, @_;
    };

    foreach my $left (qw(plain object1 object2)) {
	foreach my $right (qw(plain object1 object2)) {
	    @warnings = ();
	    $! = 0;
	    is eval {copy $what{$left}, $what{$right}}, 1, "copy $left $right";
	    is $@, '', 'No croaking';
	    is $!, '', 'No system call errors';
	    is @warnings, 1, 'Exactly 1 warning';
	    like $warnings[0],
		qr/'$object' and '$object' are identical \(not copied\)/,
		    'with the text we expect';
	}
    }
}

# On Unix systems, File::Copy always returns 0 to signal failure,
# even when in list context!  On Windows, it always returns "" to signal
# failure.
#
# While returning a list containing a false value is arguably a bad
# API design, at the very least we can make sure it always returns
# the same false value.

my $NO_SUCH_FILE       = "this_file_had_better_not_exist";
my $NO_SUCH_OTHER_FILE = "my_goodness_im_sick_of_airports";

use constant EXPECTED_SCALAR => 0;
use constant EXPECTED_LIST   => [ EXPECTED_SCALAR ];

my %subs = (
    copy    =>  \&File::Copy::copy,
    cp      =>  \&File::Copy::cp,
    move    =>  \&File::Copy::move,
    mv      =>  \&File::Copy::mv,
);

SKIP: {
    skip( "Test can't run with $NO_SUCH_FILE existing", 2 * keys %subs)
        if (-e $NO_SUCH_FILE);

    foreach my $name (keys %subs) {

        my $sub = $subs{$name};

        my $scalar = $sub->( $NO_SUCH_FILE, $NO_SUCH_OTHER_FILE );
        is( $scalar, EXPECTED_SCALAR, "$name in scalar context");

        my @array  = $sub->( $NO_SUCH_FILE, $NO_SUCH_OTHER_FILE );
        is_deeply( \@array, EXPECTED_LIST, "$name in list context");
    }
}

END {
    1 while unlink "file-$$";
    1 while unlink "lib/file-$$";
}
