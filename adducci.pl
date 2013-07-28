#!/usr/bin/env perl
#
# Copyright 2013 by the Regents of the University of Minnesota
# Written by Munir Nassar <nassarmu@msi.umn.edu>
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
# The Minnesota Supercomputing Institute http://www.msi.umn.edu sponsored
# the development of this software.
#
# Requirements - perl - tested on perl-5.10.1-17squeeze3 and perl-5.10.1-127.el6.x86_64
#								perl LWP
#								smartctl
#								dmidecode
#
# adducci: a utility to collect certain HDD SMART information and basic system inventory
#
#

use strict;
use warnings;
use Sys::Hostname;
use LWP::Simple;
use URI::Escape;
use Getopt::Long;
use Pod::Usage;

# other system vars
my (
    $defaultnic,      $smartctl,    $ip,                 $sharedsecret,
    $remotecgi,       $dmidecode,   %hash,               $mac,
    $physical_id,     $core_id,     $cpu_name,           $cpu_vendor,
    $systemmake,      $systemmodel, $systemserialnumber, $biosversion,
    $biosreleasedate, $biosvendor,  $installedmem,       $cpuspeed,
    $help,            $silent,      @drives,             $report
);
my $count      = {};
my $config     = {};
my $has_ht     = 0;
my $host       = hostname;
my $datestamp  = time;
my $version    = "1.0.2";
my @alldrives  = </dev/[sh]d?>;
my $configfile = '/etc/adducci/adducci.conf';

# Get options from the wonderful perl module Getopt::Long
my $result = GetOptions(
    "configfile=s"   => \$configfile,
    "defaultnic=s"   => \$defaultnic,
    "smartctl=s"     => \$smartctl,
    "ip=s"           => \$ip,
    "dmidecode=s"    => \$dmidecode,
    "sharedsecret=s" => \$sharedsecret,
    "remotecgi=s"    => \$remotecgi,
    "drives=s"       => \@alldrives,
    "report!"        => \$report,
    "silent!"        => \$silent,
    "help|h|?"       => \$help
);

# Conjur up the helpscreen if help is requested
if ($help) { pod2usage( -verbose => 1 ) && exit; }

# check for root privs
if ( !$> == 0 ) {
    die "Must be run as root\n";
}

unless ( -r $configfile ) {
    print "configfile $configfile could not be read.\n";
    print "please specify another.\n";
    pod2usage( -verbose => 1 ) && exit;
}

use Config::Simple;
Config::Simple->import_from( "$configfile", $config );

$defaultnic = $config->{"ClientSettings.defaultnic"} or $defaultnic = "eth0";
$ip = $config->{"ClientSettings.ip"} or $ip = "/sbin/ip";
$smartctl = $config->{"ClientSettings.smartctl"}
  or $smartctl = "/usr/sbin/smartctl";
$dmidecode = $config->{"ClientSettings.dmidecode"}
  or $dmidecode = "/usr/sbin/dmidecode";
$sharedsecret = $config->{"ConfigSettings.sharedsecret"}
  or $sharedsecret = "none";
$remotecgi = $config->{"ClientSettings.remotecgi"} or $remotecgi = "none";

# test to make sure all needed utilities are found
if ( !-e $smartctl ) {
    unless ($silent) {
        warn "smartctl utility not found at $smartctl\n";
    }
}
if ( !-e $ip ) {
    unless ($silent) {
        die "ip utility not found at $ip\n";
    }
}
if ( !-e $dmidecode ) {
    unless ($silent) {
        die "dmidecode utility not found at $dmidecode\n";
    }
}

# collect data from dmidecode,
chomp( $systemmake = `$dmidecode --string system-manufacturer` )
  or $systemmake = "N/A";
chomp( $systemmodel = `$dmidecode --string system-product-name` )
  or $systemmake = "N/A";
chomp( $systemserialnumber = `$dmidecode --string system-serial-number` )
  or $systemmake = "N/A";
chomp( $biosversion = `$dmidecode --string bios-version` )
  or $biosversion = "N/A";
chomp( $biosreleasedate = `$dmidecode --string bios-release-date` )
  or $biosreleasedate = "N/A";
chomp( $biosvendor = `$dmidecode --string bios-vendor` ) or $biosvendor = "N/A";
chomp( $cpuspeed = `$dmidecode --string processor-frequency` )
  or $cpuspeed = "N/A";

# ugh, cpuspeed is in a wierd format.
if ($cpuspeed) {
    $cpuspeed =~ m/(\d+)/;
    $cpuspeed = $1;
}
else {
    $cpuspeed = "N/A";
}

# meminfo contains total RAM installed among other information
open( MEMINFO, "<", "/proc/meminfo" ) or die "Could not open /proc/meminfo\n";
while (<MEMINFO>) {
    if (/^MemTotal:\s+(.*)\s+kB/) {
        $installedmem = $1 * 1024;
    }
}
close(MEMINFO);
unless ($installedmem) {
    $installedmem = "N/A";
}

