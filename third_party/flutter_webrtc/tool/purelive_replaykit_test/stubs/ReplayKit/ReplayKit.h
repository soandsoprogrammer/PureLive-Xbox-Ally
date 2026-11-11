#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

@class RPScreenRecorder, RPPreviewViewController;
typedef NS_ENUM(NSInteger, RPSampleBufferType) { RPSampleBufferTypeVideo = 1 };
@protocol RPScreenRecorderDelegate <NSObject>
- (void)screenRecorder:(RPScreenRecorder*)recorder
    didStopRecordingWithPreviewViewController:(RPPreviewViewController*)preview error:(NSError*)error;
- (void)screenRecorderDidChangeAvailability:(RPScreenRecorder*)recorder;
@end
@interface RPScreenRecorder : NSObject
@property(nonatomic, getter=isAvailable) BOOL available;
@property(nonatomic, getter=isMicrophoneEnabled) BOOL microphoneEnabled;
@property(nonatomic, weak) id<RPScreenRecorderDelegate> delegate;
@property(nonatomic, copy) void (^samples)(CMSampleBufferRef, RPSampleBufferType, NSError*);
@property(nonatomic, copy) void (^started)(NSError*);
@property(nonatomic, copy) void (^stopped)(NSError*);
@property(nonatomic) int stopRequests;
+ (instancetype)sharedRecorder;
+ (instancetype)replaceShared;
- (void)startCaptureWithHandler:(void (^)(CMSampleBufferRef, RPSampleBufferType, NSError*))handler
             completionHandler:(void (^)(NSError*))completion;
- (void)stopCaptureWithHandler:(void (^)(NSError*))completion;
@end
