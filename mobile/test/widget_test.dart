import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/format.dart';

void main() {
  group('money formatting (integer paise, never double)', () {
    test('formats rupees with Indian digit grouping', () {
      expect(formatRupees(0), '₹0');
      expect(formatRupees(50000), '₹500');
      expect(formatRupees(123456700), '₹12,34,567');
      expect(formatRupees(49950), '₹499.50');
      expect(formatRupees(5), '₹0.05');
    });

    test('parses user input to paise without floating point', () {
      expect(parseRupeesToPaise('1000'), 100000);
      expect(parseRupeesToPaise('499.5'), 49950);
      expect(parseRupeesToPaise('499.50'), 49950);
      expect(parseRupeesToPaise('1,250'), 125000);
      expect(parseRupeesToPaise(' 10 '), 1000);
    });

    test('rejects invalid or non-positive amounts', () {
      expect(parseRupeesToPaise(''), isNull);
      expect(parseRupeesToPaise('0'), isNull);
      expect(parseRupeesToPaise('-5'), isNull);
      expect(parseRupeesToPaise('abc'), isNull);
      expect(parseRupeesToPaise('10.999'), isNull);
    });

    test('0.1 + 0.2 style float errors cannot happen', () {
      // 3 x Rs 33.33 must be exactly Rs 99.99.
      final each = parseRupeesToPaise('33.33')!;
      expect(formatRupees(each * 3), '₹99.99');
    });
  });
}
