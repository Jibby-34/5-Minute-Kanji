/// Sample queues for the Reinforcement Day debugger.
///
/// Each list is a set of recall probabilities. The debugger evaluates them
/// with the production diagnosis and does not read or write cards.
enum ReinforcementDiagnosticSource {
  liveQueue,
  healthy,
  lowAverage,
  fragileTail,
  borderline,
  smallQueue,
  empty;

  String get label => switch (this) {
    ReinforcementDiagnosticSource.liveQueue => 'Live queue',
    ReinforcementDiagnosticSource.healthy => 'Healthy queue',
    ReinforcementDiagnosticSource.lowAverage => 'Low average',
    ReinforcementDiagnosticSource.fragileTail => 'Fragile tail',
    ReinforcementDiagnosticSource.borderline => 'Borderline queue',
    ReinforcementDiagnosticSource.smallQueue => 'Small queue',
    ReinforcementDiagnosticSource.empty => 'Empty queue',
  };

  String get detail => switch (this) {
    ReinforcementDiagnosticSource.liveQueue =>
      'Cards due today, read from this device.',
    ReinforcementDiagnosticSource.healthy => '20 cards at 0.85.',
    ReinforcementDiagnosticSource.lowAverage => '20 cards at 0.65.',
    ReinforcementDiagnosticSource.fragileTail =>
      '6 cards at 0.30 and 14 cards at 0.85.',
    ReinforcementDiagnosticSource.borderline =>
      '5 cards at 0.39 and 15 cards at 0.80.',
    ReinforcementDiagnosticSource.smallQueue => '5 cards at 0.20.',
    ReinforcementDiagnosticSource.empty => 'No cards.',
  };

  bool get simulation => this != ReinforcementDiagnosticSource.liveQueue;

  /// Deterministic probabilities for a simulation.
  ///
  /// The live queue has none of its own; the debugger supplies those from
  /// the device.
  List<double> get probabilities => switch (this) {
    ReinforcementDiagnosticSource.liveQueue => const [],
    ReinforcementDiagnosticSource.healthy => _filled(20, 0.85),
    ReinforcementDiagnosticSource.lowAverage => _filled(20, 0.65),
    ReinforcementDiagnosticSource.fragileTail => [
      ..._filled(6, 0.30),
      ..._filled(14, 0.85),
    ],
    ReinforcementDiagnosticSource.borderline => [
      ..._filled(5, 0.39),
      ..._filled(15, 0.80),
    ],
    ReinforcementDiagnosticSource.smallQueue => _filled(5, 0.20),
    ReinforcementDiagnosticSource.empty => const [],
  };
}

List<double> _filled(int count, double probability) {
  return List<double>.filled(count, probability);
}
