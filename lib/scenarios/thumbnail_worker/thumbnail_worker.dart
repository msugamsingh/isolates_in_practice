import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A long-lived background worker that makes gallery thumbnails on request.
///
/// Why long-lived? A gallery asks for dozens of thumbnails while you scroll.
/// Starting a new isolate for each one (`Isolate.run` per tile) pays the
/// start-up cost every time and keeps nothing between calls. One worker
/// started once:
///   - handles requests one after another,
///   - keeps a cache of thumbnails it already made (state that lives in the
///     worker, not on the main isolate),
///   - is stopped once, in `dispose`.
///
/// Protocol (all messages are small records):
///   main   -> worker : (id, photoIndex)
///   worker -> main   : (id, jpegBytes)
class ThumbnailWorker {
  Isolate? _isolate;
  SendPort? _toWorker;
  final _fromWorker = ReceivePort();
  final _pending = <int, Completer<Uint8List>>{};
  var _nextId = 0;

  /// Starts the worker and waits until it is ready for requests.
  Future<void> start() async {
    final ready = Completer<SendPort>();
    _fromWorker.listen((message) {
      if (message is SendPort) {
        ready.complete(message); // Handshake: the worker's own address.
      } else if (message is (int, Uint8List)) {
        final (id, jpeg) = message;
        _pending.remove(id)?.complete(jpeg);
      }
    });
    _isolate = await Isolate.spawn(
      _workerMain,
      _fromWorker.sendPort,
      debugName: 'thumbnail-worker',
    );
    _toWorker = await ready.future;
  }

  /// Asks for the thumbnail of photo [index]. Each request gets an id, so
  /// replies are matched to the right caller even if they arrive in a
  /// different order.
  Future<Uint8List> thumbnail(int index) {
    final id = _nextId++;
    final completer = Completer<Uint8List>();
    _pending[id] = completer;
    _toWorker!.send((id, index));
    return completer.future;
  }

  /// Stops the worker. A spawned isolate lives until you kill it or close
  /// its ports, so always call this (for example from `State.dispose`).
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _fromWorker.close();
    for (final c in _pending.values) {
      c.completeError(StateError('Worker stopped'));
    }
    _pending.clear();
  }
}

/// Entry point of the worker isolate. Top-level, takes the main isolate's
/// SendPort, and keeps running as long as its ReceivePort is open.
void _workerMain(SendPort toMain) {
  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);

  // Lives inside the worker, for as long as the worker lives.
  final cache = <int, Uint8List>{};

  inbox.listen((message) {
    final (id, index) = message as (int, int);
    final jpeg = cache[index] ??= makeThumbnail(index);
    toMain.send((id, jpeg));
  });
}

/// Builds photo number [index] and shrinks it to a 256 px thumbnail.
///
/// The "photo" is generated (2000x1500 pixels) so the demo needs no files.
/// In a real app you would read and decode the photo file here.
Uint8List makeThumbnail(int index) {
  final photo = img.Image(width: 2000, height: 1500);
  final hue = (index * 37) % 360;
  for (final p in photo) {
    final t = (p.x + p.y) / (photo.width + photo.height);
    final c = _hsv(hue + t * 60, 0.6, 0.5 + 0.5 * t);
    p
      ..r = c.$1
      ..g = c.$2
      ..b = c.$3;
  }
  final thumb = img.copyResize(
    photo,
    width: 256,
    interpolation: img.Interpolation.average,
  );
  return img.encodeJpg(thumb, quality: 80);
}

(int, int, int) _hsv(double h, double s, double v) {
  h %= 360;
  final c = v * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = v - c;
  final (r, g, b) = switch (h ~/ 60) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  int to8(double f) => ((f + m) * 255).round();
  return (to8(r), to8(g), to8(b));
}
