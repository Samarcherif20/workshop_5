import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'queue_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => QueueProvider(),
      child: const WaitingRoomApp(),
    ),
  );
}

class WaitingRoomApp extends StatelessWidget {
  const WaitingRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QueueProvider>();
    final controller = TextEditingController();

    return MaterialApp(
      title: 'Waiting Room',
      home: Scaffold(
        appBar: AppBar(title: const Text('Waiting Room')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: const InputDecoration(hintText: 'Enter name'),
                      onSubmitted: (name) {
                        provider.addClient(name);
                        controller.clear();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      provider.addClient(controller.text);
                      controller.clear();
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: provider.clients.isEmpty
                    ? const Center(child: Text('No one in queue yet...'))
                    : ListView.builder(
                        itemCount: provider.clients.length,
                        itemBuilder: (context, index) {
                          final client = provider.clients[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(client.name),
                              subtitle: Text(
                                client.createdAt.toLocal().toString().split(' ')[0],
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => provider.removeClient(client.id),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              ElevatedButton.icon(
                onPressed: provider.nextClient,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Next Client'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
