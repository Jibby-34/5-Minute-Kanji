import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/models/stroke_data.dart';
import '../repositories/stroke_data_repository.dart';

class AssetStrokeDataRepository implements StrokeDataRepository {
  AssetStrokeDataRepository({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  static const assetDirectory = 'assets/kanji/strokes';

  final AssetBundle _bundle;
  final Map<String, StrokeData?> _cache = {};
  final Map<String, Future<StrokeData?>> _inflight = {};

  static String unicodeHexFor(String character) {
    if (character.isEmpty) return '';
    return character.runes.first.toRadixString(16).padLeft(5, '0');
  }

  static String assetPathFor(String character) {
    return '$assetDirectory/${unicodeHexFor(character)}.json';
  }

  @override
  Future<StrokeData?> getForCharacter(String character) {
    if (character.isEmpty) return Future<StrokeData?>.value(null);
    if (_cache.containsKey(character)) {
      return Future<StrokeData?>.value(_cache[character]);
    }
    return _inflight.putIfAbsent(character, () => _load(character));
  }

  Future<StrokeData?> _load(String character) async {
    try {
      final raw = await _bundle.loadString(assetPathFor(character));
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('Stroke data JSON must be an object');
      }
      final data = StrokeData.fromJson(Map<String, dynamic>.from(decoded));
      if (data.strokes.isEmpty) {
        throw const FormatException('Stroke data has no strokes');
      }
      _cache[character] = data;
      return data;
    } catch (error) {
      debugPrint('Stroke data missing for $character: $error');
      _cache[character] = null;
      return null;
    } finally {
      _inflight.remove(character);
    }
  }
}
