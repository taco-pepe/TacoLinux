			 units 2.24 for Windows
			     November 2024

Introduction
============
The units program converts quantities expressed in various systems of
measurement to their equivalents in other systems of measurement.  Like
many similar programs, it can handle multiplicative scale changes; but
it can also handle nonlinear conversions such as Fahrenheit to Celsius.
The program can also perform conversions from and to sums of units, such
as converting between meters and feet plus inches.

Basic operation is simple: at the 'You have:' prompt, enter the unit
from which you want to convert; at the subsequent 'You want:' prompt,
enter the unit to which you want to convert. For example,

  You have: ft
  You want: m
          * 0.3048
          / 3.2808399

In other words, 1 foot is equal to 0.3048 meter (exactly), and 1 meter
is equal to approximately 3.2808339 feet.

To quit the program, press Ctrl-C or Ctrl-Z; with the latter, you may
need to press 'Enter'.

Running units
=============
You can run units from the command line, or via Start Menu or Desktop
shortcuts if you chose to create them during installation.  The 'units'
shortcut runs units in the traditional Windows Console Host.  If you
have Windows Terminal installed, you should have additional 'units WT'
shortcut that runs units in Windows Terminal with Unicode support.

Documentation
=============
The program's features are briefly described in UnitsForWindows, and are
described in detail in the user manual.  Unless you declined to create a
Start Menu folder, you can access the user manual from the Start Menu.
From the Start Menu, select 'Programs', position the cursor over 'units'
(or whatever name you specified during installation), and select 'Units
User Manual' from the submenu that appears.  The manual is PDF; to view
it, you will need the free Adobe Reader or a similar application.  Adobe
Reader is available from Adobe at http://www.adobe.com.

Updating Currency Definitions
=============================
The script units_cur.py can be used to update currency definitions (if
your system hides file extensions, this script will display as
"units_cur").  The script requires Python (available from
https://www.python.org/).

If you want to use the currency updater, install Python
You then should be able to run units_cur.py using the shortcut on the
Start Menu, or if you have added the units installation directory to
your PATH, from a command window.

Updating currency definitions is described in more detail in
UnitsForWindows.
