import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Messages the worker sends back to the main isolate.
sealed class HashEvent {
  const HashEvent();
}

class HashProgress extends HashEvent {
  const HashProgress(this.bytesRead, this.totalBytes);
  final int bytesRead;
  final int totalBytes;
  double get fraction => totalBytes == 0 ? 1 : bytesRead / totalBytes;
}

class HashDone extends HashEvent {
  const HashDone(this.sha256Hex, this.totalBytes);
  final String sha256Hex;
  final int totalBytes;
}

class HashFailed extends HashEvent {
  const HashFailed(this.message);
  final String message;
}

/// Hashes a large file in a spawned isolate, reporting progress, cancellable.
///
/// Why `Isolate.spawn` and not `Isolate.run`? `Isolate.run` gives you exactly
/// one result at the end. Here we want many messages while it works
/// (progress), and a way to stop it early (`kill`). For that you spawn the
/// isolate yourself and talk to it through ports.
class FileHasher {
  Isolate? _isolate;
  ReceivePort? _port;

  bool get isRunning => _port != null;

  /// Starts hashing [path]. The stream ends after a [HashDone] or
  /// [HashFailed] event, or when [cancel] is called.
  Stream<HashEvent> hash(String path) {
    if (isRunning) throw StateError('Already hashing a file');
    final port = ReceivePort();
    final events = StreamController<HashEvent>();
    _port = port;

    port.listen((message) {
      if (message is HashEvent) {
        events.add(message);
        if (message is HashDone || message is HashFailed) _finish(events);
      } else if (message is List) {
        // Sent by onError: [error, stackTrace], both as Strings.
        events.add(HashFailed('${message.first}'));
        _finish(events);
      } else if (message == null) {
        // Sent by onExit, after the worker is gone.
        _finish(events);
      }
    });

    Isolate.spawn(
      _hashWorker,
      (path, port.sendPort),
      onError: port.sendPort,
      onExit: port.sendPort,
      debugName: 'file-hasher',
    ).then((isolate) {
      _isolate = isolate;
      if (_port == null) isolate.kill(); // cancel() came first.
    });

    events.onCancel = cancel;
    return events.stream;
  }

  /// Stops the worker immediately. Nothing else is needed to clean it up.
  void cancel() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port?.close();
    _port = null;
  }

  void _finish(StreamController<HashEvent> events) {
    _isolate = null;
    _port?.close();
    _port = null;
    if (!events.isClosed) events.close();
  }
}

/// Runs in the worker isolate. It must be a top-level or static function.
Future<void> _hashWorker((String, SendPort) args) async {
  final (path, toMain) = args;
  final file = File(path);
  final total = await file.length();

  final digest = _DigestSink();
  final input = sha256.startChunkedConversion(digest);

  const reportEvery = 8 * 1024 * 1024; // Do not flood the main isolate.
  var read = 0;
  var lastReport = 0;
  // openRead streams the file in chunks: memory stays flat even for
  // multi-gigabyte files.
  await for (final chunk in file.openRead()) {
    input.add(chunk);
    read += chunk.length;
    if (read - lastReport >= reportEvery) {
      lastReport = read;
      toMain.send(HashProgress(read, total));
    }
  }
  input.close();

  // Last message: Isolate.exit hands it over and ends the isolate.
  Isolate.exit(toMain, HashDone(digest.value.toString(), total));
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Writes a test file of [megabytes] MB, so the demo works without a big file.
/// Runs in `Isolate.run`; returns the file size.
int writeTestFile(String path, int megabytes) {
  final out = File(path).openSync(mode: FileMode.write);
  final block = Uint8List(1024 * 1024);
  var seed = 12345;
  try {
    for (var mb = 0; mb < megabytes; mb++) {
      for (var i = 0; i < block.length; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        block[i] = seed >> 16;
      }
      out.writeFromSync(block);
    }
  } finally {
    out.closeSync();
  }
  return megabytes * block.length;
}

// Why a top-level helper instead of calling Isolate.run in the widget?
// A closure can capture more than the variables it uses: the Dart VM keeps
// the whole surrounding context. A closure created inside a State method can
// end up holding `this`, and with it the widget tree, which cannot be sent
// (we hit exactly this: "Illegal argument in isolate message"). A closure
// created here can only see this function's parameters.
Future<int> writeTestFileInBackground(String path, int megabytes) =>
    Isolate.run(() => writeTestFile(path, megabytes));
