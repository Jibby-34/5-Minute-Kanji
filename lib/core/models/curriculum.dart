import 'kanji_card.dart';

class Lesson {
  const Lesson({required this.id, required this.name, required this.cardIds});

  final String id;
  final String name;
  final List<String> cardIds;
}

/// A curriculum is a named collection of lessons. MVP has RTK → MVP Sample.
class Curriculum {
  const Curriculum({
    required this.id,
    required this.name,
    required this.lessons,
    this.access = ContentAccess.free,
  });

  final String id;
  final String name;
  final List<Lesson> lessons;
  final ContentAccess access;

  List<String> get allCardIds => [
    for (final lesson in lessons) ...lesson.cardIds,
  ];
}
