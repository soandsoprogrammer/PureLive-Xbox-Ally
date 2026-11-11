#import "FlutterRPScreenRecorder.h"
#if TARGET_OS_IPHONE
#import <ReplayKit/ReplayKit.h>

// See: https://developer.apple.com/videos/play/wwdc2017/606/

@interface FlutterRPScreenRecorder () <RPScreenRecorderDelegate>
- (void)completeStart:(NSError* _Nullable)error;
- (void)captureStopped:(NSError* _Nullable)error;
@end

@implementation FlutterRPScreenRecorder {
  RPScreenRecorder* screenRecorder;
  RTCVideoSource* source;
  void (^startCompletion)(NSError* _Nullable error);
  BOOL recording;
  BOOL stopRequested;
}

- (instancetype)initWithDelegate:(__weak id<RTCVideoCapturerDelegate>)delegate {
  source = delegate;
  return [super initWithDelegate:delegate];
}

- (void)startCapture {
  [self startCaptureWithCompletionHandler:^(NSError* error) {
    if (error != nil) NSLog(@"FlutterRPScreenRecorder.startCapture: %@", error);
  }];
}

- (void)startCaptureWithCompletionHandler:(void (^)(NSError* _Nullable))completionHandler {
  startCompletion = [completionHandler copy];
  stopRequested = NO;
  if (screenRecorder == NULL)
    screenRecorder = [RPScreenRecorder sharedRecorder];

  [screenRecorder setMicrophoneEnabled:NO];

  if (![screenRecorder isAvailable]) {
    [self completeStart:[NSError errorWithDomain:@"FlutterWebRTC.ScreenCapture" code:1
                                       userInfo:@{NSLocalizedDescriptionKey: @"Screen capture is unavailable"}]];
    return;
  }

  screenRecorder.delegate = self;
  if (@available(iOS 11.0, *)) {
    [screenRecorder
        startCaptureWithHandler:^(CMSampleBufferRef _Nonnull sampleBuffer,
                                  RPSampleBufferType bufferType, NSError* _Nullable error) {
          if (error != nil) {
            [self captureStopped:error];
            return;
          }
          if (bufferType == RPSampleBufferTypeVideo) {  // We want video only now
            [self handleSourceBuffer:sampleBuffer sampleType:bufferType];
          }
        }
        completionHandler:^(NSError* _Nullable error) {
          [self completeStart:error];
        }];
  } else {
    [self completeStart:[NSError errorWithDomain:@"FlutterWebRTC.ScreenCapture" code:1
                                       userInfo:@{NSLocalizedDescriptionKey: @"Screen capture requires iOS 11"}]];
  }
}

- (void)completeStart:(NSError* _Nullable)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    // ReplayKit may report the same failure through both completion and samples.
    if (self->startCompletion == nil) {
      if (error != nil) [self captureStopped:error];
      return;
    }
    void (^completion)(NSError*) = self->startCompletion;
    self->startCompletion = nil;
    NSError* failure = error;
    if (self->stopRequested && failure == nil) {
      [self->screenRecorder stopCaptureWithHandler:^(NSError* ignored) {}];
      failure = [NSError errorWithDomain:@"FlutterWebRTC.ScreenCapture" code:2
                               userInfo:@{NSLocalizedDescriptionKey: @"Screen capture canceled"}];
    }
    self->recording = failure == nil;
    if (failure != nil && self->screenRecorder.delegate == self) self->screenRecorder.delegate = nil;
    completion(failure);
  });
}

- (void)captureStopped:(NSError* _Nullable)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->startCompletion != nil) {
      NSError* failure = error ?: [NSError errorWithDomain:@"FlutterWebRTC.ScreenCapture" code:2
                                                userInfo:@{NSLocalizedDescriptionKey: @"Screen capture stopped"}];
      [self completeStart:failure];
      return;
    }
    if (!self->recording || self->stopRequested) return;
    self->recording = NO;
    if (self->screenRecorder.delegate == self) self->screenRecorder.delegate = nil;
    if (self.onStopped != nil) self.onStopped();
  });
}

- (void)screenRecorder:(RPScreenRecorder*)recorder
    didStopRecordingWithPreviewViewController:(RPPreviewViewController*)previewViewController
                                       error:(NSError*)error {
  [self captureStopped:error];
}

- (void)screenRecorderDidChangeAvailability:(RPScreenRecorder*)recorder {
  if (!recorder.isAvailable) [self captureStopped:nil];
}

- (void)stopCapture {
  [self stopCaptureWithCompletionHandler:nil];
}

- (void)stopCaptureWithCompletionHandler:(nullable void (^)(void))completionHandler {
  dispatch_async(dispatch_get_main_queue(), ^{
    self->stopRequested = YES;
    self->recording = NO;
    self.onStopped = nil;
    if (self->screenRecorder.delegate == self) self->screenRecorder.delegate = nil;
    if (@available(iOS 11.0, *)) {
      [self->screenRecorder stopCaptureWithHandler:^(NSError* error) {
        if (completionHandler != nil) completionHandler();
      }];
    } else if (completionHandler != nil) {
      completionHandler();
    }
  });
}

- (void)handleSourceBuffer:(CMSampleBufferRef)sampleBuffer
                sampleType:(RPSampleBufferType)sampleType {
  if (CMSampleBufferGetNumSamples(sampleBuffer) != 1 || !CMSampleBufferIsValid(sampleBuffer) ||
      !CMSampleBufferDataIsReady(sampleBuffer)) {
    return;
  }

  CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  if (pixelBuffer == nil) {
    return;
  }

  size_t width = CVPixelBufferGetWidth(pixelBuffer);
  size_t height = CVPixelBufferGetHeight(pixelBuffer);

  [source adaptOutputFormatToWidth:(int)(width / 2) height:(int)(height / 2) fps:8];

  RTCCVPixelBuffer* rtcPixelBuffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBuffer];
  int64_t timeStampNs =
      CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * NSEC_PER_SEC;
  RTCVideoFrame* videoFrame = [[RTCVideoFrame alloc] initWithBuffer:rtcPixelBuffer
                                                           rotation:RTCVideoRotation_0
                                                        timeStampNs:timeStampNs];
  [self.delegate capturer:self didCaptureVideoFrame:videoFrame];
}

@end
#endif
