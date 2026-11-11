import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';

/// The columns a room grid gets for [size] at a [window] wide window whose
/// grid content is [content] wide (V02.47).
int _columns(RoomCardSize size, {required double window, required double content}) => GridColumns.count(
  width: content,
  minItemWidth: GridColumns.roomMinWidth(window) * size.scale,
  max: size.maxColumns,
);

void main() {
  test('standard is the grid of UI.md 5.3', () {
    expect(RoomCardSize.standard.scale, 1);
    expect(RoomCardSize.standard.maxColumns, 8);
    for (final (window, content) in [(393.0, 393.0), (1280.0, 1199.0), (1920.0, 1839.0), (2560.0, 2479.0)]) {
      expect(
        _columns(RoomCardSize.standard, window: window, content: content),
        GridColumns.rooms(width: content, windowWidth: window),
        reason: 'window $window',
      );
    }
  });

  test('the six presets give distinct card widths on wide windows', () {
    expect([for (final size in RoomCardSize.values) _columns(size, window: 1920, content: 1839)], [11, 9, 8, 7, 5, 4]);
    expect([for (final size in RoomCardSize.values) _columns(size, window: 1280, content: 1199)], [7, 6, 5, 4, 3, 2]);
  });

  test('the large follows cards scale from their own smallest width', () {
    int favorites(RoomCardSize size) =>
        GridColumns.count(width: 1839, minItemWidth: 300 * size.scale, max: size.maxColumns);
    expect(favorites(RoomCardSize.standard), 5);
    expect(favorites(RoomCardSize.large), 4);
    expect(favorites(RoomCardSize.xlarge), 4);
    expect(favorites(RoomCardSize.xxlarge), 3);
  });

  test('an unknown stored size reads as standard', () {
    expect(RoomCardSize.of('xlarge'), RoomCardSize.xlarge);
    expect(RoomCardSize.of('xxlarge'), RoomCardSize.xxlarge);
    expect(RoomCardSize.of('nonsense'), RoomCardSize.standard);
  });
}
