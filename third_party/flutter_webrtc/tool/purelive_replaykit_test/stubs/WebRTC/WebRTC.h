#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

@class RTCVideoCapturer, RTCVideoFrame;
@protocol RTCVideoCapturerDelegate <NSObject>
- (void)capturer:(RTCVideoCapturer*)capturer didCaptureVideoFrame:(RTCVideoFrame*)frame;
@end
@interface RTCVideoCapturer : NSObject
@property(nonatomic, weak) id<RTCVideoCapturerDelegate> delegate;
- (instancetype)initWithDelegate:(id<RTCVideoCapturerDelegate>)delegate;
@end
@interface RTCVideoSource : NSObject <RTCVideoCapturerDelegate>
- (void)adaptOutputFormatToWidth:(int)width height:(int)height fps:(int)fps;
@end
@interface RTCCVPixelBuffer : NSObject
- (instancetype)initWithPixelBuffer:(CVPixelBufferRef)buffer;
@end
typedef NS_ENUM(NSInteger, RTCVideoRotation) { RTCVideoRotation_0 = 0 };
@interface RTCVideoFrame : NSObject
- (instancetype)initWithBuffer:(RTCCVPixelBuffer*)buffer rotation:(RTCVideoRotation)rotation timeStampNs:(int64_t)time;
@end
