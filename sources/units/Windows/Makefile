# Makefile for Windows binary distribution of GNU units, a program for
# units conversion
#
# Copyright (C) 2014-2024
# Free Software Foundation, Inc
#
# Last updated 2024-11-21 Jeff Conrad <jeff_conrad@msn.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
#    
# This Makefile was written by Jeff Conrad (jeff_conrad@msn.com)
# and Adrian Mariano (adrianm@gnu.org) and
#
# The units program was written by Adrian Mariano
#
# Distributions through version 2.20 were compiled as 32 bit
# using MS Visual C and MS Visual Studio. # Versions since 2.21
# have been compiled as 64 bit using MS Visual Studio Community.
# The installer has been built using Inno Setup.
#
# need these files:
#  Instructions.txt -- instructions for building and uploading
#  units-xxx.iss -- installer build script template
#  Readme.txt  -- specific to Windows version
#  gnu.ico     -- for the installer to display
#  Makefile (this file) to build Windows distribution
#  lwords -- words to exclude from spelling check
#  ex.rc  -- adds special mapping for spellx and formatting paragraphs
#  UnitsForWindows.texinfo

# for PTC MKS Toolkit
.POSIX:

SHELL = /bin/sh
PROG = units
VERSION = 2.24
DISTNAME = $(PROG)-$(VERSION)
INSTALLER = $(DISTNAME)$(exename)
ZIPFILE = $(DISTNAME)$(zipname)
# for installer
exename = -setup.exe
# for zipped version of installer
zipname = -setup.zip

windir = .
# adjust this to suit
srcdir = ..

#
# specific to environment; change to suit
#
ProgFiles32 = "C:/Program Files (x86)"
ProgFiles64 = "C:/Program Files"
GPG  = $(ProgFiles32)/GnuPG/bin/gpg.exe
# Inno Setup
ISCC = $(ProgFiles32)/"Inno Setup 6"/ISCC.exe
# convert LF to CRLF: based on PTC MKS Toolkit
# assumes /bin is symlink to $ROOTDIR/mksnt
UNIX2DOS = C:/bin/flip.exe -bd
# program to remove UTF-8 marker added by MKS flip(1) and sed(1)
RMBOM = rmbom
# based on MikTeX for Windows
TEXI2PDF = $(ProgFiles64)/MiKTeX/miktex/bin/x64/texify.exe -pq
# WinZip command-line add-on; normally not needed
ZIP = $(ProgFiles64)/WinZip/WZZIP.exe

# for this Windows installer, these pathnames must include only the
# filenames
data_file = definitions.units
locale_map = locale_map.txt

INSTALLER_SCRIPT_TEMPLATE = $(windir)/$(PROG)-xxx.iss
INSTALLER_SCRIPT = $(windir)/$(PROG)-$(VERSION).iss

install_dir = $(ProgFiles64)/GNU/$(PROG)

.SUFFIXES:
.SUFFIXES: .texinfo .pdf

.texinfo.pdf:
	$(TEXI2PDF) $<

# revised for units 2.15 to reflect single version for Python 2 and Python 3
CUR_PROG = units_cur.py

# copy from source distribution
DISTFILES = $(PROG).exe $(CUR_PROG) \
            definitions.units elements.units currency.units cpi.units \
	    locale_map.txt units.pdf unitsfile.ico unitsprog.ico

# files needed for Windows builder
BUILDERFILES = Instructions.txt* Makefile.in* Readme.txt* RemoveFromPath.iss* \
               RemoveOldInstallation.iss* UnitsForWindows.texinfo* ex.rc* \
               gnu.ico* lwords* units-xxx.iss*

LICENSE = License.txt
WINTEXI = UnitsForWindows.texinfo
WINPDF = UnitsForWindows.pdf
WINFILES = Readme.txt gnu.ico

# Text files get converted from LF to CRLF if necessary
TEXTFILES = $(CUR_PROG) definitions.units elements.units currency.units cpi.units \
    locale_map.txt License.txt

FILES = $(PROG).exe $(TEXTFILES)

# targets

all: windist

windist: $(INSTALLER)

ins: $(INSTALLER)

$(INSTALLER): $(INSTALLER_SCRIPT_TEMPLATE) $(WINPDF) $(WINFILES) $(FILES)
	@if test -z $(VERSION); then \
	    echo "No version specified"; \
	    false; \
	fi
	@if ! test -d $(srcdir); then \
	    echo "Cannot find source directory '$(srcdir)'"; \
	    false; \
	fi
	# check versions of units source and executable to see if they match the specified VERSION
	# check pathnames of units data file and locale map to see if they include only the filenames
	@errors=0; \
	    echo "Checking version ..."; \
	    srcversion=`sed -n -e '/\#.*VERSION/{s/.*"\(.*\)"/\1/p;q;}' $(srcdir)/$(PROG).c`; \
	    if [ "$$srcversion" != "$(VERSION)" ]; then \
		echo "specified version ($(VERSION)) does not match source version ($$srcversion)"; \
		errors=`expr $$errors + 1`; \
	    fi; \
	    if [ ! -x $(srcdir)/$(PROG).exe ]; then \
		echo "$(srcdir)/$(PROG).exe not found; build it before creating this distribution"; \
		errors=`expr $$errors + 1`; \
	    fi; \
	    exeversion=`$(srcdir)/units -V | sed -n -e 's/^.*version[ ]*//p;q'`; \
	    if [ "$$exeversion" != "$$srcversion" ]; then \
		echo "executable version ($$exeversion) does not match source version ($$srcversion)"; \
		errors=`expr $$errors + 1`; \
	    fi; \
	    \
	    echo "Checking units data files ..."; \
	    datafile=`$(srcdir)/$(PROG) -I | sed -n -e "/Default units data file/{s/.*'\(.\{1,\}\)'.*/\1/p;q;}"`; \
	    if [ "$$datafile" != $(data_file) ]; then \
		echo "Default data file ("$$datafile") does not match '$(data_file)'"; \
		errors=`expr $$errors + 1`; \
	    fi; \
	    localemap=`$(srcdir)/$(PROG) -I | sed -n -e "/Default locale map/{s/.*'\(.\{1,\}\)'.*/\1/p;q;}"`; \
	    if [ "$$localemap" != $(locale_map) ]; then \
		echo "Default locale map ("$$localemap") does not match '$(locale_map)'"; \
		errors=`expr $$errors + 1`; \
	    fi; \
	    if [ "$$errors"  -gt 0 ]; then \
		if [ $$errors -gt 1 ]; then \
		    echo $$errors errors; \
		else \
		    echo $$errors error; \
		fi; \
		false; \
	    fi

	# generate the installer script for the specified VERSION
	@echo "Generating installer script ..."
	@sed '/define MyAppVersion/{'s/"xxx"/"$(VERSION)"/';}' $(INSTALLER_SCRIPT_TEMPLATE) \
	    > $(INSTALLER_SCRIPT)

	@echo ""
	@echo "Building $@ ..."
	@$(ISCC) $(windir)/$(INSTALLER_SCRIPT)
	@echo ""

