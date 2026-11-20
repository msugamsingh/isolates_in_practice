# Isolates in practice

Real-world uses of Dart isolates in a Flutter app: `compute`, `Isolate.run`,
`Isolate.spawn`, a long-lived worker, and a lab that shows what an isolate
group is.

Companion repo for the FlutterCon India 2026 talk
**"One Isolate, Multiple Threads: Understanding Concurrency in Flutter"**.

Most screens have two buttons that run the **same work**:

- **Main isolate**: the spinner freezes. This is the jank you want to avoid.
- **Background isolate**: the spinner keeps turning.

## The scenarios

| Screen | API | Why this API |
| --- | --- | --- |
| Large API response | `compute()` | One function, one argument, one result. Flutter's helper; on the web it still runs (on the main thread). |
| Photo filter | `Isolate.run()` | Resize, filter and compress a photo before upload. One job, one result. |
| Lottie bundle | `Isolate.run()` | Unzip and validate 150 bundled animations at startup. |
| Merge audio clips | `Isolate.run()` | Join recordings with crossfades, mix in music, normalise, write a WAV. |
| Large file checksum | `Isolate.spawn()` + ports | SHA-256 of a big file with **progress updates** and a **Cancel** button. `Isolate.run` can only return once, at the end. |
| Gallery thumbnails | Long-lived isolate | One worker serves every thumbnail request while you scroll and **keeps a cache**. Starting an isolate per tile would pay the start-up cost every time. |
| Isolate group lab | Isolate groups | Measures what is copied, shared and handed over between isolates in one group. |

### Which one do I use?

```
Is the work just waiting (network, files, timers)?   -> just await it
Is it short Dart work (a few ms)?                    -> leave it on the main isolate
Long Dart work, once, one result?                    -> Isolate.run (or compute)
Long work with progress, cancel, or many requests?   -> Isolate.spawn + ports
Long work that keeps state between requests?         -> a long-lived worker
```

## Good practices shown in the code

1. **Keep isolate work in plain top-level functions.** `parseFeed`,
   `processPhoto`, `mergeClips` and friends take data and return data. No
   widgets, no `BuildContext`, no `this`. They are easy to test, too.
2. **Create `Isolate.run` closures outside your widgets.** Every screen calls a
   helper like `processPhotoInBackground(job)`. See the gotcha below.
3. **Send paths, not bytes.** A file path is a `String`, and immutable objects
   like Strings are shared, not copied. The isolate reads the file itself with
   `dart:io`.
4. **Send back small results.** The audio isolate writes the WAV file and
   returns its path and a 120-value waveform, not millions of samples.
5. **Call plugins on the main isolate.** `path_provider` and `rootBundle` run
   on the main isolate; only their results (a path, the bytes) go to the
   isolate. Plugins *can* be used in background isolates with
   `BackgroundIsolateBinaryMessenger`; see the Flutter docs link below.
6. **Do not use an isolate just to show an image.** Flutter already decodes
   images for display off the main isolate. Use `cacheWidth` to decode a big
   photo at the size you show it. Isolates are for the pixel work you write.
7. **Always stop what you spawn.** `FileHasher.cancel()` and
   `ThumbnailWorker.dispose()` kill their isolates; the pages call them from
   `dispose()`.
8. **Match replies to requests.** The thumbnail worker tags each request with
   an id and completes the matching `Completer`.
9. **Do not flood the main isolate.** The hasher reports progress every 8 MB,
   not every chunk.
10. **Errors come back to `await`.** An exception thrown inside `Isolate.run`
    is rethrown where you awaited it (see the photo page's `on FormatException`).

## The gotcha we hit while building this

The first version called `Isolate.run(() => processPhoto(job))` inside a
`State` method. It failed with:

```
Invalid argument(s): Illegal argument in isolate message
  <- _element in Instance of '_PhotoPageState'
  ...
```

The closure only used `job`, but it was created inside another closure in the
`State`. The Dart VM captured the surrounding context, including `this` (the
`State`), and through it the widget tree, which holds an `AnimationController`
that cannot be sent. The `SendPort.send` docs warn about this: closures "can
currently capture more state than they need".

The fix: create the closure in a top-level function, where it can only see
that function's parameters:

```dart
Future<ProcessedPhoto> processPhotoInBackground(PhotoJob job) =>
    Isolate.run(() => processPhoto(job));
```

`compute(parseFeed, body)` never had this problem: it takes a function and a
value, not a closure. `test/pages_test.dart` taps the real buttons so this bug
cannot come back.

## The isolate group lab, in one paragraph

Your main isolate and every isolate it starts with `Isolate.spawn` (and so
`Isolate.run` and `compute`) are in one **isolate group**. The VM shares the
program code and keeps all their objects in one heap, but that is an
implementation detail: an isolate still cannot reach another isolate's
objects, and top-level variables are per isolate (experiment 1). What the
group makes cheap is visible (experiments 2 and 3): Strings are sent by
reference, `TransferableTypedData` moves bytes in constant time (after one
copy to create it), and `Isolate.exit`, used by `Isolate.run` and `compute`,
hands a result over without copying. `Isolate.exit` only works within one
group.

Measured once on an Android emulator in profile mode (your numbers will differ):

| Sent from main to a worker | Main isolate blocked |
| --- | --- |
| 500,000 objects | 43 ms (copied) |
| 64 MB `Uint8List` | 53 ms (copied) |
| 64 MB `String` | 0.00 ms (shared) |
| 64 MB `TransferableTypedData` | 1.8 ms (moved) |

## Running it

```sh
flutter pub get
flutter run --profile     # on a real device for honest timings
flutter test
```

The demo media is generated, so the repo contains no third-party files. To
regenerate it:

```sh
dart run tool/generate_assets.dart
```

## Project layout

```
lib/
  main.dart                    home screen with the list of scenarios
  common/scenario_page.dart    shared screen: spinner, two buttons, status
  scenarios/
    json_feed/                 compute
    photo_filter/              Isolate.run
    lottie_bundle/             Isolate.run
    audio_merge/               Isolate.run
    file_hash/                 Isolate.spawn + progress + cancel
    thumbnail_worker/          long-lived worker
    isolate_group/             isolate group lab
test/
  scenarios_test.dart          logic, run through real isolates
  pages_test.dart              taps "Background isolate" on real pages
tool/generate_assets.dart      makes assets/sample_photo.jpg and the Lottie zip
```

Each scenario has a `*_logic.dart` (pure Dart, isolate-safe) and a
`*_page.dart` (the UI).

## Further reading

- [Concurrency in Dart](https://dart.dev/language/concurrency)
- [Isolates (Dart)](https://dart.dev/language/isolates)
- [Concurrency and isolates (Flutter)](https://docs.flutter.dev/perf/isolates),
  including plugins in background isolates
- [`SendPort.send`](https://api.dart.dev/dart-isolate/SendPort/send.html): what
  can be sent, what is copied or shared
- [`Isolate.exit`](https://api.dart.dev/dart-isolate/Isolate/exit.html) and
  [`TransferableTypedData`](https://api.dart.dev/dart-isolate/TransferableTypedData-class.html)
- [Dart VM runtime docs](https://github.com/dart-lang/sdk/blob/main/runtime/docs/README.md):
  isolates, isolate groups and threads

Built with Flutter 3.47.5 and Dart 3.13.4.

## License

[MIT](LICENSE)
