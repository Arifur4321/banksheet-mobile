/// Company-data extraction: the job, its per-website targets, and what was
/// found on each of them.
///
/// Field names are taken verbatim from `WebExtractionJobResource`,
/// `WebExtractionTargetResource` and `WebExtractionResultResource`.
///
/// Two server decisions are honoured rather than re-implemented here.
/// `progress_percent` is computed on the server because completed + failed can
/// briefly exceed the total while the progress service refreshes, and a phone
/// rendering 104% looks broken. `is_finished` is likewise the server's answer,
/// not a status-string match, so a state a future server adds stops the poller
/// instead of spinning it forever.
///
/// Every extracted value keeps its provenance. A phone number nobody can trace
/// back to the page that published it is not a lead, it is a liability.
library;

import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// Where a value was found: the primary page, plus every page it appeared on.
///
/// The server guarantees `source_urls` is populated even when a value was found
/// on exactly one page, so nothing downstream has to branch.
@immutable
class Provenance {
  const Provenance({this.sourceUrl, this.sourceUrls = const <String>[]});

  factory Provenance.fromJson(Map<String, dynamic> json) {
    final List<String> all = J.strings(json['source_urls']);
    final String? primary = J.str(json['source_url']);
    // The server populates the list even for a value found on one page; this
    // rebuilds it if an older build of the server ever did not, so nothing
    // downstream has to branch.
    final List<String> urls =
        all.isEmpty && primary != null ? <String>[primary] : all;

    return Provenance(
      sourceUrl: primary ?? (urls.isEmpty ? null : urls.first),
      sourceUrls: urls,
    );
  }

  final String? sourceUrl;
  final List<String> sourceUrls;

  bool get hasMultipleSources => sourceUrls.length > 1;
}

/// One scalar value plus where it came from.
///
/// The server lands every scalar under `value` whatever the storage column
/// called it — email, phone, vat_number, address — so the app has one list
/// widget instead of six that differ by a key name.
@immutable
class ContactValue {
  const ContactValue({
    required this.value,
    required this.provenance,
    this.category,
    this.city,
    this.province,
    this.country,
  });

  factory ContactValue.fromJson(Map<String, dynamic> json) => ContactValue(
        value: J.strOr(json['value'], ''),
        category: J.str(json['category']),
        city: J.str(json['city']),
        province: J.str(json['province']),
        country: J.str(json['country']),
        provenance: Provenance.fromJson(json),
      );

  final String value;

  /// Email classification, e.g. `generic`, `role`, `pec`.
  final String? category;

  final String? city;
  final String? province;
  final String? country;

  final Provenance provenance;

  /// The address line's locality, when there is one.
  String? get locality {
    final List<String> parts = <String>[
      if (city != null) city!,
      if (province != null) province!,
      if (country != null) country!,
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }
}

/// A page the crawler classified — careers, contact, about, privacy.
@immutable
class LinkEntry {
  const LinkEntry({required this.url, required this.provenance});

  factory LinkEntry.fromJson(Map<String, dynamic> json) => LinkEntry(
        url: J.strOr(json['url'], ''),
        provenance: Provenance.fromJson(json),
      );

  final String url;
  final Provenance provenance;
}

/// A named person found on the site.
@immutable
class PersonEntry {
  const PersonEntry({required this.provenance, this.name, this.role, this.email});

  factory PersonEntry.fromJson(Map<String, dynamic> json) => PersonEntry(
        name: J.str(json['name']),
        role: J.str(json['role']),
        email: J.str(json['email']),
        provenance: Provenance.fromJson(json),
      );

  final String? name;
  final String? role;
  final String? email;
  final Provenance provenance;

  String get display => name ?? role ?? email ?? '';
}

/// A social profile. `network` is one of linkedin, facebook, instagram,
/// youtube, x or other.
@immutable
class SocialLink {
  const SocialLink({
    required this.network,
    required this.url,
    required this.provenance,
  });

