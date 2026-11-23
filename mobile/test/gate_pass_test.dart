import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/guests/gate_pass_form_screen.dart';
import 'package:mobile/features/guests/gate_pass_repository.dart';

void main() {
  test('formats code and dates', () {
    expect(formatPassCode('K7M29XQP'), 'K7M2 9XQP');
    expect(formatPassDate('2026-11-28'), 'Sat 28 Nov');
    expect(validityText(1), 'valid 1 day');
  });

  test('validators', () {
    expect(validatePhone('+919876543210'), isNull);
    expect(validatePhone('12345'), isNotNull);
    expect(validateEmail('a@b.co'), isNull);
    expect(validateEmail('nope'), isNotNull);
  });

  test('parses verification', () {
    final v = PassVerification.fromJson({
      'pass': {'id': 1, 'visitor_name': 'Ravi', 'status': 'active', 'owner_names': ['A']},
      'valid': false,
      'reason': 'Expired',
    });
    expect(v.valid, isFalse);
    expect(v.pass.ownerNames, ['A']);
  });
}
