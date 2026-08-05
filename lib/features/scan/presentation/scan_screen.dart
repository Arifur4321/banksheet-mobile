/// Scan to PDF.
///
/// The free feature, and for most new installs the first thing the app is ever
/// asked to do. It therefore has to work with no account, no network and no
/// prior explanation — so everything it needs happens on the device, and the
/// only wall is the one at the end.
///
/// Layout follows the shape of the job rather than the shape of the data:
///
///   * **Empty** — two large targets, camera and gallery, and a line saying how
///     many free PDFs are left. Nothing else; a first-run user with an empty
///     page grid does not need a toolbar.
///   * **With pages** — a reorderable grid of thumbnails with a delete on each,
///     an "Add page" tile in the flow, and a persistent bottom bar carrying the
///     page count and the one primary action.
///
/// The primary action is deliberately a bottom bar and not a FAB. A FAB floats
/// over the last row of a grid, and the last row of this grid is where the "add
/// another page" tile lives — the two would fight for the same corner on every
/// scan longer than six pages.
library;

// `PathMetric` is not among the dart:ui types `package:flutter/painting.dart`
// re-exports, so the dashed outline at the bottom of this file needs it by name.
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/states.dart';
import '../data/scan_repository.dart';
import '../domain/scan_page.dart';
import 'providers.dart';
import 'widgets/scan_page_tile.dart';
import 'widgets/scan_paywall_sheet.dart';
import 'widgets/scan_result_sheet.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, this.startWith});

  /// Which picker to open on arrival.
  ///
  /// The welcome and home screens promise "Scan to PDF", and landing on an
  /// empty screen that then asks *how* is one tap of hesitation at exactly the
  /// wrong moment. Passing `ScanSource.camera` opens the camera immediately and
  /// the grid is what the user comes back to.
  final ScanSource? startWith;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _autoStarted = false;

  @override
  void initState() {
    super.initState();

    // After the first frame: opening a platform picker during build races the
    // route transition, and on iOS the sheet can be presented on a view
    // controller that is still animating in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoStarted || widget.startWith == null) {
        return;
      }
      _autoStarted = true;
      final ScanController c = ref.read(scanControllerProvider.notifier);
      if (ref.read(scanControllerProvider).isEmpty) {
        switch (widget.startWith!) {
          case ScanSource.camera:
            c.addFromCamera();
          case ScanSource.gallery:
            c.addFromGallery();
        }
      }
    });
  }

  Future<void> _create() async {
    final ScanController controller = ref.read(scanControllerProvider.notifier);
    final bool signedIn = ref.read(tokenStoreProvider).hasSession;

    // A signed-in account is what unlocked unlimited scanning, so nothing is
    // counted for them — see ScanRepository.buildPdf.
    if (!signedIn) {
      final bool allowed =
          await ref.read(scanRepositoryProvider).hasFreeQuota();
      if (!allowed) {
        if (mounted) {
          await showScanPaywall(context);
        }
        return;
      }
    }

    final ScanResult? result =
        await controller.build(metered: !signedIn);

    if (!mounted) {
      return;
    }

    if (result == null) {
      final Object? error = ref.read(scanControllerProvider).error;
      _showError(error);
      return;
    }

    controller.clear();
    await showScanResult(context, result);
  }

  void _showError(Object? error) {
    final String message = switch (error) {
      ScanPageUnreadable(:final int pageNumber) =>
        'Page $pageNumber could not be read. Remove it and try again.',
      ScanQuotaExhausted() =>
        'You have used all ${AppConfig.freeScanPdfs} free PDFs.',
      null => 'The PDF could not be created.',
      _ => 'The PDF could not be created. Please try again.',
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDiscard() async {
    if (ref.read(scanControllerProvider).isEmpty) {
      if (mounted) {
        context.pop();
      }
      return;
    }

    final bool discard = await confirmAction(
      context,
      title: 'Discard this scan?',
      message: 'The pages you captured will not be saved.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (!discard || !mounted) {
      return;
    }
    ref.read(scanControllerProvider.notifier).clear();
    if (mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ScanState scan = ref.watch(scanControllerProvider);
    final ScanController controller = ref.read(scanControllerProvider.notifier);
    final bool signedIn = ref.watch(tokenStoreProvider).hasSession;
    final AsyncValue<int> left = ref.watch(freeScansLeftProvider);

    return PopScope<void>(
      // The pages only exist in memory; a swipe back with six captures taken
      // and no warning is the kind of loss a user does not forgive.
      canPop: scan.isEmpty,
      onPopInvokedWithResult: (bool didPop, void _) {
        if (!didPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          title: const Text('Scan to PDF'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
            onPressed: _confirmDiscard,
          ),
        ),
        body: SafeArea(
          child: scan.isEmpty
              ? _EmptyScan(
                  busy: scan.isBusy,
                  signedIn: signedIn,
                  freeLeft: left.valueOrNull,
                  onCamera: controller.addFromCamera,
                  onGallery: controller.addFromGallery,
                )
              : _PageGrid(
                  scan: scan,
                  controller: controller,
                  onAdd: () => _showAddSheet(controller),
                ),
        ),
        bottomNavigationBar: scan.isEmpty
            ? null
            : _CreateBar(
                scan: scan,
                signedIn: signedIn,
                freeLeft: left.valueOrNull,
                onCreate: _create,
              ),
      ),
    );
  }

  Future<void> _showAddSheet(ScanController controller) async {
    final ScanSource? source = await showModalBottomSheet<ScanSource>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(ctx).pop(ScanSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(ScanSource.gallery),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );

    switch (source) {
      case ScanSource.camera:
        await controller.addFromCamera();
      case ScanSource.gallery:
        await controller.addFromGallery();
      case null:
        break;
    }
  }
}

/// The first screen of a scan: pick a source.
class _EmptyScan extends StatelessWidget {
  const _EmptyScan({
    required this.busy,
    required this.signedIn,
    required this.freeLeft,
    required this.onCamera,
    required this.onGallery,
  });

  final bool busy;
  final bool signedIn;
  final int? freeLeft;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: <Widget>[
        const SizedBox(height: AppSpacing.sm),
        Text('Make a PDF from photos', style: AppText.h1),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Photograph each page, or pick images you already have. '
          'Everything happens on this phone — nothing is uploaded.',
          style: AppText.body.copyWith(color: AppColors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.xxl),

        _SourceCard(
          icon: Icons.photo_camera_rounded,
          title: 'Take a photo',
          body: 'Use the camera, one page at a time.',
          primary: true,
          enabled: !busy,
          onTap: onCamera,
        ),
        const SizedBox(height: AppSpacing.md),
        _SourceCard(
          icon: Icons.photo_library_rounded,
          title: 'Choose from gallery',
          body: 'Select one or more images at once.',
          enabled: !busy,
          onTap: onGallery,
        ),

        if (!signedIn && freeLeft != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          InlineNotice(
            tone: freeLeft! > 0 ? NoticeTone.info : NoticeTone.warn,
            message: freeLeft! > 0
                ? '$freeLeft of ${AppConfig.freeScanPdfs} free PDFs left. '
                    'Create a free account for unlimited scanning.'
                : 'You have used all ${AppConfig.freeScanPdfs} free PDFs. '
                    'Create a free account to keep scanning.',
            actionLabel: 'Create account',
            onAction: () => context.pushNamed(AppRoute.register),
          ),
        ],
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.enabled,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool enabled;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg = primary ? AppColors.inkStrong : AppColors.surface;
    final Color fg = primary ? AppColors.inkInverse : AppColors.ink;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: bg,
        borderRadius: AppRadius.cardAll,
        child: InkWell(
          borderRadius: AppRadius.cardAll,
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              borderRadius: AppRadius.cardAll,
              border: primary
                  ? null
                  : Border.all(color: AppColors.border),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primary
                        ? AppColors.brandLight.withValues(alpha: 0.16)
                        : AppColors.brandTint,
                    borderRadius: AppRadius.smallAll,
                  ),
                  child: Icon(
                    icon,
                    color: primary ? AppColors.brandLight : AppColors.brandDeep,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: AppText.bodyStrong.copyWith(color: fg)),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: AppText.caption.copyWith(
                          color: primary
                              ? AppColors.inkInverse.withValues(alpha: 0.66)
                              : AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: primary
                      ? AppColors.inkInverse.withValues(alpha: 0.5)
                      : AppColors.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The captured pages, reorderable.
class _PageGrid extends StatelessWidget {
  const _PageGrid({
    required this.scan,
    required this.controller,
    required this.onAdd,
  });

  final ScanState scan;
  final ScanController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        if (scan.error is ScanTooManyPages)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.md,
              AppSpacing.page,
              0,
            ),
            child: InlineNotice(
              tone: NoticeTone.warn,
              message: 'A PDF can hold ${ScanController.maxPages} pages. '
                  'The extra images were not added.',
            ),
          ),
        Expanded(
          // ReorderableListView rather than a grid: dragging to reorder in a
          // wrapping grid needs a custom drag target per cell, and a scan is a
          // sequence — page 4 goes after page 3, not "somewhere on row two".
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.md,
              AppSpacing.page,
              AppSpacing.md,
            ),
            itemCount: scan.pageCount,
            onReorder: controller.reorder,
            proxyDecorator: (Widget child, int index, Animation<double> a) =>
                Material(
              color: Colors.transparent,
              elevation: 8,
              borderRadius: AppRadius.cardAll,
              shadowColor: AppColors.forest.withValues(alpha: 0.4),
              child: child,
            ),
            footer: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: _AddPageTile(
                enabled: !scan.isBusy && scan.pageCount < ScanController.maxPages,
                full: scan.pageCount >= ScanController.maxPages,
                onTap: onAdd,
              ),
            ),
            itemBuilder: (BuildContext context, int i) => Padding(
              key: ValueKey<String>(scan.pages[i].id),
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: ScanPageTile(
                page: scan.pages[i],
                index: i,
                onRemove: () => controller.removeAt(i),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddPageTile extends StatelessWidget {
  const _AddPageTile({
    required this.enabled,
    required this.full,
    required this.onTap,
  });

  final bool enabled;
  final bool full;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: enabled ? onTap : null,
        child: DottedOutline(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  full ? Icons.block_rounded : Icons.add_rounded,
                  size: 20,
                  color: enabled ? AppColors.brandDeep : AppColors.inkFaint,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  full
                      ? 'Maximum ${ScanController.maxPages} pages'
                      : 'Add page',
                  style: AppText.bodyStrong.copyWith(
                    color: enabled ? AppColors.brandDeep : AppColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The persistent action bar.
class _CreateBar extends StatelessWidget {
  const _CreateBar({
    required this.scan,
    required this.signedIn,
    required this.freeLeft,
    required this.onCreate,
  });

  final ScanState scan;
  final bool signedIn;
  final int? freeLeft;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final bool building = scan.phase == ScanPhase.building;
    final String pages =
        '${scan.pageCount} ${scan.pageCount == 1 ? 'page' : 'pages'}';

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(pages, style: AppText.bodyStrong),
                    if (!signedIn && freeLeft != null)
                      Text(
                        freeLeft! > 0
                            ? '$freeLeft of ${AppConfig.freeScanPdfs} free PDFs left'
                            : 'Free PDFs used — account required',
                        style: AppText.caption,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              FilledButton.icon(
                onPressed: building ? null : onCreate,
                icon: building
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.inkInverse,
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 20),
                label: Text(building ? 'Creating…' : 'Create PDF'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed border, drawn rather than imported.
///
/// Flutter has no dashed border, and the usual answer is a package. One
/// painter is cheaper than a dependency for a single decorative outline.
class DottedOutline extends StatelessWidget {
  const DottedOutline({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashPainter(),
      child: child,
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = AppColors.borderStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final Path outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0.7, 0.7, size.width - 1.4, size.height - 1.4),
          const Radius.circular(AppRadius.card),
        ),
      );

    const double dash = 6;
    const double gap = 5;
    for (final PathMetric metric in outline.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, (d + dash).clamp(0.0, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}
