import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../common/scenario_page.dart';
import 'file_hash_logic.dart';

/// Scenario: checking a large file before upload (checksum).
///
/// API: `Isolate.spawn` with ports, because we want progress updates and a
/// cancel button. `Isolate.run` only gives one result at the end.
class FileHashPage extends StatefulWidget {
  const FileHashPage({super.key});

  @override
  State<FileHashPage> createState() => _FileHashPageState();
}

class _FileHashPageState extends State<FileHashPage> {
  final _hasher = FileHasher();
  StreamSubscription<HashEvent>? _subscription;

  String? _path;
  String _name = '';
  double? _progress;
  bool _busy = false;
  String _status =
      'Pick a large file (a video works well), or create a '
      '300 MB test file.';

  @override
  void dispose() {
    _subscription?.cancel();
    _hasher.cancel(); // Never leave a worker running after the page closes.
    super.dispose();
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final path = files.single.path;
    setState(() {
      _path = path;
      _name = files.single.name;
      _status = path == null
          ? 'This file has no local path, try another.'
          : 'Picked $_name.';
    });
  }

  Future<void> _createTestFile() async {
    setState(() {
      _busy = true;
      _status = 'Writing a 300 MB test file...';
    });
    // path_provider is a plugin. Call it here, on the main isolate, and send
    // the resulting path (a String) to the isolate.
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/test_300mb.bin';
    final size = await writeTestFileInBackground(path, 300);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _path = path;
      _name = 'test_300mb.bin';
      _status = 'Created ${formatBytes(size)} test file.';
    });
  }

  void _start() {
    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Hashing $_name...';
    });
    final watch = Stopwatch()..start();
    _subscription = _hasher.hash(_path!).listen(
      (event) {
        setState(() {
          switch (event) {
            case HashProgress():
              _progress = event.fraction;
              _status =
                  'Hashing $_name: ${formatBytes(event.bytesRead)} of '
                  '${formatBytes(event.totalBytes)}';
            case HashDone():
              _progress = 1;
              _status =
                  'SHA-256 of ${formatBytes(event.totalBytes)} in '
                  '${watch.elapsed.inMilliseconds} ms:\n${event.sha256Hex}';
            case HashFailed():
              _status = 'Failed: ${event.message}';
          }
        });
      },
      onDone: () => setState(() {
        _busy = false;
        _subscription = null;
      }),
    );
  }

  void _cancel() {
    _subscription?.cancel(); // Cancelling the stream kills the worker.
    setState(() {
      _subscription = null;
      _busy = false;
      _progress = null;
      _status = 'Cancelled. The worker isolate was killed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioPage(
      title: 'Large file checksum',
      api: 'Isolate.spawn() + ports',
      description:
          'Compute the SHA-256 of a large file, for example to check an '
          'upload. The file is streamed in chunks, so memory stays low. The '
          'worker sends progress while it reads, and Cancel kills it at once.',
      busy: _busy,
      status: _status,
      onRunInIsolate: _path == null ? null : _start,
      extraActions: [
        TextButton.icon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.folder_open),
          label: const Text('Pick file'),
        ),
        TextButton.icon(
          onPressed: _busy ? null : _createTestFile,
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('Create test file'),
        ),
        if (_subscription != null)
          TextButton.icon(
            onPressed: _cancel,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Cancel'),
          ),
      ],
      result: _progress == null
          ? null
          : LinearProgressIndicator(value: _progress),
    );
  }
}
