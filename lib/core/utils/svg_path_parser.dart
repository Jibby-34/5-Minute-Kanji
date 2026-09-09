import 'package:flutter/painting.dart';

/// Parses the SVG path subset used by KanjiVG (`M/m`, `C/c`, `S/s`) plus a
/// few compatible extras so the geometry stays available as a Flutter [Path].
class SvgPathParser {
  const SvgPathParser();

  Path parse(String data) {
    final path = Path();
    final tokens = _tokenize(data);
    if (tokens.isEmpty) return path;

    var index = 0;
    var current = Offset.zero;
    var start = Offset.zero;
    var lastCubicControl = Offset.zero;
    var lastWasCubic = false;
    String? command;

    List<double> take(int count) {
      if (index + count > tokens.length) {
        throw FormatException('Unterminated SVG path command "$command"');
      }
      final values = <double>[];
      for (var i = 0; i < count; i++) {
        final token = tokens[index++];
        if (token is! double) {
          throw FormatException('Expected number in SVG path, found $token');
        }
        values.add(token);
      }
      return values;
    }

    bool hasCoordinates() {
      return index < tokens.length && tokens[index] is double;
    }

    while (index < tokens.length) {
      final token = tokens[index];
      if (token is String) {
        command = token;
        index++;
      } else if (command == null) {
        throw const FormatException('SVG path must start with a command');
      }

      switch (command) {
        case 'M':
        case 'm':
          final points = take(2);
          current = command == 'M'
              ? Offset(points[0], points[1])
              : current + Offset(points[0], points[1]);
          path.moveTo(current.dx, current.dy);
          start = current;
          lastWasCubic = false;
          command = command == 'M' ? 'L' : 'l';
        case 'L':
        case 'l':
          final points = take(2);
          current = command == 'L'
              ? Offset(points[0], points[1])
              : current + Offset(points[0], points[1]);
          path.lineTo(current.dx, current.dy);
          lastWasCubic = false;
        case 'H':
        case 'h':
          final values = take(1);
          current = Offset(
            command == 'H' ? values[0] : current.dx + values[0],
            current.dy,
          );
          path.lineTo(current.dx, current.dy);
          lastWasCubic = false;
        case 'V':
        case 'v':
          final values = take(1);
          current = Offset(
            current.dx,
            command == 'V' ? values[0] : current.dy + values[0],
          );
          path.lineTo(current.dx, current.dy);
          lastWasCubic = false;
        case 'C':
        case 'c':
          final points = take(6);
          final control1 = command == 'C'
              ? Offset(points[0], points[1])
              : current + Offset(points[0], points[1]);
          final control2 = command == 'C'
              ? Offset(points[2], points[3])
              : current + Offset(points[2], points[3]);
          final end = command == 'C'
              ? Offset(points[4], points[5])
              : current + Offset(points[4], points[5]);
          path.cubicTo(
            control1.dx,
            control1.dy,
            control2.dx,
            control2.dy,
            end.dx,
            end.dy,
          );
          lastCubicControl = control2;
          current = end;
          lastWasCubic = true;
        case 'S':
        case 's':
          final points = take(4);
          final reflected = lastWasCubic
              ? Offset(
                  2 * current.dx - lastCubicControl.dx,
                  2 * current.dy - lastCubicControl.dy,
                )
              : current;
          final control2 = command == 'S'
              ? Offset(points[0], points[1])
              : current + Offset(points[0], points[1]);
          final end = command == 'S'
              ? Offset(points[2], points[3])
              : current + Offset(points[2], points[3]);
          path.cubicTo(
            reflected.dx,
            reflected.dy,
            control2.dx,
            control2.dy,
            end.dx,
            end.dy,
          );
          lastCubicControl = control2;
          current = end;
          lastWasCubic = true;
        case 'Z':
        case 'z':
          path.close();
          current = start;
          lastWasCubic = false;
        default:
          throw FormatException('Unsupported SVG path command "$command"');
      }

      if ((command == 'Z' || command == 'z') && hasCoordinates()) {
        command = null;
      }
    }

    return path;
  }
}

final _command = RegExp(r'[MmCcSsLlHhVvZz]');

List<Object> _tokenize(String data) {
  final tokens = <Object>[];
  var index = 0;
  while (index < data.length) {
    final code = data.codeUnitAt(index);
    if (code == 32 || code == 44 || code == 9 || code == 10 || code == 13) {
      index++;
      continue;
    }
    final letter = data[index];
    if (_command.hasMatch(letter)) {
      tokens.add(letter);
      index++;
      continue;
    }
    final parsed = _readNumber(data, index);
    tokens.add(parsed.value);
    index = parsed.end;
  }
  return tokens;
}

({double value, int end}) _readNumber(String data, int start) {
  var index = start;
  if (index >= data.length) {
    throw const FormatException('Expected number in SVG path');
  }

  final buffer = StringBuffer();
  if (data[index] == '+' || data[index] == '-') {
    buffer.write(data[index]);
    index++;
  }

  var seenDot = false;
  var seenExp = false;
  while (index < data.length) {
    final char = data[index];
    if (char == '.' && !seenDot && !seenExp) {
      seenDot = true;
      buffer.write(char);
      index++;
      continue;
    }
    if ((char == 'e' || char == 'E') && !seenExp) {
      seenExp = true;
      buffer.write(char);
      index++;
      if (index < data.length && (data[index] == '+' || data[index] == '-')) {
        buffer.write(data[index]);
        index++;
      }
      continue;
    }
    final code = char.codeUnitAt(0);
    if (code >= 48 && code <= 57) {
      buffer.write(char);
      index++;
      continue;
    }
    break;
  }

  final text = buffer.toString();
  final value = double.tryParse(text);
  if (value == null) {
    throw FormatException('Invalid SVG path number "$text"');
  }
  if (index == start) {
    throw FormatException('Unexpected SVG path character "${data[start]}"');
  }
  return (value: value, end: index);
}