  factory SocialLink.fromJson(Map<String, dynamic> json) => SocialLink(
        network: J.strOr(json['network'], 'other'),
        url: J.strOr(json['url'], ''),
        provenance: Provenance.fromJson(json),
      );

  final String network;
  final String url;
  final Provenance provenance;
}

/// Everything extracted from one website.
@immutable
class WebExtractionResult {
  const WebExtractionResult({
    required this.emails,
    required this.pecEmails,
    required this.phones,
    required this.mobiles,
    required this.vatNumbers,
    required this.taxCodes,
    required this.addresses,
    required this.careerPages,
    required this.contactPages,
    required this.aboutPages,
    required this.privacyPages,
    required this.people,
    required this.socialLinks,
    required this.sourceUrls,
    this.companyName,
    this.website,
    this.confidenceScore,
    this.fieldConfidence,
    this.notes,
    this.extractedAt,
  });

  factory WebExtractionResult.fromJson(Map<String, dynamic> json) =>
      WebExtractionResult(
        companyName: J.str(json['company_name']),
        website: J.str(json['website']),
        emails: _values(json['emails']),
        pecEmails: _values(json['pec_emails']),
        phones: _values(json['phones']),
        mobiles: _values(json['mobiles']),
        vatNumbers: _values(json['vat_numbers']),
        taxCodes: _values(json['tax_codes']),
        addresses: _values(json['addresses']),
        careerPages: _links(json['career_pages']),
        contactPages: _links(json['contact_pages']),
        aboutPages: _links(json['about_pages']),
        privacyPages: _links(json['privacy_pages']),
        people: J
            .list(json['people'])
            .map(PersonEntry.fromJson)
            .where((PersonEntry p) => p.display.isNotEmpty)
            .toList(growable: false),
        socialLinks: J
            .list(json['social_links'])
            .map(SocialLink.fromJson)
            .where((SocialLink s) => s.url.isNotEmpty)
            .toList(growable: false),
        sourceUrls: J.strings(json['source_urls']),
        confidenceScore: J.intOrNull(json['confidence_score']),
        fieldConfidence: json['field_confidence'] == null
            ? null
            : J.map(json['field_confidence']),
        notes: J.str(json['notes']),
        extractedAt: J.date(json['extracted_at']),
      );

  final String? companyName;
  final String? website;

  /// Generic and role addresses. Certified (PEC) mailboxes are split out
  /// because they are acted on differently.
  final List<ContactValue> emails;
  final List<ContactValue> pecEmails;

  final List<ContactValue> phones;
  final List<ContactValue> mobiles;
  final List<ContactValue> vatNumbers;
  final List<ContactValue> taxCodes;
  final List<ContactValue> addresses;

  final List<LinkEntry> careerPages;
  final List<LinkEntry> contactPages;
  final List<LinkEntry> aboutPages;
  final List<LinkEntry> privacyPages;

  final List<PersonEntry> people;
  final List<SocialLink> socialLinks;

  /// Every page the crawler actually read for this domain.
  final List<String> sourceUrls;

  /// 0–100.
  final int? confidenceScore;

  final Map<String, dynamic>? fieldConfidence;
  final String? notes;
  final DateTime? extractedAt;

  /// Phones and mobiles as one list, which is how a person reads them.
  List<ContactValue> get allPhones =>
      <ContactValue>[...phones, ...mobiles];

  /// Everything addressable, so the results card can say "nothing here" once.
  bool get isEmpty =>
      emails.isEmpty &&
      pecEmails.isEmpty &&
      phones.isEmpty &&
      mobiles.isEmpty &&
      vatNumbers.isEmpty &&
      addresses.isEmpty &&
      people.isEmpty &&
      socialLinks.isEmpty;

  int get contactCount =>
      emails.length + pecEmails.length + phones.length + mobiles.length;

  static List<ContactValue> _values(dynamic raw) => J
      .list(raw)
      .map(ContactValue.fromJson)
      .where((ContactValue v) => v.value.isNotEmpty)
      .toList(growable: false);

