import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/shared/rooms/paging.dart';
import 'package:pure_live/shared/rooms/room_grid.dart';

import '../support.dart';

void main() {
  group('pageSizesOf (V02.47)', () {
    testWidgets('automatic by default; the pre-layout fallback follows the width', (tester) async {
      final services = (await tester.runAsync(testServices))!;
      addTearDown(() => tester.runAsync(services.close));
      final settings = services.store.settings;

      final wide = pageSizesOf(settings, 1280);
      expect(wide.auto, isTrue);
      expect(wide.size, 20);
      expect(wide.options, [20, 40, 60, 80]);

      final narrow = pageSizesOf(settings, 800);
      expect(narrow.auto, isTrue);
      expect(narrow.size, 12);
      expect(narrow.options, [12, 24, 36, 48]);
    });

    testWidgets('a stored size outside the choices is kept', (tester) async {
      final services = (await tester.runAsync(testServices))!;
      addTearDown(() => tester.runAsync(services.close));
      final settings = services.store.settings;
      await settings.set(Settings.pageDefaultSize, 30);

      final stored = pageSizesOf(settings, 1280);
      expect(stored.auto, isFalse);
      expect(stored.size, 30);
      expect(stored.options, [20, 30, 40, 60, 80]);

      await settings.set(Settings.pageSizeOptions, '12,24');
      expect(pageSizesOf(settings, 1280).options, [12, 24, 30]);

      await settings.set(Settings.pageDefaultSize, 20);
      final fixed = pageSizesOf(settings, 1280);
      expect(fixed.auto, isFalse);
      expect(fixed.size, 20);
      expect(fixed.options, [12, 20, 24]);
    });
  });

  group('pageFillCount (V02.47)', () {
    test('rows covering the area, the last may be partial', () {
      expect(pageFillCount(height: 1000, extent: 190, columns: 5, spacing: 6), 30);
      // Two rows fit exactly: no extra row.
      expect(pageFillCount(height: 398, extent: 190, columns: 5, spacing: 6), 10);
      // One pixel over: the third row shows its top.
      expect(pageFillCount(height: 399, extent: 190, columns: 5, spacing: 6), 15);
      expect(pageFillCount(height: 10, extent: 190, columns: 5, spacing: 6), 5);
      expect(pageFillCount(height: 0, extent: 190, columns: 5, spacing: 6), 5);
      expect(pageFillCount(height: double.infinity, extent: 190, columns: 5, spacing: 6), 5);
      expect(pageFillCount(height: 10000, extent: 190, columns: 5, spacing: 6), 100);
      expect(pageFillCount(height: 1000, extent: 190, columns: 0, spacing: 6), 0);
    });
  });

  group('PageFillScheduler (V02.47)', () {
    testWidgets('a resize back to the applied capacity cancels a stale pending resize', (tester) async {
      final scheduler = PageFillScheduler();
      final applied = <int>[];
      void report(int capacity) => scheduler.report(capacity, enabled: () => true, apply: applied.add);
      report(20);
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(applied, [20]);
      report(40);
      report(20);
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(applied, [20], reason: 'the last measurement matches the displayed capacity');
    });

    testWidgets('applies a new capacity once, after the frame', (tester) async {
      final scheduler = PageFillScheduler();
      final applied = <int>[];
      var enabled = true;
      void report(int capacity) => scheduler.report(capacity, enabled: () => enabled, apply: applied.add);
      // addPostFrameCallback waits for a frame; outside a build one must be
      // asked for.
      Future<void> frame() async {
        tester.binding.scheduleFrame();
        await tester.pump();
      }

      report(20);
      report(20);
      expect(applied, isEmpty);
      await frame();
      expect(applied, [20]);

      report(20);
      await frame();
      expect(applied, [20]);

      report(30);
      await frame();
      expect(applied, [20, 30]);

      enabled = false;
      report(40);
      await frame();
      expect(applied, [20, 30]);

      enabled = true;
      report(40);
      await frame();
      expect(applied, [20, 30, 40]);
    });
  });
}
