import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/firebase_providers.dart';
import '../models/seating_assignment_model.dart';
import '../models/seating_layout_model.dart';
import '../models/seating_room_model.dart';

class SeatingRepository {
  SeatingRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _roomRef(
    String cohortId,
    String roomId,
  ) =>
      _firestore
          .collection('cohorts')
          .doc(cohortId)
          .collection('seatingRooms')
          .doc(roomId);

  DocumentReference<Map<String, dynamic>> _assignmentRef(
    String cohortId,
    String roomId,
  ) =>
      _firestore
          .collection('cohorts')
          .doc(cohortId)
          .collection('seatingAssignments')
          .doc(roomId);

  DocumentReference<Map<String, dynamic>> _metaRef(String cohortId) =>
      _firestore
          .collection('cohorts')
          .doc(cohortId)
          .collection('seatingMeta')
          .doc('default');

  DocumentReference<Map<String, dynamic>> _legacyLayoutRef(String cohortId) =>
      _firestore
          .collection('cohorts')
          .doc(cohortId)
          .collection('seating')
          .doc('layout');

  DocumentReference<Map<String, dynamic>> _legacyAssignmentRef(
    String cohortId,
  ) =>
      _firestore
          .collection('cohorts')
          .doc(cohortId)
          .collection('seating')
          .doc('assignment');

  Stream<List<SeatingRoomModel>> watchRooms(String cohortId) {
    return _firestore
        .collection('cohorts')
        .doc(cohortId)
        .collection('seatingRooms')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isEmpty) {
        final migrated = await _tryMigrateLegacyLayout(cohortId);
        if (migrated != null) return [migrated];
        return [];
      }
      return snap.docs.map(SeatingRoomModel.fromFirestore).toList();
    });
  }

  Stream<SeatingRoomModel?> watchRoom(String cohortId, String roomId) {
    return _roomRef(cohortId, roomId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return SeatingRoomModel.fromFirestore(doc);
    });
  }

  Stream<SeatingAssignmentModel?> watchAssignment(
    String cohortId,
    String roomId,
  ) {
    return _assignmentRef(cohortId, roomId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return SeatingAssignmentModel.fromFirestore(doc);
    });
  }

  Stream<SeatingMetaModel> watchMeta(String cohortId) {
    return _metaRef(cohortId).snapshots().map((doc) {
      if (!doc.exists) return const SeatingMetaModel();
      return SeatingMetaModel.fromFirestore(doc);
    });
  }

  Future<SeatingRoomModel?> _tryMigrateLegacyLayout(String cohortId) async {
    final legacyDoc = await _legacyLayoutRef(cohortId).get();
    if (!legacyDoc.exists) return null;

    final layout = SeatingLayoutModel.fromFirestore(legacyDoc);
    final roomId = _firestore.collection('_').doc().id;
    final roomRef = _roomRef(cohortId, roomId);

    await roomRef.set(layout.toFirestore(updatedBy: 'migration'));

    final legacyAssignment = await _legacyAssignmentRef(cohortId).get();
    if (legacyAssignment.exists) {
      await _assignmentRef(cohortId, roomId).set(legacyAssignment.data()!);
      final data = legacyAssignment.data()!;
      if (data['status'] == 'published') {
        await _metaRef(cohortId).set(
          SeatingMetaModel(publishedRoomId: roomId).toFirestore(
            publishedRoomId: roomId,
          ),
          SetOptions(merge: true),
        );
      }
    }

    return SeatingRoomModel.fromFirestore(await roomRef.get());
  }

  Future<String> createRoom({
    required String cohortId,
    required SeatingLayoutModel layout,
    required String updatedBy,
  }) async {
    final roomId = _firestore.collection('_').doc().id;
    final room = SeatingRoomModel(id: roomId, layout: layout);
    await _roomRef(cohortId, roomId).set(
      room.toFirestore(updatedBy: updatedBy, isCreate: true),
    );
    return roomId;
  }

  Future<void> saveRoom({
    required String cohortId,
    required String roomId,
    required SeatingLayoutModel layout,
    required String updatedBy,
  }) async {
    await _roomRef(cohortId, roomId).set(
      layout.toFirestore(updatedBy: updatedBy),
      SetOptions(merge: true),
    );
  }

  Stream<SeatingLayoutModel?> watchPublishedLayout(String cohortId) {
    return watchMeta(cohortId).asyncExpand((meta) {
      final roomId = meta.publishedRoomId;
      if (roomId != null) {
        return watchRoom(cohortId, roomId).map((room) => room?.layout);
      }
      return _legacyLayoutRef(cohortId).snapshots().map((doc) {
        if (!doc.exists) return null;
        return SeatingLayoutModel.fromFirestore(doc);
      });
    });
  }

  Stream<SeatingAssignmentModel?> watchPublishedAssignment(String cohortId) {
    return watchMeta(cohortId).asyncExpand((meta) {
      final roomId = meta.publishedRoomId;
      if (roomId != null) {
        return watchAssignment(cohortId, roomId);
      }
      return _legacyAssignmentRef(cohortId).snapshots().map((doc) {
        if (!doc.exists) return null;
        return SeatingAssignmentModel.fromFirestore(doc);
      });
    });
  }

  Future<void> deleteRoom({
    required String cohortId,
    required String roomId,
  }) async {
    final batch = _firestore.batch();
    batch.delete(_roomRef(cohortId, roomId));
    batch.delete(_assignmentRef(cohortId, roomId));

    final meta = await _metaRef(cohortId).get();
    if (meta.data()?['publishedRoomId'] == roomId) {
      batch.set(
        _metaRef(cohortId),
        {
          'publishedRoomId': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> saveAssignment({
    required String cohortId,
    required String roomId,
    required SeatingAssignmentModel assignment,
    required String updatedBy,
  }) async {
    await _assignmentRef(cohortId, roomId).set(
      assignment.toFirestore(updatedBy: updatedBy),
      SetOptions(merge: true),
    );
  }

  Future<void> publishAssignment({
    required String cohortId,
    required String roomId,
    required Map<String, String> assignments,
    required Map<String, String> seatNames,
    required String publishedBy,
  }) async {
    final batch = _firestore.batch();

    final existingAssignments = await _firestore
        .collection('cohorts')
        .doc(cohortId)
        .collection('seatingAssignments')
        .where('status', isEqualTo: 'published')
        .get();

    for (final doc in existingAssignments.docs) {
      if (doc.id != roomId) {
        batch.update(doc.reference, {'status': 'draft'});
      }
    }

    batch.set(
      _assignmentRef(cohortId, roomId),
      {
        'status': SeatingAssignmentStatus.published.value,
        'assignments': assignments,
        'seatNames': seatNames,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': publishedBy,
        'publishedAt': FieldValue.serverTimestamp(),
        'publishedBy': publishedBy,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _metaRef(cohortId),
      SeatingMetaModel(publishedRoomId: roomId).toFirestore(
        publishedRoomId: roomId,
      ),
      SetOptions(merge: true),
    );

    await batch.commit();
  }
}

final seatingRepositoryProvider = Provider<SeatingRepository>((ref) {
  return SeatingRepository(ref.watch(firestoreProvider));
});
