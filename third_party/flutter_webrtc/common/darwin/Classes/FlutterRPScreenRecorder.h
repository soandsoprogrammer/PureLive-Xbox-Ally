#if TARGET_OS_IPHONE
#import <WebRTC/WebRTC.h>
@interface FlutterRPScreenRecorder : RTCVideoCapturer

- (void)startCapture;

// Completes only after local ReplayKit consent succeeds or fails.
- (void)startCaptureWithCompletionHandler:(nonnull void (^)(NSError* _Nullable error))completionHandler;

// Reports OS revocation after a successfully started capture, on the main queue.
@property(nonatomic, copy, nullable) void (^onStopped)(void);

// Stops the capture session asynchronously and notifies callback on completion.
- (void)stopCaptureWithCompletionHandler:(nullable void (^)(void))completionHandler;

- (void)stopCapture;

@end
#endif
