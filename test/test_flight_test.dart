import 'package:fiveminutekanji/services/test_flight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reinforcement debugger visibility', () {
    test('a debug run shows the debugger', () {
      expect(
        reinforcementDebuggerVisible(debugMode: true, testFlight: false),
        isTrue,
      );
    });

    test('a TestFlight install shows the debugger', () {
      expect(
        reinforcementDebuggerVisible(debugMode: false, testFlight: true),
        isTrue,
      );
    });

    test('an App Store install hides the debugger', () {
      expect(
        reinforcementDebuggerVisible(debugMode: false, testFlight: false),
        isFalse,
      );
    });
  });

  group('TestFlight receipt', () {
    test('the sandbox receipt is a TestFlight install', () {
      expect(isTestFlightReceipt('sandboxReceipt'), isTrue);
    });

    test('the public store receipt is not a TestFlight install', () {
      expect(isTestFlightReceipt('receipt'), isFalse);
      expect(isTestFlightReceipt(null), isFalse);
      expect(isTestFlightReceipt(''), isFalse);
    });
  });
}
