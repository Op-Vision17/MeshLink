import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../main.dart';
import '../providers/mesh_provider.dart';
import '../providers/permission_provider.dart';
import '../providers/user_profile_provider.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'qr_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref.read(permissionProvider.notifier).checkBluetoothState();
      ref.read(permissionProvider.notifier).checkLocationServiceState();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(permissionProvider.notifier).checkBluetoothState();
      ref.read(permissionProvider.notifier).checkLocationServiceState();
    }
  }
  @override
  Widget build(BuildContext context) {
    final permState = ref.watch(permissionProvider);
    final meshState = ref.watch(meshProvider);

    ref.listen<List<String>>(
      meshProvider.select((s) => s.errorLog),
      (previous, next) {
        if (next.isNotEmpty && (previous == null || next.length > previous.length)) {
          final rawError = next.last;

          // Suppress bind notices and transient background connection snackbars
          final hasConnectedPeers = meshState.peers.any((p) => p.isConnected);
          final lower = rawError.toLowerCase();
          if (lower.contains('eaddrinuse') || lower.contains('bind') || (hasConnectedPeers && (lower.contains('connection') || lower.contains('connect') || lower.contains('failed')))) {
            return;
          }

          final friendlyMsg = _formatFriendlyError(rawError);
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: MeshColors.surface,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: MeshColors.border),
              ),
              content: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: MeshColors.warning, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      friendlyMsg,
                      style: GoogleFonts.inter(
                        color: MeshColors.textPrimary,
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

    ref.listen(meshProvider.select((s) => s.chatMessages), (prev, next) {
      if (next.isNotEmpty && (prev == null || next.length > prev.length)) {
        final lastMsg = next.last;
        if (lastMsg.senderId != 'local' && lastMsg.senderId.isNotEmpty) {
          final activeChatId = ref.read(activeChatPeerIdProvider);
          if (activeChatId != null) {
            // User is inside ChatScreen, suppress notification banner!
            return;
          }

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

          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: MeshColors.surface,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: MeshColors.primary, width: 1.5),
              ),
              content: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: MeshColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        senderPeer.name.isNotEmpty ? senderPeer.name[0].toUpperCase() : '?',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          senderPeer.name,
                          style: GoogleFonts.inter(
                            color: MeshColors.primaryLight,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lastMsg.content,
                          style: GoogleFonts.inter(
                            color: MeshColors.textPrimary,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => ChatScreen(peer: senderPeer),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      backgroundColor: MeshColors.primary.withAlpha(40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Reply',
                      style: GoogleFonts.inter(
                        color: MeshColors.primaryLight,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    });

    return Scaffold(
      backgroundColor: MeshColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Premium App Bar ──────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 72,
            floating: true,
            pinned: true,
            backgroundColor: MeshColors.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/logo_without_bg.png',
                  width: 32,
                  height: 32,
                ),
                const SizedBox(width: 10),
                Text(
                  'MeshLink',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: MeshColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.qr_code_scanner_rounded,
                    color: MeshColors.primaryLight, size: 22),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const QrScreen()),
                  );
                },
                tooltip: 'My QR Code & Add Friend',
              ),
              IconButton(
                icon: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: kAvatarBadges[ref.watch(userProfileProvider).avatarIndex % kAvatarBadges.length].colors,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    kAvatarBadges[ref.watch(userProfileProvider).avatarIndex % kAvatarBadges.length].icon,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
                tooltip: 'Edit Profile',
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _DiscoveryIndicator(
                    isDiscovering: meshState.isDiscovering),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(0.5),
              child: Container(
                height: 0.5,
                color: MeshColors.border,
              ),
            ),
          ),

          // ── Status Banner ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _StatusBanner(message: meshState.statusMessage),
          ),

          // ── Content ──────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Quick Tutorial Card
                const _QuickGuideCard(),
                const SizedBox(height: 14),

                // Discovery Controls
                _DiscoveryCard(
                  permissionsGranted: permState.allGranted,
                  isDiscovering: meshState.isDiscovering,
                  isBatteryOptimizationIgnored:
                      permState.isBatteryOptimizationIgnored,
                  isBluetoothEnabled: permState.isBluetoothEnabled,
                  isLocationServiceEnabled: permState.isLocationServiceEnabled,
                  onToggle: () async {
                    if (meshState.isDiscovering) {
                      debugPrint('================================================================');
                      debugPrint('[USER_ACTION] 🔘 Tapped "STOP DISCOVERY"');
                      debugPrint('================================================================');
                      ref.read(meshProvider.notifier).stopDiscovery();
                    } else {
                      debugPrint('================================================================');
                      debugPrint('[USER_ACTION] 🔘 Tapped "START DISCOVERY"');
                      debugPrint('================================================================');
                      final isBtEnabled = await ref
                          .read(permissionProvider.notifier)
                          .checkBluetoothState();
                      if (!isBtEnabled && context.mounted) {
                        _showEnableBluetoothDialog(context, ref);
                        return;
                      }
                      final isLocEnabled = await ref
                          .read(permissionProvider.notifier)
                          .checkLocationServiceState();
                      if (!isLocEnabled && context.mounted) {
                        _showEnableLocationDialog(context, ref);
                        return;
                      }
                      ref.read(meshProvider.notifier).startDiscovery();
                    }
                  },
                  onRequestPermissions: () {
                    debugPrint('[USER_ACTION] 🔘 Tapped "GRANT PERMISSIONS"');
                    ref
                        .read(permissionProvider.notifier)
                        .checkAndRequestPermissions();
                  },
                  onRequestBatteryExemption: () {
                    debugPrint('[USER_ACTION] 🔘 Tapped "BATTERY EXEMPTION"');
                    ref
                        .read(permissionProvider.notifier)
                        .requestBatteryOptimizationExemption();
                  },
                  onRequestEnableBluetooth: () {
                    debugPrint('[USER_ACTION] 🔘 Tapped "ENABLE BLUETOOTH"');
                    _showEnableBluetoothDialog(context, ref);
                  },
                  onRequestEnableLocation: () {
                    debugPrint('[USER_ACTION] 🔘 Tapped "ENABLE LOCATION SERVICES"');
                    _showEnableLocationDialog(context, ref);
                  },
                ),
                const SizedBox(height: 16),

                // Saved Friends Section
                if (meshState.savedPeers.isNotEmpty) ...[
                  _SavedFriendsCard(
                    savedPeers: meshState.savedPeers,
                    livePeers: meshState.peers,
                    onConnect: (peer) {
                      debugPrint('[USER_ACTION] 🔘 Tapped "CONNECT" for saved friend ${peer.name} (${peer.id})');
                      ref.read(meshProvider.notifier).connectToPeer(peer.id, peerName: peer.name);
                    },
                    onDisconnect: (peerId) {
                      debugPrint('[USER_ACTION] 🔘 Tapped "DISCONNECT" for saved friend $peerId');
                      ref.read(meshProvider.notifier).disconnectFromPeer(peerId);
                    },
                    onSend: (peer) {
                      debugPrint('[USER_ACTION] 🔘 Tapped "OPEN CHAT" for saved friend ${peer.name}');
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => ChatScreen(peer: peer),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Peer List
                _PeerListCard(
                  peers: meshState.peers,
                  isDiscovering: meshState.isDiscovering,
                  onConnect: (peerId) {
                    final targetPeer = meshState.peers.firstWhere((p) => p.id == peerId, orElse: () => meshState.peers.first);
                    debugPrint('================================================================');
                    debugPrint('[USER_ACTION] 🔘 Tapped "CONNECT" to target: ${targetPeer.name} (peerId=$peerId, rssi=${targetPeer.rssi})');
                    debugPrint('================================================================');
                    ref.read(meshProvider.notifier).connectToPeer(peerId);
                  },
                  onDisconnect: (peerId) {
                    debugPrint('[USER_ACTION] 🔘 Tapped "DISCONNECT" for peerId=$peerId');
                    ref.read(meshProvider.notifier).disconnectFromPeer(peerId);
                  },
                  onSend: (peer) {
                    debugPrint('[USER_ACTION] 🔘 Tapped "OPEN CHAT" with ${peer.name} (peerId=${peer.id})');
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => ChatScreen(peer: peer),
                      ),
                    );
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _QuickGuideCard extends StatefulWidget {
  const _QuickGuideCard();

  @override
  State<_QuickGuideCard> createState() => _QuickGuideCardState();
}

class _QuickGuideCardState extends State<_QuickGuideCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: MeshColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isExpanded
              ? MeshColors.primary.withAlpha(60)
              : MeshColors.border,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: MeshColors.primary.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: MeshColors.primaryLight,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Getting Started',
                    style: GoogleFonts.inter(
                      color: MeshColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: MeshColors.textTertiary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                children: [
                  Container(
                    height: 0.5,
                    color: MeshColors.border,
                  ),
                  const SizedBox(height: 12),
                  _buildStep('1', 'Turn ON Bluetooth & Location on both phones.'),
                  const SizedBox(height: 8),
                  _buildStep('2', 'Tap "Start Scanning" on both phones.'),
                  const SizedBox(height: 8),
                  _buildStep('3', 'Select a device from the list & tap Connect to chat!'),
                  const SizedBox(height: 8),
                  _buildStep('🌐', 'Far devices (>30m) auto-appear via mesh relays.'),
                ],
              ),
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(String num, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: MeshColors.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            num,
            style: GoogleFonts.inter(
              color: MeshColors.primaryLight,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              color: MeshColors.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _DiscoveryIndicator extends StatelessWidget {
  final bool isDiscovering;
  const _DiscoveryIndicator({required this.isDiscovering});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDiscovering
            ? MeshColors.success.withAlpha(20)
            : MeshColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDiscovering
              ? MeshColors.success.withAlpha(60)
              : MeshColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDiscovering)
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: MeshColors.success,
              ),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MeshColors.textDisabled,
              ),
            ),
          const SizedBox(width: 6),
          Text(
            isDiscovering ? 'SCANNING' : 'IDLE',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isDiscovering
                  ? MeshColors.success
                  : MeshColors.textDisabled,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String message;
  const _StatusBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final isConnecting = message.toLowerCase().contains('connecting');
    final isError = message.toLowerCase().contains('error') ||
        message.toLowerCase().contains('failed');
    final isConnected = message.toLowerCase().contains('connected');

    final (bgColor, iconColor, icon) = isConnecting
        ? (MeshColors.warning.withAlpha(15), MeshColors.warning,
            Icons.sync_rounded)
        : isError
            ? (MeshColors.error.withAlpha(15), MeshColors.error,
                Icons.error_outline_rounded)
            : isConnected
                ? (MeshColors.success.withAlpha(15), MeshColors.success,
                    Icons.check_circle_outline_rounded)
                : (MeshColors.surface, MeshColors.info,
                    Icons.info_outline_rounded);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(color: MeshColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isConnecting
                  ? '$message — Accept prompt if shown on device notification bar!'
                  : message,
              style: GoogleFonts.inter(
                color: MeshColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  final bool permissionsGranted;
  final bool isDiscovering;
  final bool isBatteryOptimizationIgnored;
  final bool isBluetoothEnabled;
  final bool isLocationServiceEnabled;
  final VoidCallback onToggle;
  final VoidCallback onRequestPermissions;
  final VoidCallback onRequestBatteryExemption;
  final VoidCallback onRequestEnableBluetooth;
  final VoidCallback onRequestEnableLocation;

  const _DiscoveryCard({
    required this.permissionsGranted,
    required this.isDiscovering,
    required this.isBatteryOptimizationIgnored,
    required this.isBluetoothEnabled,
    required this.isLocationServiceEnabled,
    required this.onToggle,
    required this.onRequestPermissions,
    required this.onRequestBatteryExemption,
    required this.onRequestEnableBluetooth,
    required this.onRequestEnableLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MeshColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MeshColors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: MeshColors.primaryGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.radar_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device Scanning',
                    style: GoogleFonts.inter(
                      color: MeshColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Off-grid Bluetooth & Wi-Fi mesh network',
                    style: GoogleFonts.inter(
                      color: MeshColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (!permissionsGranted)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MeshColors.warning.withAlpha(10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: MeshColors.warning.withAlpha(40),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          color: MeshColors.warning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bluetooth & location permissions required',
                          style: GoogleFonts.inter(
                            color: MeshColors.warning,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MeshColors.warning,
                      side: BorderSide(
                          color: MeshColors.warning.withAlpha(100)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: onRequestPermissions,
                    icon: const Icon(Icons.security_rounded, size: 16),
                    label: Text(
                      'Grant Permissions',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            )
          else ...[
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  gradient: isDiscovering
                      ? LinearGradient(
                          colors: [
                            MeshColors.warning.withAlpha(200),
                            MeshColors.error.withAlpha(200),
                          ],
                        )
                      : MeshColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onToggle,
                  icon: Icon(
                    isDiscovering ? Icons.stop_rounded : Icons.radar_rounded,
                    size: 20,
                  ),
                  label: Text(
                    isDiscovering ? 'Stop Scanning' : 'Start Scanning',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            if (!isBluetoothEnabled) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: onRequestEnableBluetooth,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: MeshColors.warning.withAlpha(15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: MeshColors.warning.withAlpha(50),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bluetooth_disabled_rounded,
                          color: MeshColors.warning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bluetooth is turned off. Tap to turn on.',
                          style: GoogleFonts.inter(
                            color: MeshColors.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: MeshColors.textDisabled, size: 16),
                    ],
                  ),
                ),
              ),
            ],
            if (!isLocationServiceEnabled) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: onRequestEnableLocation,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: MeshColors.warning.withAlpha(15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: MeshColors.warning.withAlpha(50),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.location_off_rounded,
                          color: MeshColors.warning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Location Services turned off. Tap to turn on.',
                          style: GoogleFonts.inter(
                            color: MeshColors.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: MeshColors.textDisabled, size: 16),
                    ],
                  ),
                ),
              ),
            ],
            if (!isBatteryOptimizationIgnored) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: onRequestBatteryExemption,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: MeshColors.warning.withAlpha(10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: MeshColors.warning.withAlpha(40),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.battery_saver_rounded,
                          color: MeshColors.warning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Exempt from battery optimization for background mesh.',
                          style: GoogleFonts.inter(
                            color: MeshColors.warning.withAlpha(200),
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: MeshColors.textDisabled, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PeerListCard extends StatelessWidget {
  final List<PeerUiModel> peers;
  final bool isDiscovering;
  final void Function(String) onConnect;
  final void Function(String) onDisconnect;
  final void Function(PeerUiModel) onSend;

  const _PeerListCard({
    required this.peers,
    required this.isDiscovering,
    required this.onConnect,
    required this.onDisconnect,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MeshColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MeshColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: MeshColors.accent.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.devices_rounded,
                      color: MeshColors.accent, size: 15),
                ),
                const SizedBox(width: 10),
                Text(
                  'Nearby Devices',
                  style: GoogleFonts.inter(
                    color: MeshColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: MeshColors.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${peers.length}',
                    style: GoogleFonts.inter(
                      color: MeshColors.primaryLight,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: MeshColors.border),
          if (peers.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
              child: Row(
                children: [
                  Icon(
                    isDiscovering
                        ? Icons.bluetooth_searching_rounded
                        : Icons.bluetooth_disabled_rounded,
                    color: MeshColors.textDisabled,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isDiscovering
                          ? 'Searching for nearby devices…'
                          : 'Tap "Start Scanning" to find devices nearby.',
                      style: GoogleFonts.inter(
                        color: MeshColors.textDisabled,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: peers.length,
              separatorBuilder: (context2, idx) =>
                  Container(height: 0.5, color: MeshColors.border),
              itemBuilder: (context, i) => _PeerTile(
                peer: peers[i],
                onConnect: () => onConnect(peers[i].id),
                onDisconnect: () => onDisconnect(peers[i].id),
                onSend: () => onSend(peers[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  final PeerUiModel peer;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onSend;

  const _PeerTile({
    required this.peer,
    required this.onConnect,
    required this.onDisconnect,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final (stateLabel, stateColor) = switch (peer.wifiState) {
      PeerWifiState.connected => ('Connected', MeshColors.success),
      PeerWifiState.connecting => ('Connecting…', MeshColors.warning),
      PeerWifiState.failed => ('Failed', MeshColors.error),
      PeerWifiState.disconnected => ('Disconnected', MeshColors.textDisabled),
      PeerWifiState.discovered => ('Discovered', MeshColors.accent),
    };

    return InkWell(
      onTap: peer.isConnected ? onSend : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            // Peer avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: stateColor.withAlpha(15),
                border: Border.all(color: stateColor.withAlpha(50)),
              ),
              child: Icon(
                peer.connectionType == 'BLE'
                    ? Icons.bluetooth_rounded
                    : Icons.wifi_rounded,
                color: stateColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            // Peer info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peer.name,
                    style: GoogleFonts.inter(
                      color: MeshColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Signal Strength: ${peer.rssi} dBm',
                    style: GoogleFonts.inter(
                      color: MeshColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                  if (peer.groupOwnerIp != null)
                    Text(
                      'IP: ${peer.groupOwnerIp}',
                      style: GoogleFonts.inter(
                        color: MeshColors.success,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // State chip + actions
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: stateColor.withAlpha(15),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: stateColor.withAlpha(50)),
                  ),
                  child: Text(
                    stateLabel,
                    style: GoogleFonts.inter(
                      color: stateColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (peer.wifiState == PeerWifiState.discovered ||
                        peer.wifiState == PeerWifiState.failed ||
                        peer.wifiState == PeerWifiState.disconnected)
                      _ActionButton(
                        label: 'Connect',
                        icon: Icons.link_rounded,
                        color: MeshColors.primary,
                        onTap: onConnect,
                      ),
                    if (peer.wifiState == PeerWifiState.connecting) ...[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: MeshColors.warning,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _ActionButton(
                        label: 'Cancel',
                        icon: Icons.close_rounded,
                        color: MeshColors.error,
                        onTap: onDisconnect,
                      ),
                    ],
                    if (peer.isConnected) ...[
                      _ActionButton(
                        label: 'Chat',
                        icon: Icons.chat_bubble_outline_rounded,
                        color: MeshColors.success,
                        onTap: onSend,
                      ),
                      const SizedBox(width: 6),
                      _ActionButton(
                        label: 'Disconnect',
                        icon: Icons.link_off_rounded,
                        color: MeshColors.error,
                        onTap: onDisconnect,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showEnableBluetoothDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: MeshColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: MeshColors.border),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: MeshColors.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bluetooth_searching_rounded,
              color: MeshColors.primaryLight,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Turn On Bluetooth',
            style: GoogleFonts.inter(
              color: MeshColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: Text(
        'MeshLink requires Bluetooth to discover and connect with nearby devices. Would you like to turn on Bluetooth now?',
        style: GoogleFonts.inter(
          color: MeshColors.textSecondary,
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
              color: MeshColors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: MeshColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () async {
            Navigator.pop(ctx);
            await ref.read(permissionProvider.notifier).requestEnableBluetooth();
          },
          child: Text(
            'Allow',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

void _showEnableLocationDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: MeshColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: MeshColors.border),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: MeshColors.warning.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.location_off_rounded,
              color: MeshColors.warning,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Turn On Location',
            style: GoogleFonts.inter(
              color: MeshColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: Text(
        'MeshLink requires Location Services (GPS) turned ON for BLE and Wi-Fi Direct scanning. Would you like to open Settings to turn on Location Services?',
        style: GoogleFonts.inter(
          color: MeshColors.textSecondary,
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
              color: MeshColors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: MeshColors.warning,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () async {
            Navigator.pop(ctx);
            await ref.read(permissionProvider.notifier).requestEnableLocationService();
          },
          child: Text(
            'Allow',
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
    return 'Bluetooth permission is required to scan nearby.';
  } else if (lower.contains('location') && lower.contains('disabled')) {
    return 'Please enable Location Services to discover devices.';
  }
  return raw;
}

class _SavedFriendsCard extends StatelessWidget {
  final List<PeerUiModel> savedPeers;
  final List<PeerUiModel> livePeers;
  final void Function(PeerUiModel) onConnect;
  final void Function(String) onDisconnect;
  final void Function(PeerUiModel) onSend;

  const _SavedFriendsCard({
    required this.savedPeers,
    required this.livePeers,
    required this.onConnect,
    required this.onDisconnect,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MeshColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MeshColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: MeshColors.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.people_alt_rounded,
                      color: MeshColors.primaryLight, size: 15),
                ),
                const SizedBox(width: 10),
                Text(
                  'Saved Friends',
                  style: GoogleFonts.inter(
                    color: MeshColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: MeshColors.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${savedPeers.length}',
                    style: GoogleFonts.inter(
                      color: MeshColors.primaryLight,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: MeshColors.border),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: savedPeers.length,
            separatorBuilder: (context, index) =>
                Container(height: 0.5, color: MeshColors.borderSubtle),
            itemBuilder: (context, index) {
              final friend = savedPeers[index];
              final normFriendId = normalizeId(friend.id);
              final liveMatch = livePeers.firstWhere(
                (p) => p.id == friend.id || normalizeId(p.id) == normFriendId,
                orElse: () => friend,
              );
              final isConnected = friend.isConnected || liveMatch.isConnected;
              final isConnecting = (friend.wifiState == PeerWifiState.connecting || liveMatch.wifiState == PeerWifiState.connecting) && !isConnected;

              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            gradient: MeshColors.primaryGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              friend.name.isNotEmpty
                                  ? friend.name[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isConnected
                                  ? MeshColors.success
                                  : isConnecting
                                      ? MeshColors.warning
                                      : MeshColors.textDisabled,
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
                            friend.name,
                            style: GoogleFonts.inter(
                              color: MeshColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isConnected
                                ? 'Connected ✓'
                                : isConnecting
                                    ? 'Connecting…'
                                    : 'Offline Friend',
                            style: GoogleFonts.inter(
                              color: isConnected
                                  ? MeshColors.success
                                  : isConnecting
                                      ? MeshColors.warning
                                      : MeshColors.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isConnected) ...[
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline_rounded,
                            color: MeshColors.primaryLight, size: 20),
                        onPressed: () => onSend(liveMatch),
                        tooltip: 'Chat',
                      ),
                      IconButton(
                        icon: const Icon(Icons.link_off_rounded,
                            color: MeshColors.error, size: 20),
                        onPressed: () => onDisconnect(friend.id),
                        tooltip: 'Disconnect',
                      ),
                    ] else if (isConnecting) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: MeshColors.warning.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: MeshColors.warning.withAlpha(80)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: MeshColors.warning,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Connecting',
                              style: GoogleFonts.inter(
                                color: MeshColors.warning,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: const BorderSide(color: MeshColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => onConnect(friend),
                        icon: const Icon(Icons.link_rounded, size: 14),
                        label: Text(
                          'Connect',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline_rounded,
                            color: MeshColors.textSecondary, size: 20),
                        onPressed: () => onSend(friend),
                        tooltip: 'Chat History',
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

