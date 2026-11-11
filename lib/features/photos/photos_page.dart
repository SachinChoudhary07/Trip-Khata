import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../db/app_database.dart';
import '../cloud/cloud_sync.dart';
import '../cloud/photo_sync.dart';
import '../trips/data/trip_repository.dart';
import '../trips/presentation/trip_detail_cubit.dart';
import 'photo_processing.dart';

void _toast(BuildContext context, String m) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

/// Whether this photo was added by the person using this phone.
/// Only they can delete it (the Firestore rules say the same).
bool isMyPhoto(TripPhoto p, {String? myUid, String? myMemberId}) {
  if (p.uploaderUid != null) return p.uploaderUid == myUid;
  return p.memberId != null && p.memberId == myMemberId;
}

/// Saves photos to the phone's gallery (album "TripKhata"). Downloads any
/// that are only in the cloud first. Returns how many were saved.
Future<int> savePhotosToGallery(BuildContext context, String tripId, List<TripPhoto> photos) async {
  final cloud = context.read<CloudSync>();
  try {
    if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
      if (context.mounted) _toast(context, 'Allow TripKhata to save photos to your gallery.');
      return 0;
    }
  } catch (_) {}
  final paths = await cloud.photos.fetchFull(tripId, photos);
  var saved = 0;
  for (final path in paths) {
    if (path == null) continue;
    try {
      await Gal.putImage(path, album: 'TripKhata');
      saved++;
    } catch (e) {
      debugPrint('Save to gallery failed: $e');
    }
  }
  return saved;
}

/// Trip photos: everyone in a shared trip sees them; each person can delete
/// only the photos they added.
class PhotosPage extends StatelessWidget {
  const PhotosPage({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (c) => TripDetailCubit(c.read<TripRepository>(), tripId),
        child: _PhotosView(tripId: tripId),
      );
}

class _PhotosView extends StatefulWidget {
  const _PhotosView({required this.tripId});
  final String tripId;

  @override
  State<_PhotosView> createState() => _PhotosViewState();
}

class _PhotosViewState extends State<_PhotosView> {
  late final Stream<List<TripPhoto>> _photos = context.read<TripRepository>().watchPhotos(widget.tripId);
  final Set<String> _selected = {};
  bool _adding = false;
  String? _progress;

  bool get _selecting => _selected.isNotEmpty;

  Future<void> _add() async {
    final List<XFile> picked;
    try {
      // Native downscale first (fast, also turns HEIC into JPEG), then we
      // compress and make the thumbnail in Dart.
      picked = await ImagePicker().pickMultiImage(maxWidth: 2560, maxHeight: 2560, imageQuality: 92);
    } catch (e) {
      if (mounted) _toast(context, 'Couldn’t open your photos.');
      return;
    }
    if (picked.isEmpty || !mounted) return;
    final repo = context.read<TripRepository>();
    final cloud = context.read<CloudSync>();
    setState(() => _adding = true);
    var added = 0;
    var failed = 0;
    try {
      final dir = await PhotoSync.dir();
      for (var i = 0; i < picked.length; i++) {
        if (mounted) setState(() => _progress = 'Adding ${i + 1} of ${picked.length}…');
        final id = const Uuid().v4();
        try {
          final out = await preparePhotoFile(picked[i].path, dir, id);
          if (out == null) {
            failed++;
            continue;
          }
          await repo.addPhoto(
            id: id,
            tripId: widget.tripId,
            localPath: out.full.path,
            thumbPath: out.thumb.path,
            width: out.width,
            height: out.height,
            bytes: await out.full.length(),
          );
          added++;
        } catch (e) {
          debugPrint('Add photo failed: $e');
          failed++;
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _adding = false;
          _progress = null;
        });
      }
    }
    unawaited(cloud.photos.uploadPending());
    if (!mounted) return;
    if (failed > 0) {
      _toast(context, 'Added $added. $failed couldn’t be read.');
    } else if (added > 0) {
      _toast(context, added == 1 ? 'Photo added' : '$added photos added');
    }
  }

