enum MessageStatus { sending, sent, delivered, failed }

enum MessageType { text, image, video, file }

class ChatMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final DateTime timestamp;
  final MessageStatus status;
  final MessageType messageType;
  final String? localFilePath;
  final String? fileName;
  final int? fileSize;
  final double progress; // 0.0 to 1.0

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.timestamp,
    required this.status,
    this.messageType = MessageType.text,
    this.localFilePath,
    this.fileName,
    this.fileSize,
    this.progress = 1.0,
  });

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? content,
    DateTime? timestamp,
    MessageStatus? status,
    MessageType? messageType,
    String? localFilePath,
    String? fileName,
    int? fileSize,
    double? progress,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      messageType: messageType ?? this.messageType,
      localFilePath: localFilePath ?? this.localFilePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      progress: progress ?? this.progress,
    );
  }
}
