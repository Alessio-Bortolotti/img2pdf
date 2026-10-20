/// Modalità dimostrativa, attiva solo con `--dart-define=DEMO=true`
/// (usata per generare gli screenshot della build web; mai nell'APK).
const bool kDemo = bool.fromEnvironment('DEMO');

/// Schermata da aprire in demo: `?screen=menu|editor|pdf` nell'URL.
String? demoScreen() {
  if (!kDemo) return null;
  return Uri.base.queryParameters['screen'];
}

/// Scheda dell'editor da aprire in demo: `?tab=0..4`.
int demoTab() => int.tryParse(Uri.base.queryParameters['tab'] ?? '') ?? 0;
