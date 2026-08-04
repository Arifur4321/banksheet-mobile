/// The `GET /billing` snapshot, exactly as `BillingController::show()` builds it.
///
/// Every action on that controller — show, purchase, restore — answers with the
/// same body, so one type covers all four calls and the app is never left
/// guessing what the workspace holds after a purchase.
///
/// Entitlement, PlanLimits and UsageLine are **not** redefined here: they are
/// the shared vocabulary from `features/auth/domain/session.dart`, and billing
/// is the feature that would break the rest of the app if it grew a second,
/// drifting copy of "which plan is this workspace on".
///
/// Field names are taken verbatim from the controller. The two that are easy to
/// get wrong, and are therefore spelled out:
///   * the usage bucket for e-signature is `esign` here and `esign_requests` on
///     `GET /me` — [PlanLimits.fromJson] already accepts both;
///   * `GET /billing` publishes a seventh bucket, `api_documents`, that `GET
///     /me` does not, so it is parsed here rather than pushed into [PlanLimits].
library;

import 'package:flutter/foundation.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../auth/domain/session.dart';

/// One buyable (or contactable) plan from the snapshot's `plans` array.
///
/// The server decides what is on offer: `product_ids` is already filtered by
/// `config('mobile.iap.yearly_enabled')`, and Enterprise arrives with an empty
/// array, which is what tells the client to show "talk to us" instead of a buy
/// button. App Store guideline 3.1.1 forbids sending the user out to an
/// external purchase flow, so an empty array must never become a web link.
@immutable
class PlanOffer {
  const PlanOffer({
    required this.key,
    required this.name,
    required this.productIds,
    this.priceEur,
    this.purchasable = false,
    this.isCurrent = false,
  });

  factory PlanOffer.fromJson(Map<String, dynamic> json) {
    final String key = J.strOr(json['key'], '');
    final List<String> productIds = J.strings(json['product_ids']);

    return PlanOffer(
      key: key,
      name: J.strOr(json['name'], Fmt.humanise(key)),
      productIds: productIds,
      priceEur: J.doubleOrNull(json['price_eur']),
      // The server computes this as "has at least one offered product"; it is
      // read rather than re-derived so a future rule change lands in one place.
      purchasable: J.boolOr(json['purchasable'], fallback: productIds.isNotEmpty),
      isCurrent: J.boolOr(json['current']),
    );
  }

  final String key;
  final String name;

  /// Store product identifiers to look up through StoreKit / Play Billing.
  final List<String> productIds;

  /// The website's list price, in euro. Display only, and never shown next to a
  /// buy button: the store charges its own localised price and showing a
  /// different number is both a rejection and a lie.
  final double? priceEur;

  final bool purchasable;

  /// True when this is the plan the workspace already holds.
  final bool isCurrent;

  /// Enterprise: a real plan with nothing to sell in the app.
  bool get isContactOnly => productIds.isEmpty;

  /// The monthly product, which is what a v1 client offers. Falls back to the
  /// first id so a store that only has a yearly product still sells something.
  String? get preferredProductId {
    for (final String id in productIds) {
      if (!id.endsWith('.yearly') && !id.endsWith('.annual')) {
        return id;
      }
    }
    return productIds.isEmpty ? null : productIds.first;
  }

  bool get isYearly {
    final String? id = preferredProductId;
    return id != null && (id.endsWith('.yearly') || id.endsWith('.annual'));
  }

  /// `Monthly subscription` / `Yearly subscription`, for the purchase sheet.
  String get periodLabel => isYearly ? S.periodYearly : S.periodMonthly;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlanOffer &&
          other.key == key &&
          other.name == name &&
          listEquals(other.productIds, productIds) &&
          other.priceEur == priceEur &&
          other.purchasable == purchasable &&
          other.isCurrent == isCurrent;

  @override
  int get hashCode => Object.hash(
        key,
        name,
        Object.hashAll(productIds),
        priceEur,
        purchasable,
        isCurrent,
      );

  @override
  String toString() => 'PlanOffer($key, ${productIds.length} products)';
}

/// One receipt the restore endpoint could not use, from its `failures` array.
@immutable
class RestoreFailure {
  const RestoreFailure({required this.store, required this.code});

  factory RestoreFailure.fromJson(Map<String, dynamic> json) => RestoreFailure(
        store: J.strOr(json['store'], ''),
        code: J.strOr(json['code'], 'purchase_invalid'),
      );

  /// `apple` or `google`.
  final String store;

  /// One of the billing failure codes in `MobileErrors::CATALOG`.
  final String code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RestoreFailure && other.store == store && other.code == code;

  @override
  int get hashCode => Object.hash(store, code);

  @override
  String toString() => 'RestoreFailure($store, $code)';
}

