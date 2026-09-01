import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../../shared/demo/demo_accounts.dart';
import '../../../shared/providers/firebase_providers.dart';
import '../../../shared/services/storage_service.dart';

Future<String> uploadAssessmentProblemFile({
  required WidgetRef ref,
  required String cohortId,
  required String assessmentId,
  required PlatformFile file,
}) async {
  final uid = ref.read(sessionUidProvider).value;
  if (DemoConfig.enabled && uid != null && DemoAccounts.isDemoUid(uid)) {
    return 'demo://problems/${file.name}';
  }

  final bytes = await file.readAsBytes();
  final path = StorageService.assessmentProblemPath(
    cohortId: cohortId,
    assessmentId: assessmentId,
    fileName: file.name,
  );
  return ref.read(storageServiceProvider).uploadAndGetUrl(
        storagePath: path,
        bytes: bytes,
        contentType: _guessContentType(file.name),
      );
}

Future<String> uploadAssessmentAnswerFile({
  required WidgetRef ref,
  required String cohortId,
  required String assessmentId,
  required String userId,
  required PlatformFile file,
}) async {
  final uid = ref.read(sessionUidProvider).value;
  if (DemoConfig.enabled && uid != null && DemoAccounts.isDemoUid(uid)) {
    return 'demo://answers/${file.name}';
  }

  final bytes = await file.readAsBytes();
  final path = StorageService.assessmentAnswerPath(
    cohortId: cohortId,
    assessmentId: assessmentId,
    userId: userId,
    fileName: file.name,
  );
  return ref.read(storageServiceProvider).uploadAndGetUrl(
        storagePath: path,
        bytes: bytes,
        contentType: _guessContentType(file.name),
      );
}

String newAssessmentId(WidgetRef ref) {
  final uid = ref.read(sessionUidProvider).value;
  if (DemoConfig.enabled && uid != null && DemoAccounts.isDemoUid(uid)) {
    return 'a${DateTime.now().millisecondsSinceEpoch}';
  }
  return ref.read(firestoreProvider).collection('_ids').doc().id;
}

String _guessContentType(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.zip')) return 'application/zip';
  if (lower.endsWith('.ipynb')) return 'application/x-ipynb+json';
  return 'application/octet-stream';
}
