#!/usr/bin/env perl
# Copyright 2012, Tim Henigan <tim.henigan@gmail.com>
#
# Perform a directory diff between commits in the repository using
# the external diff or merge tool specified in the user's config.

use 5.008;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Copy;
use File::stat;
use File::Path qw(mkpath);
use File::Temp qw(tempdir);
use Getopt::Long qw(:config pass_through);
use Git;

my @working_tree;

sub usage {
	my $exit_code = shift or die;

	print STDERR <<USAGE;
git diffall [-x|--extcmd=<command>] <commit>{0,2} [--] [<path>...]

    -x=<command>
    --extcmd=<command>  Specify a custom command for viewing diffs.
                 git-diffall ignores the configured defaults and
                 runs \$command \$LOCAL \$REMOTE when this option is
                 specified.

    All other command-line options and arguments will be passed
    through to the underlying diff command (git diff --raw).
USAGE
	exit($exit_code);
}

sub setup_dir_diff
{
	# Run the diff; exit immediately if no diff found
	my $repo = Git->repository();
	my $diffrtn = $repo->command_oneline(['diff', '--raw', '--no-abbrev', '-z', @ARGV]);
	exit(0) if (length($diffrtn) == 0);

	# Setup temp directories
	my $tmpdir = tempdir('git-diffall.XXXXX', CLEANUP => 1, TMPDIR => 1);
	my $ldir = "$tmpdir/left";
	my $rdir = "$tmpdir/right";
	mkpath($ldir) or die $!;
	mkpath($rdir) or die $!;

	# Build index info for left and right sides of the diff
	my $submodule_mode = "160000";
	my $null_mode = 0 x 6;
	my $null_sha1 = 0 x 40;
	my $lindex = "";
	my $rindex = "";
	my %submodule;
	my @rawdiff = split('\0', $diffrtn);

	for (my $i=0; $i<@rawdiff; $i+=2) {
		my ($lmode, $rmode, $lsha1, $rsha1, $status) = split(' ', substr($rawdiff[$i], 1));
		my $path = $rawdiff[$i + 1];

		if (($lmode eq $submodule_mode) or ($rmode eq $submodule_mode)) {
			$submodule{$path}{left} = $lsha1;
			$submodule{$path}{right} = $rsha1;
			next;
		}

		if ($lmode ne $null_mode) {
			$lindex .= "$lmode $lsha1\t$path\0";
		}

		if ($rmode ne $null_mode) {
			if ($rsha1 ne $null_sha1) {
				$rindex .= "$rmode $rsha1\t$path\0";
			} else {
				push(@working_tree, $path);
			}
		}
	}

	# Populate the left and right directories based on each index file
	my ($inpipe, $ctx);
	$ENV{GIT_DIR} = $repo->repo_path();
	$ENV{GIT_INDEX_FILE} = "$tmpdir/lindex";
	($inpipe, $ctx) = $repo->command_input_pipe(qw/update-index -z --index-info/);
	print($inpipe $lindex);
	$repo->command_close_pipe($inpipe, $ctx);
	system(('git', 'checkout-index', '--all', "--prefix=$ldir/"));

	$ENV{GIT_INDEX_FILE} = "$tmpdir/rindex";
	($inpipe, $ctx) = $repo->command_input_pipe(qw/update-index -z --index-info/);
	print($inpipe $rindex);
	$repo->command_close_pipe($inpipe, $ctx);
	system(('git', 'checkout-index', '--all', "--prefix=$rdir/"));

	# Changes in the working tree need special treatment since they are
	# not part of the index
	my $workdir = $repo->repo_path() . "/..";
	for (@working_tree) {
		my $dir = dirname($_);
		unless (-d "$rdir/$dir") {
			mkpath("$rdir/$dir") or die $!;
		}
		copy("$workdir/$_", "$rdir/$_") or die $!;
		chmod(stat("$workdir/$_")->mode, "$rdir/$_") or die $!;
	}

	# Changes to submodules require special treatment. This loop writes a
	# temporary file to both the left and right directories to show the
	# change in the recorded SHA1 for the submodule.
	foreach my $path (keys %submodule) {
		if (defined $submodule{$path}{left}) {
			open(my $fh, ">", "$ldir/$path") or die $!;
			print($fh "Subproject commit $submodule{$path}{left}");
			close($fh);
		}
		if (defined $submodule{$path}{right}) {
			open(my $fh, ">", "$rdir/$path") or die $!;
			print($fh "Subproject commit $submodule{$path}{right}");
			close($fh);
		}
	}

	return ($ldir, $rdir);
}

# parse command-line options. all unrecognized options and arguments
my ($extcmd, $help);
GetOptions('h|help' => \$help, 'x|extcmd:s' => \$extcmd);

usage(0) if ($help);

# Verify that an external tool has been configured
if (defined($extcmd)) {
	if (length($extcmd) == 0) {
		print("No <cmd> given for '--extcmd'\n");
		usage(1);
	}
} else {
	my $difftool = Git::config('diff.tool');
	my $mergetool = Git::config('merge.tool');
	unless (defined($difftool) or defined($mergetool)) {
		print("If '--extcmd' is not used, then either 'diff.tool' or 'merge.tool' must be set!\n");
		usage(1);
	}
}

# Setup the tmp directories with the files to be compared and then
# call the diff tool.
my ($a, $b) = setup_dir_diff();

if (defined($extcmd)) {
	system(($extcmd, $a, $b));
} else {
	git_cmd_try {
		Git::command_noisy(('diffall--helper', $a, $b))
	} 'exit code %d';
}

# If the diff including working copy files and those
# files were modified during the diff, then the changes
# should be copied back to the working tree
my $repo = Git->repository();
my $workdir = $repo->repo_path() . "/..";
for (@working_tree) {
	copy("$b/$_", "$workdir/$_") or die $!;
	chmod(stat("$b/$_")->mode, "$workdir/$_") or die $!;
}
