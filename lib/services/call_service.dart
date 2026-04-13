import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';
import 'auth_service.dart';
import 'api_service.dart';

enum CallState { idle, calling, incoming, connected, ended }

typedef IncomingCallData = void Function(Map<String, dynamic> data);

class CallService {
  List<RTCIceCandidate> _remoteCandidatesQueue = [];
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

  CallState get state => _state;
  String? get currentCallId => _currentCallId;
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
    // Off trước để tránh đăng ký trùng
    socketService.off('incoming_call');
    socketService.off('call_answered');
    socketService.off('ice_candidate');
    socketService.off('call_ended');
    socketService.off('call_rejected');

    socketService.on('incoming_call', (data) {
      print('📞 Incoming call: $data');
      onIncomingCall?.call(Map<String, dynamic>.from(data as Map));
    });

    socketService.on('call_answered', (data) async {
      print('✅ Call answered - setting remote description');
      final map = Map<String, dynamic>.from(data as Map);
      final answer = RTCSessionDescription(
        map['answer']['sdp'],
        map['answer']['type'],
      );
      await _pc?.setRemoteDescription(answer);
      _hasRemoteDescription = true;

      // ✅ Flush ICE queue
      try {
        for (var c in _remoteCandidatesQueue) {
          await _pc?.addCandidate(c);
        }
        _remoteCandidatesQueue.clear();
        print('✅ Flushed ICE queue (caller)');
      } catch (e) {
        print('❌ Error flushing ICE queue (caller): $e');
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

        // ❗ FIX: nếu chưa set remoteDescription → queue lại
        if (!_hasRemoteDescription) {
          print('⏳ Queue ICE because remoteDescription is not set yet');
          _remoteCandidatesQueue.add(candidate);
        } else {
          await _pc?.addCandidate(candidate);
          print('✅ ICE added');
        }
      } catch (e) {
        print('❌ ICE error: $e');
      }
    });

    socketService.on('call_ended', (_) {
      print('📵 Call ended by remote');
      _cleanUp();
      _setState(CallState.ended);
    });

