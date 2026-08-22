import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/entities/chat_message.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_theme.dart';
import '../providers/mesh_provider.dart';
import '../providers/permission_provider.dart';
import '../providers/user_profile_provider.dart';
import 'chat_screen.dart';
import 'qr_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  ChatMessage? _incomingBannerMessage;
  PeerUiModel? _incomingBannerPeer;
  Timer? _bannerTimer;

  // Settings tab controller
  final TextEditingController _nameController = TextEditingController();
  bool _isEditingName = false;

  void _showIncomingMessageBanner(ChatMessage msg, PeerUiModel peer) {
    _bannerTimer?.cancel();
    setState(() {
      _incomingBannerMessage = msg;
      _incomingBannerPeer = peer;
    });
    _bannerTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _incomingBannerMessage = null;
          _incomingBannerPeer = null;
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref.read(permissionProvider.notifier).checkBluetoothState();
      ref.read(permissionProvider.notifier).checkWifiState();
      ref.read(permissionProvider.notifier).checkLocationServiceState();
      _nameController.text = ref.read(userProfileProvider).displayName;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bannerTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(permissionProvider.notifier).checkBluetoothState();
      ref.read(permissionProvider.notifier).checkWifiState();
      ref.read(permissionProvider.notifier).checkLocationServiceState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final meshState = ref.watch(meshProvider);
    final isDark = AppColors.isDark(context);

    // Listen for errors
    ref.listen<List<String>>(
      meshProvider.select((s) => s.errorLog),
      (previous, next) {
        if (next.isNotEmpty && (previous == null || next.length > previous.length)) {
          final rawError = next.last;
          final hasConnectedPeers = meshState.peers.any((p) => p.isConnected);
          final lower = rawError.toLowerCase();
          if (lower.contains('eaddrinuse') ||
              lower.contains('bind') ||
              (hasConnectedPeers &&
                  (lower.contains('connection') ||
                      lower.contains('connect') ||
                      lower.contains('failed')))) {
            return;
          }

          final friendlyMsg = _formatFriendlyError(rawError);
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
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      friendlyMsg,
                      style: GoogleFonts.inter(
                        color: AppColors.getText(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      },
    );

    // Listen for incoming messages
    ref.listen(meshProvider.select((s) => s.chatMessages), (prev, next) {
      if (next.isNotEmpty && (prev == null || next.length > prev.length)) {
        final lastMsg = next.last;
        if (lastMsg.senderId != 'local' && lastMsg.senderId.isNotEmpty) {
          final senderPeer = meshState.peers.firstWhere(
            (p) => p.id == lastMsg.senderId || normalizeId(p.id) == normalizeId(lastMsg.senderId),
            orElse: () => meshState.savedPeers.firstWhere(
              (sp) => sp.id == lastMsg.senderId || normalizeId(sp.id) == normalizeId(lastMsg.senderId),
              orElse: () => PeerUiModel(
                id: lastMsg.senderId,
                name: 'Friend ${normalizeId(lastMsg.senderId)}',
                rssi: -60,
                connectionType: 'Direct',
              ),
            ),
          );

          _showIncomingMessageBanner(lastMsg, senderPeer);
        }
      }
    });

    return Scaffold(
      backgroundColor: AppColors.getBg(context),
      appBar: AppBar(
        backgroundColor: AppColors.getCard(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'MeshLink',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.getText(context),
            letterSpacing: -0.3,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(
            height: 0.5,
            color: AppColors.getBorder(context),
          ),
        ),
      ),
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              // Tab 0: Chats
              _ChatsTab(
                meshState: meshState,
                onSelectPeer: (peer) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(peer: peer),
                    ),
                  );
                },
                onDeleteChat: (peer) => _showDeleteChatDialog(context, ref, peer),
                onGoToExplore: () => setState(() => _currentIndex = 1),
              ),

              // Tab 1: Explore
              _ExploreTab(
                meshState: meshState,
                onConnect: (peerId) async {
                  await ref.read(permissionProvider.notifier).ensureRadiosAndPermissionsReady();
                  ref.read(meshProvider.notifier).connectToPeer(peerId);
                },
                onDisconnect: (peerId) {
                  ref.read(meshProvider.notifier).disconnectFromPeer(peerId);
                },
                onChat: (peer) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(peer: peer),
                    ),
                  );
                },
              ),

              // Tab 2: Settings
              _SettingsTab(
                nameController: _nameController,
                isEditingName: _isEditingName,
                onToggleEditName: (isEditing) {
                  setState(() => _isEditingName = isEditing);
                },
              ),
            ],
          ),

          // Floating in-app message banner
          if (_incomingBannerMessage != null && _incomingBannerPeer != null)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: _IncomingMessageBanner(
                message: _incomingBannerMessage!,
                peer: _incomingBannerPeer!,
                onReply: () {
                  final target = _incomingBannerPeer!;
                  setState(() {
                    _incomingBannerMessage = null;
                    _incomingBannerPeer = null;
                  });
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(peer: target),
                    ),
                  );
                },
                onDismiss: () {
                  setState(() {
                    _incomingBannerMessage = null;
                    _incomingBannerPeer = null;
                  });
                },
              ),
            ),
        ],
      ),
      floatingActionButton: _currentIndex == 1
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QrScreen()),
                );
              },
              backgroundColor: AppColors.getPrimary(context),
              foregroundColor: isDark ? Colors.black : Colors.white,
              elevation: 3,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
              label: Text(
                'Scan / QR',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.getCard(context),
          border: Border(
            top: BorderSide(color: AppColors.getBorder(context), width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.getPrimary(context),
          unselectedItemColor: AppColors.getSubtext(context),
          selectedLabelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              activeIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore_rounded),
              label: 'Explore',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tab 0: Chats (WhatsApp style) ───────────────────────────────────────────

class _ChatsTab extends StatelessWidget {
  final MeshUiState meshState;
  final ValueChanged<PeerUiModel> onSelectPeer;
  final ValueChanged<PeerUiModel> onDeleteChat;
  final VoidCallback onGoToExplore;

  const _ChatsTab({
    required this.meshState,
    required this.onSelectPeer,
    required this.onDeleteChat,
    required this.onGoToExplore,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, PeerUiModel> peersMap = {};
    for (final peer in meshState.savedPeers) {
      peersMap[normalizeId(peer.id)] = peer;
    }
    for (final peer in meshState.peers) {
      peersMap[normalizeId(peer.id)] = peer;
    }

    final chatList = peersMap.values.toList();

    if (chatList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.getPrimary(context).withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 28,
                  color: AppColors.getPrimary(context),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No conversations yet',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.getText(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Find nearby friends in the Explore tab or scan a QR code to start chatting offline.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.getSubtext(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onGoToExplore,
                icon: const Icon(Icons.explore_rounded, size: 18),
                label: const Text('Go to Explore'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: chatList.length,
      separatorBuilder: (ctx, i) => Divider(
        height: 1,
        color: AppColors.getBorder(context),
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, index) {
        final friend = chatList[index];
        final normId = normalizeId(friend.id);

        final livePeer = meshState.peers.firstWhere(
          (p) => p.id == friend.id || normalizeId(p.id) == normId,
          orElse: () => friend,
        );

        final isConnected = friend.isConnected || livePeer.isConnected;
        final isConnecting = friend.wifiState == PeerWifiState.connecting || livePeer.wifiState == PeerWifiState.connecting;

        final msgs = meshState.chatMessages
            .where((m) =>
                m.senderId == friend.id ||
                normalizeId(m.senderId) == normId ||
                (m.senderId == 'local' &&
                    meshState.chatMessages.any((sub) =>
                        sub.senderId == friend.id ||
                        normalizeId(sub.senderId) == normId)))
            .toList();

        final lastMsg = msgs.isNotEmpty ? msgs.last : null;
        final lastMsgText = lastMsg != null
            ? (lastMsg.messageType == MessageType.image
                ? '📷 Photo'
                : (lastMsg.messageType == MessageType.video
                    ? '🎥 Video'
                    : (lastMsg.senderId == 'local' ? 'You: ${lastMsg.content}' : lastMsg.content)))
            : (isConnected ? 'Direct link ready' : 'Tap to open chat');

        final timeStr = lastMsg != null
            ? '${lastMsg.timestamp.hour.toString().padLeft(2, '0')}:${lastMsg.timestamp.minute.toString().padLeft(2, '0')}'
            : '';

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          onTap: () => onSelectPeer(livePeer),
          onLongPress: () => onDeleteChat(friend),
          title: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected
                      ? AppColors.success
                      : isConnecting
                          ? AppColors.warning
                          : AppColors.getSubtext(context).withAlpha(120),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  friend.name,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.getText(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (timeStr.isNotEmpty)
                Text(
                  timeStr,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.getSubtext(context),
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(left: 18, top: 4),
            child: Text(
              lastMsgText,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isConnected
                    ? AppColors.getText(context).withAlpha(180)
                    : AppColors.getSubtext(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }
}

// ── Tab 1: Explore (Searching & Connecting) ─────────────────────────────────

class _ExploreTab extends ConsumerWidget {
  final MeshUiState meshState;
  final ValueChanged<String> onConnect;
  final ValueChanged<String> onDisconnect;
  final ValueChanged<PeerUiModel> onChat;

  const _ExploreTab({
    required this.meshState,
    required this.onConnect,
    required this.onDisconnect,
    required this.onChat,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permState = ref.watch(permissionProvider);
    final isDark = AppColors.isDark(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusBanner(message: meshState.statusMessage),
        const SizedBox(height: 16),

        // Radio & Permission Warning Banners
        if (!permState.allGranted)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warning.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withAlpha(80)),
            ),
            child: Row(
              children: [
                const Icon(Icons.security_rounded, color: AppColors.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Permissions required for offline mesh',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.getText(context)),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.read(permissionProvider.notifier).checkAndRequestPermissions(),
                  child: Text('Grant', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppColors.warning)),
                ),
              ],
            ),
          ),

        if (!permState.isBluetoothEnabled)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.error.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withAlpha(80)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bluetooth_disabled_rounded, color: AppColors.error, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Bluetooth is turned OFF',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.getText(context)),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => ref.read(permissionProvider.notifier).requestEnableBluetooth(),
                  child: Text('Turn On', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ),
          ),

        if (!permState.isWifiEnabled)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warning.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withAlpha(80)),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi_off_rounded, color: AppColors.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Wi-Fi is turned OFF',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.getText(context)),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => ref.read(permissionProvider.notifier).requestEnableWifi(),
                  child: Text('Turn On', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ),
          ),

        if (!permState.isLocationServiceEnabled)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warning.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withAlpha(80)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_off_rounded, color: AppColors.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Location service is turned OFF',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.getText(context)),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => ref.read(permissionProvider.notifier).requestEnableLocationService(),
                  child: Text('Turn On', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ),
          ),

        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.getCard(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.getBorder(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Find Friends Nearby',
                style: GoogleFonts.inter(
                  color: AppColors.getText(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Discover and connect with friends offline using Bluetooth & Wi-Fi Direct.',
                style: GoogleFonts.inter(
                  color: AppColors.getSubtext(context),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: meshState.isDiscovering
                        ? AppColors.error
                        : AppColors.getPrimary(context),
                    foregroundColor: meshState.isDiscovering
                        ? Colors.white
                        : (isDark ? Colors.black : Colors.white),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    if (meshState.isDiscovering) {
                      ref.read(meshProvider.notifier).stopDiscovery();
                    } else {
                      await ref.read(permissionProvider.notifier).ensureRadiosAndPermissionsReady();
                      ref.read(meshProvider.notifier).startDiscovery();
                    }
                  },
                  icon: Icon(
                    meshState.isDiscovering ? Icons.stop_rounded : Icons.search_rounded,
                    size: 20,
                  ),
                  label: Text(
                    meshState.isDiscovering ? 'Stop Searching' : 'Find Friends Nearby',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Saved Friends Section ──────────────────────────────────────────
        if (meshState.savedPeers.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Saved Friends',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.getText(context),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.getPrimary(context).withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${meshState.savedPeers.length}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.getPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppColors.getCard(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.getBorder(context)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: meshState.savedPeers.length,
              separatorBuilder: (ctx, i) => Divider(
                height: 1,
                color: AppColors.getBorder(context),
              ),
              itemBuilder: (context, index) {
                final savedFriend = meshState.savedPeers[index];
                final norm = normalizeId(savedFriend.id);
                final livePeer = meshState.peers.firstWhere(
                  (p) => p.id == savedFriend.id || normalizeId(p.id) == norm,
                  orElse: () => savedFriend,
                );
                final isConnected = livePeer.isConnected;
                final isConnecting = livePeer.wifiState == PeerWifiState.connecting;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  onLongPress: () => _showForgetFriendDialog(context, ref, savedFriend),
                  title: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConnected
                              ? AppColors.success
                              : isConnecting
                                  ? AppColors.warning
                                  : AppColors.getSubtext(context).withAlpha(120),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          savedFriend.name,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.getText(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  trailing: isConnected
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.getPrimary(context),
                                foregroundColor: isDark ? Colors.black : Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => onChat(livePeer),
                              child: Text('Chat', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(Icons.link_off_rounded, color: AppColors.error, size: 20),
                              onPressed: () => onDisconnect(savedFriend.id),
                              tooltip: 'Disconnect',
                            ),
                          ],
                        )
                      : isConnecting
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withAlpha(20),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.warning),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Connecting',
                                    style: GoogleFonts.inter(
                                      color: AppColors.warning,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.getPrimary(context),
                                    side: BorderSide(color: AppColors.getPrimary(context)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => onConnect(savedFriend.id),
                                  child: Text('Connect', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: Icon(
                                    Icons.person_remove_outlined,
                                    color: AppColors.getSubtext(context),
                                    size: 18,
                                  ),
                                  onPressed: () => _showForgetFriendDialog(context, ref, savedFriend),
                                  tooltip: 'Forget Friend',
                                ),
                              ],
                            ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],

        // ── Nearby Friends Section ─────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Nearby Friends',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.getText(context),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.getPrimary(context).withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${meshState.peers.length}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.getPrimary(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (meshState.peers.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.getCard(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.getBorder(context)),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    meshState.isDiscovering
                        ? Icons.search_rounded
                        : Icons.people_outline_rounded,
                    size: 32,
                    color: AppColors.getSubtext(context),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    meshState.isDiscovering
                        ? 'Searching for nearby friends…'
                        : 'Tap "Find Friends Nearby" to discover devices',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.getSubtext(context),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.getCard(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.getBorder(context)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: meshState.peers.length,
              separatorBuilder: (ctx, i) => Divider(
                height: 1,
                color: AppColors.getBorder(context),
              ),
              itemBuilder: (context, index) {
                final peer = meshState.peers[index];
                final isConnected = peer.isConnected;
                final isConnecting = peer.wifiState == PeerWifiState.connecting;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConnected
                              ? AppColors.success
                              : isConnecting
                                  ? AppColors.warning
                                  : AppColors.getPrimary(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          peer.name,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.getText(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  trailing: isConnected
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.getPrimary(context),
                                foregroundColor: isDark ? Colors.black : Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => onChat(peer),
                              child: Text('Chat', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(Icons.link_off_rounded, color: AppColors.error, size: 20),
                              onPressed: () => onDisconnect(peer.id),
                              tooltip: 'Disconnect',
                            ),
                          ],
                        )
                      : isConnecting
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withAlpha(20),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.warning),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Connecting',
                                    style: GoogleFonts.inter(
                                      color: AppColors.warning,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.getPrimary(context),
                                side: BorderSide(color: AppColors.getPrimary(context)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => onConnect(peer.id),
                              child: Text('Connect', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// ── Tab 2: Settings ─────────────────────────────────────────────────────────

class _SettingsTab extends ConsumerWidget {
  final TextEditingController nameController;
  final bool isEditingName;
  final ValueChanged<bool> onToggleEditName;

  const _SettingsTab({
    required this.nameController,
    required this.isEditingName,
    required this.onToggleEditName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentThemeMode = ref.watch(themeModeProvider);
    final userProfile = ref.watch(userProfileProvider);
    final isDark = AppColors.isDark(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.getCard(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.getBorder(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Display Name',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.getText(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'How you appear to nearby friends over offline mesh.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.getSubtext(context),
                ),
              ),
              const SizedBox(height: 14),
              if (isEditingName) ...[
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: GoogleFonts.inter(
                    color: AppColors.getText(context),
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter your name',
                    filled: true,
                    fillColor: AppColors.getBg(context),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.getBorder(context)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        nameController.text = userProfile.displayName;
                        onToggleEditName(false);
                      },
                      child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.getSubtext(context))),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.getPrimary(context),
                        foregroundColor: isDark ? Colors.black : Colors.white,
                      ),
                      onPressed: () {
                        final newName = nameController.text.trim();
                        if (newName.isNotEmpty) {
                          ref.read(userProfileProvider.notifier).updateProfile(displayName: newName);
                        }
                        onToggleEditName(false);
                      },
                      child: Text('Save', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      userProfile.displayName,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.getText(context),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.edit_outlined, color: AppColors.getPrimary(context), size: 20),
                      onPressed: () {
                        nameController.text = userProfile.displayName;
                        onToggleEditName(true);
                      },
                      tooltip: 'Change Name',
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.getCard(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.getBorder(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Appearance',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.getText(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose Light or Dark theme.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.getSubtext(context),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        currentThemeMode == ThemeMode.dark
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        color: AppColors.getPrimary(context),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        currentThemeMode == ThemeMode.dark ? 'Dark Mode' : 'Light Mode',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.getText(context),
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: currentThemeMode == ThemeMode.dark,
                    activeThumbColor: AppColors.getPrimary(context),
                    onChanged: (isDarkSelected) {
                      ref.read(themeModeProvider.notifier).state =
                          isDarkSelected ? ThemeMode.dark : ThemeMode.light;
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.getCard(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.getBorder(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'About MeshLink',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.getText(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'MeshLink provides completely offline, off-grid peer-to-peer messaging using Wi-Fi Direct and Bluetooth Low Energy. No internet, cell tower, or central server required.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.getSubtext(context),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Top Connection Status Banner ───────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final String message;
  const _StatusBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final lower = message.toLowerCase();
    final isSearching = lower.contains('scanning') || lower.contains('discovering') || lower.contains('searching') || lower.contains('looking');
    final isConnecting = lower.contains('connecting');
    final isConnected = lower.contains('connected') && !lower.contains('disconnected');

    final (statusLabel, statusColor, subtext) = isConnected
        ? ('Connected', AppColors.primaryDark, 'Offline mesh link active • Real-time chat ready')
        : isConnecting
            ? ('Connecting…', AppColors.warning, 'Accept connection prompt if prompted')
            : isSearching
                ? ('Searching', AppColors.accentDark, 'Searching for nearby friends with MeshLink…')
                : ('Ready', AppColors.getSubtext(context), 'Find friends nearby or use QR code to chat offline');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: statusColor.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withAlpha(40),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
              boxShadow: isConnected || isSearching
                  ? [
                      BoxShadow(
                        color: statusColor.withAlpha(140),
                        blurRadius: 6,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusLabel,
            style: GoogleFonts.inter(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.getSubtext(context),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtext,
              style: GoogleFonts.inter(
                color: AppColors.getSubtext(context),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── In-App Message Notification Banner ──────────────────────────────────────

class _IncomingMessageBanner extends StatelessWidget {
  final ChatMessage message;
  final PeerUiModel peer;
  final VoidCallback onReply;
  final VoidCallback onDismiss;

  const _IncomingMessageBanner({
    required this.message,
    required this.peer,
    required this.onReply,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = peer.name.isNotEmpty ? peer.name : 'Friend ${normalizeId(peer.id)}';
    final isDark = AppColors.isDark(context);

    return Dismissible(
      key: ValueKey('banner_${message.id}'),
      direction: DismissDirection.up,
      onDismissed: (_) => onDismiss(),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.getCard(context).withAlpha(245),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.getPrimary(context).withAlpha(120), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 90 : 30),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.getPrimary(context).withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: AppColors.getPrimary(context),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: GoogleFonts.inter(
                              color: AppColors.getPrimary(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '• Just now',
                          style: GoogleFonts.inter(
                            color: AppColors.getSubtext(context),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message.content,
                      style: GoogleFonts.inter(
                        color: AppColors.getText(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: onReply,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  backgroundColor: AppColors.getPrimary(context),
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Reply',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper Dialogs ──────────────────────────────────────────────────────────

void _showDeleteChatDialog(BuildContext context, WidgetRef ref, PeerUiModel friend) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.getCard(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.getBorder(context)),
      ),
      title: Text(
        'Delete Chat?',
        style: GoogleFonts.inter(
          color: AppColors.getText(context),
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
      ),
      content: Text(
        'Do you want to delete all messages with "${friend.name}"? This friend will still remain saved in your Saved Friends.',
        style: GoogleFonts.inter(
          color: AppColors.getSubtext(context),
          fontSize: 14,
          height: 1.4,
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
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () {
            Navigator.pop(ctx);
            ref.read(meshProvider.notifier).deleteConversation(friend.id);
          },
          child: Text(
            'Delete Chat',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

void _showForgetFriendDialog(BuildContext context, WidgetRef ref, PeerUiModel friend) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.getCard(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.getBorder(context)),
      ),
      title: Text(
        'Forget Friend?',
        style: GoogleFonts.inter(
          color: AppColors.getText(context),
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
      ),
      content: Text(
        'Remove "${friend.name}" from your Saved Friends list? (You can reconnect anytime via QR code or Nearby search).',
        style: GoogleFonts.inter(
          color: AppColors.getSubtext(context),
          fontSize: 14,
          height: 1.4,
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
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () {
            Navigator.pop(ctx);
            ref.read(meshProvider.notifier).forgetFriend(friend.id);
          },
          child: Text(
            'Forget Friend',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

String _formatFriendlyError(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('bluetooth') && lower.contains('permission')) {
    return 'Bluetooth permission is required to search nearby.';
  } else if (lower.contains('location') && lower.contains('disabled')) {
    return 'Please enable Location Services to find friends.';
  }
  return raw;
}
