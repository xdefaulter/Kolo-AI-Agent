import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import '../tool_base.dart';

/// Get current device GPS location.
class LocationTool extends KoloTool {
  @override
  String get name => 'location';
  @override
  String get description => 'Get the current GPS coordinates (latitude, longitude) and address details of the device.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'accuracy': {'type': 'string', 'enum': ['low', 'medium', 'high'], 'description': 'Location accuracy (default medium)'},
    },
    'required': [],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final accuracyStr = params['accuracy'] as String? ?? 'medium';
    final accuracy = switch (accuracyStr) {
      'low' => LocationAccuracy.low,
      'high' => LocationAccuracy.high,
      _ => LocationAccuracy.medium,
    };

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return ToolResult.err('Location services are disabled. Please enable GPS.');
      }

      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return ToolResult.err('Location permission denied by user.');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return ToolResult.err('Location permission permanently denied. Enable in app settings.');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
      );

      // Try reverse geocoding for approximate address
      String? address;
      try {
        final placemarks = await geocoding.placemarkFromCoordinates(
          position.latitude, position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          address = '${p.street ?? ""} ${p.locality ?? ""}, ${p.administrativeArea ?? ""} ${p.country ?? ""}'.trim();
        }
      } catch (_) {
        // Reverse geocoding may fail — that's fine
      }

      final result = StringBuffer();
      result.writeln('Latitude: ${position.latitude}');
      result.writeln('Longitude: ${position.longitude}');
      result.writeln('Accuracy: ${position.accuracy.toStringAsFixed(1)}m');
      result.writeln('Altitude: ${position.altitude.toStringAsFixed(1)}m');
      result.writeln('Speed: ${position.speed.toStringAsFixed(1)} m/s');
      result.writeln('Timestamp: ${position.timestamp?.toIso8601String() ?? "N/A"}');
      if (address != null) result.writeln('Approximate address: $address');

      return ToolResult.ok(result.toString(), metadata: {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'address': address,
      });
    } catch (e) {
      return ToolResult.err('Location failed: $e');
    }
  }
}