/// Everything `GET /billing` returns, in one object.
@immutable
class BillingSnapshot {
  const BillingSnapshot({
    required this.entitlement,
    required this.planName,
    required this.usage,
    required this.plans,
    this.planPriceEur,
    this.subscriptionStatus,
    this.autoRenewing,
    this.renewsAt,
    this.usagePeriodEndsAt,
    this.apiDocuments,
    this.employees,
    this.extractionProfiles,
    this.storageLimitMb,
    this.features = const <String>[],
    this.manageUrl,
    this.termsUrl,
    this.privacyUrl,
    this.restoredCount = 0,
    this.restoreFailures = const <RestoreFailure>[],
  });

  /// Accepts the bare object and a `{"data": {...}}` envelope, because the
  /// mobile controller's `ok()` sends the array itself while the rest of the
  /// API wraps resources.
  factory BillingSnapshot.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> root =
        J.map(json['data']).isEmpty ? json : J.map(json['data']);

    final Map<String, dynamic> plan = J.map(root['plan']);
    final Map<String, dynamic> usage = J.map(root['usage']);
    final Map<String, dynamic> limits = J.map(root['limits']);
    final Map<String, dynamic> links = J.map(root['links']);

    return BillingSnapshot(
      // Entitlement.fromJson reads `plan.key`, `source`, `managed_by` and
      // `can_purchase` off this same root — the shape it was written for.
      entitlement: Entitlement.fromJson(root),
      planName: J.strOr(plan['name'], Fmt.humanise(J.str(plan['key']))),
      planPriceEur: J.doubleOrNull(plan['price_eur']),
      subscriptionStatus: J.str(root['subscription_status']),
      // Explicitly null for a free workspace, and null is not false: "we do not
      // know whether this renews" must not render as "auto-renew off".
      autoRenewing:
          root['auto_renewing'] == null ? null : J.boolOr(root['auto_renewing']),
      renewsAt: J.date(root['renews_at']),
      usagePeriodEndsAt: J.date(root['usage_period_ends_at']),
      usage: PlanLimits.fromJson(usage),
      apiDocuments: _line(
        usage['api_documents'],
        _keyApiDocuments,
        S.usageApiDocuments,
      ),
      employees: _line(
        limits['employees'],
        _keyEmployees,
        S.usageEmployees,
      ),
      extractionProfiles: _line(
        limits['extraction_profiles'],
        _keyExtractionProfiles,
        S.usageExtractionProfiles,
      ),
      storageLimitMb: J.intOrNull(J.map(limits['storage_mb'])['limit']),
      features: J.strings(root['features']),
      plans: J
          .list(root['plans'])
          .map(PlanOffer.fromJson)
          .toList(growable: false),
      manageUrl: J.str(root['manage_url']),
      termsUrl: J.str(links['terms']),
      privacyUrl: J.str(links['privacy']),
      restoredCount: J.intOr(root['restored'], 0),
      restoreFailures: J
          .list(root['failures'])
          .map(RestoreFailure.fromJson)
          .toList(growable: false),
    );
  }

  /// Bucket keys the billing payload adds on top of [PlanLimits]'.
  ///
  /// `api_documents` lives here rather than on [PlanLimits] for the reason
  /// this file's header gives: only `GET /billing` publishes it, and `GET /me`
  /// does not. Putting it on the shared type would promise every consumer a
  /// bucket that is absent from the payload most of them read.
  static const String _keyApiDocuments = 'api_documents';
  static const String _keyEmployees = 'employees';
  static const String _keyExtractionProfiles = 'extraction_profiles';

  /// Plan, source, who manages it, and whether an in-app purchase is allowed.
  final Entitlement entitlement;

  /// Display name from the plan catalogue, e.g. "Professional".
  final String planName;

  /// The website's euro price for the current plan. Never shown as the price of
  /// a purchase — the store's own localised string is.
  final double? planPriceEur;

  /// `active`, `inactive` or `past_due`.
  final String? subscriptionStatus;

  /// Null when nothing renews (free), true/false otherwise.
  final bool? autoRenewing;

  /// Next charge for a Stripe subscription; end of the paid term for a store
  /// one. With [autoRenewing] false the same date is the last day of access.
  final DateTime? renewsAt;

  /// When the monthly counters reset.
  final DateTime? usagePeriodEndsAt;

  /// The six metered buckets `GET /me` also publishes.
  final PlanLimits usage;

  /// The seventh bucket, which only `GET /billing` publishes. Null when the
  /// plan has no API allowance at all — a limit of 0 means "none", and the
  /// shared meter reads 0 as "unlimited", so it must not be drawn.
  final UsageLine? apiDocuments;

  final UsageLine? employees;
  final UsageLine? extractionProfiles;

  /// Storage ceiling in megabytes. The server publishes no `used` for it, so it
  /// is stated rather than metered.
  final int? storageLimitMb;

  /// Feature flags the workspace may use, e.g. `ocr`, `api_access`.
  final List<String> features;

  /// Starter, Professional and Enterprise, in catalogue order. Free is not
  /// included: the server skips its default plan key.
  final List<PlanOffer> plans;

  /// Deep link into the store's own subscription settings, chosen by the server
  /// from the platform header. Null when the platform is neither iOS nor
  /// Android — the client falls back to [AppConfig]'s https URLs.
  final String? manageUrl;

  final String? termsUrl;
  final String? privacyUrl;

  /// Only meaningful on the answer to `POST /billing/purchases/restore`.
  final int restoredCount;
  final List<RestoreFailure> restoreFailures;

  // ------------------------------------------------------------- entitlement

  String get planKey => entitlement.plan;

  /// False while a card subscription on banksheet.pro is live. The server
  /// enforces the same rule; this only stops the app from offering something it
  /// knows will be refused.
  bool get canPurchase => entitlement.canPurchase;

  bool get isManagedOnWeb => entitlement.isManagedOnWeb;

  bool get isStoreManaged => entitlement.isStore;

  bool get isFree => entitlement.isFree;

  bool get isPastDue => subscriptionStatus == 'past_due';

  /// Who is billing, in words: "App Store", "Google Play", "banksheet.pro" or
  /// "Free plan".
  String get sourceLabel => switch (entitlement.source) {
        Entitlement.sourceApple => S.billedByAppStore,
        Entitlement.sourceGoogle => S.billedByGooglePlay,
        Entitlement.sourceStripe => S.billedByWebsite,
        _ => S.billedByNobody,
      };

  /// `Renews` while auto-renew is on, `Access until` once it is off — the same
  /// date means two different things and saying "renews" after a cancellation
  /// is how support tickets start.
  String get renewalLabel =>
      autoRenewing == false ? S.accessUntil : S.renewsOn;

  // ------------------------------------------------------------------ offers

  PlanOffer? offer(String planKey) {
    for (final PlanOffer plan in plans) {
      if (plan.key == planKey) {
        return plan;
      }
    }
    return null;
  }

  PlanOffer? get currentOffer => offer(planKey);

  /// The plans a buy button may be drawn for: purchasable, not already held,
  /// and only when the workspace is allowed to buy at all.
  List<PlanOffer> get buyableOffers => canPurchase
      ? plans
          .where((PlanOffer p) => p.purchasable && !p.isCurrent)
          .toList(growable: false)
      : const <PlanOffer>[];

  /// Enterprise, or whatever else the catalogue offers with no store product.
  PlanOffer? get contactOffer {
    for (final PlanOffer plan in plans) {
      if (plan.isContactOnly) {
        return plan;
      }
    }
    return null;
  }

  /// Every product identifier worth asking the store about.
  Set<String> get productIds => <String>{
        for (final PlanOffer plan in plans) ...plan.productIds,
      };

  // ------------------------------------------------------------------- usage

  /// Every meter the workspace has, in display order.
  List<UsageLine> get usageLines => <UsageLine>[
        ...usage.lines,
        if (apiDocuments != null) apiDocuments!,
        if (employees != null) employees!,
        if (extractionProfiles != null) extractionProfiles!,
      ];

  /// Builds a [UsageLine] from a `{used, limit, remaining}` block, and returns
  /// null when the bucket carries no ceiling worth drawing.
  static UsageLine? _line(dynamic raw, String key, String label) {
    final Map<String, dynamic> map = J.map(raw);
    if (map.isEmpty) {
      return null;
    }

    final int? limit = J.intOrNull(map['limit']);
    if (limit == null || limit <= 0) {
      // 0 is "no allowance on this plan" for these buckets, and UsageMeter
      // renders 0 as "unlimited" — drawing it would claim the opposite of the
      // truth, so the row is dropped instead.
      return null;
    }

    return UsageLine(
      key: key,
      label: label,
      used: J.intOrNull(map['used']),
      limit: limit,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BillingSnapshot &&
          other.entitlement == entitlement &&
          other.planName == planName &&
          other.planPriceEur == planPriceEur &&
          other.subscriptionStatus == subscriptionStatus &&
          other.autoRenewing == autoRenewing &&
          other.renewsAt == renewsAt &&
          other.usagePeriodEndsAt == usagePeriodEndsAt &&
          other.usage == usage &&
          other.apiDocuments == apiDocuments &&
          other.employees == employees &&
          other.extractionProfiles == extractionProfiles &&
          other.storageLimitMb == storageLimitMb &&
          listEquals(other.features, features) &&
          listEquals(other.plans, plans) &&
          other.manageUrl == manageUrl &&
          other.termsUrl == termsUrl &&
          other.privacyUrl == privacyUrl &&
          other.restoredCount == restoredCount &&
          listEquals(other.restoreFailures, restoreFailures);

  @override
  int get hashCode => Object.hash(
        entitlement,
        planName,
        planPriceEur,
        subscriptionStatus,
        autoRenewing,
        renewsAt,
        usagePeriodEndsAt,
        usage,
        apiDocuments,
        employees,
        extractionProfiles,
        storageLimitMb,
        Object.hashAll(features),
        Object.hashAll(plans),
        manageUrl,
        termsUrl,
        privacyUrl,
        restoredCount,
        Object.hashAll(restoreFailures),
      );

  @override
  String toString() =>
      'BillingSnapshot($planKey via ${entitlement.source}, '
      'canPurchase: $canPurchase)';
}
