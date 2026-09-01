import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/role.dart';
import '../../core/utils/date_utils.dart';

/// Firestore `users/{uid}` 문서 모델
class UserModel {
  const UserModel({
    required this.uid,
    required this.email,
    this.personalEmail,
    required this.displayName,
    required this.role,
    required this.cohortId,
    required this.cohortName,
    this.seatNumber,
    this.isActive = true,
    this.mustChangePassword = false,
    this.motto,
    this.skills = const [],
    this.socialLinks = const {},
    this.birthDate,
    this.mileageBalance = 0,
    this.createdAt,
    this.updatedAt,
    this.lastLoginAt,
  });

  final String uid;
  final String email;
  /// 구글폼 제출 매칭용 개인 이메일 (Gmail 등)
  final String? personalEmail;
  final String displayName;
  final UserRole role;
  final String cohortId;
  final String cohortName;
  final int? seatNumber;
  final bool isActive;
  final bool mustChangePassword;
  final String? motto;
  final List<String> skills;
  final Map<String, String> socialLinks;
  final String? birthDate;
  final int mileageBalance;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastLoginAt;

  bool get isAdmin => role.isAdmin;

  /// Firestore Document → UserModel
  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return UserModel(
      uid: doc.id,
      email: data['email'] as String? ?? '',
      personalEmail: data['personalEmail'] as String?,
      displayName: data['displayName'] as String? ?? '',
      role: UserRole.fromString(data['role'] as String? ?? 'student'),
      cohortId: data['cohortId'] as String? ?? '',
      cohortName: data['cohortName'] as String? ?? '',
      seatNumber: data['seatNumber'] as int?,
      isActive: data['isActive'] as bool? ?? true,
      mustChangePassword: data['mustChangePassword'] as bool? ?? false,
      motto: data['motto'] as String?,
      skills: List<String>.from(data['skills'] as List? ?? []),
      socialLinks: Map<String, String>.from(
        data['socialLinks'] as Map? ?? {},
      ),
      birthDate: data['birthDate'] as String?,
      mileageBalance: data['mileageBalance'] as int? ?? 0,
      createdAt: AppDateUtils.timestampToDateTime(data['createdAt']),
      updatedAt: AppDateUtils.timestampToDateTime(data['updatedAt']),
      lastLoginAt: AppDateUtils.timestampToDateTime(data['lastLoginAt']),
    );
  }

  /// UserModel → Firestore Map
  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      if (personalEmail != null && personalEmail!.isNotEmpty)
        'personalEmail': personalEmail,
      'displayName': displayName,
      'role': role.value,
      'cohortId': cohortId,
      'cohortName': cohortName,
      if (seatNumber != null) 'seatNumber': seatNumber,
      'isActive': isActive,
      'mustChangePassword': mustChangePassword,
      if (motto != null) 'motto': motto,
      'skills': skills,
      'socialLinks': socialLinks,
      if (birthDate != null) 'birthDate': birthDate,
      'mileageBalance': mileageBalance,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  UserModel copyWith({
    String? displayName,
    String? motto,
    List<String>? skills,
    Map<String, String>? socialLinks,
    String? birthDate,
    String? personalEmail,
    bool? mustChangePassword,
    DateTime? lastLoginAt,
  }) {
    return UserModel(
      uid: uid,
      email: email,
      personalEmail: personalEmail ?? this.personalEmail,
      displayName: displayName ?? this.displayName,
      role: role,
      cohortId: cohortId,
      cohortName: cohortName,
      seatNumber: seatNumber,
      isActive: isActive,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      motto: motto ?? this.motto,
      skills: skills ?? this.skills,
      socialLinks: socialLinks ?? this.socialLinks,
      birthDate: birthDate ?? this.birthDate,
      mileageBalance: mileageBalance,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }
}
