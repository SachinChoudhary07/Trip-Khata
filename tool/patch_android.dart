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
    'android.permission.READ_CONTACTS',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.VIBRATE',
  ];
  for (final p in perms) {
    if (!xml.contains(p)) {
      xml = xml.replaceFirst('<application', '<uses-permission android:name="$p" />\n    <application');
    }
  }
  const receivers = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>''';
  if (!xml.contains('ScheduledNotificationReceiver')) {
    xml = xml.replaceFirst('</application>', '$receivers\n    </application>');
  }
  xml = xml.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="TripKhata"');
  f.writeAsStringSync(xml);
  _patchGradle();
  stdout.writeln('AndroidManifest.xml patched for UPI and speech.');
}

/// flutter_local_notifications needs core library desugaring.
void _patchGradle() {
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  final f = kts.existsSync() ? kts : groovy;
  if (!f.existsSync()) return;
  var g = f.readAsStringSync();
  if (g.contains('desugar_jdk_libs')) return;
  final isKts = f.path.endsWith('.kts');
  g = g.replaceFirst(
    'compileOptions {',
    isKts ? 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true' : 'compileOptions {\n        coreLibraryDesugaringEnabled true',
  );
  g += isKts
      ? '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
      : "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n";
  f.writeAsStringSync(g);
  stdout.writeln('Enabled core library desugaring in ${f.path}.');
}
