import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// What to process: either a file on disk or bytes already in memory.
///
/// Prefer [path] when you have one. A path is a String, and Strings are
/// shared between isolates for free. Bytes are a mutable Uint8List, so they
/// are copied when they cross into the isolate.
class PhotoJob {
  const PhotoJob.file(String this.path) : bytes = null;
  const PhotoJob.bytes(Uint8List this.bytes) : path = null;

  final String? path;
  final Uint8List? bytes;
}

class ProcessedPhoto {
  const ProcessedPhoto({
    required this.jpeg,
    required this.originalWidth,
    required this.originalHeight,
    required this.width,
    required this.height,
  });

  final Uint8List jpeg;
  final int originalWidth;
  final int originalHeight;
  final int width;
  final int height;
}

/// Decode, resize to [maxSide], apply a "vintage" filter, encode as JPEG.
///
/// Pure Dart (package:image), no dart:ui and no plugins, so it runs in any
/// isolate. dart:io file reads work in background isolates too.
ProcessedPhoto processPhoto(PhotoJob job, {int maxSide = 1600}) {
  final input = job.path != null
      ? File(job.path!).readAsBytesSync()
      : job.bytes!;
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    throw const FormatException('Not an image this decoder understands');
  }

  final landscape = decoded.width >= decoded.height;
  final resized = img.copyResize(
    decoded,
    width: landscape ? maxSide : null,
    height: landscape ? null : maxSide,
    interpolation: img.Interpolation.cubic,
  );
  final filtered = img.vignette(img.sepia(resized, amount: 0.8), amount: 0.6);

  return ProcessedPhoto(
    jpeg: img.encodeJpg(filtered, quality: 85),
    originalWidth: decoded.width,
    originalHeight: decoded.height,
    width: filtered.width,
    height: filtered.height,
  );
}

// Why a top-level helper instead of calling Isolate.run in the widget?
// A closure can capture more than the variables it uses: the Dart VM keeps
// the whole surrounding context. A closure created inside a State method can
// end up holding `this`, and with it the widget tree, which cannot be sent
// (we hit exactly this: "Illegal argument in isolate message"). A closure
// created here can only see this function's parameters.
Future<ProcessedPhoto> processPhotoInBackground(PhotoJob job) =>
    Isolate.run(() => processPhoto(job));
