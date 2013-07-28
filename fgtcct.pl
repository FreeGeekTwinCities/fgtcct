#!/usr/bin/env perl

# Copyright 2013 by Munir Nassar <nassarmu@gmail.com>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# strict and warnings should be perl defaults IMHO
use strict;
use warnings;

# perl modules we will be using
use Getopt::Long;
use Sys::Syslog;
use feature 'switch';

# config options:
my $name          = "Free Geek Twin Cities Customization Tool";
my $version       = "0.1.0";
my $remote        = "http://build.office.freegeektwincities.org";
my $setupstepfile = ".fgtcsetup";
my $loops         = "10";
my @cmdargs       = @ARGV;
my $extrapackages =
"libreoffice wkhtmltopdf deborphan vim less vlc libdvdread4 libwww-perl dmidecode libconfig-simple-perl libwww-perl smartmontools flashplugin-nonfree";
my $drivers       = "firmware-b43-installer";
my $removepackages     = "gnumeric abiword";
my $geekbenchbydefault = "1";

# Start sysloging
openlog( $0, "ndelay", "LOG_LOCAL4" );

# initialize other variables
my ( $help, $debug, $dryrun, $zerocool, $step, $geekbenchurl, $illegal,
    $geekbench );
my $geekbenchoutput  = "/tmp/geekbench-output";
my $geekbenchweb     = "/tmp/geekbench-web.html";
my $installcssscript = "/usr/share/doc/libdvdread4/install-css.sh";

# get commandline options:
my $result = GetOptions(
    "remote|r=s" => \$remote,
    "debug!"     => \$debug,
    "dryrun!"    => \$dryrun,
    "zerocool!"  => \$zerocool,
    "stepfile=s" => \$setupstepfile,
    "loops=i"    => \$loops,
    "illegal!"   => \$illegal,
    "geekbench!" => \$geekbench,
    "help|?|h"   => \$help
);

# Conjur up the helpscreen if help is requested
if ($help) {
	print "\tNAME\n";
	print "\t\tfgtcct - The Free Geek Twin Cities Customization Tool\n";
	print "\n";
	print "\tSYNOPSIS\n";
	print "\t\tfgtcct [OPTION]\n";
	print "\n";
	print "\tOPTIONS\n";
	print "\t\t--remote|-r <URL> (default: $remote)\n";
	print "\t\t\tremote server that houses extra files used\n";
	print "\n";
	print "\t\t--stepfile <file> (default: .fgtcsetup)\n";
	print "\t\t\tspecify a file to use to store which steps we are on\n";
	print "\n";
	print "\t\t--loops <int> (default: 10)\n";
	print "\t\t\tspecify the number of iterations for the cleanup loop\n";
	print "\n";
	print "\t\t--geekbench (default)\n";
	print "\t\t\tSpecify if the geekbench tests should be run\n";
	print "\n";
	print "\t\t--dryrun\n";
	print "\t\t\tDry run, do not actually do anything\n";
	print "\n";
	print "\t\t--debug\n";
	print "\t\t\tdebugging mode, very verbose\n";
	exit 0
}

if ($geekbenchbydefault) {
    if ($debug) {
        print "debug: enable geekbench by default config\n";
    }
    $geekbench = "1";
}

if ($geekbench) {
    if ($debug) {
        print "debug: geekbench enabled\n";
    }
}
else {
    if ($debug) {
        print "debug: geekbench disabled\n";
    }
}

# make sure we have superuser privs
unless ( $> == 0 ) {
    print "rerunning with sudo: sudo $0 @cmdargs\n";
    syslog( 'info', "Running with sudo" );
    system("sudo $0 @cmdargs");
    exit 0;
}
else {
    if ($debug) {
        print "debug: superuser privs detected.\n";
    }
    syslog( 'info', "superuser privs detected." );
}

# print out remote server notification
if ($debug) {
    print "Using $remote for the remote host\n";
}
syslog( 'info', "using $remote for the remote host" );

if ($debug) {
    print "Using $loops deborphan loops\n";
}
syslog( 'info', "using $loops deborphan loops" );

# process the setup step file
# if one exists read the step we are currently on
# otherwise set step to 1
if ( -e $setupstepfile ) {
    syslog( 'info', "$setupstepfile detected, reading" );
    if ($debug) {
        print "$setupstepfile detected, reading\n";
    }
    open( STEP, "< $setupstepfile" ) or die "Could not read $setupstepfile\n";
    while (<STEP>) {
        chomp;
        $step = $_;
    }
    close(STEP);
}
else {
    syslog( 'info', "no $setupstepfile, starting at step 1" );
    $step = 1;
}

