/// One signature request, end to end.
///
/// Status first, then the people in signing order, then the audit trail — which
/// is shown in full rather than summarised because those rows are immutable at
/// the model layer for a reason: they are the evidence that a signature
/// happened. The signed PDF can be downloaded and shared the moment it exists.
///
/// Read-only in v1, and the screen says so in one line instead of ending in a
/// button that is not there.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../../exports/data/file_downloader.dart';
import '../data/signature_repository.dart';
import '../domain/signature.dart';
import 'providers.dart';
import 'widgets/signature_status_header.dart';
import 'widgets/signer_timeline.dart';

class SignatureDetailScreen extends ConsumerStatefulWidget {
  const SignatureDetailScreen({required this.signatureId, super.key});

  final int signatureId;

  @override
  ConsumerState<SignatureDetailScreen> createState() =>
      _SignatureDetailScreenState();
}

class _SignatureDetailScreenState
    extends ConsumerState<SignatureDetailScreen> {
  bool _isTransferring = false;

  Future<void> _transfer(
    SignatureRequest request,
    FileAction action,
    Rect? origin,
  ) async {
    if (_isTransferring) {
      return;
    }
    setState(() => _isTransferring = true);

    try {
      final File file = await ref.read(signatureRepositoryProvider).download(
            request.id,
            filename: request.signedFilename,
          );
      if (!context.mounted) {
        return;
      }
      await FileDownloader.apply(
        action,
        file,
        subject: request.displayName,
        origin: origin,
      );
      if (!context.mounted) {
        return;
      }
      if (action == FileAction.save) {
        Toast.success(context, S.savedToDevice);
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      Toast.error(context, error);
    } finally {
      if (mounted) {
        setState(() => _isTransferring = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<SignatureRequest> state =
        ref.watch(signatureDetailProvider(widget.signatureId));

    return PageScaffold(
      title: state.valueOrNull?.displayName ?? S.signatures,
      showBack: true,
      scrollable: true,
      onRefresh: () =>
          ref.refresh(signatureDetailProvider(widget.signatureId).future),
      child: state.when(
        loading: () => const _DetailSkeleton(),
        error: (Object error, _) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.section),
          child: ErrorState(
            error: error,
            onRetry: () =>
                ref.invalidate(signatureDetailProvider(widget.signatureId)),
            onUpgrade: () => context.pushNamed(AppRoute.billing),
          ),
        ),
        data: _buildDetail,
      ),
    );
  }

  Widget _buildDetail(SignatureRequest request) {
    final List<SignatureSigner> signers = request.signerList;
    final List<SignatureEvent> events =
        request.events ?? const <SignatureEvent>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SignatureStatusHeader(request: request),
        const SizedBox(height: AppSpacing.xl),
        _Facts(request: request),
        const SizedBox(height: AppSpacing.xl),
        if (request.canDownloadSigned)
          _DownloadRow(
            isBusy: _isTransferring,
            onAction: (FileAction action, Rect? origin) =>
                _transfer(request, action, origin),
          )
        // Promising a signed PDF "once everyone has signed" would be a lie on a
        // request that was declined or has expired.
        else if (!request.state.isProblem)
          const InlineNotice(message: S.signedPdfPending),
        const SizedBox(height: AppSpacing.section),
        SectionHeader(
          title: S.signers,
          subtitle: request.progress.label,
        ),
        if (signers.isEmpty)
          const Text(S.noSignersRecorded, style: AppText.bodySm)
        else
          SignerTimeline(signers: signers),
        const SizedBox(height: AppSpacing.section),
        SectionHeader(
          title: S.auditTrail,
          subtitle: request.eventsCount == null
              ? null
              : S.eventCount(request.eventsCount!),
        ),
        if (events.isEmpty)
          const Text(S.noAuditEvents, style: AppText.bodySm)
        else
          _EventList(events: events),
        const SizedBox(height: AppSpacing.xl),
        const Text(
          S.signaturesReadOnly,
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.section),
      ],
    );
  }
}

/// The handful of facts worth stating outright: which document, how it is being
/// signed, and who was copied.
class _Facts extends StatelessWidget {
  const _Facts({required this.request});

  final SignatureRequest request;

  @override
  Widget build(BuildContext context) {
    final List<(String, String)> rows = <(String, String)>[
      if (request.source.label != null)
        (S.signatureDocument, request.source.label!),
      if (request.provider != null)
        (S.signatureProvider, Fmt.humanise(request.provider)),
      if (request.signingMode != null)
        (S.signingOrder, Fmt.humanise(request.signingMode)),
      if (request.subject != null) (S.emailSubject, request.subject!),
      if (request.ccEmails.isNotEmpty)
        (S.copiedTo, request.ccEmails.join(', ')),
    ];

    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < rows.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == rows.length - 1 ? 0 : AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 108,
                    child: Text(rows[i].$1, style: AppText.bodySm),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      rows[i].$2,
                      style: AppText.bodySm.copyWith(color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Download and share the signed PDF.
class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.isBusy, required this.onAction});

  final bool isBusy;
  final void Function(FileAction action, Rect? origin) onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: isBusy ? null : () => onAction(FileAction.open, null),
            icon: isBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.inkInverse,
                    ),
                  )
                : const Icon(Icons.download_rounded, size: 19),
            label: Text(isBusy ? S.downloading : S.downloadSigned),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Builder(
          builder: (BuildContext buttonContext) => IconButton.filledTonal(
            onPressed: isBusy
                ? null
                : () => onAction(
                      FileAction.share,
                      FileDownloader.originOf(buttonContext),
                    ),
            tooltip: S.share,
            icon: const Icon(Icons.ios_share_rounded, size: 20),
          ),
        ),
      ],
    );
  }
}

/// The audit trail, newest first, exactly as the server ordered it.
class _EventList extends StatelessWidget {
  const _EventList({required this.events});

  final List<SignatureEvent> events;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < events.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: AppSpacing.xl),
            _EventRow(event: events[i]),
          ],
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final SignatureEvent event;

  @override
  Widget build(BuildContext context) {
    final String? actor = event.actor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 6),
          decoration: const BoxDecoration(
            color: AppColors.brand,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(event.title, style: AppText.bodyStrong),
              const SizedBox(height: 2),
              Text(
                <String>[
                  if (actor != null) actor,
                  Fmt.dateTime(event.createdAt),
                ].join(' · '),
                style: AppText.caption,
              ),
              if (event.ipAddress != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(event.ipAddress!, style: AppText.caption),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The detail's shape while it loads, so the screen does not jump.
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Skeleton(height: 132, radius: AppRadius.card),
        SizedBox(height: AppSpacing.xl),
        Skeleton(height: 96, radius: AppRadius.card),
        SizedBox(height: AppSpacing.xl),
        Skeleton(height: 48, radius: AppRadius.control),
        SizedBox(height: AppSpacing.section),
        Skeleton(width: 120, height: 15),
        SizedBox(height: AppSpacing.lg),
        Skeleton(height: 64, radius: AppRadius.control),
        SizedBox(height: AppSpacing.md),
        Skeleton(height: 64, radius: AppRadius.control),
      ],
    );
  }
}
