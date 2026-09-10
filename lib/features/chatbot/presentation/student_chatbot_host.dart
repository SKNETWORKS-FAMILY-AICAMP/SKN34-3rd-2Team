import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/providers/firebase_providers.dart';
import '../data/student_chatbot_api_client.dart';

class StudentChatbotHost extends ConsumerStatefulWidget {
  const StudentChatbotHost({
    super.key,
    required this.user,
    required this.child,
    this.apiClient,
  });

  final UserModel user;
  final Widget child;
  final StudentChatbotApiClient? apiClient;

  @override
  ConsumerState<StudentChatbotHost> createState() => _StudentChatbotHostState();
}

class _StudentChatbotHostState extends ConsumerState<StudentChatbotHost> {
  static const _faqAnswers = {
    '출결 기준': '''**출결 기준**

- **출석**: 정규수업 8시간을 모두 수강한 경우
- **결석**: 정규수업의 50%인 4시간 미만을 수강한 경우
- **지각·조퇴·외출**: 4시간 이상 8시간 미만을 수강한 경우
- 단위기간 내 지각·조퇴·외출 합계 3회는 결석 1일로 처리돼요.
- 단위기간 출석률 50% 미만 또는 전체 훈련기간 출석률 80% 미만이면 제적 대상이에요.''',
    '공가 사용 방법': '''**공가 사용 방법**

1. 공가 사용 당일 출결이슈 구글폼으로 일정을 공유해 주세요.
2. 다음 출석일 16:50에 라운지에서 증빙서류를 제출해 주세요.
3. 출석입력대장에 서명해 주세요.

훈련·시험, 면접, 예비군, 병가, 휴가 등이 증빙 제출 시 공가로 인정될 수 있어요.''',
    '캠퍼스 운영 시간': '''캠퍼스 운영 시간은 **오전 8:30부터 오후 9:50까지**예요.

공식 오픈 시간은 오전 8:30이며, 일찍 출근한 직원이 있는 경우 더 일찍 열릴 수 있어요.''',
    '훈련장려금': '''훈련장려금은 **단위기간 출석률 80% 이상**이 지급 기준이에요.

단위기간 종료 후 공가 등 출석 증빙이 반영되면 비용 신청이 진행돼요. 실업급여 등 다른 지원금 수급이나 취업 상태에 따라 지급 대상에서 제외될 수 있어요.''',

    '질문 가이드': '''**질문할 수 있는 내용**

- LMS 정책·FAQ, 출결·공가, 훈련장려금, 교육 일정
- 캠퍼스 운영 공지와 이전 기수 프로젝트 레퍼런스

**질문하는 방법**

질문의 대상과 조건을 함께 적어 주세요. 기수·차수·단위기간·날짜·원하는 개수를 넣으면 더 정확하게 안내할 수 있어요.

- 공지: “34기 라운지 취식 가능 여부를 알려줘”
- 출결: “3단위기간 출석률 85%면 훈련장려금을 받을 수 있어?”
- 프로젝트: “25기 3차 프로젝트 주제 5개와 핵심 기술을 알려줘”
- 최종 프로젝트: “34기 최종 프로젝트 레퍼런스 3개를 비교해줘”

검색 근거가 없는 내용이나 LMS와 관련 없는 질문에는 답변하기 어려워요.''',
  };

