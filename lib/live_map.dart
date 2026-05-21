import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class LiveMap extends StatefulWidget {
  const LiveMap({super.key});

  @override
  State<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<LiveMap> {
  final MapController _mapController = MapController();
  // Defaults to Vanimo!
  LatLng _taxiLocation = const LatLng(-2.6741, 141.3028);
  bool _isLoadingLocation = true; 

  // Premium Theme Colors
  final Color flisingOrange = const Color(0xFFE9692C);
  final Color darkSurface = const Color(0xFF1C1C1E);

  @override
  void initState() {
    super.initState();
    _goToMyLocation();
  }

  Future<void> _goToMyLocation() async {
    setState(() { _isLoadingLocation = true; });
    
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission denied. Cannot track ride.', style: TextStyle(color: Colors.white)),
            backgroundColor: Color(0xFFD32F2F),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() { _isLoadingLocation = false; });
        return;
      }
    }

    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng myPosition = LatLng(position.latitude, position.longitude);
      
      if (!mounted) return;
      setState(() {
        _taxiLocation = myPosition;
        _isLoadingLocation = false;
      });
      
      // Flies the camera to you smoothly!
      _mapController.move(myPosition, 16.0);
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoadingLocation = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error getting location: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFD32F2F),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Keeps edges dark so it blends with menus
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _taxiLocation,
              initialZoom: 14.0,
            ),
            children: [
              // --- THE CLASSIC BRIGHT MAP TILES ---
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.flising.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _taxiLocation,
                    width: 70,
                    height: 70,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Soft orange glow behind the taxi
                        Container(
                          width: 45,
                          height: 45,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: flisingOrange.withOpacity(0.2),
                          ),
                        ),
                        // Inner solid circle
                        Container(
                          width: 25,
                          height: 25,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: flisingOrange.withOpacity(0.5),
                          ),
                        ),
                        // The actual taxi icon
                        Icon(Icons.local_taxi, color: flisingOrange, size: 35),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          // --- GPS ACQUIRING PILL ---
          if (_isLoadingLocation)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 80.0), // Pushed down so it doesn't block your Online/Offline toggle!
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: darkSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: flisingOrange.withOpacity(0.5)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: flisingOrange, strokeWidth: 2)),
                        const SizedBox(width: 10),
                        const Text("Acquiring GPS...", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      
      // --- PREMIUM SNAP-TO-CENTER BUTTON ---
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