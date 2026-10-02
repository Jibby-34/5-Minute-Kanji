import '../models/kanji_card.dart';

/// One slice of a mnemonic: plain English, or an English phrase tied to a
/// component.
class MnemonicSegment {
  const MnemonicSegment({required this.text, this.component});

  final String text;
  final KanjiComponent? component;

  bool get isLink => component != null;
}

/// Splits [mnemonic] into plain text and component links.
///
/// A component is linked only when its [KanjiComponent.mnemonicText] occurs
/// as a whole word or phrase. [KanjiComponent.occurrence] chooses which match
/// to use. Overlapping phrases keep the earlier, then longer, match.
List<MnemonicSegment> segmentMnemonic(
  String mnemonic,
  List<KanjiComponent> components,
) {
  final links = resolveMnemonicLinks(mnemonic, components);
  if (links.isEmpty) {
    return [MnemonicSegment(text: mnemonic)];
  }

  final segments = <MnemonicSegment>[];
  var cursor = 0;
  for (final link in links) {
    if (link.start > cursor) {
      segments.add(
        MnemonicSegment(text: mnemonic.substring(cursor, link.start)),
      );
    }
    segments.add(
      MnemonicSegment(
        text: mnemonic.substring(link.start, link.end),
        component: link.component,
      ),
    );
    cursor = link.end;
  }
  if (cursor < mnemonic.length) {
    segments.add(MnemonicSegment(text: mnemonic.substring(cursor)));
  }
  return segments;
}

class MnemonicLink {
  const MnemonicLink({
    required this.component,
    required this.start,
    required this.end,
  });

  final KanjiComponent component;
  final int start;
  final int end;
}

List<MnemonicLink> resolveMnemonicLinks(
  String mnemonic,
  List<KanjiComponent> components,
) {
  final candidates = <_LinkCandidate>[];
  for (var index = 0; index < components.length; index++) {
    final component = components[index];
    final phrase = component.mnemonicText;
    if (phrase == null || phrase.isEmpty) continue;
    final matches = findPhraseOccurrences(mnemonic, phrase);
    final occurrence = component.occurrence;
    if (occurrence < 0 || occurrence >= matches.length) continue;
    final match = matches[occurrence];
    candidates.add(
      _LinkCandidate(
        order: index,
        start: match.start,
        end: match.end,
        component: component,
      ),
    );
  }

  candidates.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    final byLength = (b.end - b.start).compareTo(a.end - a.start);
    if (byLength != 0) return byLength;
    return a.order.compareTo(b.order);
  });

  final accepted = <MnemonicLink>[];
  var cursor = 0;
  for (final candidate in candidates) {
    if (candidate.start < cursor) continue;
    accepted.add(
      MnemonicLink(
        component: candidate.component,
        start: candidate.start,
        end: candidate.end,
      ),
    );
    cursor = candidate.end;
  }
  return accepted;
}

class PhraseMatch {
  const PhraseMatch({required this.start, required this.end});

  final int start;
  final int end;
}

/// Whole-word matches of [phrase] in [text]. Matching ignores case and does
/// not match inside a longer word.
List<PhraseMatch> findPhraseOccurrences(String text, String phrase) {
  if (phrase.isEmpty) return const [];
  final pattern = RegExp(RegExp.escape(phrase), caseSensitive: false);
  final matches = <PhraseMatch>[];
  for (final match in pattern.allMatches(text)) {
    if (_touchesWord(text, match.start, before: true)) continue;
    if (_touchesWord(text, match.end, before: false)) continue;
    matches.add(PhraseMatch(start: match.start, end: match.end));
  }
  return matches;
}

bool _touchesWord(String text, int index, {required bool before}) {
  final neighbor = before ? index - 1 : index;
  if (neighbor < 0 || neighbor >= text.length) return false;
  return _isWordChar(text.codeUnitAt(neighbor));
}

bool _isWordChar(int codeUnit) {
  final isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
  final isUpper = codeUnit >= 0x41 && codeUnit <= 0x5a;
  final isLower = codeUnit >= 0x61 && codeUnit <= 0x7a;
  return isDigit || isUpper || isLower;
}

class _LinkCandidate {
  const _LinkCandidate({
    required this.order,
    required this.start,
    required this.end,
    required this.component,
  });

  final int order;
  final int start;
  final int end;
  final KanjiComponent component;
}
