import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSidebarDarkModeKey = 'sidebar_dark_mode';

/// 사이드바만 다크/라이트 (앱 전체 테마와 무관)
class SideRailDarkMode extends Notifier<bool> {
  @override
  bool build() {
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted) return;
      // 예전 앱 전체 다크 키도 사이드바 설정으로 이어받음
      state = prefs.getBool(_kSidebarDarkModeKey) ??
          prefs.getBool('app_dark_mode') ??
          false;
    });
    return false;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSidebarDarkModeKey, state);
  }

  Future<void> setDark(bool value) async {
    if (state == value) return;
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSidebarDarkModeKey, state);
  }
}

final sideRailDarkModeProvider =
    NotifierProvider<SideRailDarkMode, bool>(SideRailDarkMode.new);
