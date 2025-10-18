import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/client.dart';
import 'package:uuid/uuid.dart';
import 'local_queue_service.dart';
import 'geolocation_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';


class QueueProvider extends ChangeNotifier {
  final List<Client> _clients = [];
  List<Client> get clients => _clients;

  final SupabaseClient _supabase = Supabase.instance.client;
  final LocalQueueService _localDb = LocalQueueService();
  final GeolocationService _geoService;

  late RealtimeChannel _subscription;

  QueueProvider({GeolocationService? geoService})
      : _geoService = geoService ?? GeolocationService() {
    initialize();
  }

  Future<void> initialize() async {
    await _loadQueue();
    _setupRealtimeSubscription();
    _monitorConnectivity(); // ✅ start listening
  }

  Future<void> _loadQueue() async {
    final localClients = await _localDb.getClients();
    _clients
      ..clear()
      ..addAll(localClients.map((map) => Client.fromMap(map)));
    notifyListeners();

    await _syncLocalToRemote();
    await _fetchInitialClients();
  }

  Future<void> _syncLocalToRemote() async {
    final unsynced = await _localDb.getUnsyncedClients();
    for (var client in unsynced) {
      try {
        final remoteClient = Map<String, dynamic>.from(client)
        ..remove('is_synced') // remove SQLite integer
        ..['is_synced'] = true; // ✅ explicitly set to true
        print('Upserting to Supabase: $remoteClient');

final response = await _supabase
  .from('clients')
  .upsert(remoteClient, onConflict: 'id')
  .select();

print('Supabase response: $response');
        await _localDb.markClientAsSynced(client['id'] as String);
      } catch (e) {
        print('Sync failed for ${client['id']}: $e');
      }
    }
  }

  Future<void> _fetchInitialClients() async {
    try {
      final data =
          await _supabase.from('clients').select().order('created_at');
      _clients
        ..clear()
        ..addAll((data as List).map((e) => Client.fromMap(e)));
      notifyListeners();
      print('Fetched ${_clients.length} clients.');
    } catch (e) {
      print('Error fetching clients: $e');
    }
  }

  void _setupRealtimeSubscription() {
    _subscription = _supabase.channel('public:clients')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'clients',
        callback: (payload) async {
          try {
            final newClient = Client.fromMap(payload.newRecord);
            final exists = _clients.any((c) => c.id == newClient.id);
            if (!exists) {
              final localClient = Map<String, dynamic>.from(payload.newRecord)
                ..['is_synced'] = 1;
              await _localDb.insertClientLocally(localClient);
              _clients.add(newClient);
              _clients.sort((a, b) => a.createdAt.compareTo(b.createdAt));
              notifyListeners();
              print('Client inserted: ${newClient.name}');
            }
          } catch (e) {
            print('Error handling insert: $e');
          }
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'clients',
        callback: (payload) async {
          try {
            final deletedId = payload.oldRecord['id'] as String;
            _clients.removeWhere((c) => c.id == deletedId);
            notifyListeners();
            print('Client deleted: $deletedId');
          } catch (e) {
            print('Error handling delete: $e');
          }
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'clients',
        callback: (payload) async {
          try {
            final updatedClient = Client.fromMap(payload.newRecord);
            final index =
                _clients.indexWhere((c) => c.id == updatedClient.id);
            if (index != -1) {
              _clients[index] = updatedClient;
              notifyListeners();
              print('Client updated: ${updatedClient.name}');
            }
          } catch (e) {
            print('Error handling update: $e');
          }
        },
      )
      ..subscribe();
  }

  Future<void> addClient(String name) async {
    if (name.trim().isEmpty) {
      print('Cannot add empty client name');
      return;
    }

    try {
      final position = await _geoService.getCurrentPosition();
      final newClient = {
        'id': const Uuid().v4(),
        'name': name.trim(),
        'lat': position?.latitude,
        'lng': position?.longitude,
        'created_at': DateTime.now().toIso8601String(),
        'is_synced': 0,
      };

      await _localDb.insertClientLocally(newClient);
      final clientObj = Client.fromMap(newClient);
      _clients.add(clientObj);
      _clients.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      notifyListeners();

      unawaited(_syncAddClientToRemote(newClient));
      print('Client added locally: $name');
    } catch (e) {
      print('Failed to add client locally: $e');
    }
  }
Future<void> _syncAddClientToRemote(Map<String, dynamic> client) async {
  try {
    final remoteClient = Map<String, dynamic>.from(client)
      ..remove('is_synced')
      ..['is_synced'] = true;

    print('Upserting to Supabase: $remoteClient');

    final response = await _supabase
        .from('clients')
        .upsert(remoteClient, onConflict: 'id')
        .select();

    print('Supabase response: $response');

    // ✅ Only mark as synced if Supabase responded successfully
    if (response is List && response.isNotEmpty) {
      await _localDb.markClientAsSynced(client['id'] as String);
      await _localDb.debugPrintAllClients();

      // Refresh local client state
      final updatedClientMap = await _localDb.getClients();
      final updatedClient = updatedClientMap.firstWhere((c) => c['id'] == client['id']);
      final index = _clients.indexWhere((c) => c.id == client['id']);
      if (index != -1) {
        _clients[index] = Client.fromMap(updatedClient);
        notifyListeners();
      }

      print('Client synced to remote: ${client['name']}');
    } else {
      print('Supabase did not return a valid response. Skipping mark as synced.');
    }
  } catch (e) {
    print('Failed to sync client to remote: $e');
    // ❌ Do NOT mark as synced here
  }
}



  Future<void> removeClient(String id) async {
    try {
      await _localDb.markClientAsSynced(id);
      _clients.removeWhere((c) => c.id == id);
      notifyListeners();

      unawaited(_syncRemoveClientFromRemote(id));
      print('Client removed locally: $id');
    } catch (e) {
      print('Failed to remove client locally: $e');
    }
  }

  Future<void> _syncRemoveClientFromRemote(String id) async {
    try {
      await _supabase.from('clients').delete().match({'id': id});
      print('Client removal synced to remote: $id');
    } catch (e) {
      print('Failed to sync client removal to remote: $e');
    }
  }

  Future<void> nextClient() async {
    if (_clients.isEmpty) {
      print('Queue is empty!');
      return;
    }

    final firstClient = _clients.first;
    await removeClient(firstClient.id);
    print('Next client: ${firstClient.name}');
  }

  @override
  void dispose() {
    _supabase.removeChannel(_subscription);
    super.dispose();
  }
  void _monitorConnectivity() {
  final connectivity = Connectivity();
  connectivity.onConnectivityChanged.listen((result) {
    if (result != ConnectivityResult.none) {
      print('🔌 Internet reconnected — retrying sync');
      _syncLocalToRemote();
    }
  });
}

}
