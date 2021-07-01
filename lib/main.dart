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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'controller.dart';
import 'constants.dart';
import 'm/freecell.dart';

void main() async {
  // Get there first!
  LicenseRegistry.addLicense(Assets._getLicenses);

  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.read();
  runApp(MainWindow(await Assets.getAssets(rootBundle, settings), settings));
}

class Settings {
  String deckAsset = 'guyenne-classic.si';
  bool cacheCardImages = true;
  static Color foregroundColor = Colors.indigo.shade50;

  static Future<Settings> read() async {
    final storage = await SharedPreferences.getInstance();
    String? js = storage.getString('settings');
    final r = Settings();
    if (js != null) {
      try {
        r.decodeJson(json.decode(js) as Map<String, dynamic>);
      } catch (e) {
        print(e);
      }
    }
    return r;
  }

  Future<void> write() async {
    final storage = await SharedPreferences.getInstance();
    String js = json.encode(toJson());
    await storage.setString('settings', js);
  }

  ///
  /// Convert to a data structure that can be serialized as JSON.
  ///
  Map<String, dynamic> toJson() => <String, dynamic>{
        'cacheCardImages': cacheCardImages,
        'deckAsset': deckAsset
      };

  ///
  /// Convert from a data structure that comes from JSON
  ///
  void decodeJson(Map<String, dynamic> json) {
    cacheCardImages = (json['cacheCardImages'] as bool?) ?? cacheCardImages;
    deckAsset = (json['deckAsset'] as String?) ?? deckAsset;
  }
}

class Assets {
  final AssetBundle bundle;

  /// The jupiter image, used as an application icon
  final ScalableImage icon;

  final Deck initialDeck;

  List<Deck> decks;

  Assets._p(this.bundle, this.icon, this.initialDeck, List<Deck> decks)
      : decks = List.unmodifiable(decks);

  static Future<Assets> getAssets(AssetBundle b, Settings s) async {
    final manifestS =
        await b.loadString('assets/cards/manifest.json', cache: false);
    final manifestU = jsonDecode(manifestS) as List<dynamic>;
    Deck? first;
    final manifest = List<Deck>.generate(manifestU.length, (i) {
      final du = manifestU[i] as List<dynamic>;
      final d = Deck(du[0] as String, du[1] as String);
      if (d.assetKey == s.deckAsset) {
        first = d;
      }
      return d;
    });
    final icon = await ScalableImage.fromSIAsset(
        rootBundle, 'assets/jupiter.si',
        currentColor: Settings.foregroundColor);
    await icon.prepareImages(); // There aren't any, but it's totally harmless
    final deck = first ?? manifest[0];
    return Assets._p(b, icon, deck, manifest);
  }

  static Stream<LicenseEntry> _getLicenses() async* {
    yield LicenseEntryWithLineBreaks(['jovial aisleriot'], LICENSE);
  }
}

class Deck {
  final String deckName;
  final String assetKey;

  Deck(this.deckName, this.assetKey);

  Future<GamePainter> makePainter(AssetBundle b,
          {required bool cacheCards}) async =>
      GamePainter.create(b, 'assets/cards/$assetKey', cacheCards: cacheCards);
}

class MainWindow extends StatefulWidget {
  final Assets assets;
  final Settings initialSettings;

  MainWindow(Assets assets, this.initialSettings) : assets = assets;

  @override
  _MainWindowState createState() =>
      _MainWindowState(assets.initialDeck, initialSettings);
}

class _MainWindowState extends State<MainWindow> {
  Deck lastDeckSelected;
  GamePainter? painter;
  Settings settings;
  bool _first = true;
  GameController controller = Freecell().makeController();

  _MainWindowState(this.lastDeckSelected, this.settings);

