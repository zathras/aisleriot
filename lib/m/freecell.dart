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

abstract class _FreecellGenericSlot implements Slot {
  /// Is moving movable to us?
  bool movableTo(_SlotStack moving, FreecellBoard board);

  bool canSelect(_SlotStack cards, FreecellBoard board);

  _FreecellGenericSlot _clone();
}

typedef _SlotStack = CardStack<_FreecellGenericSlot>;
typedef _Move = Move<_FreecellGenericSlot>;
typedef _FoundCard = FoundCard<_FreecellGenericSlot>;

class _FreecellSlot extends NormalSlot implements _FreecellGenericSlot {
  _FreecellSlot(int slotNumber, {_FreecellSlot? copyFrom})
      : super(slotNumber, copyFrom: copyFrom);

  @override
  bool canSelect(_SlotStack cards, FreecellBoard board) => true;

  /// movable-to-freecell?
  @override
  bool movableTo(_SlotStack moving, FreecellBoard board) =>
      isEmpty && moving.numCards == 1;

  @override
  _FreecellSlot _clone() => _FreecellSlot(slotNumber, copyFrom: this);
}

class _HomecellSlot extends NormalSlot implements _FreecellGenericSlot {
  _HomecellSlot(int slotNumber, {_HomecellSlot? copyFrom})
      : super(slotNumber, copyFrom: copyFrom);

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

  @override
  _HomecellSlot _clone() => _HomecellSlot(slotNumber, copyFrom: this);
}

class _FieldSlot extends ExtendedSlot implements _FreecellGenericSlot {
  _FieldSlot(int slotNumber, {_FieldSlot? copyFrom})
      : super(slotNumber, copyFrom: copyFrom);

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

  @override
  _FieldSlot _clone() => _FieldSlot(slotNumber, copyFrom: this);
}

class FreecellBoard extends Board<_FreecellGenericSlot> {
  final List<_FreecellSlot> freecell;
  final List<_HomecellSlot> homecell;
  final List<_FieldSlot> field;

  FreecellBoard(List<_FreecellSlot> freecell, List<_HomecellSlot> homecell,
      List<_FieldSlot> field)
      : freecell = List.unmodifiable(freecell),
        homecell = List.unmodifiable(homecell),
        field = List.unmodifiable(field),
        super([...freecell, ...homecell, ...field]);

  @override
  bool get gameWon =>
      freecell.every((s) => s.isEmpty) && field.every((s) => s.isEmpty);

  @override
  bool canSelect(_SlotStack s) => s.slot.canSelect(s, this);

  @override
  bool canDrop(_FoundCard card, _FreecellGenericSlot dest) =>
      dest.movableTo(card, this);

  /// 0 (one less than ace) on empty
  int minimumHomecellValue() =>
      homecell.fold(99, (a, _HomecellSlot v) => min(a, v.numCards));

  /// field-join?
  static bool fieldJoinQ(Card lower, Card upper) =>
      lower.suit.color != upper.suit.color && lower.value == upper.value + 1;

