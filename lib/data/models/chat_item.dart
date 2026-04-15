import 'models.dart';

enum ChatItemType { message, call }

class ChatItem {
  final ChatItemType type;
  final MessageModel? message;
  final CallModel? call;
  final DateTime createdAt;

   ChatItem.message(MessageModel msg)
      : type = ChatItemType.message,
        message = msg,
        call = null,
        createdAt = msg.createdAt;

   ChatItem.call(CallModel c)
      : type = ChatItemType.call,
        message = null,
        call = c,
        createdAt = c.createdAt;
}