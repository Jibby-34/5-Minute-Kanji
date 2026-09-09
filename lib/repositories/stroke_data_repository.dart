import '../core/models/stroke_data.dart';

abstract class StrokeDataRepository {
  /// Returns stroke-order geometry for [character], or `null` when unavailable.
  Future<StrokeData?> getForCharacter(String character);
}

class MemoryStrokeDataRepository implements StrokeDataRepository {
  MemoryStrokeDataRepository([Map<String, StrokeData>? data])
    : _data = data ?? {};

  final Map<String, StrokeData> _data;

  @override
  Future<StrokeData?> getForCharacter(String character) async =>
      _data[character];
}
