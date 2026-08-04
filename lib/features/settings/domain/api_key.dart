/// API credentials, as `ApiKeyResource` publishes them.
///
/// The raw secret is deliberately absent from [ApiKey]: the server puts it in
/// exactly one response — the 201 from `POST /api-keys` — and never stores it in
/// a retrievable form. [MintedApiKey] is that one response, and it is the only
/// type in the app that ever carries a plaintext key. Keeping the two apart is
/// what makes it impossible for a list screen to leak one by accident.
///
/// `masked_key` is nullable on the wire (the resource guards on the model type),
/// so a mask is rebuilt from `last_four` rather than printing "null" at the one
/// place a user looks to identify which key is which.
library;

import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

@immutable
class ApiKey {
  const ApiKey({
    required this.id,
    required this.name,
    required this.maskedKey,
    required this.environment,
    this.lastFour,
    this.scopes = const <String>[],
    this.createdByName,
    this.isActive = true,
    this.lastUsedAt,
    this.lastUsedIp,
    this.expiresAt,
    this.revokedAt,
    this.createdAt,
  });

  factory ApiKey.fromJson(Map<String, dynamic> json) {
    final String? lastFour = J.str(json['last_four']);
    final String environment = J.strOr(json['environment'], environmentLive);

    return ApiKey(
      id: J.intOr(json['id'], 0),
      name: J.strOr(json['name'], ''),
      // The mask is display-only; rebuilding it locally when the server sent
      // null keeps the row identifiable without ever needing the secret.
      maskedKey: J.str(json['masked_key']) ?? _mask(environment, lastFour),
      environment: environment,
      lastFour: lastFour,
      scopes: J.strings(json['scopes']),
      createdByName: J.str(J.map(json['created_by'])['name']),
      isActive: J.boolOr(json['is_active'], fallback: true),
      lastUsedAt: J.date(json['last_used_at']),
      lastUsedIp: J.str(json['last_used_ip']),
      expiresAt: J.date(json['expires_at']),
      revokedAt: J.date(json['revoked_at']),
      createdAt: J.date(json['created_at']),
    );
  }

  static const String environmentLive = 'live';
  static const String environmentTest = 'test';

  final int id;
  final String name;

  /// Safe for display: `sk_live_••••••••3f7a`.
  final String maskedKey;

  /// `live` or `test`.
  final String environment;

  final String? lastFour;
  final List<String> scopes;

  /// Who minted it. Null when the account that created it has been removed.
  final String? createdByName;

  /// The server's own verdict — false once revoked or expired.
  final bool isActive;

  final DateTime? lastUsedAt;
  final String? lastUsedIp;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final DateTime? createdAt;

  bool get isTest => environment == environmentTest;

  /// Revoked keys are kept, never deleted, so the audit trail of which key
  /// submitted which document survives. They are drawn greyed out.
  bool get isRevoked => revokedAt != null;

  bool get hasBeenUsed => lastUsedAt != null;

  static String _mask(String environment, String? lastFour) {
    final String prefix =
        environment == environmentTest ? 'sk_test' : 'sk_live';
    return '${prefix}_${'•' * 8}${lastFour ?? ''}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiKey &&
          other.id == id &&
          other.name == name &&
          other.maskedKey == maskedKey &&
          other.environment == environment &&
          other.lastFour == lastFour &&
          listEquals(other.scopes, scopes) &&
          other.createdByName == createdByName &&
          other.isActive == isActive &&
          other.lastUsedAt == lastUsedAt &&
          other.lastUsedIp == lastUsedIp &&
          other.expiresAt == expiresAt &&
          other.revokedAt == revokedAt &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        maskedKey,
        environment,
        lastFour,
        Object.hashAll(scopes),
        createdByName,
        isActive,
        lastUsedAt,
        lastUsedIp,
        expiresAt,
        revokedAt,
        createdAt,
      );

  @override
  String toString() => 'ApiKey($id, $maskedKey)';
}

/// A freshly minted key plus its one and only plaintext.
///
/// Held for exactly as long as the reveal sheet is on screen and never written
/// anywhere — not to preferences, not to the keychain, not to the log.
@immutable
class MintedApiKey {
  const MintedApiKey({required this.key, required this.plainKey});

  factory MintedApiKey.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> root =
        J.map(json['data']).isEmpty ? json : J.map(json['data']);

    return MintedApiKey(
      key: ApiKey.fromJson(J.map(root['key'])),
      plainKey: J.strOr(root['plain_key'], ''),
    );
  }

  final ApiKey key;
  final String plainKey;

  bool get hasPlainKey => plainKey.isNotEmpty;

  @override
  String toString() => 'MintedApiKey(${key.id})';
}

/// The allowance snapshot `ApiKeyController::index` sends beside the keys.
///
/// Without it the screen lists credentials but cannot answer the only question
/// anyone actually has, which is how much quota is left on them.
@immutable
class ApiUsage {
  const ApiUsage({
    required this.includedInPlan,
    this.used,
    this.limit,
    this.remaining,
    this.resetsAt,
    this.trialRemaining,
  });

  factory ApiUsage.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> period = J.map(json['current_period']);
    final Map<String, dynamic> trial = J.map(json['trial']);

    return ApiUsage(
      includedInPlan: J.boolOr(json['api_included_in_plan']),
      used: J.intOrNull(period['used']),
      limit: J.intOrNull(period['limit']),
      remaining: J.intOrNull(period['remaining']),
      resetsAt: J.date(period['resets_at']),
      trialRemaining: J.intOrNull(trial['remaining']),
    );
  }

  final bool includedInPlan;
  final int? used;
  final int? limit;
  final int? remaining;
  final DateTime? resetsAt;

  /// What is left of the free trial allowance for workspaces whose plan does
  /// not include API access.
  final int? trialRemaining;

  @override
  String toString() => 'ApiUsage($used/$limit)';
}

/// Everything `GET /api-keys` returns.
@immutable
class ApiKeyBundle {
  const ApiKeyBundle({required this.keys, this.usage});

  factory ApiKeyBundle.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> root =
        J.map(json['data']).isEmpty ? json : J.map(json['data']);
    final Map<String, dynamic> usage = J.map(root['usage']);

    return ApiKeyBundle(
      keys: J
          .list(root['keys'])
          .map(ApiKey.fromJson)
          .toList(growable: false),
      usage: usage.isEmpty ? null : ApiUsage.fromJson(usage),
    );
  }

  static const ApiKeyBundle empty = ApiKeyBundle(keys: <ApiKey>[]);

  final List<ApiKey> keys;
  final ApiUsage? usage;

  bool get isEmpty => keys.isEmpty;

  /// Active keys first, then revoked ones, newest first within each group —
  /// the order a person scanning for "the key my server uses" needs.
  List<ApiKey> get sorted {
    final List<ApiKey> out = List<ApiKey>.of(keys);
    out.sort((ApiKey a, ApiKey b) {
      if (a.isRevoked != b.isRevoked) {
        return a.isRevoked ? 1 : -1;
      }
      final DateTime? aAt = a.createdAt;
      final DateTime? bAt = b.createdAt;
      if (aAt == null || bAt == null) {
        return b.id.compareTo(a.id);
      }
      return bAt.compareTo(aAt);
    });
    return List<ApiKey>.unmodifiable(out);
  }

  @override
  String toString() => 'ApiKeyBundle(${keys.length} keys)';
}
