/// The signed-in session, as every screen in the app sees it.
///
/// These five types are the only vocabulary shared between features: documents
/// asks a [Session] whether the workspace still has allowance, billing asks it
/// for the current [Entitlement], settings renders the [AppUser]. They are
/// parsed once from `GET /me`, which bundles user, company, plan and usage in a
/// single response precisely so a cold start costs one round trip.
///
/// Field names are taken verbatim from `UserResource`, `CompanyResource`,
/// `PlanResource` and `UsageResource`. Everything is read through [J] rather
/// than cast: the server promises never to drop a key, but a value can
/// legitimately be null, and one unexpected type must cost a single field, not
/// the whole launch.
library;

import 'package:flutter/foundation.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';

/// The person holding the phone.
///
/// `UserResource` also publishes `auth_provider` and `avatar_url`; both are
/// carried because settings hides the change-password screen for a Google
/// account and the dashboard draws the avatar.
@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.locale,
    this.role,
    this.emailVerified = false,
    this.emailVerifiedAt,
    this.avatarUrl,
    this.authProvider,
    this.companyId,
    this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final DateTime? verifiedAt = J.date(json['email_verified_at']);

    return AppUser(
      id: J.intOr(json['id'], 0),
      name: J.strOr(json['name'], ''),
      email: J.strOr(json['email'], ''),
      locale: J.str(json['locale']),
      role: J.str(json['role']),
      // The resource sends both; the timestamp is the fallback so an older
      // build of the server that only sent one of them still reads correctly.
      emailVerified: J.boolOr(
        json['email_verified'],
        fallback: verifiedAt != null,
      ),
      emailVerifiedAt: verifiedAt,
      avatarUrl: J.str(json['avatar_url']),
      authProvider: J.str(json['auth_provider']),
      companyId: J.intOrNull(json['company_id']),
      createdAt: J.date(json['created_at']),
    );
  }

  final int id;
  final String name;
  final String email;

  /// Interface language the account chose, e.g. `it`. Null means "never set".
  final String? locale;

  /// `owner`, `admin` or `employee` on the server.
  final String? role;

  final bool emailVerified;
  final DateTime? emailVerifiedAt;

  /// Google profile picture, when the account was created that way.
  final String? avatarUrl;

  /// `password` or `google`. Drives whether a password can be changed at all.
  final String? authProvider;

  final int? companyId;
  final DateTime? createdAt;

  /// What the greeting row addresses the user by. Falls back to the local part
  /// of the email so the dashboard never says "Good morning, ".
  String get firstName {
    final String trimmed = name.trim();
    if (trimmed.isNotEmpty) {
      return trimmed.split(RegExp(r'\s+')).first;
    }
    final int at = email.indexOf('@');
    if (at > 0) {
      return email.substring(0, at);
    }
    return S.greetingFallback;
  }

  /// One or two letters for the avatar placeholder.
  String get initials {
    final List<String> words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .toList(growable: false);

    if (words.isEmpty) {
      return email.isEmpty ? '?' : email.substring(0, 1).toUpperCase();
    }
    if (words.length == 1) {
      return words.first.substring(0, 1).toUpperCase();
    }
    return (words.first.substring(0, 1) + words[1].substring(0, 1))
        .toUpperCase();
  }

  bool get isOwner => role == 'owner';

  /// A Google account has a password row, but it is random — offering to change
  /// it would be offering something that cannot be used.
  bool get canChangePassword => authProvider != 'google';

  AppUser copyWith({
    int? id,
    String? name,
    String? email,
    String? locale,
    String? role,
    bool? emailVerified,
    DateTime? emailVerifiedAt,
    String? avatarUrl,
    String? authProvider,
    int? companyId,
    DateTime? createdAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      locale: locale ?? this.locale,
      role: role ?? this.role,
      emailVerified: emailVerified ?? this.emailVerified,
      emailVerifiedAt: emailVerifiedAt ?? this.emailVerifiedAt,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      authProvider: authProvider ?? this.authProvider,
      companyId: companyId ?? this.companyId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUser &&
          other.id == id &&
          other.name == name &&
          other.email == email &&
          other.locale == locale &&
          other.role == role &&
          other.emailVerified == emailVerified &&
          other.emailVerifiedAt == emailVerifiedAt &&
          other.avatarUrl == avatarUrl &&
          other.authProvider == authProvider &&
          other.companyId == companyId &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        email,
        locale,
        role,
        emailVerified,
        emailVerifiedAt,
        avatarUrl,
        authProvider,
        companyId,
        createdAt,
      );

  @override
  String toString() => 'AppUser($id, $email)';
}