    socketService.on('call_rejected', (_) {
      print('❌ Call rejected');
      _cleanUp();
      _setState(CallState.ended);
    });
  }

  Future<String?> startCall({
    required String conversationId,
    required String calleeId,
    bool isVideo = false,
  }) async {
    dev.log(
      '🚀 Starting call to $calleeId, conversation: $conversationId, isVideo: $isVideo',
    );
    try {
      _currentConversationId = conversationId;
      dev.log('🔧 Creating PeerConnection');
      await _createPeerConnection(isVideo: isVideo);
      dev.log('🎤 Getting local stream');
      await _getLocalStream(isVideo: isVideo);

      dev.log('💾 Creating call record on server');
      final callRecord = await apiService.createCall(
        conversationId: conversationId,
        callerId: authService.userId!,
        participants: [calleeId],
        type: isVideo ? 'VIDEO' : 'VOICE',
      );
      _currentCallId = callRecord['_id']?.toString();
      dev.log('✅ Call record created: $_currentCallId');

      dev.log('📡 Creating offer');
      final offer = await _pc!.createOffer();
      dev.log('📡 Setting local description');
      await _pc!.setLocalDescription(offer);

      dev.log('📤 Emitting start_call');
      socketService.emit('start_call', {
        'callDto': {
          'conversationId': conversationId,
          'callerId': authService.userId!,
          'participants': [calleeId],
          'type': isVideo ? 'VIDEO' : 'VOICE',
        },
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });

      dev.log('📞 Setting state to calling');
      _setState(CallState.calling);
      return _currentCallId;
    } catch (e) {
      dev.log('❌ startCall error: $e');
      _cleanUp();
      return null;
    }
  }

  Future<void> answerCall({
    required String conversationId,
    required String callId,
    required Map<String, dynamic> offer,
    bool isVideo = false,
  }) async {
    dev.log(
      '📞 Answering call $callId, conversation: $conversationId, isVideo: $isVideo',
    );
    try {
      _currentConversationId = conversationId;
      _currentCallId = callId;

      dev.log('🔧 Creating PeerConnection for answer');
      await _createPeerConnection(isVideo: isVideo);
      dev.log('🎤 Getting local stream for answer');
      await _getLocalStream(isVideo: isVideo);

      dev.log('📡 Setting remote description from offer');
      final remoteDesc = RTCSessionDescription(offer['sdp'], offer['type']);
      await _pc!.setRemoteDescription(remoteDesc);
      _hasRemoteDescription = true;

      // ✅ Flush ICE queue
      try {
        for (var c in _remoteCandidatesQueue) {
          await _pc?.addCandidate(c);
        }
        _remoteCandidatesQueue.clear();
        print('✅ Flushed ICE queue (callee)');
      } catch (e) {
        print('❌ Error flushing ICE queue (callee): $e');
      }

      dev.log('📡 Creating answer');
      final answer = await _pc!.createAnswer();
      dev.log('📡 Setting local description for answer');
      await _pc!.setLocalDescription(answer);

      dev.log('📤 Emitting answer_call');
      socketService.emit('answer_call', {
        'conversationId': conversationId,
        'callId': callId,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      });

      dev.log('📤 Sent answer_call: $callId');
      dev.log('📞 Setting state to calling after answer');
      _setState(CallState.calling);
    } catch (e) {
      dev.log('❌ answerCall error: $e');
      _cleanUp();
    }
  }

  void rejectCall({required String callId, required String conversationId}) {
    dev.log('❌ Rejecting call $callId');
    socketService.emit('reject_call', {
      'callId': callId,
      'conversationId': conversationId,
    });
    _cleanUp();
    _setState(CallState.ended);
  }

  void endCall() {
    dev.log('📵 Ending call $_currentCallId');
    if (_currentCallId != null && _currentConversationId != null) {
      dev.log('📤 Emitting end_call');
      socketService.emit('end_call', {
        'callId': _currentCallId!,
        'conversationId': _currentConversationId!,
      });
    }
    _cleanUp();
    _setState(CallState.ended);
  }

  void toggleMute(bool mute) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !mute);
  }

  void toggleSpeaker(bool speaker) {
    if (!kIsWeb) Helper.setSpeakerphoneOn(speaker);
  }

  Future<void> _createPeerConnection({bool isVideo = false}) async {
    dev.log('🔧 Creating RTCPeerConnection');
    _pc = await createPeerConnection(_iceConfig);
    dev.log('✅ PeerConnection created');

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      dev.log('🧊 ICE candidate generated: ${candidate.candidate}');
      // ✅ FIX: gửi flat object, không lồng nhau
      socketService.emit('ice_candidate', {
        'conversationId': _currentConversationId,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
      dev.log('🧊 ICE sent: ${candidate.candidate}');
    };

    _pc!.onConnectionState = (state) {
      print('🔗 PeerConnection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateNew) {
        print('🔗 State: New');
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
        print('🔗 State: Connecting');
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        print('✅ WebRTC Connected, setting state to connected');
        if (_currentCallId != null) {
          socketService.emit('call_connected', {'callId': _currentCallId});
        }
        _setState(CallState.connected);
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        print('🔗 State: Disconnected');
        endCall();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        print('❌ State: Failed');
        endCall();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        print('🔗 State: Closed');
      }
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        dev.log('🎵 Remote track received, setting remote stream');
        _remoteStream = event.streams[0];
        onRemoteStream?.call(
          _remoteStream!,
        ); // Force connected if still calling (fallback for web)
        if (_state == CallState.calling) {
          print('🎵 Forcing state to connected on track received');
          _setState(CallState.connected);
        }
      }
    };
  }

  Future<void> _getLocalStream({bool isVideo = false}) async {
    try {
      dev.log('🎤 Requesting user media: audio=true, video=$isVideo');
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': isVideo ? {'facingMode': 'user'} : false,
      });
      dev.log(
        '✅ Got local stream with ${_localStream!.getTracks().length} tracks',
      );
      _localStream!.getTracks().forEach((track) {
        dev.log('🎤 Adding track: ${track.kind} - ${track.id}');
        _pc!.addTrack(track, _localStream!);
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
    dev.log('📞 CallService state changing from $_state to $s');
    _state = s;
    for (final listener in List.from(_stateListeners)) {
      listener(s);
    }
  }

  void _cleanUp() {
    dev.log('🧹 Cleaning up call resources');
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
    dev.log('✅ Cleanup completed');
  }

  void dispose() {
    socketService.off('incoming_call');
    socketService.off('call_answered');
    socketService.off('ice_candidate');
    socketService.off('call_ended');
    socketService.off('call_rejected');
    _cleanUp();
  }
}

final callService = CallService();
