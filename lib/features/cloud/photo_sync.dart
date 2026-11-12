import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../db/app_database.dart';
import '../trips/data/trip_repository.dart';
import 'cloud_sync.dart';

/// Moves trip photos to and from Cloudflare R2.
///
/// The bucket is private. The `tripkhataPhotoUrls` Cloud Function checks that
/// you're in the trip and hands out signed URLs that work for 15 minutes; the
/// files go straight between the phone and R2.
class PhotoSync {
  PhotoSync(this._cloud, this._repo);
  final CloudSync _cloud;
  final TripRepository _repo;

  static final _http = HttpClient()..connectionTimeout = const Duration(seconds: 20);

  bool _uploading = false;
  final Set<String> _fetching = {};

  bool get _ready => _cloud.available && _cloud.user != null;

  /// Where photos and thumbnails are kept on this phone.
  static Future<Directory> dir() async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/photos');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static String thumbKeyOf(String key) => key.endsWith('.jpg') ? '${key.substring(0, key.length - 4)}_t.jpg' : key;

  Future<Map<String, dynamic>> _urls(
    String tripId, {
    List<Map<String, Object>> uploads = const [],
    List<String> downloads = const [],
  }) async {
    final res = await FirebaseFunctions.instanceFor(region: CloudConfig.functionsRegion)
        .httpsCallable('tripkhataPhotoUrls')
        .call<dynamic>({'tripId': tripId, 'uploads': uploads, 'downloads': downloads});
    return _map(res.data);
  }

  static Map<String, dynamic> _map(Object? v) =>
      v is Map ? v.map((k, val) => MapEntry(k.toString(), val is Map ? _map(val) : val)) : <String, dynamic>{};

  static Future<void> _put(String url, File file) async {
    final bytes = await file.readAsBytes();
    final req = await _http.putUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.contentTypeHeader, 'image/jpeg');
    req.contentLength = bytes.length; // signed into the URL
    req.add(bytes);
    final res = await req.close().timeout(const Duration(minutes: 2));
    await res.drain<void>();
    if (res.statusCode < 200 || res.statusCode >= 300) throw HttpException('Upload failed (${res.statusCode})');
  }

  static Future<void> _get(String url, File dest) async {
    final req = await _http.getUrl(Uri.parse(url));
    final res = await req.close().timeout(const Duration(minutes: 2));
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('Download failed (${res.statusCode})');
    }
    final part = File('${dest.path}.part');
    await res.pipe(part.openWrite());
    await part.rename(dest.path);
  }

  /// Uploads photos of shared trips that are still only on this phone.
  /// Safe to call any time; photos that fail are tried again next time.
  Future<void> uploadPending() async {
    if (!_ready || _uploading) return;
    _uploading = true;
    final uid = _cloud.user!.uid;
    try {
      final pending = await _repo.pendingPhotoUploads();
      final byTrip = <String, List<TripPhoto>>{};
      for (final p in pending) {
        if (p.localPath == null || p.thumbPath == null) continue;
        if (!File(p.localPath!).existsSync() || !File(p.thumbPath!).existsSync()) continue;
        byTrip.putIfAbsent(p.tripId, () => []).add(p);
      }
      for (final entry in byTrip.entries) {
        for (var i = 0; i < entry.value.length; i += 10) {
          final chunk = entry.value.skip(i).take(10).toList();
          Map<String, dynamic> urls;
          try {
            urls = _map((await _urls(entry.key, uploads: [
              for (final p in chunk)
                {
                  'id': p.id,
                  'bytes': File(p.localPath!).lengthSync(),
                  'thumbBytes': File(p.thumbPath!).lengthSync(),
                },
            ]))['uploads']);
          } catch (e) {
            debugPrint('Photo upload URLs failed: $e');
            break; // offline or not allowed: try this trip again later
          }
          for (final p in chunk) {
            final u = urls[p.id];
            if (u is! Map) continue;
            try {
              await _put(u['full'] as String, File(p.localPath!));
              await _put(u['thumb'] as String, File(p.thumbPath!));
              await _repo.setPhotoUploaded(p.id, u['key'] as String, uid);
            } catch (e) {
              debugPrint('Photo upload failed: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Photo upload failed: $e');
    } finally {
      _uploading = false;
    }
  }

  /// Downloads grid thumbnails of friends' photos that aren't on this phone.
  Future<void> fetchThumbs(String tripId, List<TripPhoto> photos) async {
    if (!_ready) return;
    final need = photos
        .where((p) =>
            p.remoteKey != null &&
            (p.thumbPath == null || !File(p.thumbPath!).existsSync()) &&
            !_fetching.contains('t:${p.id}'))
        .toList();
    if (need.isEmpty) return;
    for (final p in need) {
      _fetching.add('t:${p.id}');
    }
    try {
      final d = await dir();
      for (var i = 0; i < need.length; i += 50) {
        final chunk = need.skip(i).take(50).toList();
        final urls = _map((await _urls(tripId, downloads: [for (final p in chunk) thumbKeyOf(p.remoteKey!)]))['downloads']);
        await Future.wait(chunk.map((p) async {
          final url = urls[thumbKeyOf(p.remoteKey!)];
          if (url is! String) return;
          try {
            final dest = File('${d.path}/${p.id}_t.jpg');
            await _get(url, dest);
            await _repo.setPhotoFiles(p.id, thumbPath: dest.path);
          } catch (e) {
            debugPrint('Thumbnail download failed: $e');
          }
        }));
      }
    } catch (e) {
      debugPrint('Thumbnail URLs failed: $e');
    } finally {
      for (final p in need) {
        _fetching.remove('t:${p.id}');
      }
    }
  }

  /// Makes sure the full photos are on this phone and returns their paths
  /// (same order; null for any that couldn't be fetched).
  Future<List<String?>> fetchFull(String tripId, List<TripPhoto> photos) async {
    final out = List<String?>.filled(photos.length, null);
    final missing = <int>[];
    for (var i = 0; i < photos.length; i++) {
      final path = photos[i].localPath;
      if (path != null && File(path).existsSync()) {
        out[i] = path;
      } else if (photos[i].remoteKey != null) {
        missing.add(i);
      }
    }
    if (missing.isEmpty || !_ready) return out;
    final d = await dir();
    for (var s = 0; s < missing.length; s += 50) {
      final idx = missing.skip(s).take(50).toList();
      Map<String, dynamic> urls;
      try {
        urls = _map((await _urls(tripId, downloads: [for (final i in idx) photos[i].remoteKey!]))['downloads']);
      } catch (e) {
        debugPrint('Photo URLs failed: $e');
        break;
      }
      // A few at a time: full photos are a few hundred KB each.
      for (var k = 0; k < idx.length; k += 4) {
        await Future.wait(idx.skip(k).take(4).map((i) async {
          final p = photos[i];
          final url = urls[p.remoteKey!];
          if (url is! String) return;
          try {
            final dest = File('${d.path}/${p.id}.jpg');
            await _get(url, dest);
            await _repo.setPhotoFiles(p.id, localPath: dest.path);
            out[i] = dest.path;
          } catch (e) {
            debugPrint('Photo download failed: $e');
          }
        }));
      }
    }
    return out;
  }
}
