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
  xml = _installWidget(xml);
  f.writeAsStringSync(xml);
  _patchGradle();
  _patchFirebaseGradle();
  stdout.writeln('AndroidManifest.xml patched for UPI and speech.');
}

/// flutter_local_notifications needs core library desugaring.
void _patchGradle() {
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  final f = kts.existsSync() ? kts : groovy;
  if (!f.existsSync()) return;
  var g = f.readAsStringSync();
  final isKts = f.path.endsWith('.kts');
  // Must match the Android app registered in Firebase (google-services.json).
  g = g.replaceFirst(RegExp(r'applicationId\s*=\s*"[^"]*"'), 'applicationId = "com.trip_khata.trip_khata"');
  g = g.replaceFirst(RegExp(r'applicationId\s+"[^"]*"'), 'applicationId "com.trip_khata.trip_khata"');
  // Firebase Auth / Firestore need Android 6.0+.
  g = g.replaceFirst(RegExp(r'minSdk\s*=\s*flutter\.minSdkVersion'), 'minSdk = 23');
  g = g.replaceFirst(RegExp(r'minSdkVersion\s+flutter\.minSdkVersion'), 'minSdkVersion 23');
  if (isKts && !g.contains('key.properties')) {
    // (signing block follows)
    // Stable release signing from android/key.properties (written by CI from
    // secrets). Without it the build falls back to the debug key.
    g = 'import java.io.FileInputStream\nimport java.util.Properties\n\n$g';
    g = g.replaceFirst('android {', '''val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) keystoreProperties.load(FileInputStream(keystorePropertiesFile))

android {
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }''');
    g = g.replaceFirst('signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")');
  }
  if (g.contains('desugar_jdk_libs')) {
    f.writeAsStringSync(g);
    return;
  }
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

/// Home screen widget: copies the provider and its resources from
/// tool/android_widget/ into android/, registers the receiver and lets
/// MainActivity receive widget taps. Safe to run more than once.
String _installWidget(String xml) {
  final main = Directory('android/app/src/main');
  final activity = main
      .listSync(recursive: true)
      .whereType<File>()
      .firstWhere((f) => f.path.endsWith('MainActivity.kt') || f.path.endsWith('MainActivity.java'));
  final pkg = RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(activity.readAsStringSync())!.group(1)!;

  final src = Directory('tool/android_widget');
  final kt = File('${src.path}/TripWidgetProvider.kt').readAsStringSync().replaceAll('__PACKAGE__', pkg);
  File('${activity.parent.path}/TripWidgetProvider.kt').writeAsStringSync(kt);
  for (final f in Directory('${src.path}/res').listSync(recursive: true).whereType<File>()) {
    final rel = f.path.substring('${src.path}/res/'.length);
    final out = File('${main.path}/res/$rel')..createSync(recursive: true);
    f.copySync(out.path);
  }

  if (!xml.contains('TripWidgetProvider')) {
    xml = xml.replaceFirst('</application>', '''
        <receiver android:name="$pkg.TripWidgetProvider" android:exported="true">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/trip_widget_info" />
        </receiver>
    </application>''');
  }
  if (!xml.contains('es.antonborri.home_widget.action.LAUNCH')) {
    // First </activity> is MainActivity in the generated manifest.
    xml = xml.replaceFirst('</activity>', '''    <intent-filter>
                <action android:name="es.antonborri.home_widget.action.LAUNCH" />
            </intent-filter>
        </activity>''');
  }
  stdout.writeln('Home screen widget installed ($pkg.TripWidgetProvider).');
  return xml;
}

/// google-services.json (TripKhata's app only) plus the Google Services and
/// Crashlytics Gradle plugins. Crashlytics needs both at build time.
void _patchFirebaseGradle() {
  File('tool/android/google-services.json').copySync('android/app/google-services.json');

  final settingsKts = File('android/settings.gradle.kts');
  final settingsGroovy = File('android/settings.gradle');
  final settings = settingsKts.existsSync() ? settingsKts : settingsGroovy;
  var st = settings.readAsStringSync();
  if (!st.contains('com.google.gms.google-services')) {
    final kts = settings.path.endsWith('.kts');
    final lines = kts
        ? '    id("com.google.gms.google-services") version "4.4.2" apply false\n'
            '    id("com.google.firebase.crashlytics") version "3.0.2" apply false\n'
        : '    id "com.google.gms.google-services" version "4.4.2" apply false\n'
            '    id "com.google.firebase.crashlytics" version "3.0.2" apply false\n';
    st = st.replaceFirstMapped(
      RegExp(r'(id[ (]"dev\.flutter\.flutter-plugin-loader"\)?[^\n]*\n)'),
      (m) => '${m.group(1)}$lines',
    );
    settings.writeAsStringSync(st);
  }

  final appKts = File('android/app/build.gradle.kts');
  final app = appKts.existsSync() ? appKts : File('android/app/build.gradle');
  var g = app.readAsStringSync();
  if (!g.contains('com.google.gms.google-services')) {
    final kts = app.path.endsWith('.kts');
    final lines = kts
        ? '    id("com.google.gms.google-services")\n    id("com.google.firebase.crashlytics")\n'
        : '    id "com.google.gms.google-services"\n    id "com.google.firebase.crashlytics"\n';
    g = g.replaceFirstMapped(
      RegExp(r'(\n)(\s*id[ (]"dev\.flutter\.flutter-gradle-plugin")'),
      (m) => '${m.group(1)}$lines${m.group(2)}',
    );
    app.writeAsStringSync(g);
  }
  if (!st.contains('com.google.gms.google-services') || !g.contains('com.google.firebase.crashlytics')) {
    stderr.writeln('Could not add the Firebase Gradle plugins. Check settings.gradle and app/build.gradle.');
    exit(1);
  }
  stdout.writeln('Added google-services.json and the Google Services + Crashlytics Gradle plugins.');
}
