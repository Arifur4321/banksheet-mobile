/// Scan to PDF.
///
/// The free feature, and for most new installs the first thing the app is ever
/// asked to do. It therefore has to work with no account, no network and no
/// prior explanation — so everything it needs happens on the device, and the
/// only wall is the one at the end.
///
/// **A note on why this screen is deliberately boring.** The first version used
/// [ReorderableListView] for drag-to-reorder, a [CustomPaint] dashed border and
/// a footer slot. On a real device it rendered blank in release and threw
/// `'_dependents.isEmpty': is not true` in debug — a framework assertion that
/// fires when an inherited element is unmounted with dependents still attached,
/// which `ReorderableListView`'s internal `GlobalKey` reparenting is a known way
/// to provoke. Reordering four scanned pages is not worth a screen that can
/// fail to paint. It is now a plain [ListView] with explicit move controls, and
/// every widget on it is one that has been in Flutter since 1.0.
///
/// Layout follows the shape of the job:
///
///   * **Empty** — two large targets, camera and gallery, and a line saying how
///     many free PDFs are left.
///   * **With pages** — a list of page cards with move/delete on each, an
///     "Add page" button at the end of the list, and a persistent bottom bar
///     carrying the page count and the one primary action.
library;

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
  /// The welcome and home screens promise "Scan to PDF", and landing on a
  /// screen that then asks *how* is one tap of hesitation at the wrong moment.
  final ScanSource? startWith;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen>
    with WidgetsBindingObserver {
  bool _autoStarted = false;

  /// True while the discard confirmation sheet is on screen.
  bool _discarding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // After the first frame: opening a platform picker during build races the
    // route transition, and on iOS the sheet can be presented on a view
    // controller that is still animating in.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      // Android can kill this process while the camera app is in the
      // foreground. The photo was still taken; it is waiting in the picker's
      // cache and is lost forever unless it is claimed here. This is the whole
      // explanation for "I took a photo and nothing happened".
      await ref.read(scanControllerProvider.notifier).recoverLostCaptures();

      if (!mounted || _autoStarted || widget.startWith == null) {
        return;
      }
      _autoStarted = true;
      if (ref.read(scanControllerProvider).isEmpty) {
        _start(widget.startWith!);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the camera after the OS reclaimed us: same recovery.
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(scanControllerProvider.notifier).recoverLostCaptures();
    }
  }

  void _start(ScanSource source) {
    final ScanController c = ref.read(scanControllerProvider.notifier);
    switch (source) {
      case ScanSource.camera:
        c.addFromCamera();
      case ScanSource.gallery:
        c.addFromGallery();
    }
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

    final ScanResult? result = await controller.build(metered: !signedIn);

    if (!mounted) {
      return;
    }

    if (result == null) {
      _showError(ref.read(scanControllerProvider).error);
      return;
    }

    controller.clear();
    await showScanResult(context, result);
  }

  void _showError(Object? error) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(describeScanError(error))));
  }

  Future<void> _confirmDiscard() async {
    // Two entry points reach this — the system Back gesture through [PopScope]
    // and the ✕ in the app bar — so a second Back while the sheet is already up
    // would otherwise stack a second identical sheet, and dismissing one would
    // leave the other on screen.
    if (_discarding) {
      return;
    }

    if (ref.read(scanControllerProvider).isEmpty) {
      if (mounted) {
        context.pop();
      }
      return;
    }

    _discarding = true;
    final bool discard;
    try {
      discard = await confirmAction(
        context,
        title: 'Discard this scan?',
        message: 'The pages you captured will not be saved.',
        confirmLabel: 'Discard',
        destructive: true,
      );
    } finally {
      _discarding = false;
    }

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
    final bool signedIn = ref.watch(tokenStoreProvider).hasSession;
    final AsyncValue<int> left = ref.watch(freeScansLeftProvider);

    return PopScope(
      // The pages only exist in memory; a swipe back with six captures taken
      // and no warning is the kind of loss a user does not forgive.
      canPop: scan.isEmpty,
      onPopInvokedWithResult: (bool didPop, Object? result) {
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
                  error: scan.error,
                  onCamera: () => _start(ScanSource.camera),
                  onGallery: () => _start(ScanSource.gallery),
                )
              : _PageList(
                  scan: scan,
                  onAdd: _showAddSheet,
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

  Future<void> _showAddSheet() async {
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

    if (source != null && mounted) {
      _start(source);
    }
  }
}

/// Turns anything the scanner can throw into one sentence a user can act on.
///
/// Public because three places show it — the snack bar, the empty state and the
/// page list — and three slightly different wordings for the same failure is
/// how a support conversation becomes unanswerable.
String describeScanError(Object? error) {
  return switch (error) {
    ScanPageUnreadable(:final int pageNumber) =>
      'Page $pageNumber could not be read. Remove it and try again.',
    ScanQuotaExhausted() =>
      'You have used all ${AppConfig.freeScanPdfs} free PDFs.',
    ScanTooManyPages(:final int limit) =>
      'A PDF can hold $limit pages. The extra images were not added.',
    ScanPickerFailed(:final String detail) => detail,
    null => 'Something went wrong.',
    _ => 'That did not work. Please try again.',
  };
}

/// The first screen of a scan: pick a source.
class _EmptyScan extends StatelessWidget {
  const _EmptyScan({
    required this.busy,
    required this.signedIn,
    required this.freeLeft,
    required this.error,
    required this.onCamera,
    required this.onGallery,
  });

  final bool busy;
  final bool signedIn;
  final int? freeLeft;
  final Object? error;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    // Every child carries an explicit key.
    //
    // `ListView(children: ...)` matches old elements to new ones by POSITION,
    // and the two conditional blocks below insert rows in the MIDDLE of the
    // list. Unkeyed, the moment a camera failure sets `error`, position 5 stops
    // being the "Take a photo" card and becomes the notice — so Flutter tears
    // down that card's whole `Material`/`InkWell` subtree, inherited elements
    // and all, during the very build that the tap which caused the failure is
    // still settling. Keys make the two rows an insertion instead of a
    // reshuffle: the cards keep their elements and nothing is deactivated.
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: <Widget>[
        const SizedBox(key: ValueKey<String>('scan-gap-top'), height: AppSpacing.sm),
        Text(
          'Make a PDF from photos',
          key: const ValueKey<String>('scan-title'),
          style: AppText.h1,
        ),
        const SizedBox(key: ValueKey<String>('scan-gap-title'), height: AppSpacing.xs),
        Text(
          'Photograph each page, or pick images you already have. '
          'Everything happens on this phone — nothing is uploaded.',
          key: const ValueKey<String>('scan-blurb'),
          style: AppText.body.copyWith(color: AppColors.inkMuted),
        ),

        if (error != null) ...<Widget>[
          const SizedBox(key: ValueKey<String>('scan-gap-error'), height: AppSpacing.lg),
          InlineNotice(
            key: const ValueKey<String>('scan-error'),
            tone: NoticeTone.warn,
            message: describeScanError(error),
          ),
        ],

        const SizedBox(key: ValueKey<String>('scan-gap-sources'), height: AppSpacing.xxl),
        _SourceCard(
          key: const ValueKey<String>('scan-source-camera'),
          icon: Icons.photo_camera_rounded,
          title: 'Take a photo',
          body: 'Use the camera, one page at a time.',
          primary: true,
          enabled: !busy,
          onTap: onCamera,
        ),
        const SizedBox(key: ValueKey<String>('scan-gap-between'), height: AppSpacing.md),
        _SourceCard(
          key: const ValueKey<String>('scan-source-gallery'),
          icon: Icons.photo_library_rounded,
          title: 'Choose from gallery',
          body: 'Select one or more images at once.',
          enabled: !busy,
          onTap: onGallery,
        ),

        if (!signedIn && freeLeft != null) ...<Widget>[
          const SizedBox(key: ValueKey<String>('scan-gap-quota'), height: AppSpacing.xl),
          InlineNotice(
            key: const ValueKey<String>('scan-quota'),
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
    super.key,
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
              border: primary ? null : Border.all(color: AppColors.border),
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

/// The captured pages.
///
/// A plain [ListView.builder]. The last row is the "Add page" button rather
/// than a separate footer slot, so there is exactly one scrollable and no
/// index bookkeeping between two of them.
class _PageList extends ConsumerWidget {
  const _PageList({required this.scan, required this.onAdd});

  final ScanState scan;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ScanController controller = ref.read(scanControllerProvider.notifier);
    final bool full = scan.pageCount >= ScanController.maxPages;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.md,
        AppSpacing.page,
        AppSpacing.md,
      ),
      // +1 for the trailing "Add page" row, +1 for the notice when there is one.
      itemCount: scan.pageCount + (scan.error != null ? 2 : 1),
      itemBuilder: (BuildContext context, int i) {
        final int offset = scan.error != null ? 1 : 0;

        if (offset == 1 && i == 0) {
          return Padding(
            key: const ValueKey<String>('scan-list-error'),
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: InlineNotice(
              tone: NoticeTone.warn,
              message: describeScanError(scan.error),
            ),
          );
        }

        final int index = i - offset;

        if (index >= scan.pageCount) {
          return Padding(
            key: const ValueKey<String>('scan-list-add'),
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: OutlinedButton.icon(
              onPressed: (scan.isBusy || full) ? null : onAdd,
              icon: Icon(full ? Icons.block_rounded : Icons.add_rounded,
                  size: 20),
              label: Text(
                full ? 'Maximum ${ScanController.maxPages} pages' : 'Add page',
              ),
            ),
          );
        }

        // The key belongs on the widget the builder RETURNS.
        //
        // SliverChildBuilderDelegate reads `child.key` off this widget and
        // nothing deeper, so a key on the ScanPageTile inside the Padding was
        // silently discarded — every move or delete re-inflated every tile
        // below it (re-decoding each thumbnail) instead of moving the elements
        // that already existed, which is exactly what the key was added to
        // prevent.
        return Padding(
          key: ValueKey<String>(scan.pages[index].id),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: ScanPageTile(
            page: scan.pages[index],
            index: index,
            total: scan.pageCount,
            onRemove: () => controller.removeAt(index),
            onMoveUp: index == 0 ? null : () => controller.moveUp(index),
            onMoveDown: index == scan.pageCount - 1
                ? null
                : () => controller.moveDown(index),
          ),
        );
      },
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
