import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../main.dart';
import '../providers/mesh_provider.dart';
import '../providers/user_profile_provider.dart';
import 'qr_screen.dart';

// Preset avatar badge styles
class AvatarBadge {
  final int id;
  final String label;
  final List<Color> colors;
  final IconData icon;

  const AvatarBadge({
    required this.id,
    required this.label,
    required this.colors,
    required this.icon,
  });
}

const List<AvatarBadge> kAvatarBadges = [
  AvatarBadge(
    id: 0,
    label: 'Indigo Mesh',
    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
    icon: Icons.hub_rounded,
  ),
  AvatarBadge(
    id: 1,
    label: 'Emerald Signal',
    colors: [Color(0xFF059669), Color(0xFF10B981)],
    icon: Icons.wifi_rounded,
  ),
  AvatarBadge(
    id: 2,
    label: 'Amber Flare',
    colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
    icon: Icons.bolt_rounded,
  ),
  AvatarBadge(
    id: 3,
    label: 'Rose Echo',
    colors: [Color(0xFFE11D48), Color(0xFFF43F5E)],
    icon: Icons.graphic_eq_rounded,
  ),
  AvatarBadge(
    id: 4,
    label: 'Cyan Pulse',
    colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
    icon: Icons.radar_rounded,
  ),
  AvatarBadge(
    id: 5,
    label: 'Violet Orbit',
    colors: [Color(0xFF9333EA), Color(0xFFA855F7)],
    icon: Icons.language_rounded,
  ),
  AvatarBadge(
    id: 6,
    label: 'Teal Beam',
    colors: [Color(0xFF0D9488), Color(0xFF14B8A6)],
    icon: Icons.sensors_rounded,
  ),
  AvatarBadge(
    id: 7,
    label: 'Gold Spark',
    colors: [Color(0xFFCA8A04), Color(0xFFEAB308)],
    icon: Icons.stars_rounded,
  ),
];

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _statusController;
  int _selectedAvatarIndex = 0;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(userProfileProvider);
    _nameController = TextEditingController(text: profile.displayName);
    _statusController = TextEditingController(text: profile.statusMessage);
    _selectedAvatarIndex = profile.avatarIndex;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Display name cannot be empty')),
      );
      return;
    }

    ref.read(userProfileProvider.notifier).updateProfile(
          displayName: name,
          avatarIndex: _selectedAvatarIndex,
          statusMessage: _statusController.text.trim(),
        );

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
            const Icon(Icons.check_circle_rounded,
                color: MeshColors.success, size: 20),
            const SizedBox(width: 10),
            Text(
              'Profile updated successfully!',
              style: GoogleFonts.inter(
                color: MeshColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final meshState = ref.watch(meshProvider);
    final localNodeId = meshState.localNodeId ?? 'local';

    final activeBadge = kAvatarBadges.firstWhere(
      (b) => b.id == _selectedAvatarIndex,
      orElse: () => kAvatarBadges.first,
    );

    return Scaffold(
      backgroundColor: MeshColors.background,
      appBar: AppBar(
        title: Text(
          'Edit Profile',
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _saveProfile,
              child: Text(
                'Save',
                style: GoogleFonts.inter(
                  color: MeshColors.primaryLight,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar Preview Header
            Center(
              child: Column(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: activeBadge.colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: activeBadge.colors.first.withAlpha(80),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        activeBadge.icon,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _nameController.text.isEmpty
                        ? profile.displayName
                        : _nameController.text,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: MeshColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    activeBadge.label,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: MeshColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Display Name Input Field
            Text(
              'Display Name',
              style: GoogleFonts.inter(
                color: MeshColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.inter(color: MeshColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Enter nickname…',
                prefixIcon: const Icon(Icons.person_outline_rounded,
                    color: MeshColors.primaryLight, size: 20),
              ),
            ),

            const SizedBox(height: 20),

            // Status Message Input Field
            Text(
              'Status Message',
              style: GoogleFonts.inter(
                color: MeshColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _statusController,
              style: GoogleFonts.inter(color: MeshColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Available on MeshLink…',
                prefixIcon: const Icon(Icons.chat_bubble_outline_rounded,
                    color: MeshColors.primaryLight, size: 20),
              ),
            ),

            const SizedBox(height: 28),

            // Avatar Badge Selection Palette
            Text(
              'Choose Avatar Badge',
              style: GoogleFonts.inter(
                color: MeshColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.0,
              ),
              itemCount: kAvatarBadges.length,
              itemBuilder: (context, index) {
                final badge = kAvatarBadges[index];
                final isSelected = badge.id == _selectedAvatarIndex;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedAvatarIndex = badge.id;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: badge.colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: isSelected ? 3 : 0,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: badge.colors.first.withAlpha(120),
                                blurRadius: 12,
                                spreadRadius: 1,
                              )
                            ]
                          : [],
                    ),
                    child: Center(
                      child: Icon(
                        badge.icon,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // QR Code Quick Access Button
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  gradient: MeshColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const QrScreen()),
                    );
                  },
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                  label: Text(
                    'My QR Code & Add Friend',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Node Fingerprint Information Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MeshColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MeshColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: MeshColors.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.fingerprint_rounded,
                        color: MeshColors.primaryLight, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Node Fingerprint ID',
                          style: GoogleFonts.inter(
                            color: MeshColors.textTertiary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          localNodeId,
                          style: GoogleFonts.inter(
                            color: MeshColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded,
                        color: MeshColors.textSecondary, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: localNodeId));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Node ID copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
