// Conditional export: web → dart:html canvas | mobile → video_thumbnail
export 'thumbnail_helper_stub.dart'
    if (dart.library.html) 'thumbnail_helper_web.dart'
    if (dart.library.io) 'thumbnail_helper_io.dart';
