import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/entities/chat_message.dart';
import '../../utils/app_colors.dart';
import '../providers/mesh_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final PeerUiModel peer;

  const ChatScreen({super.key, required this.peer});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeChatPeerIdProvider.notifier).state = widget.peer.id;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeChatPeerIdProvider.notifier).state = null;
    });
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    ref.read(meshProvider.notifier).sendPacket(
          receiverId: widget.peer.id,
          payload: text,
        );
    _scrollToBottom();
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 40,
                          color: AppColors.getSubtext(context).withAlpha(120),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No messages yet',
                          style: GoogleFonts.inter(
                            color: AppColors.getText(context),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Say hello to ${currentPeer.name}!',
                          style: GoogleFonts.inter(
                            color: AppColors.getSubtext(context),
                            fontSize: 13,
                          ),
                        ),
                      ],
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
                      return _MessageBubble(message: msg, isMe: isMe);
                    },
                  ),
          ),
          _buildInputArea(currentPeer.isConnected, isDark),
        ],
      ),
    );
  }

  Widget _buildInputArea(bool isConnected, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.getCard(context),
        border: Border(
          top: BorderSide(color: AppColors.getBorder(context), width: 0.5),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.getBg(context),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.getBorder(context)),
                ),
                child: TextField(
                  controller: _textController,
                  style: GoogleFonts.inter(
                    color: AppColors.getText(context),
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: isConnected ? 'Type a message…' : 'Connecting to friend…',
                    hintStyle: GoogleFonts.inter(
                      color: AppColors.getSubtext(context),
                      fontSize: 14,
                    ),
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.getPrimary(context),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: _handleSend,
                icon: const Icon(Icons.send_rounded, size: 18),
                color: isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.all(10),
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
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

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
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
            Text(
              message.content,
              style: GoogleFonts.inter(
                color: textColor,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Row(
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
          ],
        ),
      ),
    );
  }
}
