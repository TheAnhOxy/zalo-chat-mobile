import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';
import 'auth_service.dart';

enum CallState { idle, calling, incoming, connected, ended }

typedef IncomingCallData = void Function(Map<String, dynamic> data);
typedef ParticipantJoinedData = void Function(Map<String, dynamic> data);
typedef ParticipantLeftData = void Function(Map<String, dynamic> data);
typedef CallStartedData = void Function(Map<String, dynamic> data);
typedef PeerRemoteStreamData = void Function(String peerId, MediaStream stream);

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
  bool _callMediaIsVideo = false; // Cuộc gọi VIDEO dù local không có cam
  bool _callConnectedEmitted = false; // ✅ Chỉ emit call_connected một lần

  CallState get state => _state;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  String? get currentCallId => _currentCallId;

  final List<void Function(CallState)> _stateListeners = [];
  IncomingCallData? onIncomingCall;
  ParticipantJoinedData? onParticipantJoined;
  ParticipantLeftData? onParticipantLeft;
  CallStartedData? onCallStarted;
  void Function(MediaStream)? onRemoteStream;
  void Function(MediaStream)? onLocalStream;
  PeerRemoteStreamData? onPeerRemoteStream;

  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  String _peerKey(String? id) => (id ?? '').trim();

  RTCPeerConnection? _findPeerConnection(String peerId) {
    final key = _peerKey(peerId);
    if (key.isEmpty) return _pc;
    final direct = _peerConnections[key];
    if (direct != null) return direct;
    for (final entry in _peerConnections.entries) {
      if (entry.key == key) return entry.value;
      if (entry.key.endsWith(key) || key.endsWith(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

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
    socketService.off('participant_joined'); // ✅ thêm
    socketService.off('participant_left'); // ✅ thêm
    socketService.off('active_participants'); // ✅ thêm
    socketService.off('call_started'); // ✅ thêm
    socketService.off('call_offer'); // ✅ thêm

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

      if (_isGroupCall) {
        _emitCallConnectedIfReady();
      }
    });

    socketService.on('call_answered', (data) async {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final responderId = _peerKey(map['responderId']?.toString());
        final sourceId = _peerKey(map['sourceId']?.toString());
        final peerId = responderId.isNotEmpty
            ? responderId
            : (sourceId.isNotEmpty
                ? sourceId
                : _peerKey(_currentPeerId));
        final pc = _findPeerConnection(peerId);

        dev.log(
          '📩 call_answered received: peer=$peerId responder=$responderId target=${map['targetId']} source=${map['sourceId']}',
        );

        if (pc == null) {
          dev.log(
            '❌ call_answered: no PC for peer=$peerId keys=${_peerConnections.keys.toList()}',
          );
          return;
        }

        final answerMap = map['answer'];
        if (answerMap is! Map) {
          dev.log('❌ call_answered: missing answer payload');
          return;
        }
        final answerPayload = Map<String, dynamic>.from(answerMap);
        final answer = RTCSessionDescription(
          answerPayload['sdp']?.toString(),
          answerPayload['type']?.toString(),
        );
        dev.log(
          '🧾 setRemoteDescription(answer): peer=$peerId type=${answer.type} sdpLen=${answer.sdp?.length ?? 0}',
        );
        await pc.setRemoteDescription(answer);
        final peerKey = peerId.isNotEmpty ? peerId : 'default';
        _peerHasRemoteDescription[peerKey] = true;

        final pending = _pendingRemoteCandidates[peerKey] ?? [];
        dev.log('🧊 flushing pending ICE: peer=$peerKey count=${pending.length}');
        for (final c in pending) {
          await pc.addCandidate(c);
        }
        _pendingRemoteCandidates.remove(peerKey);

        if (_isGroupCall && peerKey.isNotEmpty) {
          await _pullRemoteTracksForPeer(peerKey);
        }
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
        final sourceId = _peerKey(map['sourceId']?.toString());
        final targetId = _peerKey(map['targetId']?.toString());
        final peerId = sourceId.isNotEmpty
            ? sourceId
            : (targetId.isNotEmpty ? targetId : _peerKey(_currentPeerId));
        final cType = _candidateType(candidate.candidate);

        dev.log(
          '📩 ICE received: peer=$peerId type=$cType source=$sourceId target=$targetId',
        );

        if (targetId.isNotEmpty && targetId != _peerKey(authService.userId)) {
          dev.log('↪️ ICE ignored (target mismatch): myId=${authService.userId} target=$targetId');
          return;
        }

        final pc = peerId.isNotEmpty ? _findPeerConnection(peerId) : _pc;
        if (pc == null) {
          _pendingRemoteCandidates
              .putIfAbsent(peerId.isNotEmpty ? peerId : 'default', () => [])
              .add(candidate);
              dev.log('🧊 ICE queued (pc missing): peer=$peerId');
          return;
        }

        final hasRemote =
            _peerHasRemoteDescription[peerId] ?? _hasRemoteDescription;
        if (!hasRemote) {
          _pendingRemoteCandidates
              .putIfAbsent(peerId.isNotEmpty ? peerId : 'default', () => [])
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

    socketService.on('participant_joined', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      dev.log(
        '👥 Participant joined: ${map['userId']}, Total: ${map['activeParticipantsCount']}',
      );
      onParticipantJoined?.call(map);

      final joinedId = _peerKey(map['userId']?.toString());
      if (_isGroupCall) {
        _ensureMeshToPeer(joinedId);
      }
    });

    // ✅ Xử lý khi 1 người rời khỏi cuộc gọi nhóm (call vẫn tiếp tục nếu còn 2+ người)
    socketService.on('participant_left', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      dev.log('👤 Participant left: ${map['userId']}, Remaining: ${map['activeParticipantsCount']}');
      onParticipantLeft?.call(map);
    });

    socketService.on('active_participants', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      final ids = ((map['activeParticipants'] as List?) ?? [])
          .map((id) => id?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      for (final raw in ids) {
        final id = _peerKey(raw);
        if (id.isEmpty || id == _peerKey(authService.userId)) continue;
        onParticipantJoined?.call({'userId': id});
        if (_isGroupCall) {
          _ensureMeshToPeer(id);
        }
      }
    });

    socketService.on('call_offer', (data) async {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final targetId = map['targetId']?.toString();
        if (targetId != null && targetId != authService.userId) return;

        final sourceId = _peerKey(map['sourceId']?.toString());
        if (sourceId.isEmpty || sourceId == _peerKey(authService.userId)) {
          return;
        }

        final offer = Map<String, dynamic>.from((map['offer'] as Map?) ?? {});
        final callId = map['callId']?.toString();
        await _answerPeerOffer(sourceId, offer, callId: callId);
      } catch (e) {
        dev.log('❌ call_offer error: $e');
      }
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
      _callMediaIsVideo = isVideo;

      await _getLocalStream(isVideo: isVideo);
      final offers = <Map<String, dynamic>>[];

      for (final rawId in participantIds) {
        final participantId = _peerKey(rawId);
        if (participantId.isEmpty) continue;
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

      final callIdCompleter = Completer<String?>();
      void onCallCreated(dynamic data) {
        try {
          final map = Map<String, dynamic>.from(data as Map);
          final id = map['callId']?.toString();
          if (id != null && id.isNotEmpty) {
            _currentCallId = id;
            if (!callIdCompleter.isCompleted) callIdCompleter.complete(id);
          }
        } catch (e) {
          if (!callIdCompleter.isCompleted) callIdCompleter.complete(null);
        }
      }

      socketService.on('call_created', onCallCreated);

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

      final callId = await callIdCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          dev.log('❌ startGroupCall: call_created timeout');
          return null;
        },
      );

      socketService.off('call_created', onCallCreated);

      if (callId == null) {
        _cleanUp();
        return null;
      }

      _currentCallId = callId;
      _emitCallConnectedIfReady();

      if (!kIsWeb) {
        Helper.setSpeakerphoneOn(true);
      }

      _setState(CallState.calling);
      return callId;
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
      if (isGroup && isVideo) _callMediaIsVideo = true;

      await _getLocalStream(isVideo: isVideo);
      final recvVideo = _wantsRecvVideo();
      final pc = await _createPeerConnection(peerId, isVideo: recvVideo);

      final remoteDesc = RTCSessionDescription(offer['sdp'], offer['type']);
      dev.log(
        '🧾 setRemoteDescription(offer): peer=$peerId video=$isVideo type=${remoteDesc.type} sdpLen=${remoteDesc.sdp?.length ?? 0}',
      );
      final peerKey = _peerKey(peerId);
      await pc.setRemoteDescription(remoteDesc);
      _peerHasRemoteDescription[peerKey] = true;

      final pending = _pendingRemoteCandidates[peerKey] ?? [];
      for (final c in pending) {
        await pc.addCandidate(c);
      }
      _pendingRemoteCandidates.remove(peerKey);

      var answer = await pc.createAnswer(_sdpReceiveConstraints(recvVideo));
      answer = _preferVp8Codec(answer);
      dev.log(
        '🧾 createAnswer(callee): peer=$peerKey video=$isVideo type=${answer.type} sdpLen=${answer.sdp?.length ?? 0}',
      );
      await pc.setLocalDescription(answer);

      socketService.emit('answer_call', {
        'conversationId': conversationId,
        'callId': callId,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'targetId': peerKey,
        'sourceId': authService.userId,
      });

      _setState(CallState.calling);
      if (isGroup) {
        _emitCallConnectedIfReady();
        await _pullRemoteTracksForPeer(peerKey);
      }
    } catch (e) {
      dev.log('❌ answerCall error: $e');
      _cleanUp();
    }
  }

  Future<void> joinGroupCall({
    required String conversationId,
    required String callId,
    bool isVideo = false,
  }) async {
    try {
      _currentConversationId = conversationId;
      _currentCallId = callId;
      _currentCallerId = authService.userId;
      _isGroupCall = true;
      _callMediaIsVideo = isVideo;

      await _getLocalStream(isVideo: isVideo);

      _emitCallConnectedIfReady();

      _setState(CallState.calling);
    } catch (e) {
      dev.log('❌ joinGroupCall error: $e');
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
    final key = _peerKey(peerId);
    final pc = await createPeerConnection(_iceConfig);
    _peerConnections[key] = pc;
    _pc = pc;
    _peerHasRemoteDescription[key] = false;
    _pendingRemoteCandidates.putIfAbsent(key, () => []);

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
        'targetId': key,
        'sourceId': authService.userId,
      });
    };

    pc.onConnectionState = (state) {
      dev.log('📡 connectionState: peer=$key state=$state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _emitCallConnectedIfReady();
        if (_isGroupCall) {
          _pullRemoteTracksForPeer(key);
        }
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
          _emitCallConnectedIfReady();
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

      onPeerRemoteStream?.call(key, stream);

      if (_state == CallState.calling) {
        _emitCallConnectedIfReady();
        _setState(CallState.connected);
      }
    };

    // Fallback for platforms where remote media is delivered via onAddStream.
    pc.onAddStream = (stream) {
      dev.log(
        '🎬 onAddStream: peer=$key tracks=${stream.getTracks().length}',
      );
      _remoteStream = stream;

      if (!_isGroupCall) {
        onRemoteStream?.call(stream);
      } else {
        onRemoteStream?.call(stream);
        onPeerRemoteStream?.call(key, stream);
      }

      if (_state == CallState.calling) {
        _emitCallConnectedIfReady();
        _setState(CallState.connected);
      }
    };

    return pc;
  }

  bool _isVideoCall() {
    return (_localStream?.getVideoTracks().isNotEmpty ?? false);
  }

  /// Nhận video từ remote khi đang trong cuộc VIDEO (kể cả máy không có cam).
  bool _wantsRecvVideo() => _callMediaIsVideo || _isVideoCall();

  bool _isPoliteTo(String peerKey) {
    final myId = _peerKey(authService.userId);
    if (myId.isEmpty || peerKey.isEmpty) return false;
    return myId.compareTo(peerKey) > 0;
  }

  /// Gom track từ receivers (Android/Web đôi khi onTrack không fire).
  Future<void> _pullRemoteTracksForPeer(String peerId) async {
    if (!_isGroupCall) return;
    final key = _peerKey(peerId);
    final pc = _peerConnections[key];
    if (pc == null) return;

    try {
      final receivers = await pc.getReceivers();
      if (receivers.isEmpty) return;

      final stream = await createLocalMediaStream('remote_pull_$key');
      for (final receiver in receivers) {
        final track = receiver.track;
        if (track == null) continue;
        final sameKind =
            stream.getTracks().where((t) => t.kind == track.kind).toList();
        for (final old in sameKind) {
          await stream.removeTrack(old);
        }
        await stream.addTrack(track);
      }

      if (stream.getTracks().isEmpty) return;
      dev.log(
        '[Mesh] pullRemoteTracks $key: ${stream.getTracks().map((t) => t.kind).toList()}',
      );
      onPeerRemoteStream?.call(key, stream);
    } catch (e) {
      dev.log('[Mesh] pullRemoteTracks($key) error: $e');
    }
  }

  void _emitCallConnectedIfReady() {
    if (_callConnectedEmitted) return;
    if (_currentCallId == null || _currentConversationId == null) return;
    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;

    _callConnectedEmitted = true;
    socketService.emit('call_connected', {
      'callId': _currentCallId,
      'conversationId': _currentConversationId,
      'userId': userId,
    });
    dev.log('📞 call_connected emitted: callId=$_currentCallId');
  }

  bool _shouldInitiateOfferWith(String peerId) {
    final key = _peerKey(peerId);
    if (key.isEmpty) return false;
    final myId = _peerKey(authService.userId);
    if (myId.isEmpty || myId == key) return false;
    return myId.compareTo(key) < 0;
  }

  /// Tạo kết nối mesh tới peer nếu chưa có PC.
  void _ensureMeshToPeer(String peerId) {
    final key = _peerKey(peerId);
    if (key.isEmpty || key == _peerKey(authService.userId)) return;
    if (_peerConnections.containsKey(key)) return;
    if (_shouldInitiateOfferWith(key)) {
      _createOfferForPeer(key);
    }
    // Retry mesh sau khi peer ổn định (tránh lúc thấy 1 người lúc thấy 2).
    Future.delayed(const Duration(seconds: 2), () async {
      if (!_isGroupCall) return;
      if (_peerConnections.containsKey(key)) {
        await _pullRemoteTracksForPeer(key);
        if (_peerHasRemoteDescription[key] != true &&
            _shouldInitiateOfferWith(key)) {
          final stuck = _peerConnections.remove(key);
          await stuck?.close();
          _peerHasRemoteDescription.remove(key);
          await _createOfferForPeer(key);
        }
        return;
      }
      if (_shouldInitiateOfferWith(key)) {
        await _createOfferForPeer(key);
      }
    });
  }

  Future<void> _createOfferForPeer(String peerId) async {
    try {
      final key = _peerKey(peerId);
      if (key.isEmpty || key == _peerKey(authService.userId)) return;
      if (!_isGroupCall) return;
      if (_currentConversationId == null || _currentConversationId!.isEmpty) {
        return;
      }
      if (_peerConnections.containsKey(key)) return;

      final recvVideo = _wantsRecvVideo();
      await _getLocalStream(isVideo: recvVideo);
      final pc = await _createPeerConnection(key, isVideo: recvVideo);

      var offer = await pc.createOffer(_sdpReceiveConstraints(recvVideo));
      offer = _preferVp8Codec(offer);
      await pc.setLocalDescription(offer);

      socketService.emit('call_offer', {
        'conversationId': _currentConversationId,
        'callId': _currentCallId,
        'targetId': key,
        'sourceId': authService.userId,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });
      dev.log('📤 call_offer sent to $key');
    } catch (e) {
      dev.log('❌ create offer for peer($peerId) error: $e');
    }
  }

  Future<void> _answerPeerOffer(
    String sourceId,
    Map<String, dynamic> offer, {
    String? callId,
  }) async {
    try {
      if (!_isGroupCall) return;
      final key = _peerKey(sourceId);
      if (key.isEmpty || key == _peerKey(authService.userId)) return;

      // Tránh glare chỉ khi đã có remote description (đã kết nối xong).
      if (_peerHasRemoteDescription[key] == true) {
        dev.log('↪️ Ignoring duplicate call_offer from $key (already connected)');
        return;
      }

      final existingPc = _peerConnections[key];
      if (existingPc != null) {
        final state = existingPc.signalingState;
        final waitingOurAnswer = state ==
                RTCSignalingState.RTCSignalingStateHaveLocalOffer ||
            state == RTCSignalingState.RTCSignalingStateHaveLocalPrAnswer;
        if (waitingOurAnswer && !_isPoliteTo(key)) {
          dev.log('↪️ Ignoring call_offer from $key — awaiting our offer answer');
          return;
        }
        if (waitingOurAnswer && _isPoliteTo(key)) {
          dev.log('🔄 Polite rollback for $key — accept incoming offer');
          await existingPc.close();
          _peerConnections.remove(key);
          _peerHasRemoteDescription.remove(key);
          _pendingRemoteCandidates.remove(key);
        }
      }

      final offerSdp = offer['sdp']?.toString() ?? '';
      final recvVideo = _wantsRecvVideo() || offerSdp.contains('m=video');

      _currentCallId ??= callId;
      await _getLocalStream(isVideo: recvVideo);

      final pc = _peerConnections[key] ??
          await _createPeerConnection(key, isVideo: recvVideo);

      final remoteDesc = RTCSessionDescription(
        offer['sdp']?.toString(),
        offer['type']?.toString(),
      );
      await pc.setRemoteDescription(remoteDesc);
      _peerHasRemoteDescription[key] = true;

      final pending = _pendingRemoteCandidates[key] ?? [];
      for (final c in pending) {
        await pc.addCandidate(c);
      }
      _pendingRemoteCandidates.remove(key);

      var answer = await pc.createAnswer(_sdpReceiveConstraints(recvVideo));
      answer = _preferVp8Codec(answer);
      await pc.setLocalDescription(answer);

      socketService.emit('answer_call', {
        'conversationId': _currentConversationId,
        'callId': _currentCallId,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'targetId': key,
        'sourceId': authService.userId,
      });
      dev.log('📤 mesh answer sent to $key');
      await _pullRemoteTracksForPeer(key);
    } catch (e) {
      dev.log('❌ answer peer offer($sourceId) error: $e');
    }
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

      for (final pc in _peerConnections.values) {
        for (final track in _localStream!.getTracks()) {
          pc.addTrack(track, _localStream!);
        }
      }

      onLocalStream?.call(_localStream!);
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
    _callMediaIsVideo = false;
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
    socketService.off('participant_joined');
    socketService.off('participant_left');
    socketService.off('active_participants');
    socketService.off('call_started');
    socketService.off('call_offer');
    _cleanUp();
  }
}

final callService = CallService();
