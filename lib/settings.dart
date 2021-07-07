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
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';


class Settings {
  String deckAsset = 'guyenne-classic.si';
  bool automaticPlay = false;   // Not saved
  bool cacheCardImages = true;
  int wins = 0;
  int losses = 0;
  final statistics = <String, GameStatistics>{};
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
    'deckAsset': deckAsset,
    'statistics': statistics
  };

  ///
  /// Convert from a data structure that comes from JSON
  ///
  void decodeJson(Map<String, dynamic> json) {
    cacheCardImages = (json['cacheCardImages'] as bool?) ?? cacheCardImages;
    deckAsset = (json['deckAsset'] as String?) ?? deckAsset;
    final statisticsJ = (json['statistics'] as Map<String, dynamic>?);
    if (statisticsJ != null) {
      for (final e in statisticsJ.entries) {
        statistics[e.key] = GameStatistics()
          ..decodeJson(e.value as Map<String, dynamic>);
      }
    }
  }
}
