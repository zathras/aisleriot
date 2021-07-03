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

import '../constants.dart';
import '../game.dart';

abstract class _FreecellGenericSlot implements Slot {
  /// Is moving movable to us?
  bool movableTo(_SlotStack moving, FreecellBoard board);

  bool canSelect(_SlotStack cards, FreecellBoard board);
}

typedef _SlotStack = CardStack<_FreecellGenericSlot>;
typedef _Move = Move<_FreecellGenericSlot>;
typedef _FoundCard = FoundCard<_FreecellGenericSlot>;

class _FreecellSlot extends NormalSlot implements _FreecellGenericSlot {
  _FreecellSlot(Board board, int slotNumber) : super(board, slotNumber);

  @override
  bool canSelect(_SlotStack cards, FreecellBoard board) => true;

  /// movable-to-freecell?
  @override
  bool movableTo(_SlotStack moving, FreecellBoard board) =>
      isEmpty && moving.numCards == 1;
}

class _HomecellSlot extends NormalSlot implements _FreecellGenericSlot {
  _HomecellSlot(Board board, int slotNumber) : super(board, slotNumber);

  @override
  bool canSelect(_SlotStack cards, FreecellBoard board) => false;

  /// movable-to-homecell?
  @override
  bool movableTo(_SlotStack moving, FreecellBoard board) {
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

  ///
  /// Is this card eligible for a move to a homecell, based on the minimum
  /// card values tehre now?  This is a little tricky.  It's true if c
  /// couldn't possibly be needed in the field to put another card on.
  ///
  static bool cardAutoEligible(Card c, List<int> homecellMin) {
    final minThisColor = homecellMin[c.suit.color.index];
    final minOtherColor = homecellMin[1 - c.suit.color.index];
    if (c.value <= minOtherColor + 1) {
      return true;
    } else if (c.value == minOtherColor + 2) {
      return c.value <= minThisColor + 2;
    } else {
      return false;
    }
  }
}

class _FieldSlot extends ExtendedSlot implements _FreecellGenericSlot {
  _FieldSlot(Board board, int slotNumber) : super(board, slotNumber);

  @override
  bool canSelect(_SlotStack cards, FreecellBoard board) =>
      FreecellBoard.fieldSequenceQ(cards);

