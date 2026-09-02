import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/firebase_providers.dart';
import '../../../shared/services/storage_service.dart';
import '../models/curriculum_day_model.dart';
import '../models/curriculum_meta_model.dart';
import '../models/curriculum_progress_model.dart';
import '../models/curriculum_week_model.dart';

const int kCurriculumPdfMaxBytes = 20 * 1024 * 1024;

class CurriculumRepository {
  CurriculumRepository(this._firestore, this._storage);

  final FirebaseFirestore _firestore;
  final StorageService _storage;

  DocumentReference<Map<String, dynamic>> _metaRef(String cohortId) =>
      _firestore
          .collection('cohorts')
          .doc(cohortId)
          .collection('curriculum')
          .doc('meta');

  CollectionReference<Map<String, dynamic>> _weeksRef(String cohortId) =>
      _firestore
          .collection('cohorts')
          .doc(cohortId)
          .collection('curriculumWeeks');

  CollectionReference<Map<String, dynamic>> _daysRef(String cohortId) =>
      _firestore
          .collection('cohorts')
          .doc(cohortId)
          .collection('curriculumDays');

  DocumentReference<Map<String, dynamic>> _progressRef(
    String cohortId,
    String userId,
  ) =>
      _firestore
          .collection('cohorts')
          .doc(cohortId)
          .collection('curriculumProgress')
          .doc(userId);