/// The workspace (a `Company` on the server) the account belongs to.
///
/// Team management stays on the web, so the only team information here is
/// [memberCount] — exactly what `CompanyResource` publishes.
@immutable
class Workspace {
  const Workspace({
    required this.id,
    required this.name,
    required this.plan,
    this.planName,
    this.memberCount = 0,
    this.usagePeriodEndsAt,
    this.subscriptionStatus,
    this.onPaidPlan = false,
    this.trialEndsAt,
    this.renewsAt,
  });

  /// [planName] comes from the sibling `plan` block of `GET /me` (the plan
  /// catalogue's display name) and [usagePeriodEndsAt] from the `usage` block,
  /// because neither lives on the company payload itself.
  factory Workspace.fromJson(
    Map<String, dynamic> json, {
    String? planName,
    DateTime? usagePeriodEndsAt,
  }) {
    return Workspace(
      id: J.intOr(json['id'], 0),
      name: J.strOr(json['name'], ''),
      plan: J.strOr(json['plan'], 'free'),
      planName: planName,
      memberCount: J.intOr(json['member_count'], 0),
      usagePeriodEndsAt: usagePeriodEndsAt,
      subscriptionStatus: J.str(json['subscription_status']),
      onPaidPlan: J.boolOr(json['on_paid_plan']),
      trialEndsAt: J.date(json['trial_ends_at']),
      renewsAt: J.date(json['renews_at']),
    );
  }

  final int id;
  final String name;

  /// Plan key: `free`, `starter`, `professional`, `enterprise`.
  final String plan;

  /// Display name from the plan catalogue, e.g. "Professional".
  final String? planName;

  final int memberCount;

  /// When the monthly counters reset.
  final DateTime? usagePeriodEndsAt;

  /// `active`, `inactive` or `past_due`.
  final String? subscriptionStatus;

  final bool onPaidPlan;
  final DateTime? trialEndsAt;
  final DateTime? renewsAt;

  /// What to print next to "Plan". Never empty.
  String get planLabel {
    final String? catalogue = planName;
    if (catalogue != null && catalogue.isNotEmpty) {
      return catalogue;
    }
    return Fmt.humanise(plan);
  }

  bool get isPastDue => subscriptionStatus == 'past_due';

  bool get isOnTrial {
    final DateTime? ends = trialEndsAt;
    return ends != null && ends.isAfter(DateTime.now());
  }

