import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isolates_in_practice/scenarios/audio_merge/audio_logic.dart';
import 'package:isolates_in_practice/scenarios/file_hash/file_hash_logic.dart';
import 'package:isolates_in_practice/scenarios/isolate_group/group_logic.dart';
import 'package:isolates_in_practice/scenarios/json_feed/feed_logic.dart';
import 'package:isolates_in_practice/scenarios/lottie_bundle/lottie_logic.dart';
import 'package:isolates_in_practice/scenarios/photo_filter/photo_logic.dart';
import 'package:isolates_in_practice/scenarios/thumbnail_worker/thumbnail_worker.dart';
import 'package:lottie/lottie.dart';

void main() {
  late Directory tmp;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('isolates_test'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('feed: parsed in an isolate, sorted by likes', () async {
    final body = await Isolate.run(() => buildFakeFeedJson(5000));
    final posts = await Isolate.run(() => parseFeed(body));
    expect(posts, hasLength(5000));
    expect(posts.first.likes >= posts.last.likes, isTrue);
  });

  test('photo: resized, filtered and encoded in an isolate', () async {
    final bytes = File('assets/sample_photo.jpg').readAsBytesSync();
    final job = PhotoJob.bytes(bytes);
    final photo = await Isolate.run(() => processPhoto(job));
    expect((photo.originalWidth, photo.originalHeight), (4000, 3000));
    expect((photo.width, photo.height), (1600, 1200));
    expect(photo.jpeg.take(2), [0xFF, 0xD8]); // JPEG magic bytes
  });

  test('lottie: bundle unpacks and every clip is a valid animation', () async {
    final zip = File('assets/lottie_bundle.zip').readAsBytesSync();
    final clips = await Isolate.run(() => unpackLottieBundle(zip));
    expect(clips, hasLength(150));
    final composition = await LottieComposition.fromBytes(clips.first.json);
    expect(composition.durationFrames, closeTo(600, 0.1));
    expect(clips.first.duration, const Duration(seconds: 10));
  });

  test('audio: clips merged with crossfades into one WAV', () async {
    final dir = tmp.path;
    final clips = await Isolate.run(
      () => writeTestClips(dir, 3, const Duration(seconds: 2)),
    );
    final job = MergeJob(clipPaths: clips, outputPath: '$dir/merged.wav');
    final result = await Isolate.run(() => mergeClips(job));
    // 3 x 2 s, minus two 0.5 s crossfades = 5 s.
    expect(result.duration, const Duration(seconds: 5));
    expect(File(result.path).lengthSync(), result.bytes);
    expect(result.peaks.reduce((a, b) => a > b ? a : b), closeTo(0.89, 0.01));
  });

  test('file hash: progress, then the correct SHA-256', () async {
    final path = '${tmp.path}/data.bin';
    await Isolate.run(() => writeTestFile(path, 20));
    final events = await FileHasher().hash(path).toList();
    expect(events.whereType<HashProgress>(), isNotEmpty);
    final done = events.last as HashDone;
    expect(
      done.sha256Hex,
      sha256.convert(File(path).readAsBytesSync()).toString(),
    );
  });

  test('file hash: cancel stops the worker', () async {
    final path = '${tmp.path}/cancel.bin';
    await Isolate.run(() => writeTestFile(path, 50));
    final hasher = FileHasher();
    final sub = hasher.hash(path).listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    expect(hasher.isRunning, isFalse);
  });

  test('thumbnail worker: answers each request and caches', () async {
    final worker = ThumbnailWorker();
    await worker.start();
    final thumbs = await Future.wait([
      for (var i = 0; i < 4; i++) worker.thumbnail(i),
    ]);
    expect(
      thumbs.every((t) => t.take(2).toList().toString() == '[255, 216]'),
      isTrue,
    );
    final again = Stopwatch()..start();
    await worker.thumbnail(0); // cached in the worker
    expect(again.elapsedMilliseconds, lessThan(50));
    worker.dispose();
  });

  test('isolate group: statics are per isolate, strings are shared', () async {
    final (mainValue, workerValue) = await GroupLab.separateStatics();
    expect((mainValue, workerValue), (5, 1));
    final into = await GroupLab.sendInto();
    final string = into.firstWhere((m) => m.label.contains('String'));
    final bytes = into.firstWhere((m) => m.label == '64 MB Uint8List');
    expect(string.millis, lessThan(bytes.millis));
  });
}
