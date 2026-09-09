import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:fiveminutekanji/core/models/card_schedule.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/models/kanji_status.dart';
import 'package:fiveminutekanji/core/models/stroke_data.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/features/kanji_list/kanji_detail_screen.dart';
import 'package:fiveminutekanji/features/stroke_order/kanji_stroke_animation.dart';
import 'package:fiveminutekanji/repositories/progress_repository.dart';
import 'package:fiveminutekanji/repositories/stroke_data_repository.dart';
import 'package:fiveminutekanji/services/mark_as_known.dart';
import 'package:fiveminutekanji/services/srs_engine.dart';

import 'support/fakes.dart';

StrokeData loadFixture(String hex) {
  final raw = File('test/fixtures/strokes/$hex.json').readAsStringSync();
  return StrokeData.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  const card = KanjiCard(
    id: 'n5-001',
    character: '一',
    meaning: 'one',
    keyword: 'one',
    mnemonic: 'One horizontal stroke.',
    components: [],
    jlptLevel: JlptLevel.n5,
    onyomi: ['イチ'],
    kunyomi: ['ひと'],
  );

  Future<void> pumpDetail(
    WidgetTester tester, {
    required KanjiCard kanji,
    StrokeData? strokeData,
    KanjiProgressStatus status = KanjiProgressStatus.notEncountered,
    CardSchedule? schedule,
    ProgressRepository? progress,
  }) async {
    final repo = progress ?? MemoryProgressRepository();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProgressRepository>.value(value: repo),
          Provider<StrokeDataRepository>.value(
            value: MemoryStrokeDataRepository({
              kanji.character: ?strokeData,
            }),
          ),
          Provider<MarkAsKnownService>(
            create: (_) => MarkAsKnownService(
              progressRepository: repo,
              srsEngine: const SrsEngine(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: KanjiDetailScreen(
            card: kanji,
            status: status,
            schedule: schedule,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('detail uses stroke animation as the only kanji hero', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await pumpDetail(tester, kanji: card, strokeData: loadFixture('04e00'));

    expect(find.text('Kanji Detail'), findsOneWidget);
    expect(find.text('一'), findsNothing);
    expect(find.byType(KanjiStrokeAnimation), findsOneWidget);
    expect(find.text('Stroke Order'), findsOneWidget);
    expect(find.text('1 stroke'), findsOneWidget);

    final state = tester.state<KanjiStrokeAnimationState>(
      find.byType(KanjiStrokeAnimation),
    );
    expect(state.hasStrokeData, isTrue);
    expect(state.isPlaying, isFalse);
    expect(state.isComplete, isTrue);

    final hero = tester.getSize(find.byType(KanjiStrokeAnimation));
    expect(hero.height, greaterThan(190));
    expect(hero.height, lessThan(250));

    expect(find.text('MEANING'), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('ONE'), findsNothing);
    expect(find.text('READINGS'), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('イチ'), findsOneWidget);
    expect(find.text('Kun'), findsOneWidget);
    expect(find.text('ひと'), findsOneWidget);
    expect(find.text('STATUS'), findsOneWidget);
    expect(find.text('Not encountered'), findsOneWidget);
    expect(find.text('N5'), findsOneWidget);
    expect(find.text('MEMORY TIP'), findsOneWidget);
    expect(find.text('One horizontal stroke.'), findsOneWidget);
    expect(find.text('REVIEW STATS'), findsOneWidget);
    expect(find.text('Reviews'), findsOneWidget);
    expect(find.text('Mark as Known'), findsOneWidget);
  });

  testWidgets('detail replay starts the stroke animation from the beginning', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await pumpDetail(tester, kanji: card, strokeData: loadFixture('04e00'));

    final state = tester.state<KanjiStrokeAnimationState>(
      find.byType(KanjiStrokeAnimation),
    );
    expect(state.isComplete, isTrue);

    await tester.tap(find.text('Stroke Order'));
    await tester.pump();
    expect(state.isPlaying, isTrue);
    expect(state.isComplete, isFalse);
  });

  testWidgets('detail omits empty readings and keeps Mark as Known', (
    tester,
  ) async {
    usePhoneViewport(tester);
    const bare = KanjiCard(
      id: 'bare',
      character: '一',
      meaning: 'daylight',
      keyword: 'day',
      mnemonic: 'A sun through a window.',
      components: ['日'],
      jlptLevel: JlptLevel.none,
    );
    await pumpDetail(tester, kanji: bare, strokeData: loadFixture('04e00'));

    expect(find.text('Day'), findsOneWidget);
    expect(find.text('daylight'), findsOneWidget);
    expect(find.text('READINGS'), findsNothing);
    expect(find.text('On'), findsNothing);
    expect(find.text('N5'), findsNothing);
    expect(find.text('COMPONENTS'), findsOneWidget);
    expect(find.text('日'), findsOneWidget);
    expect(find.text('Mark as Known'), findsOneWidget);

    await tester.tap(find.text('Mark as Known'));
    await tester.pumpAndSettle();
    expect(find.text('Learning'), findsOneWidget);
    expect(find.text('Mark as Known'), findsNothing);
  });

  testWidgets('large text still scrolls the detail reference content', (
    tester,
  ) async {
    usePhoneViewport(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpDetail(tester, kanji: card, strokeData: loadFixture('04e00'));

    expect(find.text('MEANING'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    expect(find.text('REVIEW STATS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
