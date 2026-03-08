import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'native_bridge.dart';

class StoragePermissionService {
  static Future<bool> ensurePermission(
    BuildContext context, {
    required String dialogTitleKey,
    required String dialogBodyKey,
  }) async {
    final hasPermission = await NativeBridge.hasStoragePermission();
    if (hasPermission) {
      return true;
    }

    if (!context.mounted) {
      return false;
    }

    final l10n = context.l10n;
    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t(dialogTitleKey)),
        content: Text(l10n.t(dialogBodyKey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.t('settingsStorageDialogAction')),
          ),
        ],
      ),
    );

    if (shouldRequest != true) {
      return false;
    }

    await NativeBridge.requestStoragePermission();
    return await NativeBridge.hasStoragePermission();
  }
}
