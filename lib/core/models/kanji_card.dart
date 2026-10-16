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

  /// Reads a catalog label such as `木 — tree`.
  factory KanjiComponent.fromLabel(String label) {
    final parts = label.split(' — ');
    if (parts.length < 2) {
      final text = label.trim();
      return KanjiComponent(
        id: text,
        character: text,
        name: text,
        mnemonicText: text,
      );
    }
    final character = parts.first.trim();
    final name = parts.sublist(1).join(' — ').trim();
    return KanjiComponent(
      id: label,
      character: character,
      name: name,
      mnemonicText: name,
    );
  }
}

/// A common Japanese word that uses a kanji.
///
/// [word] is the written form, [reading] is the full hiragana pronunciation,
/// and [meaning] is a short English definition. Cards with no vocabulary leave
/// [KanjiCard.commonWords] empty.
class CommonWord {
  const CommonWord({
    required this.word,
    required this.reading,
    required this.meaning,
  });

  final String word;
  final String reading;
  final String meaning;

  /// True when every field is missing or only whitespace.
  bool get isBlank =>
      word.trim().isEmpty && reading.trim().isEmpty && meaning.trim().isEmpty;
}

/// A single kanji study card. Content-agnostic: RTK, Anki, JLPT, or custom later.
class KanjiCard {
  const KanjiCard({
    required this.id,
    required this.character,
    required this.meaning,
    required this.keyword,
    required this.mnemonic,
    this.components = const [],
    this.structuredComponents = const [],
    this.strokeCount = 0,
    this.jlptLevel = JlptLevel.none,
    this.rtkIndex,
    this.onyomi = const [],
    this.kunyomi = const [],
    this.vocabulary = const [],
    this.commonWords = const [],
    this.source = ContentSource.rtk,
    this.sourceDeckId,
    this.access = ContentAccess.free,
    this.difficulty = 0,
    this.frequency = 0,
  });

  final String id;
  final String character;
  final String meaning;
  final String keyword;
  final String mnemonic;

  /// Catalog labels, `character — name`. Empty when [structuredComponents]
  /// carries the richer form used by tests and hand-built cards.
  final List<String> components;

  final List<KanjiComponent> structuredComponents;
  final int strokeCount;
  final JlptLevel jlptLevel;
  final int? rtkIndex;
  final List<String> onyomi;
  final List<String> kunyomi;
  final List<String> vocabulary;

  /// Everyday words that use this kanji. Empty when the dataset has none.
  final List<CommonWord> commonWords;
  final ContentSource source;
  final String? sourceDeckId;
  final ContentAccess access;

  /// Relative difficulty from 1 (easiest) to 100 (hardest).
  ///
  /// 0 means this card has no placement difficulty. Several kanji can share
  /// the same value; it is not an id.
  final int difficulty;

  /// Corpus frequency rank. Lower means the kanji is more common.
  ///
  /// 0 means this card has no frequency rank. The value is metadata, not a
  /// curriculum priority score.
  final int frequency;

  /// Components the mnemonic and detail screens can draw.
  List<KanjiComponent> get componentModels {
    if (structuredComponents.isNotEmpty) return structuredComponents;
    return [for (final label in components) KanjiComponent.fromLabel(label)];
  }

  String get componentsLabel => componentModels.isEmpty
      ? ''
      : componentModels.map((component) => component.label).join(' + ');

  /// Whether the components line adds information beyond the character itself.
  bool get hasComponentBreakdown {
    final models = componentModels;
    return models.length > 1 ||
        (models.length == 1 && models.single.label != character);
  }

  String get onyomiLabel => onyomi.join('・');

  String get kunyomiLabel => kunyomi.join('・');

  bool get hasReadings => onyomi.isNotEmpty || kunyomi.isNotEmpty;

  /// Whether [commonWords] has at least one word with visible text.
  bool get hasCommonWords => commonWords.any((word) => !word.isBlank);
}
