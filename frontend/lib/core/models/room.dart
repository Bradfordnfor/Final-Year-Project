class Room {
  final int id;
  final String name;
  final int capacity;
  final String roomType;
  final bool isActive;
  final int buildingId;

  const Room({
    required this.id, required this.name, required this.capacity,
    required this.roomType, required this.isActive, required this.buildingId,
  });

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        id: json['id'] as int,
        name: json['name'] as String,
        capacity: json['capacity'] as int,
        roomType: json['room_type'] as String,
        isActive: json['is_active'] as bool,
        buildingId: json['building_id'] as int,
      );
}
