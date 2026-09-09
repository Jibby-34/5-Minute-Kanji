import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const kanjiVgName = 'KanjiVG';
const kanjiVgAuthor = 'Ulrich Apel';
const kanjiVgSite = 'https://kanjivg.tagaini.net';
const kanjiVgLicenseName = 'Creative Commons Attribution-Share Alike 3.0';
const kanjiVgCopyright = 'Copyright © 2009–2026 Ulrich Apel';
const kanjiVgLicenseAsset = 'third_party/kanjivg/COPYING';

const kanjiVgAttribution =
    '''
$kanjiVgName
$kanjiVgCopyright

Stroke-order diagrams in 5-Minute Kanji are generated from $kanjiVgName
($kanjiVgSite).

$kanjiVgName is released under the $kanjiVgLicenseName license. The JSON
stroke files bundled with this app are an adaptation of that data and are
therefore also licensed under CC BY-SA 3.0.
''';

void registerThirdPartyLicenses({AssetBundle? bundle}) {
  final assets = bundle ?? rootBundle;
  LicenseRegistry.addLicense(() async* {
    final text = await assets.loadString(kanjiVgLicenseAsset);
    yield LicenseEntryWithLineBreaks([kanjiVgName], text);
  });
}
