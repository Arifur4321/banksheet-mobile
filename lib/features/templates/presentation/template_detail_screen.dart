/// Fill a template in and get the PDF.
///
/// The form is built from the schema the server publishes, and validated with
/// the same rules the server will apply — so a value this screen accepts is a
/// value `TemplateController::generate()` accepts, and the user finds out about
/// a missing field before the round trip rather than after it.
///
/// The controllers are rebuilt only when the template itself changes, so a
/// pull-to-refresh never wipes half-typed work.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../../exports/data/file_downloader.dart';
import '../data/generated_pdf_repository.dart';
import '../data/template_repository.dart';
import '../domain/generated_pdf.dart';
import '../domain/template.dart';
import 'providers.dart';
import 'widgets/generated_pdf_card.dart';
import 'widgets/template_variable_field.dart';

/// `title` is `required|string|max:255` on the server.
const int _maxTitleLength = 255;

class TemplateDetailScreen extends ConsumerStatefulWidget {
  const TemplateDetailScreen({required this.templateId, super.key});

  final int templateId;

  @override
  ConsumerState<TemplateDetailScreen> createState() =>
      _TemplateDetailScreenState();
}

class _TemplateDetailScreenState extends ConsumerState<TemplateDetailScreen> {
  final TextEditingController _title = TextEditingController();

  /// One controller per variable, keyed by the name the value is posted under.
  Map<String, TextEditingController> _fields =
      <String, TextEditingController>{};

  /// The template the controllers above were built for. Rebuilding them on
  /// every refresh would throw away whatever the user had typed.
  int? _boundTemplateId;

  /// Field name (or `title`) to the message shown under it.
  Map<String, String> _errors = <String, String>{};

  bool _isSubmitting = false;

  /// The PDF this screen just produced, if any.
  GeneratedPdf? _result;

  /// True while the produced PDF is being fetched for opening or sharing.
  bool _isTransferring = false;

