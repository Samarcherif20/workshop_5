import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/client.dart';

class QueueProvider extends ChangeNotifier {
  final List<Client> _clients = [];
  List<Client> get clients => _clients;

  final SupabaseClient _supabase = Supabase.instance.client;
  late RealtimeChannel _subscription;

  QueueProvider() {
    _fetchInitialClients();
    _setupRealtimeSubscription();
  }

  /// Fetch all clients that already exist in the DB
  Future<void> _fetchInitialClients() async {
    try {
      final data = await _supabase
          .from('clients')
          .select()
          .order('created_at');

      _clients
        ..clear()
        ..addAll((data as List).map((e) => Client.fromMap(e)));
      notifyListeners();

      print('Fetched ${_clients.length} clients.');
    } catch (e) {
      print('Error fetching clients: $e');
    }
  }

  /// Realtime subscription (INSERT + DELETE)
  void _setupRealtimeSubscription() {
    _subscription = _supabase.channel('public:clients')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'clients',
        callback: (payload) {
          try {
            final newClient = Client.fromMap(payload.newRecord!);
            _clients.add(newClient);
            _clients.sort((a, b) => a.createdAt.compareTo(b.createdAt));
            notifyListeners();
            print('Client inserted: ${newClient.name}');
          } catch (e) {
            print('Error handling insert: $e');
          }
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'clients',
        callback: (payload) {
          try {
            final deletedId = payload.oldRecord!['id'] as String;
            _clients.removeWhere((c) => c.id == deletedId);
            notifyListeners();
            print('Client deleted: $deletedId');
          } catch (e) {
            print('Error handling delete: $e');
          }
        },
      )
      .subscribe();
  }

  /// Add a new client
  Future<void> addClient(String name) async {
    if (name.trim().isEmpty) {
      print('Cannot add empty client name');
      return;
    }

    try {
      await _supabase.from('clients').insert({'name': name.trim()});
      print('Client added: $name');
    } catch (e) {
      print('Failed to add client: $e');
    }
  }

  /// Remove client by id
  Future<void> removeClient(String id) async {
    try {
      await _supabase.from('clients').delete().match({'id': id});
      print('Client removed: $id');
    } catch (e) {
      print('Failed to remove client: $e');
    }
  }

  /// Move queue to next client
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
}
