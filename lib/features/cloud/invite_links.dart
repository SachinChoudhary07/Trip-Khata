import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../../core/router/app_router.dart';

/// Invite links that open the app straight into "join this trip".
///
///   https://sachinchoudhary07.github.io/Trip-Khata/join/?c=AB12CD           whole group
///   https://sachinchoudhary07.github.io/Trip-Khata/join/?c=AB12CD&m=<id>    one member
///
/// The link is an Android App Link: the domain's /.well-known/assetlinks.json
/// lists this app, so a tap opens TripKhata directly. Without the app the same
/// URL shows a web page (docs/join/index.html) with the download link.
class InviteLink {
  const InviteLink({required this.code, this.memberId});

  final String code;

  /// The member this link was made for. Null for the group link.
  final String? memberId;

  static const host = 'sachinchoudhary07.github.io';
  static const path = '/Trip-Khata/join/';

  Uri toUri() => Uri.https(host, path, {'c': code, if (memberId != null) 'm': memberId!});

  @override
  String toString() => toUri().toString();

  /// Reads an invite out of an incoming link. Returns null for anything else.
  static InviteLink? parse(Uri uri) {
    if (uri.host.toLowerCase() != host) return null;
    final p = uri.path.toLowerCase();
    if (p != path.toLowerCase() && p != path.toLowerCase().substring(0, path.length - 1)) return null;
    final code = (uri.queryParameters['c'] ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (code.length != 6) return null;
    final m = uri.queryParameters['m']?.trim();
    return InviteLink(code: code, memberId: (m == null || m.isEmpty) ? null : m);
  }

  /// Route inside the app that handles the invite.
  String get route => Uri(path: '/join', queryParameters: {'c': code, if (memberId != null) 'm': memberId!}).toString();
}

/// Listens for invite links. A link that arrives before the home screen is
/// up (cold start, onboarding, sign-in) is held until [homeReady].
class DeepLinks {
  DeepLinks._();

  static InviteLink? _pending;
  static bool _home = false;
  static String? _last;
  static StreamSubscription<Uri>? _sub;

  static void init() {
    if (_sub != null) return;
    try {
      // On app_links 6+ this stream also delivers the link that launched the app.
      _sub = AppLinks().uriLinkStream.listen(_handle, onError: (Object e) => debugPrint('deep link: $e'));
    } catch (e) {
      debugPrint('deep links unavailable: $e');
    }
  }

  static void _handle(Uri uri) {
    final invite = InviteLink.parse(uri);
    if (invite == null) return;
    // The same launch link can be delivered twice; open it once.
    final key = uri.toString();
    if (key == _last) return;
    _last = key;
    if (_home) {
      appRouter.push(invite.route);
    } else {
      _pending = invite;
    }
  }

  /// Called once the home screen is showing. Opens a held invite, if any.
  static void homeReady() {
    _home = true;
    final p = _pending;
    _pending = null;
    if (p != null) appRouter.push(p.route);
  }
}
