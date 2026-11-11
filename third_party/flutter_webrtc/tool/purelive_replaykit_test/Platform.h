#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>

// Exercise the real capture lifecycle on a Mac without recording its display.
// The full iOS build separately compiles against Apple's actual ReplayKit API.
#undef TARGET_OS_IPHONE
#define TARGET_OS_IPHONE 1
