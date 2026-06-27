import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveVideoPreviewState {
  final livekit.LocalVideoTrack? track;
  final livekit.CameraPosition cameraPosition;
  final bool isStreaming;

  const LiveVideoPreviewState({
    required this.track,
    required this.cameraPosition,
    required this.isStreaming,
  });

  bool get isFrontCamera =>
      cameraPosition == livekit.CameraPosition.front;
}

class LiveVideoService {
  livekit.Room? _room;
  livekit.CameraPosition _cameraPosition = livekit.CameraPosition.back;
  final ValueNotifier<LiveVideoPreviewState> previewState =
      ValueNotifier<LiveVideoPreviewState>(
    const LiveVideoPreviewState(
      track: null,
      cameraPosition: livekit.CameraPosition.back,
      isStreaming: false,
    ),
  );

  bool get isStreaming => _room != null;
  bool get isFrontCamera => _cameraPosition == livekit.CameraPosition.front;

  livekit.LocalVideoTrack? get localVideoTrack {
    final publication = _room?.localParticipant
        ?.getTrackPublicationBySource(livekit.TrackSource.camera);
    final track = publication?.track;
    return track is livekit.LocalVideoTrack ? track : null;
  }

  void _notifyPreviewState() {
    previewState.value = LiveVideoPreviewState(
      track: localVideoTrack,
      cameraPosition: _cameraPosition,
      isStreaming: isStreaming,
    );
  }

  Future<void> start({
    required String sessionId,
    required String driverSecret,
  }) async {
    await stop();

    final response = await Supabase.instance.client.functions.invoke(
      'livekit-token',
      body: {
        'sessionId': sessionId,
        'role': 'driver',
        'driverSecret': driverSecret,
      },
    );

    if (response.status >= 400 || response.data is! Map) {
      throw StateError('LiveKit token request failed');
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    final url = data['url'] as String?;
    final token = data['token'] as String?;
    if (url == null || token == null) {
      throw StateError('Invalid LiveKit token response');
    }

    final room = livekit.Room(
      roomOptions: livekit.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultCameraCaptureOptions: livekit.CameraCaptureOptions(
          cameraPosition: _cameraPosition,
        ),
      ),
    );
    await room.connect(
      url,
      token,
    );

    try {
      await room.localParticipant?.setCameraEnabled(
        true,
        cameraCaptureOptions: livekit.CameraCaptureOptions(
          cameraPosition: _cameraPosition,
        ),
      );
    } catch (_) {
      await room.disconnect();
      rethrow;
    }

    _room = room;
    _notifyPreviewState();
  }

  Future<void> switchCamera() async {
    final room = _room;
    if (room == null) return;

    final nextPosition = _cameraPosition == livekit.CameraPosition.front
        ? livekit.CameraPosition.back
        : livekit.CameraPosition.front;

    final publication = room.localParticipant
        ?.getTrackPublicationBySource(livekit.TrackSource.camera);
    final track = publication?.track;
    if (track is livekit.LocalVideoTrack) {
      await track.setCameraPosition(nextPosition);
    } else {
      await room.localParticipant?.setCameraEnabled(
        true,
        cameraCaptureOptions: livekit.CameraCaptureOptions(
          cameraPosition: nextPosition,
        ),
      );
    }

    _cameraPosition = nextPosition;
    _notifyPreviewState();
  }

  Future<void> stop() async {
    final room = _room;
    _room = null;
    if (room == null) return;

    try {
      await room.localParticipant?.setCameraEnabled(false);
    } catch (_) {}

    try {
      await room.disconnect();
    } catch (_) {}

    try {
      await room.dispose();
    } catch (_) {}

    _notifyPreviewState();
  }

  void dispose() {
    previewState.dispose();
  }
}