  late StudentChatbotApiClient _api;
  late bool _ownsApi;
  late String _threadId;
  final _messages = <_ChatMessage>[];
  final _questionController = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _open = false;
  bool _searching = false;
  bool _initializing = false;
  bool _ready = false;
  bool _answering = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _threadId = _newThreadId();
    _ownsApi = widget.apiClient == null;
    _api =
        widget.apiClient ??
        StudentChatbotApiClient(
          token: () async =>
              await ref.read(firebaseAuthProvider).currentUser?.getIdToken(),
        );
    if (widget.user.isStudent) _initialize();
  }

  @override
  void didUpdateWidget(covariant StudentChatbotHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid && widget.user.isStudent) {
      _newChat();
    }
  }

  @override
  void dispose() {
    if (_ownsApi) _api.close();
    _questionController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _newThreadId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _initialize() async {
    setState(() {
      _initializing = true;
      _ready = false;
      _error = null;
    });
    try {
      await _api.initialize(_threadId);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _messages
          ..clear()
          ..add(
            const _ChatMessage(
              text: '안녕하세요! LMS 정책, 공지, 출결과 이전 기수 프로젝트를 도와드릴게요.',
              fromUser: false,
            ),
          );
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('FormatException: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _newChat() async {
    if (_answering) return;
    _threadId = _newThreadId();
    _searchController.clear();
    _searching = false;
    await _initialize();
  }

  void _showFaq(String label, String answer) {
    if (!_ready || _answering) return;
    setState(() {
      _messages
        ..add(_ChatMessage(text: '$label을 알려주세요.', fromUser: true))
        ..add(_ChatMessage(text: answer, fromUser: false));
    });
    _scrollToBottom();
  }

  Future<void> _send([String? preset]) async {
    final question = (preset ?? _questionController.text).trim();
    if (question.isEmpty || !_ready || _answering) return;
    _questionController.clear();
    setState(() {
      _answering = true;
      _error = null;
      _messages
        ..add(_ChatMessage(text: question, fromUser: true))
        ..add(const _ChatMessage(text: '', fromUser: false));
    });
    _scrollToBottom();

    try {
      await for (final chunk in _api.ask(
        threadId: _threadId,
        question: question,
      )) {
        if (!mounted) return;
        setState(() {
          final current = _messages.last;
          _messages[_messages.length - 1] = current.copyWith(
            text: current.text + chunk,
          );
        });
        _scrollToBottom();
      }
      if (mounted && _messages.last.text.isEmpty) {
        setState(
          () => _messages[_messages.length - 1] = const _ChatMessage(
            text: '답변을 생성하지 못했습니다. 다시 시도해 주세요.',
            fromUser: false,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _messages[_messages.length - 1] = _ChatMessage(
          text: error.toString().replaceFirst('FormatException: ', ''),
          fromUser: false,
          isError: true,
        ),
      );
    } finally {
      if (mounted) setState(() => _answering = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.isStudent) return widget.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final width = compact ? constraints.maxWidth - 24 : 390.0;
        final height = (constraints.maxHeight - 92)
            .clamp(420.0, 640.0)
            .toDouble();
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: widget.child),
            if (_open)
              Positioned(
                right: compact ? 12 : 20,
                bottom: 76,
                child: _ChatPanel(
                  width: width,
                  height: height,
                  messages: _filteredMessages,
                  searchQuery: _searching ? _searchController.text.trim() : '',
                  questionController: _questionController,
                  searchController: _searchController,
                  scrollController: _scrollController,
                  faqAnswers: _faqAnswers,
                  searching: _searching,
                  initializing: _initializing,
                  answering: _answering,
                  ready: _ready,
                  error: _error,
                  onClose: () => setState(() => _open = false),
                  onToggleSearch: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _searchController.clear();
                  }),
                  onSearchChanged: (_) => setState(() {}),
                  onNewChat: _newChat,
                  onRetry: _initialize,
                  onSend: _send,
                  onFaq: _showFaq,
                ),
              ),
            Positioned(
              right: compact ? 12 : 20,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'student-chatbot',
                tooltip: _open ? '챗봇 닫기' : '학생 챗봇 열기',
                onPressed: () => setState(() => _open = !_open),
                child: Icon(
                  _open ? Icons.close_rounded : Icons.smart_toy_rounded,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<_ChatMessage> get _filteredMessages {
    final query = _searchController.text.trim().toLowerCase();
    if (!_searching || query.isEmpty) return _messages;
    return _messages
        .where((message) => message.text.toLowerCase().contains(query))
        .toList();
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.width,
    required this.height,
    required this.messages,
    required this.searchQuery,
    required this.questionController,
    required this.searchController,
    required this.scrollController,
    required this.faqAnswers,
    required this.searching,
    required this.initializing,
    required this.answering,
    required this.ready,
    required this.error,
    required this.onClose,
    required this.onToggleSearch,
    required this.onSearchChanged,
    required this.onNewChat,
    required this.onRetry,
    required this.onSend,
    required this.onFaq,
  });

  final double width;
  final double height;
  final List<_ChatMessage> messages;
  final String searchQuery;
  final TextEditingController questionController;
  final TextEditingController searchController;
  final ScrollController scrollController;
  final Map<String, String> faqAnswers;
  final bool searching;
  final bool initializing;
  final bool answering;
  final bool ready;
  final String? error;
  final VoidCallback onClose;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onNewChat;
  final VoidCallback onRetry;
  final ValueChanged<String?> onSend;
  final void Function(String label, String answer) onFaq;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 18,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      color: AppColors.surface,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _header(),
            if (searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: TextField(
                  controller: searchController,
                  autofocus: true,
                  onChanged: onSearchChanged,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    hintText: '현재 채팅 기록 검색',
                  ),
                ),
              ),
            Expanded(child: _body()),
            _input(),
            const Padding(
              padding: EdgeInsets.only(bottom: 9),
              child: Text(
                '챗봇은 실수할 수 있습니다',
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
    height: 58,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    color: AppColors.primary,
    child: Row(
      children: [
        const CircleAvatar(
          radius: 17,
          backgroundColor: Colors.white,
          child: Icon(
            Icons.smart_toy_rounded,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 9),
        const Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PLAYDATA 챗봇',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '● 온라인',
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
        ),
        _headerButton(Icons.search_rounded, '기록 검색', onToggleSearch),
        _headerButton(Icons.add_rounded, '새 채팅', onNewChat),
        _headerButton(Icons.close_rounded, '닫기', onClose),
      ],
    ),
  );

  Widget _headerButton(IconData icon, String tooltip, VoidCallback onPressed) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 20, color: Colors.white),
      );

  Widget _body() {
    if (initializing) {
      return const _ChatLoading(
        initialLabel: '학생 정보를 불러오는 중입니다...',
        centered: true,
      );
    }
    if (error != null && !ready) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.error,
                size: 32,
              ),
              const SizedBox(height: 10),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: const Text(
              'FAQ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Wrap(
            spacing: 5,
            runSpacing: 2,
            children: faqAnswers.entries
                .map(
                  (entry) => ActionChip(
                    avatar: const Icon(Icons.help_outline_rounded, size: 16),
                    label: Text(
                      entry.key,
                      style: const TextStyle(fontSize: 11),
                    ),
                    onPressed: answering
                        ? null
                        : () => onFaq(entry.key, entry.value),
                  ),
                )
                .toList(),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Text(
                    '검색 결과가 없습니다.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    if (answering &&
                        index == messages.length - 1 &&
                        !message.fromUser &&
                        message.text.isEmpty) {
                      return const _ChatLoading(
                        initialLabel: '챗봇이 정보를 검색 중입니다...',
                        nextLabel: '챗봇이 답변을 생성하는 중입니다...',
                      );
                    }
                    return _MessageBubble(
                      message: message,
                      highlight: searchQuery,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _input() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
    child: TextField(
      controller: questionController,
      enabled: ready && !answering,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => onSend(null),
      decoration: InputDecoration(
        isDense: true,
        hintText: '메시지를 입력하세요',
        suffixIcon: IconButton(
          tooltip: '질문 보내기',
          onPressed: ready && !answering ? () => onSend(null) : null,
          icon: const Icon(Icons.send_rounded),
        ),
      ),
    ),
  );
}

class _ChatLoading extends StatefulWidget {
  const _ChatLoading({
    required this.initialLabel,
    this.nextLabel,
    this.centered = false,
  });

  final String initialLabel;
  final String? nextLabel;
  final bool centered;

  @override
  State<_ChatLoading> createState() => _ChatLoadingState();
}

class _ChatLoadingState extends State<_ChatLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _labelTimer;
  var _showNextLabel = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    if (widget.nextLabel != null) {
      _labelTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _showNextLabel = true);
      });
    }
  }

  @override
  void dispose() {
    _labelTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '챗봇 응답 대기 중',
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              key: const Key('chatbot-loading-dots'),
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final wave = math.sin(
                  (_controller.value * math.pi * 2) - (index * 0.8),
                );
                return Transform.translate(
                  offset: Offset(0, -4 * wave),
                  child: Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Text(
            _showNextLabel ? widget.nextLabel! : widget.initialLabel,
            key: ValueKey(_showNextLabel),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
    return widget.centered
        ? Center(child: content)
        : Align(alignment: Alignment.centerLeft, child: content);
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.highlight});
  final _ChatMessage message;
  final String highlight;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: message.fromUser
        ? MainAxisAlignment.end
        : MainAxisAlignment.start,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (!message.fromUser) ...[
        const CircleAvatar(
          radius: 14,
          backgroundColor: AppColors.primary,
          child: Icon(Icons.smart_toy_rounded, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 7),
      ],
      Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: message.fromUser
                ? AppColors.primary
                : message.isError
                ? AppColors.error.withValues(alpha: 0.1)
                : AppColors.background,
            borderRadius: BorderRadius.circular(13),
          ),
          child: message.fromUser || message.isError
              ? _HighlightedText(
                  text: message.text,
                  query: highlight,
                  style: TextStyle(
                    color: message.fromUser
                        ? Colors.white
                        : AppColors.textPrimary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                )
              : highlight.isNotEmpty
              ? _HighlightedMarkdown(text: message.text, query: highlight)
              : MarkdownBody(
                  data: message.text,
                  selectable: true,
                  softLineBreak: true,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    listBullet: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    strong: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                    code: const TextStyle(
                      color: AppColors.textPrimary,
                      backgroundColor: AppColors.surfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
        ),
      ),
    ],
  );
}

