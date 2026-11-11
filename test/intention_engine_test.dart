import 'package:flutter_test/flutter_test.dart';
import 'package:drift_globe_poc/features/intention/intention_engine.dart';

void main() {
  test('six categories are defined', () {
    expect(intentionCategories.length, 6);
  });
  test('description only boosts compatible categories', () {
    expect(IntentionEngine.descriptionBonus('Peace', 'quiet forest', 'natural=wood'), 8);
    expect(IntentionEngine.descriptionBonus('Peace', 'busy nightlife', 'natural=wood'), 0);
    expect(IntentionEngine.descriptionBonus('Connection', 'beach', 'natural=beach'), 8);
  });
}
