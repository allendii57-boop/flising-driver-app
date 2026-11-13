import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';

class LiveMap extends StatefulWidget {
  final LatLng? destination;
  final String? destinationLabel;

  const LiveMap({super.key, this.destination, this.destinationLabel});

  @override
  State<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<LiveMap> {
  GoogleMapController? _mapController;
  LatLng _myLocation = const LatLng(-2.6741, 141.3028);
  double _myHeading = 0.0;
  bool _isLoadingLocation = true;
  bool _isLoadingRoute = false;

  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  Marker? _destMarker;
  LatLng? _activeTarget;
  String? _lastRouteKey;
  BitmapDescriptor? _carIcon;
  StreamSubscription<Position>? _posStream;
  StreamSubscription<DatabaseEvent>? _rideStream;

  final Color flisingOrange = const Color(0xFFE9692C);
  final Color darkSurface = const Color(0xFF1C1C1E);

  @override
  void initState() {
    super.initState();
    _loadCarIcon();
    _goToMyLocation();
    _startLiveTracking();
    _watchActiveRideRoute();
  }

  @override
  void dispose() {
    _posStream?.cancel();
    _rideStream?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadCarIcon() async {
    _carIcon = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(64, 64)),
      "assets/images/map_marker.png",
    );
    if (mounted) _setDriverMarker(_myLocation, _myHeading);
  }

