import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/live_video_service.dart';

class DetenerScreen extends StatefulWidget {
  final String sessionId;
  final String driverName;
  final String shareLink;
  final bool liveVideoEnabled;
  final ValueListenable<LiveVideoPreviewState> liveVideoPreview;
  final Future<bool> Function(bool enabled) onLiveVideoChanged;
  final Future<bool> Function() onSwitchCamera;
  final VoidCallback onDetener;

  const DetenerScreen({
    super.key,
    required this.sessionId,
    required this.driverName,
    required this.shareLink,
    required this.liveVideoEnabled,
    required this.liveVideoPreview,
    required this.onLiveVideoChanged,
    required this.onSwitchCamera,
    required this.onDetener,
  });

  @override
  State<DetenerScreen> createState() => _DetenerScreenState();
}

class _DetenerScreenState extends State<DetenerScreen>
    with TickerProviderStateMixin {
  bool _stopping = false;
  late bool _liveVideoEnabled;
  bool _videoBusy = false;
  bool _switchingCamera = false;
  bool _previewVisible = false;
  bool _previewExpanded = false;
  late AnimationController _pulseController;
  late AnimationController _glowController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _liveVideoEnabled = widget.liveVideoEnabled;
    _previewVisible = widget.liveVideoEnabled;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _glowAnimation = Tween<double>(begin: 0.4, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant DetenerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liveVideoEnabled != widget.liveVideoEnabled) {
      _liveVideoEnabled = widget.liveVideoEnabled;
      if (widget.liveVideoEnabled) {
        _previewVisible = true;
      } else {
        _previewVisible = false;
        _previewExpanded = false;
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _glowController.dispose();
    // NOTE: we do NOT mark the session inactive here.
    // Session lifecycle is managed by IniciarScreen via SharedPreferences.
    // When the app is reopened, _checkForActiveSession() will restore it.
    super.dispose();
  }

  Future<void> _shareLink() async {
    try {
      await Share.share(
        widget.shareLink,
        subject: "Track my location — Where Is My Driver",
      );
    } catch (_) {}
  }

  Future<void> _toggleLiveVideo() async {
    if (_videoBusy || _stopping) return;

    final nextValue = !_liveVideoEnabled;
    setState(() => _videoBusy = true);

    final success = await widget.onLiveVideoChanged(nextValue);
    if (!mounted) return;

    setState(() {
      _videoBusy = false;
      if (success) {
        _liveVideoEnabled = nextValue;
        _previewVisible = nextValue;
        if (!nextValue) _previewExpanded = false;
      }
    });

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextValue
                ? 'Camera could not start. Check camera permission.'
                : 'Camera could not stop.',
          ),
          backgroundColor: const Color(0xFFBA1A1A),
        ),
      );
    }
  }

  Future<void> _switchCamera() async {
    if (!_liveVideoEnabled || _switchingCamera || _videoBusy || _stopping) {
      return;
    }

    setState(() => _switchingCamera = true);
    final success = await widget.onSwitchCamera();
    if (!mounted) return;

    setState(() {
      _switchingCamera = false;
      if (success) _previewVisible = true;
    });
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera could not switch.'),
          backgroundColor: Color(0xFFBA1A1A),
        ),
      );
    }
  }

  Future<void> _stopSharing() async {
    if (_stopping) return;
    setState(() => _stopping = true);

    try {
      await Supabase.instance.client.from('location_sessions').update({
        'active': false,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.sessionId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: const Color(0xFFBA1A1A)),
        );
      }
      setState(() => _stopping = false);
      return;
    }

    widget.onDetener();

    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle,
                      color: Color(0xFF059669), size: 44),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Trip Ended',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF191C1E)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Location sharing has stopped.\nThe link is no longer available.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF424750), height: 1.4),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF003461),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Accept',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    }
  }

  Widget _buildSwitchCameraButton({double size = 56}) {
    return GestureDetector(
      onTap: _switchingCamera ? null : _switchCamera,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF003461).withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: const Color(0xFF006972).withValues(alpha: 0.18),
            width: 1.5,
          ),
        ),
        child: _switchingCamera
            ? const Padding(
                padding: EdgeInsets.all(17),
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF006972),
                ),
              )
            : const Icon(
                Icons.cameraswitch_rounded,
                color: Color(0xFF006972),
                size: 29,
              ),
      ),
    );
  }

  Widget _buildPreviewIconButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 26,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.56),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
          ),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.58),
      ),
    );
  }

  Widget _buildPreviewVideo(LiveVideoPreviewState preview,
      {double radius = 18}) {
    final track = preview.track;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        color: const Color(0xFF101820),
        child: track != null
            ? livekit.VideoTrackRenderer(
                track,
                fit: livekit.VideoViewFit.cover,
                renderMode: livekit.VideoRenderMode.auto,
              )
            : const Center(
                child: Icon(
                  Icons.videocam_rounded,
                  color: Colors.white54,
                  size: 28,
                ),
              ),
      ),
    );
  }

  Widget _buildCameraPreview(LiveVideoPreviewState preview) {
    final cameraLabel = preview.isFrontCamera ? 'FRONT' : 'BACK';

    return SizedBox(
      width: 106,
      height: 76,
      child: Stack(
        children: [
          Positioned.fill(child: _buildPreviewVideo(preview)),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF003461).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                cameraLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Row(
              children: [
                _buildPreviewIconButton(
                  icon: Icons.fullscreen_rounded,
                  onTap: () => setState(() => _previewExpanded = true),
                  size: 25,
                ),
                const SizedBox(width: 5),
                _buildPreviewIconButton(
                  icon: Icons.close_rounded,
                  onTap: () => setState(() {
                    _previewVisible = false;
                    _previewExpanded = false;
                  }),
                  size: 25,
                ),
              ],
            ),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: _buildPreviewIconButton(
              icon: Icons.cameraswitch_rounded,
              onTap: _switchCamera,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedPreview(LiveVideoPreviewState preview) {
    final cameraLabel = preview.isFrontCamera ? 'FRONT CAMERA' : 'REAR CAMERA';

    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: _buildPreviewVideo(preview, radius: 0),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.56),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  cameraLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 14,
              right: 14,
              child: Row(
                children: [
                  _buildPreviewIconButton(
                    icon: Icons.fullscreen_exit_rounded,
                    onTap: () => setState(() => _previewExpanded = false),
                    size: 42,
                  ),
                  const SizedBox(width: 10),
                  _buildPreviewIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => setState(() {
                      _previewVisible = false;
                      _previewExpanded = false;
                    }),
                    size: 42,
                  ),
                ],
              ),
            ),
            Positioned(
              right: 18,
              bottom: 18,
              child: _buildPreviewIconButton(
                icon: Icons.cameraswitch_rounded,
                onTap: _switchCamera,
                size: 48,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FB),
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF7F9FB), Color(0xFFFFF0F0)],
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // TRIP ACTIVE badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF006972).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle, color: Color(0xFF006972)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.driverName.isNotEmpty
                              ? '${widget.driverName.toUpperCase()} — TRIP ACTIVE'
                              : 'TRIP ACTIVE',
                          style: const TextStyle(
                            color: Color(0xFF006972),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Stop button
                  SizedBox(
                    width: 320,
                    height: 320,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Glow
                        AnimatedBuilder(
                          animation: _glowAnimation,
                          builder: (_, __) => Container(
                            width: 290,
                            height: 290,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFBA1A1A).withValues(
                                      alpha: _glowAnimation.value * 0.35),
                                  blurRadius: 60,
                                  spreadRadius: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Button
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (_, __) => Transform.scale(
                            scale: _stopping ? 0.95 : _pulseAnimation.value,
                            child: GestureDetector(
                              onTap: _stopping ? null : _stopSharing,
                              child: Container(
                                width: 270,
                                height: 270,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const RadialGradient(
                                    colors: [
                                      Color(0xFFCC1A1A),
                                      Color(0xFF93000A),
                                    ],
                                    center: Alignment.topCenter,
                                    radius: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFBA1A1A)
                                          .withValues(alpha: 0.3),
                                      blurRadius: 40,
                                      offset: const Offset(0, 16),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 250,
                                      height: 250,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.15),
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (_stopping)
                                          const SizedBox(
                                            width: 56,
                                            height: 56,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 4,
                                            ),
                                          )
                                        else
                                          Container(
                                            width: 72,
                                            height: 72,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white,
                                            ),
                                            child: const Icon(Icons.stop,
                                                color: Color(0xFF93000A),
                                                size: 44),
                                          ),
                                        const SizedBox(height: 18),
                                        Text(
                                          _stopping
                                              ? 'Stopping...'
                                              : 'Stop Sharing',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 26,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _videoBusy ? null : _toggleLiveVideo,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 150),
                              opacity: _videoBusy ? 0.72 : 1,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 15, horizontal: 18),
                                decoration: BoxDecoration(
                                  color: _liveVideoEnabled
                                      ? const Color(0xFF006972)
                                      : const Color(0xFF003461),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_liveVideoEnabled
                                              ? const Color(0xFF006972)
                                              : const Color(0xFF003461))
                                          .withValues(alpha: 0.22),
                                      blurRadius: 18,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_videoBusy)
                                      const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    else
                                      Icon(
                                        _liveVideoEnabled
                                            ? Icons.videocam_rounded
                                            : Icons.videocam_off_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        _videoBusy
                                            ? (_liveVideoEnabled
                                                ? 'Stopping camera...'
                                                : 'Starting camera...')
                                            : (_liveVideoEnabled
                                                ? 'Stop Transmission'
                                                : 'Start Transmission'),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_liveVideoEnabled) ...[
                          const SizedBox(width: 12),
                          if (_previewVisible)
                            ValueListenableBuilder<LiveVideoPreviewState>(
                              valueListenable: widget.liveVideoPreview,
                              builder: (_, preview, __) =>
                                  _buildCameraPreview(preview),
                            )
                          else
                            _buildSwitchCameraButton(),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Share link again button
                  GestureDetector(
                    onTap: _shareLink,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF003461).withValues(alpha: 0.10),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color:
                              const Color(0xFF003461).withValues(alpha: 0.12),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF003461)
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.share_rounded,
                                color: Color(0xFF003461), size: 18),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Share Link Again',
                            style: TextStyle(
                              color: Color(0xFF003461),
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_liveVideoEnabled && _previewVisible && _previewExpanded)
              ValueListenableBuilder<LiveVideoPreviewState>(
                valueListenable: widget.liveVideoPreview,
                builder: (_, preview, __) => _buildExpandedPreview(preview),
              ),
          ],
        ),
      ),
    );
  }
}
