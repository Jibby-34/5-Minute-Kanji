enum ContentSource { rtk, anki, custom, premiumCourse }

enum ContentAccess { free, premium }

enum JlptLevel {
  n5,
  n4,
  n3,
  n2,
  n1,
  none;

  static const sectionOrder = [n5, n4, n3, n2, n1, none];

  String get sectionTitle => switch (this) {
    n5 => 'JLPT N5',
    n4 => 'JLPT N4',
    n3 => 'JLPT N3',
    n2 => 'JLPT N2',
    n1 => 'JLPT N1',
    none => 'No JLPT Level',
  };
}

/// A visual building block of a kanji, optionally tied to the mnemonic.
///
/// [mnemonicText] is the English word or phrase in the card mnemonic that
/// refers to this component. It is matched exactly, aside from case.
/// [occurrence] selects which match to use when that phrase appears more
/// than once, starting at 0. Leave [mnemonicText] null to keep the component
/// out of the mnemonic.
class KanjiComponent {
  const KanjiComponent({
    required this.id,
    required this.character,
    required this.name,
    this.image,
    this.mnemonicText,
    this.occurrence = 0,
  });

  final String id;
  final String character;
  final String name;

  /// Asset path for a component illustration. A missing file falls back to
  /// [character].
  final String? image;

  final String? mnemonicText;
  final int occurrence;

  String get label => '$character — $name';
}

/// A single kanji study card. Content-agnostic: RTK, Anki, JLPT, or custom later.
class KanjiCard {
  const KanjiCard({
    required this.id,
    required this.character,
    required this.meaning,
    required this.keyword,
    required this.mnemonic,
    required this.components,
    this.strokeCount = 0,
    this.jlptLevel = JlptLevel.none,
    this.rtkIndex,
    this.onyomi = const [],
    this.kunyomi = const [],
    this.vocabulary = const [],
    this.source = ContentSource.rtk,
    this.sourceDeckId,
    this.access = ContentAccess.free,
  });

  final String id;
  final String character;
  final String meaning;
  final String keyword;
  final String mnemonic;
  final List<KanjiComponent> components;
  final int strokeCount;
  final JlptLevel jlptLevel;
  final int? rtkIndex;
  final List<String> onyomi;
  final List<String> kunyomi;
  final List<String> vocabulary;
  final ContentSource source;
  final String? sourceDeckId;
  final ContentAccess access;

  String get componentsLabel =>
      components.map((component) => component.label).join(' + ');

  /// Whether the components line adds information beyond the character itself.
  bool get hasComponentBreakdown =>
      components.length > 1 ||
      (components.length == 1 && components.single.label != character);

  String get onyomiLabel => onyomi.join('・');

  String get kunyomiLabel => kunyomi.join('・');

  bool get hasReadings => onyomi.isNotEmpty || kunyomi.isNotEmpty;
}
