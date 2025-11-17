class Client {
  final String id;
  final String? name;
  final DateTime createdAt;
  final double? lat;
  final double? lng;
  final bool isSynced;

  Client({
    required this.id,
    this.name,
    required this.createdAt,
    this.lat,
    this.lng,
    this.isSynced = false,
  });

  factory Client.fromMap(Map<String, dynamic> map) {
    return Client(
      id: (map['id'] ?? '').toString(),
      name: map['name'],
      createdAt: map['created_at'] is String
          ? DateTime.parse(map['created_at'])
          : (map['created_at'] ?? DateTime.now()),
      lat: map['lat'] is num ? (map['lat'] as num).toDouble() : null,
      lng: map['lng'] is num ? (map['lng'] as num).toDouble() : null,
      isSynced: (map['is_synced'] == 1 || map['is_synced'] == true),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        'lat': lat,
        'lng': lng,
        'is_synced': isSynced ? 1 : 0,
      };
}
