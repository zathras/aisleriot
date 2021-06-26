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

import 'package:aisleriot/graphics.dart';

import 'game.dart';

abstract class _FreecellGenericSlot extends Slot {
  /// Is moving movable to us?
  bool movableTo(_SlotStack moving, Freecell game);

  bool canSelect(_SlotStack cards, Freecell game);
}

typedef _SlotStack = CardStack<_FreecellGenericSlot>;
typedef _Move = Move<_FreecellGenericSlot>;
typedef _FoundCard = FoundCard<_FreecellGenericSlot>;

class _FreecellSlot extends NormalSlot implements _FreecellGenericSlot {
  @override
  bool canSelect(_SlotStack cards, Freecell game) => true;

  /// movable-to-freecell?
  @override
  bool movableTo(_SlotStack moving, Freecell game) =>
      isEmpty && moving.numCards == 1;
}

class _HomecellSlot extends NormalSlot implements _FreecellGenericSlot {
  @override
  bool canSelect(_SlotStack cards, Freecell game) => false;

  /// movable-to-homecell?
  @override
  bool movableTo(_SlotStack moving, Freecell game) {
    if (moving.slot == this || moving.numCards != 1) {
      return false;
    }
    final card = moving.slot.top;
    if (isEmpty) {
      return card.value == 1;
    } else {
      return top.suit == card.suit && top.value + 1 == card.value;
    }
  }
}

class _FieldSlot extends ExtendedSlot implements _FreecellGenericSlot {
  @override
  bool canSelect(_SlotStack cards, Freecell game) =>
      game.fieldSequenceQ(cards);

  /// Based on movable-to-field?, but we already know the cards being
  /// considered are a sequence.
  @override
  bool movableTo(_SlotStack moving, Freecell game) {
    if (moving.slot == this) {
      return false;
    }
    if (moving.numCards >
        (game.emptyFreecellCount() + 1) *
            pow(2, game.emptyFieldCount() - (isEmpty ? 1 : 0))) {
      // Note:  freecell.scm has a bit of code here that does nothing:
      //          (if (empty-slot? start-slot) 1 0)
      //        Start slot *can't* be empty, because card-list is there.
      //        And because of that, the max() does nothing.
      return false;
    }
    return isEmpty || game.fieldJoinQ(top, moving.bottom);
  }
}

class Freecell extends Game<_FreecellGenericSlot> {
  final List<_FreecellSlot> freecell;
  final List<_HomecellSlot> homecell;
  final List<_FieldSlot> field;

  Freecell._p(
      {required this.freecell,
      required this.homecell,
      required this.field,
      required List<SlotOrLayout> slots})
      : super(slots);

  factory Freecell() {
    Deck d = Deck();
    final freecell = List.generate(4, (i) => _FreecellSlot(), growable: false);
    final homecell = List.generate(4, (i) => _HomecellSlot(), growable: false);
    final field = List.generate(8, (_) => _FieldSlot(), growable: false);
    int f = 0;
    while (!d.isEmpty) {
      field[f].addCard(d.dealCard());
      f++;
      f %= field.length;
    }
    final allSlots = List<SlotOrLayout>.empty(growable: true);
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
    for (final s in field) {
      allSlots.add(s);
      allSlots.add(HorizontalSpaceSlot(1 / 24));
    }
    allSlots.add(CarriageReturnSlot(extraHeight: 0.2));
    return Freecell._p(
        freecell: freecell, homecell: homecell, field: field, slots: allSlots);
  }

  @override
  bool canSelect(_SlotStack s) => s.slot.canSelect(s, this);

  @override
  bool canDrop(_FoundCard card, _FreecellGenericSlot dest) =>
      dest.movableTo(card, this);

  @override
  List<_Move> doubleClick(_SlotStack s) {
    if (canSelect(s)) {
      final eligibleValue = minimumHomecellValue() + 2;
      final Card card = s.slot.top;
      if (card.value <= eligibleValue) {
        for (final dest in homecell) {
          if (dest.movableTo(s, this)) {
            return [_Move(src: s, dest: dest)];
          }
        }
      }
      for (final dest in freecell) {
        if (dest.movableTo(s, this)) {
          return [_Move(src: s, dest: dest)];
        }
      }
    }
    return const [];
  }

  /// 0 (one less than ace) on empty
  int minimumHomecellValue() =>
      homecell.fold(99, (a, _HomecellSlot v) => min(a, v.numCards));

  /// field-join?
  bool fieldJoinQ(Card lower, Card upper) =>
      lower.suit.color != upper.suit.color && lower.value == upper.value + 1;

  /// field-sequence?
  bool fieldSequenceQ(_SlotStack cards) {
    Card? upper;
    return cards.slot.allTrueFromTop((card) {
      final u = upper;
      upper = card;
      return u == null || fieldJoinQ(card, u);
    }, maxCards: cards.numCards);
  }

  /// empty-field-number
  int emptyFieldCount() => field.fold(0, (acc, f) => acc + (f.isEmpty ? 1 : 0));

  /// empty-freecell-number
  int emptyFreecellCount() =>
      freecell.fold(0, (acc, f) => acc + (f.isEmpty ? 1 : 0));

  @override
  List<_Move> automaticMoves() {
    final eligibleValue = minimumHomecellValue() + 2;
    _Move? check(_FreecellGenericSlot slot) {
      if (slot.isNotEmpty) {
        if (slot.top.value <= eligibleValue) {
          final stack = CardStack(slot, 1, slot.top);
          for (final dest in homecell) {
            if (dest.movableTo(stack, this)) {
              return _Move(src: stack, dest: dest);
            }
          }
        }
      }
      return null;
    }
    for (final slot in freecell) {
      final m = check(slot);
      if (m != null) {
        return [ m ];
      }
    }
    for (final slot in field) {
      final m = check(slot);
      if (m != null) {
        return [ m ];
      }
    }
    return const [];
  }
}
