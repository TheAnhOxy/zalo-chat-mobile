import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';
import 'auth_service.dart';

enum CallState { idle, calling, incoming, connected, ended }

typedef IncomingCallData = void Function(Map<String, dynamic> data);

class CallService {
  final List<RTCIceCandidate> _remoteCandidatesQueue = [];
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  bool _hasRemoteDescription = false;
  CallState _state = CallState.idle;

  String? _currentCallId;
  String? _currentConversationId;

  bool _isStartingCall = false; // ✅ chống gọi trùng

  CallState get state => _state;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  final List<void Function(CallState)> _stateListeners = [];
  IncomingCallData? onIncomingCall;
  void Function(MediaStream)? onRemoteStream;

  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  void init() {
    socketService.off('incoming_call');
    socketService.off('call_answered');
    socketService.off('ice_candidate');
    socketService.off('call_ended');
    socketService.off('call_rejected');
    socketService.off('call_created'); // ✅ thêm

    socketService.on('incoming_call', (data) {
      onIncomingCall?.call(Map<String, dynamic>.from(data as Map));
    });

    // ✅ nhận callId từ BE
    socketService.on('call_created', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      _currentCallId = map['callId']?.toString();
      dev.log('📞 Received callId: $_currentCallId');
    });

    socketService.on('call_answered', (data) async {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final answer = RTCSessionDescription(
          map['answer']['sdp'],
          map['answer']['type'],
        );
        await _pc?.setRemoteDescription(answer);
        _hasRemoteDescription = true;

        for (final c in _remoteCandidatesQueue) {
          await _pc?.addCandidate(c);
        }
        _remoteCandidatesQueue.clear();
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

        if (!_hasRemoteDescription) {
          _remoteCandidatesQueue.add(candidate);
        } else {
          await _pc?.addCandidate(candidate);
        }
      } catch (e) {
        dev.log('❌ ICE error: $e');
      }
    });

    socketService.on('call_ended', (_) {
      _cleanUp();
      _setState(CallState.ended);
    });

    socketService.on('call_rejected', (_) {
      _cleanUp();
      _setState(CallState.ended);
    });
  }

  Future<String?> startCall({
    required String conversationId,
    required String calleeId,
    bool isVideo = false,
  }) async {
    // ✅ chống spam / gọi 2 lần
    if (_isStartingCall) return null;
    _isStartingCall = true;

    try {
      _currentConversationId = conversationId;

      await _createPeerConnection(isVideo: isVideo);
      await _getLocalStream(isVideo: isVideo);

      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);

      // ❌ ĐÃ XOÁ createCall API ở đây

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

  Future<void> answerCall({
    required String conversationId,
    required String callId,
    required Map<String, dynamic> offer,
    bool isVideo = false,
  }) async {
    try {
      _currentConversationId = conversationId;
      _currentCallId = callId;

      await _createPeerConnection(isVideo: isVideo);
      await _getLocalStream(isVideo: isVideo);

      final remoteDesc = RTCSessionDescription(offer['sdp'], offer['type']);
      await _pc!.setRemoteDescription(remoteDesc);
      _hasRemoteDescription = true;

      for (final c in _remoteCandidatesQueue) {
        await _pc?.addCandidate(c);
      }
      _remoteCandidatesQueue.clear();

      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);

      socketService.emit('answer_call', {
        'conversationId': conversationId,
        'callId': callId,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
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

    _setState(CallState.ended);

    if (_currentCallId != null && _currentConversationId != null) {
      socketService.emit('end_call', {
        'callId': _currentCallId!,
        'conversationId': _currentConversationId!,
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

  Future<void> _createPeerConnection({bool isVideo = false}) async {
    _pc = await createPeerConnection(_iceConfig);

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;

      socketService.emit('ice_candidate', {
        'conversationId': _currentConversationId,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (_currentCallId != null) {
          socketService.emit('call_connected', {'callId': _currentCallId});
        }
        _setState(CallState.connected);
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        endCall();
      }
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);

        if (_state == CallState.calling) {
          _setState(CallState.connected);
        }
      }
    };
  }

  Future<void> _getLocalStream({bool isVideo = false}) async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': isVideo ? {'facingMode': 'user'} : false,
      });
      _localStream!.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));
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

    _pc?.close();
    _pc = null;

    _currentCallId = null;
    _currentConversationId = null;

    _state = CallState.idle;
    _hasRemoteDescription = false;
    _remoteCandidatesQueue.clear();
  }

  void dispose() {
    socketService.off('incoming_call');
    socketService.off('call_answered');
    socketService.off('ice_candidate');
    socketService.off('call_ended');
    socketService.off('call_rejected');
    socketService.off('call_created');
    _cleanUp();
  }
}

final callService = CallService();
