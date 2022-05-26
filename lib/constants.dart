/*
 Copyright (C) 2021, William Foote

 Author: William Foote

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

/// Hack for an experiment:  Around 2021, I measured the performance
/// of the static compiler versus the dynamic compiler.  To make
/// it a fair comparision, I had to shut off assertions, so I added
/// this constant.
///
/// Interestingly, on MacOS the dynamic compiler (the "debug" one)
/// was faster for game solving!
const bool disableDebug = false;

/// package_info doesn't exist for all platforms, so I'm doing it the old
/// fashioned way.
const applicationVersion = '0.1';
final Uri applicationWebAddress = Uri.parse('https://aisleriot.jovial.com');
final Uri applicationIssueAddress = Uri.parse('https://github.com/zathras/aisleriot/issues');

const nonWarranty = '''
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
''';

const license = '''
 Copyright (C) 2021-2022, William Foote

 Portions also copyright by various other authors, where the work
 is derived from Aisleriot sources (https://wiki.gnome.org/Apps/Aisleriot).

 INFORMATIVE NOTE:  Consultation/use of Aisleriot sources was limited to the
 game logic and API, written in Scheme, and the card assets.  The game
 sources can be found in doc/original, and the card assets in assets/cards.

 Author: William Foote 
         Various, as noted in some other files

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
$nonWarranty
 The GNU General Public License is available at
 http://www.gnu.org/licenses/.
''';
