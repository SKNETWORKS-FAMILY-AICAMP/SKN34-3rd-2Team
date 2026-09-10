import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSidebarDarkModeKey = 'sidebar_dark_mode';
const _kSidebarDarkPaletteKey = 'sidebar_dark_palette_v1';

/// 밝은 본문(#F8F9FB)과 맞춰볼 다크 사이드바 후보 (임시 테스트용)
class SideRailDarkPalette {
  const SideRailDarkPalette({
    required this.id,
    required this.label,
    required this.background,
    required this.border,
    required this.accent,
    required this.muted,
  });

  final String id;
  final String label;
  final Color background;
  final Color border;
  final Color accent;
  final Color muted;
}

const kSideRailDarkPalettes = <SideRailDarkPalette>[
  SideRailDarkPalette(
    id: 'soft_slate',
    label: '1 Soft Slate',
    background: Color(0xFF0F172A),
    border: Color(0xFF1E293B),
    accent: Color(0xFF38BDF8),
    muted: Color(0xFF94A3B8),
  ),
  SideRailDarkPalette(
    id: 'charcoal',
    label: '2 Charcoal',
    background: Color(0xFF111827),
    border: Color(0xFF1F2937),
    accent: Color(0xFF00C2D4),
    muted: Color(0xFF94A3B8),
  ),
  SideRailDarkPalette(
    id: 'brand_navy',
    label: '3 Brand Navy',
    background: Color(0xFF0B2A6F),
    border: Color(0xFF1E3A8A),
    accent: Color(0xFF60A5FA),
    muted: Color(0xFF94A3B8),
  ),
  SideRailDarkPalette(
    id: 'soft_cinematic',
    label: '4 Soft Cinematic',
    background: Color(0xFF0B1224),
    border: Color(0xFF1E2538),
    accent: Color(0xFF00C2D4),
    muted: Color(0xFF94A3B8),
  ),
  SideRailDarkPalette(
    id: 'mid_slate',
    label: '5 Mid Slate',
    background: Color(0xFF1E293B),
    border: Color(0xFF334155),
    accent: Color(0xFF00C2D4),
    muted: Color(0xFFCBD5E1),
  ),
];

/// 사이드바만 다크/라이트 (앱 전체 테마와 무관)
class SideRailDarkMode extends Notifier<bool> {
  @override
  bool build() {
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted) return;
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

/// 다크 팔레트 인덱스 (테스트용, 로컬 저장)
class SideRailDarkPaletteIndex extends Notifier<int> {
  @override
  int build() {
    Future<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted) return;
      final saved = prefs.getInt(_kSidebarDarkPaletteKey) ?? 0;
      state = saved.clamp(0, kSideRailDarkPalettes.length - 1);
    });
    return 0;
  }

  Future<void> cycle() async {
    state = (state + 1) % kSideRailDarkPalettes.length;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSidebarDarkPaletteKey, state);
  }

  Future<void> setIndex(int index) async {
    final next = index.clamp(0, kSideRailDarkPalettes.length - 1);
    if (state == next) return;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSidebarDarkPaletteKey, state);
  }
}

final sideRailDarkPaletteIndexProvider =
    NotifierProvider<SideRailDarkPaletteIndex, int>(
  SideRailDarkPaletteIndex.new,
);

final sideRailDarkPaletteProvider = Provider<SideRailDarkPalette>((ref) {
  final index = ref.watch(sideRailDarkPaletteIndexProvider);
  return kSideRailDarkPalettes[index];
});
