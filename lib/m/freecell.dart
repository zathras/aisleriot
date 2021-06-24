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

import 'dart:math';

import 'game.dart';

class _FreecellSlot extends NormalSlot {}

class _HomecellSlot extends NormalSlot {}

class Freecell extends Game {
  final List<_FreecellSlot> freecell;
  final List<_HomecellSlot> homecell;
  final List<ExtendedSlot> tableau;

  Freecell._p(
      {required this.freecell,
      required this.homecell,
      required this.tableau,
      required List<Slot> slots})
      : super(slots);

  factory Freecell() {
    Deck d = Deck();
    final freecell = List.generate(4, (i) => _FreecellSlot(), growable: false);
    final homecell = List.generate(4, (i) => _HomecellSlot(), growable: false);
    final tableau = List.generate(8, (_) => ExtendedSlot(), growable: false);
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
      allSlots.add(HorizontalSpaceSlot(1 / 24));
    }
    allSlots.add(HorizontalSpaceSlot(0.2));
    for (final s in homecell) {
      allSlots.add(s);
      allSlots.add(HorizontalSpaceSlot(1 / 24));
    }
    allSlots.add(HorizontalSpaceSlot(0.4 - 1 / 24));
    allSlots.add(CarriageReturnSlot(extraHeight: 0.3));
    allSlots.add(HorizontalSpaceSlot(0.5));
    for (final s in tableau) {
      allSlots.add(s);
      allSlots.add(HorizontalSpaceSlot(1 / 24));
    }
    allSlots.add(CarriageReturnSlot(extraHeight: 0.2));
    return Freecell._p(
        freecell: freecell,
        homecell: homecell,
        tableau: tableau,
        slots: allSlots);
  }

  @override
  bool canSelect(SlotStack s) {
    if (s.slot is ExtendedSlot) {
      return fieldSequenceQ(s.toList());
    } else if (s.slot is _HomecellSlot) {
      return false;
    } else {
      assert(s.slot is _FreecellSlot);
      return true;
    }
  }

  @override
  List<Move> doubleClick(SlotStack s) {
    if (s.slot.cards.isNotEmpty &&
        (s.slot is ExtendedSlot || s.slot is _FreecellSlot)) {
      final Card card = s.slot.cards.last;
      final eligibleValue = minimumHomecellValue() + 2;
      if (card.value <= eligibleValue) {
        for (final dest in homecell) {
          if (dest.cards.isEmpty ||
              (dest.cards.first.suit == card.suit &&
                  dest.cards.last.value + 1 == card.value)) {
            return [Move(src: s.slot, dest: dest)];
          }
        }
      }
      for (final dest in freecell) {
        if (s.slot != dest && dest.cards.isEmpty) {
          return [Move(src: s.slot, dest: dest)];
        }
      }
      for (final dest in tableau) {
        if (s.slot != dest && dest.cards.isEmpty) {
          return [Move(src: s.slot, dest: dest)];
        }
      }
    }
    return const [];
  }

  int minimumHomecellValue() =>
      homecell.fold(99, (a, v) => min(a, v.cards.length));

  /// field-join?
  bool fieldJoinQ(Card lower, Card upper) =>
      lower.suit.color != upper.suit.color && lower.value + 1 == upper.value;

  /// field-sequence?
  bool fieldSequenceQ(CardList? cards) {
    // Dart does NOT optimize tail recursion (because JS is evil), so I guess
    // I will.  cf. https://github.com/dart-lang/language/issues/1159
    for (;;) {
      if (cards == null || cards.cdr == null) {
        return true;
      } else if (!fieldJoinQ(cards.car, cards.cadr)) {
        return false;
      } else {
        cards = cards.cdr;
      }
    }
  }
}
