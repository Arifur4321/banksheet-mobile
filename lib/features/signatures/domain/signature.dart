/// E-signature models: the request, the people on it, and the audit trail.
///
/// Field names mirror `SignatureRequestResource`, `SignatureSignerResource` and
/// the event block that resource builds. Two omissions on the server are
/// deliberate and worth knowing about here: no signing token or anything
/// derived from it is published (it is a bearer credential for a third party),
/// and neither is the drawn signature image.
///
/// `signers` and `events` are null until the relations are loaded — the detail
/// endpoint — rather than absent, so both screens parse one shape. Null means
/// "not loaded", which is a different statement from an empty list, and
/// [SignatureRequest.hasDetail] is what tells them apart.
library;

import 'package:flutter/foundation.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';

/// The ten values `SignatureRequest::STATUS_*` can hold, plus a defensive
/// [unknown].
enum SignatureStatus {
  draft('draft'),
  guestDraft('guest_draft'),
  sent('sent'),
  viewed('viewed'),
  partiallySigned('partially_signed'),
  completed('completed'),
  declined('declined'),
  expired('expired'),
  error('error'),

  /// Provider finished, the signed file has not been retrieved yet. Counts as
  /// signed for progress, exactly as the server counts it.
  awaitingDownload('awaiting_download'),

  unknown('unknown');

  const SignatureStatus(this.wire);

  final String wire;

  static SignatureStatus from(String? raw) =>
      switch ((raw ?? '').trim().toLowerCase()) {
        'draft' => SignatureStatus.draft,
        'guest_draft' => SignatureStatus.guestDraft,
        'sent' => SignatureStatus.sent,
        'viewed' => SignatureStatus.viewed,
        'partially_signed' => SignatureStatus.partiallySigned,
        'completed' => SignatureStatus.completed,
        'declined' => SignatureStatus.declined,
        'expired' => SignatureStatus.expired,
        'error' => SignatureStatus.error,
        'awaiting_download' => SignatureStatus.awaitingDownload,
        _ => SignatureStatus.unknown,
      };

  /// `SignatureRequest::OPEN_STATUSES` — the ones a request can still progress
  /// from, and therefore the ones worth chasing.
  bool get isOpen =>
      this == SignatureStatus.sent ||
      this == SignatureStatus.viewed ||
      this == SignatureStatus.partiallySigned;

  /// Everyone has signed. `awaiting_download` is included because the signing
  /// is done — only the file transfer is outstanding.
  bool get isSigned =>
      this == SignatureStatus.completed ||
      this == SignatureStatus.awaitingDownload;

  bool get isDeclined => this == SignatureStatus.declined;

  /// Terminated without a signature.
  bool get isProblem =>
      this == SignatureStatus.declined ||
      this == SignatureStatus.expired ||
      this == SignatureStatus.error;
}

/// The five values `SignatureSigner::STATUS_*` can hold.
enum SignerStatus {
  pending('pending'),
  sent('sent'),
  viewed('viewed'),
  signed('signed'),
  declined('declined'),
  unknown('');

  const SignerStatus(this.wire);

  final String wire;

  static SignerStatus from(String? raw) =>
      switch ((raw ?? '').trim().toLowerCase()) {
        'pending' => SignerStatus.pending,
        'sent' => SignerStatus.sent,
        'viewed' => SignerStatus.viewed,
        'signed' => SignerStatus.signed,
        'declined' => SignerStatus.declined,
        _ => SignerStatus.unknown,
      };

  String get label => switch (this) {
        SignerStatus.pending => S.signerPending,
        SignerStatus.sent => S.signerInvited,
        SignerStatus.viewed => S.signerViewed,
        SignerStatus.signed => S.signerSigned,
        SignerStatus.declined => S.signerDeclined,
        SignerStatus.unknown => S.signerPending,
      };
}

/// Which PDF is being signed.
@immutable
class SignatureSource {
  const SignatureSource({this.type, this.id, this.label});

  factory SignatureSource.fromJson(Map<String, dynamic> json) =>
      SignatureSource(
        type: J.str(json['type']),
        id: J.intOrNull(json['id']),
        label: J.str(json['label']),
      );

