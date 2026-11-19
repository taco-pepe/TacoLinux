# set MKS Korn shell environment variables for MS Visual Studio
# 2015/2019/2022 Community

# Revision history
#            2023-09-08: changed to work with Visual Studio 2022:
#                        replaced here document with temorary file;
#                        improved error messages
#            2022-09-04: changed "egrep" to "grep -E"
#            2021-09-26: revised to use Visual Studio 2019
#            2020-05-08: revised to prevent MKS Toolkit from prepending
#                        UTF-8 signature
#            2016-05-28: initial version
#
# Copyright (C) 2016, 2020, 2022, 2023 Free Software Foundation, Inc

# Microsoft Visual Studio requires that several environment variables
# include many directories if a build is to be done from the command
# line.  These variables are normally set by selecting 'Developer
# Command Prompt' or one of the more specific options on the Windows
# Start Menu under the appropriate Visual Studio version; the shortcut
# runs a batch file that calls several other batch files to set the
# variables before launching an instance of the Windows command
# interpreter.  This program calls the Windows command interpreter to
# run the batch file; the resulting values of the variables are echoed
# and read into the shell to set the variables in the shell.  For the
# values to persist, this program must be run in the current
# environment, i.e.,
#
#   source setvcvars
#
#       or
#
#   . setvcvars
#
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or (at
# your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY--without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-
# 1301 USA
#
# 
# This program was written by Jeff Conrad (jeff_conrad@msn.com), and
# tested with the MKS Toolkit version 10.4 and Microsoft Visual Studio
# 2015, 2019, and 2022 on Windows 10 Professional.

tempdir="$TEMP"
tempfile="$tempdir\setvctemp$$.bat"
progname=setvcvars

# this will match progname if not invoked with source
thisprog=${0##*[/\\]}
thisprog=${thisprog%.sh}

if [[ $thisprog == $progname ]]
then
    print -r "Environment not initialized; run as 'source $thisprog'"
    exit 1
fi

setvcerrors=

umsg="Usage: source $progname [options] [platform]
Options:
  -V<vsversion>  Use Visual Studio <vsversion> (default: 2022)"

# default version; change to suit
vsversion=2022
vcverbose=

DUALCASE=1	# MKS Toolkit option to distinguish upper and lower case
while getopts :V: arg
do
    case $arg in
    v)
	vcverbose=YES ;;	# not yet used
    V)
	vsversion=$OPTARG ;;
    :)
	# OPTARG contains the option missing the argument
	print -ru2 -- "$progname: option $OPTARG requires an argument"
	setvcerrors=YES
	;;
    [?])
	# OPTARG contains the invalid option
	print -ru2 -- "$progname: unknown option $OPTARG"
	setvcerrors=YES
	;;
    esac
done
shift OPTIND-1
unset DUALCASE

if [ -n "$setvcerrors" ]
then
    print -ru2 -- "$umsg"
fi

# These values assume the default installation directory for Visual
# Studio Community; after initialization, the first part of the PATH
# should match the VSINSTALLDIR environment variable.

if [[ -z "$setvcerrors" ]]
then
    case $vsversion in
    2022)
	vsinstalldir="C:\Program Files\Microsoft Visual Studio\2022\Community"
	vcbatdir="$vsinstalldir\VC\Auxiliary\Build"
	vscommontools=VS170COMNTOOLS
	;;
    2019)
	vsinstalldir="C:\Program Files (x86)\Microsoft Visual Studio\2019\Community"
	vcbatdir="$vsinstalldir\VC\Auxiliary\Build"
	vscommontools=VS160COMNTOOLS
	;;
    2015)
	vsinstalldir="C:\Program Files (x86)\Microsoft Visual Studio 14.0"
	vcbatdir="$vsinstalldir\VC"
	vscommontools=VS140COMNTOOLS
	;;
    *)
	print -ru2 "$progname: unsupported Visual Studio version: '$vsversion'; choices are 2022/2019/2015"
	setvcerrors=YES
	;;
    esac
fi

# variables needed for Visual Studio; 'PATH' will match 'LIBPATH'
envvars="PATH=|INCLUDE=|LIB=|$vscommontools="

# batch file: this value is installation and version dependent--adjust
# as needed. It should be the shortcut on the Start Menu for 
# 'x64 Native Tools Command Prompt' or 'x64_x86 Cross Tools Command Prompt'
# for Visual Studio 2019 and 2022 or for 'x64 Native Tools Command Prompt'
# or 'x64 x86 Cross Tools Command Prompt' for Visual Studio 2015

# This assumes the compilation will be run on a 64-bit host; use the
# commented-out values for 'vcarch' to run it on a 32-bit host