  Future<void> _download(List<TripPhoto> photos) async {
    setState(() => _progress = photos.length == 1 ? 'Saving photo…' : 'Saving ${photos.length} photos…');
    final saved = await savePhotosToGallery(context, widget.tripId, photos);
    if (!mounted) return;
    setState(() {
      _progress = null;
      _selected.clear();
    });
    if (saved == photos.length) {
      _toast(context, saved == 1 ? 'Saved to Gallery › TripKhata' : '$saved photos saved to Gallery › TripKhata');
    } else {
      _toast(context, 'Saved $saved of ${photos.length}. Check your internet and try again.');
    }
  }

  Future<void> _delete(List<TripPhoto> mine) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(mine.length == 1 ? 'Delete this photo?' : 'Delete ${mine.length} photos?'),
        content: const Text('They’ll be removed for everyone in the trip.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.owe),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = context.read<TripRepository>();
    for (final p in mine) {
      await repo.deletePhoto(p.id);
    }
    if (mounted) setState(_selected.clear);
  }

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudSync>();
    final s = context.watch<TripDetailCubit>().state;
    final shared = s.trip?.joinCode != null;
    final myUid = cloud.user?.uid;
    final myMemberId = s.me?.id;

    return StreamBuilder<List<TripPhoto>>(
      stream: _photos,
      builder: (context, snap) {
        final photos = snap.data ?? const <TripPhoto>[];
        if (shared && photos.isNotEmpty) unawaited(cloud.photos.fetchThumbs(widget.tripId, photos));
        _selected.removeWhere((id) => !photos.any((p) => p.id == id));
        final selected = photos.where((p) => _selected.contains(p.id)).toList();
        final mineSelected = selected.where((p) => isMyPhoto(p, myUid: myUid, myMemberId: myMemberId)).toList();

        return PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(_selected.clear);
          },
          child: Scaffold(
            backgroundColor: Colors.white,
            appBar: _selecting
                ? AppBar(
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
                    title: Text('${_selected.length} selected'),
                    actions: [
                      IconButton(
                        tooltip: 'Select all',
                        icon: const Icon(Icons.select_all),
                        onPressed: () => setState(() => _selected.addAll(photos.map((p) => p.id))),
                      ),
                      IconButton(
                        tooltip: 'Save to gallery',
                        icon: const Icon(Icons.download_outlined),
                        onPressed: _progress == null ? () => _download(selected) : null,
                      ),
                      IconButton(
                        tooltip: mineSelected.length == selected.length
                            ? 'Delete'
                            : 'You can delete only the photos you added',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: mineSelected.isEmpty || mineSelected.length != selected.length
                            ? null
                            : () => _delete(mineSelected),
                      ),
                    ],
                  )
                : AppBar(
                    leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
                    title: Text(photos.isEmpty ? 'Photos' : 'Photos · ${photos.length}'),
                    actions: [
                      if (photos.isNotEmpty)
                        IconButton(
                          tooltip: 'Save all to gallery',
                          icon: const Icon(Icons.download_outlined),
                          onPressed: _progress == null ? () => _download(photos) : null,
                        ),
                    ],
                  ),
            floatingActionButton: _selecting
                ? null
                : FloatingActionButton.extended(
                    onPressed: _adding ? null : _add,
                    icon: _adding
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(_adding ? 'Adding…' : 'Add photos'),
                  ),
            body: Column(children: [
              if (!shared)
                Container(
                  width: double.infinity,
                  color: AppColors.yellowSoft,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: const Text(
                    'Photos stay on this phone. Share the trip so everyone in it sees them.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              if (_progress != null) ...[
                const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_progress!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ),
              ],
              Expanded(
                child: photos.isEmpty
                    ? _Empty(loading: snap.connectionState == ConnectionState.waiting)
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(2, 2, 2, 96),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                        ),
                        itemCount: photos.length,
                        itemBuilder: (context, i) {
                          final p = photos[i];
                          return _Tile(
                            photo: p,
                            pending: shared && p.remoteKey == null,
                            selecting: _selecting,
                            selected: _selected.contains(p.id),
                            onTap: () {
                              if (_selecting) {
                                _toggle(p.id);
                              } else {
                                Navigator.of(context).push(MaterialPageRoute<void>(
                                  builder: (_) => BlocProvider.value(
                                    value: context.read<TripDetailCubit>(),
                                    child: PhotoViewerPage(tripId: widget.tripId, photos: photos, initial: i),
                                  ),
                                ));
                              }
                            },
                            onLongPress: () => _toggle(p.id),
                          );
                        },
                      ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.loading});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.photo_library_outlined, color: AppColors.primary, size: 30),
        ),
        const SizedBox(height: 14),
        const Text('No photos yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'Add the trip’s photos here. Everyone in the trip can see and save them.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, height: 1.45),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.photo,
    required this.pending,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final TripPhoto photo;
  final bool pending;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final path = photo.thumbPath ?? photo.localPath;
    final file = path == null ? null : File(path);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(fit: StackFit.expand, children: [
        Container(color: AppColors.lineSoft),
        if (file != null && file.existsSync())
          Image.file(
            file,
            fit: BoxFit.cover,
            cacheWidth: 360,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox(),
          ),
        if (selected) Container(color: AppColors.primary.withValues(alpha: 0.35)),
        if (selecting)
          Positioned(
            top: 6,
            right: 6,
            child: Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: Colors.white,
              size: 22,
              shadows: const [Shadow(blurRadius: 4, color: Colors.black45)],
            ),
          ),
        if (pending)
          const Positioned(
            left: 6,
            bottom: 6,
            child: Icon(Icons.cloud_upload_outlined,
                color: Colors.white, size: 18, shadows: [Shadow(blurRadius: 4, color: Colors.black54)]),
          ),
      ]),
    );
  }
}