  Workspace copyWith({
    int? id,
    String? name,
    String? plan,
    String? planName,
    int? memberCount,
    DateTime? usagePeriodEndsAt,
    String? subscriptionStatus,
    bool? onPaidPlan,
    DateTime? trialEndsAt,
    DateTime? renewsAt,
  }) {
    return Workspace(
      id: id ?? this.id,
      name: name ?? this.name,
      plan: plan ?? this.plan,
      planName: planName ?? this.planName,
      memberCount: memberCount ?? this.memberCount,
      usagePeriodEndsAt: usagePeriodEndsAt ?? this.usagePeriodEndsAt,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      onPaidPlan: onPaidPlan ?? this.onPaidPlan,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      renewsAt: renewsAt ?? this.renewsAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Workspace &&
          other.id == id &&
          other.name == name &&
          other.plan == plan &&
          other.planName == planName &&
          other.memberCount == memberCount &&
          other.usagePeriodEndsAt == usagePeriodEndsAt &&
          other.subscriptionStatus == subscriptionStatus &&
          other.onPaidPlan == onPaidPlan &&
          other.trialEndsAt == trialEndsAt &&
          other.renewsAt == renewsAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        plan,
        planName,
        memberCount,
        usagePeriodEndsAt,
        subscriptionStatus,
        onPaidPlan,
        trialEndsAt,
        renewsAt,
      );

  @override
  String toString() => 'Workspace($id, $name, $plan)';
}

/// One metered allowance, ready to hand to a `UsageMeter`.
///
/// The label is resolved here so no screen has to know that "esign" is spelled
/// `esign_requests` on `GET /me` and `esign` on `GET /billing`.
@immutable
class UsageLine {
  const UsageLine({
    required this.key,
    required this.label,
    required this.used,
    required this.limit,
  });

  /// Stable identifier — one of the `PlanLimits.key*` constants.
  final String key;

  /// Localised, already user-facing.
  final String label;

  final int? used;
  final int? limit;

  /// A limit of 0 means "not metered on this plan" on the server, which reads
  /// to a person as no ceiling rather than as a ceiling of nothing.
  bool get isUnlimited => limit == null || limit! <= 0;

  double get ratio => Fmt.usageRatio(used, limit);

  /// The threshold the dashboard uses to start offering an upgrade.
  bool get isNearLimit => !isUnlimited && ratio >= 0.85;

  bool get isExhausted => !isUnlimited && (used ?? 0) >= limit!;

  int? get remaining {
    if (isUnlimited) {
      return null;
    }
    final int left = limit! - (used ?? 0);
    return left < 0 ? 0 : left;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsageLine &&
          other.key == key &&
          other.label == label &&
          other.used == used &&
          other.limit == limit;

  @override
  int get hashCode => Object.hash(key, label, used, limit);

  @override
  String toString() => 'UsageLine($key, $used/$limit)';
}

/// What the plan allows and what has been used this period.
///
/// Every pair is nullable because `UsageResource` publishes an explicit null
/// where the application genuinely does not count something — "we don't know"
/// and "you have used none" are different bars.
@immutable
class PlanLimits {
  const PlanLimits({
    this.documentsUsed,
    this.documentsLimit,
    this.pagesUsed,
    this.pagesLimit,
    this.conversionsUsed,
    this.conversionsLimit,
    this.esignUsed,
    this.esignLimit,
    this.webScansUsed,
    this.webScansLimit,
    this.barcodesUsed,
    this.barcodesLimit,
    this.periodStartedAt,
    this.periodEndsAt,
  });

  /// Parses the `usage` block of `GET /me`.
  ///
  /// `GET /billing` publishes the same buckets under the key `esign` instead of
  /// `esign_requests`; both are accepted so the billing screen can reuse this
  /// parser rather than keeping a second copy that can drift.
  factory PlanLimits.fromJson(Map<String, dynamic> json) {
    final (int? documentsUsed, int? documentsLimit) = _pair(json['documents']);
    final (int? pagesUsed, int? pagesLimit) = _pair(json['pages']);
    final (int? conversionsUsed, int? conversionsLimit) =
        _pair(json['conversions']);
    final (int? esignUsed, int? esignLimit) =
        _pair(json['esign_requests'] ?? json['esign']);
    final (int? webScansUsed, int? webScansLimit) = _pair(json['web_scans']);
    final (int? barcodesUsed, int? barcodesLimit) = _pair(json['barcodes']);

    return PlanLimits(
      documentsUsed: documentsUsed,
      documentsLimit: documentsLimit,
      pagesUsed: pagesUsed,
      pagesLimit: pagesLimit,
      conversionsUsed: conversionsUsed,
      conversionsLimit: conversionsLimit,
      esignUsed: esignUsed,
      esignLimit: esignLimit,
      webScansUsed: webScansUsed,
      webScansLimit: webScansLimit,
      barcodesUsed: barcodesUsed,
      barcodesLimit: barcodesLimit,
      periodStartedAt: J.date(json['period_started_at']),
      periodEndsAt: J.date(json['period_ends_at']),
    );
  }

