import 'package:flutter_test/flutter_test.dart';
import 'package:fiveminutekanji/core/models/kanji_card.dart';
import 'package:fiveminutekanji/core/utils/mnemonic_links.dart';

KanjiComponent component({
  required String id,
  required String character,
  required String name,
  String? mnemonicText,
  int occurrence = 0,
}) {
  return KanjiComponent(
    id: id,
    character: character,
    name: name,
    mnemonicText: mnemonicText,
    occurrence: occurrence,
  );
}

void main() {
  test('leaves a mnemonic unchanged when nothing is linked', () {
    final segments = segmentMnemonic('One horizontal stroke.', const []);

    expect(segments, hasLength(1));
    expect(segments.single.text, 'One horizontal stroke.');
    expect(segments.single.isLink, isFalse);
  });

  test('links each English phrase to its component', () {
    final segments = segmentMnemonic('A person rests against a tree.', [
      component(
        id: 'person',
        character: '亻',
        name: 'person',
        mnemonicText: 'person',
      ),
      component(id: 'tree', character: '木', name: 'tree', mnemonicText: 'tree'),
    ]);

    expect(segments.map((segment) => segment.text), [
      'A ',
      'person',
      ' rests against a ',
      'tree',
      '.',
    ]);
    expect(segments[1].component!.character, '亻');
    expect(segments[3].component!.character, '木');
  });

  test('matches a phrase without matching a longer word', () {
    final segments = segmentMnemonic('A personal person hears an ear.', [
      component(
        id: 'person',
        character: '人',
        name: 'person',
        mnemonicText: 'person',
      ),
      component(id: 'ear', character: '耳', name: 'ear', mnemonicText: 'ear'),
    ]);

    expect(
      segments
          .where((segment) => segment.isLink)
          .map((segment) => segment.text),
      ['person', 'ear'],
    );
  });

  test('uses occurrence to choose a repeated word', () {
    const mnemonic = 'A person sees another person.';
    final firstOnly = segmentMnemonic(mnemonic, [
      component(
        id: 'person',
        character: '亻',
        name: 'person',
        mnemonicText: 'person',
      ),
    ]);
    final secondOnly = segmentMnemonic(mnemonic, [
      component(
        id: 'person',
        character: '亻',
        name: 'person',
        mnemonicText: 'person',
        occurrence: 1,
      ),
    ]);

    expect(firstOnly[1].text, 'person');
    expect(firstOnly[1].isLink, isTrue);
    expect(firstOnly.last.text, ' sees another person.');

    expect(secondOnly.first.text, 'A person sees another ');
    expect(secondOnly[1].text, 'person');
    expect(secondOnly[1].isLink, isTrue);
    expect(secondOnly.last.text, '.');
  });

  test('ignores a phrase that is not in the mnemonic', () {
    final segments = segmentMnemonic('One horizontal stroke.', [
      component(id: 'sun', character: '日', name: 'sun', mnemonicText: 'sun'),
    ]);

    expect(segments.single.isLink, isFalse);
    expect(segments.single.text, 'One horizontal stroke.');
  });

  test('keeps the earlier longer phrase when two links overlap', () {
    final segments = segmentMnemonic('A sun with one white ray.', [
      component(
        id: 'white',
        character: '白',
        name: 'white',
        mnemonicText: 'white',
      ),
      component(
        id: 'ray',
        character: '光',
        name: 'white ray',
        mnemonicText: 'white ray',
      ),
    ]);

    expect(
      segments
          .where((segment) => segment.isLink)
          .map((segment) => segment.text),
      ['white ray'],
    );
  });

  test('matches the mnemonic phrase regardless of case', () {
    final segments = segmentMnemonic('Ten with a slant on top.', [
      component(id: 'ten', character: '十', name: 'ten', mnemonicText: 'ten'),
    ]);

    expect(segments.first.text, 'Ten');
    expect(segments.first.isLink, isTrue);
    expect(segments.last.text, ' with a slant on top.');
  });

  test('skips an occurrence that is not in the mnemonic', () {
    final segments = segmentMnemonic('A person rests.', [
      component(
        id: 'person',
        character: '亻',
        name: 'person',
        mnemonicText: 'person',
        occurrence: 2,
      ),
    ]);

    expect(segments.single.isLink, isFalse);
  });
}