  Stream<CurriculumMetaModel?> watchMeta(String cohortId) {
    return _metaRef(cohortId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return CurriculumMetaModel.fromFirestore(doc);
    });
  }

  Stream<List<CurriculumWeekModel>> watchWeeks(String cohortId) {
    return _weeksRef(cohortId)
        .orderBy('order')
        .snapshots()
        .map((snap) => snap.docs.map(CurriculumWeekModel.fromFirestore).toList());
  }

  Stream<List<CurriculumDayModel>> watchDays(String cohortId) {
    return _daysRef(cohortId)
        .orderBy('order')
        .snapshots()
        .map((snap) => snap.docs.map(CurriculumDayModel.fromFirestore).toList());
  }

  Stream<CurriculumDayModel?> watchDay(String cohortId, String dayId) {
    return _daysRef(cohortId).doc(dayId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return CurriculumDayModel.fromFirestore(doc);
    });
  }

  Stream<CurriculumWeekModel?> watchWeek(String cohortId, String weekId) {
    return _weeksRef(cohortId).doc(weekId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return CurriculumWeekModel.fromFirestore(doc);
    });
  }

  Stream<CurriculumProgressModel> watchProgress(
    String cohortId,
    String userId,
  ) {
    return _progressRef(cohortId, userId).snapshots().map((doc) {
      if (!doc.exists) return const CurriculumProgressModel();
      return CurriculumProgressModel.fromFirestore(doc);
    });
  }

  Future<void> saveMeta({
    required String cohortId,
    required CurriculumMetaModel meta,
    required String updatedBy,
  }) async {
    await _metaRef(cohortId).set(
      meta.toFirestore(updatedBy: updatedBy),
      SetOptions(merge: true),
    );
  }

  Future<String> createWeek({
    required String cohortId,
    required CurriculumWeekModel week,
  }) async {
    final ref = week.id.isNotEmpty
        ? _weeksRef(cohortId).doc(week.id)
        : _weeksRef(cohortId).doc();
    final model = CurriculumWeekModel(
      id: ref.id,
      weekNumber: week.weekNumber,
      title: week.title,
      summary: week.summary,
      startDate: week.startDate,
      endDate: week.endDate,
      published: week.published,
      order: week.order,
      topics: week.topics,
      links: week.links,
      attachments: week.attachments,
    );
    await ref.set(model.toFirestore());
    return ref.id;
  }

  Future<void> saveWeek({
    required String cohortId,
    required CurriculumWeekModel week,
  }) async {
    await _weeksRef(cohortId).doc(week.id).set(week.toFirestore(), SetOptions(merge: true));
  }

  Future<void> deleteWeek({
    required String cohortId,
    required String weekId,
  }) async {
    await _weeksRef(cohortId).doc(weekId).delete();
  }

  Future<void> saveDay({
    required String cohortId,
    required CurriculumDayModel day,
  }) async {
    await _daysRef(cohortId).doc(day.id).set(day.toFirestore(), SetOptions(merge: true));
  }

  Future<void> deleteDay({
    required String cohortId,
    required String dayId,
  }) async {
    await _daysRef(cohortId).doc(dayId).delete();
  }

  /// 메타 + 일수 일괄 저장 (초안 확정)
  Future<void> saveCurriculumDaysBundle({
    required String cohortId,
    required CurriculumMetaModel meta,
    required String updatedBy,
    required List<CurriculumDayModel> days,
    List<String> deleteDayIds = const [],
  }) async {
    final batch = _firestore.batch();

    batch.set(
      _metaRef(cohortId),
      meta.toFirestore(updatedBy: updatedBy),
      SetOptions(merge: true),
    );

    for (final day in days) {
      final isDraftId = day.id.startsWith('draft-');
      final ref =
          isDraftId ? _daysRef(cohortId).doc() : _daysRef(cohortId).doc(day.id);
      final model = CurriculumDayModel(
        id: ref.id,
        dayNumber: day.dayNumber,
        classDate: day.classDate,
        subject: day.subject,
        content: day.content,
        published: day.published,
        order: day.order,
        links: day.links,
        attachments: day.attachments,
      );
      batch.set(ref, model.toFirestore());
    }

    for (final dayId in deleteDayIds) {
      batch.delete(_daysRef(cohortId).doc(dayId));
    }

    await batch.commit();
  }

  /// 메타 + 주차 일괄 저장 (초안 확정)
  Future<void> saveCurriculumBundle({
    required String cohortId,
    required CurriculumMetaModel meta,
    required String updatedBy,
    required List<CurriculumWeekModel> weeks,
    List<String> deleteWeekIds = const [],
  }) async {
    final batch = _firestore.batch();

    batch.set(
      _metaRef(cohortId),
      meta.toFirestore(updatedBy: updatedBy),
      SetOptions(merge: true),
    );

    for (final week in weeks) {
      final isDraftId = week.id.startsWith('draft-');
      final ref = isDraftId
          ? _weeksRef(cohortId).doc()
          : _weeksRef(cohortId).doc(week.id);
      final model = CurriculumWeekModel(
        id: ref.id,
        weekNumber: week.weekNumber,
        title: week.title,
        summary: week.summary,
        startDate: week.startDate,
        endDate: week.endDate,
        published: week.published,
        order: week.order,
        topics: week.topics,
        links: week.links,
        attachments: week.attachments,
      );
      batch.set(ref, model.toFirestore());
    }

    for (final weekId in deleteWeekIds) {
      batch.delete(_weeksRef(cohortId).doc(weekId));
    }

    await batch.commit();
  }

  Future<String> uploadPdf({
    required String cohortId,
    required String scopeId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (bytes.length > kCurriculumPdfMaxBytes) {
      throw StateError('PDF는 20MB 이하만 업로드할 수 있습니다.');
    }
    final safeName = fileName.replaceAll(RegExp(r'[^\w.\-가-힣]'), '_');
    final path = 'cohorts/$cohortId/curriculum/$scopeId/$safeName';
    return _storage.uploadAndGetUrl(
      storagePath: path,
      bytes: bytes,
      contentType: 'application/pdf',
    );
  }

  Future<void> setLastViewedDay({
    required String cohortId,
    required String userId,
    required String dayId,
  }) async {
    await _progressRef(cohortId, userId).set(
      {
        'lastViewedDayId': dayId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> toggleDayCompleted({
    required String cohortId,
    required String userId,
    required String dayId,
    required bool completed,
  }) async {
    final doc = await _progressRef(cohortId, userId).get();
    final current = doc.exists
        ? CurriculumProgressModel.fromFirestore(doc)
        : const CurriculumProgressModel();
    final ids = List<String>.from(current.completedDayIds);
    if (completed) {
      if (!ids.contains(dayId)) ids.add(dayId);
    } else {
      ids.remove(dayId);
    }
    await _progressRef(cohortId, userId).set(
      CurriculumProgressModel(
        completedWeekIds: current.completedWeekIds,
        completedDayIds: ids,
        completedTopicIds: current.completedTopicIds,
        lastViewedWeekId: current.lastViewedWeekId,
        lastViewedDayId: current.lastViewedDayId,
      ).toFirestore(),
      SetOptions(merge: true),
    );
  }

  Future<void> setLastViewedWeek({
    required String cohortId,
    required String userId,
    required String weekId,
  }) async {
    await _progressRef(cohortId, userId).set(
      {
        'lastViewedWeekId': weekId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> toggleWeekCompleted({
    required String cohortId,
    required String userId,
    required String weekId,
    required bool completed,
  }) async {
    final doc = await _progressRef(cohortId, userId).get();
    final current = doc.exists
        ? CurriculumProgressModel.fromFirestore(doc)
        : const CurriculumProgressModel();
    final ids = List<String>.from(current.completedWeekIds);
    if (completed) {
      if (!ids.contains(weekId)) ids.add(weekId);
    } else {
      ids.remove(weekId);
    }
    await _progressRef(cohortId, userId).set(
      CurriculumProgressModel(
        completedWeekIds: ids,
        completedDayIds: current.completedDayIds,
        completedTopicIds: current.completedTopicIds,
        lastViewedWeekId: current.lastViewedWeekId,
        lastViewedDayId: current.lastViewedDayId,
      ).toFirestore(),
      SetOptions(merge: true),
    );
  }
}

final curriculumRepositoryProvider = Provider<CurriculumRepository>((ref) {
  return CurriculumRepository(
    ref.watch(firestoreProvider),
    ref.watch(storageServiceProvider),
  );
});
