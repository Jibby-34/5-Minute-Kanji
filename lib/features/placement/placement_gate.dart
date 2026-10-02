import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/placement_service.dart';
import '../home/home_screen.dart';
import 'placement_screen.dart';

/// App root. Sends a user who has not been placed yet through the placement
/// test once, and everyone else straight to Home.
class PlacementGate extends StatefulWidget {
  const PlacementGate({super.key});

  @override
  State<PlacementGate> createState() => _PlacementGateState();
}

class _PlacementGateState extends State<PlacementGate> {
  bool? _placementRequired;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    var required = false;
    try {
      required = await context.read<PlacementService>().isRequired();
    } catch (_) {
      // Never let a storage failure lock the user out of the app.
      required = false;
    }
    if (!mounted) return;
    setState(() => _placementRequired = required);
  }

  @override
  Widget build(BuildContext context) {
    final required = _placementRequired;
    if (required == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (!required) return const HomeScreen();

    return PlacementScreen(
      onFinished: () => setState(() => _placementRequired = false),
    );
  }
}
