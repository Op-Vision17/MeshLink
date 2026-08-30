import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/app_colors.dart';
import '../providers/call_provider.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);
    final isDark = AppColors.isDark(context);

    // Automatically close CallScreen if call has ended/idle
    ref.listen<CallStateModel>(callProvider, (prev, next) {
      if (next.status == CallStatus.idle) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    });

    final isConnected = callState.status == CallStatus.connected;
    final isOutgoing = callState.status == CallStatus.outgoingRinging;
    final isEnded = callState.status == CallStatus.ended;

    String statusText;
    if (isEnded) {
      statusText = callState.endReason ?? 'Call Ended';
    } else if (isConnected) {
      statusText = _formatDuration(callState.durationSeconds);
    } else if (isOutgoing) {
      statusText = 'Ringing…';
    } else {
      statusText = 'Incoming Call…';
    }

    final peerName = callState.peerName ?? 'Friend';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (callState.status != CallStatus.idle && callState.status != CallStatus.ended) {
          ref.read(callProvider.notifier).endActiveCall();
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0B0F14) : const Color(0xFF1B2430),
        body: SafeArea(
          child: Stack(
            children: [
              // Top Bar
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isConnected ? const Color(0xFF00B894) : const Color(0xFFE17055),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isConnected ? 'ENCRYPTED DIRECT P2P' : 'CONNECTING',
                            style: GoogleFonts.inter(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 28),
                      onPressed: () {
                        if (Navigator.canPop(context)) Navigator.pop(context);
                      },
                      tooltip: 'Minimize',
                    ),
                  ],
                ),
              ),

              // Center Avatar & Wave Pulsing
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animated Pulse Wave Rings
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer Wave
                            Container(
                              width: 140 * _pulseAnimation.value,
                              height: 140 * _pulseAnimation.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: (isConnected ? const Color(0xFF00D4A8) : const Color(0xFF6C5CE7))
                                    .withAlpha((35 / _pulseAnimation.value).toInt()),
                              ),
                            ),
                            // Middle Wave
                            Container(
                              width: 120 * _pulseAnimation.value,
                              height: 120 * _pulseAnimation.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: (isConnected ? const Color(0xFF00D4A8) : const Color(0xFF6C5CE7))
                                    .withAlpha((50 / _pulseAnimation.value).toInt()),
                              ),
                            ),
                            // Main Avatar Circle
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: const Color(0xFF6C5CE7),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white30, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(80),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 40,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 28),

                    // Peer Name
                    Text(
                      peerName,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Call Status / Live Duration
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: isEnded
                            ? Colors.redAccent.withAlpha(40)
                            : (isConnected ? const Color(0xFF00B894).withAlpha(40) : Colors.white10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        statusText,
                        style: GoogleFonts.inter(
                          color: isEnded ? Colors.redAccent : (isConnected ? const Color(0xFF00D4A8) : Colors.white70),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: isConnected ? 1.5 : 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Call Action Controls
              Positioned(
                bottom: 36,
                left: 24,
                right: 24,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Mute Mic Toggle
                        _CallControlButton(
                          icon: callState.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          label: callState.isMuted ? 'Muted' : 'Mute',
                          isActive: callState.isMuted,
                          activeColor: Colors.redAccent,
                          onTap: isConnected ? () => ref.read(callProvider.notifier).toggleMute() : null,
                        ),

                        // End Call (Hang Up) Button
                        GestureDetector(
                          onTap: () {
                            if (callState.status == CallStatus.incomingRinging) {
                              ref.read(callProvider.notifier).declineIncomingCall();
                            } else {
                              ref.read(callProvider.notifier).endActiveCall();
                            }
                          },
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF5252),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF5252).withAlpha(100),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.call_end_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),

                        // Speakerphone Toggle
                        _CallControlButton(
                          icon: callState.isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                          label: callState.isSpeakerOn ? 'Speaker' : 'Earpiece',
                          isActive: callState.isSpeakerOn,
                          activeColor: const Color(0xFF00D4A8),
                          onTap: isConnected ? () => ref.read(callProvider.notifier).toggleSpeaker() : null,
                        ),
                      ],
                    ),
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

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive ? activeColor : Colors.white.withAlpha(25),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? activeColor : Colors.white24,
                width: 1.2,
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.black87 : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