# not used unless distribution is in WinZip format; usually needed only
# to get past an exe filter
zip: $(ZIPFILE)

$(ZIPFILE): $(INSTALLER)
	@echo "Creating $@"
	@$(ZIP) $(windir)/$(ZIPFILE) $(windir)/$(INSTALLER) > /dev/null
	@ls -l $(ZIPFILE)

$(FILES):
	@echo "Copying files:"
	@for file in $(DISTFILES); do \
	    echo "  $(srcdir)/$$file"; \
	    cp -p $(srcdir)/$$file $(windir); \
	done

	# rename file for Windows
	@echo "  $(srcdir)/COPYING to $(windir)/License.txt"
	@cp -p $(srcdir)/COPYING $(windir)/License.txt

	@make currency_update

	@echo "Converting files to CRLF:"
	@for file in $(TEXTFILES); do \
	    echo "  $$file"; \
	    $(UNIX2DOS) $$file; \
	done

# MikTeX for Windows usually needs to run twice to properly generate the
# Table of Contents
$(WINPDF): $(WINTEXI)
	@echo "Generating documentation ..."
	@$(TEXI2PDF) $(WINTEXI)
	@$(TEXI2PDF) $(WINTEXI)

currency_update:
	@if [ -x $(windir)/$(CUR_PROG) ]; then \
	    echo "Trying to update currency.units (will use existing file if this fails)"; \
	    $(windir)/$(CUR_PROG); \
	else \
	    echo "Using existing currency file"; \
	fi; \
	touch currency_update

# create binary signature and ASCII directive
winsig: windist
	@echo "Creating directive and signature"
	@echo 'version: 1.2' > $(INSTALLER).Directive
	@echo 'directory: units/windows' >> $(INSTALLER).Directive
	@echo 'filename: '$(INSTALLER) >> $(INSTALLER).Directive
	@$(GPG) --clearsign $(INSTALLER).Directive
	@$(GPG) -b $(INSTALLER)
	@ls -l $(INSTALLER).Directive.asc $(INSTALLER).sig
	@rm -f $(INSTALLER).Directive

install: windist
	$(windir)/$(INSTALLER)
	# make sure everything is OK
	$(install_dir)/$(PROG) -I

# make sure the executable is the right version, with the right paths for
# the support files
check:
	$(windir)/$(PROG) -I

# make sure the installed executable is the right version, with the right
# paths for the support files
check2:
	cd; $(install_dir)/$(PROG) -I

# see if a UTF-8 marker has been added
bomcheck:
	@file * | grep -e 'UTF-8' -e BOM

# remove any added UTF-8 markers; needs $(RMBOM) to work
rmbom:
	@$(RMBOM) $(TEXTFILES) $(CUR_PROG) *.iss *.texinfo

# get rid of the TeX auxilliary files
texclean: FORCE
	-rm -f UnitsForWindows.log \
	    *.aux *.cp *.fn *.ky *.op *.pg *.toc *.tp *.vr

clean: FORCE
	-rm -f $(INSTALLER) $(ZIPFILE) $(CUR_PROG)

distclean: clean texclean FORCE
	-rm -f $(DISTFILES) $(WINPDF) License.txt
	-rm -f $(INSTALLER_SCRIPT)
	-rm -f $(INSTALLER).directive $(INSTALLER).directive.asc $(INSTALLER).sig
	-rm -f $(ZIPFILE).directive $(ZIPFILE).directive.asc $(ZIPFILE).sig
	-rm -f currency_update

# files needed for Windows builder
# long form
listfiles: FORCE
	@ls -l $(BUILDERFILES)

# just file names
files: FORCE
	@ls $(BUILDERFILES)

list: FORCE
	@ls -l $(INSTALLER) $(DISTFILES) $(WINFILES) $(WINPDF)
	@if [ -e $(INSTALLER).Directive.asc ]; then \
	    ls -l $(INSTALLER).Directive.asc $(INSTALLER).sig; \
	fi

showsrc: FORCE
	@ls -ld $(srcdir)

# for PTC MKS make
FORCE:

# for GNU make; not recognized by PTC MKS make
.PHONY: clean texclean distclean

# Tell versions [3.59,3.63) of GNU make not to export all variables.
# Otherwise a system limit (for SysV at least) may be exceeded.
.NOEXPORT:
