import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common/scenario_page.dart';
import 'photo_logic.dart';

/// Scenario: editing a photo before upload.
///
/// API: `Isolate.run`, called through `processPhotoInBackground` in
/// photo_logic.dart. The closure is created there, not in this State, so it
/// cannot accidentally capture the widget (see the note in that file).
///
/// Note: just *showing* a photo does not need an isolate. Flutter decodes
/// images for display off the main isolate already; use `cacheWidth` to
/// decode big photos at the size you show them. An isolate is for the pixel
/// work you write yourself: resize, filter, compress.
class PhotoPage extends StatefulWidget {
  const PhotoPage({super.key});

  @override
  State<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<PhotoPage> {
  PhotoJob? _job;
  String _source = 'sample photo';
  ProcessedPhoto? _result;
  bool _busy = false;
  String _status = 'Uses the bundled sample photo, or pick your own.';

  Future<PhotoJob> _currentJob() async {
    if (_job != null) return _job!;
    // rootBundle only works on the main isolate, so assets are loaded here
    // and the bytes are sent to the background isolate.
    final data = await rootBundle.load('assets/sample_photo.jpg');
    return _job = PhotoJob.bytes(data.buffer.asUint8List());
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return;
    final path = files.single.path;
    if (path == null) {
      setState(() => _status = 'This file has no local path, try another.');
      return;
    }
    setState(() {
      _job = PhotoJob.file(path); // A path is a String: free to send.
      _source = files.single.name;
      _result = null;
      _status = 'Picked ${files.single.name}.';
    });
  }

  Future<void> _process({required bool inIsolate}) async {
    final job = await _currentJob();
    setState(() {
      _busy = true;
      _status = 'Processing $_source...';
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));

    try {
      final (photo, took) = await timed(() async {
        if (inIsolate) {
          return processPhotoInBackground(job); // Isolate.run inside
        }
        return processPhoto(job);
      });
      if (!mounted) return;
      setState(() {
        _result = photo;
        _status =
            '${inIsolate ? 'Isolate.run' : 'Main isolate'}: '
            '${photo.originalWidth}x${photo.originalHeight} -> '
            '${photo.width}x${photo.height}, '
            '${formatBytes(photo.jpeg.length)} JPEG in ${took.inMilliseconds} ms.';
      });
    } on FormatException catch (e) {
      // Errors thrown in the isolate come back here, like any other await.
      if (mounted) setState(() => _status = 'Failed: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioPage(
      title: 'Photo filter',
      api: 'Isolate.run()',
      description:
          'Resize a photo, apply a filter and compress it before upload. '
          'Every pixel goes through your own Dart code, so on the main isolate '
          'the screen freezes until it is done.',
      busy: _busy,
      status: _status,
      onRunOnMain: () => _process(inIsolate: false),
      onRunInIsolate: () => _process(inIsolate: true),
      extraActions: [
        TextButton.icon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Pick photo'),
        ),
      ],
      result: _result == null
          ? null
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              // cacheWidth: decode at display size, not full size.
              child: Image.memory(_result!.jpeg, cacheWidth: 1080),
            ),
    );
  }
}
