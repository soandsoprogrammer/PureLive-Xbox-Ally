import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/app/desktop/display_geometry.dart';

void main() {
  const left = DesktopDisplayGeometry(
    name: 'Generic PnP Monitor',
    bounds: Rect.fromLTWH(-1536, 0, 1536, 864),
    workArea: Rect.fromLTWH(-1536, 0, 1536, 824),
    isPrimary: false,
  );
  const right = DesktopDisplayGeometry(
    name: 'Generic PnP Monitor',
    bounds: Rect.fromLTWH(0, 0, 1920, 1080),
    workArea: Rect.fromLTWH(0, 0, 1920, 1040),
    isPrimary: true,
  );

  test('display identity survives handle reallocation and distinguishes identical monitors', () {
    final reconnected = DesktopDisplayGeometry(
      name: left.name,
      bounds: left.bounds,
      workArea: left.workArea,
      isPrimary: true,
    );
    expect(reconnected.persistenceKey, left.persistenceKey);
    expect(right.persistenceKey, isNot(left.persistenceKey));
    expect(left.acceptsSavedWindow(left.persistenceKey, const Rect.fromLTWH(-500, 100, 360, 200)), isTrue);
    expect(right.acceptsSavedWindow(left.persistenceKey, const Rect.fromLTWH(100, 100, 360, 200)), isFalse);
  });

  test('legacy platform IDs retain valid geometry without moving it to another monitor', () {
    const saved = Rect.fromLTWH(-500, 100, 360, 200);
    expect(left.acceptsSavedWindow(r'\\.\DISPLAY2', saved), isTrue);
    expect(right.acceptsSavedWindow(r'\\.\DISPLAY2', saved), isFalse);
    expect(left.acceptsSavedWindow('', saved), isTrue);
    expect(left.acceptsSavedWindow('old-id', Rect.zero), isFalse);
    expect(left.acceptsSavedWindow('old-id', const Rect.fromLTWH(double.nan, 0, 360, 200)), isFalse);
  });
}
