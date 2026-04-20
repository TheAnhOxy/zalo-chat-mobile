import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/image_utils.dart';
import '../../data/models/models.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../../widgets/common/common_widgets.dart';

class ForwardMessageScreen extends StatefulWidget {
  final MessageModel? message;

  const ForwardMessageScreen({super.key, this.message});

  @override
  State<ForwardMessageScreen> createState() => _ForwardMessageScreenState();
}

class _ForwardMessageScreenState extends State<ForwardMessageScreen> {
  List<ConversationModel> _conversations = [];
  final Map<String, UserModel> _userProfiles = {};
  final Set<String> _sendingConversationIds = {};
  final Set<String> _sentConversationIds = {};
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    final myId = authService.userId;
    if (myId == null || myId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Không xác định được người dùng hiện tại';
      });
      return;
    }

    try {
      final conversations = await apiService.getConversations(myId);
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _isLoading = false;
        _loadError = null;
      });
      await _fetchOtherUserProfiles(conversations);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Không tải được danh sách hội thoại';
      });
    }
  }

  Future<void> _fetchOtherUserProfiles(List<ConversationModel> conversations) async {
    final myId = authService.userId ?? '';
    final ids = conversations
        .where((c) => !c.isGroup)
        .map((c) => _getOtherUserId(c))
      .where((id) => id?.isNotEmpty == true)
      .cast<String>()
        .where((id) => id != myId && !_userProfiles.containsKey(id))
        .toSet()
        .toList();

    if (ids.isEmpty) return;

    final results = await Future.wait(ids.map((id) => apiService.getUserById(id)));
    final updates = <String, UserModel>{};
    for (final user in results) {
      if (user != null && user.id.isNotEmpty) {
        updates[user.id] = user;
      }
    }

    if (updates.isEmpty || !mounted) return;
    setState(() => _userProfiles.addAll(updates));
  }

  ConversationMember? _findOtherMember(ConversationModel conversation) {
    if (conversation.members.isEmpty) return null;

    final myId = authService.userId;
    for (final member in conversation.members) {
      if (member.userId != myId) return member;
    }

    return conversation.members.first;
  }

  String? _getOtherUserId(ConversationModel conversation) {
    if (conversation.isGroup) return null;
    return _findOtherMember(conversation)?.userId;
  }

  String _getDisplayName(ConversationModel conversation) {
    if (conversation.isGroup) {
      return conversation.name?.isNotEmpty == true ? conversation.name! : 'Nhóm';
    }

    final otherId = _getOtherUserId(conversation);
    final profile = otherId != null ? _userProfiles[otherId] : null;
    if (profile != null && profile.fullName.isNotEmpty) return profile.fullName;

    final other = _findOtherMember(conversation);
    if (other == null) return 'Người dùng';

    if (other.nickname != null && other.nickname!.isNotEmpty) {
      return other.nickname!;
    }
    if (other.name != null && other.name!.isNotEmpty) {
      return other.name!;
    }
    return 'Người dùng';
  }

  String? _getAvatar(ConversationModel conversation) {
    if (conversation.isGroup) {
      return conversation.avatar?.isNotEmpty == true ? conversation.avatar : null;
    }
    final otherId = _getOtherUserId(conversation);
    final profile = otherId != null ? _userProfiles[otherId] : null;
    if (profile != null && profile.avatar.isNotEmpty) return profile.avatar;
    return conversation.avatar?.isNotEmpty == true ? conversation.avatar : null;
  }

  Map<String, dynamic>? _buildForwardMetadata(MessageModel message) {
    final md = message.metadata;
    if (md == null) return null;

    final metadata = <String, dynamic>{
      if (md.fileName != null && md.fileName!.isNotEmpty) 'fileName': md.fileName,
      if (md.fileSize != null) 'fileSize': md.fileSize,
      if (md.thumbnail != null && md.thumbnail!.isNotEmpty) 'thumbnail': md.thumbnail,
      if (md.thumbnailUrl != null && md.thumbnailUrl!.isNotEmpty) 'thumbnailUrl': md.thumbnailUrl,
      if (md.lat != null) 'lat': md.lat,
      if (md.lng != null) 'lng': md.lng,
      if (md.duration != null) 'duration': md.duration,
    };

    return metadata.isEmpty ? null : metadata;
  }

  void _forwardToConversation(ConversationModel conversation) {
    if (!mounted) return;

    final message = widget.message;
    final conversationId = conversation.id;
    final myId = authService.userId;
    if (message == null) return;
    if (myId == null || myId.isEmpty) return;
    if (_sendingConversationIds.contains(conversationId) ||
        _sentConversationIds.contains(conversationId)) {
      return;
    }

    setState(() => _sendingConversationIds.add(conversationId));

    final payload = <String, dynamic>{
      'conversationId': conversationId,
      'senderId': myId,
      'type': message.type,
      'content': message.content,
    };

    final metadata = _buildForwardMetadata(message);
    if (metadata != null) {
      payload['metadata'] = metadata;
    }

    try {
      socketService.sendMessage(payload);

      if (!mounted) return;
      setState(() {
        _sendingConversationIds.remove(conversationId);
        _sentConversationIds.add(conversationId);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sendingConversationIds.remove(conversationId);
      });
    }
  }

  Widget _buildForwardPreview() {
    final message = widget.message;
    if (message == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.error),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Không có dữ liệu tin nhắn để chuyển tiếp',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
        ),
      );
    }

    final title = switch (message.type) {
      'IMAGE' => 'Ảnh',
      'VIDEO' => 'Video',
      'FILE' => 'Tệp',
      'VOICE' => 'Tin nhắn thoại',
      'LOCATION' => 'Vị trí',
      _ => 'Tin nhắn',
    };

    final thumbUrl = message.metadata?.thumbnailUrl ?? message.metadata?.thumbnail;
    final canShowImage = (message.type == 'IMAGE' || message.type == 'VIDEO') &&
        ((message.type == 'IMAGE' && message.content.isNotEmpty) ||
            (thumbUrl != null && thumbUrl.isNotEmpty));
    final previewUrl = message.type == 'IMAGE' ? message.content : (thumbUrl ?? '');

    final subtitle = message.type == 'TEXT'
        ? (message.content.isNotEmpty ? message.content : 'Tin nhắn trống')
        : (message.metadata?.fileName?.isNotEmpty == true
              ? message.metadata!.fileName!
              : message.content);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canShowImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                webSafeImageUrl(previewUrl),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(Icons.broken_image_outlined, color: AppColors.textHint),
                ),
              ),
            )
          else
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                message.type == 'FILE'
                    ? Icons.insert_drive_file_outlined
                    : message.type == 'VOICE'
                        ? Icons.mic_none
                        : message.type == 'LOCATION'
                            ? Icons.location_on_outlined
                            : Icons.chat_bubble_outline,
                color: AppColors.primary,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Đang chuyển tiếp',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _loadError!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontFamily: 'Inter',
            ),
          ),
        ),
      );
    }

    if (_conversations.isEmpty) {
      return const Center(
        child: Text(
          'Không tìm thấy hội thoại nào',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontFamily: 'Inter',
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _conversations.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        color: AppColors.divider,
        indent: 76,
      ),
      itemBuilder: (_, index) {
        final conversation = _conversations[index];
        final conversationId = conversation.id;
        final isSending = _sendingConversationIds.contains(conversationId);
        final isSent = _sentConversationIds.contains(conversationId);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              AvatarWidget(
                url: _getAvatar(conversation),
                name: _getDisplayName(conversation),
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _getDisplayName(conversation),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 88,
                height: 36,
                child: ElevatedButton(
                  onPressed: isSending || isSent || widget.message == null
                      ? null
                      : () => _forwardToConversation(conversation),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor:
                        isSent ? AppColors.bgCardLight : AppColors.success,
                    foregroundColor:
                        isSent ? AppColors.textSecondary : Colors.white,
                    disabledBackgroundColor: isSending
                        ? AppColors.success.withOpacity(0.65)
                        : AppColors.bgCardLight,
                    disabledForegroundColor:
                        isSending ? Colors.white : AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    isSent
                        ? 'Đã gửi'
                        : isSending
                            ? 'Đang gửi'
                            : 'Gửi',
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text(
          'Chuyển tiếp',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontFamily: 'Inter',
          ),
        ),
        backgroundColor: AppColors.bgCard,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildForwardPreview(),
          Expanded(
            child: _buildConversationBody(),
          ),
        ],
      ),
    );
  }
}
