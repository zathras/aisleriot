/*
 Copyright (C) 2021, William Foote
 Copyright (C) 1998, 2003 Changwoo Ryu

 Author: William Foote (Port from Scheme to Dart)
         Changwoo Ryu <cwryu@adam.kaist.ac.kr> (Original Scheme version)

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



import 'game.dart';

class Freecell extends Game {
  final List<NormalSlot> freecell;
  final List<NormalSlot> homecell;
  final List<ExtendedSlot> tableau;

  Freecell._p(
      {required this.freecell,
      required this.homecell,
      required this.tableau,
      required List<Slot> slots})
      : super(slots);

  factory Freecell() {
    Deck d = Deck();
    final freecell = List<NormalSlot>.generate(
        4, (i) => NormalSlot(),
        growable: false);
    final homecell = List<NormalSlot>.generate(
        4, (i) => NormalSlot(),
        growable: false);
    final tableau =
        List<ExtendedSlot>.generate(8, (_) => ExtendedSlot(), growable: false);
    int f = 0;
    while (!d.isEmpty) {
      tableau[f].cards.add(d.dealCard());
      f++;
      f %= tableau.length;
    }
    final allSlots = List<Slot>.empty(growable: true);
    allSlots.add(CarriageReturnSlot(extraHeight: 0.3));
    allSlots.add(HorizontalSpaceSlot(0.4));
    for (final s in freecell) {
      allSlots.add(s);
      allSlots.add(HorizontalSpaceSlot(1/24));
    }
    allSlots.add(HorizontalSpaceSlot(0.2));
    for (final s in homecell) {
      allSlots.add(s);
      allSlots.add(HorizontalSpaceSlot(1/24));
    }
    allSlots.add(HorizontalSpaceSlot(0.4 - 1/24));
    allSlots.add(CarriageReturnSlot(extraHeight: 0.3));
    allSlots.add(HorizontalSpaceSlot(0.5));
    for (final s in tableau) {
      allSlots.add(s);
      allSlots.add(HorizontalSpaceSlot(1/24));
    }
    allSlots.add(CarriageReturnSlot(extraHeight: 0.2));
    return Freecell._p(
        freecell: freecell,
        homecell: homecell,
        tableau: tableau,
        slots: allSlots);
  }
}
