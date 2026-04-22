import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';
import 'auth_service.dart';

enum CallState { idle, calling, incoming, connected, ended }

typedef IncomingCallData = void Function(Map<String, dynamic> data);
typedef ParticipantLeftData = void Function(Map<String, dynamic> data);
typedef CallStartedData = void Function(Map<String, dynamic> data);

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  RTCPeerConnection? _pc;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStream? _mixedRemoteStream;
  final Map<String, List<RTCIceCandidate>> _pendingRemoteCandidates = {};
  final Map<String, bool> _peerHasRemoteDescription = {};
  bool _hasRemoteDescription = false;
  CallState _state = CallState.idle;

  String? _currentCallId;
  String? _currentConversationId;
  String? _currentCallerId;
  String? _currentPeerId;
  bool _pendingRejectBeforeCallId = false;
  String? _pendingRejectConversationId;

  bool _isStartingCall = false; // ✅ chống gọi trùng
  bool _isGroupCall = false;
  bool _callConnectedEmitted = false; // ✅ Chỉ emit call_connected một lần

  CallState get state => _state;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  final List<void Function(CallState)> _stateListeners = [];
  IncomingCallData? onIncomingCall;
  ParticipantLeftData? onParticipantLeft;
  CallStartedData? onCallStarted;
  void Function(MediaStream)? onRemoteStream;

  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  Map<String, dynamic> _sdpReceiveConstraints(bool isVideo) => {
    'offerToReceiveAudio': true,
    'offerToReceiveVideo': isVideo,
  };

  RTCSessionDescription _preferVp8Codec(RTCSessionDescription desc) {
    final sdp = desc.sdp;
    if (sdp == null || sdp.isEmpty) return desc;

    final lines = sdp.split('\r\n');
    int? mVideoIndex;
    final vp8Payloads = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('m=video ')) {
        mVideoIndex = i;
      }
      final match = RegExp(r'^a=rtpmap:(\d+) VP8\/\d+', caseSensitive: false)
          .firstMatch(line);
      if (match != null) {
        vp8Payloads.add(match.group(1)!);
      }
    }

    if (mVideoIndex == null || vp8Payloads.isEmpty) return desc;

    final mParts = lines[mVideoIndex].split(' ');
    if (mParts.length <= 3) return desc;

    final header = mParts.sublist(0, 3);
    final payloads = mParts.sublist(3);
    final preferred = <String>[];
    final rest = <String>[];

    for (final p in payloads) {
      if (vp8Payloads.contains(p)) {
        preferred.add(p);
      } else {
        rest.add(p);
      }
    }

    lines[mVideoIndex] = [...header, ...preferred, ...rest].join(' ');
    return RTCSessionDescription(lines.join('\r\n'), desc.type);
  }

  String _candidateType(String? rawCandidate) {
    if (rawCandidate == null || rawCandidate.isEmpty) return 'unknown';
    final parts = rawCandidate.split(' ');
    final idx = parts.indexOf('typ');
    if (idx >= 0 && idx + 1 < parts.length) {
      return parts[idx + 1];
    }
    return 'unknown';
  }

  void init() {
    socketService.off('incoming_call');
    socketService.off('call_answered');
    socketService.off('ice_candidate');
    socketService.off('call_ended');
    socketService.off('call_rejected');
    socketService.off('call_created'); // ✅ thêm
    socketService.off('participant_left'); // ✅ thêm
    socketService.off('call_started'); // ✅ thêm

    socketService.on('incoming_call', (data) {
      _setState(CallState.incoming);
      onIncomingCall?.call(Map<String, dynamic>.from(data as Map));
    });

    // ✅ nhận callId từ BE
    socketService.on('call_created', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      _currentCallId = map['callId']?.toString();
      dev.log('📞 Received callId: $_currentCallId');

      final createdConversationId = map['conversationId']?.toString();
      final canFlushPendingEnd =
          _pendingRejectBeforeCallId &&
          _currentCallId != null &&
          _currentCallId!.isNotEmpty &&
          _pendingRejectConversationId != null &&
          (createdConversationId == null ||
              createdConversationId.isEmpty ||
              createdConversationId == _pendingRejectConversationId);

      if (canFlushPendingEnd) {
        socketService.emit('reject_call', {
          'callId': _currentCallId!,
          'conversationId': _pendingRejectConversationId!,
        });
        _pendingRejectBeforeCallId = false;
        _pendingRejectConversationId = null;
      }
    });

    socketService.on('call_answered', (data) async {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final responderId = map['responderId']?.toString();
        final peerId = responderId ?? _currentPeerId;
        final pc = peerId != null ? _peerConnections[peerId] : _pc;

        dev.log(
          '📩 call_answered received: peer=$peerId responder=$responderId target=${map['targetId']} source=${map['sourceId']}',
        );

        if (pc == null) {
          dev.log(
            '❌ call_answered received but no peer connection found for $peerId',
          );
          return;
        }

        final answer = RTCSessionDescription(
          map['answer']['sdp'],
          map['answer']['type'],
        );
        dev.log(
          '🧾 setRemoteDescription(answer): peer=$peerId type=${answer.type} sdpLen=${answer.sdp?.length ?? 0}',
        );
        await pc.setRemoteDescription(answer);
        _peerHasRemoteDescription[peerId ?? 'default'] = true;

        final pending = _pendingRemoteCandidates[peerId] ?? [];
        dev.log('🧊 flushing pending ICE: peer=$peerId count=${pending.length}');
        for (final c in pending) {
          await pc.addCandidate(c);
        }
        _pendingRemoteCandidates.remove(peerId);
      } catch (e) {
        dev.log('❌ call_answered error: $e');
      }
    });

    socketService.on('ice_candidate', (data) async {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final candidate = RTCIceCandidate(
          map['candidate'],
          map['sdpMid'],
          map['sdpMLineIndex'],
        );
        final sourceId = map['sourceId']?.toString();
        final targetId = map['targetId']?.toString();
        final peerId = sourceId ?? targetId ?? _currentPeerId;
        final cType = _candidateType(candidate.candidate);

        dev.log(
          '📩 ICE received: peer=$peerId type=$cType source=$sourceId target=$targetId',
        );

        if (targetId != null && targetId != authService.userId) {
          dev.log('↪️ ICE ignored (target mismatch): myId=${authService.userId} target=$targetId');
          return;
        }

        final pc = peerId != null ? _peerConnections[peerId] : _pc;
        if (pc == null) {
          _pendingRemoteCandidates
              .putIfAbsent(peerId ?? 'default', () => [])
              .add(candidate);
              dev.log('🧊 ICE queued (pc missing): peer=$peerId');
          return;
        }

        final hasRemote =
            _peerHasRemoteDescription[peerId] ?? _hasRemoteDescription;
        if (!hasRemote) {
          _pendingRemoteCandidates
              .putIfAbsent(peerId ?? 'default', () => [])
              .add(candidate);
          dev.log('🧊 ICE queued (no remoteDescription yet): peer=$peerId');
        } else {
          await pc.addCandidate(candidate);
          dev.log('🧊 ICE added immediately: peer=$peerId type=$cType');
        }
      } catch (e) {
        dev.log('❌ ICE error: $e');
      }
    });

    socketService.on('call_ended', (_) {
      _cleanUp();
      _setState(CallState.ended);
    });

    socketService.on('call_rejected', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      final groupReject = map['isGroup'] == true;
      if (groupReject) {
        dev.log('📞 Group call participant rejected: ${map['rejecterId']}');
        return;
      }
      _cleanUp();
      _setState(CallState.ended);
    });

    // ✅ Xử lý khi 1 người rời khỏi cuộc gọi nhóm (call vẫn tiếp tục nếu còn 2+ người)
    socketService.on('participant_left', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      dev.log('👤 Participant left: ${map['userId']}, Remaining: ${map['activeParticipantsCount']}');
      onParticipantLeft?.call(map);
    });
    // ✅ Đồng bộ thời gian cuộc gọi từ server
    socketService.on('call_started', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      dev.log('⏱️ Call started (sync timer): ${map['startedAt']}');
      onCallStarted?.call(map);
    });  }

  Future<String?> startCall({
    required String conversationId,
    required String calleeId,
    bool isVideo = false,
  }) async {
    if (_isStartingCall) return null;
    _isStartingCall = true;

    try {
      _currentConversationId = conversationId;
      _currentCallerId = authService.userId;
      _currentPeerId = calleeId;
      _isGroupCall = false;

      await _getLocalStream(isVideo: isVideo);
      final pc = await _createPeerConnection(calleeId, isVideo: isVideo);

      var offer = await pc.createOffer(_sdpReceiveConstraints(isVideo));
      offer = _preferVp8Codec(offer);
      dev.log(
        '🧾 createOffer(caller): peer=$calleeId video=$isVideo type=${offer.type} sdpLen=${offer.sdp?.length ?? 0}',
      );
      await pc.setLocalDescription(offer);

      socketService.emit('start_call', {
        'callDto': {
          'conversationId': conversationId,
          'callerId': authService.userId!,
          'callerName': authService.currentUser?.fullName ?? '',
          'callerAvatar': authService.currentUser?.avatar ?? '',
          'participants': [calleeId],
          'type': isVideo ? 'VIDEO' : 'VOICE',
        },
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });

      _setState(CallState.calling);
      return null;
    } catch (e) {
      dev.log('❌ startCall error: $e');
      _cleanUp();
      return null;
    } finally {
      _isStartingCall = false;
    }
  }

  Future<String?> startGroupCall({
    required String conversationId,
    required List<String> participantIds,
    bool isVideo = false,
  }) async {
    if (_isStartingCall) return null;
    _isStartingCall = true;

    try {
      _currentConversationId = conversationId;
      _currentCallerId = authService.userId;
      _isGroupCall = true;

      await _getLocalStream(isVideo: isVideo);
      final offers = <Map<String, dynamic>>[];

      for (final participantId in participantIds) {
        final pc = await _createPeerConnection(participantId, isVideo: isVideo);
        var offer = await pc.createOffer(_sdpReceiveConstraints(isVideo));
        offer = _preferVp8Codec(offer);
        dev.log(
          '🧾 createOffer(group-caller): peer=$participantId video=$isVideo type=${offer.type} sdpLen=${offer.sdp?.length ?? 0}',
        );
        await pc.setLocalDescription(offer);

        offers.add({
          'targetId': participantId,
          'offer': {'sdp': offer.sdp, 'type': offer.type},
        });
      }

      socketService.emit('start_call', {
        'callDto': {
          'conversationId': conversationId,
          'callerId': authService.userId!,
          'callerName': authService.currentUser?.fullName ?? '',
          'callerAvatar': authService.currentUser?.avatar ?? '',
          'participants': participantIds,
          'type': isVideo ? 'VIDEO' : 'VOICE',
        },
        'offers': offers,
      });

      _setState(CallState.calling);
      return null;
    } catch (e) {
      dev.log('❌ startGroupCall error: $e');
      _cleanUp();
      return null;
    } finally {
      _isStartingCall = false;
    }
  }

  Future<void> answerCall({
    required String conversationId,
    required String callId,
    required String peerId,
    required Map<String, dynamic> offer,
    bool isVideo = false,
    bool isGroup = false,
  }) async {
    try {
      _currentConversationId = conversationId;
      _currentCallId = callId;
      _currentPeerId = peerId;
      _currentCallerId = peerId;
      _isGroupCall = isGroup;

      await _getLocalStream(isVideo: isVideo);
      final pc = await _createPeerConnection(peerId, isVideo: isVideo);

      final remoteDesc = RTCSessionDescription(offer['sdp'], offer['type']);
      dev.log(
        '🧾 setRemoteDescription(offer): peer=$peerId video=$isVideo type=${remoteDesc.type} sdpLen=${remoteDesc.sdp?.length ?? 0}',
      );
      await pc.setRemoteDescription(remoteDesc);
      _peerHasRemoteDescription[peerId] = true;

      final pending = _pendingRemoteCandidates[peerId] ?? [];
      for (final c in pending) {
        await pc.addCandidate(c);
      }
      _pendingRemoteCandidates.remove(peerId);

      var answer = await pc.createAnswer(_sdpReceiveConstraints(isVideo));
      answer = _preferVp8Codec(answer);
      dev.log(
        '🧾 createAnswer(callee): peer=$peerId video=$isVideo type=${answer.type} sdpLen=${answer.sdp?.length ?? 0}',
      );
      await pc.setLocalDescription(answer);

      socketService.emit('answer_call', {
        'conversationId': conversationId,
        'callId': callId,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'targetId': peerId,
        'sourceId': authService.userId,
      });

      _setState(CallState.calling);
    } catch (e) {
      dev.log('❌ answerCall error: $e');
      _cleanUp();
    }
  }

  void rejectCall({required String callId, required String conversationId}) {
    socketService.emit('reject_call', {
      'callId': callId,
      'conversationId': conversationId,
    });
    _cleanUp();
    _setState(CallState.ended);
  }

  void endCall() {
    if (_state == CallState.ended) return;
    final wasConnected = _state == CallState.connected;

    _setState(CallState.ended);

    if (_currentCallId != null && _currentConversationId != null) {
      if (wasConnected) {
        socketService.emit('end_call', {
          'callId': _currentCallId!,
          'conversationId': _currentConversationId!,
        });
      } else {
        socketService.emit('reject_call', {
          'callId': _currentCallId!,
          'conversationId': _currentConversationId!,
        });
      }
    } else if (_currentConversationId != null && !wasConnected) {
      // Caller tắt trước khi connected và trước khi có callId:
      // emit reject sớm theo conversation để callee đóng incoming,
      // rồi flush reject_call có callId khi call_created về.
      _pendingRejectBeforeCallId = true;
      _pendingRejectConversationId = _currentConversationId;
      socketService.emit('reject_call', {
        'conversationId': _currentConversationId!,
        'callerId': authService.userId,
      });
    } else if (_currentConversationId != null) {
      socketService.emit('end_call', {
        'conversationId': _currentConversationId!,
        'callerId': authService.userId,
      });
    }

    _cleanUp();
  }

  // ✅ Rời khỏi cuộc gọi nhóm (nhưng call vẫn tiếp tục nếu còn 2+ người)
  void leaveCall() {
    if (!_isGroupCall) {
      endCall();
      return;
    }

    dev.log('📞 Leaving group call...');

    if (_currentCallId != null && _currentConversationId != null) {
      socketService.emit('leave_call', {
        'callId': _currentCallId!,
        'conversationId': _currentConversationId!,
        'userId': authService.userId,
      });
    }

    _cleanUp();
  }

  void toggleMute(bool mute) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !mute);
  }

  void toggleSpeaker(bool speaker) {
    if (!kIsWeb) Helper.setSpeakerphoneOn(speaker);
  }

  Future<RTCPeerConnection> _createPeerConnection(
    String peerId, {
    bool isVideo = false,
  }) async {
    final pc = await createPeerConnection(_iceConfig);
    _peerConnections[peerId] = pc;
    _pc = pc;
    _peerHasRemoteDescription[peerId] = false;
    _pendingRemoteCandidates.putIfAbsent(peerId, () => []);

    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;

      final cType = _candidateType(candidate.candidate);
      dev.log('📤 ICE send: peer=$peerId type=$cType mid=${candidate.sdpMid}');

      socketService.emit('ice_candidate', {
        'conversationId': _currentConversationId,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'targetId': peerId,
        'sourceId': authService.userId,
      });
    };

    pc.onConnectionState = (state) {
      dev.log('📡 connectionState: peer=$peerId state=$state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        // ✅ Emit call_connected chỉ lần đầu tiên
        if (!_callConnectedEmitted && _currentCallId != null && _currentConversationId != null) {
          _callConnectedEmitted = true;
          socketService.emit('call_connected', {
            'callId': _currentCallId,
            'conversationId': _currentConversationId,
            'userId': authService.userId,
          });
        }
        // ✅ Chỉ transition tới connected nếu chưa connected
        if (_state != CallState.connected) {
          _setState(CallState.connected);
        }
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        // ✅ Group call: một kết nối P2P bị lỗi ≠ kết thúc toàn bộ call
        // Chỉ end call nếu là 1-1 call hoặc người dùng tự click leave
        if (!_isGroupCall) {
          endCall();
        }
      }
    };

    pc.onIceConnectionState = (state) {
      dev.log('🧊 iceConnectionState: peer=$peerId state=$state');
    };

    pc.onIceGatheringState = (state) {
      dev.log('🧊 iceGatheringState: peer=$peerId state=$state');
    };

    pc.onSignalingState = (state) {
      dev.log('📶 signalingState: peer=$peerId state=$state');
    };

    pc.onTrack = (event) async {
      dev.log(
        '🎬 onTrack: peer=$peerId kind=${event.track.kind} streams=${event.streams.length}',
      );
      MediaStream? stream;

      if (event.streams.isNotEmpty) {
        stream = event.streams[0];
      } else {
        try {
          final fallbackStream = await createLocalMediaStream(
            'remote_${peerId}_${event.track.id}',
          );
          await fallbackStream.addTrack(event.track);
          stream = fallbackStream;
          dev.log('ℹ️ onTrack fallback stream created for peer $peerId');
        } catch (e) {
          dev.log('❌ onTrack fallback failed for peer $peerId: $e');
          return;
        }
      }

      _remoteStream = stream;
      if (!_isGroupCall) {
        onRemoteStream?.call(stream);

        if (_state == CallState.calling) {
          // ✅ onTrack cũng có thể emit call_connected nếu onConnectionState chưa emit
          if (!_callConnectedEmitted && _currentCallId != null && _currentConversationId != null) {
            _callConnectedEmitted = true;
            socketService.emit('call_connected', {
              'callId': _currentCallId,
              'conversationId': _currentConversationId,
              'userId': authService.userId,
            });
          }
          _setState(CallState.connected);
        }
        return;
      }

      if (_mixedRemoteStream == null) {
        try {
          _mixedRemoteStream = await createLocalMediaStream('mixed_remote');
        } catch (_) {
          _mixedRemoteStream = null;
        }
      }

      if (_mixedRemoteStream != null) {
        for (final track in stream.getTracks()) {
          if (!_mixedRemoteStream!.getTracks().any((t) => t.id == track.id)) {
            await _mixedRemoteStream!.addTrack(track);
          }
        }
        onRemoteStream?.call(_mixedRemoteStream!);
      } else {
        onRemoteStream?.call(_remoteStream!);
      }

      if (_state == CallState.calling) {
        // ✅ onTrack cũng có thể emit call_connected nếu onConnectionState chưa emit
        if (!_callConnectedEmitted && _currentCallId != null && _currentConversationId != null) {
          _callConnectedEmitted = true;
          socketService.emit('call_connected', {
            'callId': _currentCallId,
            'conversationId': _currentConversationId,
            'userId': authService.userId,
          });
        }
        _setState(CallState.connected);
      }
    };

    // Fallback for platforms where remote media is delivered via onAddStream.
    pc.onAddStream = (stream) {
      dev.log(
        '🎬 onAddStream: peer=$peerId tracks=${stream.getTracks().length}',
      );
      _remoteStream = stream;

      if (!_isGroupCall) {
        onRemoteStream?.call(stream);
      } else {
        onRemoteStream?.call(stream);
      }

      if (_state == CallState.calling) {
        if (!_callConnectedEmitted &&
            _currentCallId != null &&
            _currentConversationId != null) {
          _callConnectedEmitted = true;
          socketService.emit('call_connected', {
            'callId': _currentCallId,
            'conversationId': _currentConversationId,
            'userId': authService.userId,
          });
        }
        _setState(CallState.connected);
      }
    };

    return pc;
  }

  Future<void> _getLocalStream({bool isVideo = false}) async {
    if (_localStream != null) return;

    try {
      if (isVideo) {
        try {
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': {'facingMode': 'user'},
          });
        } catch (e) {
          dev.log('⚠️ getUserMedia facingMode failed, retry generic video: $e');
          try {
            _localStream = await navigator.mediaDevices.getUserMedia({
              'audio': true,
              'video': true,
            });
          } catch (e2) {
            dev.log('⚠️ getUserMedia video failed, fallback audio-only: $e2');
            _localStream = await navigator.mediaDevices.getUserMedia({
              'audio': true,
              'video': false,
            });
          }
        }
      } else {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
      }

      _peerConnections.values.forEach((pc) {
        _localStream!.getTracks().forEach(
          (track) => pc.addTrack(track, _localStream!),
        );
      });
    } catch (e) {
      dev.log('❌ getUserMedia error: $e');
    }
  }

  void addStateListener(void Function(CallState) listener) {
    _stateListeners.add(listener);
  }

  void removeStateListener(void Function(CallState) listener) {
    _stateListeners.remove(listener);
  }

  void _setState(CallState s) {
    _state = s;
    for (final listener in List.from(_stateListeners)) {
      listener(s);
    }
  }

  void _cleanUp() {
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;

    _remoteStream?.dispose();
    _remoteStream = null;

    _mixedRemoteStream?.dispose();
    _mixedRemoteStream = null;

    for (final pc in _peerConnections.values) {
      pc.close();
    }
    _peerConnections.clear();
    _peerHasRemoteDescription.clear();
    _pendingRemoteCandidates.clear();

    _pc?.close();
    _pc = null;

    _currentCallId = null;
    _currentConversationId = null;
    _currentCallerId = null;
    _currentPeerId = null;
    _isGroupCall = false;
    _callConnectedEmitted = false; // ✅ Reset flag

    _state = CallState.idle;
    _hasRemoteDescription = false;
  }

  void dispose() {
    socketService.off('incoming_call');
    socketService.off('call_answered');
    socketService.off('ice_candidate');
    socketService.off('call_ended');
    socketService.off('call_rejected');
    socketService.off('call_created');
    socketService.off('participant_left');
    socketService.off('call_started');
    _cleanUp();
  }
}

final callService = CallService();