/// Full-screen photos with swipe, pinch to zoom, save and (your own) delete.
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({super.key, required this.tripId, required this.photos, required this.initial});
  final String tripId;
  final List<TripPhoto> photos;
  final int initial;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;
  final Map<String, Future<String?>> _full = {};
  bool _saving = false;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<String?> _fullPath(TripPhoto p) => _full.putIfAbsent(
        p.id,
        () => context.read<CloudSync>().photos.fetchFull(widget.tripId, [p]).then((l) => l.first),
      );

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudSync>();
    final s = context.watch<TripDetailCubit>().state;
    final p = widget.photos[_i];
    final who = p.memberId == null ? null : s.member(p.memberId!)?.name;
    final mine = isMyPhoto(p, myUid: cloud.user?.uid, myMemberId: s.me?.id);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(mine ? 'You' : (who ?? 'Someone'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text(DateFormat('d MMM, h:mm a').format(p.createdAt),
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Save to gallery',
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download_outlined),
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    final n = await savePhotosToGallery(context, widget.tripId, [p]);
                    if (!mounted) return;
                    setState(() => _saving = false);
                    _toast(context, n == 1 ? 'Saved to Gallery › TripKhata' : 'Couldn’t save. Check your internet.');
                  },
          ),
          if (mine)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Delete this photo?'),
                    content: const Text('It’ll be removed for everyone in the trip.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                await context.read<TripRepository>().deletePhoto(p.id);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _i = i),
        itemBuilder: (context, i) {
          final ph = widget.photos[i];
          final thumb = ph.thumbPath ?? ph.localPath;
          return FutureBuilder<String?>(
            future: _fullPath(ph),
            builder: (context, snap) {
              final path = snap.data ?? thumb;
              final file = path == null ? null : File(path);
              return Stack(fit: StackFit.expand, children: [
                if (file != null && file.existsSync())
                  InteractiveViewer(
                    maxScale: 5,
                    child: Image.file(file, fit: BoxFit.contain, gaplessPlayback: true),
                  ),
                if (snap.connectionState != ConnectionState.done)
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
                if (snap.connectionState == ConnectionState.done && snap.data == null && thumb == null)
                  const Center(
                    child: Text('Couldn’t load this photo. Check your internet.', style: TextStyle(color: Colors.white70)),
                  ),
              ]);
            },
          );
        },
      ),
    );
  }
}