  @override
  void dispose() {
    _title.dispose();
    for (final TextEditingController controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Creates the controllers for [template] the first time it arrives.
  ///
  /// Called from `build`, which is safe because it only allocates — it never
  /// calls `setState`, and the widgets built in the same pass read the result.
  void _bind(Template template) {
    if (_boundTemplateId == template.id) {
      return;
    }

    for (final TextEditingController controller in _fields.values) {
      controller.dispose();
    }

    _fields = <String, TextEditingController>{
      for (final TemplateVariable variable in template.variables)
        variable.name: TextEditingController(text: variable.defaultValue),
    };
    _boundTemplateId = template.id;

    // The server needs a title and uses it for the download filename; the
    // template's own name is the answer nine times out of ten.
    if (_title.text.isEmpty) {
      _title.text = template.displayName;
    }
  }

  void _clearError(String key) {
    if (!_errors.containsKey(key)) {
      return;
    }
    setState(() => _errors = <String, String>{..._errors}..remove(key));
  }

  /// The device-side half of the server's rule set. Returns the errors found,
  /// empty when everything passes.
  Map<String, String> _validate(Template template) {
    final Map<String, String> errors = <String, String>{};

    final String title = _title.text.trim();
    if (title.isEmpty) {
      errors['title'] = S.required;
    } else if (title.length > _maxTitleLength) {
      errors['title'] = S.tooLong;
    }

    for (final TemplateVariable variable in template.variables) {
      final String? message = variable.validate(_fields[variable.name]?.text);
      if (message != null) {
        errors[variable.name] = message;
      }
    }

    return errors;
  }

  Future<void> _generate(Template template) async {
    if (_isSubmitting) {
      return;
    }

    FocusScope.of(context).unfocus();

    final Map<String, String> errors = _validate(template);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }

    setState(() {
      _errors = <String, String>{};
      _isSubmitting = true;
    });

    try {
      final GeneratedPdf pdf =
          await ref.read(templateRepositoryProvider).generate(
                template.id,
                title: _title.text.trim(),
                variables: <String, String>{
                  for (final TemplateVariable variable in template.variables)
                    variable.name: _fields[variable.name]?.text.trim() ?? '',
                },
              );

      if (!context.mounted) {
        return;
      }

      // The archive on the other screen is now one PDF out of date. Not
      // awaited: the user is looking at the result, not at that list.
      unawaited(ref.read(generatedPdfListProvider.notifier).refresh());

      setState(() => _result = pdf);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      setState(() => _errors = _fieldErrorsFrom(error));
      Toast.error(context, error);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Maps the server's `variables.customer_name` keys back onto the fields.
  static Map<String, String> _fieldErrorsFrom(Object error) {
    final ApiException failure = ApiException.from(error);
    final Map<String, String> errors = <String, String>{};

    failure.fieldErrors.forEach((String key, List<String> messages) {
      if (messages.isEmpty) {
        return;
      }
      errors[key.startsWith('variables.') ? key.substring(10) : key] =
          messages.first;
    });

    return errors;
  }

  Future<void> _transfer(
    GeneratedPdf pdf,
    FileAction action,
    Rect? origin,
  ) async {
    if (_isTransferring) {
      return;
    }
    setState(() => _isTransferring = true);

    try {
      final File file = await ref.read(generatedPdfRepositoryProvider).download(
            pdf.id,
            filename: pdf.filename,
          );
      if (!context.mounted) {
        return;
      }
      await FileDownloader.apply(
        action,
        file,
        subject: pdf.displayName,
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
    final AsyncValue<Template> state =
        ref.watch(templateDetailProvider(widget.templateId));

    return PageScaffold(
      title: state.valueOrNull?.displayName ?? S.templates,
      subtitle: state.valueOrNull == null ? null : S.fillVariables,
      showBack: true,
      scrollable: true,
      onRefresh: () =>
          ref.refresh(templateDetailProvider(widget.templateId).future),
      child: state.when(
        loading: () => const _FormSkeleton(),
        error: (Object error, _) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.section),
          child: ErrorState(
            error: error,
            onRetry: () =>
                ref.invalidate(templateDetailProvider(widget.templateId)),
            onUpgrade: () => context.pushNamed(AppRoute.billing),
          ),
        ),
        data: (Template template) {
          _bind(template);
          final GeneratedPdf? result = _result;

          return result == null ? _buildForm(template) : _buildSuccess(result);
        },
      ),
    );
  }

  Widget _buildForm(Template template) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TemplateHeader(template: template),
        const SizedBox(height: AppSpacing.xl),
        TextField(
          controller: _title,
          enabled: !_isSubmitting,
          maxLength: _maxTitleLength,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.sentences,
          buildCounter: (
            BuildContext context, {
            required int currentLength,
            required int? maxLength,
            required bool isFocused,
          }) =>
              null,
          decoration: InputDecoration(
            labelText: S.documentTitle,
            helperText: S.documentTitleHint,
            errorText: _errors['title'],
            prefixIcon: const Icon(Icons.title_rounded, size: 20),
          ),
          onChanged: (_) => _clearError('title'),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (!template.hasVariables)
          const InlineNotice(message: S.noVariablesBody)
        else ...<Widget>[
          const SectionHeader(title: S.fillVariables),
          for (int i = 0; i < template.variables.length; i++)
            TemplateVariableField(
              variable: template.variables[i],
              controller: _fields[template.variables[i].name]!,
              enabled: !_isSubmitting,
              errorText: _errors[template.variables[i].name],
              isLast: i == template.variables.length - 1,
              onChanged: () => _clearError(template.variables[i].name),
            ),
        ],
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : () => _generate(template),
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.inkInverse,
                  ),
                )
              : const Icon(Icons.picture_as_pdf_rounded, size: 19),
          label: Text(_isSubmitting ? S.generating : S.generatePdf),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          S.templatesAuthoredOnWeb,
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.section),
      ],
    );
  }

  Widget _buildSuccess(GeneratedPdf pdf) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const InlineNotice(
          message: S.pdfReady,
          tone: NoticeTone.success,
        ),
        const SizedBox(height: AppSpacing.lg),
        GeneratedPdfCard(
          pdf: pdf,
          isBusy: _isTransferring,
          onAction: (FileAction action, Rect? origin) =>
              _transfer(pdf, action, origin),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.tonalIcon(
          onPressed: () => context.pushNamed(AppRoute.generatedPdfs),
          icon: const Icon(Icons.folder_open_rounded, size: 19),
          label: const Text(S.seeAllGeneratedPdfs),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          // The values are still in the controllers, so "another" means the
          // same invoice with one field changed — which is the common case.
          onPressed: () => setState(() {
            _result = null;
          }),
          child: const Text(S.generateAnother),
        ),
        const SizedBox(height: AppSpacing.section),
      ],
    );
  }
}

/// What this template is, above the form.
class _TemplateHeader extends StatelessWidget {
  const _TemplateHeader({required this.template});

  final Template template;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.brandTint,
              borderRadius: AppRadius.smallAll,
            ),
            child: const Icon(
              Icons.article_rounded,
              size: 21,
              color: AppColors.brandDeep,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  template.displayName,
                  style: AppText.bodyStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  _meta,
                  style: AppText.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _meta {
    final List<String> parts = <String>[
      if (template.type != null) Fmt.humanise(template.type),
      template.hasVariables
          ? S.templateFieldCount(template.variablesCount)
          : S.noVariables,
      if (template.generatedPdfsCount != null)
        S.generatedPdfCount(template.generatedPdfsCount!),
    ];
    return parts.join(' · ');
  }
}

/// The form's shape while the schema is on its way, so the screen does not jump
/// when it lands.
class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Skeleton(height: 76, radius: AppRadius.card),
        SizedBox(height: AppSpacing.xl),
        Skeleton(width: 140, height: 14),
        SizedBox(height: AppSpacing.md),
        Skeleton(height: 56, radius: AppRadius.control),
        SizedBox(height: AppSpacing.lg),
        Skeleton(height: 56, radius: AppRadius.control),
        SizedBox(height: AppSpacing.lg),
        Skeleton(height: 56, radius: AppRadius.control),
        SizedBox(height: AppSpacing.xl),
        Skeleton(height: 48, radius: AppRadius.control),
      ],
    );
  }
}