# cpuinfo contains cpu information
open( CPUINFO, "<", "/proc/cpuinfo" );
while (<CPUINFO>) {
    if (/^model name\s+:\s+(.*)/) {
        $cpu_name = $1;
    }
    elsif (/^vendor_id\s+:\s+(.*)/) {
        $cpu_vendor = $1;
    }
    elsif (/^physical id\s+:\s+(\d+)/) {
        $physical_id = $1;
    }
    elsif (/^core id\s+:\s+(\d+)/) {
        $core_id = $1;
    }
    elsif ( /^\s*$/ && $physical_id && $core_id ) {
        if ( ++$count->{$physical_id}->{$core_id} > 1 ) {
            $has_ht = 1;
            next;
        }
        undef $physical_id;
        undef $core_id;
    }
}
close(CPUINFO);

# reread cpu info for more information # FIXME no need to have this twice.
open( CPUINFO, "<", "/proc/cpuinfo" );
my @cpuinfo     = <CPUINFO>;
my $processors  = grep /processor/, @cpuinfo;
my @physicalids = grep /physical id/, @cpuinfo;
my %uniqueids   = map { $_, 1 } @physicalids;
my $sockets     = keys %uniqueids;

# if there is only one processor socket there may not be a physical id
if ( $sockets == 0 ) {
    $sockets = 1;
}
chomp( $sockets, $processors );
close(CPUINFO);

# pull network information
open( IP, "$ip -o link show |" );
while (<IP>) {
    my ( $macaddress, $nic );
    ($macaddress) = /link\/ether (.*) brd/;
    ($nic)        = /: (.*): /;
    if ($macaddress) {
        $hash{"MACAddress"}->{"$nic"} = "$macaddress";
    }
    else {
        $hash{"MACAddress"}->{"$nic"} = "N/A";
    }
}
if ( $hash{"MACAddress"}->{"$defaultnic"} ) {
    $mac = $hash{"MACAddress"}->{"$defaultnic"};
}
else {
    die
"$defaultnic is not available on this system, select another with $0 --defaultnic <nic>\n";
}

# by default it is attempted to detect drives
# all detected drives are tested with smartctl -q silent to determine if smartctl can get any data whatsoever
if ( -e $smartctl ) {
    unless (@alldrives) {
        unless ($silent) {
            warn "no SATA or PATA drives detected\n";
        }
    }
    else {
        foreach (@alldrives) {
            system("$smartctl -q silent $_");
            if ( $? == "0" ) {
                push( @drives, $_ );
            }
            else {
                unless ($silent) {
                    warn "$_ not a usable drive\n";
                }
            }
        }
        unless (@drives) {
            unless ($silent) {
                warn "no usable drives found\n";
            }
        }

        # presumably we have at least one drive by now
        # for each drive, we collect
        # drive information smartctl -i
        # drive health smartctl -H
        # drive smart attributes smartctl -A
        # smartctl does not provide easily parseable output
        # and some numbers need to be fixed
        foreach my $drive (@drives) {

# using the macaddress of $defaultnic as a joint key between the drives and the system inventory
            $hash{"$drive"}->{"mac"} = $mac;
            open( DRIVEINFO, "$smartctl -i $drive |" );
            while (<DRIVEINFO>) {
                chomp;
                if ( $_ =~ "Device does not support SMART" ) {
                    unless ($silent) {
                        warn "$drive: $_\n";
                    }
                }
                my @line = split( /\:/, $_ );
                if ( $line[0] && $line[1] ) {
                    $line[1] =~ s/^\s+//;
                    if ( $line[0] =~ "Device Model" ) {
                        $hash{"$drive"}->{"DeviceModel"} = $line[1];
                    }
                    if ( $line[0] =~ "Model Family" ) {
                        $hash{"$drive"}->{"ModelFamily"} = $line[1];
                    }
                    if ( $line[0] =~ "Serial Number" ) {
                        $hash{"$drive"}->{"SerialNumber"} = $line[1];
                    }
                    if ( $line[0] =~ "SMART support is" ) {
                        if ( $line[1] =~ "Enabled" ) {
                            $hash{"$drive"}->{"SMARTSupport"} = $line[1];
                        }
                    }
                    if ( $line[0] =~ "User Capacity" ) {
                        my @capacity = split( /\s+/, $line[1] );
                        $capacity[0] =~ s/\,//g;
                        $capacity[0] = $capacity[0];
                        $hash{"$drive"}->{"Capacity"} = $capacity[0];
                    }
                }
            }
            close(DRIVEINFO);

           # the only thing we need from drivehealth is the current smart status
            open( DRIVEHEALTH, "$smartctl -H $drive |" );
            while (<DRIVEHEALTH>) {
                chomp;
                my @line = split( /\:/, $_ );
                if ( $line[0] && $line[1] ) {
                    if ( $line[1] =~ "PASSED" ) {
                        $hash{"$drive"}->{"SMARTStatus"} = "PASSED";
                    }
                }
            }
            close(DRIVEHEALTH);

            # pull some important SMART values
            open( DRIVEVALUES, "$smartctl -A $drive |" );
            while (<DRIVEVALUES>) {
                chomp;

            # smart has a nasty habit of alligning the data by prepending spaces
                $_ =~ s/^\s+//;
                my @line = split( /\s+/, $_ );

 # these four values have been determined to be most indicative of drive failure
 # all should be 0, some greater values are to be expected as a drive ages
 # but if values rise quickly then the drive if failing.
                if ( $line[1] ) {
                    if ( $line[1] =~ "Reallocated_Sector_Ct" ) {
                        $hash{"$drive"}->{"ReallocatedSectorCount"} =
                          int( $line[9] );
                    }
                    if ( $line[1] =~ "Reallocated_Event_Count" ) {
                        $hash{"$drive"}->{"ReallocatedEventCount"} =
                          int( $line[9] );
                    }
                    if ( $line[1] =~ "Current_Pending_Sector" ) {
                        $hash{"$drive"}->{"CurrentPendingSector"} =
                          int( $line[9] );
                    }
                    if ( $line[1] =~ "Offline_Uncorrectable" ) {
                        $hash{"$drive"}->{"OfflineUncorrectable"} =
                          int( $line[9] );
                    }
                }
            }
            close(DRIVEVALUES);
        }
    }
}

