import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'agora_config.dart';

Future<void>? _agoraShutdown;

Future<void> _shutdownEngine(RtcEngine eng) async {
  try { await eng.leaveChannel(); } catch (_) {}
  try { await eng.release(); } catch (_) {}
}

class DriverCallScreen extends StatefulWidget {
  final String rideId;
  final String otherPersonName;
  final String? otherPersonPhoto;
  final bool isIncoming;

  const DriverCallScreen({
    super.key,
    required this.rideId,
    required this.otherPersonName,
    this.otherPersonPhoto,
    this.isIncoming = false,
  });

  @override
  State<DriverCallScreen> createState() => _DriverCallScreenState();
}

class _DriverCallScreenState extends State<DriverCallScreen> {
  RtcEngine? _engine;
  String _step = 'start';

  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isConnected = false;
  bool _isConnecting = true;
  bool _otherPersonJoined = false;

  int _callDurationSeconds = 0;
  bool _hasPopped = false;
  void _safePop() {
    if (_hasPopped || !mounted) return;
    _hasPopped = true;
    if (Navigator.canPop(context)) _safePop();
  }
  Timer? _callTimer;
  StreamSubscription<DatabaseEvent>? _callSignalListener;

  final Color flisingOrange = const Color(0xFFE9692C);
  final Color darkSurface = const Color(0xFF1C1C1E);

  late DatabaseReference _callRef;

  @override
  void initState() {
    super.initState();
    _callRef = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app').ref('rides/${widget.rideId}/call');
    _initCall();
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _callSignalListener?.cancel();
    final eng = _engine; _engine = null;
    if (eng != null) _agoraShutdown = _shutdownEngine(eng);
    super.dispose();
  }

  Future<void> _initCall() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is required for calls'),
            backgroundColor: Colors.red,
          ),
        );
        _safePop();
      }
      return;
    }

    if (widget.isIncoming) {
      await _callRef.update({'status': 'ANSWERED'});
    } else await _callRef.set({
      'status': 'CALLING',
      'callerType': 'driver',
      'channel': widget.rideId,
      'timestamp': ServerValue.timestamp,
    });

    _callSignalListener = _callRef.onValue.listen((event) {
      if (!event.snapshot.exists || !mounted) return;
      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final status = data['status'] as String? ?? '';

      if (status == 'DECLINED' || status == 'ENDED') {
        _endCall(byRemote: true);
      }
    });

    await _setupAgora();
  }

  Future<void> _setupAgora() async {
    try {
      if (_agoraShutdown != null) await _agoraShutdown;
      _engine = createAgoraRtcEngine();
      _step = 'initialize'; await _engine!.initialize(RtcEngineContext(appId: agoraAppId));

      _step = 'setChannelProfile'; await _engine!.setChannelProfile(
        ChannelProfileType.channelProfileCommunication,
      );
      _step = 'setClientRole'; await _engine!.setClientRole(
        role: ClientRoleType.clientRoleBroadcaster,
      );
      _step = 'enableAudio'; await _engine!.enableAudio();
      _step = 'setDefaultAudioRouteToSpeakerphone'; await _engine!.setDefaultAudioRouteToSpeakerphone(_isSpeakerOn);

      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            if (mounted) {
              setState(() {
                _isConnecting = false;
                _isConnected = true;
              });
            }
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (mounted) {
              setState(() => _otherPersonJoined = true);
              _startCallTimer();
            }
          },
          onUserOffline: (connection, remoteUid, reason) {
            _endCall(byRemote: true);
          },
          onLeaveChannel: (connection, stats) {
            if (mounted) {
              setState(() => _isConnected = false);
            }
          },
          onError: (err, msg) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Call error: $msg'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
      );

      _step = 'joinChannel'; await _engine!.joinChannel(
        token: '',
        channelId: widget.rideId,
        uid: 0,
        options: const ChannelMediaOptions(
          autoSubscribeAudio: true,
          publishMicrophoneTrack: true,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed at $_step: $e'),
            backgroundColor: Colors.red,
          ),
        );
        _safePop();
      }
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callDurationSeconds++);
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _engine?.muteLocalAudioStream(_isMuted);
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    _engine?.setEnableSpeakerphone(_isSpeakerOn);
  }

  Future<void> _endCall({bool byRemote = false}) async {
    _callTimer?.cancel();
    _callSignalListener?.cancel();

    try {
      await _callRef.update({'status': 'ENDED'});
    } catch (_) {}

    final eng = _engine; _engine = null;
    if (eng != null) { _agoraShutdown = _shutdownEngine(eng); await _agoraShutdown; }

    _safePop();
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: darkSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Driver Call',
                    style: TextStyle(
                      color: flisingOrange,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            const Spacer(),
            CircleAvatar(
              radius: 64,
              backgroundColor: flisingOrange.withOpacity(0.15),
              backgroundImage: widget.otherPersonPhoto != null
                  ? NetworkImage(widget.otherPersonPhoto!)
                  : null,
              child: widget.otherPersonPhoto == null
                  ? Icon(Icons.person, size: 64, color: flisingOrange)
                  : null,
            ),
            const SizedBox(height: 24),
            Text(
              widget.otherPersonName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isConnecting
                  ? 'Calling passenger...'
                  : _otherPersonJoined
                      ? _formatDuration(_callDurationSeconds)
                      : 'Waiting for answer...',
              style: TextStyle(
                color: _otherPersonJoined ? Colors.greenAccent : Colors.white54,
                fontSize: 16,
              ),
            ),
            if (_isConnecting) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: flisingOrange,
                ),
              ),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _controlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    color: _isMuted ? Colors.white : darkSurface,
                    iconColor: _isMuted ? Colors.black : Colors.white,
                    onTap: _toggleMute,
                  ),
                  GestureDetector(
                    onTap: _endCall,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.4),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  _controlButton(
                    icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                    label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                    color: _isSpeakerOn ? flisingOrange : darkSurface,
                    iconColor: Colors.white,
                    onTap: _toggleSpeaker,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}
