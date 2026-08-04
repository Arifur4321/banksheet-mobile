/// Opening, saving and sharing a finished conversion.
///
/// Both screens that offer those three verbs — the run screen and the history —
/// go through this one class, so "Open" means the same thing in both places and
/// a change to where downloads land is a single edit.
///
/// The distinction the three verbs draw is deliberate. Open and Share fetch into
/// the cache directory, which the OS may reclaim; Save writes into the app's
/// documents directory, which it may not. A user who taps Download and finds the
/// file gone next week would be right to call that a bug.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/states.dart';
import '../data/tool_repository.dart';
import '../domain/conversion.dart';

class ConversionFiles {
  const ConversionFiles(this._repository);

  final ToolRepository _repository;

  /// Fetch, then hand the file to whatever app owns that type.
  Future<void> open(BuildContext context, Conversion conversion) async {
    final File file = await _fetch(conversion, permanent: false);
    if (!context.mounted) {
      return;
    }

    final OpenResult result = await OpenFilex.open(
      file.path,
      type: conversion.outputMimeType,
    );
    if (!context.mounted || result.type == ResultType.done) {
      return;
    }
    Toast.error(
      context,
      ApiException(
        code: 'cannot_open',
        message: result.type == ResultType.noAppToOpen
            ? S.noAppForFile
            : S.cannotOpenFile,
      ),
    );
  }

  /// Fetch into permanent storage and say where it went.
  Future<void> save(BuildContext context, Conversion conversion) async {
    final File file = await _fetch(conversion, permanent: true);
    if (!context.mounted) {
      return;
    }
    Toast.success(context, S.savedAs(p.basename(file.path)));
  }

  /// Fetch, then open the platform share sheet.
  Future<void> share(BuildContext context, Conversion conversion) async {
    final File file = await _fetch(conversion, permanent: false);
    if (!context.mounted) {
      return;
    }

    final String filename = conversion.downloadFilename;
    final RenderObject? box = context.findRenderObject();

    await Share.shareXFiles(
      <XFile>[XFile(file.path, name: filename)],
      subject: filename,
      // Required on iPad: without an anchor the share sheet has nowhere to
      // attach and the call throws.
      sharePositionOrigin:
          box is RenderBox ? box.localToGlobal(Offset.zero) & box.size : null,
    );
  }

  Future<File> _fetch(
    Conversion conversion, {
    required bool permanent,
  }) async {
    final Directory directory = permanent
        ? await getApplicationDocumentsDirectory()
        : await getTemporaryDirectory();

    return _repository.download(
      conversion.id,
      p.join(directory.path, _safeName(conversion.downloadFilename)),
    );
  }

  /// A filename from the server is data. A path separator in it would write
  /// outside the directory we chose.
  static String _safeName(String filename) {
    final String safe = p
        .basename(filename)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'conversion' : safe;
  }
}
