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

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:aisleriot/graphics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:pedantic/pedantic.dart';
import 'package:url_launcher/url_launcher.dart';

import 'controller.dart';
import 'constants.dart';
import 'm/freecell.dart';

void main() async {
  // Get there first!
  LicenseRegistry.addLicense(Assets._getLicenses);

  WidgetsFlutterBinding.ensureInitialized();
  runApp(MainWindow(await Assets.getAssets(rootBundle)));
}

class Assets {
  final AssetBundle bundle;

  /// The jupiter image, used as an appliation icon
  final ScalableImage icon;

  final GamePainter initialPainter;
  final Deck initialDeck;

  List<Deck> decks;

  Assets._p(this.bundle, this.icon, this.initialPainter, this.initialDeck,
      List<Deck> decks)
      : decks = List.unmodifiable(decks);

  static Future<Assets> getAssets(AssetBundle b) async {
    final manifestS =
        await b.loadString('assets/cards/manifest.json', cache: false);
    final manifestU = jsonDecode(manifestS) as List<dynamic>;
    Deck? guyenne;
    final manifest = List<Deck>.generate(manifestU.length, (i) {
      final du = manifestU[i] as List<dynamic>;
      final d = Deck(du[0] as String, du[1] as String);
      if (d.assetKey == 'guyenne-classic.si') {
        guyenne = d;
      }
      return d;
    });
    final icon = await ScalableImage.fromSIAsset(
        rootBundle, 'assets/jupiter.si',
        currentColor: Colors.indigo.shade100);
    await icon.prepareImages(); // There aren't any, but it's totally harmless
    final deck = guyenne ?? manifest[0];
    final painter = await deck.makePainter(b);
    return Assets._p(b, icon, painter, deck, manifest);
  }

  static Stream<LicenseEntry> _getLicenses() async* {
    yield LicenseEntryWithLineBreaks(['jovial aisleriot'], LICENSE);
  }
}

class Deck {
  final String deckName;
  final String assetKey;

  Deck(this.deckName, this.assetKey);

  Future<GamePainter> makePainter(AssetBundle b) async =>
      GamePainter.create(b, 'assets/cards/$assetKey');
}

class MainWindow extends StatefulWidget {
  final Assets assets;

  MainWindow(Assets assets) : assets = assets;

  @override
  _MainWindowState createState() =>
      _MainWindowState(assets.initialDeck, assets.initialPainter);
}

class _MainWindowState extends State<MainWindow> {
  Deck lastDeckSelected;
  GamePainter painter;

  _MainWindowState(this.lastDeckSelected, this.painter);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Jovial Aisleriot',
        home: Material(
            // The Material widget is needed for text widgets to work:
            // https://stackoverflow.com/questions/47114639/yellow-lines-under-text-widgets-in-flutter
            type: MaterialType.transparency,
            child: Stack(
              children: [
                GameWidget(widget.assets, painter),
                Padding(
                    padding: EdgeInsets.fromLTRB(0, 5, 0, 0),
                    child: Align(
                        alignment: Alignment.topLeft,
                        child: ScalableImageWidget(
                            si: widget.assets.icon, scale: 0.08))),
                Align(alignment: Alignment.topRight, child: _buildMenu(context))
              ],
            )));
  }

  Widget _buildMenu(BuildContext context) => PopupMenuButton(
        icon: Icon(
          Icons.menu,
          color: Colors.indigo.shade100,
        ),
        onSelected: (void Function() action) => action(),
        itemBuilder: (BuildContext context) {
          return <PopupMenuEntry<void Function()>>[
            PopupMenuItem(
                value: () {},
                child: Row(
                  children: [
                    Text('Deck:  '),
                    DropdownButton(
                        value: lastDeckSelected,
                        // icon: const Icon(Icons.arrow_downward),
                        onChanged: (Deck? deck) => _changeDeck(context, deck),
                        items: widget.assets.decks
                            .map((v) => DropdownMenuItem(
                                value: v, child: Text(v.deckName)))
                            .toList())
                  ],
                )),
            PopupMenuItem(
                value: () {},
                child:
                    _HelpMenu('Help', widget.assets.icon, painter.paintTimes))
          ];
        },
      );

  void _changeDeck(BuildContext context, Deck? newDeck) {
    if (newDeck != null) {
      setState(() {
        lastDeckSelected = newDeck;
        unawaited(() async {
          final p = await newDeck.makePainter(widget.assets.bundle);
          setState(() {
            painter = p;
            // The old painter gets disposed down in GameState
          });
        }());
      });
    }
    Navigator.pop(context);
  }
}

class _HelpMenu extends StatelessWidget {
  final String title;
  final ScalableImage icon;
  final List<double> paintTimes;

