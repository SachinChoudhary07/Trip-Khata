import 'package:flutter_test/flutter_test.dart';
import 'package:tripkhata/features/cloud/invite_links.dart';

void main() {
  group('InviteLink', () {
    test('member link round-trips', () {
      const link = InviteLink(code: 'AB12CD', memberId: 'm-1');
      final uri = link.toUri();
      expect(uri.toString(), 'https://sachinchoudhary07.github.io/Trip-Khata/join/?c=AB12CD&m=m-1');
      final back = InviteLink.parse(uri)!;
      expect(back.code, 'AB12CD');
      expect(back.memberId, 'm-1');
      expect(back.route, '/join?c=AB12CD&m=m-1');
    });

    test('group link has no member', () {
      final back = InviteLink.parse(const InviteLink(code: 'XY34ZW').toUri())!;
      expect(back.memberId, isNull);
      expect(back.route, '/join?c=XY34ZW');
    });

    test('tidies the code and accepts the path without a trailing slash', () {
      final back = InviteLink.parse(Uri.parse('https://sachinchoudhary07.github.io/Trip-Khata/join?c=ab-12cd'))!;
      expect(back.code, 'AB12CD');
    });

    test('ignores other links', () {
      expect(InviteLink.parse(Uri.parse('https://sachinchoudhary07.github.io/Trip-Khata/privacy/?c=AB12CD')), isNull);
      expect(InviteLink.parse(Uri.parse('https://example.com/Trip-Khata/join/?c=AB12CD')), isNull);
      expect(InviteLink.parse(Uri.parse('https://sachinchoudhary07.github.io/Trip-Khata/join/?c=ABC')), isNull);
    });
  });
}
