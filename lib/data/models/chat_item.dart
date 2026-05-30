import 'models.dart';

enum ChatItemType { message, call, mediaGroup }

class ChatItem {
  final ChatItemType type;
  final MessageModel? message;
  final CallModel? call;
  final List<MessageModel>? mediaGroup;
  final DateTime createdAt;

   ChatItem.message(MessageModel msg)
      : type = ChatItemType.message,
        message = msg,
        call = null,
        mediaGroup = null,
        createdAt = msg.createdAt;

   ChatItem.call(CallModel c)
      : type = ChatItemType.call,
        message = null,
        call = c,
        mediaGroup = null,
        createdAt = c.createdAt;

   ChatItem.mediaGroup(List<MessageModel> group)
      : type = ChatItemType.mediaGroup,
        message = null,
        call = null,
        mediaGroup = group,
        createdAt = group.isNotEmpty ? group.first.createdAt : DateTime.now();
}