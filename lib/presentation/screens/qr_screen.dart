import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../domain/entities/peer_node.dart';
import '../../main.dart';
import '../providers/mesh_provider.dart';
import '../providers/user_profile_provider.dart';
import 'chat_screen.dart';

class QrScreen extends ConsumerStatefulWidget {
  const QrScreen({super.key});

  @override
  ConsumerState<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends ConsumerState<QrScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late MobileScannerController _scannerController;

  final TextEditingController _friendCodeController = TextEditingController();
  final TextEditingController _friendNameController = TextEditingController();

  bool _isProcessingScan = false;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.read(meshProvider).isDiscovering) {
        ref.read(meshProvider.notifier).startDiscovery();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    _friendCodeController.dispose();
    _friendNameController.dispose();
    super.dispose();
  }

  void _handleDecodedQr(String rawData) {
    if (_isProcessingScan) return;
    _isProcessingScan = true;

    HapticFeedback.vibrate();

    String peerId = rawData.trim();
    String peerName = 'Friend ${peerId.take(6)}';

    // Parse JSON payload if available
    try {
      if (rawData.trim().startsWith('{')) {
        final map = jsonDecode(rawData) as Map<String, dynamic>;
        peerId = map['nodeId'] as String? ?? peerId;
        peerName = map['name'] as String? ?? peerName;
      }
    } catch (_) {}

    final cleanId = peerId.length > 8 ? peerId.substring(0, 8).toLowerCase() : peerId.toLowerCase();

    // Prevent self-pairing
    final meshState = ref.read(meshProvider);
    final localNodeId = (meshState.localNodeId ?? '').toLowerCase();
    final cleanLocalId = localNodeId.length > 8 ? localNodeId.substring(0, 8) : localNodeId;

    if (cleanId.isEmpty || cleanId == cleanLocalId || (cleanLocalId.isNotEmpty && cleanId.contains(cleanLocalId))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MeshColors.surface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: MeshColors.border),
          ),
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: MeshColors.warning, size: 20),
              const SizedBox(width: 10),
              Text(
                'You cannot add your own QR code as a friend!',
                style: GoogleFonts.inter(
                  color: MeshColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
      _isProcessingScan = false;
      return;
    }

    // Ensure discovery is active
    if (!meshState.isDiscovering) {
      ref.read(meshProvider.notifier).startDiscovery();
    }

    // Trigger connection
    ref.read(meshProvider.notifier).connectToPeer(cleanId, peerName: peerName);

    // Save friend locally
    final peerRepo = ref.read(peerRepositoryProvider);
    peerRepo.savePeer(PeerNode(
      id: cleanId,
      name: peerName,
      connectionType: 'QR Scan',
      rssi: -60,
      lastSeen: DateTime.now(),
    ));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: MeshColors.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: MeshColors.border),
        ),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: MeshColors.success, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Scanned "$peerName"! Saved & connecting offline…',
                style: GoogleFonts.inter(
                  color: MeshColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final newPeer = PeerUiModel(
      id: cleanId,
      name: peerName,
      rssi: -60,
      connectionType: 'QR Scan',
      wifiState: PeerWifiState.connecting,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ChatScreen(peer: newPeer)),
    );
  }

  void _handleAddFriendManual() {
    final code = _friendCodeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a friend Node ID or payload')),
      );
      return;
    }
    _handleDecodedQr(code);
  }

  Future<void> _pickQrFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final BarcodeCapture? capture = await _scannerController.analyzeImage(image.path);
      if (capture != null && capture.barcodes.isNotEmpty) {
        final code = capture.barcodes.first.rawValue;
        if (code != null && code.isNotEmpty) {
          _handleDecodedQr(code);
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No QR Code found in selected image')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error analyzing image: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final meshState = ref.watch(meshProvider);
    final localNodeId = meshState.localNodeId ?? 'local';

    ref.listen(meshProvider.select((s) => s.peers), (prev, next) {
      final justConnected = next.where((p) => p.wifiState == PeerWifiState.connected).toList();
      if (justConnected.isNotEmpty && (prev == null || !prev.any((p) => p.id == justConnected.first.id && p.wifiState == PeerWifiState.connected))) {
        final connectedPeer = justConnected.first;
        HapticFeedback.heavyImpact();
        showModalBottomSheet(
          context: context,
          backgroundColor: MeshColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (ctx) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: MeshColors.success.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: MeshColors.success, size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  '🎉 Friend Connected!',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: MeshColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${connectedPeer.name} (${normalizeId(connectedPeer.id)}) just joined your direct mesh network!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: MeshColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => ChatScreen(peer: connectedPeer)),
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_rounded),
                    label: const Text('Open Chat Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MeshColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    });

    // Encode QR Payload
    final qrData = jsonEncode({
      'app': 'MeshLink',
      'nodeId': localNodeId,
      'name': profile.displayName,
      'avatar': profile.avatarIndex,
    });

    return Scaffold(
      backgroundColor: MeshColors.background,
      appBar: AppBar(
        title: Text(
          'QR Friend Pairing',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: MeshColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: MeshColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: MeshColors.primaryLight,
          indicatorWeight: 3,
          labelColor: MeshColors.primaryLight,
          unselectedLabelColor: MeshColors.textTertiary,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner_rounded, size: 18), text: 'Scan QR'),
            Tab(icon: Icon(Icons.qr_code_rounded, size: 18), text: 'My QR'),
            Tab(icon: Icon(Icons.keyboard_rounded, size: 18), text: 'Type Code'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Tab 1: Live Camera QR Scanner ─────────────────────────────
          Stack(
            children: [
              MobileScanner(
                controller: _scannerController,
                onDetect: (capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
                      _handleDecodedQr(barcode.rawValue!);
                      break;
                    }
                  }
                },
              ),

              // Scanner Glassmorphic Overlay Frame
              Center(
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: MeshColors.primaryLight,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: MeshColors.primary.withAlpha(80),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),

              // Instruction Banner Top
              Positioned(
                top: 24,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: MeshColors.surface.withAlpha(220),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MeshColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.camera_alt_rounded,
                          color: MeshColors.primaryLight, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Point camera at friend\'s QR Code to pair',
                          style: GoogleFonts.inter(
                            color: MeshColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Torch, Camera & Gallery Controls Bottom
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: MeshColors.surface.withAlpha(220),
                        shape: BoxShape.circle,
                        border: Border.all(color: MeshColors.border),
                      ),
                      child: IconButton(
                        icon: Icon(
                          _isTorchOn
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          color: _isTorchOn ? Colors.amber : Colors.white,
                        ),
                        onPressed: () {
                          _scannerController.toggleTorch();
                          setState(() {
                            _isTorchOn = !_isTorchOn;
                          });
                        },
                        tooltip: 'Toggle Flash',
                      ),
                    ),
                    const SizedBox(width: 20),
                    Container(
                      decoration: BoxDecoration(
                        color: MeshColors.surface.withAlpha(220),
                        shape: BoxShape.circle,
                        border: Border.all(color: MeshColors.border),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.flip_camera_ios_rounded,
                            color: Colors.white),
                        onPressed: () => _scannerController.switchCamera(),
                        tooltip: 'Switch Camera',
                      ),
                    ),
                    const SizedBox(width: 20),
                    Container(
                      decoration: BoxDecoration(
                        color: MeshColors.surface.withAlpha(220),
                        shape: BoxShape.circle,
                        border: Border.all(color: MeshColors.border),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.photo_library_rounded,
                            color: MeshColors.primaryLight),
                        onPressed: _pickQrFromGallery,
                        tooltip: 'Upload QR from Gallery',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Tab 2: My QR Code ──────────────────────────────────────────
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Text(
                  'Show this QR code to your friend to pair offline',
                  style: GoogleFonts.inter(
                    color: MeshColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),

                // Card with QR Code
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: MeshColors.primary.withAlpha(60),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 220.0,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF0A0A14),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF0A0A14),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        profile.displayName,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF0A0A14),
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Node ID: $localNodeId',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Copy Payload Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: MeshColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: qrData));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Friend payload string copied to clipboard'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded,
                        size: 18, color: MeshColors.primaryLight),
                    label: Text(
                      'Copy Friend Payload String',
                      style: GoogleFonts.inter(
                        color: MeshColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Tab 3: Type Code Fallback ──────────────────────────────────
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                Text(
                  'Enter your friend\'s Node ID or paste their QR payload string to add them manually.',
                  style: GoogleFonts.inter(
                    color: MeshColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                // Friend Display Name Field
                Text(
                  'Friend Name (Optional)',
                  style: GoogleFonts.inter(
                    color: MeshColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _friendNameController,
                  style: GoogleFonts.inter(color: MeshColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Sam',
                    prefixIcon: Icon(Icons.person_outline_rounded,
                        color: MeshColors.primaryLight, size: 20),
                  ),
                ),

                const SizedBox(height: 20),

                // Friend Node ID / Payload Field
                Text(
                  'Node ID or Payload String',
                  style: GoogleFonts.inter(
                    color: MeshColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _friendCodeController,
                  style: GoogleFonts.inter(color: MeshColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Paste 8-char Node ID or QR JSON…',
                    prefixIcon: const Icon(Icons.qr_code_rounded,
                        color: MeshColors.primaryLight, size: 20),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste_rounded,
                          color: MeshColors.textSecondary, size: 18),
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null) {
                          _friendCodeController.text = data!.text!;
                        }
                      },
                      tooltip: 'Paste',
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Add Friend Button
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: MeshColors.primaryGradient,
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
                      onPressed: _handleAddFriendManual,
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                      label: Text(
                        'Pair & Add Friend',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _StringExt on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