  /// Based on movable-to-field?, but we already know the cards being
  /// considered are a sequence.
  @override
  bool movableTo(_SlotStack moving, FreecellBoard board) {
    if (moving.slot == this) {
      return false;
    }
    if (moving.numCards >
        (board.emptyFreecellCount() + 1) *
            _pow2(board.emptyFieldCount() - (isEmpty ? 1 : 0))) {
      // Note:  freecell.scm has a bit of code here that does nothing:
      //          (if (empty-slot? start-slot) 1 0)
      //        Start slot *can't* be empty, because card-list is there.
      //        And because of that, the max() does nothing.
      return false;
    }
    return isEmpty || FreecellBoard.fieldJoinQ(top, moving.bottom);
  }
}

class FreecellBoard<SD extends SlotData>
    extends Board<_FreecellGenericSlot, SD> {
  late final List<_FreecellSlot> freecell;
  late final List<_HomecellSlot> homecell;
  late final List<_FieldSlot> field;

  FreecellBoard(SD slotData) : super(slotData) {
    int slotNumber = 0;
    final freecell = List.generate(4, (i) => _FreecellSlot(this, slotNumber++),
        growable: false);
    final homecell = List.generate(4, (i) => _HomecellSlot(this, slotNumber++),
        growable: false);
    final field = List.generate(8, (_) => _FieldSlot(this, slotNumber++),
        growable: false);
    addActiveSlotGroup(freecell);
    this.freecell = List.unmodifiable(freecell);
    addActiveSlotGroup(homecell);
    this.homecell = List.unmodifiable(homecell);
    addActiveSlotGroup(field);
    this.field = List.unmodifiable(field);
  }

  @override
  bool get gameWon =>
      freecell.every((s) => s.isEmpty) && field.every((s) => s.isEmpty);

  @override
  bool canSelect(_SlotStack s) => s.slot.canSelect(s, this);

  @override
  bool canDrop(_FoundCard card, _FreecellGenericSlot dest) =>
      dest.movableTo(card, this);

  /// field-join?
  static bool fieldJoinQ(Card lower, Card upper) =>
      lower.suit.color != upper.suit.color && lower.value == upper.value + 1;

  /// field-sequence?
  static bool fieldSequenceQ(_SlotStack cards) {
    Card? upper;
    int toGo = cards.numCards;
    assert(NDEBUG || toGo > 0);
    for (final card in cards.slot.fromTop) {
      final u = upper;
      if (u != null && !fieldJoinQ(card, u)) {
        return false;
      }
      if (--toGo == 0) {
        break;
      }
      upper = card;
    }
    return true;
  }

  /// empty-field-number
  int emptyFieldCount() => field.fold(0, (acc, f) => acc + (f.isEmpty ? 1 : 0));

  /// empty-freecell-number
  int emptyFreecellCount() =>
      freecell.fold(0, (acc, f) => acc + (f.isEmpty ? 1 : 0));

  /// Indexed by CardColor.index
  List<int> minimumHomecellValues() {
    final result = List.filled(2, 99);
    final count = List.filled(2, 0);
    for (final s in homecell) {
      if (s.isNotEmpty) {
        final c = s.top;
        result[c.suit.color.index] = min(result[c.suit.color.index], c.value);
        count[c.suit.color.index]++;
      }
    }
    for (int i = 0; i < 2; i++) {
      if (count[i] < 2) {
        result[i] = 0;
      }
    }
    return result;
  }

  @override
  List<_Move> automaticMoves() {
    final homecellMin = minimumHomecellValues();
    _Move? check(_FreecellGenericSlot slot) {
      if (slot.isNotEmpty) {
        if (_HomecellSlot.cardAutoEligible(slot.top, homecellMin)) {
          final stack = CardStack(slot, 1, slot.top);
          for (final dest in homecell) {
            if (dest.movableTo(stack, this)) {
              return _Move(src: stack, dest: dest, automatic: true);
            }
          }
        }
      }
      return null;
    }

    for (final slot in freecell) {
      final m = check(slot);
      if (m != null) {
        return [m];
      }
    }
    for (final slot in field) {
      final m = check(slot);
      if (m != null) {
        return [m];
      }
    }
    return const [];
  }

  @override
  void debugPrintGoodness() => print('Goodness now ${_calculateGoodness()}');

  double _calculateGoodness() {
    double weight = 0;
    int emptyFreecells = 0;
    for (final s in freecell) {
      if (s.isEmpty) {
        emptyFreecells++;
      } else {
        weight++;
      }
    }
    int emptyFields = 0;
    for (final s in field) {
      Card? upper;
      if (s.isEmpty) {
        emptyFields++;
      }
      double stackWeight = 0;
      double stackWeightIncr = 0.25;
      for (final card in s.fromTop) {
        final u = upper;
        if (u == null) {
          weight += stackWeight + 1;
        } else if (!FreecellBoard.fieldJoinQ(card, u)) {
          weight += stackWeight + 1;
          stackWeight = 0;
          // Don't change stackWeightIncr - buried runs are still good,
          // but not as good as unburied ones.
        } else {
          stackWeight += stackWeightIncr;
          stackWeightIncr += 0.01; // slightly encourage balanced stacks
        }
        upper = card;
      }
      if (upper?.value == 13) {
        // encourage king on bottom
        weight -= 1;
      } else {
        weight += stackWeight;
      }
    }
    int homeMin = 99;
    int redMax = 0;
    int blackMax = 0;
    for (final s in homecell) {
      homeMin = min(homeMin, s.numCards);
      if (s.isNotEmpty) {
        if (s.top.suit.color == CardColor.black) {
          blackMax = max(blackMax, s.top.value);
        } else {
          redMax = max(redMax, s.top.value);
        }
      }
    }
    final minMax = min(blackMax, redMax);
    double bonus = 20.0 * minMax + 100.0 * homeMin;
    int mobility = (emptyFreecells + 1) * _pow2(emptyFields);
    // print("  mobility $mobility weight $weight bonus $bonus");
    mobility = min(mobility, 6);
    mobility *= 10000;
    weight = max(99 - weight, 0);
    return bonus + mobility + weight * 100 + max(99 - slotData.depth, 0);
  }

  @override
  FreecellBoard<SearchSlotData> makeSearchBoard() =>
      FreecellBoard(slotData.copy(0));

  @override
  void calculateChildren(FreecellBoard<SearchSlotData> scratch,
          bool Function(SearchSlotData child) accepted) =>
      _ChildCalculator(scratch, accepted).run();

  @override
  // TODO: implement externalID
  String get externalID => 'f0'; // freecell version 0
}

class _ChildCalculator {
  final FreecellBoard<SearchSlotData> scratch;
  final bool Function(SearchSlotData child) accepted;

