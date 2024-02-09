/*
 Copyright (C) 2022, William Foote

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

import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;
import 'dart:io' show Platform;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' as ui;
import 'package:flutter/foundation.dart';
import 'package:jovial_misc/circular_buffer.dart';
import 'package:quiver/collection.dart' as quiver;
import 'package:quiver/core.dart' as quiver;

import 'constants.dart';
import 'graphics.dart';
import 'game.dart';
import 'controller.dart';

abstract class Solver<ST extends Slot> {
  void stop();
}

bool _isDesktop() {
  if (ui.kIsWeb) {
    return false;
  } else if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
    return true;
  } else {
    return false;
  }
}

class SolutionSearcher<ST extends Slot> extends Solver<ST> {
  final GameController<ST> controller;
  final Board<ST, ListSlotData> board;
  bool _stopped = false;
  int lastReportedArrangements = 0;
  static final int maxArrangements = (_isDesktop()) ? 4000000 : 40000000;
  static final List<double> solveTimes = CircularBuffer(Float64List(20000));

  SolutionSearcher(this.controller) : board = controller.game.board;

  @override
  void stop() {
    _stopped = true;
    controller.painter.currentSearch = null;
  }

  /// Returns true if we exit for an OK reason, false if we fail.
  Future<bool> solve() async {
    final scratch = board.makeSearchBoard();
    controller.painter.currentSearch = scratch;
    final initial = scratch.slotData;
    final external = scratch.toExternal();
    final q = PriorityQueue<SearchSlotData>(
        (a, b) => b.goodness.compareTo(a.goodness));
    final seen = HashSet<List<int>>(
        equals: quiver.listsEqual, hashCode: quiver.hashObjects);
    scratch.doAllAutomaticMoves();
    scratch.canonicalize();
    seen.add(scratch.slotData.raw);
    final sw = Stopwatch()..start();
    scratch.calculateChildren(scratch, (k) {
      if (seen.add(k.raw)) {
        q.add(k);
        return true;
      } else {
        return false;
      }
    });
    double nextFrame = 0.25 * sw.frequency;
    int iterations = 0;
    while (q.isNotEmpty && seen.length < maxArrangements) {
      if (_stopped) {
        return true;
      }
      if (seen.length > lastReportedArrangements + (maxArrangements ~/ 40)) {
        lastReportedArrangements = seen.length;
      }
      final k = q.removeFirst();
      scratch.slotData = k;
      k.timeUsed = sw.elapsedTicks / sw.frequency;
      if (sw.elapsedTicks > nextFrame) {
        nextFrame += 0.25 * sw.frequency;
        controller.publicNotifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      if (scratch.gameWon) {
        sw.stop();
        scratch.slotData = initial;
        SearchSlotData? next = k;
        final path = List.generate(k.depth + 1, (_) {
          final sd = next!;
          next = sd.from;
          return sd;
        });
        final solution = Solution(path, scratch);
        assert(next == null);
        stop();
        final solveTime = sw.elapsedTicks / sw.frequency;
        if (solveTime >= 10) {
          debugPrint('Solve time $solveTime for $external, '
              '$iterations iterations, ${seen.length} arrangements');
        }
        solveTimes.add(solveTime);
        controller.solver = solution;
        await solution.run(controller);
        return true;
      }
      iterations++;
      scratch.calculateChildren(scratch, (final SearchSlotData kk) {
        if (seen.add(kk.raw)) {
          q.add(kk);
          return true;
        } else {
          return false;
        }
      });
    }
    final msg = q.isEmpty ? '@@ No solution.  ' : '@@ Gave up.  ';
    debugPrint('Failed to solve $external');
    debugPrint('  $msg $iterations iterations, ${seen.length} arrangements'
        ' in ${sw.elapsed}.');
    sw.stop();
    solveTimes.add(sw.elapsedTicks / sw.frequency);
    controller.stopSolve();
    controller.publicNotifyListeners();
    return false;
  }
}

///
/// A solution of this game.  The data structure looks like this:
/// <pre>
///              from ┌──────┐      ┌──────┐          ┌──────┐         ┌──────┐
///             ┌─────┤ null │ from │  m1  │   from   │  m2  │  from   │  m3  │
///             ▼     │      │◄─────┤      │◄─────────┤      │◄────────┤      │
///            ───    │      │      │      │          │      │         │      │
///            ///    │  s0  │      │ s1   │          │ s2   │         │ s3   │
///       auto,canon  │      │      │      │          │      │         │      │
///      ┌──────────► │      │      └────┬─┘          └───┬──┘         └──────┘
///      │            └──┬───┘       ▲   │m2          ▲   │m3            ▲
/// ┌────┴──┐            │m1         │   │            │   │              │
/// │ start │            ▼           │   ▼            │   ▼              │
/// │       │           ┌──┐         │  ┌──┐          │ ┌──┐             │
/// │       │           │b1├─────────┘  │b2├──────────┘ │b3├─────────────┘
/// │       │           └──┘auto,canon  └──┘ auto,canon └──┘ auto,canon
/// │       │
/// └───────┘
///
/// </pre>
/// Each box is a board arrangement; SearchSlotData instances are along the
/// top, where m? is viaXXX.  For the pictured graph, path would contain
/// [s3, s2, s1, s0].
///
class Solution<ST extends Slot> extends Solver<ST> {
  /// The path to the solution, in reverse order.
  /// path[0] is the solved game.
  final List<SearchSlotData> path;

  int nextStep;

  /// For nextStep, the map from the slot numbers in
  /// path[nextStep].viaXXX to the real game board.  This moves around
  /// due to slot canonicalization.
  final List<int> slotMap;

  /// A board we can modify as we go
  final Board<ST, SearchSlotData> scratch;

  bool _stopped = false;

  final waitForDone = Completer<void>();

  Solution(this.path, this.scratch)
      : nextStep = path.length - 1,
        slotMap = List<int>.generate(scratch.numSlots, (i) => i);

  @override
  void stop() => _stopped = true;

  bool get done => nextStep < 0;

  Future<void> run(GameController<ST> controller) {
    assert(path.isEmpty || path[path.length - 1].from == null);
    if (controller.game.canUndo) {
      // There can be no automatic moves
      _moveCompleted(controller, false);
    } else {
      controller.doAutomaticMoves(() => _moveCompleted(controller, true));
    }
    return waitForDone.future;
  }

  /// Now, both scratch and game are at one of the "s" states along the top.
  void _moveCompleted(GameController<ST> controller, bool auto) {
    int nextEmptySlot = 0;
    final board = controller.game.board;
    assert(disableDebug ||
        quiver.listsEqual(
            (board.makeSearchBoard()..canonicalize()).slotData.raw,
            scratch.slotData.raw));
    assert(disableDebug ||
        () {
          slotMap.fillRange(0, slotMap.length, -1);
          return true;
        }());
    for (int i = 0; i < slotMap.length; i++) {
      final realSlot = board.slotFromNumber(i);
      int canonicalized = -1;
      if (realSlot.isEmpty) {
        while (scratch.slotFromNumber(nextEmptySlot).isNotEmpty) {
          nextEmptySlot++;
        }
        canonicalized = scratch.slotFromNumber(nextEmptySlot++).slotNumber;
      } else {
        final Card top = realSlot.top;
        for (int j = 0; j < scratch.numSlots; j++) {
          final s = scratch.slotFromNumber(j);
          if (s.isNotEmpty && s.top == top) {
            canonicalized = j;
            break;
          }
        }
      }
      slotMap[canonicalized] = i;
    }
    assert(disableDebug || !slotMap.any((v) => v < 0));
    _takeNextStep(controller, auto);
  }

  /// The first time through, scratch is at the state state s0, then s1, etc.
  void _takeNextStep(GameController<ST> controller, bool auto) {
    nextStep--;
    if (_stopped || nextStep < 0) {
      assert(_stopped || controller.game.gameWon);
      waitForDone.complete(null);
      return;
    }
    final step = path[nextStep];
    scratch.slotData = step;
    final board = controller.game.board;
    final srcSlot = board.slotFromNumber(slotMap[step.viaSlotFrom]);
    final Card bottom = srcSlot.cardDownFromTop(step.viaNumCards - 1);
    final src = CardStack(srcSlot, step.viaNumCards, bottom);
    final dest = board.slotFromNumber(slotMap[step.viaSlotTo]);
    final move = Move(src: src, dest: dest, automatic: auto);
    // move.debugComment = 'Used at ${step.timeUsed}';
    assert(disableDebug || controller.inFlight == null);
    assert(disableDebug || board.canSelect(src));
    assert(disableDebug ||
        board.canDrop(
            FoundCard(srcSlot, step.viaNumCards, bottom, ui.Rect.zero), dest));
    controller.inFlight = GameAnimation<ST>(
        controller,
        [move],
        () => controller
            .doAutomaticMoves(() => _moveCompleted(controller, true)));
  }
}
