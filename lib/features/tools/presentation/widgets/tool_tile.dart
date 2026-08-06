/// One tool in the grid.
///
/// A [TiltCard] so the tools screen shares the depth idiom the rest of the app
/// uses, with the server's own badge printed under the label — "PDF -> DOCX",
/// "Ghostscript" — because that string is what tells a user which of two
/// similar-sounding tools they actually want.
///
/// An unsupported tool (edit-pdf) is drawn flat and greyed with its reason on
/// the tile rather than hidden: a user who came looking for the visual editor
/// needs to be told where it lives, not left wondering whether the app lost it.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/typography.dart';
import '../../../../core/widgets/scene_3d.dart';
import '../../domain/tool.dart';
import '../../domain/tool_copy.dart';

/// The icon for a tool key.
///
/// Keyed on the server's identifiers, with a category fallback so a tool added
/// server-side still renders something sensible without an app release.
IconData toolIcon(ToolDefinition tool) => switch (tool.key) {
      'pdf-to-word' => Icons.description_rounded,
      'office-to-pdf' => Icons.picture_as_pdf_rounded,
      'images-to-pdf' => Icons.burst_mode_rounded,
      'pdf-to-images' => Icons.image_rounded,
      'merge-pdf' => Icons.merge_rounded,
      'split-pdf' => Icons.call_split_rounded,
      'rotate-pdf' => Icons.rotate_90_degrees_cw_rounded,
      'compress-pdf' => Icons.compress_rounded,
      'ocr-pdf' => Icons.document_scanner_rounded,
      'extract-text' => Icons.text_snippet_rounded,
      'html-to-pdf' => Icons.code_rounded,
      'repair-pdf' => Icons.build_rounded,
      'edit-pdf' => Icons.edit_document,
      'barcode-generator' => Icons.qr_code_2_rounded,
      _ => switch (tool.category) {
          ToolCategory.documentConversion => Icons.swap_horiz_rounded,
          ToolCategory.imageConversion => Icons.photo_library_rounded,
          ToolCategory.pdfUtilities => Icons.picture_as_pdf_rounded,
        },
    };

class ToolTile extends StatelessWidget {
  const ToolTile({
    required this.tool,
    required this.onTap,
    super.key,
  });

  final ToolDefinition tool;

  /// Called for a supported tool. An unsupported one still calls it so the
  /// screen can explain itself — the tile does not decide the copy.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = tool.supported;
    final Color accent = enabled ? AppColors.brandDeep : AppColors.inkFaint;
    final Color tint = enabled ? AppColors.brandTint : AppColors.surfaceMuted;

    return TiltCard(
      onTap: onTap,
      maxTilt: enabled ? 7 : 0,
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: enabled ? AppColors.surface : AppColors.surfaceMuted,
      semanticLabel: enabled
          ? '${tool.label}. ${ToolCopy.description(tool.key, tool.description) ?? ''}'
          : '${tool.label}. ${tool.unsupportedReason ?? ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: AppRadius.smallAll,
                ),
                child: Icon(toolIcon(tool), size: 20, color: accent),
              ),
              const Spacer(),
              if (!enabled)
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: AppColors.inkFaint,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            tool.label,
            style: AppText.bodyStrong.copyWith(
              color: enabled ? AppColors.ink : AppColors.inkMuted,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            enabled
                ? (tool.badge ?? tool.acceptedLabel ?? '')
                : (tool.unsupportedReason ?? ''),
            style: AppText.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
