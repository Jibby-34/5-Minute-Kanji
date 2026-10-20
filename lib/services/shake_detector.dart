import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Recognizes a deliberate phone shake from accelerometer samples.
///
/// Samples include gravity, so a phone at rest sits near 1g. [thresholdG]
/// is well above a bump or a walk, and [cooldown] keeps one shake from
/// undoing more than one answer.
///
/// iOS shake-to-edit is left alone: that path feeds the system undo manager
/// for text, which this session does not use. CoreMotion on iOS and the
/// accelerometer on Android both arrive through the same stream, so a phone
/// without the sensor simply never shakes.
class ShakeGesture {
  ShakeGesture({
    this.thresholdG = 2.7,
    this.cooldown = const Duration(milliseconds: 1200),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const standardGravity = 9.80665;

  final double thresholdG;
  final Duration cooldown;
  final DateTime Function() _clock;
  DateTime? _lastShake;

  /// True when [x], [y], and [z] are a new shake, in m/s².
  bool consider(double x, double y, double z) {
    final magnitude = math.sqrt(x * x + y * y + z * z);
    if (magnitude < thresholdG * standardGravity) return false;
    final now = _clock();
    final previous = _lastShake;
    if (previous != null && now.difference(previous) < cooldown) return false;
    _lastShake = now;
    return true;
  }
}

/// A stream of shake gestures. An error means the sensor cannot be used.
abstract class ShakeEvents {
  const ShakeEvents();

  Stream<void> watch();
}

/// Phone accelerometer. The stream closes itself if the sensor is missing.
class SensorShakeEvents extends ShakeEvents {
  SensorShakeEvents({ShakeGesture? gesture})
    : gesture = gesture ?? ShakeGesture();

  final ShakeGesture gesture;

  @override
  Stream<void> watch() {
    late final StreamController<void> controller;
    StreamSubscription<AccelerometerEvent>? subscription;
    controller = StreamController<void>(
      onListen: () {
        try {
          subscription =
              accelerometerEventStream(
                samplingPeriod: SensorInterval.uiInterval,
              ).listen(
                (event) {
                  if (!controller.isClosed &&
                      gesture.consider(event.x, event.y, event.z)) {
                    controller.add(null);
                  }
                },
                onError: (Object _) {
                  if (!controller.isClosed) controller.close();
                },
                cancelOnError: true,
              );
        } catch (_) {
          if (!controller.isClosed) controller.close();
        }
      },
      onCancel: () async {
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}

/// Accelerometer shakes on phones. Other platforms never emit.
ShakeEvents? sensorShakeEventsForPlatform() {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => SensorShakeEvents(),
    _ => null,
  };
}
