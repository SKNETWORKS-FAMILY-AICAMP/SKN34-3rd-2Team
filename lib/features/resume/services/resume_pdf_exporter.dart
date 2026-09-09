import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../shared/models/resume_content.dart';
import '../../../shared/models/resume_model.dart';

/// 이력서 Doc 모드 → PDF 미리보기/인쇄
abstract final class ResumePdfExporter {
  /// 한 번 받아 두고 다시 쓴다. 내보낼 때마다 내려받지 않는다.
  static pw.ThemeData? _theme;

  /// PDF 기본 글꼴에는 한글 글자가 없어 그냥 두면 전부 네모로 나온다.
  /// 본문·굵은 글씨 둘 다 한글 글꼴로 깔아 둔다.
  static Future<pw.ThemeData> _koreanTheme() async {
    final cached = _theme;
    if (cached != null) return cached;
    final [base, bold] = await Future.wait([
      PdfGoogleFonts.notoSansKRRegular(),
      PdfGoogleFonts.notoSansKRBold(),
    ]);
    return _theme = pw.ThemeData.withFont(base: base, bold: bold);
  }

  static Future<void> showPrintPreview(ResumeModel resume) async {
    final doc = pw.Document(theme: await _koreanTheme());
    final c = resume.content;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(resume.title, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('${c.basicInfo.name} · ${c.basicInfo.email} · ${c.basicInfo.phone}'),
          pw.SizedBox(height: 16),
          if (c.coreCompetencies.text.isNotEmpty) ...[
            _heading('핵심역량/강점'),
            pw.Text(c.coreCompetencies.text),
            pw.SizedBox(height: 12),
          ],
          ..._listSection('경력사항', c.experience.map((e) => '${e.company} · ${e.role}\n${e.description}')),
          ..._listSection('학력사항', c.education.map((e) => '${e.school} · ${e.major}')),
          ..._listSection('기술스택', c.techStack.map((e) => e.name)),
          ..._listSection('프로젝트', c.projects.map((e) => '${e.name}\n${e.description}')),
          _heading('자기소개서'),
          ...ResumeSelfIntroLabels.keys.map((key) {
            final s = c.selfIntroduction.sectionByKey(key);
            if (s.body.isEmpty) return pw.SizedBox.shrink();
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(ResumeSelfIntroLabels.labels[key] ?? key, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                if (s.subtitle.isNotEmpty) pw.Text(s.subtitle),
                pw.Text(s.body),
                pw.SizedBox(height: 8),
              ],
            );
          }),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  static pw.Widget _heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(text, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      );

  static List<pw.Widget> _listSection(String title, Iterable<String> items) {
    final list = items.where((e) => e.trim().isNotEmpty).toList();
    if (list.isEmpty) return [];
    return [
      _heading(title),
      ...list.map((e) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 4), child: pw.Text('• $e'))),
      pw.SizedBox(height: 12),
    ];
  }
}
