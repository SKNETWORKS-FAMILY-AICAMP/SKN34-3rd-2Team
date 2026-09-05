import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/profile_nav_chip.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../auth/presentation/widgets/password_change_panel.dart';
import '../../auth/providers/auth_providers.dart';

/// 마이페이지 — 프로필 요약, 개인 정보, 비밀번호 변경
class MyPageScreen extends ConsumerStatefulWidget {
  const MyPageScreen({super.key});

  @override
  ConsumerState<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends ConsumerState<MyPageScreen> {
  Future<void> _savePersonalEmail(UserModel user, String email) async {
    try {
      await ref.read(lmsRepositoryProvider).updatePersonalEmail(
            uid: user.uid,
            personalEmail: email,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('개인 이메일이 저장되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e is DataException ? e.message : '$e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  Future<void> _editPersonalEmail(UserModel user) async {
    final controller = TextEditingController(text: user.personalEmail ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('개인 이메일'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '구글폼 제출 시 이 이메일로 LMS 계정과 자동 매칭됩니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'your@gmail.com',
                labelText: 'Gmail / 개인 이메일',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () {
            final error = Validators.email(controller.text);
            if (error != null) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(error)));
              return;
            }
            Navigator.pop(ctx, true);
          }, child: const Text('저장')),
        ],
      ),
    );
    if (saved == true) {
      await _savePersonalEmail(user, controller.text);
    }
    controller.dispose();
  }

  Future<void> _saveBirthDate(UserModel user, String birthDate) async {
    try {
      await ref.read(lmsRepositoryProvider).updateProfile(
            uid: user.uid,
            birthDate: birthDate,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    }
  }

  Future<void> _saveSocialLink(
    UserModel user, {
    required String key,
    required String value,
  }) async {
    final links = Map<String, String>.from(user.socialLinks);
    if (value.trim().isEmpty) {
      links.remove(key);
    } else {
      links[key] = value.trim();
    }
    try {
      await ref.read(lmsRepositoryProvider).updateProfile(
            uid: user.uid,
            socialLinks: links,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    }
  }

  Future<void> _pickBirthDate(UserModel user) async {
    final initial = user.birthDate != null && user.birthDate!.isNotEmpty
        ? DateTime.tryParse(user.birthDate!) ?? DateTime(2000, 1, 1)
        : DateTime(2000, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    await _saveBirthDate(user, AppDateUtils.toDateKey(picked));
  }

  Future<void> _editLinkDialog({
    required String title,
    required String initial,
    required ValueChanged<String> onSave,
  }) async {
    final controller = TextEditingController(text: initial);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'https://'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
        ],
      ),
    );
    if (saved == true) onSave(controller.text);
    controller.dispose();
  }

  void _goBack(UserModel user) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.homeFor(user.role));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    return currentUser.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (user) {
        if (user == null) return const SizedBox.shrink();

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PageHeader(onBack: () => _goBack(user)),
                  const SizedBox(height: 16),
                  _ProfileOverviewCard(user: user),
                  const SizedBox(height: 12),
                  _PersonalInfoCard(
                    user: user,
                    onEditPersonalEmail: () => _editPersonalEmail(user),
                    onPickBirthDate: () => _pickBirthDate(user),
                    onEditGithub: () => _editLinkDialog(
                      title: 'GitHub URL',
                      initial: user.socialLinks['github'] ?? '',
                      onSave: (v) => _saveSocialLink(user, key: 'github', value: v),
                    ),
                    onEditBlog: () => _editLinkDialog(
                      title: '블로그 URL',
                      initial: user.socialLinks['blog'] ?? '',
                      onSave: (v) => _saveSocialLink(user, key: 'blog', value: v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  MyPagePasswordSection(
                    userEmail: user.email,
                    initiallyExpanded: user.mustChangePassword,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surfaceVariant.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          '마이페이지',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _ProfileOverviewCard extends StatelessWidget {
  const _ProfileOverviewCard({required this.user});

  final UserModel user;

  String get _courseName {
    final match = RegExp(r'^(.*)\s+\d+기$').firstMatch(user.cohortName.trim());
    return match?.group(1)?.trim() ?? user.cohortName;
  }

  String get _termLabel {
    final match = RegExp(r'(\d+기)$').firstMatch(user.cohortName.trim());
    return match?.group(1) ?? '-';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProfileSummaryRow(
              user: user,
              avatarRadius: 32,
              showEditBadge: true,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _InfoRow(label: '교육과정', value: _courseName),
                  const SizedBox(height: 8),
                  _InfoRow(label: '기수', value: _termLabel),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '계정 생성일',
                    value: user.createdAt != null
                        ? AppDateUtils.formatDetailDateTime(user.createdAt!)
                        : '-',
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '마지막 로그인',
                    value: user.lastLoginAt != null
                        ? AppDateUtils.formatDetailDateTime(user.lastLoginAt!)
                        : '-',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _PersonalInfoCard extends StatelessWidget {
  const _PersonalInfoCard({
    required this.user,
    required this.onEditPersonalEmail,
    required this.onPickBirthDate,
    required this.onEditGithub,
    required this.onEditBlog,
  });

  final UserModel user;
  final VoidCallback onEditPersonalEmail;
  final VoidCallback onPickBirthDate;
  final VoidCallback onEditGithub;
  final VoidCallback onEditBlog;

  @override
  Widget build(BuildContext context) {
    final birthLabel = user.birthDate != null && user.birthDate!.isNotEmpty
        ? user.birthDate!
        : '생년월일 선택';
    final hasPersonalEmail =
        user.personalEmail != null && user.personalEmail!.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '개인 정보',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            if (!hasPersonalEmail) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '개인 이메일이 등록되지 않았습니다. 구글폼 제출 연동을 위해 등록해 주세요.',
                  style: TextStyle(fontSize: 11, color: AppColors.warning),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _LinkRow(
              icon: Icons.mail_outline,
              label: '개인 이메일 (구글폼)',
              url: user.personalEmail,
              emptyLabel: '등록된 이메일 없음',
              onEdit: onEditPersonalEmail,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            const Text(
              '생년월일',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: onPickBirthDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textHint),
                    const SizedBox(width: 8),
                    Text(
                      birthLabel,
                      style: TextStyle(
                        fontSize: 13,
                        color: user.birthDate != null && user.birthDate!.isNotEmpty
                            ? AppColors.textPrimary
                            : AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            _LinkRow(
              icon: Icons.code,
              label: 'GitHub',
              url: user.socialLinks['github'],
              onEdit: onEditGithub,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            _LinkRow(
              icon: Icons.article_outlined,
              label: '블로그',
              url: user.socialLinks['blog'],
              onEdit: onEditBlog,
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.url,
    required this.onEdit,
    this.emptyLabel = '등록된 링크 없음',
  });

  final IconData icon;
  final String label;
  final String? url;
  final VoidCallback onEdit;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    final isHttpUrl = hasUrl && url!.startsWith('http');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (hasUrl)
                isHttpUrl
                    ? InkWell(
                        onTap: () => launchUrl(Uri.parse(url!)),
                        child: Text(
                          url!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      )
                    : Text(
                        url!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                        ),
                      )
              else
                Text(
                  emptyLabel,
                  style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          visualDensity: VisualDensity.compact,
          tooltip: '수정',
        ),
      ],
    );
  }
}
