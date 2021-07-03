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


const bool NDEBUG = false;

/// package_info doesn't exist for all platforms, so I'm doing it the old
/// fashioned way.
const APPLICATION_VERSION = '0.1';
const APPLICATION_WEB_ADDRESS = 'https://aisleriot.jovial.com';
const APPLICATION_ISSUE_ADDRESS = 'https://github.com/zathras/aisleriot/issues';

const NON_WARRANTY = '''
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
''';

const LICENSE = '''
 Copyright (C) 2021, William Foote

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
$NON_WARRANTY
 The GNU General Public License is available at
 http://www.gnu.org/licenses/.
''';
