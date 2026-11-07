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
  if (xml.contains('android:scheme="upi"')) {
    stdout.writeln('UPI query already present.');
    return;
  }
  const upi = '''
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="upi" />
        </intent>''';
  if (xml.contains('<queries>')) {
    xml = xml.replaceFirst('<queries>', '<queries>\n$upi');
  } else {
    xml = xml.replaceFirst('</manifest>', '    <queries>\n$upi\n    </queries>\n</manifest>');
  }
  if (!xml.contains('android.permission.RECORD_AUDIO')) {
    xml = xml.replaceFirst('<application',
        '<uses-permission android:name="android.permission.RECORD_AUDIO" />\n    <application');
  }
  f.writeAsStringSync(xml);
  stdout.writeln('AndroidManifest.xml patched for UPI.');
}
