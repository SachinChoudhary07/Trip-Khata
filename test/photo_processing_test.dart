import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tripkhata/features/photos/photo_processing.dart';

void main() {
  test('big photo is scaled to 2048px with a 480px thumbnail, both JPEG', () {
    final src = img.encodeJpg(img.Image(width: 3000, height: 1500), quality: 95);
    final p = preparePhoto(src)!;
    expect((p.width, p.height), (2048, 1024));
    final thumb = img.decodeJpg(p.thumb)!;
    expect(thumb.height, kThumbSide);
    expect(thumb.width, 960);
    expect(img.decodeJpg(p.full)!.width, 2048);
  });

  test('small photo keeps its size', () {
    final src = img.encodePng(img.Image(width: 400, height: 300));
    final p = preparePhoto(src)!;
    expect((p.width, p.height), (400, 300));
    expect(img.decodeJpg(p.full), isNotNull); // PNG in, JPEG out
  });

  test('not an image', () {
    expect(preparePhoto(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}
