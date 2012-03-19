//
//  ViewController.h
//  FaceTracker
//
//  Created by Robin Summerhill on 9/22/11.
//  Copyright 2011 Aptogo Limited. All rights reserved.
//
//  Permission is given to use this source code file without charge in any
//  project, commercial or otherwise, entirely at your risk, with the condition
//  that any redistribution (in part or whole) of source code must retain
//  this copyright and permission notice. Attribution in compiled projects is
//  appreciated but not required.
//
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface VideoCaptureViewController : UIViewController <AVCaptureVideoDataOutputSampleBufferDelegate>
{
    AVCaptureSession *_captureSession;
    AVCaptureDevice *__weak _captureDevice;
    AVCaptureVideoDataOutput *_videoOutput;
    AVCaptureVideoPreviewLayer *_videoPreviewLayer;
    
    int _camera;
    NSString *__weak _qualityPreset;
    BOOL _captureGrayscale;
    
    // Fps calculation
    CMTimeValue _lastFrameTimestamp;
    float *_frameTimes;
    int _frameTimesIndex;
    int _framesToAverage;
    
    float _captureQueueFps;
    float _fps;
    
    // Debug UI
    UILabel *_fpsLabel;
}

// Current frames per second
@property (nonatomic, readonly) float fps;
@property (nonatomic) ino64_t frameNumber;

@property (nonatomic, assign) BOOL showDebugInfo;
@property (nonatomic, assign) BOOL torchOn;

// AVFoundation components
@property (nonatomic, readonly) AVCaptureSession *captureSession;
@property (nonatomic, readonly) AVCaptureDevice *captureDevice;
@property (nonatomic, readonly) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, readonly) AVCaptureVideoPreviewLayer *videoPreviewLayer;

@property (nonatomic, strong) AVAssetWriterInput *assetWriterInput;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *pixelBufferAdaptor;
@property (nonatomic, strong) AVAssetWriter *assetWriter;
@property (nonatomic, strong) NSURL *tempFileURL;
@property (nonatomic, assign) BOOL isRecoding;
@property (nonatomic, strong) NSError *assetWriterError;
@property (nonatomic, strong) NSMutableArray *lightPath;

// -1: default, 0: back camera, 1: front camera
@property (nonatomic, assign) int camera;

// These should only be modified in the initializer
@property (nonatomic, weak) NSString * const qualityPreset;
@property (nonatomic, assign) BOOL captureGrayscale;

- (CGAffineTransform)affineTransformForVideoFrame:(CGRect)videoFrame orientation:(AVCaptureVideoOrientation)videoOrientation;
- (void)removeFile:(NSURL *)fileURL;
@end
