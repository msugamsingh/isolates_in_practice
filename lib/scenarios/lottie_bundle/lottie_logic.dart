import 'dart:isolate';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One animation from the bundle, ready for `Lottie.memory`.
class LottieClip {
  const LottieClip({
    required this.name,
    required this.json,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.frames,
  });

  final String name;

  /// The animation's JSON, as UTF-8 bytes.
  final Uint8List json;
  final int width;
  final int height;
  final double frameRate;
  final int frames;

  Duration get duration =>
      Duration(milliseconds: (frames / frameRate * 1000).round());
}

/// Unzips a bundle of Lottie animations and reads each one's metadata.
///
/// Runs in `Isolate.run`. It returns plain data (names, numbers, bytes).
/// It does not build `LottieComposition`s: a composition can hold dart:ui
/// objects such as decoded images, and objects backed by native resources
/// cannot be sent between isolates. The main isolate builds each composition
/// from the bytes, one small animation at a time, when its tile appears.
List<LottieClip> unpackLottieBundle(Uint8List zipBytes) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  final clips = <LottieClip>[];
  for (final file in archive.files) {
    if (!file.isFile || !file.name.endsWith('.json')) continue;
    final bytes = file.content;
    // Decoding validates the JSON and gives us the metadata to show.
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    clips.add(
      LottieClip(
        name: json['nm'] as String? ?? file.name,
        json: bytes,
        width: (json['w'] as num).toInt(),
        height: (json['h'] as num).toInt(),
        frameRate: (json['fr'] as num).toDouble(),
        frames: ((json['op'] as num) - (json['ip'] as num)).toInt(),
      ),
    );
  }
  clips.sort((a, b) => a.name.compareTo(b.name));
  return clips;
}

// Why a top-level helper instead of calling Isolate.run in the widget?
// A closure can capture more than the variables it uses: the Dart VM keeps
// the whole surrounding context. A closure created inside a State method can
// end up holding `this`, and with it the widget tree, which cannot be sent
// (we hit exactly this: "Illegal argument in isolate message"). A closure
// created here can only see this function's parameters.
Future<List<LottieClip>> unpackLottieBundleInBackground(Uint8List zipBytes) =>
    Isolate.run(() => unpackLottieBundle(zipBytes));