  /// `generated_pdf`, `document`, or null when neither is attached.
  final String? type;

  final int? id;

  /// The server's own fallback chain for the document's name, so the app and
  /// the website never disagree about what a request is called.
  final String? label;

  bool get isEmpty => id == null && label == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignatureSource &&
          other.type == type &&
          other.id == id &&
          other.label == label;

  @override
  int get hashCode => Object.hash(type, id, label);
}

/// "2 of 3 signed" — the single fact the list exists to show.
@immutable
class SignatureProgress {
  const SignatureProgress({
    required this.total,
    required this.signed,
    required this.declined,
    required this.pending,
  });

  /// Resolves progress from the three sources, in the order the server itself
  /// prefers them.
  ///
  /// The loaded signer rows win when there are any, because they are the same
  /// data one step fresher. Failing that the server's own counts are used. The
  /// last branch is the one that matters in the field: a single-signer request
  /// has no `SignatureSigner` rows at all — the person is stored on the request
  /// — so without it every legacy request would render "0 of 0 signed".
  factory SignatureProgress.resolve({
    required Map<String, dynamic> raw,
    required SignatureStatus status,
    List<SignatureSigner>? signers,
  }) {
    if (signers != null && signers.isNotEmpty) {
      return SignatureProgress._count(signers);
    }

    final int total = J.intOr(raw['total'], 0);
    if (total > 0) {
      final int signed = J.intOr(raw['signed'], 0);
      final int declined = J.intOr(raw['declined'], 0);
      final int remaining = total - signed - declined;

      return SignatureProgress(
        total: total,
        signed: signed,
        declined: declined,
        // Recomputed rather than trusted: `pending` has to agree with the other
        // three or the progress line contradicts itself.
        pending: remaining < 0 ? 0 : remaining,
      );
    }

    final bool isSigned = status.isSigned;
    final bool isDeclined = status.isDeclined;

    return SignatureProgress(
      total: 1,
      signed: isSigned ? 1 : 0,
      declined: isDeclined ? 1 : 0,
      pending: isSigned || isDeclined ? 0 : 1,
    );
  }

  factory SignatureProgress._count(List<SignatureSigner> signers) {
    int signed = 0;
    int declined = 0;

    for (final SignatureSigner signer in signers) {
      if (signer.state == SignerStatus.signed) {
        signed++;
      } else if (signer.state == SignerStatus.declined) {
        declined++;
      }
    }

    return SignatureProgress(
      total: signers.length,
      signed: signed,
      declined: declined,
      pending: signers.length - signed - declined,
    );
  }

  final int total;
  final int signed;
  final int declined;
  final int pending;

  String get label => S.signerProgress(signed, total);

  double get ratio =>
      total <= 0 ? 0 : (signed / total).clamp(0.0, 1.0).toDouble();

  bool get isComplete => total > 0 && signed >= total;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignatureProgress &&
          other.total == total &&
          other.signed == signed &&
          other.declined == declined &&
          other.pending == pending;

  @override
  int get hashCode => Object.hash(total, signed, declined, pending);
}

/// One person on a request.
@immutable
class SignatureSigner {
  const SignatureSigner({
    required this.id,
    required this.sortOrder,
    required this.hasSigned,
    required this.isExpired,
    this.name,
    this.email,
    this.status,
    this.color,
    this.message,
    this.viewedAt,
    this.signedAt,
    this.declinedAt,
    this.declineReason,
    this.tokenExpiresAt,
    this.createdAt,
  });

  factory SignatureSigner.fromJson(Map<String, dynamic> json) =>
      SignatureSigner(
        id: J.intOr(json['id'], 0),
        name: J.str(json['name']),
        email: J.str(json['email']),
        sortOrder: J.intOr(json['sort_order'], 0),
        status: J.str(json['status']),
        color: J.str(json['color']),
        message: J.str(json['message']),
        viewedAt: J.date(json['viewed_at']),
        signedAt: J.date(json['signed_at']),
        declinedAt: J.date(json['declined_at']),
        declineReason: J.str(json['decline_reason']),
        hasSigned: J.boolOr(json['has_signed']),
        isExpired: J.boolOr(json['is_expired']),
        tokenExpiresAt: J.date(json['token_expires_at']),
        createdAt: J.date(json['created_at']),
      );