  /// field-sequence?
  static bool fieldSequenceQ(_SlotStack cards) {
    Card? upper;
    int toGo = cards.numCards;
    assert(toGo > 0);
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
  FreecellSearchBoard toSearchBoard() => FreecellSearchBoard(this);
}

class FreecellSearchBoard extends FreecellBoard
    implements SearchBoard<_FreecellGenericSlot> {
  @override
  int get goodness => _goodness;
  int _goodness;
  final int depth;
  @override
  final FreecellSearchBoard? from;

  /// We get from from to this board by applying move via, and then any
  /// automatic moves.
  @override
  final _Move? via;

  FreecellSearchBoard(FreecellBoard other)
      : _goodness = _calculateGoodness(other.freecell, other.field, 0),
        depth = 0,
        from = null,
        via = null,
        super(
            _copy(other.freecell), _copy(other.homecell), _copy(other.field)) {
    doAllAutomaticMoves();
  }

  FreecellSearchBoard._withMove(FreecellSearchBoard from, _Move move)
      : _goodness = -1,
        depth = from.depth + 1,
        from = from,
        via = move,
        super(_copy(from.freecell), _copy(from.homecell), _copy(from.field)) {
    final mSrc = _SlotStack(slotFromNumber(move.src.slot.slotNumber),
        move.src.numCards, move.src.bottom);
    _Move(src: mSrc, dest: slotFromNumber(move.dest.slotNumber)).move();
    doAllAutomaticMoves();
    _goodness = _calculateGoodness(freecell, field, depth);
  }

  void doAllAutomaticMoves() {
    for (;;) {
      final moves = automaticMoves();
      if (moves.isEmpty) {
        break;
      }
      for (final m in moves) {
        m.move();
      }
    }
  }

  static List<T> _copy<T extends _FreecellGenericSlot>(List<T> src) {
    final r = List<T>.from(src);
    for (int i = 0; i < r.length; i++) {
      r[i] = r[i]._clone() as T;
    }
    return r;
  }

  static int _calculateGoodness(final List<_FreecellSlot> freecell,
      final List<_FieldSlot> field, final int depth) {
    int weight = 0;
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
      for (final card in s.fromTop) {
        final u = upper;
        if (u == null || !FreecellBoard.fieldJoinQ(card, u)) {
          weight++;
        }
        upper = card;
      }
      ;
    }
    int mobility = (emptyFreecells + 1) * _pow2(emptyFields);
    mobility = min(mobility, 6);
    mobility *= 10000;
    weight = max(99 - weight, 0);
    return mobility + weight + max(99 - depth, 0);
  }

  @override
  FreecellSearchBoard toSearchBoard() => this;

  @override
  void calculateChildren(void Function(FreecellSearchBoard child) f) {
    void moveTo(_SlotStack src, List<_FreecellGenericSlot> slots,
        {bool justOne = false}) {
      for (final dest in slots) {
        if (dest != src.slot && dest.movableTo(src, this)) {
          final m = _Move(src: src, dest: dest, animate: true);
          f(FreecellSearchBoard._withMove(this, m));
          if (justOne) {
            break;
          }
        }
      }
    }

    for (final s in freecell) {
      if (s.isNotEmpty) {
        final src = _SlotStack(s, 1, s.top);
        moveTo(src, homecell, justOne: true);
        moveTo(src, field);
      }
    }
    for (final s in field) {
      int numCards = 1;
      for (final bottom in s.fromTop) {
        final src = _SlotStack(s, numCards, bottom);
        if (!s.canSelect(src, this)) {
          break;
        }
        moveTo(src, homecell, justOne: true);
        moveTo(src, freecell, justOne: true);
        moveTo(src, field);
        numCards++;
      }
    }
  }
}

class Freecell extends Game<_FreecellGenericSlot> {
  @override
  final FreecellBoard board;

  Freecell._p(this.board, List<SlotOrLayout> slots) : super(slots);

  factory Freecell() {
    Deck d = Deck();
    int slotNumber = 0;
    final freecell =
        List.generate(4, (i) => _FreecellSlot(slotNumber++), growable: false);
    final homecell =
        List.generate(4, (i) => _HomecellSlot(slotNumber++), growable: false);
    final field =
        List.generate(8, (_) => _FieldSlot(slotNumber++), growable: false);
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
    final board = FreecellBoard(freecell, homecell, field);
    return Freecell._p(board, allSlots);
  }

  @override
  List<_Move> doubleClick(_SlotStack s) {
    if (board.canSelect(s)) {
      final eligibleValue = board.minimumHomecellValue() + 2;
      final Card card = s.slot.top;
      if (card.value <= eligibleValue) {
        for (final dest in board.homecell) {
          if (dest.movableTo(s, board)) {
            return [_Move(src: s, dest: dest)];
          }
        }
      }
      for (final dest in board.freecell) {
        if (dest.movableTo(s, board)) {
          return [_Move(src: s, dest: dest)];
        }
      }
    }
    return const [];
  }
}

// 2^exp
int _pow2(int exp) => 1 << exp;
