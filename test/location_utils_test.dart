import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app_5/location_utils.dart';

void main() {
  group('calculateDistance', () {
    test('retourne une distance non nulle pour des coordonnées différentes', () {
      final distance = calculateDistance(0, 0, 0.001, 0.001);
      expect(distance, greaterThan(0));
    });

    test('retourne 0 pour des coordonnées identiques', () {
      final distance = calculateDistance(36.8065, 10.1815, 36.8065, 10.1815);
      expect(distance, lessThan(0.001)); // Très proche de 0
    });

    test('calcule correctement la distance entre Tunis et Carthage (~15km)', () {
      // Tunis centre: 36.8065, 10.1815
      // Carthage: 36.8531, 10.3233
      final distance = calculateDistance(36.8065, 10.1815, 36.8531, 10.3233);
      expect(distance, greaterThan(10));
      expect(distance, lessThan(20));
    });
  });
}