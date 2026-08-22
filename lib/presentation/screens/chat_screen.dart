import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/entities/chat_message.dart';
import '../../main.dart';
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

    return Scaffold(
      backgroundColor: MeshColors.background,
      appBar: AppBar(
        backgroundColor: MeshColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: MeshColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            // Peer avatar with status indicator
            Stack(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: MeshColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      currentPeer.name.isNotEmpty
                          ? currentPeer.name[0].toUpperCase()
                          : '?',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                // Connection dot
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: currentPeer.isConnected
                          ? MeshColors.success
                          : MeshColors.warning,
                      border: Border.all(
                        color: MeshColors.surface,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentPeer.name,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: MeshColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    currentPeer.isConnected
                        ? 'Connected via Wi-Fi Direct ${currentPeer.groupOwnerIp != null ? "(${currentPeer.groupOwnerIp})" : ""}'
                        : 'Status: ${currentPeer.wifiState.name}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: currentPeer.isConnected
                          ? MeshColors.success
                          : MeshColors.warning,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (currentPeer.isConnected || currentPeer.wifiState == PeerWifiState.connecting)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () {
                  ref.read(meshProvider.notifier).disconnectFromPeer(currentPeer.id);
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.link_off_rounded, size: 16, color: MeshColors.error),
                label: Text(
                  'Disconnect',
                  style: GoogleFonts.inter(
                    color: MeshColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: MeshColors.border),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: MeshColors.primary.withAlpha(10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 28,
                            color: MeshColors.primary.withAlpha(80),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: GoogleFonts.inter(
                            color: MeshColors.textTertiary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Send a message to ${currentPeer.name}',
                          style: GoogleFonts.inter(
                            color: MeshColors.textDisabled,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg.senderId == 'local';
                      return _MessageBubble(message: msg, isMe: isMe);
                    },
                  ),
          ),
          _buildInputArea(currentPeer.isConnected),
        ],
      ),
    );
  }

  Widget _buildInputArea(bool isConnected) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: MeshColors.surface,
        border: Border(
          top: BorderSide(color: MeshColors.border, width: 0.5),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: MeshColors.background,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: MeshColors.border),
                ),
                child: TextField(
                  controller: _textController,
                  style: GoogleFonts.inter(
                    color: MeshColors.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: isConnected
                        ? 'Type a message…'
                        : 'Connecting to peer…',
                    hintStyle: GoogleFonts.inter(
                      color: MeshColors.textDisabled,
                      fontSize: 14,
                    ),
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
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
                gradient: MeshColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: _handleSend,
                icon: const Icon(Icons.send_rounded, size: 18),
                color: Colors.white,
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
    final timeStr =
        '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          gradient: isMe ? MeshColors.primaryGradient : null,
          color: isMe ? null : MeshColors.surfaceElevated,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
          border: isMe
              ? null
              : Border.all(color: MeshColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.content,
              style: GoogleFonts.inter(
                color: isMe ? Colors.white : MeshColors.textPrimary,
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
                    color: isMe
                        ? Colors.white.withAlpha(150)
                        : MeshColors.textDisabled,
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
                        ? MeshColors.error
                        : Colors.white.withAlpha(150),
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
