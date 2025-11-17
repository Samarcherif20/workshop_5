import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  bool _isOnline = false;
  bool get isOnline => _isOnline;
  
  ConnectivityService() {
    _checkConnectivity();
    
    // Écouter les changements de connectivité
    Connectivity().onConnectivityChanged.listen((result) {
      _updateConnectionStatus(result);
    });
  }
  
  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _updateConnectionStatus(result);
  }
  
  void _updateConnectionStatus(ConnectivityResult result) {
    // Vérifier si la connexion est active
    final newStatus = result != ConnectivityResult.none;
    
    if (_isOnline != newStatus) {
      _isOnline = newStatus;
      debugPrint('Connectivité changée: ${_isOnline ? "Online" : "Offline"}');
      notifyListeners();
    }
  }
}