  @override
  Widget build(BuildContext context) {
    if (_first) {
      _first = false;
      unawaited(() async {
        final cc = settings.cacheCardImages;
        await Future<void>.delayed(Duration(milliseconds: 40));
        GamePainter p = await lastDeckSelected.makePainter(widget.assets.bundle,
            cacheCards: cc);
        if (settings.cacheCardImages != cc) {
          final p2 = p.withNewCacheCards(settings.cacheCardImages);
          p.dispose();
          p = p2;
        }
        ;
        setState(() {
          painter = p;
        });
      }());
    }
    final p = painter;
    return MaterialApp(
        title: 'Jovial Aisleriot',
        theme: Theme.of(context).copyWith(
          elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
            primary: Colors.indigo.shade400,
            onSurface: Colors.white,
          )),
        ),
        home: Material(
            // The Material widget is needed for text widgets to work:
            // https://stackoverflow.com/questions/47114639/yellow-lines-under-text-widgets-in-flutter
            type: MaterialType.transparency,
            child: LayoutBuilder(builder: (context, BoxConstraints bc) {
              final short = bc.hasBoundedHeight &&
                  bc.hasBoundedWidth &&
                  bc.maxHeight * 1.5 < bc.maxWidth;
              return Stack(
                children: [
                  Padding(
                    padding: short
                        ? const EdgeInsets.fromLTRB(120, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 60, 0, 0),
                    child: (p != null)
                        ? GameWidget(widget.assets, controller, p)
                        : Container(
                            color: GamePainter.background,
                          ),
                  ),
                  short
                      ? ButtonArea(
                          state: this, width: 120, maxHeight: bc.maxHeight)
                      : ButtonArea(
                          state: this, height: 60, maxWidth: bc.maxWidth),
                  Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                          padding: EdgeInsets.fromLTRB(0, 8, 8, 0),
                          child: _buildMenu(context))),
                  Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                          padding: EdgeInsets.fromLTRB(5, 10, 0, 0),
                          child: ScalableImageWidget(
                              si: widget.assets.icon, scale: 0.08))),
                ],
              );
            })));
  }

  Widget _buildMenu(BuildContext context) => PopupMenuButton(
        icon: Icon(
          Icons.menu,
          color: Colors.indigo.shade50,
        ),
        onSelected: (void Function() action) => action(),
        itemBuilder: (BuildContext context) {
          return <PopupMenuEntry<void Function()>>[
            PopupMenuItem(value: () {}, child: _saveMenu(context)),
            PopupMenuItem(
                enabled: true,
                value: () {},
                child: Row(children: [Icon(Icons.arrow_back), Text(' Undo')])),
            PopupMenuItem(
                enabled: true,
                value: () => controller.solve(),
                child: Text(r'¯\_(ツ)_/¯  Solve')),
            PopupMenuItem(
                enabled: true,
                value: () {},
                child:
                    Row(children: [Icon(Icons.arrow_forward), Text(' Redo')])),
            PopupMenuItem(enabled: true, value: () {}, child: Text('New Game')),
            PopupMenuItem(value: () {}, child: _settingsMenu(context)),
            PopupMenuItem(
                value: () {},
                child:
                    _HelpMenu('Help', widget.assets.icon, painter?.paintTimes))
          ];
        },
      );

  PopupMenuButton _saveMenu(BuildContext context) =>
      PopupMenuButton<void Function()>(
        offset: const Offset(-100, 0),
        onSelected: (void Function() action) => action(),
        onCanceled: () => Navigator.pop(context),
        itemBuilder: (BuildContext context) => [
          PopupMenuItem(
              value: () {
                final ext = controller.game.board.toExternal();
                Clipboard.setData(ClipboardData(text: ext));
                Navigator.pop(context);
              },
              child: Text('Copy game to clipboard')),
          PopupMenuItem(
              value: () {
                unawaited(() async {
                  final String? cd;
                  try {
                    cd = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
                    if (cd == null || cd == '') {
                      return showErrorDialog(context, 'Empty clipboard', null);
                    }
                    controller.game.board.setFromExternal(cd);
                    controller.notifyListeners();
                  } catch (e, s) {
                    print(e);
                    print(s);
                    return showErrorDialog(context, 'Clipboard error', e);
                  }
                }());
                Navigator.pop(context);
              },
              child: Text('Paste game from clipboard')),
        ],
        child: Row(
          children: [
            Text('Save / Restore'),
            const Spacer(),
            const Icon(Icons.arrow_right, size: 30.0),
          ],
        ),
      );

  PopupMenuButton _settingsMenu(BuildContext context) =>
      PopupMenuButton<void Function()>(
        offset: const Offset(-100, 0),
        onSelected: (void Function() action) => action(),
        onCanceled: () => Navigator.pop(context),
        itemBuilder: (BuildContext context) => [
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
                          .toList()),
                ],
              )),
          CheckedPopupMenuItem(
              checked: settings.cacheCardImages,
              value: () => _changeCacheCardImages(context),
              child: const Text('Cache Card Images')),
          CheckedPopupMenuItem(
              checked: true,
              value: () => null,
              child: const Text('Automatic Play')),
        ],
        child: Row(
          children: [
            Text('Settings'),
            const Spacer(),
            const Icon(Icons.arrow_right, size: 30.0),
          ],
        ),
      );

  void _changeCacheCardImages(BuildContext context) {
    setState(() {
      settings.cacheCardImages = !settings.cacheCardImages;
      unawaited(settings.write());
      painter = painter?.withNewCacheCards(settings.cacheCardImages);
    });
    Navigator.pop(context);
  }

  void _changeDeck(BuildContext context, Deck? newDeck) {
    if (newDeck != null) {
      setState(() {
        lastDeckSelected = newDeck;
        settings.deckAsset = newDeck.assetKey;
        unawaited(() async {
          await settings.write();
          // A slight delay so Flutter has a chance to at least start
          // dismissing the dropdown on slow platforms.  I miss having
          // thread priorities :-)
          await Future<void>.delayed(Duration(milliseconds: 50));
          final p = await newDeck.makePainter(widget.assets.bundle,
              cacheCards: settings.cacheCardImages);
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

class ButtonArea extends StatelessWidget {
  final _MainWindowState state;
  final double? height;
  final double? width;
  final double? maxWidth;
  final double? maxHeight;

  ButtonArea(
      {Key? key,
      required this.state,
      this.height,
      this.width,
      this.maxWidth,
      this.maxHeight})
      : super(key: key) {
    assert(height != null || width != null);
  }

  bool get isHorizontal => height != null;
  static final TextStyle _style = TextStyle(
      fontSize: 18, fontFamily: 'Helvetica', color: Settings.foregroundColor);

  @override
  Widget build(BuildContext context) {
    if (width != null) {
      final h = maxHeight ?? 10000.0;
      return Container(
          height: 5000,
          width: width,
          color: Color(0xff00270a),
          child: Padding(
              padding: EdgeInsets.fromLTRB(8, 60, 0, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...(h > 270
                        ? [
                            SizedBox(height: 45),
                            Center(
                                child: Padding(
                                    padding: EdgeInsets.fromLTRB(0, 0, 8, 0),
                                    child: ElevatedButton(
                                      onPressed: () {},
                                      child: Text(
                                        'New Game',
                                      ), // color: Settings.foregroundColor),
                                    ))),
                            SizedBox(height: 45),
                          ]
                        : []),
                    Text(' Wins:', style: _style, textAlign: TextAlign.left),
                    Text('   99999', style: _style, textAlign: TextAlign.left),
                    Text(' ', style: _style),
                    Text(' Losses:', style: _style),
                    Text('   0', style: _style),
                    ...(h > 385
                        ? [
                            SizedBox(height: 35),
                            Row(children: [
                              Padding(
                                  padding: EdgeInsets.fromLTRB(5, 0, 0, 0),
                                  child: SizedBox(
                                      width: 40,
                                      child: ElevatedButton(
                                        onPressed: () {},
                                        child: Icon(
                                          Icons.arrow_back,
                                        ), // color: Settings.foregroundColor),
                                      ))),
                              Padding(
                                  padding: EdgeInsets.fromLTRB(15, 0, 0, 0),
                                  child: SizedBox(
                                      width: 40,
                                      child: ElevatedButton(
                                        onPressed: () {},
                                        child: Icon(
                                          Icons.arrow_forward,
                                        ), // color: Settings.foregroundColor),
                                      ))),
                            ]),
                            SizedBox(height: 20),
                            Padding(
                                padding: EdgeInsets.fromLTRB(15, 0, 0, 0),
                                child: SizedBox(
                                    width: 70,
                                    child: ElevatedButton(
                                        onPressed: () =>
                                            state.controller.solve(),
                                        child: Text(r'¯\_(ツ)_/¯',
                                            style: TextStyle(fontSize: 10))))),
                          ]
                        : []),
                  ])));
    } else if (height != null) {
      final w = maxWidth ?? 10000.0;
      return Container(
          height: height!,
          width: 50000,
          color: Color(0xff00270a),
          child: Center(
              child: Row(children: [
            SizedBox(width: 45),
            Spacer(),
            ...(w > 630
                ? [
                    ElevatedButton(
                        onPressed: () {},
                        child: Text(
                          'New Game',
                        )), // color: Settings.foregroundColor),
                    Spacer(),
                  ]
                : []),
            SizedBox(
              width: 250,
              child: Center(
                  child: Text('Wins:  99999   Losses: 0', style: _style)),
            ),
            Spacer(),
            ...(w > 510
                ? [
                    Padding(
                        padding: EdgeInsets.fromLTRB(0, 0, 0, 0),
                        child: SizedBox(
                            width: 40,
                            child: ElevatedButton(
                              onPressed: () {},
                              child: Icon(
                                Icons.arrow_back,
                              ), // color: Settings.foregroundColor),
                            ))),
                    Padding(
                        padding: EdgeInsets.fromLTRB(15, 0, 0, 0),
                        child: SizedBox(
                            width: 60,
                            child: ElevatedButton(
                                onPressed: () => state.controller.solve(),
                                child: Text(r'¯\_(ツ)_/¯',
                                    style: TextStyle(fontSize: 9))))),
                    Padding(
                        padding: EdgeInsets.fromLTRB(15, 0, 0, 0),
                        child: SizedBox(
                            width: 40,
                            child: ElevatedButton(
                              onPressed: null,
                              child: Icon(
                                Icons.arrow_forward,
                              ), // color: Settings.foregroundColor),
                            ))),
                  ]
                : []),
            Spacer(),
            SizedBox(width: 40)
          ])));
    } else {
      throw 'Internal error';
    }
  }
}

class _HelpMenu extends StatelessWidget {
  final String title;
  final ScalableImage icon;
  final List<double>? paintTimes;

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

Widget _showPerformance(BuildContext context, List<double>? paintTimes) {
  final String histogram;
  if (paintTimes == null || paintTimes.isEmpty) {
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
  final GameController controller;

  GameWidget(this.assets, this.controller, this.painter, {Key? key})
      : super(key: key);

  @override
  GameState createState() => GameState(assets, controller);
}

class GameState extends State<GameWidget> {
  final GameController controller;
  final Assets assets;
  bool needsPaint = false;

  GameState(this.assets, this.controller);

  @override
  void initState() {
    super.initState();
    controller.addListener(_appearanceChanged);
    controller.painter = widget.painter;
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
      controller.painter = widget.painter;
    }
  }

  void _appearanceChanged() => setState(() => needsPaint = true);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTapDown: (e) => controller.clickStart(e.localPosition),
        onTap: () => controller.click(),
        onDoubleTapDown: (e) => controller.doubleClickStart(e.localPosition),
        onDoubleTap: () => controller.doubleClick(),
        onPanStart: (e) => controller.dragStart(e.localPosition),
        onPanUpdate: (e) => controller.dragMove(e.localPosition),
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


Future<void> showErrorDialog(
    BuildContext context, String message, Object? exception) =>
    showDialog(
        context: context,
        builder: (BuildContext context) => ErrorDialog(message, exception));

class ErrorDialog extends StatelessWidget {
  final String message;
  final Object? exception;

  ErrorDialog(this.message, this.exception);

  @override
  Widget build(BuildContext context) {
    String exs = '';
    if (exception != null) {
      exs = 'Error';
      try {
        exs = exception.toString();
      } catch (ex) {
        print('Error in exception.toString()');
      }
    }
    // return object of type Dialog
    return AlertDialog(
      title: Text(message),
      content: (exception == null)
          ? Text('')
          : SingleChildScrollView(
        child: Column(children: [
          SizedBox(height: 20),
          Text(exs),
        ]),
      ),
      actions: <Widget>[
        // usually buttons at the bottom of the dialog
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text('OK'),
        )
      ],
    );
  }
}