# run the command requested
# $params[0]: intro string
# $params[1]: command to be run
# $params[2]: dryrun command
sub command {
    my @params = @_;

    if ($debug) {
        print "debug: parameters passed to command: @params\n";
    }

    unless ($zerocool) {
        print "$params[0]\n";
        print "\t$params[1]\n";
        print "Press ENTER to continue\n";
        <>;
    }
    else {
        if ($debug) {
            print "debug: in zerocool mode, $params[1] without asking\n";
        }
    }
    if ($dryrun) {
        if ($debug) {
            print "debug: running $params[2]\n";
        }
        system("$params[2]");
    }
    else {
        if ($debug) {
            print "debug: running $params[1]\n";
        }
        system("$params[1]");
    }
}

# here we process the different steps
given ($step) {
    when ( "$step" eq "1" ) {
        print "$name - Step $step\n";

        # update the apt database
        &command(
            "Update the apt database",
            "apt-get -y update",
            "apt-get -y --dry-run update"
        );

        # remove the unwanted packages
        &command(
            "Remove unwanted packages",
            "apt-get -y remove --purge $removepackages",
            "apt-get -y --dry-run remove --purge $removepackages"
        );

        # install the extra packages
        &command(
            "Install extra packages",
            "apt-get -y install $extrapackages",
            "apt-get -y --dry-run install $extrapackages"
        );

        # now perform a full system update
        &command(
            "Perform a full system update",
            "apt-get -y dist-upgrade",
            "apt-get -y --dry-run dist-upgrade"
        );

        # Step 1 complete
        print "Step $step complete\n";
        if ($dryrun) {
            print "dryrun: not touching $setupstepfile\n";
        }
        else {
            if ($debug) {
                print "debug: creating $setupstepfile\n";
            }
            open( STEP, "> $setupstepfile" )
              or die "Could not write $setupstepfile\n";
            if ($debug) {
                print "debug: writing 2 to $setupstepfile\n";
            }
            print STEP "2";
            close(STEP);
        }
        print "Press ENTER to REBOOT\n";
        <>;
        if ($dryrun) {
            print "dryrun: would have rebooted otherwise\n";
        }
        else {
            if ($debug) {
                print "debug: running /sbin/reboot\n";
            }
            system("/sbin/reboot");
        }
    }
    when ( "$step" eq "2" ) {
        print "$name - Step $step\n";
        my $runningkernel = `uname -r`;
        chomp $runningkernel;
        if ($debug) {
            print "debug: kernel: $runningkernel\n";
        }

        # remove all but the running kernel
        &command(
            "Remove unused kernels",
"apt-get -y remove --purge \$(dpkg -l | grep linux-image | grep -v $runningkernel | grep -v linux-image-generic | cut -d' ' -f 3)",
"apt-get -y --dry-run remove --purge \$(dpkg -l | grep linux-image | grep -v $runningkernel | grep -v linux-image-generic | cut -d' ' -f 3)"
        );  
        # install common drivers
        &command(
            "Install drivers",
            "apt-get -y install $drivers",
            "apt-get -y --dry-run install $drivers"
        );
        my $loop    = 0;
        my $orphans = `deborphan | wc -l`;
	chomp( $orphans );
        while ( !$orphans == 0 ) {
            if ($debug) {
                print "loop: $loop\n";
                print "orphans: $orphans\n";
            }
            &command(
                "Removing unneccesary libraries, loop $loop",
                "apt-get -y remove --purge \$(deborphan)",
                "apt-get -y remove --purge \$(deborphan)"
            );
            $orphans = `deborphan | wc -l`;
            chomp ( $orphans );
            if ($dryrun) {
                print
"dryrun: setting orphans to 0 as it would make no sense to continue looping\n";
                $orphans = 0;
            }
            else {
                $loop = $loop + 1;
            }
            if ( $loop > $loops ) {
                warn "exceeding maxloops of $loops\n";
            }
        }

        # remove autoinstalled packages
        &command(
            "Removing autoinstalled packages",
            "apt-get -y --purge autoremove",
            "apt-get -y --purge --dry-run autoremove"
        );

        # create a desktop directory in /etc/skel
        &command(
            "Create a Desktop directory",
            "mkdir /etc/skel/Desktop",
            "echo mkdir /etc/skel/Desktop"
        );

        # download freegeek customizations
        &command(
            "Download Free Geek Twin Cities XFce4 customizations",
            "wget --progress=dot:binary -O xfce4-settings.tar.gz $remote/xfce4-settings.tar.gz",
            "echo wget --progress=dot:binary -O xfce4-settings.tar.gz $remote/xfce4-settings.tar.gz"
        );

	if ( -e "xfce4-settings.tar.gz" ) {
		# unpack freegeek customizations
		&command(
		    "Unpack Free Geek Twin Cities Customizations",
		    "tar -xzf xfce4-settings.tar.gz -C /etc/skel",
		    "echo tar -xzf xfce4-settings.tar.gz -C /etc/skel"
		);
 	}
	else {
		print "xfce4-settings.tar.gz not found.";
	}

        # download the PrimateLabs Geekbench utility
        &command(
            "Download the PrimateLabs Geekbench utility",
            "wget --progress=dot:binary -O geekbench.tar.gz $remote/geekbench.tar.gz",
            "echo wget --progress=dot:binary -O geekbench.tar.gz $remote/geekbench.tar.gz"
        );
	
	if ( -e "geekbench.tar.gz" ) {
		# unpack geekbench
		&command(
		    "Unpack the PrimateLabs Geekbench utility",
		    "tar -xzf geekbench.tar.gz",
		    "echo tar -xzf geekbench.tar.gz"
		);

		# run the PrimateLabs Geekbench utility
		&command(
		    "Perform a Geekbench using the PrimateLabs utility. This will take several minutes!",
		    "geekbench/geekbench_x86_32 \> $geekbenchoutput",
		    "echo geekbench/geekbench_x86_32 \> $geekbenchoutput"
		);
	
		# parse the geekbench results to find the URL
		if ($dryrun) {
		    print "dryrun: cat $geekbenchoutput | grep key\= | grep http\n";
		    print "dryrun: setting remote to $remote/DRYRUN.html\n";
		    $geekbenchurl = "$remote/DRYRUN.html";
		}
		else {
		    $geekbenchurl = `cat $geekbenchoutput | grep key\= | grep http`;
		}
		if ($debug) {
		    print "debug: geekbenchurl=$geekbenchurl\n";
		}
		# fetch the geekbench
		&command(
		    "Fetch the Geekbench results",
		    "wget -O $geekbenchweb $geekbenchurl",
		    "echo wget -O $geekbenchweb $geekbenchurl"
		);

		# Convert the html to a pdf document
		&command(
		    "Convert $geekbenchweb to a PDF document",
		    "wkhtmltopdf $geekbenchweb Desktop/geekbench.pdf",
		    "echo wkhtmltopdf $geekbenchweb Desktop/geekbench.pdf"
		);

		# copy the result to the skel directory
		&command(
		    "Copy the results to the skeleton directory",
		    "cp Desktop/geekbench.pdf /etc/skel/Desktop",
		    "echo cp Desktop/geekbench.pdf /etc/skel/Desktop"
		);
	} else {
		print "geekbench.tar.gz not found.";
	}

        # fetch adducci to collect system and S.M.A.R.T. information.
        &command(
"Fetch adducci, a utility to collect System and Hard Drive S.M.A.R.T. Information",
            "wget --progress=dot:binary -O adducci.tar.gz $remote/adducci.tar.gz",
            "echo wget --progress=dot:binary -O adducci.tar.gz $remote/adducci.tar.gz"
        );

	if ( -e "adducci.tar.gz" ) {
		# unpack adducci
		&command(
		    "Unpack the adducci utility",
		    "tar -xzf adducci.tar.gz",
		    "echo tar -xvf adducci.tar.gz"
		);

		# run adducci to collect system and S.M.A.R.T. information
		&command(
		    "Run adducci to collect system and S.M.A.R.T. information",
		    "./adducci.pl --config adducci.conf --report",
		    "echo ./adducci.pl --config adducci.conf --report"
		);
	} else {
		print "adducci.tar.gz not found.";
	}


        # we are done
        open( STEP, "> $setupstepfile" )
          or die "Could not write $setupstepfile\n";
        print STEP "3";
        close(STEP);

        # Perform a potentially illegal act
        if ($illegal) {
            &command( "Installing software that may be illegal!",
                $installcssscript, "echo $installcssscript" );
        }

        # print out goodbye message
        print "Free Geek Twin Cities Customization Tool is now complete\n";
        print "Please contact a staff member to inspect the system\n";
    }
    when ( "$step" eq "3" ) {
        print "STEP $step\n";
        if ($illegal) {
            &command( "Installing software that may be illegal!",
                $installcssscript, "echo $installcssscript" );
            print "$name changes have already been applied to this system\n";
            print "Please contact a staff member to inspect the system\n";
        }
    }
    default {
        die "unknown step: $step\n";
    }
}
