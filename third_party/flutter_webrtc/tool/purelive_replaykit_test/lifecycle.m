#import <ReplayKit/ReplayKit.h>
#import "FlutterRPScreenRecorder.h"

@implementation RTCVideoCapturer
- (instancetype)initWithDelegate:(id<RTCVideoCapturerDelegate>)delegate {
  if ((self = [super init])) self.delegate = delegate;
  return self;
}
@end
@implementation RTCVideoSource
- (void)adaptOutputFormatToWidth:(int)width height:(int)height fps:(int)fps {}
- (void)capturer:(RTCVideoCapturer*)capturer didCaptureVideoFrame:(RTCVideoFrame*)frame {}
@end
@implementation RTCCVPixelBuffer
- (instancetype)initWithPixelBuffer:(CVPixelBufferRef)buffer { return [super init]; }
@end
@implementation RTCVideoFrame
- (instancetype)initWithBuffer:(RTCCVPixelBuffer*)buffer rotation:(RTCVideoRotation)rotation timeStampNs:(int64_t)time {
  return [super init];
}
@end

static RPScreenRecorder* shared;
@implementation RPScreenRecorder
+ (instancetype)sharedRecorder { return shared; }
+ (instancetype)replaceShared {
  shared = [RPScreenRecorder new];
  shared.available = YES;
  return shared;
}
- (void)startCaptureWithHandler:(void (^)(CMSampleBufferRef, RPSampleBufferType, NSError*))handler
             completionHandler:(void (^)(NSError*))completion {
  self.samples = handler;
  self.started = completion;
}
- (void)stopCaptureWithHandler:(void (^)(NSError*))completion {
  self.stopRequests++;
  self.stopped = completion;
}
@end

static void check(BOOL condition, NSString* message) {
  if (!condition) {
    fprintf(stderr, "ReplayKit lifecycle FAILED: %s\n", message.UTF8String);
    exit(1);
  }
}
static NSError* denied(void) {
  return [NSError errorWithDomain:@"ReplayKitTest" code:1 userInfo:nil];
}
// Queue barriers exercise the implementation's main-queue callbacks without
// sleeping, starting a recorder, requesting permission or touching user data.
static void afterCallbacks(int count, dispatch_block_t block) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (count > 1) afterCallbacks(count - 1, block); else block();
  });
}

static void lateCancellation(void) {
  RPScreenRecorder* fake = [RPScreenRecorder replaceShared];
  FlutterRPScreenRecorder* capture = [[FlutterRPScreenRecorder alloc] initWithDelegate:nil];
  __block int results = 0;
  [capture startCaptureWithCompletionHandler:^(NSError* error) {
    results++;
    check(error != nil, @"late grant must be rejected after local cancellation");
  }];
  [capture stopCaptureWithCompletionHandler:nil];
  fake.started(nil);
  afterCallbacks(4, ^{
    check(results == 1 && fake.stopRequests >= 1, @"late canceled capture must be stopped once acknowledged");
    puts("ReplayKit lifecycle: passed (consent, denial, revocation, stop acknowledgement, late cancellation)");
    exit(0);
  });
}

static void stopAcknowledgement(void) {
  RPScreenRecorder* fake = [RPScreenRecorder replaceShared];
  FlutterRPScreenRecorder* capture = [[FlutterRPScreenRecorder alloc] initWithDelegate:nil];
  __block int ended = 0;
  __block BOOL done = NO;
  capture.onStopped = ^{ ended++; };
  [capture startCaptureWithCompletionHandler:^(NSError* error) { check(error == nil, @"valid grant"); }];
  fake.started(nil);
  afterCallbacks(2, ^{
    [capture stopCaptureWithCompletionHandler:^{ done = YES; }];
    afterCallbacks(2, ^{
      check(!done && fake.stopRequests == 1, @"local stop must wait for native acknowledgement");
      fake.stopped(nil);
      check(done && ended == 0, @"local stop must not report a second OS revocation");
      lateCancellation();
    });
  });
}

static void grantAndRevoke(void) {
  RPScreenRecorder* fake = [RPScreenRecorder replaceShared];
  FlutterRPScreenRecorder* capture = [[FlutterRPScreenRecorder alloc] initWithDelegate:nil];
  __block int results = 0, ended = 0;
  capture.onStopped = ^{ ended++; };
  [capture startCaptureWithCompletionHandler:^(NSError* error) { results++; check(error == nil, @"valid consent result"); }];
  check(results == 0 && !fake.microphoneEnabled, @"no ready stream before consent or microphone capture");
  fake.started(nil);
  afterCallbacks(2, ^{
    check(results == 1, @"consent success must complete exactly once");
    fake.samples(NULL, RPSampleBufferTypeVideo, denied());
    [fake.delegate screenRecorder:fake didStopRecordingWithPreviewViewController:nil error:denied()];
    afterCallbacks(3, ^{
      check(results == 1 && ended == 1, @"duplicate native stop callbacks must revoke once");
      stopAcknowledgement();
    });
  });
}

static void denial(void) {
  RPScreenRecorder* fake = [RPScreenRecorder replaceShared];
  FlutterRPScreenRecorder* capture = [[FlutterRPScreenRecorder alloc] initWithDelegate:nil];
  __block int results = 0, ended = 0;
  capture.onStopped = ^{ ended++; };
  [capture startCaptureWithCompletionHandler:^(NSError* error) { results++; check(error != nil, @"denial must fail start"); }];
  check(results == 0, @"pending consent cannot complete early");
  fake.started(denied());
  fake.samples(NULL, RPSampleBufferTypeVideo, denied());
  afterCallbacks(4, ^{
    check(results == 1 && ended == 0, @"denial must not duplicate the request result or create a live track");
    grantAndRevoke();
  });
}

int main(void) {
  @autoreleasepool {
    dispatch_async(dispatch_get_main_queue(), ^{
      RPScreenRecorder* fake = [RPScreenRecorder replaceShared];
      fake.available = NO;
      FlutterRPScreenRecorder* capture = [[FlutterRPScreenRecorder alloc] initWithDelegate:nil];
      __block int results = 0;
      [capture startCaptureWithCompletionHandler:^(NSError* error) { results++; check(error != nil, @"unavailable recorder"); }];
      afterCallbacks(2, ^{ check(results == 1, @"unavailable must complete once"); denial(); });
    });
    dispatch_main();
  }
}
