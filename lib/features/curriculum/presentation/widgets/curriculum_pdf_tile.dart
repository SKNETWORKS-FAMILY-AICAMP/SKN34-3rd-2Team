import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/curriculum_attachment_model.dart';

class CurriculumPdfTile extends StatelessWidget {
  const CurriculumPdfTile({
    super.key,
    required this.attachment,
  });

  final CurriculumAttachmentModel attachment;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(attachment.fileUrl);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF를 열 수 없습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf, color: AppColors.error),
        title: Text(
          attachment.title.isNotEmpty ? attachment.title : attachment.fileName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          attachment.fileName,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.open_in_new),
          tooltip: '열기',
          onPressed: () => _open(context),
        ),
        onTap: () => _open(context),
      ),
    );
  }
}
