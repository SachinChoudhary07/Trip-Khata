import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Longest side of a saved photo, and JPEG quality. ~300-600 KB a photo,
/// so the free 10 GB of R2 holds tens of thousands of them.
const kPhotoMaxSide = 2048;
const kPhotoQuality = 80;

/// Shortest side of the grid thumbnail (~30 KB).
const kThumbSide = 480;
const kThumbQuality = 70;

class PreparedPhoto {
  const PreparedPhoto(this.full, this.thumb, this.width, this.height);
  final Uint8List full;
  final Uint8List thumb;
  final int width;
  final int height;
}

/// Turns a picked image into a compressed JPEG and a thumbnail: applies the
/// camera's rotation, scales down, and drops EXIF (so no GPS location is
/// shared). Returns null if the file isn't an image we can read.
/// Runs in the calling isolate; use [preparePhotoFile] from the UI.
PreparedPhoto? preparePhoto(Uint8List data) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(data);
  } catch (_) {
    return null; // corrupt or unsupported file
  }
  if (decoded == null) return null;
  var im = img.bakeOrientation(decoded);
  if (math.max(im.width, im.height) > kPhotoMaxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: kPhotoMaxSide, interpolation: img.Interpolation.average)
        : img.copyResize(im, height: kPhotoMaxSide, interpolation: img.Interpolation.average);
  }
  var thumb = im;
  if (math.min(im.width, im.height) > kThumbSide) {
    thumb = im.width <= im.height
        ? img.copyResize(im, width: kThumbSide, interpolation: img.Interpolation.average)
        : img.copyResize(im, height: kThumbSide, interpolation: img.Interpolation.average);
  }
  return PreparedPhoto(
    img.encodeJpg(im, quality: kPhotoQuality),
    img.encodeJpg(thumb, quality: kThumbQuality),
    im.width,
    im.height,
  );
}

/// Reads [source], prepares it off the UI thread and writes the photo and
/// thumbnail into [dir] as `{id}.jpg` and `{id}_t.jpg`.
Future<({File full, File thumb, int width, int height})?> preparePhotoFile(
  String source,
  Directory dir,
  String id,
) async {
  final data = await File(source).readAsBytes();
  final p = await Isolate.run(() => preparePhoto(data));
  if (p == null) return null;
  final full = File('${dir.path}/$id.jpg');
  final thumb = File('${dir.path}/${id}_t.jpg');
  await full.writeAsBytes(p.full, flush: true);
  await thumb.writeAsBytes(p.thumb, flush: true);
  return (full: full, thumb: thumb, width: p.width, height: p.height);
}