  _ChildCalculator(this.scratch, this.accepted);

  void moveTo(_SlotStack src, List<_FreecellGenericSlot> slots,
      {bool justOne = false}) {
    final SearchSlotData initial = scratch.slotData;
    for (final dest in slots) {
      if (dest != src.slot && dest.movableTo(src, scratch)) {
        final child = initial.copy(initial.depth + 1);
        scratch.slotData = child;
        child.viaSlotFrom = src.slot.slotNumber;
        child.viaSlotTo = dest.slotNumber;
        child.viaNumCards = src.numCards;
        _Move(src: src, dest: dest, automatic: false).move();
        scratch.doAllAutomaticMoves();
        final srcTop = src.slot.isEmpty ? null : src.slot.top;
        scratch.canonicalize();
        child.goodness = scratch._calculateGoodness();
        final more = accepted(child);
        if (more && srcTop != null) {
          // src must be a field slot, so we explore further up that slot.
          _FieldSlot? newSrc;
          for (final s in scratch.field) {
            if (s.top == srcTop) {
              newSrc = s;
              break;
            }
          }
          assert(newSrc != null);
          tryFromField(newSrc!);
        }
        scratch.slotData = initial;
        if (justOne) {
          break;
        }
      }
    }
  }

  void tryFromField(_FieldSlot s) {
    int numCards = 1;
    for (final bottom in s.fromTop) {
      final src = _SlotStack(s, numCards, bottom);
      if (!s.canSelect(src, scratch)) {
        break;
      }
      moveTo(src, scratch.homecell, justOne: true);
      moveTo(src, scratch.freecell, justOne: true);
      moveTo(src, scratch.field);
      numCards++;
    }
  }

  void run() {
    final SearchSlotData initial = scratch.slotData;
    for (final s in scratch.freecell) {
      if (s.isNotEmpty) {
        final src = _SlotStack(s, 1, s.top);
        moveTo(src, scratch.homecell, justOne: true);
        moveTo(src, scratch.field);
      }
    }
    for (final s in scratch.field) {
      tryFromField(s);
    }
    assert(NDEBUG || identical(scratch.slotData, initial));
  }

}

class Freecell extends Game<_FreecellGenericSlot> {
  @override
  final FreecellBoard<ListSlotData> board;

  Freecell._p(this.board, List<SlotOrLayout> slots) : super(slots);

  factory Freecell() {
    Deck d = Deck();
    final board = FreecellBoard(ListSlotData(16));
    int f = 0;
    while (!d.isEmpty) {
      board.field[f].addCard(d.dealCard());
      f++;
      f %= board.field.length;
    }
    final allSlots = List<SlotOrLayout>.empty(growable: true);
    allSlots.add(CarriageReturnSlot(extraHeight: 0.3));
    allSlots.add(HorizontalSpaceSlot(0.4));
    for (final s in board.freecell) {
      allSlots.add(s);
      allSlots.add(HorizontalSpaceSlot(1 / 24));
    }
    allSlots.add(HorizontalSpaceSlot(0.2));
    for (final s in board.homecell) {
      allSlots.add(s);
      allSlots.add(HorizontalSpaceSlot(1 / 24));
    }
    allSlots.add(HorizontalSpaceSlot(0.4 - 1 / 24));
    allSlots.add(CarriageReturnSlot(extraHeight: 0.3));
    allSlots.add(HorizontalSpaceSlot(0.5));
    for (final s in board.field) {
      allSlots.add(s);
      allSlots.add(HorizontalSpaceSlot(1 / 24));
    }
    allSlots.add(CarriageReturnSlot(extraHeight: 0.2));
    return Freecell._p(board, allSlots);
  }

  @override
  List<_Move> doubleClick(_SlotStack s) {
    if (board.canSelect(s)) {
      final homecellMin = board.minimumHomecellValues();
      final Card card = s.slot.top;
      if (_HomecellSlot.cardAutoEligible(card, homecellMin)) {
        for (final dest in board.homecell) {
          if (dest.movableTo(s, board)) {
            return [_Move(src: s, dest: dest, automatic: false)];
          }
        }
      }
      for (final dest in board.freecell) {
        if (dest.movableTo(s, board)) {
          return [_Move(src: s, dest: dest, automatic: false)];
        }
      }
    }
    return const [];
  }

  @override
  Freecell newGame() => Freecell();
}

// 2^exp
int _pow2(int exp) => 1 << exp;