  static List<LinkEntry> _links(dynamic raw) => J
      .list(raw)
      .map(LinkEntry.fromJson)
      .where((LinkEntry l) => l.url.isNotEmpty)
      .toList(growable: false);
}

/// One website inside a job.
@immutable
class WebExtractionTarget {
  const WebExtractionTarget({
    required this.id,
    required this.status,
    required this.pagesScanned,
    required this.emailsFoundCount,
    this.inputName,
    this.inputValue,
    this.domain,
    this.url,
    this.httpStatus,
    this.confidenceScore,
    this.error,
    this.warning,
    this.startedAt,
    this.completedAt,
    this.result,
  });

  factory WebExtractionTarget.fromJson(Map<String, dynamic> json) =>
      WebExtractionTarget(
        id: J.intOr(json['id'], 0),
        inputName: J.str(json['input_name']),
        inputValue: J.str(json['input_value']),
        domain: J.str(json['domain']),
        url: J.str(json['url']),
        status: J.strOr(json['status'], 'pending'),
        httpStatus: J.intOrNull(json['http_status']),
        pagesScanned: J.intOr(json['pages_scanned'], 0),
        emailsFoundCount: J.intOr(json['emails_found_count'], 0),
        confidenceScore: J.intOrNull(json['confidence_score']),
        error: J.str(json['error_message']),
        warning: J.str(json['warning_message']),
        startedAt: J.date(json['started_at']),
        completedAt: J.date(json['completed_at']),
        result: json['result'] == null
            ? null
            : WebExtractionResult.fromJson(J.map(json['result'])),
      );

  final int id;

  /// What the user typed, kept verbatim so a line they cannot find in the
  /// results is still recognisable to them.
  final String? inputName;
  final String? inputValue;

  final String? domain;

  /// Null when the normaliser refused the line — which is what `skipped` means.
  final String? url;

  final String status;
  final int? httpStatus;
  final int pagesScanned;
  final int emailsFoundCount;

  /// 0–100, and genuinely null before the target has been crawled, which is not
  /// the same as a confident zero.
  final int? confidenceScore;

  final String? error;
  final String? warning;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final WebExtractionResult? result;

  bool get isWorking => status == 'pending' || status == 'processing';

  bool get isDone => status == 'completed';

  bool get isFailed => status == 'failed';

  bool get isSkipped => status == 'skipped';

  bool get isCancelled => status == 'cancelled';

  /// True for the rows `POST /web-extractions/{id}/retry` would pick up.
  bool get isRetryable => (isFailed || isSkipped) && url != null;

  /// What to print as the row's headline. Never empty.
  String get display => domain ?? inputValue ?? inputName ?? '#$id';
}

/// One extraction job.
@immutable
class WebExtractionJob {
  const WebExtractionJob({
    required this.id,
    required this.title,
    required this.status,
    required this.totalTargets,
    required this.completedTargets,
    required this.failedTargets,
    required this.processedTargets,
    required this.progressPercent,
    required this.emailsFoundCount,
    required this.careerPagesFoundCount,
    required this.isFinished,
    this.inputType,
    this.originalFilename,
    this.maxPagesPerTarget,
    this.warning,
    this.error,
    this.xlsxUrl,
    this.csvUrl,
    this.pollAfterSeconds,
    this.createdBy,
    this.createdAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
  });

  factory WebExtractionJob.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> exports = J.map(json['exports']);
    final int total = J.intOr(json['total_targets'], 0);
    final int id = J.intOr(json['id'], 0);

