import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/theme/app_theme.dart';
import 'package:fiveminutekanji/features/learn/learn_kanji_body.dart';
import 'package:fiveminutekanji/repositories/stroke_data_repository.dart';
import 'package:fiveminutekanji/widgets/mnemonic_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const style = TextStyle(fontSize: 16, height: 1.4, color: Color(0xFF8A8478));

  Future<void> pumpMnemonic(
    WidgetTester tester, {
    required String mnemonic,
    required List<KanjiComponent> components,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: MnemonicText(
                mnemonic: mnemonic,
                components: components,
                style: style,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder linkText(String text) {
    return find.descendant(
      of: find.byType(MnemonicText),
      matching: find.text(text),
    );
  }

  testWidgets('renders a mnemonic with no components as plain text', (
    tester,
  ) async {
    await pumpMnemonic(
      tester,
      mnemonic: 'One horizontal stroke.',
      components: const [],
    );

    expect(find.text('One horizontal stroke.'), findsOneWidget);
    expect(find.byIcon(Icons.lightbulb_outline), findsNothing);
    expect(find.bySemanticsLabel('Show the person component'), findsNothing);
  });

  testWidgets('opens a component from its English phrase and dismisses it', (
    tester,
  ) async {
    await pumpMnemonic(
      tester,
      mnemonic: 'A person rests against a tree.',
      components: const [
        KanjiComponent(
          id: 'person',
          character: '亻',
          name: 'person',
          image: 'assets/components/person.png',
          mnemonicText: 'person',
        ),
        KanjiComponent(
          id: 'tree',
          character: '木',
          name: 'tree',
          image: 'assets/components/tree.png',
          mnemonicText: 'tree',
        ),
      ],
    );

    expect(find.text('A person rests against a tree.'), findsNothing);
    expect(linkText('person'), findsOneWidget);
    expect(linkText('tree'), findsOneWidget);
    final personStyle = tester.widget<Text>(linkText('person')).style!;
    expect(personStyle.fontWeight, FontWeight.w600);
    expect(personStyle.color, AppTheme.light.colorScheme.primary);
    expect(personStyle.decoration, TextDecoration.underline);
    expect(find.text('亻'), findsNothing);
    expect(find.byIcon(Icons.lightbulb_outline), findsNWidgets(2));
    expect(find.bySemanticsLabel('Show the person component'), findsOneWidget);

    await tester.tap(linkText('person'));
    await tester.pumpAndSettle();

    expect(find.text('亻'), findsOneWidget);
    expect(find.text('person'), findsNWidgets(2));

    await tester.tapAt(const Offset(300, 700));
    await tester.pumpAndSettle();

    expect(find.text('亻'), findsNothing);
    expect(linkText('person'), findsOneWidget);

    await tester.tap(linkText('tree'));
    await tester.pumpAndSettle();
    expect(find.text('木'), findsOneWidget);
    expect(find.text('亻'), findsNothing);

    await tester.tap(linkText('tree'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('木'), findsNothing);
  });

  testWidgets('links only the chosen occurrence of a repeated word', (
    tester,
  ) async {
    await pumpMnemonic(
      tester,
      mnemonic: 'A person sees another person.',
      components: const [
        KanjiComponent(
          id: 'person',
          character: '亻',
          name: 'person',
          mnemonicText: 'person',
        ),
      ],
    );

    expect(linkText('person'), findsOneWidget);
    expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
    expect(
      find.bySemanticsLabel('Memory aid: A person sees another person.'),
      findsOneWidget,
    );

    await tester.tap(linkText('person'));
    await tester.pumpAndSettle();
    expect(find.text('亻'), findsOneWidget);
  });

  testWidgets('shows the component name when the mnemonic word differs', (
    tester,
  ) async {
    await pumpMnemonic(
      tester,
      mnemonic: 'Trees where people mix.',
      components: const [
        KanjiComponent(
          id: 'tree',
          character: '木',
          name: 'tree',
          mnemonicText: 'Trees',
        ),
      ],
    );

    expect(linkText('Trees'), findsOneWidget);
    await tester.tap(linkText('Trees'));
    await tester.pumpAndSettle();

    expect(find.text('木'), findsOneWidget);
    expect(find.text('tree'), findsOneWidget);
    expect(find.text('Trees'), findsOneWidget);
  });

  testWidgets('learn card keeps the mnemonic in English and can expand it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const card = KanjiCard(
      id: 'n5-076',
      character: '休',
      meaning: 'rest',
      keyword: 'rest',
      mnemonic: 'A person rests against a tree.',
      structuredComponents: [
        KanjiComponent(
          id: 'person',
          character: '亻',
          name: 'person',
          image: 'assets/components/person.png',
          mnemonicText: 'person',
        ),
        KanjiComponent(
          id: 'tree',
          character: '木',
          name: 'tree',
          image: 'assets/components/tree.png',
          mnemonicText: 'tree',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Provider<StrokeDataRepository>.value(
            value: MemoryStrokeDataRepository(),
            child: const LearnKanjiBody(card: card),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('rest'), findsOneWidget);
    expect(find.text('A person rests against a tree.'), findsNothing);
    expect(find.text(card.componentsLabel), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MnemonicText),
        matching: find.text('person'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(MnemonicText),
        matching: find.text('person'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('亻'), findsWidgets);
    expect(find.text('rest'), findsOneWidget);
  });
}
