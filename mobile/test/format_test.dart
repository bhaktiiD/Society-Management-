import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/format.dart';

void main() {
  group('ordinal', () {
    test('basic suffixes', () {
      expect(ordinal(1), '1st');
      expect(ordinal(2), '2nd');
      expect(ordinal(3), '3rd');
      expect(ordinal(4), '4th');
    });
    test('teens are always th', () {
      expect(ordinal(11), '11th');
      expect(ordinal(12), '12th');
      expect(ordinal(13), '13th');
    });
    test('21-23 follow last digit', () {
      expect(ordinal(21), '21st');
      expect(ordinal(22), '22nd');
      expect(ordinal(23), '23rd');
    });
  });

  group('paiseToInput', () {
    test('whole rupees drop the fraction', () => expect(paiseToInput(150000), '1500'));
    test('fraction keeps two digits', () {
      expect(paiseToInput(150050), '1500.50');
      expect(paiseToInput(105), '1.05');
    });
  });

  group('parseRupeesAllowZero', () {
    test('zero forms parse to 0', () {
      expect(parseRupeesAllowZero('0'), 0);
      expect(parseRupeesAllowZero('0.00'), 0);
      expect(parseRupeesAllowZero('00'), 0);
    });
    test('positive amount parses', () => expect(parseRupeesAllowZero('5'), 500));
    test('invalid input is null', () {
      expect(parseRupeesAllowZero('abc'), isNull);
      expect(parseRupeesAllowZero(''), isNull);
      expect(parseRupeesAllowZero('-1'), isNull);
    });
  });

  group('formatRupees', () {
    test('small amounts', () {
      expect(formatRupees(0), '₹0');
      expect(formatRupees(500), '₹5');
      expect(formatRupees(99), '₹0.99');
      expect(formatRupees(100), '₹1');
    });
    test('Indian grouping', () {
      expect(formatRupees(99999), '₹999.99');
      expect(formatRupees(100000), '₹1,000');
      expect(formatRupees(12345678), '₹1,23,456.78');
    });
    test('negative', () => expect(formatRupees(-150), '-₹1.50'));
  });

  group('parseRupeesToPaise', () {
    test('valid inputs', () {
      expect(parseRupeesToPaise('1250'), 125000);
      expect(parseRupeesToPaise('1250.5'), 125050);
      expect(parseRupeesToPaise('1,250.50'), 125050);
    });
    test('rejects bad input', () {
      for (final s in ['1.234', '-1', '', '1e3', '0', 'abc']) {
        expect(parseRupeesToPaise(s), isNull, reason: s);
      }
    });
  });
}
