import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:live_ui/src/theme/motion.dart';
import 'package:scroll_animator/scroll_animator.dart';

/// Short enough to feel immediate on high-refresh displays while leaving the
/// tab indicator and page transition enough frames to look linear.
const Duration pureLiveTabTransitionDuration = Duration(milliseconds: 220);

/// Content lists: on a phone or tablet the damped edge of the refreshable
/// lists everywhere (A03.5: past an end the list follows the finger ever
/// more heavily, at most the 0.52 of 3.x's lists, and springs back with
/// [AppMotion.refreshSpring]); on a desktop the hard edge its wheel and
/// scroll bars expect.
class PureLiveScrollPhysics extends ScrollPhysics {
  /// Creates the physics.
  const new({super.parent});

  static bool get _touch => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
    _ => false,
  };

  /// The physics for this platform over [parent].
  ScrollPhysics get _platform =>
      _touch ? PureLiveDampedScrollPhysics(parent: parent) : ClampingScrollPhysics(parent: parent);

  @override
  ScrollPhysics applyTo(ScrollPhysics? ancestor) {
    final parent = buildParent(ancestor);
    return _touch ? PureLiveDampedScrollPhysics(parent: parent) : ClampingScrollPhysics(parent: parent);
  }

  // Used without [applyTo] (as another physics' parent, or the scroll
  // behaviour's physics) the instance itself must act like the platform's
  // physics; plain ScrollPhysics has no edges, so lists scrolled past their
  // content.

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      _platform.applyPhysicsToUserOffset(position, offset);

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) =>
      _platform.applyBoundaryConditions(position, value);

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) =>
      _platform.createBallisticSimulation(position, velocity);

  @override
  double get minFlingVelocity => _platform.minFlingVelocity;

  @override
  double get maxFlingVelocity => _platform.maxFlingVelocity;

  @override
  double carriedMomentum(double existingVelocity) => _platform.carriedMomentum(existingVelocity);

  @override
  double? get dragStartDistanceMotionThreshold => _platform.dragStartDistanceMotionThreshold;

  @override
  SpringDescription get spring => _platform.spring;
}

/// The damped edge (A03.5): iOS's deceleration and rubber band, which are
/// 3.x's refreshable lists' (easy_refresh's `_ERScrollPhysics`), springing
/// back with [AppMotion.refreshSpring].
class PureLiveDampedScrollPhysics extends BouncingScrollPhysics {
  /// Creates the physics.
  const new({super.parent});

  @override
  PureLiveDampedScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      PureLiveDampedScrollPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => AppMotion.refreshSpring;
}

/// Navigation strips, filters and paged views: the damped edge on every
/// platform (A03.5; a hard one before), and never left before the first or
/// after the last item when the content shrinks while the route stays
/// mounted.
class PureLiveBoundedScrollPhysics extends PureLiveDampedScrollPhysics {
  /// Creates the physics.
  const new({super.parent});

  @override
  PureLiveBoundedScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      PureLiveBoundedScrollPhysics(parent: buildParent(ancestor));

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final adjusted = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
    // While a drag holds the strip past an end it stays there; at rest it
    // is put back inside.
    if (isScrolling) return adjusted;
    return adjusted.clamp(newPosition.minScrollExtent, newPosition.maxScrollExtent);
  }
}

/// The pages of a `TabBarView`: [PureLiveBoundedScrollPhysics]'s damped
/// edges past the first and the last page, a firmer spring and Android
/// ViewPager's fling rule (research 2026-10-02
/// S3). A release turns the page by itself only when at least
/// [AppMotion.pageFlingVelocity] fast after [AppMotion.pageFlingDistance];
/// otherwise the page turns only when dragged past half, so the sideways
/// part of an upward scroll does not turn it. The page settles with
/// [AppMotion.pageSpring] in about 0.27 s, in step with a tapped tab
/// ([pureLiveTabTransitionDuration]).
class PureLivePageScrollPhysics extends PureLiveBoundedScrollPhysics {
  /// Creates the physics.
  const new({super.parent});

  @override
  PureLivePageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      PureLivePageScrollPhysics(parent: buildParent(ancestor));

  // The page physics `TabBarView` and `PageView` wrap this in read these
  // from their parent.

  @override
  SpringDescription get spring => AppMotion.pageSpring;

  @override
  double get minFlingVelocity => AppMotion.pageFlingVelocity;

  @override
  double get minFlingDistance => AppMotion.pageFlingDistance;
}

/// A scroll controller that turns discrete mouse-wheel steps on Windows into
/// one continuous movement (Chromium's ease-in-out curve); a plain controller
/// elsewhere, so touch keeps Flutter's own scrolling.
ScrollController createPureLiveScrollController({double initialScrollOffset = 0}) {
  if (defaultTargetPlatform == TargetPlatform.windows) {
    return AnimatedScrollController(
      animationFactory: const ChromiumEaseInOut(),
      initialScrollOffset: initialScrollOffset,
    );
  }
  return ScrollController(initialScrollOffset: initialScrollOffset);
}

/// Gives one desktop route its own animated primary scroll controller, so
/// pages without a controller of their own scroll smoothly with the wheel on
/// Windows. Per route: a controller at the app root would attach to several
/// offstage routes and tab views.
class PureLiveRouteScrollScope extends StatelessWidget {
  /// Wraps a route's [child].
  const new({required this.child, super.key});

  /// The route's page.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.windows) return child;
    return AnimatedPrimaryScrollController(
      automaticallyInheritForPlatforms: const {TargetPlatform.windows},
      child: child,
    );
  }
}

/// Remembers where the list under [child] was scrolled to, so the list
/// comes back there when it is taken out of the tree and built again while
/// its route stays: a page shown in its place and closed (the settings
/// overview on phones), a layout that crosses a breakpoint (A11.6).
///
/// The position goes to the route's [PageStorage] under `id` (a
/// [PageStorageKey]); lists under one route need different ids, and a list
/// that should start at the top again (another search) gets a new one. A
/// page pushed over the list does not need this: the list stays in the tree
/// under it. Lists whose controller has `keepScrollOffset: false` are not
/// remembered.
class KeepScrollPosition extends StatelessWidget {
  /// Remembers the position of the list in [child] as [id].
  new({required String id, required this.child}) : super(key: PageStorageKey<String>('scroll:$id'));

  /// The list (or the page holding it).
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Keeps a tab's page alive when it scrolls out of a [PageView] or
/// `TabBarView` (3.x `KeepAliveWrapper`).
class KeepAliveWrapper extends StatefulWidget {
  /// Keeps [child] alive.
  const new({required this.child, super.key});

  /// The page.
  final Widget child;

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