if [[ -z "$setvcerrors" ]]
then
    if [[ $# -gt 0 ]]
    then
	vcarch=$1
    else
	vcarch=x64
    fi

    # valid target architectures; 64-bit host is assumed
    vcarches32='x86|x64_x86|amd64_x86|32|32bit|32-bit'
    vcarches64='x64|amd64|64|64bit|64-bit'
    
    case $vsversion in
    2019|2022)
	case $vcarch in
	x86|x64_x86|amd64_x86|32|32bit|32-bit)
	    vcbatfile="$vcbatdir\vcvars32.bat"
	    #vcarch=x86		# 32 bit target on 32 bit host
	    vcarch=x64_x86	# 32 bit target on 64 bit host
	    ;;
	x64|amd64|64|64bit|64-bit)
	    vcbatfile="$vcbatdir\vcvars64.bat"
	    #vcarch=x86_x64	# 64 bit target on 32 bit host
	    vcarch=x64		# 64 bit target on 64 bit host
	    ;;
	*)
	    print -ru2 "$progname: invalid architecture: '$vcarch'"
	    print -ru2 "$progname: 64-bit choices are $vcarches64"
	    print -ru2 "$progname: 32-bit choices are $vcarches32"
	    setvcerrors=YES
	    ;;
	esac
	;;
    2015)
	case $vcarch in
	x86|32|32bit|32-bit)
	    vcbatfile="$vcbatdir\vcvarsall.bat"
	    vcarch=amd64_x86
	    ;;
	x64|amd64|64|64bit|64-bit)
	    vcbatfile="$vcbatdir\vcvarsall.bat"
	    vcarch=amd64
	    ;;
	*)
	    print -ru2 "$progname: invalid architecture: '$vcarch'"
	    print -ru2 "$progname: 64-bit choices are $vcarches64"
	    print -ru2 "$progname: 32-bit choices are $vcarches32"
	    setvcerrors=YES
	    ;;
	esac
	;;
    esac

    if [[ -z "$setvcerrors" ]]
    then
	# don't set the variables twice, because new values are added to previous values
	if test "$VCVARSSET" != ""
	then
	    print -ru2 "$progname: Visual C $VSVERSION variables already set: $VCVARSSET bit"
	    setvcerrors=YES
	fi
	if test ! -e "$vcbatfile"
	then
	    print -ru2 "$progname: cannot find Command Prompt batch file '$vcbatfile'"
	    setvcerrors=YES
	fi
	if test -z "$ComSpec"
	then
	    print -ru2 "$progname: no path to command interpreter: ComSpec not set"
	    setvcerrors=YES
	fi
	if test ! -e "$ComSpec"
	then
	    print -ru2 "$progname: cannot find command interpreter '$ComSpec'"
	    setvcerrors=YES
	fi
	if test ! -x "$ComSpec"	# this should never happen ...
	then
	    print -ru2 "$progname: cannot run command interpreter '$ComSpec'"
	    setvcerrors=YES
	fi
	if test ! -d "$tempdir"	# this should never happen, either
	then
	    print -ru2 "$progname: cannot find TEMP dir'$tempdir'"
	    setvcerrors=YES
	fi
    fi
fi

if [ -z "$setvcerrors" ]
then
    # save this for comparison with (hopefully) modified version
    OPATH="$PATH"

    # create a batch file to initialize the environment using the Visual
    # Studio batch files and echo the results
    # As of Visual Studio 2022, this no longer works in a here document
    # with PTC MKS Toolkit 10.4

    print -r "prompt \$s
@call \"$vcbatfile\" $vcarch
@echo PATH=\"%PATH%\"; export PATH
@echo INCLUDE=\"%INCLUDE%\"; export INCLUDE
@echo LIB=\"%LIB%\"; export LIB
@echo LIBPATH=\"%LIBPATH%\"; export LIBPATH
@rem assume $vscommontools has trailing backslash
@echo $vscommontools=\"%$vscommontools%\\\"; export $vscommontools" > $tempfile

    # run the batch file and echo the results to read into the shell with
    # eval(1)
    eval "$($ComSpec /q /c $tempfile | grep -E $envvars)"
    rm -f $tempfile

    # variable initialization probably failed
    if test "$PATH" = "$OPATH"
    then
	echo "$progname: could not set Visual C variables"
    else	# prevent setting the variables more than once
	VSVERSION=$vsversion
	export VSVERSION
	case "$vcarch" in
	x64|amd64)
	    VCVARSSET=64 ;;
	*)
	    VCVARSSET=32 ;;
	esac
	export VCVARSSET

	# FIXME: show this only with vcverbose set?
	print -r "Environment initialized for Visual Studio $vsversion: '$vcarch'"
    fi
fi

# make getopts work in case a previous invocation used an invalid option
OPTIND=1

# because this is run in source mode, these will persist if not unset
unset progname umsg thisprog tempdir tempfile OPATH OPTARG
unset envvars setvcerrors vsversion vscommontools vcbatdir vcbatfile
unset vcarch vcarches32 vcarches64 vcverbose