  final int id;
  final String? name;
  final String? email;

  /// For a sequential request this is the signing order, which is why the
  /// server returns the rows already ordered by it.
  final int sortOrder;

  /// The raw server string; [state] interprets it.
  final String? status;

  /// The colour the web editor gave this person's fields, so the same signer is
  /// the same colour on both clients.
  final String? color;

  final String? message;
  final DateTime? viewedAt;
  final DateTime? signedAt;
  final DateTime? declinedAt;
  final String? declineReason;

  /// Computed server-side.
  final bool hasSigned;

  /// Computed server-side, because the phone's clock is not authoritative and
  /// an expired link is the most common reason a request stalls.
  final bool isExpired;

  final DateTime? tokenExpiresAt;
  final DateTime? createdAt;

  SignerStatus get state => SignerStatus.from(status);

  String get displayName => name ?? email ?? S.signers;

  /// One or two letters for the timeline's avatar.
  String get initials {
    final String source = (name ?? email ?? '?').trim();
    if (source.isEmpty) {
      return '?';
    }
    final List<String> words = source
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .toList(growable: false);

    if (words.length == 1) {
      return words.first.substring(0, 1).toUpperCase();
    }
    return (words.first.substring(0, 1) + words[1].substring(0, 1))
        .toUpperCase();
  }

  /// The moment this signer last did something, for the timeline's caption.
  DateTime? get lastActivityAt => declinedAt ?? signedAt ?? viewedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignatureSigner &&
          other.id == id &&
          other.name == name &&
          other.email == email &&
          other.sortOrder == sortOrder &&
          other.status == status &&
          other.color == color &&
          other.message == message &&
          other.viewedAt == viewedAt &&
          other.signedAt == signedAt &&
          other.declinedAt == declinedAt &&
          other.declineReason == declineReason &&
          other.hasSigned == hasSigned &&
          other.isExpired == isExpired &&
          other.tokenExpiresAt == tokenExpiresAt &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        id,
        name,
        email,
        sortOrder,
        status,
        color,
        message,
        viewedAt,
        signedAt,
        declinedAt,
        declineReason,
        hasSigned,
        isExpired,
        tokenExpiresAt,
        createdAt,
      ]);
}

/// One entry in the audit trail.
///
/// `SignatureEvent` rows are immutable at the model layer — they are the
/// evidence that a signature happened — so the app shows them rather than
/// summarising them.
@immutable
class SignatureEvent {
  const SignatureEvent({
    required this.id,
    this.eventType,
    this.actorType,
    this.actorName,
    this.actorEmail,
    this.ipAddress,
    this.userAgent,
    this.metadata,
    this.createdAt,
  });

  factory SignatureEvent.fromJson(Map<String, dynamic> json) => SignatureEvent(
        id: J.intOr(json['id'], 0),
        eventType: J.str(json['event_type']),
        actorType: J.str(json['actor_type']),
        actorName: J.str(json['actor_name']),
        actorEmail: J.str(json['actor_email']),
        ipAddress: J.str(json['ip_address']),
        userAgent: J.str(json['user_agent']),
        metadata: json['metadata'] == null ? null : J.map(json['metadata']),
        createdAt: J.date(json['created_at']),
      );

  final int id;

  /// `sent`, `viewed`, `signed`, `declined`, `completed`, `signer_invited`,
  /// `signer_viewed`, `signer_signed`, `signer_declined` — free text on the
  /// server, so it is humanised rather than matched against a closed set.
  final String? eventType;

  /// `employee`, `signer` or `system`.
  final String? actorType;

  final String? actorName;
  final String? actorEmail;
  final String? ipAddress;
  final String? userAgent;
  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;

  String get title => Fmt.humanise(eventType);

