import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LiveMap extends StatefulWidget {
  // Pass these when showing a route to pickup/dropoff
  final LatLng? destination;
  final String? destinationLabel;

  const LiveMap({super.key, this.destination, this.destinationLabel});

  @override
  State<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<LiveMap> {
  GoogleMapController? _mapController;
  LatLng _myLocation = const LatLng(-2.6741, 141.3028);
  bool _isLoadingLocation = true;
  bool _isLoadingRoute = false;

  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  BitmapDescriptor? _carIcon;

  Future<void> _loadCarIcon() async {
    _carIcon = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(64, 64)),
      "assets/images/map_marker.png",
    );
    if (mounted) setState(() {});
  }

  final Color flisingOrange = const Color(0xFFE9692C);
  final Color darkSurface = const Color(0xFF1C1C1E);

  // YOUR GOOGLE MAPS API KEY
  static const String _apiKey = 'AIzaSyCLZjxEEPtXycS2meKlSlhyk_x2gn9daBo';

  @override
  void initState() {
    super.initState();
    _loadCarIcon();
    _goToMyLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
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
        _isLoadingLocation = false;
      });

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: myPos, zoom: 15.0),
        ),
      );

      // If a destination was passed, draw the route!
      if (widget.destination != null) {
        await _drawRoute(myPos, widget.destination!);
      } else {
        _setDriverMarker(myPos);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingLocation = false);
      _showSnack('Error getting location: $e');
    }
  }

  void _setDriverMarker(LatLng pos) {
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('driver'),
          position: pos,
          icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: const InfoWindow(title: 'You'),
        ),
      };
    });
  }

  Future<void> _drawRoute(LatLng origin, LatLng destination) async {
    setState(() => _isLoadingRoute = true);

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&key=$_apiKey',
      );

      final response = await http.get(url);
      final data = json.decode(response.body);

      if (data['status'] == 'OK') {
        final points = data['routes'][0]['overview_polyline']['points'];
        final polylineCoords = _decodePolyline(points);

        // Fit the map to show both points
        final bounds = LatLngBounds(
          southwest: LatLng(
            [origin.latitude, destination.latitude].reduce((a, b) => a < b ? a : b),
            [origin.longitude, destination.longitude].reduce((a, b) => a < b ? a : b),
          ),
          northeast: LatLng(
            [origin.latitude, destination.latitude].reduce((a, b) => a > b ? a : b),
            [origin.longitude, destination.longitude].reduce((a, b) => a > b ? a : b),
          ),
        );

        _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 80),
        );

        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              points: polylineCoords,
              color: flisingOrange,
              width: 5,
            ),
          };
          _markers = {
            Marker(
              markerId: const MarkerId('driver'),
              position: origin,
              icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
              infoWindow: const InfoWindow(title: 'You'),
            ),
            Marker(
              markerId: const MarkerId('destination'),
              position: destination,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed),
              infoWindow: InfoWindow(
                  title: widget.destinationLabel ?? 'Destination'),
            ),
          };
        });
      } else {
        _showSnack('Could not get directions: ${data['status']}');
        _setDriverMarker(origin);
      }
    } catch (e) {
      _showSnack('Route error: $e');
      _setDriverMarker(origin);
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  // Decodes Google's encoded polyline format
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

          // GPS pill
          if (_isLoadingLocation || _isLoadingRoute)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 80.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: darkSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: flisingOrange.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: flisingOrange, strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isLoadingRoute
                              ? "Getting route..."
                              : "Acquiring GPS...",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
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
            side: BorderSide(
                color: flisingOrange.withOpacity(0.5), width: 1.5),
          ),
          child: Icon(Icons.my_location, color: flisingOrange, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
