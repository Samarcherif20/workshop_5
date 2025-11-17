import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/client.dart';
import 'package:uuid/uuid.dart';
import 'local_queue_service.dart';
import 'geolocation_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'location_utils.dart';
import 'connectivity_service.dart';

class QueueProvider extends ChangeNotifier {
  final List<Client> _clients = [];
  List<Client> get clients => _clients;

  final SupabaseClient _supabase = Supabase.instance.client;
  final LocalQueueService _localDb = LocalQueueService();
  final GeolocationService _geoService;

  late RealtimeChannel _subscription;

  ConnectivityService? _connectivity;

  // Waiting rooms
  final List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> get rooms => _rooms;

  QueueProvider({GeolocationService? geoService})
      : _geoService = geoService ?? GeolocationService() {
    initialize();
  }

  /// Inject connectivity service
  void setConnectivity(ConnectivityService connectivity) {
    _connectivity = connectivity;
    notifyListeners();
  }

  Future<void> initialize() async {
    await _loadQueue();
    _setupRealtimeSubscription();
    _monitorConnectivity();
    await fetchWaitingRooms();
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

  /// Sync local unsynced clients to Supabase
  Future<void> _syncLocalToRemote() async {
    if (_connectivity == null || !_connectivity!.isOnline) return;

    final unsynced = await _localDb.getUnsyncedClients();
    for (var clientMap in unsynced) {
      try {
        final client = Client.fromMap(clientMap);

        final remoteClient = Map<String, dynamic>.from(clientMap)
          ..remove('is_synced')
          ..['is_synced'] = true; // Supabase expects boolean

        final response = await _supabase
            .from('clients')
            .upsert(remoteClient, onConflict: 'id')
            .select();

        if (response.isNotEmpty) {
          await _localDb.markClientAsSynced(client.id);

          // Update client in the list for green icon
          final index = _clients.indexWhere((c) => c.id == client.id);
          if (index != -1) {
            _clients[index] = Client(
              id: client.id,
              name: client.name,
              createdAt: client.createdAt,
              lat: client.lat,
              lng: client.lng,
              isSynced: true,
            );
            notifyListeners();
          }
          print('Client synced: ${client.name}');
        }
      } catch (e) {
        print('Sync failed for ${clientMap['id']}: $e');
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
    if (name.trim().isEmpty) return;

    try {
      final position = await _geoService.getCurrentPosition();
      final roomId = await _findNearestRoom(
          position?.latitude ?? 0.0, position?.longitude ?? 0.0);

      final newClient = {
        'id': const Uuid().v4(),
        'name': name.trim(),
        'lat': position?.latitude,
        'lng': position?.longitude,
        'created_at': DateTime.now().toIso8601String(),
        'is_synced': 0,
        'waiting_room_id': roomId,
      };

      await _localDb.insertClientLocally(newClient);
      _clients.add(Client.fromMap(newClient));
      _clients.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      notifyListeners();

      unawaited(_syncAddClientToRemote(newClient));
      print('Client added locally: $name');
    } catch (e) {
      print('Failed to add client locally: $e');
    }
  }

  Future<void> _syncAddClientToRemote(Map<String, dynamic> clientMap) async {
    if (_connectivity == null || !_connectivity!.isOnline) return;

    try {
      final client = Client.fromMap(clientMap);

      final remoteClient = Map<String, dynamic>.from(clientMap)
        ..remove('is_synced')
        ..['is_synced'] = true;

      final response =
          await _supabase.from('clients').upsert(remoteClient).select();

      if (response.isNotEmpty) {
        await _localDb.markClientAsSynced(client.id);

        // 🔹 Update local list for UI icon
        final index = _clients.indexWhere((c) => c.id == client.id);
        if (index != -1) {
          _clients[index] = Client(
            id: client.id,
            name: client.name,
            createdAt: client.createdAt,
            lat: client.lat,
            lng: client.lng,
            isSynced: true,
          );
          notifyListeners();
        }

        print('Client synced to remote: ${client.name}');
      }
    } catch (e) {
      print('Failed to sync client to remote: $e');
    }
  }

 Future<void> removeClient(String id) async {
    try {
      await _supabase.from('clients').delete().match({'id': id});
      print('Client removed: $id');
    } catch (e) {
      print('Failed to remove client: $e');
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

  Future<void> fetchWaitingRooms() async {
    try {
      final response = await _supabase.from('waiting_rooms').select();
      _rooms.clear();
      _rooms.addAll(List<Map<String, dynamic>>.from(response));
      notifyListeners();
    } catch (e) {
      debugPrint('Erreur fetchWaitingRooms: $e');
    }
  }

  Future<String?> _findNearestRoom(double clientLat, double clientLng) async {
    if (_rooms.isEmpty) await fetchWaitingRooms();
    if (_rooms.isEmpty) return null;

    double minDistance = double.infinity;
    String? nearestRoomId;

    for (var room in _rooms) {
      final roomLat = room['latitude'] as double;
      final roomLng = room['longitude'] as double;
      final distance = calculateDistance(clientLat, clientLng, roomLat, roomLng);

      if (distance < minDistance) {
        minDistance = distance;
        nearestRoomId = room['id'] as String;
      }
    }

    return nearestRoomId;
  }
}