  _HelpMenu(this.title, this.icon, this.paintTimes);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void Function()>(
      offset: const Offset(-100, 0),
      onSelected: (void Function() action) => action(),
      onCanceled: () {
        Navigator.pop(context);
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<void Function()>>[
        PopupMenuItem(
            value: () {
              Navigator.pop<void>(context, () {});
              unawaited(
                  showDialog(context: context, builder: _showNonWarranty));
            },
            child: Text('Non-warranty')),
        PopupMenuItem(
            value: () {
              Navigator.pop<void>(context, () {});
              launch(APPLICATION_ISSUE_ADDRESS);
            },
            child: Text('Submit Issue (Web)')),
        PopupMenuItem(
            value: () {
              Navigator.pop<void>(context, () {});
              unawaited(showDialog(
                  context: context,
                  builder: (c) => _showPerformance(c, paintTimes)));
            },
            child: Text('Performance Stats')),
        PopupMenuItem(
            value: () {
              Navigator.pop<void>(context, () {});
              showAboutDialog(
                  context: context,
                  applicationIcon: ScalableImageWidget(si: icon, scale: 0.1),
                  applicationName: 'Jovial Aisleriot',
                  applicationVersion: 'Version $APPLICATION_VERSION',
                  applicationLegalese: '© 2021 Bill Foote',
                  children: [
                    SizedBox(height: 40),
                    InkWell(
                        onTap: () => unawaited(launch(APPLICATION_WEB_ADDRESS)),
                        child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                                style: TextStyle(
                                    fontSize: 18,
                                    color: Theme.of(context).accentColor),
                                text: APPLICATION_WEB_ADDRESS)))
                  ]);
            },
            child: Text('About')),
      ],
      child: Row(
        children: [
          Text(title),
          const Spacer(),
          const Icon(Icons.arrow_right, size: 30.0),
        ],
      ),
    );
  }
}

Widget _showNonWarranty(BuildContext context) => AlertDialog(
        title: Text('Non-Warranty'),
        content: Text(NON_WARRANTY.replaceAll('\n', ' ')),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('OK'))
        ]);

Widget _showPerformance(BuildContext context, List<double> paintTimes) {
  final String histogram;
  if (paintTimes.isEmpty) {
    histogram = '';
  } else {
    paintTimes.sort();
    double smallestMS = double.infinity;
    double largestMS = double.negativeInfinity;
    for (double v in paintTimes) {
      v *= 1000; // ms
      smallestMS = min(smallestMS, v);
      largestMS = max(largestMS, v);
    }
    final int digits;
    if (smallestMS.roundToDouble() >= 10) {
      digits = 0;
    } else if ((smallestMS * 10).roundToDouble() >= 10) {
      digits = 1;
    } else {
      digits = 2;
    }
    if (smallestMS == largestMS) {
      histogram = smallestMS.toStringAsFixed(digits) + ' ms:  X';
    } else {
      int len = 0;
      final counts = Int32List(20);
      final double delta = (largestMS - smallestMS) / counts.length;
      String format(int i) => (smallestMS + i * delta).toStringAsFixed(digits);
      for (int i = 0; i <= counts.length; i++) {
        len = max(len, format(i).length);
      }
      for (double v in paintTimes) {
        v *= 1000; // ms
        int bin = ((v - smallestMS) / delta).floor();
        bin = min(bin, counts.length - 1);
        counts[bin]++;
      }
      final sb = StringBuffer();
      sb.write('  PAINT TIMES\n');
      sb.write('  ===========\n');
      for (int i = 0; i < counts.length; i++) {
        sb.write(format(i).padLeft(len));
        sb.write(' - ');
        sb.write(format(i + 1).padLeft(len));
        sb.write(' ms: ');
        sb.write(''.padLeft(counts[i], 'X'));
        sb.write('\n');
      }
      histogram = sb.toString();
    }
  }

  return AlertDialog(
      title: Text('Performance Information'),
      content: Column(children: [
        Text(GamePainter.loadMessages
            .fold(StringBuffer(),
                (StringBuffer buf, el) => buf..write(el)..write('\n'))
            .toString()),
        Text(histogram, style: const TextStyle(fontFamily: 'Courier New'))
      ]),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('OK'))
      ]);
}

class GameWidget extends StatefulWidget {
  final Assets assets;
  final GamePainter painter;

  GameWidget(this.assets, this.painter, {Key? key}) : super(key: key);

  @override
  GameState createState() => GameState(assets);
}

class GameState extends State<GameWidget> {
  GameController controller = GameController(Freecell());
  Assets assets;
  bool needsPaint = false;

  GameState(this.assets);

  @override
  void initState() {
    super.initState();
    controller.addListener(_appearanceChanged);
    controller.finder = CardFinder(widget.painter);
  }

  @override
  void dispose() {
    super.dispose();
    widget.painter.dispose();
    controller.removeListener(_appearanceChanged);
  }

  @override
  void didUpdateWidget(GameWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.painter != oldWidget.painter) {
      oldWidget.painter.dispose();
      controller.finder = CardFinder(widget.painter);
    }
  }

  void _appearanceChanged() => setState(() => needsPaint = true);

  @override
  Widget build(BuildContext context) {
    Size getSize() =>
        (context.findRenderObject() as RenderBox?)?.size ?? Size.zero;
    return GestureDetector(
        onTapDown: (e) => controller.clickStart(getSize(), e.localPosition),
        onTap: () => controller.click(),
        onDoubleTapDown: (e) =>
            controller.doubleClickStart(getSize(), e.localPosition),
        onDoubleTap: () => controller.doubleClick(),
        onPanStart: (e) => controller.dragStart(getSize(), e.localPosition),
        onPanUpdate: (e) => controller.dragMove(getSize(), e.localPosition),
        onPanCancel: () => controller.dragCancel(),
        onPanEnd: (e) => controller.dragEnd(),
        child: CustomPaint(
            size: Size.infinite,
            painter: _GameCustomPainter(this, widget.painter)));
  }
}

class _GameCustomPainter extends CustomPainter {
  final GameState state;
  final GamePainter painter;

  _GameCustomPainter(this.state, this.painter);

  @override
  void paint(Canvas canvas, Size size) {
    state.needsPaint = false;
    painter.paint(canvas, size, state.controller);
  }

  @override
  bool shouldRepaint(_GameCustomPainter oldDelegate) {
    return state.needsPaint ||
        state != oldDelegate.state ||
        painter != oldDelegate.painter;
  }
}