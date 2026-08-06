/// The page chrome every screen shares.
///
/// Wraps a [Scaffold] with the canvas colour, the offline banner and a
/// consistent title treatment so screens only describe their own content.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'states.dart';

class PageScaffold extends ConsumerWidget {
  const PageScaffold({
    required this.title,
    required this.child,
    super.key,
    this.subtitle,
    this.actions,
    this.floatingActionButton,
    this.bottom,
    this.showBack = false,
    this.padding = const EdgeInsets.all(AppSpacing.page),
    this.scrollable = false,
    this.onRefresh,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;
  final bool showBack;
  final EdgeInsets padding;

  /// When true the body is wrapped in a scroll view. Screens that supply their
  /// own [ListView] leave this false so they keep lazy building.
  final bool scrollable;

  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool online = ref.watch(isOnlineProvider);

    Widget body = Padding(padding: padding, child: child);

    if (scrollable) {
      body = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        child: child,
      );
    }

    if (onRefresh != null) {
      body = RefreshIndicator(
        onRefresh: onRefresh!,
        color: AppColors.brand,
        backgroundColor: AppColors.surface,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        automaticallyImplyLeading: showBack,
        titleSpacing: showBack ? 0 : AppSpacing.page,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(title, style: AppText.h1),
            if (subtitle != null)
              Text(
                subtitle!,
                style: AppText.bodySm,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        toolbarHeight: subtitle == null ? 58 : 72,
        actions: <Widget>[
          ...?actions,
          const SizedBox(width: AppSpacing.sm),
        ],
        bottom: bottom,
      ),
      floatingActionButton: floatingActionButton,
      // `SafeArea(top: false)`: the AppBar already consumes the status bar, but
      // nothing was consuming the bottom inset.
      //
      // Every screen on this scaffold is a full-screen route pushed on the root
      // navigator, so unlike the tabbed screens there is no NavigationBar
      // sitting in the gap. The last control on the page therefore rendered
      // underneath Android's navigation bar and could not be tapped — the
      // "Convert to DOCX" button at the bottom of every tool form is the one
      // people hit first.
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            if (!online) const OfflineBanner(),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// A full-bleed variant for screens whose first element is a 3D hero panel and
/// that therefore supply their own title inside the scroll view.
class HeroPageScaffold extends ConsumerWidget {
  const HeroPageScaffold({
    required this.slivers,
    super.key,
    this.floatingActionButton,
    this.onRefresh,
  });

  final List<Widget> slivers;
  final Widget? floatingActionButton;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool online = ref.watch(isOnlineProvider);

    Widget body = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );

    if (onRefresh != null) {
      body = RefreshIndicator(
        onRefresh: onRefresh!,
        color: AppColors.brand,
        backgroundColor: AppColors.surface,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            if (!online) const OfflineBanner(),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
