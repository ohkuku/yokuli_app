import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_colors.dart';
import 'update_service.dart';

/// Shows the update dialog if [info] indicates a newer version is available.
/// Safe to call from any screen after first frame.
Future<void> showUpdateDialogIfNeeded(BuildContext context) async {
  final info = await UpdateService.checkForUpdate();
  if (info == null) return;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatelessWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        const Icon(Icons.system_update_rounded, color: AppColors.cyan, size: 22),
        const SizedBox(width: 10),
        const Text('New version available',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
      ]),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Version row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Current  ${info.currentVersion}',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13)),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 14, color: AppColors.textMuted),
                  Text(info.latestVersion,
                      style: const TextStyle(
                          color: AppColors.cyan,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (info.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('What\'s new',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12, height: 1.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Later',
              style: TextStyle(color: AppColors.textMuted)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.cyan),
          onPressed: () async {
            Navigator.of(context).pop();
            // Prefer direct APK download on Android; fall back to release page
            final target = info.apkUrl ?? info.releaseUrl;
            final uri = Uri.parse(target);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          icon: const Icon(Icons.download_rounded, size: 16,
              color: AppColors.background),
          label: const Text('Update now',
              style: TextStyle(color: AppColors.background)),
        ),
      ],
    );
  }
}
