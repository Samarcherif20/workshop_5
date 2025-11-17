import 'package:geolocator/geolocator.dart';

class GeolocationService {
  Future<Position?> getCurrentPosition() async {
    print('🔍 Checking permissions...');
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('❌ Permission denied');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('❌ Permission denied forever');
      return null;
    }

    print('✅ Permission granted');

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('❌ Location services disabled');
      return null;
    }
    print('✅ Location services enabled');

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20), // timeout élargi
      );
      print('✅ Position obtained: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('❌ Geolocation error: $e');
      return null;
    }
  }
}
