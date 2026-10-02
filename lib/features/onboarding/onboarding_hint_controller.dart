import 'package:flutter/foundation.dart';

import '../../core/models/onboarding.dart';
import '../../services/onboarding_service.dart';

/// Tracks which one-time pointers the learning screen still owes the user.
///
/// Lives above the session so a hint survives being closed and reopened, and
/// is dismissed by the action it describes rather than by a timer.
class OnboardingHintController extends ChangeNotifier {
  OnboardingHintController({required this.service});

  final OnboardingService service;

  /// Nothing is shown until the stored state is known, so a hint cannot flash
  /// in front of a user who has already seen it.
  Set<OnboardingHint>? _pending;

  Future<void> load() async {
    try {
      final progress = await service.progress();
      _pending = {
        for (final hint in OnboardingHint.values)
          if (!progress.hasSeen(hint)) hint,
      };
    } catch (_) {
      _pending = const {};
    }
    notifyListeners();
  }

  bool shouldShow(OnboardingHint hint) => _pending?.contains(hint) ?? false;

  /// Called when the user does the thing the hint was pointing at.
  Future<void> dismiss(OnboardingHint hint) => dismissAll([hint]);

  Future<void> dismissAll(Iterable<OnboardingHint> hints) async {
    final pending = _pending;
    if (pending == null) return;
    final seen = hints.where(pending.contains).toList();
    if (seen.isEmpty) return;

    _pending = {...pending}..removeAll(seen);
    notifyListeners();
    await service.markHintsSeen(seen);
  }
}
