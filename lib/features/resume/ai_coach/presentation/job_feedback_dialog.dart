import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../data/job_recommend_api_client.dart';

/// 고른 공고 하나를 기준으로 받은 이력서 피드백을 보여준다.
///
/// 읽기만 하는 화면이다. 이력서를 고치지 않으므로 저장 전 초안으로도 열 수 있다.
/// 문장을 대신 써 주지 않고, 어디에 무엇을 드러내면 좋은지만 알려준다.
class JobFeedbackDialog extends StatefulWidget {
  const JobFeedbackDialog({
    super.key,
    required this.client,
    required this.jobId,
    required this.resumeText,
  });

  final JobRecommendApiClient client;
  final String jobId;
  final String resumeText;

  @override
  State<JobFeedbackDialog> createState() => _JobFeedbackDialogState();
}

class _JobFeedbackDialogState extends State<JobFeedbackDialog> {
  JobFeedbackResponse? _result;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.client.feedback(
        jobId: widget.jobId,
        resumeText: widget.resumeText,
      );
      if (mounted) setState(() => _result = result);
    } on JobRecommendApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '피드백을 받지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AlertDialog(
      title: const Text('이 공고 기준 이력서 피드백', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading) ...[
                const LinearProgressIndicator(minHeight: 3),
                const SizedBox(height: 10),
                const Text(
                  '공고가 원하는 것과 이력서를 대조하고 있습니다…',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
              if (_error case final message?)
                Text(message, style: const TextStyle(fontSize: 12, color: AppColors.error)),
              if (result != null) ...[
                Text(
                  '${result.company} · ${result.title}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _Label('이 공고가 원하는 사람', AppColors.info),
                Text(result.wanted, style: const TextStyle(fontSize: 12, height: 1.45)),
                const SizedBox(height: 14),
                if (result.shown.isNotEmpty) ...[
                  _Label('이력서에서 드러나는 것 ${result.shown.length}건', AppColors.success),
                  for (final point in result.shown) _PointTile(point: point),
                  const SizedBox(height: 10),
                ],
                if (result.missing.isNotEmpty) ...[
                  _Label('이력서에서 확인되지 않는 것 ${result.missing.length}건', AppColors.warning),
                  for (final point in result.missing) _PointTile(point: point),
                  const SizedBox(height: 10),
                ],
                if (result.points.isEmpty)
                  const Text(
                    '공고에서 대조할 요건을 찾지 못했습니다. 공고 원문을 직접 확인해 주세요.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                for (final warning in result.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      warning,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textHint, height: 1.4),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  result.notice,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.textHint, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (!_loading && _error != null)
          TextButton(onPressed: _load, child: const Text('다시 시도')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// 공고가 원하는 것 하나와, 그 근거·조언.
class _PointTile extends StatelessWidget {
  const _PointTile({required this.point});

  final JobFeedbackPoint point;

  @override
  Widget build(BuildContext context) {
    final color = point.isShown ? AppColors.success : AppColors.warning;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  point.kind,
                  style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  point.topic,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _Quote(label: '공고', text: point.jobQuote, color: AppColors.info),
          if (point.resumeQuote.isNotEmpty)
            _Quote(label: '이력서', text: point.resumeQuote, color: AppColors.success),
          const SizedBox(height: 4),
          Text(
            point.advice,
            style: const TextStyle(fontSize: 11, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.label, required this.text, required this.color});

  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              label,
              style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              '“$text”',
              style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