  /// Who did it, with no invented detail: the name if there is one, otherwise
  /// the email, otherwise the actor type.
  String? get actor => actorName ?? actorEmail ?? Fmt.humanise(actorType);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignatureEvent &&
          other.id == id &&
          other.eventType == eventType &&
          other.actorType == actorType &&
          other.actorName == actorName &&
          other.actorEmail == actorEmail &&
          other.ipAddress == ipAddress &&
          other.userAgent == userAgent &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        id,
        eventType,
        actorType,
        actorName,
        actorEmail,
        ipAddress,
        userAgent,
        createdAt,
      ]);
}

/// An e-signature request.
@immutable
class SignatureRequest {
  const SignatureRequest({
    required this.id,
    required this.status,
    required this.source,
    required this.progress,
    required this.ccEmails,
    required this.isMultiSigner,
    required this.signedFileAvailable,
    required this.signedFilename,
    this.title,
    this.subject,
    this.message,
    this.provider,
    this.signingMode,
    this.signerName,
    this.signerEmail,
    this.signerPhone,
    this.signers,
    this.events,
    this.eventsCount,
    this.sentAt,
    this.viewedAt,
    this.signedAt,
    this.declinedAt,
    this.completedAt,
    this.expiresAt,
    this.lastEventAt,
    this.errorMessage,
    this.downloadUrl,
    this.createdAt,
    this.updatedAt,
  });

  factory SignatureRequest.fromJson(Map<String, dynamic> json) {
    final String status = J.strOr(json['status'], SignatureStatus.unknown.wire);
    final SignatureStatus state = SignatureStatus.from(status);

    final List<SignatureSigner>? signers = json['signers'] == null
        ? null
        : (J
            .list(json['signers'])
            .map(SignatureSigner.fromJson)
            .toList(growable: false)
          ..sort((SignatureSigner a, SignatureSigner b) =>
              a.sortOrder.compareTo(b.sortOrder)));

    return SignatureRequest(
      id: J.intOr(json['id'], 0),
      title: J.str(json['title']),
      subject: J.str(json['subject']),
      message: J.str(json['message']),
      status: status,
      provider: J.str(json['provider']),
      signingMode: J.str(json['signing_mode']),
      isMultiSigner: J.boolOr(json['is_multi_signer']),
      source: SignatureSource.fromJson(J.map(json['source'])),
      signerName: J.str(json['signer_name']),
      signerEmail: J.str(json['signer_email']),
      signerPhone: J.str(json['signer_phone']),
      ccEmails: J.strings(json['cc_emails']),
      progress: SignatureProgress.resolve(
        raw: J.map(json['progress']),
        status: state,
        signers: signers,
      ),
      signers: signers,
      events: json['events'] == null
          ? null
          : J
              .list(json['events'])
              .map(SignatureEvent.fromJson)
              .toList(growable: false),
      eventsCount: J.intOrNull(json['events_count']),
      sentAt: J.date(json['sent_at']),
      viewedAt: J.date(json['viewed_at']),
      signedAt: J.date(json['signed_at']),
      declinedAt: J.date(json['declined_at']),
      completedAt: J.date(json['completed_at']),
      expiresAt: J.date(json['expires_at']),
      lastEventAt: J.date(json['last_event_at']),
      errorMessage: J.str(json['error_message']),
      signedFileAvailable: J.boolOr(json['signed_file_available']),
      signedFilename: J.strOr(json['signed_filename'], 'signed-document.pdf'),
      downloadUrl: J.str(json['download_url']),
      createdAt: J.date(json['created_at']),
      updatedAt: J.date(json['updated_at']),
    );
  }

  final int id;
  final String? title;
  final String? subject;
  final String? message;

  /// The raw server string, kept verbatim so [StatusBadge] can colour it and so
  /// a value this build has never seen still round-trips. [state] interprets it.
  final String status;

  /// `internal` for requests this product signs itself.
  final String? provider;

  /// `sequential` or `parallel`.
  final String? signingMode;

  final bool isMultiSigner;
  final SignatureSource source;

