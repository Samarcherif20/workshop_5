import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'connectivity_service.dart';
import 'queue_provider.dart';
import 'room_list_screen.dart'; // N'oubliez pas d'importer RoomListScreen

// MAIN
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  // Supabase initialization
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(
    MultiProvider(
      providers: [
        // Connectivity service
        ChangeNotifierProvider(
          create: (_) => ConnectivityService(),
        ),

        // Queue provider that depends on connectivity
        ChangeNotifierProxyProvider<ConnectivityService, QueueProvider>(
          create: (_) => QueueProvider(),
          update: (_, connectivity, queue) =>
              queue!..setConnectivity(connectivity),
        ),
      ],
      child: const WaitingRoomApp(),
    ),
  );
}

// APP ROOT
class WaitingRoomApp extends StatelessWidget {
  const WaitingRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waiting Room',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const WaitingRoomScreen(),
    );
  }
}

// WAITING ROOM SCREEN
class WaitingRoomScreen extends StatefulWidget {
  const WaitingRoomScreen({super.key});

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final connectivityService = context.watch<ConnectivityService>();
    final provider = context.watch<QueueProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Waiting Room'),
        actions: [
          // BOUTON POUR VOIR TOUTES LES SALLES
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () {
              // Navigation vers l'écran des salles
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RoomListScreen(),
                ),
              );
            },
            tooltip: 'Voir toutes les salles',
          ),
        ],
      ),
      body: Column(
        children: [
          // Offline Banner
          if (!connectivityService.isOnline)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red[800],
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Offline Mode - Data will sync when connected.',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),

          // Main content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Input Row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration:
                              const InputDecoration(hintText: 'Enter name'),
                          onSubmitted: (name) {
                            if (name.isNotEmpty) {
                              provider.addClient(name);
                              _controller.clear();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          if (_controller.text.isNotEmpty) {
                            provider.addClient(_controller.text);
                            _controller.clear();
                          }
                        },
                        child: const Text('Add'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Client List
                  Expanded(
                    child: provider.clients.isEmpty
                        ? const Center(child: Text('No one in queue yet...'))
                        : ListView.builder(
                            itemCount: provider.clients.length,
                            itemBuilder: (context, index) {
                              final client = provider.clients[index];

                              final name = client.name ?? 'No name';
                              final lat = client.lat;
                              final lng = client.lng;
                              final isSynced = client.isSynced ?? false;

                              return Card(
                                margin:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: CircleAvatar(
                                      child: Text('${index + 1}')),
                                  title: Text(name),
                                  subtitle: Text(
                                    (lat != null && lng != null)
                                        ? '📍 ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
                                        : '📍 Position non capturée',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isSynced
                                            ? Icons.cloud_done
                                            : Icons.cloud_upload,
                                        color: isSynced
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete,
                                            color: Colors.red),
                                        onPressed: () {
                                          provider.removeClient(client.id);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // Next Client Button
                  ElevatedButton.icon(
                    onPressed: provider.nextClient,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next Client'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}