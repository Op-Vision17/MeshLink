import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/app_colors.dart';
import '../providers/call_provider.dart';
import '../screens/call_screen.dart';

class IncomingCallOverlay extends ConsumerWidget {
  const IncomingCallOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callProvider);

    if (callState.status != CallStatus.incomingRinging) {
      return const SizedBox.shrink();
    }

    final isDark = AppColors.isDark(context);
    final peerName = callState.peerName ?? 'Friend';

    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: SafeArea(
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(20),
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161E28) : const Color(0xFF2C3E50),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF00D4A8).withAlpha(120), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(90),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                // Avatar with glowing pulse
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6C5CE7),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Name and label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        peerName,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00D4A8),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Incoming voice call…',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF00D4A8),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Action Buttons
                // Decline (Red)
                IconButton(
                  icon: const Icon(Icons.call_end_rounded, color: Colors.white, size: 22),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5252),
                    padding: const EdgeInsets.all(10),
                  ),
                  onPressed: () {
                    ref.read(callProvider.notifier).declineIncomingCall();
                  },
                  tooltip: 'Decline',
                ),
                const SizedBox(width: 8),

                // Accept (Green)
                IconButton(
                  icon: const Icon(Icons.call_rounded, color: Colors.white, size: 22),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF00B894),
                    padding: const EdgeInsets.all(10),
                  ),
                  onPressed: () async {
                    await ref.read(callProvider.notifier).acceptIncomingCall();
                    if (context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CallScreen()),
                      );
                    }
                  },
                  tooltip: 'Accept',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
