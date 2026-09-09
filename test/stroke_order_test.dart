import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/stroke_data.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/core/utils/parsed_stroke_geometry.dart';
import 'package:fiveminutekanji/core/utils/svg_path_parser.dart';
import 'package:fiveminutekanji/data/asset_stroke_data_repository.dart';
import 'package:fiveminutekanji/features/learn/learn_kanji_body.dart';
import 'package:fiveminutekanji/features/stroke_order/kanji_stroke_animation.dart';
import 'package:fiveminutekanji/features/stroke_order/stroke_order_timeline.dart';
import 'package:fiveminutekanji/repositories/stroke_data_repository.dart';

StrokeData loadFixture(String hex) {
  final raw = File('test/fixtures/strokes/$hex.json').readAsStringSync();
  return StrokeData.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('SvgPathParser', () {
    const parser = SvgPathParser();

    test('parses a KanjiVG cubic stroke', () {
      const d =
          'M11,54.25c3.19,0.62,6.25,0.75,9.73,0.5c20.64-1.5,50.39-5.12,68.58-5.24';
      final path = parser.parse(d);
      expect(path.computeMetrics().isEmpty, isFalse);
      expect(ParsedStrokeGeometry.totalLength(path), greaterThan(10));
    });

    test('handles smooth cubic continuation', () {
      final path = parser.parse('M0,0 C0,10 10,10 10,0 S20,-10 20,0');
      expect(ParsedStrokeGeometry.totalLength(path), greaterThan(1));
    });

    test('throws on unsupported commands', () {
      expect(() => parser.parse('M0,0 A5,5 0 0 1 10,0'), throwsFormatException);
    });
  });

  group('StrokeData parsing', () {
    test('loads 一 with one stroke in order', () {
      final data = loadFixture('04e00');
      expect(data.character, '一');
      expect(data.unicodeHex, '04e00');
      expect(data.strokeCount, 1);
      expect(data.strokes.first.pathData, startsWith('M11,54.25'));
      expect(data.strokes.first.numberPosition, isNotNull);
    });

    test('loads 日 with four ordered strokes', () {
      final data = loadFixture('065e5');
      expect(data.character, '日');
      expect(data.strokeCount, 4);
      expect(data.strokes[0].pathData, startsWith('M31.5,24.5'));
      expect(data.strokes[1].pathData, startsWith('M33.48,26'));
      expect(data.strokes[2].pathData, startsWith('M34.22,55.25'));
      expect(data.strokes[3].pathData, startsWith('M34.23,86.5'));
    });
  });

  group('AssetStrokeDataRepository', () {
    test('loads stroke data for a known kanji', () async {
      final ichi = File('test/fixtures/strokes/04e00.json').readAsStringSync();
      final repo = AssetStrokeDataRepository(
        bundle: _MemoryAssetBundle({
          AssetStrokeDataRepository.assetPathFor('一'): ichi,
        }),
      );

      final data = await repo.getForCharacter('一');
      expect(data, isNotNull);
      expect(data!.strokeCount, 1);
      expect(data.character, '一');
      expect(await repo.getForCharacter('一'), same(data));
    });

    test('returns null for missing stroke data', () async {
      final repo = AssetStrokeDataRepository(bundle: _MemoryAssetBundle({}));
      expect(await repo.getForCharacter('一'), isNull);
      expect(await repo.getForCharacter(''), isNull);
    });

    test('returns null for corrupt JSON', () async {
      final repo = AssetStrokeDataRepository(
        bundle: _MemoryAssetBundle({
          AssetStrokeDataRepository.assetPathFor('一'): '{not json',
        }),
      );
      expect(await repo.getForCharacter('一'), isNull);
    });
  });

  group('MemoryStrokeDataRepository', () {
    test('returns null when the kanji is absent', () async {
      final repo = MemoryStrokeDataRepository();
      expect(await repo.getForCharacter('日'), isNull);
    });
  });

  group('StrokeOrderTimeline', () {
    test('draws strokes in order then holds the complete glyph', () {
      final geometry = ParsedStrokeGeometry.fromStrokeData(
        loadFixture('065e5'),
      );
      final timeline = StrokeOrderTimeline.from(geometry);
      expect(timeline.strokeDurations, hasLength(4));

      final start = timeline.at(0);
      expect(start.completedCount, 0);
      expect(start.activeIndex, 0);

      final mid = timeline.at(0.35);
      expect(mid.activeIndex ?? mid.completedCount, inInclusiveRange(0, 3));

      final end = timeline.at(1);
      expect(end.completedCount, 4);
      expect(end.activeIndex, isNull);
      expect(end.numberIndex, isNull);
    });
  });

  group('KanjiStrokeAnimation', () {
    testWidgets('renders and replays stroke order', (tester) async {
      final data = loadFixture('04e00');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Provider<StrokeDataRepository>.value(
              value: MemoryStrokeDataRepository({'一': data}),
              child: const KanjiStrokeAnimation(
                character: '一',
                autoPlay: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Stroke Order'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      final state = tester.state<KanjiStrokeAnimationState>(
        find.byType(KanjiStrokeAnimation),
      );
      expect(state.hasStrokeData, isTrue);
      expect(state.isPlaying, isFalse);

      await tester.tap(find.text('Stroke Order'));
      await tester.pump();
      expect(state.isPlaying, isTrue);

      await tester.tap(find.text('Stroke Order'));
      await tester.pump();
      expect(state.isPlaying, isTrue);
      expect(state.hasStrokeData, isTrue);
    });

    testWidgets('hides itself when stroke data is missing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Provider<StrokeDataRepository>.value(
              value: MemoryStrokeDataRepository(),
              child: const KanjiStrokeAnimation(character: '一'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Stroke Order'), findsNothing);
      expect(find.byType(KanjiStrokeAnimation), findsOneWidget);
      expect(tester.getSize(find.byType(KanjiStrokeAnimation)), Size.zero);
    });

    testWidgets('unframed animation replays without a card chrome', (
      tester,
    ) async {
      final data = loadFixture('04e00');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Provider<StrokeDataRepository>.value(
              value: MemoryStrokeDataRepository({'一': data}),
              child: const KanjiStrokeAnimation(
                character: '一',
                autoPlay: false,
                showFrame: false,
                showStrokeNumbers: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Stroke Order'), findsOneWidget);
      expect(find.text('一'), findsNothing);

      final state = tester.state<KanjiStrokeAnimationState>(
        find.byType(KanjiStrokeAnimation),
      );
      await tester.tap(find.text('Stroke Order'));
      await tester.pump();
      expect(state.isPlaying, isTrue);
    });

    testWidgets('startCompleted shows the finished glyph without playing', (
      tester,
    ) async {
      final data = loadFixture('04e00');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Provider<StrokeDataRepository>.value(
              value: MemoryStrokeDataRepository({'一': data}),
              child: const KanjiStrokeAnimation(
                character: '一',
                autoPlay: false,
                startCompleted: true,
                showFrame: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final state = tester.state<KanjiStrokeAnimationState>(
        find.byType(KanjiStrokeAnimation),
      );
      expect(state.hasStrokeData, isTrue);
      expect(state.isPlaying, isFalse);
      expect(state.isComplete, isTrue);

      await tester.tap(find.text('Stroke Order'));
      await tester.pump();
      expect(state.isPlaying, isTrue);
      expect(state.isComplete, isFalse);
    });

    testWidgets('fallback character is shown when stroke data is missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Provider<StrokeDataRepository>.value(
              value: MemoryStrokeDataRepository(),
              child: const KanjiStrokeAnimation(
                character: '一',
                showFallbackCharacter: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('一'), findsOneWidget);
      expect(find.text('Stroke Order'), findsNothing);
    });
  });

  group('LearnKanjiBody stroke presentation', () {
    const card = KanjiCard(
      id: 'ichi',
      character: '一',
      meaning: 'one',
      keyword: 'One',
      mnemonic: 'A single horizontal stroke.',
      components: [],
      onyomi: ['イチ'],
      kunyomi: ['ひと'],
    );

    testWidgets('uses the animation as the only large kanji', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final data = loadFixture('04e00');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Provider<StrokeDataRepository>.value(
              value: MemoryStrokeDataRepository({'一': data}),
              child: const LearnKanjiBody(card: card),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('一'), findsNothing);
      expect(find.text('Stroke Order'), findsOneWidget);
      expect(find.text('MEANING'), findsOneWidget);
      expect(find.text('One'), findsOneWidget);
      expect(find.text('READINGS'), findsOneWidget);
      expect(find.text('A single horizontal stroke.'), findsOneWidget);
      expect(find.byType(KanjiStrokeAnimation), findsOneWidget);

      final animationSize = tester.getSize(find.byType(KanjiStrokeAnimation));
      expect(animationSize.height, greaterThan(150));
      expect(animationSize.height, lessThan(230));
    });
  });
}

class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this._assets);

  final Map<String, String> _assets;

  @override
  Future<ByteData> load(String key) async {
    final source = _assets[key];
    if (source == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    final bytes = Uint8List.fromList(utf8.encode(source));
    return ByteData.view(bytes.buffer);
  }
}
