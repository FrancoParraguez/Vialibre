// lib/models/location_model.dart

import 'package:equatable/equatable.dart';

class LocationModel extends Equatable {
  final String id;
  final String ownerId;       // uid del usuario o id del vehículo
  final double lat;
  final double lng;
  final double speedKmh;      // velocidad en km/h
  final double? heading;      // dirección en grados (0-360)
  final double? accuracy;     // precisión del GPS en metros
  final DateTime timestamp;

  const LocationModel({
    required this.id,
    required this.ownerId,
    required this.lat,
    required this.lng,
    required this.speedKmh,
    this.heading,
    this.accuracy,
    required this.timestamp,
  });

  factory LocationModel.fromMap(Map<String, dynamic> map) {
    return LocationModel(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      speedKmh: (map['speed_kmh'] as num).toDouble(),
      heading: (map['heading'] as num?)?.toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'owner_id': ownerId,
    'lat': lat,
    'lng': lng,
    'speed_kmh': speedKmh,
    'heading': heading,
    'accuracy': accuracy,
    'timestamp': timestamp.toIso8601String(),
  };

  @override
  List<Object?> get props => [id, ownerId, lat, lng, speedKmh, timestamp];
}
