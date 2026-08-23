import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../domain/entities/chat_message.dart';
import '../../utils/app_colors.dart';
import '../providers/mesh_provider.dart';
import '../providers/permission_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final PeerUiModel peer;

  const ChatScreen({super.key, required this.peer});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    ref.read(meshProvider.notifier).sendMessage(
          receiverId: widget.peer.id,
          content: text,
        );

    _textController.clear();
    _scrollToBottom();
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.getCard(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.getBorder(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _AttachmentOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    color: const Color(0xFF6C5CE7),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickAndSendImage(ImageSource.gallery);
                    },
                  ),
                  _AttachmentOption(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    color: const Color(0xFF00B894),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickAndSendImage(ImageSource.camera);
                    },
                  ),
                  _AttachmentOption(
                    icon: Icons.videocam_rounded,
                    label: 'Video',
                    color: const Color(0xFFFF7675),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickAndSendVideo();
                    },
                  ),
                  _AttachmentOption(
                    icon: Icons.insert_drive_file_rounded,
                    label: 'Document',
                    color: const Color(0xFF0984E3),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickAndSendDocument();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (picked != null) {
        final file = File(picked.path);
        await ref.read(meshProvider.notifier).sendFile(
              receiverId: widget.peer.id,
              file: file,
              type: MessageType.image,
            );
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error picking media: $e');
    }
  }

  Future<void> _pickAndSendVideo() async {
    try {
      final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (picked != null) {
        final file = File(picked.path);
        await ref.read(meshProvider.notifier).sendFile(
              receiverId: widget.peer.id,
              file: file,
              type: MessageType.video,
            );
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error picking video: $e');
    }
  }

  Future<void> _pickAndSendDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        await ref.read(meshProvider.notifier).sendFile(
              receiverId: widget.peer.id,
              file: file,
              type: MessageType.file,
            );
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error picking document: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final meshState = ref.watch(meshProvider);
    final normPeerId = normalizeId(widget.peer.id);
    final currentPeer = meshState.peers.firstWhere(
      (p) => p.id == widget.peer.id || normalizeId(p.id) == normPeerId,
      orElse: () => meshState.savedPeers.firstWhere(
        (sp) => sp.id == widget.peer.id || normalizeId(sp.id) == normPeerId,
        orElse: () => widget.peer,
      ),
    );

    final cleanPeerId = normalizeId(currentPeer.id);

    ref.listen(conversationMessagesStreamProvider(cleanPeerId), (previous, next) {
      if (next.hasValue) {
        _scrollToBottom();
      }
    });

    final isarMessagesAsync = ref.watch(conversationMessagesStreamProvider(cleanPeerId));
    final isarMessages = isarMessagesAsync.value ?? [];

    final Map<String, ChatMessage> messageMap = {};
    for (final m in isarMessages) {
      messageMap[m.id] = m;
    }
    for (final m in meshState.chatMessages) {
      final normSender = normalizeId(m.senderId);
      final normReceiver = normalizeId(m.receiverId);
      if ((m.senderId == 'local' && (m.receiverId == currentPeer.id || normReceiver == cleanPeerId)) ||
          (m.senderId == currentPeer.id || normSender == cleanPeerId)) {
        messageMap[m.id] = m;
      }
    }

    final messages = messageMap.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final isDark = AppColors.isDark(context);

    return Scaffold(
      backgroundColor: AppColors.getBg(context),
      appBar: AppBar(
        backgroundColor: AppColors.getCard(context),
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.getText(context),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: currentPeer.isConnected
                    ? AppColors.success
                    : AppColors.getSubtext(context).withAlpha(140),
                boxShadow: currentPeer.isConnected
                    ? [
                        BoxShadow(
                          color: AppColors.success.withAlpha(140),
                          blurRadius: 6,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentPeer.name,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.getText(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    currentPeer.isConnected ? 'Direct Offline Link' : 'Offline',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: currentPeer.isConnected
                          ? AppColors.success
                          : AppColors.getSubtext(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (currentPeer.isConnected)
            IconButton(
              icon: const Icon(Icons.link_off_rounded, color: AppColors.error, size: 20),
              onPressed: () {
                ref.read(meshProvider.notifier).disconnectFromPeer(currentPeer.id);
              },
              tooltip: 'Disconnect',
            )
          else if (currentPeer.wifiState == PeerWifiState.connecting)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.getPrimary(context),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.getPrimary(context),
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  await ref.read(permissionProvider.notifier).ensureRadiosAndPermissionsReady();
                  ref.read(meshProvider.notifier).connectToPeer(currentPeer.id, peerName: currentPeer.name);
                },
                icon: const Icon(Icons.link_rounded, size: 16),
                label: Text('Connect', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(
            height: 0.5,
            color: AppColors.getBorder(context),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet.\nSay hello!',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: AppColors.getSubtext(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg.senderId == 'local';
                      return _MessageBubble(
                        message: msg,
                        isMe: isMe,
                      );
                    },
                  ),
          ),

          // Message Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.getCard(context),
              border: Border(
                top: BorderSide(color: AppColors.getBorder(context), width: 0.5),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.add_circle_outline_rounded,
                      color: AppColors.getPrimary(context),
                      size: 24,
                    ),
                    onPressed: _showAttachmentSheet,
                    tooltip: 'Send Media',
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.getBg(context),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.getBorder(context), width: 0.8),
                      ),
                      child: TextField(
                        controller: _textController,
                        style: GoogleFonts.inter(
                          color: AppColors.getText(context),
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Type a message…',
                          hintStyle: GoogleFonts.inter(
                            color: AppColors.getSubtext(context),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.getPrimary(context),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.send_rounded,
                        color: isDark ? Colors.black : Colors.white,
                        size: 18,
                      ),
                      onPressed: _sendMessage,
                      tooltip: 'Send',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                shape: BoxShape.circle,
                border: Border.all(color: color.withAlpha(60)),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.getText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  final ChatMessage message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.getCard(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.getBorder(context)),
        ),
        title: Text(
          'Delete Message',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: AppColors.getText(context),
            fontSize: 16,
          ),
        ),
        content: Text(
          'Do you want to delete this message?',
          style: GoogleFonts.inter(
            color: AppColors.getSubtext(context),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                color: AppColors.getSubtext(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(meshProvider.notifier).deleteMessage(message.id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message deleted'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: Text(
              'Delete',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveToDownloads(BuildContext context, WidgetRef ref, String localPath, String fileName) async {
    final platformDs = ref.read(platformDataSourceProvider);
    final savedPath = await platformDs.saveFileToDownloads(localPath, fileName);
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.getCard(context),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.getBorder(context)),
          ),
          content: Row(
            children: [
              Icon(
                savedPath != null ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                color: savedPath != null ? AppColors.success : AppColors.error,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  savedPath != null ? 'Saved to Downloads/MeshLink/' : 'Failed to save file',
                  style: GoogleFonts.inter(
                    color: AppColors.getText(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _openImageViewer(BuildContext context, WidgetRef ref, String path, String fileName) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isMe)
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: Colors.white, size: 26),
                    onPressed: () => _saveToDownloads(context, ref, path, fileName),
                    tooltip: 'Save to Downloads',
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openInAppVideoPlayer(BuildContext context, WidgetRef ref, String path, String fileName) {
    showDialog(
      context: context,
      builder: (_) => _MeshVideoPlayerDialog(
        videoPath: path,
        fileName: fileName,
        showDownload: !isMe,
        onDownload: () => _saveToDownloads(context, ref, path, fileName),
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) return Icons.folder_zip_rounded;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.description_rounded;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return Icons.table_chart_rounded;
    if (lower.endsWith('.apk')) return Icons.android_rounded;
    if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.m4a')) return Icons.audio_file_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileIconColor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return const Color(0xFFFF4757);
    if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) return const Color(0xFFFFA502);
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return const Color(0xFF2ED573);
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return const Color(0xFF1E90FF);
    if (lower.endsWith('.apk')) return const Color(0xFF2ED573);
    return const Color(0xFF70A1FF);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = AppColors.isDark(context);
    final timeStr =
        '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';

    final Color bubbleColor = isMe
        ? (isDark ? AppColors.primaryDarkSurface : AppColors.primaryLight)
        : (isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceLight);

    final Color textColor = isMe
        ? (isDark ? const Color(0xFFE6FBF5) : Colors.white)
        : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight);

    final Color timeColor = isMe
        ? (isDark ? const Color(0xFF8CEFD8) : Colors.white.withAlpha(180))
        : (isDark ? AppColors.textTertiaryDark : AppColors.textSecondaryLight);

    final Border? bubbleBorder = isMe
        ? (isDark ? Border.all(color: AppColors.primaryDark.withAlpha(60), width: 0.8) : null)
        : Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
            width: 0.8,
          );

    final isMedia = message.messageType != MessageType.text;
    final isImage = message.messageType == MessageType.image;
    final isVideo = message.messageType == MessageType.video;
    final hasLocalFile = message.localFilePath != null && File(message.localFilePath!).existsSync();
    final fileName = message.fileName ?? (isImage ? 'image.jpg' : (isVideo ? 'video.mp4' : 'document.pdf'));

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showDeleteDialog(context, ref),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: isMedia
              ? const EdgeInsets.all(6)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
            border: bubbleBorder,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
            if (isMedia) ...[
              if (isImage && hasLocalFile)
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    GestureDetector(
                      onTap: () => _openImageViewer(context, ref, message.localFilePath!, fileName),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(message.localFilePath!),
                          width: 220,
                          height: 180,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    if (!isMe)
                      Container(
                        margin: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(160),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          padding: EdgeInsets.zero,
                          onPressed: () => _saveToDownloads(context, ref, message.localFilePath!, fileName),
                          tooltip: 'Save to Downloads',
                        ),
                      ),
                  ],
                )
              else if (isVideo && hasLocalFile)
                GestureDetector(
                  onTap: () => _openInAppVideoPlayer(context, ref, message.localFilePath!, fileName),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _VideoThumbnailWidget(
                        videoPath: message.localFilePath!,
                        width: 220,
                        height: 140,
                      ),
                      if (!isMe)
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(160),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              padding: EdgeInsets.zero,
                              onPressed: () => _saveToDownloads(context, ref, message.localFilePath!, fileName),
                              tooltip: 'Save to Downloads',
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              else
                // Document / Generic file card
                GestureDetector(
                  onTap: hasLocalFile
                      ? () => ref.read(platformDataSourceProvider).openFile(message.localFilePath!)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.black : Colors.white).withAlpha(40),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _getFileIconColor(fileName).withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _getFileIcon(fileName),
                            color: _getFileIconColor(fileName),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fileName,
                                style: GoogleFonts.inter(
                                  color: textColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (message.fileSize != null)
                                Text(
                                  '${(message.fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB',
                                  style: GoogleFonts.inter(
                                    color: timeColor,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (!isMe && hasLocalFile)
                          IconButton(
                            icon: Icon(Icons.download_rounded, color: textColor, size: 20),
                            onPressed: () => _saveToDownloads(context, ref, message.localFilePath!, fileName),
                            tooltip: 'Save to Downloads',
                          ),
                      ],
                    ),
                  ),
                ),

              // Progress bar during transfer or Cancelled status
              if (message.status == MessageStatus.failed) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cancel_outlined, color: AppColors.error, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        'Transfer cancelled',
                        style: GoogleFonts.inter(
                          color: AppColors.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (message.progress < 1.0 && message.status == MessageStatus.sending) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: message.progress,
                        backgroundColor: (isDark ? Colors.black : Colors.white).withAlpha(50),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isMe ? (isDark ? AppColors.primaryDark : Colors.white) : AppColors.getPrimary(context),
                        ),
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${(message.progress * 100).toInt()}% • Transferring…',
                            style: GoogleFonts.inter(color: timeColor, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                          GestureDetector(
                            onTap: () {
                              final targetId = isMe ? message.receiverId : message.senderId;
                              ref.read(meshProvider.notifier).cancelFileTransfer(message.id, receiverId: targetId);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withAlpha(40),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.redAccent.withAlpha(100), width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.close_rounded, color: Colors.redAccent, size: 12),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Cancel',
                                    style: GoogleFonts.inter(
                                      color: Colors.redAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ] else ...[
              Text(
                message.content,
                style: GoogleFonts.inter(
                  color: textColor,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeStr,
                    style: GoogleFonts.inter(
                      color: timeColor,
                      fontSize: 10,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.status == MessageStatus.sending
                          ? Icons.access_time_rounded
                          : message.status == MessageStatus.sent ||
                                  message.status == MessageStatus.delivered
                              ? Icons.check_rounded
                              : Icons.error_outline_rounded,
                      size: 12,
                      color: message.status == MessageStatus.failed
                          ? AppColors.error
                          : timeColor,
                    ),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

// ── Video Thumbnail Widget ──────────────────────────────────────────────────

class _VideoThumbnailWidget extends ConsumerStatefulWidget {
  final String videoPath;
  final double width;
  final double height;

  const _VideoThumbnailWidget({
    required this.videoPath,
    required this.width,
    required this.height,
  });

  @override
  ConsumerState<_VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends ConsumerState<_VideoThumbnailWidget> {
  String? _thumbPath;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final ds = ref.read(platformDataSourceProvider);
    final path = await ds.createVideoThumbnail(widget.videoPath);
    if (mounted) {
      setState(() {
        _thumbPath = path;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: widget.width,
        height: widget.height,
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_thumbPath != null && File(_thumbPath!).existsSync())
              Image.file(
                File(_thumbPath!),
                width: widget.width,
                height: widget.height,
                fit: BoxFit.cover,
              )
            else if (_loading)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                  ),
                ),
              )
            else
              Container(
                color: Colors.black87,
              ),

            // Play overlay button
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.getPrimary(context).withAlpha(220),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(100),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: isDark ? Colors.black : Colors.white,
                size: 30,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── In-App Video Player Dialog ──────────────────────────────────────────────

class _MeshVideoPlayerDialog extends ConsumerStatefulWidget {
  final String videoPath;
  final String fileName;
  final bool showDownload;
  final VoidCallback onDownload;

  const _MeshVideoPlayerDialog({
    required this.videoPath,
    required this.fileName,
    required this.showDownload,
    required this.onDownload,
  });

  @override
  ConsumerState<_MeshVideoPlayerDialog> createState() => _MeshVideoPlayerDialogState();
}

class _MeshVideoPlayerDialogState extends ConsumerState<_MeshVideoPlayerDialog> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        setState(() {
          _errorMessage = "Video file not found on disk";
        });
        return;
      }
      _controller = VideoPlayerController.file(file);
      await _controller.initialize();
      _controller.addListener(() {
        if (mounted) setState(() {});
      });
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _controller.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Unable to play video: $e";
        });
      }
    }
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _controller.dispose();
    }
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.black,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: Colors.black87,
                child: Row(
                  children: [
                    const Icon(Icons.videocam_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.fileName,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.showDownload)
                      IconButton(
                        icon: const Icon(Icons.download_rounded, color: Colors.white, size: 22),
                        onPressed: widget.onDownload,
                        tooltip: 'Save to Downloads',
                      ),
                    IconButton(
                      icon: const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 20),
                      onPressed: () {
                        Navigator.pop(context);
                        ref.read(platformDataSourceProvider).openFile(widget.videoPath);
                      },
                      tooltip: 'Open with App',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Video Area
              GestureDetector(
                onTap: () => setState(() => _showControls = !_showControls),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: _errorMessage != null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.movie_creation_outlined, color: Color(0xFF00D4A8), size: 48),
                              const SizedBox(height: 12),
                              Text(
                                'High-Resolution Video (HEVC / 4K)',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'This video format uses high-bitrate device hardware encoding. Tap below to play with your installed video player (VLC, Photos, MX Player, Mi Video).',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00D4A8),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  ref.read(platformDataSourceProvider).openFile(widget.videoPath);
                                },
                                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                                label: Text(
                                  'Play with App',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        )
                      : _isInitialized
                          ? AspectRatio(
                              aspectRatio: _controller.value.aspectRatio,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  VideoPlayer(_controller),
                                  if (_showControls)
                                    Container(
                                      color: Colors.black38,
                                      child: Center(
                                        child: IconButton(
                                          iconSize: 56,
                                          icon: Icon(
                                            _controller.value.isPlaying
                                                ? Icons.pause_circle_filled_rounded
                                                : Icons.play_circle_fill_rounded,
                                            color: Colors.white,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _controller.value.isPlaying
                                                  ? _controller.pause()
                                                  : _controller.play();
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : const Padding(
                              padding: EdgeInsets.all(48),
                              child: Center(
                                child: CircularProgressIndicator(color: Colors.white),
                              ),
                            ),
                ),
              ),

              // Bottom Playback Slider & Timers
              if (_isInitialized)
                ValueListenableBuilder(
                  valueListenable: _controller,
                  builder: (context, VideoPlayerValue val, _) {
                    final pos = val.position;
                    final dur = val.duration;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      color: Colors.black87,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: Color(0xFF00D4A8),
                              bufferedColor: Colors.white24,
                              backgroundColor: Colors.white10,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(pos),
                                style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                              ),
                              Text(
                                _formatDuration(dur),
                                style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