    return WebExtractionJob(
      id: id,
      title: J.strOr(json['title'], '#$id'),
      status: J.strOr(json['status'], 'pending'),
      inputType: J.str(json['input_type']),
      originalFilename: J.str(json['original_filename']),
      totalTargets: total,
      completedTargets: J.intOr(json['completed_targets'], 0),
      failedTargets: J.intOr(json['failed_targets'], 0),
      processedTargets: J.intOr(json['processed_targets'], 0),
      progressPercent:
          J.intOr(json['progress_percent'], 0).clamp(0, 100).toInt(),
      emailsFoundCount: J.intOr(json['emails_found_count'], 0),
      careerPagesFoundCount: J.intOr(json['career_pages_found_count'], 0),
      maxPagesPerTarget: J.intOrNull(json['max_pages_per_target']),
      warning: J.str(json['warning_message']),
      error: J.str(json['error_message']),
      isFinished: J.boolOr(json['is_finished']),
      xlsxUrl: J.str(exports['xlsx']),
      csvUrl: J.str(exports['csv']),
      pollAfterSeconds: J.intOrNull(json['poll_after_seconds']),
      createdBy: J.str(J.map(json['created_by'])['name']),
      createdAt: J.date(json['created_at']),
      startedAt: J.date(json['started_at']),
      completedAt: J.date(json['completed_at']),
      cancelledAt: J.date(json['cancelled_at']),
    );
  }

  final int id;

  /// Already carries the server's "Company data extraction #id" fallback.
  final String title;

  final String status;
  final String? inputType;
  final String? originalFilename;

  final int totalTargets;
  final int completedTargets;

  /// The progress service's rollup of failed + skipped + cancelled, not just
  /// hard failures.
  final int failedTargets;

  final int processedTargets;

  /// 0–100, clamped on the server.
  final int progressPercent;

  final int emailsFoundCount;
  final int careerPagesFoundCount;
  final int? maxPagesPerTarget;
  final String? warning;
  final String? error;

  final bool isFinished;

  /// Null until the job is finished, because export is refused before then.
  final String? xlsxUrl;
  final String? csvUrl;

  /// Withdrawn (null) the moment the job settles.
  final int? pollAfterSeconds;

  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  /// 0–1, for a progress bar.
  double get progress => progressPercent / 100;

  bool get isRunning => !isFinished;

  bool get isCancelled => status == 'cancelled';

  bool get hasWarnings => status == 'completed_with_warnings' || warning != null;

  /// The server refuses to delete a job that has not finished.
  bool get canDelete => isFinished;

  /// And refuses to cancel one that has.
  bool get canCancel => !isFinished;

  bool get canExport => isFinished && (xlsxUrl != null || csvUrl != null);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebExtractionJob &&
          other.id == id &&
          other.status == status &&
          other.progressPercent == progressPercent &&
          other.completedTargets == completedTargets &&
          other.failedTargets == failedTargets &&
          other.isFinished == isFinished;

  @override
  int get hashCode => Object.hash(
        id,
        status,
        progressPercent,
        completedTargets,
        failedTargets,
        isFinished,
      );

  @override
  String toString() => 'WebExtractionJob($id, $status, $progressPercent%)';
}

/// `GET /web-extractions/{id}` — the job with one page of its targets.
@immutable
class WebExtractionJobDetail {
  const WebExtractionJobDetail({
    required this.job,
    required this.targets,
    required this.targetsMeta,
  });

  factory WebExtractionJobDetail.fromJson(Map<String, dynamic> json) =>
      WebExtractionJobDetail(
        job: WebExtractionJob.fromJson(J.map(json['job'])),
        targets: J
            .list(json['targets'])
            .map(WebExtractionTarget.fromJson)
            .toList(growable: false),
        targetsMeta: PageMeta.fromJson(J.map(json['targets_meta'])),
      );

  final WebExtractionJob job;
  final List<WebExtractionTarget> targets;

  /// The nested paginator does not publish `has_more`; [PageMeta] derives it
  /// from current < last.
  final PageMeta targetsMeta;
}

/// What `POST /web-extractions` answers with.
@immutable
class WebExtractionCreated {
  const WebExtractionCreated({
    required this.job,
    required this.queuedTargets,
    this.message,
  });

  factory WebExtractionCreated.fromJson(Map<String, dynamic> json) =>
      WebExtractionCreated(
        job: WebExtractionJob.fromJson(J.map(json['job'])),
        queuedTargets: J.intOr(json['queued_targets'], 0),
        message: J.str(json['message']),
      );

