import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/features/onboarding/welcome_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Tests do not download Google Fonts. Roboto is a similar width, so the
    // wrap and the scroll check reflect a real phone rather than the missing
    // font's one-em-per-letter fallback.
    await _loadRobotoAsSourceSans();
  });

  Future<SemanticsHandle> pumpWelcome(
    WidgetTester tester, {
    required Size size,
    EdgeInsets viewPadding = EdgeInsets.zero,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = FakeViewPadding(
      left: viewPadding.left,
      top: viewPadding.top,
      right: viewPadding.right,
      bottom: viewPadding.bottom,
    );
    tester.view.padding = FakeViewPadding(
      left: viewPadding.left,
      top: viewPadding.top,
      right: viewPadding.right,
      bottom: viewPadding.bottom,
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);

    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: WelcomeScreen(onGetStarted: () {}),
      ),
    );
    await tester.pumpAndSettle();
    return semantics;
  }

  void expectWelcomeCopy(WidgetTester tester) {
    expect(find.text('Kanji study that fits your day.'), findsOneWidget);
    expect(
      find.text(
        "Make the most of your time. We'll prioritize your reviews "
        'to fit the time you have.',
      ),
      findsOneWidget,
    );
    expect(find.text('YOUR 5-MINUTE PLAN'), findsOneWidget);
    expect(find.text('Example plan'), findsOneWidget);
    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('Priority reviews'), findsOneWidget);
    expect(find.text('3 min 10 sec'), findsOneWidget);
    expect(find.text('New kanji'), findsOneWidget);
    expect(find.text('1 min 50 sec'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('字'), findsNothing);
    expect(find.bySemanticsLabel('YOUR 5-MINUTE PLAN'), findsNothing);
    expect(
      find.bySemanticsLabel(
        'Example plan: 5 minutes. Priority reviews 3 minutes 10 seconds. '
        'New kanji 1 minute 50 seconds.',
      ),
      findsOneWidget,
    );
  }

  void expectButtonStaysPinned(WidgetTester tester) {
    expect(
      find.descendant(
        of: find.byType(Scrollable),
        matching: find.text('Get Started'),
      ),
      findsNothing,
    );
  }

  void expectPlanFitsAboveTheButton(WidgetTester tester) {
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, lessThan(1));
    expectButtonStaysPinned(tester);

    final plan = tester.getRect(find.text('New kanji'));
    final button = tester.getRect(find.text('Get Started'));
    expect(plan.bottom, lessThan(button.top));

    final primary = Theme.of(
      tester.element(find.text('5 min')),
    ).colorScheme.primary;
    const newKanji = Color(0xFF8E96C4);

    bool isFill(Widget widget, Color color) {
      if (widget is! DecoratedBox) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.color == color;
    }

    List<RenderBox> segments(Color color) {
      return tester
          .renderObjectList<RenderBox>(
            find.byWidgetPredicate((widget) => isFill(widget, color)),
          )
          .where((box) => (box.size.height - 12).abs() < 0.1)
          .toList();
    }

    final reviews = segments(primary);
    final fresh = segments(newKanji);
    expect(reviews, hasLength(1));
    expect(fresh, hasLength(1));
    expect(
      reviews.single.size.width / fresh.single.size.width,
      closeTo(190 / 110, 0.02),
    );
    final reviewsRight = reviews.single
        .localToGlobal(Offset(reviews.single.size.width, 0))
        .dx;
    final freshLeft = fresh.single.localToGlobal(Offset.zero).dx;
    expect(freshLeft - reviewsRight, closeTo(3, 0.5));

    final card = tester.getRect(
      find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final decoration = widget.decoration;
        return decoration is BoxDecoration &&
            decoration.color == const Color(0xFFFBF9F5);
      }),
    );
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(card.left, closeTo(28, 0.5));
    expect(card.right, closeTo(width - 28, 0.5));

    final subtitle = tester.getRect(
      find.textContaining('Make the most of your time'),
    );
    final viewport = tester.getRect(find.byType(Scrollable));
    final groupCenter = (card.top + subtitle.bottom) / 2;
    expect((groupCenter - viewport.center.dy).abs(), lessThan(12));
  }

  testWidgets('the example plan fits a phone without scrolling', (
    tester,
  ) async {
    final semantics = await pumpWelcome(tester, size: const Size(390, 844));
    try {
      expectWelcomeCopy(tester);
      expectPlanFitsAboveTheButton(tester);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('the example plan fits a small Android phone', (tester) async {
    final semantics = await pumpWelcome(
      tester,
      size: const Size(360, 640),
      viewPadding: const EdgeInsets.only(top: 24, bottom: 48),
    );
    try {
      expectWelcomeCopy(tester);
      expectPlanFitsAboveTheButton(tester);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('the example plan fits a very short phone', (tester) async {
    final semantics = await pumpWelcome(
      tester,
      size: const Size(320, 568),
      viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
    );
    try {
      expectWelcomeCopy(tester);
      expectButtonStaysPinned(tester);

      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      final button = tester.getRect(find.text('Get Started'));
      expect(
        tester.getRect(find.text('New kanji')).bottom,
        lessThan(button.top),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('large text scrolls instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            );
          },
          home: WelcomeScreen(onGetStarted: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Priority reviews'), findsOneWidget);
      expect(find.text('3 min 10 sec'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _loadRobotoAsSourceSans() async {
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final fonts = Directory(
    '${artifacts.path}${Platform.pathSeparator}material_fonts',
  );
  Future<void> load(String fileName, String family) async {
    final bytes = await File(
      '${fonts.path}${Platform.pathSeparator}$fileName',
    ).readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  await load('roboto-regular.ttf', 'SourceSans3_regular');
  await load('roboto-medium.ttf', 'SourceSans3_500');
  await load('roboto-medium.ttf', 'SourceSans3_600');
  await load('roboto-bold.ttf', 'SourceSans3_700');
  await load('roboto-regular.ttf', 'SourceSans3');
}
