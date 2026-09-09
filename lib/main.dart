import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/licenses/third_party_licenses.dart';
import 'data/hardcoded_kanji_repository.dart';
import 'data/shared_prefs_progress_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  registerThirdPartyLicenses();

  const kanjiRepository = HardcodedKanjiRepository();
  final prefs = await SharedPreferences.getInstance();
  final progressRepository = SharedPrefsProgressRepository(prefs);

  final cards = await kanjiRepository.getAll();
  await progressRepository.seedIfNeeded(cards.map((card) => card.id).toList());

  runApp(
    FiveMinuteKanjiApp(
      kanjiRepository: kanjiRepository,
      progressRepository: progressRepository,
    ),
  );
}