  final WebExtractionJob job;

  /// How many lines were resolvable — and therefore how many scans were spent.
  final int queuedTargets;

  final String? message;
}

/// The outcome of reading a pasted website list.
@immutable
class DomainListParse {
  const DomainListParse({required this.domains, required this.rejected});

  static const DomainListParse empty =
      DomainListParse(domains: <String>[], rejected: <String>[]);

  /// Normalised, deduplicated, in the order they were first seen.
  final List<String> domains;

  /// The tokens that were not websites, verbatim, so the user can see which of
  /// their lines will not be scanned.
  final List<String> rejected;

  int get count => domains.length;

  bool get isEmpty => domains.isEmpty;
}

/// Reads a pasted list of websites.
///
/// This runs on the device so the create screen can show a live count and name
/// the lines that will not be scanned before the user spends anything. The
/// server parses the list again with `InputListParser` and its answer is the
/// one that bills; this is a courtesy, not a substitute.
abstract final class DomainList {
  /// The web caps the pasted text at 500 000 characters and a phone must not be
  /// able to submit a list the website would refuse.
  static const int maxInputLength = 500000;

  /// Separators: newlines, commas, semicolons and any whitespace. A domain
  /// never contains one of these, so splitting on all of them cannot break a
  /// value the way splitting on a comma alone would break a CSV cell.
  static final RegExp _separators = RegExp(r'[\s,;]+');

  /// A hostname with at least one dot and a two-letter-or-longer TLD. The
  /// `¡-￿` range keeps internationalised domains (münchen.de) valid
  /// while still rejecting "hello", "1234", "192.168.0.1" and "!!!.com".
  static final RegExp _hostname = RegExp(
    '^(?:[a-z0-9¡-￿]'
    '(?:[a-z0-9¡-￿-]{0,61}[a-z0-9¡-￿])?\\.)+'
    '[a-z¡-￿]{2,}\$',
  );

  static final RegExp _scheme = RegExp(r'^[a-z][a-z0-9+.-]*://');

  /// Quotes, brackets and sentence punctuation from a paste.
  static final RegExp _wrapping = RegExp('''^["'<(]+|["'>).]+\$''');

  static DomainListParse parse(String raw) {
    if (raw.trim().isEmpty) {
      return DomainListParse.empty;
    }

    final LinkedHashSet<String> domains = LinkedHashSet<String>();
    final LinkedHashSet<String> rejected = LinkedHashSet<String>();

    for (final String token in raw.split(_separators)) {
      final String trimmed = token.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final String? host = normalise(trimmed);
      if (host == null) {
        rejected.add(trimmed);
      } else {
        domains.add(host);
      }
    }

    return DomainListParse(
      domains: List<String>.unmodifiable(domains),
      rejected: List<String>.unmodifiable(rejected),
    );
  }

  /// Reduces one token to a bare hostname, or null when it is not a website.
  static String? normalise(String token) {
    String value = token.trim().toLowerCase();

    // Punctuation a paste from a sentence or a spreadsheet cell drags along.
    value = value.replaceAll(_wrapping, '');
    value = value.replaceFirst(_scheme, '');

    // An email address is the single most common thing people paste into a
    // website column; it is not a website.
    if (value.contains('@')) {
      return null;
    }

    // Path, query and fragment.
    for (final String cut in <String>['/', '?', '#']) {
      final int index = value.indexOf(cut);
      if (index >= 0) {
        value = value.substring(0, index);
      }
    }

    // Port.
    final int colon = value.indexOf(':');
    if (colon >= 0) {
      value = value.substring(0, colon);
    }

    // A fully qualified name may end in a dot.
    while (value.endsWith('.')) {
      value = value.substring(0, value.length - 1);
    }

    if (value.isEmpty || !_hostname.hasMatch(value)) {
      return null;
    }

    return value;
  }
}