class _HighlightedMarkdown extends StatelessWidget {
  const _HighlightedMarkdown({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style.copyWith(
      color: AppColors.textPrimary,
      fontSize: 13,
      height: 1.4,
    );
    final spans = <InlineSpan>[];
    final bold = RegExp(r'\*\*(.*?)\*\*', dotAll: true);
    var cursor = 0;
    for (final match in bold.allMatches(text)) {
      spans.addAll(
        _highlightSpans(text.substring(cursor, match.start), query, baseStyle),
      );
      spans.addAll(
        _highlightSpans(
          match.group(1)!,
          query,
          baseStyle.copyWith(fontWeight: FontWeight.w800),
        ),
      );
      cursor = match.end;
    }
    spans.addAll(_highlightSpans(text.substring(cursor), query, baseStyle));
    return Text.rich(
      key: const Key('chat-search-highlight'),
      TextSpan(children: spans),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.style,
  });

  final String text;
  final String query;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text.rich(
    key: const Key('chat-search-highlight'),
    TextSpan(children: _highlightSpans(text, query, style)),
  );
}

List<InlineSpan> _highlightSpans(String text, String query, TextStyle style) {
  if (query.isEmpty) return [TextSpan(text: text, style: style)];
  final matches = RegExp(
    RegExp.escape(query),
    caseSensitive: false,
  ).allMatches(text);
  if (matches.isEmpty) return [TextSpan(text: text, style: style)];

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(text: text.substring(cursor, match.start), style: style),
      );
    }
    spans.add(
      TextSpan(
        text: text.substring(match.start, match.end),
        style: style.copyWith(
          backgroundColor: AppColors.warning.withValues(alpha: 0.32),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: style));
  }
  return spans;
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.fromUser,
    this.isError = false,
  });
  final String text;
  final bool fromUser;
  final bool isError;

  _ChatMessage copyWith({String? text}) => _ChatMessage(
    text: text ?? this.text,
    fromUser: fromUser,
    isError: isError,
  );
}
