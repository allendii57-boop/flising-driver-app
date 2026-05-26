import 'package:flutter/material.dart';

class CallScreen extends StatelessWidget {
  final String rideId;
  final String callerType;
  final String otherPersonName;
  final String? otherPersonPhoto;

  const CallScreen({
    super.key,
    required this.rideId,
    required this.callerType,
    required this.otherPersonName,
    this.otherPersonPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('Call with $otherPersonName')),
    );
  }
}
