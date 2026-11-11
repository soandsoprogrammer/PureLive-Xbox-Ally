# flutter_webrtc 1.6.3 capture lifecycle bridges

Source: https://pub.dev/packages/flutter_webrtc/versions/1.6.3
Upstream: https://github.com/flutter-webrtc/flutter-webrtc

The upstream pub package is retained with LICENSE and NOTICE. Example, test,
documentation and illustration directories are omitted from this runtime copy.
Native SDK versions and all other platform implementations stay upstream's.

Android's `GetUserMediaImpl.getDisplayMedia` already receives
`MediaProjection.Callback.onStop`, but does not forward revocation to Dart.
The patch allocates the captured track ID before starting projection and sends
`onScreenCaptureStopped` on the existing plugin event channel. The public
`ScreenCaptureEvents.stopped` stream carries only that track ID. No permission,
screen pixels, session credentials or application data are added to events.

Consumers subscribe before requesting capture, match the returned track ID and
release the stream, peer and foreground service on revocation. They must ignore
events for an older stopped track. This remains separate from request completion:
never call `result.error` from `onStop` after capture succeeded, which would repeat
the upstream double-reply failure discussed in:
https://github.com/flutter-webrtc/flutter-webrtc/issues/465

Validation is recorded in task N02.2: event contract, cancellation tests and
controlled Android capture/revoke/restart tests. Native acceptance remains
separate from fake-peer tests.

Native CMake SDK downloads/extraction are ignored build caches. Flutter license
collection also includes upstream NOTICE and the WebRTC project BSD license from
https://webrtc.googlesource.com/src/+/refs/heads/main/LICENSE.

ReplayKit application capture resolves only after local start completion. Denied
or unavailable starts fail once; later sample errors and recorder stop callbacks
emit the same track-scoped event. Local stop waits for acknowledgement. Common
CocoaPods and Swift Package Manager copies are synchronized. The app keeps its
consent state until the result and releases late canceled streams. This supports
iOS application capture; no broadcast extension or other-app capture is promised.

Apple native compilation and simulator checks remain separate from physical
consent, capture and revocation acceptance.

## Strict Linux compiler compatibility

Clang 23 diagnoses unused-but-set globals under the existing warning-as-error policy. Keep the retained event-channel host messenger on Windows only, where it is read for engine-detachment checks; preserve the setter as a no-op on other platforms. Explicitly acknowledge G_DEFINE_TYPE's generated parent-class cache in the Linux texture class initializer. No warning flags or texture lifecycle behavior are changed. References: https://clang.llvm.org/docs/DiagnosticsReference.html#wunused-but-set-global and https://docs.gtk.org/gobject/func.DEFINE_TYPE.html .
