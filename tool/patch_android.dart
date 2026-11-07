// Adds the UPI intent query to AndroidManifest.xml so url_launcher can open
// upi:// links on Android 11+. Safe to run more than once.
import 'dart:io';

void main() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) {
    stderr.writeln('Run `flutter create --platforms=android .` first.');
    exit(1);
  }
  var xml = f.readAsStringSync();

  const upi = '''
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="upi" />
        </intent>
        <intent>
            <action android:name="android.speech.RecognitionService" />
        </intent>''';
  if (xml.contains('android.speech.RecognitionService')) {
    // queries already added
  } else if (xml.contains('<queries>')) {
    xml = xml.replaceFirst('<queries>', '<queries>\n$upi');
  } else {
    xml = xml.replaceFirst('</manifest>', '    <queries>\n$upi\n    </queries>\n</manifest>');
  }
  const perms = [
    'android.permission.INTERNET',
    'android.permission.RECORD_AUDIO',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
  ];
  for (final p in perms) {
    if (!xml.contains(p)) {
      xml = xml.replaceFirst('<application', '<uses-permission android:name="$p" />\n    <application');
    }
  }
  f.writeAsStringSync(xml);
  stdout.writeln('AndroidManifest.xml patched for UPI and speech.');
}
