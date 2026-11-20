import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

/// A top-level variable. Every isolate gets its OWN copy of it.
int launchCount = 0;

class Item {
  const Item(this.id, this.name, this.price);
  final int id;
  final String name;
  final double price;
}

List<Item> makeItems(int count) => [
  for (var i = 0; i < count; i++) Item(i, 'item $i', i * 1.5),
];

/// One measured line in the results table.
class Measurement {
  const Measurement(this.label, this.what, this.millis);
  final String label;

  /// Copied, shared or moved, in plain words.
  final String what;
  final double millis;
}

/// Experiments that show what an isolate group does and does not share.
///
/// Every isolate here is started with `Isolate.spawn` or `Isolate.run`, so all
/// of them are in the same isolate group as the main isolate. Inside a group
/// the Dart VM shares the program code and keeps all objects in one heap.
/// That heap sharing is an implementation detail: your Dart code still cannot
/// reach another isolate's objects. What you CAN see is what it makes cheap:
///   - immutable objects (like String) are sent by reference,
///   - `Isolate.exit` hands a result over without copying (same group only),
///   - spawning reuses the group's code.
class GroupLab {
  static const megabytes64 = 64 * 1024 * 1024;
  static const objectCount = 500000;

  /// 1. Same code, separate memory.
  ///
  /// Main sets the top-level variable to 5. A spawned isolate in the same
  /// group runs the same code but has its own copy, starting from 0.
  static Future<(int, int)> separateStatics() async {
    launchCount = 5;
    final seenByWorker = await Isolate.run(() => ++launchCount);
    return (launchCount, seenByWorker); // (5, 1)
  }

  /// 2. Sending INTO a worker. `SendPort.send` makes any copy right away, on
  ///    the sender. Here the sender is the main isolate, so we time how long
  ///    the main isolate is blocked by each `send` call.
  static Future<List<Measurement>> sendInto() async {
    final worker = await _EchoWorker.start();
    try {
      final items = makeItems(objectCount);
      final bytes = Uint8List(megabytes64);
      final text = 'x' * megabytes64;

      final results = <Measurement>[
        await worker.timeSend('$objectCount objects', 'copied', items),
        await worker.timeSend('64 MB Uint8List', 'copied', bytes),
        await worker.timeSend('64 MB String', 'shared (immutable)', text),
      ];

      // TransferableTypedData: creating it copies the bytes once; after
      // that, sending it is constant time and the receiver owns the bytes.
      final create = Stopwatch()..start();
      final transferable = TransferableTypedData.fromList([bytes]);
      final createMs = create.elapsedMicroseconds / 1000;
      results
        ..add(
          Measurement(
            '  creating the TransferableTypedData',
            'one copy',
            createMs,
          ),
        )
        ..add(
          await worker.timeSend(
            '64 MB TransferableTypedData',
            'moved',
            transferable,
          ),
        );
      return results;
    } finally {
      worker.close();
    }
  }

  /// 3. Getting a result OUT of a worker, timed end to end on main.
  ///    A long-lived worker must `send` (a copy, made in the worker).
  ///    `Isolate.run` ends with `Isolate.exit`, which hands the result over
  ///    without a copy. That only works inside one isolate group.
  static Future<List<Measurement>> resultBack() async {
    final worker = await _EchoWorker.start();
    try {
      final viaSend = Stopwatch()..start();
      await worker.request('make');
      final sendMs = viaSend.elapsedMicroseconds / 1000;

      final viaExit = Stopwatch()..start();
      await Isolate.run(() => makeItems(objectCount));
      final exitMs = viaExit.elapsedMicroseconds / 1000;

      return [
        Measurement('$objectCount objects via SendPort.send', 'copied', sendMs),
        Measurement(
          '$objectCount objects via Isolate.run (exit)',
          'handed over',
          exitMs,
        ),
      ];
    } finally {
      worker.close();
    }
  }
}

/// A tiny long-lived worker that replies to every message.
class _EchoWorker {
  _EchoWorker._(this._isolate, this._inbox, this._replies, this._toWorker);

  final Isolate _isolate;
  final ReceivePort _inbox;
  final StreamIterator<Object?> _replies;
  final SendPort _toWorker;

  static Future<_EchoWorker> start() async {
    final inbox = ReceivePort();
    final replies = StreamIterator<Object?>(inbox);
    final isolate = await Isolate.spawn(_echoMain, inbox.sendPort);
    await replies.moveNext();
    return _EchoWorker._(isolate, inbox, replies, replies.current as SendPort);
  }

  Future<Measurement> timeSend(
    String label,
    String what,
    Object message,
  ) async {
    final watch = Stopwatch()..start();
    _toWorker.send(message); // Any copy happens inside this call.
    final ms = watch.elapsedMicroseconds / 1000;
    await _replies.moveNext(); // Wait for the worker before the next test.
    return Measurement(label, what, ms);
  }

  Future<Object?> request(Object message) async {
    _toWorker.send(message);
    await _replies.moveNext();
    return _replies.current;
  }

  void close() {
    _isolate.kill();
    _inbox.close();
  }
}

void _echoMain(SendPort toMain) {
  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);
  inbox.listen((message) {
    if (message == 'make') {
      toMain.send(makeItems(GroupLab.objectCount)); // copied on the way out
    } else {
      if (message is TransferableTypedData) message.materialize();
      toMain.send('ok');
    }
  });
}
