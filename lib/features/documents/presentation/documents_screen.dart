/// The documents list — the screen the product is used from.
///
/// Search is debounced by 350 ms so a five-letter filename is one request
/// rather than five, the filter chips are the five states a user actually asks
/// about, and the list pages as it is scrolled. The rows are fixed height and
/// built with `itemExtent`, because a workspace with two thousand statements
/// must scroll at the same frame rate as one with three.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../domain/document.dart';
import 'providers.dart';
import 'widgets/document_card.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  final TextEditingController _search = TextEditingController();

  /// Long enough that typing a filename is one request, short enough that the
  /// list feels like it is reacting to the keyboard.
  static const Duration _debounce = Duration(milliseconds: 350);

  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      if (!mounted) {
        return;
      }
      ref.read(documentListProvider.notifier).setQuery(value);
    });
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _search.clear();
    ref.read(documentListProvider.notifier).setQuery('');
  }

  bool _onScroll(ScrollNotification notification) {
    // 600 px of runway: far enough that the next page has usually landed before
    // the user reaches the bottom, close enough not to prefetch the whole
    // archive on a flick.
    if (notification.metrics.extentAfter < 600) {
      ref.read(documentListProvider.notifier).loadMore();
    }
    return false;
  }

  void _open(int documentId) {
    context.pushNamed(
      AppRoute.documentDetail,
      pathParameters: <String, String>{'id': '$documentId'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final DocumentListState state = ref.watch(documentListProvider);
    final List<DocumentSummary> rows = state.visible;
    final double extent = DocumentCard.extentFor(context) + AppSpacing.md;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: HeroPageScaffold(
        onRefresh: () => ref.read(documentListProvider.notifier).refresh(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.pushNamed(AppRoute.documentUpload),
          icon: const Icon(Icons.add_rounded),
          label: const Text(S.uploadDocument),
        ),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.page,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            sliver: SliverToBoxAdapter(
              child: HeroPanel(
                eyebrow: S.documents,
                title: S.documentsSubtitle,
                scene: const DocumentsScene(),
                subtitle: state.total > 0 ? S.documentCount(state.total) : null,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _SearchField(
              controller: _search,
              onChanged: _onSearchChanged,
              onClear: _clearSearch,
            ),
          ),
          SliverToBoxAdapter(
            child: _FilterChips(
              selected: state.filter,
              onSelect: ref.read(documentListProvider.notifier).setFilter,
            ),
          ),
          if (state.page.isLoading && !state.page.hasValue)
            const SliverToBoxAdapter(child: SkeletonList())
          else if (state.page.hasError && !state.page.hasValue)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                error: state.page.error!,
                onRetry: () => ref
                    .read(documentListProvider.notifier)
                    .refresh(showLoading: true),
                onUpgrade: () => context.pushNamed(AppRoute.billing),
              ),
            )
          else if (rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: state.isFiltered
                  ? EmptyState(
                      icon: Icons.search_off_rounded,
                      title: S.noResults,
                      body: S.noResultsBody,
                      actionLabel: S.clearFilters,
                      onAction: () {
                        _clearSearch();
                        ref
                            .read(documentListProvider.notifier)
                            .setFilter(DocumentFilter.all);
                      },
                    )
                  : EmptyState(
                      icon: Icons.description_outlined,
                      title: S.noDocuments,
                      body: S.noDocumentsBody,
                      actionLabel: S.uploadDocument,
                      onAction: () =>
                          context.pushNamed(AppRoute.documentUpload),
                    ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.page,
              ),
              sliver: SliverFixedExtentList.builder(
                itemExtent: extent,
                itemCount: rows.length,
                itemBuilder: (BuildContext context, int index) {
                  final DocumentSummary document = rows[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: DocumentCard(
                      document: document,
                      onTap: () => _open(document.id),
                    ),
                  );
                },
              ),
            ),
          SliverToBoxAdapter(
            child: _ListFooter(
              isLoadingMore: state.isLoadingMore,
              error: state.loadMoreError,
              onRetry: () =>
                  ref.read(documentListProvider.notifier).loadMore(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: S.searchDocuments,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (BuildContext context, TextEditingValue value, _) {
              if (value.text.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onClear,
                tooltip: S.clear,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelect});

  final DocumentFilter selected;
  final ValueChanged<DocumentFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.md,
          AppSpacing.page,
          AppSpacing.sm,
        ),
        itemCount: DocumentFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final DocumentFilter filter = DocumentFilter.values[index];
          final bool active = filter == selected;
          return ChoiceChip(
            label: Text(filter.label),
            selected: active,
            showCheckmark: false,
            onSelected: (_) => onSelect(filter),
            labelStyle: AppText.bodySm.copyWith(
              fontWeight: FontWeight.w600,
              color: active ? AppColors.brandDeep : AppColors.inkBody,
            ),
            selectedColor: AppColors.brandTint,
            backgroundColor: AppColors.surface,
            side: BorderSide(
              color: active ? AppColors.brandTintStrong : AppColors.border,
            ),
          );
        },
      ),
    );
  }
}

/// The bottom of the list: a spinner while another page is loading, a retry
/// when one failed, and breathing room above the FAB otherwise.
class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.isLoadingMore,
    required this.error,
    required this.onRetry,
  });

  final bool isLoadingMore;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: InlineNotice(
          message: S.couldNotLoadMore,
          tone: NoticeTone.warn,
          actionLabel: S.tryAgain,
          onAction: onRetry,
        ),
      );
    }

    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    return const SizedBox(height: 96);
  }
}