  /// Still populated for a multi-signer request, where they hold the *first*
  /// signer — which is why [signers] and [progress] are what the app renders
  /// when [isMultiSigner].
  final String? signerName;
  final String? signerEmail;
  final String? signerPhone;

  final List<String> ccEmails;
  final SignatureProgress progress;

  /// Null until the relation is loaded — the detail endpoint.
  final List<SignatureSigner>? signers;

  /// Null until the relation is loaded. Newest first, as the server orders it.
  final List<SignatureEvent>? events;

  final int? eventsCount;
  final DateTime? sentAt;
  final DateTime? viewedAt;
  final DateTime? signedAt;
  final DateTime? declinedAt;
  final DateTime? completedAt;
  final DateTime? expiresAt;
  final DateTime? lastEventAt;
  final String? errorMessage;

  /// The signed PDF exists on disk right now.
  final bool signedFileAvailable;

  final String signedFilename;

  /// Null until the signed file exists.
  final String? downloadUrl;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName => title ?? source.label ?? S.signatures;

  SignatureStatus get state => SignatureStatus.from(status);

  /// True when this instance came from the detail endpoint.
  bool get hasDetail => signers != null || events != null;

  bool get isOpen => state.isOpen;

  bool get canDownloadSigned => signedFileAvailable;

  /// The people to render. Falls back to the single-signer fields, which is the
  /// only place that person exists for a legacy request.
  List<SignatureSigner> get signerList {
    final List<SignatureSigner>? loaded = signers;
    if (loaded != null && loaded.isNotEmpty) {
      return loaded;
    }
    if (signerName == null && signerEmail == null) {
      return const <SignatureSigner>[];
    }

    return <SignatureSigner>[
      SignatureSigner(
        id: 0,
        sortOrder: 0,
        name: signerName,
        email: signerEmail,
        // Derived from the request, because a single-signer request keeps no
        // signer row of its own to read a status from.
        status: switch (state) {
          SignatureStatus.completed ||
          SignatureStatus.awaitingDownload =>
            SignerStatus.signed.wire,
          SignatureStatus.declined => SignerStatus.declined.wire,
          SignatureStatus.viewed ||
          SignatureStatus.partiallySigned =>
            SignerStatus.viewed.wire,
          SignatureStatus.sent => SignerStatus.sent.wire,
          _ => SignerStatus.pending.wire,
        },
        viewedAt: viewedAt,
        signedAt: signedAt,
        declinedAt: declinedAt,
        hasSigned: state.isSigned,
        isExpired: state == SignatureStatus.expired,
      ),
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignatureRequest &&
          other.id == id &&
          other.title == title &&
          other.subject == subject &&
          other.message == message &&
          other.status == status &&
          other.provider == provider &&
          other.signingMode == signingMode &&
          other.isMultiSigner == isMultiSigner &&
          other.source == source &&
          other.signerName == signerName &&
          other.signerEmail == signerEmail &&
          other.signerPhone == signerPhone &&
          listEquals(other.ccEmails, ccEmails) &&
          other.progress == progress &&
          listEquals(other.signers, signers) &&
          listEquals(other.events, events) &&
          other.eventsCount == eventsCount &&
          other.sentAt == sentAt &&
          other.viewedAt == viewedAt &&
          other.signedAt == signedAt &&
          other.declinedAt == declinedAt &&
          other.completedAt == completedAt &&
          other.expiresAt == expiresAt &&
          other.lastEventAt == lastEventAt &&
          other.errorMessage == errorMessage &&
          other.signedFileAvailable == signedFileAvailable &&
          other.signedFilename == signedFilename &&
          other.downloadUrl == downloadUrl &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        id,
        title,
        subject,
        message,
        status,
        provider,
        signingMode,
        isMultiSigner,
        source,
        signerName,
        signerEmail,
        signerPhone,
        progress,
        eventsCount,
        sentAt,
        viewedAt,
        signedAt,
        declinedAt,
        completedAt,
        expiresAt,
        lastEventAt,
        errorMessage,
        signedFileAvailable,
        signedFilename,
        downloadUrl,
        createdAt,
        updatedAt,
      ]);
}
