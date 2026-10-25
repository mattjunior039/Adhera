import 'package:adhera/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timestamps without an offset are treated as UTC', () {
    final parsed = parseServerDateTime('2026-10-24T18:00:00.123456');
    expect(parsed.isUtc, isFalse);
    expect(parsed.toUtc(), DateTime.utc(2026, 10, 24, 18, 0, 0, 123, 456));
  });

  test('explicit offsets are preserved', () {
    expect(
      parseServerDateTime('2026-10-24T18:00:00Z').toUtc(),
      DateTime.utc(2026, 10, 24, 18),
    );
    expect(
      parseServerDateTime('2026-10-24T11:00:00-07:00').toUtc(),
      DateTime.utc(2026, 10, 24, 18),
    );
    expect(
      parseServerDateTime('2026-10-24T18:00:00+0000').toUtc(),
      DateTime.utc(2026, 10, 24, 18),
    );
  });
}
