import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:waiting_room_app_5/connectivity_service.dart';
import 'package:waiting_room_app_5/queue_provider.dart';
import 'package:waiting_room_app_5/main.dart';

// Mock pour ConnectivityService
class MockConnectivityService extends ChangeNotifier {
  bool _isOnline = false;
  
  bool get isOnline => _isOnline;
  
  void setOnline(bool online) {
    _isOnline = online;
    notifyListeners();
  }
}

// Mock COMPLET pour QueueProvider - n'étend PAS la vraie classe
class MockQueueProvider extends ChangeNotifier {
  final List<dynamic> _clients = [];
  
  List<dynamic> get clients => _clients;

  Future<void> addClient(String name) async {
    final newClient = _createMockClient(name);
    _clients.add(newClient);
    notifyListeners();
  }

  Future<void> removeClient(String id) async {
    _clients.removeWhere((client) => _getClientId(client) == id);
    notifyListeners();
  }

  Future<void> nextClient() async {
    if (_clients.isNotEmpty) {
      await removeClient(_getClientId(_clients.first));
    }
  }

  // Méthodes helper pour gérer les clients mock
  dynamic _createMockClient(String name) {
    return {
      'id': 'test-id-${DateTime.now().millisecondsSinceEpoch}',
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
      'is_synced': true,
    };
  }

  String _getClientId(dynamic client) {
    if (client is Map) return client['id'] as String;
    return client.id; // Si c'est un vrai objet Client
  }
}

void main() {
  testWidgets('Affiche bannière offline quand déconnecté', (tester) async {
    final mockConnectivity = MockConnectivityService();
    mockConnectivity.setOnline(false);
    final mockQueue = MockQueueProvider();
    
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: mockConnectivity),
          ChangeNotifierProvider.value(value: mockQueue),
        ],
        child: const MaterialApp(home: WaitingRoomScreen()),
      ),
    );
    
    // Vérifier que la bannière offline est visible
    expect(find.text('Offline Mode - Data will sync when connected.'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('Cache bannière offline quand connecté', (tester) async {
    final mockConnectivity = MockConnectivityService();
    mockConnectivity.setOnline(true);
    final mockQueue = MockQueueProvider();
    
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: mockConnectivity),
          ChangeNotifierProvider.value(value: mockQueue),
        ],
        child: const MaterialApp(home: WaitingRoomScreen()),
      ),
    );
    
    // Vérifier que la bannière n'est PAS visible
    expect(find.text('Offline Mode - Data will sync when connected.'), findsNothing);
  });
}