  void _watchActiveRideRoute() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final db = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    _rideStream = db
        .child('rides')
        .orderByChild('assignedDriverId')
        .equalTo(uid)
        .onValue
        .listen((event) {
      if (!mounted) return;
      LatLng? target;
      String? label;
      double hue = BitmapDescriptor.hueRed;
      String? rideStatus;
      String? rideId;

      if (event.snapshot.exists && event.snapshot.value is Map) {
        final rides = event.snapshot.value as Map;
        int bestTs = -1;
        rides.forEach((k, v) {
          if (v is Map && (v['status'] == 'ACCEPTED' || v['status'] == 'IN_PROGRESS')) {
            final ts = v['timestamp'] is num ? (v['timestamp'] as num).toInt() : 0;
            if (ts > bestTs) {
              bestTs = ts;
              rideId = k.toString();
              rideStatus = v['status'].toString();
              if (rideStatus == 'ACCEPTED') {
                final lat = v['pickupLat'];
                final lng = v['pickupLng'];
                if (lat is num && lng is num) {
                  target = LatLng(lat.toDouble(), lng.toDouble());
                  label = 'Pickup: ${v['pickupText'] ?? 'Passenger'}';
                  hue = BitmapDescriptor.hueGreen;
                }
              } else if (rideStatus == 'IN_PROGRESS') {
                final lat = v['dropoffLat'];
                final lng = v['dropoffLng'];
                if (lat is num && lng is num) {
                  target = LatLng(lat.toDouble(), lng.toDouble());
                  label = 'Dropoff: ${v['dropoffText'] ?? 'Destination'}';
                  hue = BitmapDescriptor.hueRed;
                }
              }
            }
          }
        });
      }

      if (target == null && widget.destination != null) {
        target = widget.destination;
        label = widget.destinationLabel ?? 'Destination';
      }

      if (target == null) {
        if (_polylines.isNotEmpty || _destMarker != null) {
          setState(() {
            _polylines = {};
            _destMarker = null;
            _activeTarget = null;
            _lastRouteKey = null;
          });
          _setDriverMarker(_myLocation, _myHeading);
        }
        return;
      }

      final routeKey = '${rideId ?? "custom"}_${rideStatus ?? ""}_${target!.latitude}_${target!.longitude}';
      if (_lastRouteKey != routeKey) {
        _lastRouteKey = routeKey;
        _activeTarget = target;
        _drawRoute(_myLocation, target!, label: label, pinHue: hue);
      }
    });
  }

  void _startLiveTracking() {
    _posStream = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "Flising Driver Active",
          notificationText: "Sharing live location with your passenger",
          enableWakeLock: true,
        ),
      ),
    ).listen((pos) {
      final here = LatLng(pos.latitude, pos.longitude);
      _myLocation = here;
      _myHeading = pos.heading;
      _setDriverMarker(here, pos.heading);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: 'https://flising-default-rtdb.asia-southeast1.firebasedatabase.app',
        ).ref('drivers/$uid').update({
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'heading': pos.heading,
        });
      }
      if (_activeTarget == null) {
        _mapController?.animateCamera(CameraUpdate.newLatLng(here));
      }
    });
  }

  Future<void> _goToMyLocation() async {
    setState(() => _isLoadingLocation = true);

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        _showSnack('Location permission denied.');
        setState(() => _isLoadingLocation = false);
        return;
      }
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final myPos = LatLng(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() {
        _myLocation = myPos;
        _myHeading = position.heading;
        _isLoadingLocation = false;
      });

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: myPos, zoom: 15.0),
        ),
      );

      if (_activeTarget != null) {
        await _drawRoute(myPos, _activeTarget!);
      } else if (widget.destination != null) {
        await _drawRoute(myPos, widget.destination!, label: widget.destinationLabel);
      } else {
        _setDriverMarker(myPos, position.heading);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingLocation = false);
      _showSnack('Error getting location: $e');
    }
  }

  void _setDriverMarker(LatLng pos, [double heading = 0]) {
    if (!mounted) return;
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId("driver"),
          position: pos,
          icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          rotation: heading,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          infoWindow: const InfoWindow(title: "You"),
        ),
        if (_destMarker != null) _destMarker!,
      };
    });
  }

  Future<void> _drawRoute(
    LatLng origin,
    LatLng destination, {
    String? label,
    double pinHue = BitmapDescriptor.hueRed,
  }) async {
    if (!mounted) return;
    setState(() => _isLoadingRoute = true);

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=polyline',
      );

      final response = await http.get(url);
      final data = json.decode(response.body);

      if (data['code'] == 'Ok' && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
        final points = data['routes'][0]['geometry'] as String;
        final polylineCoords = _decodePolyline(points);

        double minLat = [origin.latitude, destination.latitude, ...polylineCoords.map((p) => p.latitude)].reduce((a, b) => a < b ? a : b);
        double maxLat = [origin.latitude, destination.latitude, ...polylineCoords.map((p) => p.latitude)].reduce((a, b) => a > b ? a : b);
        double minLng = [origin.longitude, destination.longitude, ...polylineCoords.map((p) => p.longitude)].reduce((a, b) => a < b ? a : b);
        double maxLng = [origin.longitude, destination.longitude, ...polylineCoords.map((p) => p.longitude)].reduce((a, b) => a > b ? a : b);

        _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLat, minLng),
              northeast: LatLng(maxLat, maxLng),
            ),
            80,
          ),
        );

        _destMarker = Marker(
          markerId: const MarkerId('destination'),
          position: destination,
          icon: BitmapDescriptor.defaultMarkerWithHue(pinHue),
          infoWindow: InfoWindow(title: label ?? widget.destinationLabel ?? 'Destination'),
        );

        if (mounted) {
          setState(() {
            _polylines = {
              Polyline(
                polylineId: const PolylineId('route'),
                points: polylineCoords,
                color: flisingOrange,
                width: 5,
              ),
            };
          });
          _setDriverMarker(origin, _myHeading);
        }
      } else {
        _setDriverMarker(origin, _myHeading);
      }
    } catch (_) {
      _setDriverMarker(origin, _myHeading);
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFFD32F2F),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _myLocation,
              zoom: 14.0,
            ),
            onMapCreated: (controller) => _mapController = controller,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: _markers,
            polylines: _polylines,
          ),
          if (_isLoadingLocation || _isLoadingRoute)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 80.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: darkSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: flisingOrange.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: flisingOrange, strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isLoadingRoute ? "Getting road route..." : "Acquiring GPS...",
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 20.0, right: 10.0),
        child: FloatingActionButton(
          onPressed: _goToMyLocation,
          backgroundColor: darkSurface,
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: flisingOrange.withOpacity(0.5), width: 1.5),
          ),
          child: Icon(Icons.my_location, color: flisingOrange, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
