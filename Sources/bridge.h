// Private MultitouchSupport.framework bridge.
// Canonical MTTouch ("Finger") layout used by open-source multitouch tools.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

typedef struct { float x; float y; } MTPoint;
typedef struct { MTPoint position; MTPoint velocity; } MTReadout;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int foo3;
    int foo4;
    MTReadout normalized;   // position/velocity in 0..1 (x: left->right, y: bottom->top)
    float size;
    int zero1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTReadout absolute;
    int zero2[2];
    float unk2;
    int zero3;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef, MTTouch *, int, double, int);

CFMutableArrayRef MTDeviceCreateList(void);
MTDeviceRef MTDeviceCreateDefault(void);
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTUnregisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MTDeviceRef, int);
void MTDeviceStop(MTDeviceRef);

// Private DisplayServices.framework — built-in display brightness (0..1).
int DisplayServicesGetBrightness(uint32_t display, float *brightness);
int DisplayServicesSetBrightness(uint32_t display, float brightness);

// Private MediaRemote.framework — now-playing seek (for 1s video scrubbing).
typedef void (^MRNowPlayingInfoBlock)(CFDictionaryRef info);
void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t queue, MRNowPlayingInfoBlock block);
void MRMediaRemoteSetElapsedTime(double seconds);

// Taptic actuator (private, in MultitouchSupport) — reliable trackpad haptics
// from a background app, unlike NSHapticFeedbackManager.
typedef void *MTActuatorRef;
MTActuatorRef MTActuatorCreateFromDeviceID(uint64_t deviceID);
int MTActuatorOpen(MTActuatorRef);
int MTActuatorClose(MTActuatorRef);
int MTActuatorActuate(MTActuatorRef, int32_t actuationID, uint32_t, float, float);
int MTDeviceGetDeviceID(MTDeviceRef, uint64_t *);
