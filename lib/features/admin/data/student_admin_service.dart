import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../shared/models/student_intake_model.dart';
import '../../../shared/providers/firebase_providers.dart';

class CreateStudentResult {
  const CreateStudentResult({
    required this.uid,
    required this.email,
    required this.password,
    required this.displayName,
  });

  final String uid;
  final String email;
  final String password;
  final String displayName;

  factory CreateStudentResult.fromMap(Map<String, dynamic> data) {
    return CreateStudentResult(
      uid: data['uid'] as String? ?? '',
      email: data['email'] as String? ?? '',
      password: data['password'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
    );
  }
}

class ResetPasswordResult {
  const ResetPasswordResult({
    required this.password,
    required this.passwordChanged,
  });

  final String password;
  final bool passwordChanged;

  factory ResetPasswordResult.fromMap(Map<String, dynamic> data) {
    return ResetPasswordResult(
      password: data['password'] as String? ?? '',
      passwordChanged: data['passwordChanged'] as bool? ?? false,
    );
  }
}

/// 관리자 — 학생 상담 등록 / 계정 관리
class StudentAdminService {
  StudentAdminService(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Stream<List<StudentIntakeModel>> watchCohortIntakes(String cohortId) {
    return _firestore
        .collection(FirestorePaths.studentIntakes)
        .where('cohortId', isEqualTo: cohortId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map(StudentIntakeModel.fromFirestore).toList(),
        );
  }

  Stream<StudentIntakeModel?> watchIntake(String uid) {
    return _firestore
        .collection(FirestorePaths.studentIntakes)
        .doc(uid)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return StudentIntakeModel.fromFirestore(doc);
    });
  }

  Future<CreateStudentResult> createStudentWithIntake(
    StudentIntakeFormData form,
  ) async {
    final callable = _functions.httpsCallable(
      'createStudentAccount',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );
    final result = await callable.call<Map<String, dynamic>>(form.toJson());
    return CreateStudentResult.fromMap(result.data);
  }

  Future<ResetPasswordResult> resetStudentPassword(String uid) async {
    final callable = _functions.httpsCallable('resetStudentPassword');
    final result = await callable.call<Map<String, dynamic>>({'uid': uid});
    return ResetPasswordResult.fromMap(result.data);
  }
}

final studentAdminServiceProvider = Provider<StudentAdminService>((ref) {
  return StudentAdminService(
    ref.watch(firestoreProvider),
    FirebaseFunctions.instanceFor(region: 'asia-northeast3'),
  );
});
