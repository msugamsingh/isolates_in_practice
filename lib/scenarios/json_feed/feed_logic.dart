import 'dart:isolate';
import 'dart:convert';
import 'dart:math';

/// One post in a social feed.
class Post {
  const Post({
    required this.id,
    required this.author,
    required this.text,
    required this.likes,
    required this.tags,
  });

  factory Post.fromJson(Map<String, dynamic> json) => Post(
    id: json['id'] as int,
    author: json['author'] as String,
    text: json['text'] as String,
    likes: json['likes'] as int,
    tags: (json['tags'] as List).cast<String>(),
  );

  final int id;
  final String author;
  final String text;
  final int likes;
  final List<String> tags;
}

/// Turns a raw API response into posts, most liked first.
///
/// This is a plain top-level function: no `this`, no widgets, no plugins.
/// That is what makes it safe to hand to `compute` or `Isolate.run`.
List<Post> parseFeed(String body) {
  final raw = jsonDecode(body) as List<dynamic>;
  final posts = [
    for (final item in raw) Post.fromJson(item as Map<String, dynamic>),
  ];
  posts.sort((a, b) => b.likes.compareTo(a.likes));
  return posts;
}

/// Builds a fake API response with [count] posts (about 230 bytes each).
///
/// In a real app this string comes from `http.get(...)`. Building it is
/// heavy too, so the page builds it in an isolate as well.
String buildFakeFeedJson(int count) {
  final random = Random(7);
  const words = [
    'flutter',
    'dart',
    'isolate',
    'async',
    'widget',
    'frame',
    'thread',
    'event',
    'loop',
    'raster',
    'build',
    'layout',
    'paint',
    'ship',
    'today',
  ];
  String sentence(int n) =>
      List.generate(n, (_) => words[random.nextInt(words.length)]).join(' ');
  return jsonEncode([
    for (var i = 0; i < count; i++)
      {
        'id': i,
        'author': 'user_${random.nextInt(50000)}',
        'text': sentence(20),
        'likes': random.nextInt(100000),
        'tags': [
          for (var t = 0; t < 3; t++) words[random.nextInt(words.length)],
        ],
      },
  ]);
}

// Why a top-level helper instead of calling Isolate.run in the widget?
// A closure can capture more than the variables it uses: the Dart VM keeps
// the whole surrounding context. A closure created inside a State method can
// end up holding `this`, and with it the widget tree, which cannot be sent
// (we hit exactly this: "Illegal argument in isolate message"). A closure
// created here can only see this function's parameters.
Future<String> buildFakeFeedJsonInBackground(int count) =>
    Isolate.run(() => buildFakeFeedJson(count));
