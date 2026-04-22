import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import '../../core/constants/app_colors.dart';
import '../../data/models/models.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

class GroupMediaScreen extends StatefulWidget {
  final String conversationId;
  final String title;

  const GroupMediaScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  @override
  State<GroupMediaScreen> createState() => _GroupMediaScreenState();
}

class _GroupMediaScreenState extends State<GroupMediaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _skip = 0;
  static const int _pageSize = 50;

  final List<MessageModel> _all = [];
  final List<MessageModel> _media = [];
  final List<MessageModel> _files = [];
  final List<_LinkItem> _links = [];
  final List<MessageModel> _voices = [];
  final Set<String> _seenLinkUrls = {};

  final ScrollController _scrollCtrl = ScrollController();

  // Voice player (1 player dùng chung)
  final AudioPlayer _voicePlayer = AudioPlayer();
  StreamSubscription<Duration>? _voicePosSub;
  StreamSubscription<Duration>? _voiceDurSub;
  StreamSubscription<PlayerState>? _voiceStateSub;
  Duration _voicePos = Duration.zero;
  Duration _voiceDur = Duration.zero;
  PlayerState _voiceState = PlayerState.stopped;
  String? _playingMessageId;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _scrollCtrl.addListener(_onScroll);
    _loadFirst();

    _voicePosSub = _voicePlayer.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _voicePos = p);
    });
    _voiceDurSub = _voicePlayer.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _voiceDur = d);
    });
    _voiceStateSub = _voicePlayer.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _voiceState = s);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _tabCtrl.dispose();
    _voicePosSub?.cancel();
    _voiceDurSub?.cancel();
    _voiceStateSub?.cancel();
    _voicePlayer.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 320) {
      _loadMore();
    }
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _hasMore = true;
      _skip = 0;
      _all.clear();
      _media.clear();
      _files.clear();
      _links.clear();
      _voices.clear();
      _seenLinkUrls.clear();
    });
    await _loadMore();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    final myId = authService.userId ?? '';
    if (myId.isEmpty) {
      if (mounted) {
        setState(() {
          _hasMore = false;
          _loading = false;
        });
      }
      return;
    }

    setState(() => _loadingMore = true);
    try {
      final page = await apiService.getMessages(
        widget.conversationId,
        myId,
        limit: _pageSize,
        skip: _skip,
      );

      if (!mounted) return;

      if (page.isEmpty) {
        setState(() {
          _hasMore = false;
          _loadingMore = false;
        });
        return;
      }

      _skip += page.length;
      _all.addAll(page);
      _indexMessages(page);

      setState(() {
        _hasMore = page.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _indexMessages(List<MessageModel> msgs) {
    for (final m in msgs) {
      if (m.isRecalled) continue;

      final t = (m.type).toUpperCase();
      if (t == 'IMAGE' || t == 'VIDEO') {
        if (m.content.trim().isNotEmpty) _media.add(m);
        continue;
      }
      if (t == 'FILE') {
        _files.add(m);
        continue;
      }
      if (t == 'VOICE') {
        if (m.content.trim().isNotEmpty) _voices.add(m);
        continue;
      }
      if (t == 'TEXT') {
        final found = _extractUrls(m.content);
        for (final u in found) {
          if (_seenLinkUrls.add(u)) {
            _links.add(_LinkItem(url: u, message: m));
          }
        }
      }
    }
  }

  List<String> _extractUrls(String text) {
    final t = text.trim();
    if (t.isEmpty) return const [];
    final reg = RegExp(r'(https?:\/\/[^\s]+)', caseSensitive: false);
    return reg
        .allMatches(t)
        .map((m) => (m.group(0) ?? '').replaceAll(RegExp(r'[)\],.]+$'), ''))
        .where((u) => u.isNotEmpty)
        .toList();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _fmtClock(Duration d) {
    final total = d.inSeconds.clamp(0, 24 * 3600);
    final m = (total ~/ 60).toString();
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Duration _voiceTotalFor(MessageModel m) {
    final sec = m.metadata?.duration;
    if (sec != null && sec > 0) return Duration(seconds: sec);
    return _voiceDur;
  }

  Future<void> _toggleVoice(MessageModel m) async {
    final url = m.content.trim();
    if (url.isEmpty) return;
    try {
      final isSame = _playingMessageId == m.id;
      final isPlaying = _voiceState == PlayerState.playing;
      if (isSame && isPlaying) {
        await _voicePlayer.pause();
        return;
      }
      if (!isSame) {
        _playingMessageId = m.id;
        _voicePos = Duration.zero;
        _voiceDur = Duration.zero;
        await _voicePlayer.stop();
        await _voicePlayer.setSourceUrl(url);
      }
      await _voicePlayer.resume();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không phát được tin nhắn thoại.')),
      );
    }
  }

  Future<void> _seekVoice(Duration target) async {
    try {
      await _voicePlayer.seek(target);
    } catch (_) {}
  }

  String _fileLabel(MessageModel m) {
    final name = m.metadata?.fileName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final uri = Uri.tryParse(m.content.trim());
    final last = uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : null;
    if (last != null && last.isNotEmpty) return last;
    return 'Tệp đính kèm';
  }

  IconData _fileIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.description_rounded;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return Icons.grid_on_rounded;
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) return Icons.slideshow_rounded;
    if (lower.endsWith('.zip') || lower.endsWith('.rar')) return Icons.archive_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Widget _empty(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          // Tránh 3 tab chia đều width → chữ tab dài (Ảnh/Video) bị clip / không vẽ trên web.
          isScrollable: true,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.72),
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: 'Ảnh/Video'),
            Tab(text: 'File'),
            Tab(text: 'Link'),
            Tab(text: 'Thoại'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            onPressed: _loading ? null : _loadFirst,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildMediaTab(),
                _buildFilesTab(),
                _buildLinksTab(),
                _buildVoicesTab(),
              ],
            ),
    );
  }

  Widget _buildMediaTab() {
    if (_media.isEmpty && !_loadingMore) {
      return _empty('Chưa có ảnh hoặc video trong nhóm này.');
    }
    return CustomScrollView(
      controller: _scrollCtrl,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(10),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final m = _media[i];
                final url = m.content.trim();
                final isVideo = m.type.toUpperCase() == 'VIDEO';
                return InkWell(
                  onTap: () => _openUrl(url),
                  borderRadius: BorderRadius.circular(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.bgCard,
                            child: const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: AppColors.textHint,
                              ),
                            ),
                          ),
                          loadingBuilder: (c, child, prog) {
                            if (prog == null) return child;
                            return Container(
                              color: AppColors.bgCard,
                              child: const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        if (isVideo)
                          const Align(
                            alignment: Alignment.center,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0x77000000),
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
              childCount: _media.length,
            ),
          ),
        ),
        SliverToBoxAdapter(child: _buildLoadingMore()),
      ],
    );
  }

  Widget _buildFilesTab() {
    if (_files.isEmpty && !_loadingMore) {
      return _empty('Chưa có file nào trong nhóm này.');
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _files.length + 1,
      itemBuilder: (_, i) {
        if (i == _files.length) return _buildLoadingMore();
        final m = _files[i];
        final label = _fileLabel(m);
        return ListTile(
          leading: Icon(_fileIcon(label), color: AppColors.primary),
          title: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: (m.metadata?.fileSize != null && m.metadata!.fileSize! > 0)
              ? Text(
                  '${m.metadata!.fileSize} bytes',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: AppColors.textHint,
                    fontSize: 12,
                  ),
                )
              : null,
          trailing: IconButton(
            icon: const Icon(Icons.download_rounded, color: AppColors.textSecondary),
            onPressed: () => _openUrl(m.content.trim()),
          ),
          onTap: () => _openUrl(m.content.trim()),
        );
      },
    );
  }

  Widget _buildLinksTab() {
    if (_links.isEmpty && !_loadingMore) {
      return _empty('Chưa có link nào trong nhóm này.');
    }
    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _links.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
      itemBuilder: (_, i) {
        if (i == _links.length) return _buildLoadingMore();
        final item = _links[i];
        return ListTile(
          leading: const Icon(Icons.link_rounded, color: AppColors.primary),
          title: Text(
            item.url,
            style: const TextStyle(
              fontFamily: 'Inter',
              color: AppColors.textPrimary,
              fontSize: 13,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _fmtTime(item.message.createdAt),
            style: const TextStyle(
              fontFamily: 'Inter',
              color: AppColors.textHint,
              fontSize: 12,
            ),
          ),
          onTap: () => _openUrl(item.url),
        );
      },
    );
  }

  Widget _buildVoicesTab() {
    if (_voices.isEmpty && !_loadingMore) {
      return _empty('Chưa có tin nhắn thoại trong nhóm này.');
    }
    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _voices.length + 1,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.divider),
      itemBuilder: (_, i) {
        if (i == _voices.length) return _buildLoadingMore();
        final m = _voices[i];
        final isCurrent = _playingMessageId == m.id;
        final total = _voiceTotalFor(m);
        final pos = isCurrent ? _voicePos : Duration.zero;
        final maxSec = total.inSeconds > 0 ? total.inSeconds : 1;
        final value = (pos.inSeconds.clamp(0, maxSec)).toDouble();
        final isPlaying = isCurrent && _voiceState == PlayerState.playing;

        return ListTile(
          leading: InkWell(
            onTap: () => _toggleVoice(m),
            borderRadius: BorderRadius.circular(99),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: AppColors.primary,
              ),
            ),
          ),
          title: const Text(
            'Tin nhắn thoại',
            style: TextStyle(
              fontFamily: 'Inter',
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Slider(
                  min: 0,
                  max: maxSec.toDouble(),
                  value: value,
                  onChanged: isCurrent
                      ? (v) => _seekVoice(Duration(seconds: v.toInt()))
                      : null,
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.border,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _fmtClock(pos),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: AppColors.textHint,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    _fmtClock(total),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: AppColors.textHint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          onTap: () => _toggleVoice(m),
        );
      },
    );
  }

  String _fmtTime(DateTime t) {
    final d = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _buildLoadingMore() {
    if (!_loadingMore) {
      if (!_hasMore) return const SizedBox(height: 16);
      return const SizedBox(height: 10);
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _LinkItem {
  final String url;
  final MessageModel message;
  const _LinkItem({required this.url, required this.message});
}

