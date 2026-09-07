import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playdata_lms/features/resume/ai_coach/data/resume_review_api_client.dart';
import 'package:playdata_lms/features/resume/ai_coach/presentation/job_resume_review_dialog.dart';
import 'package:playdata_lms/shared/models/resume_content.dart';

class FakeReviewClient extends ResumeReviewApiClient {
  FakeReviewClient() : super(token: () async => 'fake');
  String text = '개발 하였습니다.';
  Map<String, dynamic>? applied;
  int reviews = 0;
  @override
  Future<Map<String, dynamic>> context(
    String cohort,
    String resume, {
    String? job,
  }) async => {
    'content': {
      'coreCompetencies': {'text': text},
    },
    'input_hash': 'version',
    'job_source': {'snapshot_hash': 'job-version'},
  };
  @override
  Future<Map<String, dynamic>> review(Map<String, dynamic> body) async {
    reviews++;
    return {
      'review_id': 'review',
      'input_hash': 'version',
      'summary': '검토 결과',
      'job_source': {'company': '회사', 'title': '개발자'},
      'sentence_reviews': [
        {
          'field_path': 'coreCompetencies.text',
          'original_quote': text,
          'suggested_revision': '개발하였습니다.',
          'reason': '띄어쓰기 수정',
          'edit_type': 'spelling',
          'status': 'formatting',
          'evidence_quotes': [text],
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> apply(Map<String, dynamic> body) async {
    applied = body;
    text = '개발하였습니다.';
    return {'operation_id': 'op', 'input_hash': 'updated'};
  }

  @override
  Future<Map<String, dynamic>> undo(Map<String, dynamic> body) async {
    text = '개발 하였습니다.';
    return {'operation_id': 'undo', 'input_hash': 'version'};
  }
}

void main() {
  testWidgets(
    'review -> selected apply -> undo refreshes parent without automatic overwrite',
    (tester) async {
      final client = FakeReviewClient();
      final changes = <ResumeContent>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JobResumeReviewDialog(
              client: client,
              cohortId: 'c',
              resumeId: 'r',
              jobId: 'job',
              draft: ResumeContent.fromMap({
                'coreCompetencies': {'text': '개발 하였습니다.'},
              }),
              onChanged: changes.add,
            ),
          ),
        ),
      );
      await tester.tap(find.text('첨삭 실행 / 재시도'));
      await tester.pumpAndSettle();
      expect(find.text('검토 결과'), findsOneWidget);
      expect(changes, isEmpty);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('선택 수정안 저장 / 재시도'));
      await tester.pumpAndSettle();
      expect(client.applied!['selected_indices'], [0]);
      expect(changes.last.coreCompetencies.text, '개발하였습니다.');
      await tester.tap(find.text('적용 되돌리기'));
      await tester.pumpAndSettle();
      expect(changes.last.coreCompetencies.text, '개발 하였습니다.');
      expect(changes.length, 2);
      client.close();
    },
  );

  testWidgets('unsaved snapshot mismatch stops before model request', (
    tester,
  ) async {
    final client = FakeReviewClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobResumeReviewDialog(
            client: client,
            cohortId: 'c',
            resumeId: 'r',
            jobId: 'job',
            draft: ResumeContent.empty(),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('첨삭 실행 / 재시도'));
    await tester.pumpAndSettle();
    expect(client.reviews, 0);
    expect(find.textContaining('화면과 저장된 이력서가 다릅니다'), findsOneWidget);
    client.close();
  });
}