  static const PlanLimits empty = PlanLimits();

  // Bucket identifiers, matching the server's own key names.
  static const String keyDocuments = 'documents';
  static const String keyPages = 'pages';
  static const String keyConversions = 'conversions';
  static const String keyEsign = 'esign';
  static const String keyWebScans = 'web_scans';
  static const String keyBarcodes = 'barcodes';

  final int? documentsUsed;
  final int? documentsLimit;
  final int? pagesUsed;
  final int? pagesLimit;
  final int? conversionsUsed;
  final int? conversionsLimit;
  final int? esignUsed;
  final int? esignLimit;
  final int? webScansUsed;
  final int? webScansLimit;
  final int? barcodesUsed;
  final int? barcodesLimit;

  final DateTime? periodStartedAt;
  final DateTime? periodEndsAt;

  /// Every bucket in display order, so a screen can render meters without
  /// knowing any of the field names above.
  List<UsageLine> get lines => <UsageLine>[
        UsageLine(
          key: keyDocuments,
          label: S.documents,
          used: documentsUsed,
          limit: documentsLimit,
        ),
        UsageLine(
          key: keyPages,
          label: S.usagePages,
          used: pagesUsed,
          limit: pagesLimit,
        ),
        UsageLine(
          key: keyConversions,
          label: S.conversions,
          used: conversionsUsed,
          limit: conversionsLimit,
        ),
        UsageLine(
          key: keyEsign,
          label: S.usageEsign,
          used: esignUsed,
          limit: esignLimit,
        ),
        UsageLine(
          key: keyWebScans,
          label: S.usageWebScans,
          used: webScansUsed,
          limit: webScansLimit,
        ),
        UsageLine(
          key: keyBarcodes,
          label: S.usageBarcodes,
          used: barcodesUsed,
          limit: barcodesLimit,
        ),
      ];

  /// One bucket by key, or null when the server did not publish it.
  UsageLine? line(String key) {
    for (final UsageLine line in lines) {
      if (line.key == key) {
        return line;
      }
    }
    return null;
  }

  /// The buckets named in [keys], in the order given, skipping unknown keys.
  List<UsageLine> linesFor(List<String> keys) {
    final List<UsageLine> out = <UsageLine>[];
    for (final String key in keys) {
      final UsageLine? found = line(key);
      if (found != null) {
        out.add(found);
      }
    }
    return out;
  }

  bool get anyNearLimit => lines.any((UsageLine l) => l.isNearLimit);

  static (int?, int?) _pair(dynamic raw) {
    final Map<String, dynamic> map = J.map(raw);
    return (J.intOrNull(map['used']), J.intOrNull(map['limit']));
  }

