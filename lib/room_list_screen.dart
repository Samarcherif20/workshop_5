import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'queue_provider.dart';

class RoomListScreen extends StatelessWidget {
  const RoomListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QueueProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Toutes les salles'),
      ),
      body: provider.rooms.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: provider.rooms.length,
              itemBuilder: (context, index) {
                final room = provider.rooms[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: const Icon(Icons.meeting_room, size: 40),
                    title: Text(room['name'] ?? 'Sans nom'),
                    subtitle: Text(
                      '📍 ${room['latitude']?.toStringAsFixed(4)}, ${room['longitude']?.toStringAsFixed(4)}',
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      // Option: navigation vers détail de la salle
                      // Navigator.push(...);
                    },
                  ),
                );
              },
            ),
    );
  }
}