# put all the inventory information collected so far into the hash
if ($has_ht) {
    $hash{"inventory"}->{"CPUHyperThreading"} = "true";
}
else {
    $hash{"inventory"}->{"CPUHyperThreading"} = "false";
}
$hash{"inventory"}->{"ram"}                = $installedmem;
$hash{"inventory"}->{"CPUType"}            = $cpu_name;
$hash{"inventory"}->{"CPUVendor"}          = $cpu_vendor;
$hash{"inventory"}->{"CPUSockets"}         = $sockets;
$hash{"inventory"}->{"CPUProcessors"}      = $processors;
$hash{"inventory"}->{"hostname"}           = $host;
$hash{"inventory"}->{"mac"}                = $mac;
$hash{"inventory"}->{"systemmake"}         = $systemmake;
$hash{"inventory"}->{"systemmodel"}        = $systemmodel;
$hash{"inventory"}->{"systemserialnumber"} = $systemserialnumber;
$hash{"inventory"}->{"CPUClockSpeed"}      = $cpuspeed;

# finally for each hash we are going to call the $remotecgi
# we need to build up a getstring with all the information
foreach my $system ( keys %hash ) {
    my $getstring;
    my $postfix = "";
    $getstring = "?system=$system&Datestamp=$datestamp&secret=$sharedsecret&";
    for my $value ( keys %{ $hash{$system} } ) {
        $postfix =
          "$postfix" . "$value=" . uri_escape( $hash{$system}{$value} ) . "&";
    }

    # FIXME is there a better way to do this?
    chop($postfix);
    $getstring = "$getstring" . "$postfix";

    # finally call remotecgi
    my $content = get( "$remotecgi" . "$getstring" );

}

# now report everything to screen if requested
if ($report) {

    foreach ( keys %hash ) {
        if ( $_ =~ '/dev/[sh]d?' ) {
            my $smartfailed;

            if ( $hash{"$_"}->{"SMARTSupport"} eq "Enabled" ) {
                if ( !$hash{"$_"}->{"SMARTStatus"} eq "PASSED" ) {
                    $smartfailed = 1;
                }

            }

            if ($smartfailed) {
                print "$_: SMART Failed\n";
            }
            else {
                my $count = "0";

                if ( $hash{"$_"}->{"OfflineUncorrectable"} ) {
                    $count += $hash{"$_"}->{"OfflineUncorrectable"};
                }
                if ( $hash{"$_"}->{"CurrentPendingSector"} ) {
                    $count += $hash{"$_"}->{"CurrentPendingSector"};
                }
                if ( $hash{"$_"}->{"ReallocatedEventCount"} ) {
                    $count += $hash{"$_"}->{"ReallocatedEventCount"};
                }
                if ( $hash{"$_"}->{"ReallocatedSectorCount"} ) {
                    $count += $hash{"$_"}->{"ReallocatedSectorCount"};
                }

                if ( $count > 0 ) {
                    print "$_ may be failing, please replace drive\n";
                }
            }

        }
    }

}

=head1 NAME

	adducci

=head1 SYNOPSIS

	adducci [OPTIONS]

=head1 DESCRIPTION

	Collect system hardware inventory and critical S.M.A.R.T. values

=head1 OPTIONS

  --defaultnic <nic>
		Use the specifieds nic MAC Address rather than eth0's MAC Address as a key.

	--smartctl <path to smartctl>
		specify the path to the smartctl binary, smartctl is not mandatory

	--ip <path to ip>
		specify the path to the ip binary, used to get gather nic information

	--dmidecode <path to dmidecode>
		specify the path to the dmidecode binary which collects system information

	--sharedsecret <string>
		simple check to ensure that the client and database are in sync
		this should not be used to secure the database!

	--remotecgi <url>
		full url indicating which server to use

	--drives 
		which drives to use instead of relying on the autodetection of scsi, sas, sata and ide(pata) hard drives

	--silent
		attempt to silence non-fatal errors

	--help|h|?
		this screen