  PlanLimits copyWith({
    int? documentsUsed,
    int? documentsLimit,
    int? pagesUsed,
    int? pagesLimit,
    int? conversionsUsed,
    int? conversionsLimit,
    int? esignUsed,
    int? esignLimit,
    int? webScansUsed,
    int? webScansLimit,
    int? barcodesUsed,
    int? barcodesLimit,
    DateTime? periodStartedAt,
    DateTime? periodEndsAt,
  }) {
    return PlanLimits(
      documentsUsed: documentsUsed ?? this.documentsUsed,
      documentsLimit: documentsLimit ?? this.documentsLimit,
      pagesUsed: pagesUsed ?? this.pagesUsed,
      pagesLimit: pagesLimit ?? this.pagesLimit,
      conversionsUsed: conversionsUsed ?? this.conversionsUsed,
      conversionsLimit: conversionsLimit ?? this.conversionsLimit,
      esignUsed: esignUsed ?? this.esignUsed,
      esignLimit: esignLimit ?? this.esignLimit,
      webScansUsed: webScansUsed ?? this.webScansUsed,
      webScansLimit: webScansLimit ?? this.webScansLimit,
      barcodesUsed: barcodesUsed ?? this.barcodesUsed,
      barcodesLimit: barcodesLimit ?? this.barcodesLimit,
      periodStartedAt: periodStartedAt ?? this.periodStartedAt,
      periodEndsAt: periodEndsAt ?? this.periodEndsAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlanLimits &&
          other.documentsUsed == documentsUsed &&
          other.documentsLimit == documentsLimit &&
          other.pagesUsed == pagesUsed &&
          other.pagesLimit == pagesLimit &&
          other.conversionsUsed == conversionsUsed &&
          other.conversionsLimit == conversionsLimit &&
          other.esignUsed == esignUsed &&
          other.esignLimit == esignLimit &&
          other.webScansUsed == webScansUsed &&
          other.webScansLimit == webScansLimit &&
          other.barcodesUsed == barcodesUsed &&
          other.barcodesLimit == barcodesLimit &&
          other.periodStartedAt == periodStartedAt &&
          other.periodEndsAt == periodEndsAt;

  @override
  int get hashCode => Object.hash(
        documentsUsed,
        documentsLimit,
        pagesUsed,
        pagesLimit,
        conversionsUsed,
        conversionsLimit,
        esignUsed,
        esignLimit,
        webScansUsed,
        webScansLimit,
        barcodesUsed,
        barcodesLimit,
        periodStartedAt,
        periodEndsAt,
      );

  @override
  String toString() =>
      'PlanLimits(documents: $documentsUsed/$documentsLimit, '
      'pages: $pagesUsed/$pagesLimit)';
}

/// Which plan the workspace is entitled to, and who is billing for it.
///
/// `GET /billing` publishes this exactly (`plan`, `source`, `managed_by`,
/// `can_purchase`) and is the authority. `GET /me` does not, so a session-built
/// entitlement reports [sourceUnknown] for a paid workspace rather than
/// guessing between Stripe and a store — and, being unsure, refuses to claim
/// that an in-app purchase is allowed. Selling a second subscription to someone
/// who already pays by card on the website is a refund, a chargeback, and a
/// rejected review.
@immutable
class Entitlement {
  const Entitlement({
    required this.plan,
    required this.source,
    required this.managedBy,
    required this.canPurchase,
  });

  /// Parses the `GET /billing` snapshot, where `plan` is an object.
  factory Entitlement.fromJson(Map<String, dynamic> json) {
    final dynamic rawPlan = json['plan'];
    final String plan = rawPlan is Map
        ? J.strOr(J.map(rawPlan)['key'], 'free')
        : J.strOr(rawPlan, 'free');

    return Entitlement(
      plan: plan,
      source: J.strOr(json['source'], sourceFree),
      managedBy: J.strOr(json['managed_by'], managedByNone),
      canPurchase: J.boolOr(json['can_purchase']),
    );
  }

  /// Derives what can honestly be derived from `CompanyResource` alone.
  factory Entitlement.fromCompany(Map<String, dynamic> company) {
    final bool paid = J.boolOr(company['on_paid_plan']);

    return Entitlement(
      plan: J.strOr(company['plan'], 'free'),
      source: paid ? sourceUnknown : sourceFree,
      managedBy: paid ? sourceUnknown : managedByNone,
      canPurchase: !paid,
    );
  }

  static const Entitlement free = Entitlement(
    plan: 'free',
    source: sourceFree,
    managedBy: managedByNone,
    canPurchase: true,
  );

  static const String sourceStripe = 'stripe';
  static const String sourceApple = 'apple';
  static const String sourceGoogle = 'google';
  static const String sourceFree = 'free';

  /// Only ever produced by [Entitlement.fromCompany]; `GET /billing` never
  /// returns it.
  static const String sourceUnknown = 'unknown';

  static const String managedByNone = 'none';

  /// Plan key the workspace is entitled to right now.
  final String plan;

  /// Where the money comes from: `stripe`, `apple`, `google` or `free`.
  final String source;

  /// Who the customer manages the subscription with: the same values plus
  /// `none`.
  final String managedBy;

  /// Whether an in-app purchase may be started. False while a card
  /// subscription on the website is live.
  final bool canPurchase;

  bool get isFree => source == sourceFree;

  bool get isStore => source == sourceApple || source == sourceGoogle;

  /// Billed by card on banksheet.pro — the app must not sell here.
  bool get isManagedOnWeb => managedBy == sourceStripe;

  bool get isKnown => source != sourceUnknown;

  Entitlement copyWith({
    String? plan,
    String? source,
    String? managedBy,
    bool? canPurchase,
  }) {
    return Entitlement(
      plan: plan ?? this.plan,
      source: source ?? this.source,
      managedBy: managedBy ?? this.managedBy,
      canPurchase: canPurchase ?? this.canPurchase,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Entitlement &&
          other.plan == plan &&
          other.source == source &&
          other.managedBy == managedBy &&
          other.canPurchase == canPurchase;

  @override
  int get hashCode => Object.hash(plan, source, managedBy, canPurchase);

  @override
  String toString() => 'Entitlement($plan via $source)';
}

/// Everything `GET /me` returns, in one object.
@immutable
class Session {
  const Session({
    required this.user,
    required this.workspace,
    required this.limits,
    required this.entitlement,
    this.features = const <String>[],
  });

  /// Accepts both the bare object and a `{"data": {...}}` envelope.
  factory Session.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> root =
        J.map(json['data']).isEmpty ? json : J.map(json['data']);

    final Map<String, dynamic> company = J.map(root['company']);
    final Map<String, dynamic> plan = J.map(root['plan']);
    final PlanLimits limits = PlanLimits.fromJson(J.map(root['usage']));

    return Session(
      user: AppUser.fromJson(J.map(root['user'])),
      workspace: Workspace.fromJson(
        company,
        planName: J.str(plan['name']),
        usagePeriodEndsAt: limits.periodEndsAt,
      ),
      limits: limits,
      entitlement: root['entitlement'] is Map
          ? Entitlement.fromJson(J.map(root['entitlement']))
          : Entitlement.fromCompany(company),
      features: _features(company, plan),
    );
  }

  final AppUser user;
  final Workspace workspace;
  final PlanLimits limits;
  final Entitlement entitlement;

  /// Feature flags this workspace may use, e.g. `esign_requests`, `ocr`,
  /// `api_access`.
  final List<String> features;

  /// True when the workspace may use [feature].
  bool has(String feature) => features.contains(feature);

  String get planKey => workspace.plan;

  /// The union of the features stored on the workspace and the ones its plan
  /// grants — the same set `Company::hasPlanFeature()` checks, so the app hides
  /// exactly what the server would refuse and nothing more.
  static List<String> _features(
    Map<String, dynamic> company,
    Map<String, dynamic> plan,
  ) {
    final Set<String> all = <String>{
      ...J.strings(company['features']),
      ...J.strings(plan['features']),
    };
    return List<String>.unmodifiable(all);
  }

  Session copyWith({
    AppUser? user,
    Workspace? workspace,
    PlanLimits? limits,
    Entitlement? entitlement,
    List<String>? features,
  }) {
    return Session(
      user: user ?? this.user,
      workspace: workspace ?? this.workspace,
      limits: limits ?? this.limits,
      entitlement: entitlement ?? this.entitlement,
      features: features ?? this.features,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Session &&
          other.user == user &&
          other.workspace == workspace &&
          other.limits == limits &&
          other.entitlement == entitlement &&
          listEquals(other.features, features);

  @override
  int get hashCode => Object.hash(
        user,
        workspace,
        limits,
        entitlement,
        Object.hashAll(features),
      );

  @override
  String toString() => 'Session(${user.email}, ${workspace.plan})';
}
