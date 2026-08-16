/// KaiSecretInventory — Sadeq's actual credentials, and when each was rotated.
///
/// The registry in `lib/logic/secret_registry.dart` is the pure policy. This is
/// the list it operates on, plus the small amount of persistence needed to
/// remember when something was last rotated.
///
/// ── Still no values ─────────────────────────────────────────────────────────
///
/// Nothing here reads `lib/secrets.dart` or secure storage. It knows the NAMES
/// and the LOCATIONS, which is all a rotation panel needs. Fingerprints are
/// supplied by the caller that already legitimately holds a value, so this file
/// never has to.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../logic/secret_registry.dart';

class KaiSecretInventory {
  static const _prefsKey = 'kai_secret_rotations_v1';

  /// The credentials this app actually uses, discovered by reading the codebase
  /// rather than imagined.
  ///
  /// Firebase entries are marked `publicIdentifier`: a web/mobile API key
  /// identifies a project and is meant to ship in clients. The thing to audit
  /// there is `database.rules.json`, not the string — and saying so is what
  /// keeps the panel believable.
  static const catalogue = <KaiSecret>[
    KaiSecret(
      id: 'openai',
      label: 'OpenAI',
      provider: 'OpenAI',
      store: KaiSecretStore.sourceLocal,
      location: 'lib/secrets.dart · kOpenAIKey',
      consoleUrl: 'https://platform.openai.com/api-keys',
      note: 'Kai\'s voice. Rotating this stops every surface until replaced.',
    ),
    KaiSecret(
      id: 'anthropic',
      label: 'Anthropic',
      provider: 'Anthropic',
      store: KaiSecretStore.secureStorage,
      location: 'secure storage · anthropic_api_key',
      consoleUrl: 'https://console.anthropic.com/settings/keys',
    ),
    KaiSecret(
      id: 'elevenlabs',
      label: 'ElevenLabs',
      provider: 'ElevenLabs',
      store: KaiSecretStore.sourceLocal,
      location: 'lib/secrets.dart · kElevenLabsKey',
      consoleUrl: 'https://elevenlabs.io/app/settings/api-keys',
      note: 'Also duplicated in secure storage under two different keys.',
    ),
    KaiSecret(
      id: 'picovoice',
      label: 'Picovoice',
      provider: 'Picovoice',
      store: KaiSecretStore.sourceLocal,
      location: 'lib/secrets.dart · kPicovoiceKey',
      consoleUrl: 'https://console.picovoice.ai/',
      note: 'Compile-time only. Changing it needs an edit and a rebuild, not '
          'this screen — which is why it is listed rather than editable.',
    ),
    KaiSecret(
      id: 'google_api',
      label: 'Google API',
      provider: 'Google Cloud',
      store: KaiSecretStore.sourceLocal,
      location: 'lib/secrets.dart · kGoogleApiKey',
      consoleUrl: 'https://console.cloud.google.com/apis/credentials',
    ),
    KaiSecret(
      id: 'gumroad',
      label: 'Gumroad',
      provider: 'Gumroad',
      store: KaiSecretStore.secureStorage,
      location: 'secure storage · gumroad token',
      consoleUrl: 'https://app.gumroad.com/settings/advanced',
    ),
    KaiSecret(
      id: 'etsy',
      label: 'Etsy',
      provider: 'Etsy',
      store: KaiSecretStore.secureStorage,
      location: 'secure storage · etsy_api_key',
      consoleUrl: 'https://www.etsy.com/developers/your-apps',
      note: 'Has a setter but no field on the keys screen — set elsewhere.',
    ),
    KaiSecret(
      id: 'tavern_console_web',
      label: 'Tavern console (web)',
      provider: 'Firebase',
      store: KaiSecretStore.tracked,
      location: 'scripts/firebase/tavern_console.html',
      kind: KaiSecretKind.publicIdentifier,
      inGitHistory: true,
      consoleUrl: 'https://console.firebase.google.com/',
      note: 'Public by design. Audit database.rules.json, not the key. The '
          'untracked tavern_console/ holds a SECOND, different project key.',
    ),
    KaiSecret(
      id: 'firebase_app',
      label: 'Firebase app config',
      provider: 'Firebase',
      store: KaiSecretStore.tracked,
      location: 'lib/firebase_options.dart · google-services.json',
      kind: KaiSecretKind.publicIdentifier,
      inGitHistory: true,
      consoleUrl: 'https://console.firebase.google.com/',
      note: 'Ships in every client by design.',
    ),
  ];

  /// The ids this app can change from the keys screen.
  ///
  /// Everything else is compile-time or lives in a console, so the panel can
  /// report its age and link out but cannot record a rotation on its own. Being
  /// explicit about the difference is what stops the screen claiming credit for
  /// a key it never touched.
  static const editableIds = <String>{
    'openai',
    'anthropic',
    'elevenlabs',
    'google_api',
    'gumroad',
  };

  /// Rotation dates, keyed by secret id.
  ///
  /// Absent means never recorded, which the registry deliberately treats as its
  /// own state rather than as "old". Nothing is invented on first run: an empty
  /// map is the honest starting position for a project that has never rotated
  /// anything.
  static Future<Map<String, DateTime>> loadRotations() async {
    final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is String)
            entry.key.toString():
                DateTime.tryParse(entry.value as String) ?? DateTime(1970),
      }..removeWhere((_, v) => v.year == 1970);
    } catch (_) {
      // A corrupt record must not read as "everything is fresh". Returning
      // empty puts every secret back into neverRotated, which is loud and
      // correct.
      return {};
    }
  }

  static Future<void> recordRotation(String id, DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadRotations();
    current[id] = at;
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        for (final e in current.entries) e.key: e.value.toIso8601String(),
      }),
    );
  }

  /// The catalogue with recorded dates applied.
  static Future<KaiSecretRegistry> load() async {
    final rotations = await loadRotations();
    return KaiSecretRegistry([
      for (final s in catalogue)
        KaiSecret(
          id: s.id,
          label: s.label,
          provider: s.provider,
          store: s.store,
          location: s.location,
          kind: s.kind,
          consoleUrl: s.consoleUrl,
          lastRotated: rotations[s.id],
          fingerprint: s.fingerprint,
          // A recorded rotation clears the exposure flag: the committed value
          // no longer opens anything.
          inGitHistory: s.inGitHistory && !rotations.containsKey(s.id),
          note: s.note,
        ),
    ]);
  }
}
