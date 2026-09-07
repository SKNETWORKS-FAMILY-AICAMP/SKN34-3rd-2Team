import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/firebase_providers.dart';

/// 성취도평가 썸네일 — Storage path 우선 로드 (웹 CORS 회피), URL/메모리 fallback
class AssessmentThumbnail extends ConsumerStatefulWidget {
  const AssessmentThumbnail({
    super.key,
    this.url,
    this.storagePath,
    this.bytes,
    this.width = 96,
    this.height = 72,
    this.borderRadius = 8,
    this.placeholderIcon = Icons.quiz_outlined,
    this.placeholderIconSize = 28,
  });

  final String? url;
  final String? storagePath;
  final Uint8List? bytes;
  final double width;
  final double height;
  final double borderRadius;
  final IconData placeholderIcon;
  final double placeholderIconSize;

  static final Map<String, Uint8List> _cache = {};

  static void putCache(String key, Uint8List bytes) {
    if (key.isEmpty || bytes.isEmpty) return;
    _cache[key] = bytes;
  }

  @override
  ConsumerState<AssessmentThumbnail> createState() =>
      _AssessmentThumbnailState();
}

class _AssessmentThumbnailState extends ConsumerState<AssessmentThumbnail> {
  Uint8List? _loaded;
  var _loading = false;
  String? _loadKey;

  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(covariant AssessmentThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes ||
        oldWidget.url != widget.url ||
        oldWidget.storagePath != widget.storagePath) {
      _loaded = null;
      _loadKey = null;
      _scheduleLoad();
    }
  }

  void _scheduleLoad() {
    if (widget.bytes != null && widget.bytes!.isNotEmpty) return;
    final key = _cacheKey();
    if (key == null) return;
    final cached = AssessmentThumbnail._cache[key];
    if (cached != null) {
      _loaded = cached;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadBytes(key);
    });
  }

  String? _cacheKey() {
    final path = widget.storagePath?.trim();
    if (path != null && path.isNotEmpty) return path;
    final url = widget.url?.trim();
    if (url != null && url.isNotEmpty) return url;
    return null;
  }

  Future<void> _loadBytes(String key) async {
    if (_loading && _loadKey == key) return;
    _loading = true;
    _loadKey = key;
    try {
      final storage = ref.read(firebaseStorageProvider);
      Uint8List? data;
      final path = widget.storagePath?.trim();
      if (path != null &&
          path.isNotEmpty &&
          !path.startsWith('demo://')) {
        try {
          data = await storage.ref(path).getData(5 * 1024 * 1024);
        } catch (_) {}
      }
      final url = widget.url?.trim();
      if ((data == null || data.isEmpty) &&
          url != null &&
          url.isNotEmpty &&
          (url.startsWith('http://') || url.startsWith('https://'))) {
        try {
          data = await storage.refFromURL(url).getData(5 * 1024 * 1024);
        } catch (_) {}
      }
      if (data != null && data.isNotEmpty) {
        AssessmentThumbnail._cache[key] = data;
        if (mounted && _loadKey == key) {
          setState(() => _loaded = data);
        }
      }
    } finally {
      _loading = false;
    }
  }

  Widget _placeholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFFF3F4F6),
      alignment: Alignment.center,
      child: Icon(
        widget.placeholderIcon,
        size: widget.placeholderIconSize,
        color: AppColors.textHint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.bytes;
    final bytes = (memory != null && memory.isNotEmpty) ? memory : _loaded;
    final httpUrl = widget.url?.trim();
    // 웹 Image.network는 Storage CORS로 statusCode:0 + 오버플로우가 자주 남.
    // Storage getData 실패 시 플레이스홀더만 쓰고, 네이티브에서만 URL fallback.
    final canNetwork = !kIsWeb &&
        bytes == null &&
        httpUrl != null &&
        httpUrl.isNotEmpty &&
        (httpUrl.startsWith('http://') || httpUrl.startsWith('https://'));

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: bytes != null
            ? Image.memory(
                bytes,
                fit: BoxFit.cover,
                width: widget.width,
                height: widget.height,
                errorBuilder: (_, __, ___) => _placeholder(),
              )
            : canNetwork
                ? Image.network(
                    httpUrl,
                    fit: BoxFit.cover,
                    width: widget.width,
                    height: widget.height,
                    errorBuilder: (_, __, ___) => _placeholder(),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return _placeholder();
                    },
                  )
                : _placeholder(),
      ),
    );
  }
}
