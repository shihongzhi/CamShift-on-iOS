//
//  OpenCVClientViewController.m
//  OpenCVClient
//
//  Created by Robin Summerhill on 02/09/2011.
//  Copyright 2011 Aptogo Limited. All rights reserved.
//
//  Permission is given to use this source code file without charge in any
//  project, commercial or otherwise, entirely at your risk, with the condition
//  that any redistribution (in part or whole) of source code must retain
//  this copyright and permission notice. Attribution in compiled projects is
//  appreciated but not required.
//

#import "UIImage+OpenCV.h"

#import "VideoCaptureViewController.h"

// Number of frames to average for FPS calculation
const int kFrameTimeBufferSize = 5;

// Private interface
@interface VideoCaptureViewController ()
- (BOOL)createCaptureSessionForCamera:(NSInteger)camera qualityPreset:(NSString *)qualityPreset grayscale:(BOOL)grayscale;
- (BOOL)setupWriter;
- (void)destroyCaptureSession;
- (CGPoint)processFrame:(cv::Mat&)mat videoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)orientation;
- (void)updateDebugInfo;
- (CVPixelBufferRef)drowLightLocation:(CGPoint)location toPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@property (nonatomic, assign) float fps;

@end

@implementation VideoCaptureViewController

@synthesize fps = _fps;
@synthesize frameNumber = _frameNumber;
@synthesize camera = _camera;
@synthesize captureGrayscale = _captureGrayscale;
@synthesize qualityPreset = _qualityPreset;
@synthesize captureSession = _captureSession;
@synthesize captureDevice = _captureDevice;
@synthesize videoOutput = _videoOutput;
@synthesize videoPreviewLayer = _videoPreviewLayer;
@synthesize assetWriterInput = _assetWriterInput;
@synthesize pixelBufferAdaptor = _pixelBufferAdaptor;
@synthesize assetWriter = _assetWriter;
@synthesize tempFileURL = _tempFileURL;
@synthesize isRecoding = _isRecoding;
@synthesize assetWriterError = _assetWriterError;
@synthesize lightPath = _lightPath;

@dynamic showDebugInfo;
@dynamic torchOn;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        //这里的代码执行不到的
//        _camera = -1;
//        _qualityPreset = AVCaptureSessionPresetMedium;
//        _captureGrayscale = YES;
//        
//        // Create frame time circular buffer for calculating averaged fps
//        _frameTimes = (float*)malloc(sizeof(float) * kFrameTimeBufferSize);
    }
    return self;
}

- (void)dealloc
{
    [self destroyCaptureSession];
    _fpsLabel = nil;
    if (_frameTimes) {
        free(_frameTimes);
    }
    
}
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    _camera = -1;
    _qualityPreset = AVCaptureSessionPresetMedium;
    _captureGrayscale = YES;
    self.isRecoding = NO;
    
    // Create frame time circular buffer for calculating averaged fps
    _frameTimes = (float*)malloc(sizeof(float) * kFrameTimeBufferSize);
    
    
    [self createCaptureSessionForCamera:_camera qualityPreset:_qualityPreset grayscale:_captureGrayscale];
    [self setupWriter];
    [_captureSession startRunning];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    
    [self destroyCaptureSession];
    _fpsLabel = nil;
}

- (NSMutableArray*)lightPath
{
    if (!_lightPath) {
        _lightPath = [[NSMutableArray alloc] init];
    }
    return _lightPath;
}

// MARK: Accessors
- (void)setFps:(float)fps
{
    [self willChangeValueForKey:@"fps"];
    _fps = fps;
    [self didChangeValueForKey:@"fps"];
    
    [self updateDebugInfo];
}



- (NSURL *) tempFileURL
{
    return [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@%@", NSTemporaryDirectory(), @"output.mov"]];
}

- (BOOL)showDebugInfo
{
    return (_fpsLabel != nil);
}

// Show/hide debug panel with current FPS 
- (void)setShowDebugInfo:(BOOL)showDebugInfo
{
    if (!showDebugInfo && _fpsLabel) {
        [_fpsLabel removeFromSuperview];
        _fpsLabel = nil;
    }
    
    if (showDebugInfo && !_fpsLabel) {
        // Create label to show FPS
        CGRect frame = self.view.bounds;
        frame.size.height = 40.0f;
        _fpsLabel = [[UILabel alloc] initWithFrame:frame];
        _fpsLabel.textColor = [UIColor whiteColor];
        _fpsLabel.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
        [self.view addSubview:_fpsLabel];
        
        [self updateDebugInfo];
    }
}

// Set torch on or off (if supported)
- (void)setTorchOn:(BOOL)torch
{
    NSError *error = nil;
    if ([_captureDevice hasTorch]) {
        BOOL locked = [_captureDevice lockForConfiguration:&error];
        if (locked) {
            _captureDevice.torchMode = (torch)? AVCaptureTorchModeOn : AVCaptureTorchModeOff;
            [_captureDevice unlockForConfiguration];
        }
    }
}

// Return YES if the torch is on
- (BOOL)torchOn
{
    return (_captureDevice.torchMode == AVCaptureTorchModeOn);
}


// Switch camera 'on-the-fly'
//
// camera: 0 for back camera, 1 for front camera
//
- (void)setCamera:(int)camera
{
    if (camera != _camera)
    {
        _camera = camera;
        
        if (_captureSession) {
            NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
            
            [_captureSession beginConfiguration];
            
            [_captureSession removeInput:[[_captureSession inputs] lastObject]];
    
            
            if (_camera >= 0 && _camera < [devices count]) {
                _captureDevice = [devices objectAtIndex:camera];
            }
            else {
                _captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            }
         
            // Create device input
            NSError *error = nil;
            AVCaptureDeviceInput *input = [[AVCaptureDeviceInput alloc] initWithDevice:_captureDevice error:&error];
            [_captureSession addInput:input];
            
            [_captureSession commitConfiguration];
        }
    }
}

// MARK: AVCaptureVideoDataOutputSampleBufferDelegate delegate methods

// AVCaptureVideoDataOutputSampleBufferDelegate delegate method called when a video frame is available
//
// This method is called on the video capture GCD queue. A cv::Mat is created from the frame data and
// passed on for processing with OpenCV.
- (void)captureOutput:(AVCaptureOutput *)captureOutput 
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer 
       fromConnection:(AVCaptureConnection *)connection
{
    @autoreleasepool {
    
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
        CGRect videoRect = CGRectMake(0.0f, 0.0f, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer));
        AVCaptureVideoOrientation videoOrientation = [[[_videoOutput connections] objectAtIndex:0] videoOrientation];
        
        CGPoint location = CGPointMake(0, 0);

        
        if (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            // For grayscale mode, the luminance channel of the YUV data is used
            CVPixelBufferLockBaseAddress(pixelBuffer, 0);
            //获得0通道的pixle位置
            void *baseaddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
            
            cv::Mat mat(videoRect.size.height, videoRect.size.width, CV_8UC1, baseaddress, 0);
            
            location = [self processFrame:mat videoRect:videoRect videoOrientation:videoOrientation];
            
            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0); 
        }
        else if (format == kCVPixelFormatType_32BGRA) {
            // For color mode a 4-channel cv::Mat is created from the BGRA data
            CVPixelBufferLockBaseAddress(pixelBuffer, 0);
            void *baseaddress = CVPixelBufferGetBaseAddress(pixelBuffer);
            
            cv::Mat mat(videoRect.size.height, videoRect.size.width, CV_8UC4, baseaddress, 0);
            
            location = [self processFrame:mat videoRect:videoRect videoOrientation:videoOrientation];
            
            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);    
        }
        else {
            NSLog(@"Unsupported video format");
        }
        
        if (self.isRecoding) {
            pixelBuffer = [self drowLightLocation:location toPixelBuffer:pixelBuffer];
            
            if (self.assetWriterInput.readyForMoreMediaData) {
                if (![self.pixelBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:CMTimeMake(self.frameNumber, 30)]) {
                    NSLog(@"Unable append pixelBuffer to adaptor");
                    
                    NSLog(@"%@", [self.assetWriter error]);
                }
            }
            else
            {
                NSLog(@"assetWriterInput is not readyForMoreMediaData");
            }
            NSLog(@"recording...frameNumber:%lld", self.frameNumber);
            _frameNumber++;
        }
        
        // Update FPS calculation
        CMTime presentationTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
        
        if (_lastFrameTimestamp == 0) {
            _lastFrameTimestamp = presentationTime.value;
            _framesToAverage = 1;
        }
        else {
            float frameTime = (float)(presentationTime.value - _lastFrameTimestamp) / presentationTime.timescale;
            _lastFrameTimestamp = presentationTime.value;
            
            _frameTimes[_frameTimesIndex++] = frameTime;
            
            if (_frameTimesIndex >= kFrameTimeBufferSize) {
                _frameTimesIndex = 0;
            }
            
            float totalFrameTime = 0.0f;
            for (int i = 0; i < _framesToAverage; i++) {
                totalFrameTime += _frameTimes[i];
            }
            
            float averageFrameTime = totalFrameTime / _framesToAverage;
            float fps = 1.0f / averageFrameTime;
            
            if (fabsf(fps - _captureQueueFps) > 0.1f) {
                _captureQueueFps = fps;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self setFps:fps];
                });    
            }
            
            _framesToAverage++;
            if (_framesToAverage > kFrameTimeBufferSize) {
                _framesToAverage = kFrameTimeBufferSize;
            }
        }
    
    }
}

//drow light path location to the pixelBuffer
- (CVPixelBufferRef)drowLightLocation:(CGPoint)location toPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    //draw the path on the frame
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    int bufferHeight = CVPixelBufferGetHeight(pixelBuffer);
    int bufferWidth = CVPixelBufferGetWidth(pixelBuffer);
    unsigned char *rowBase = (unsigned char *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    int bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    
    [self.lightPath addObject:[NSValue valueWithCGPoint:location]];
    BOOL firstLocation = YES;
    CGPoint pathLocationPre;
    unsigned char *pixel = NULL;
    for (NSValue* pathLocationValue in self.lightPath) {
        CGPoint pathLocation = [pathLocationValue CGPointValue];
        if (firstLocation) {
            for (int t=-2; t<=2; t++) {
                for (int k=-2; k<=2; k++) {
                    pixel = rowBase + ((int)(bufferHeight - pathLocation.x + t) * bytesPerRow) + (int)(pathLocation.y + k);
                    pixel[0] = 255;
                }
            }
            firstLocation = NO;
        }
        else{
            int minX = pathLocation.x > pathLocationPre.x ? pathLocationPre.x : pathLocation.x;
            int minY = pathLocation.y > pathLocationPre.y ? pathLocationPre.y : pathLocation.y;
            int maxX = pathLocation.x > pathLocationPre.x ? pathLocation.x : pathLocationPre.x;
            int maxY = pathLocation.y > pathLocationPre.y ? pathLocation.y : pathLocationPre.y;
            //NSLog(@"minX = %d; maxX = %d; minY = %d; maxY = %d", minX, maxX, minY, maxY);
            //如果跳跃过大，则不画中间的过渡线
            if (maxX-minX<=20 && maxY-minY<=20) {
                for (int i = minX; i < maxX; i++) {
                    for (int j = minY; j < maxY; j++) {
                        for (int t=-2; t<=2; t++) {
                            for (int k=-2; k<=2; k++) {
                                pixel = rowBase + ((int)(bufferHeight - i + t) * bytesPerRow) + (int)(j + k);
                                pixel[0] = 255;
                            }
                        }
                    }
                }
            }
        }
        pathLocationPre = pathLocation;
    }
    //这里的tranpose会很麻烦，因为YUV的格式问题
    //http://stackoverflow.com/a/4577389/379941
//    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
//                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
//                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
//                             nil];
//    CVPixelBufferRef transposeBuffer = NULL;
//    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, bufferHeight, bufferWidth, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, (__bridge CFDictionaryRef)options, &transposeBuffer);
//    NSParameterAssert(status == kCVReturnSuccess && transposeBuffer != NULL);
//    CVPixelBufferLockBaseAddress(transposeBuffer, 0);
//    
//    void *dest_buff = CVPixelBufferGetBaseAddress(transposeBuffer);
//    void *src_buff = CVPixelBufferGetBaseAddress(pixelBuffer);
//    
//    
//    CVPixelBufferUnlockBaseAddress(transposeBuffer, 0);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    return pixelBuffer;
}


// MARK: Methods to override

// Override this method to process the video frame with OpenCV
//
// Note that this method is called on the video capture GCD queue. Use dispatch_sync or dispatch_async to update UI
// from the main queue.
//
// mat: The frame as an OpenCV::Mat object. The matrix will have 1 channel for grayscale frames and 4 channels for
//      BGRA frames. (Use -[VideoCaptureViewController setGrayscale:])
// rect: A CGRect describing the video frame dimensions
// orientation: Will generally by AVCaptureVideoOrientationLandscapeRight for the back camera and
//              AVCaptureVideoOrientationLandscapeRight for the front camera
//
- (void)processFrame:(cv::Mat &)mat videoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)orientation
{

}

// MARK: Geometry methods

// Create an affine transform for converting CGPoints and CGRects from the video frame coordinate space to the
// preview layer coordinate space. Usage:
//
// CGPoint viewPoint = CGPointApplyAffineTransform(videoPoint, transform);
// CGRect viewRect = CGRectApplyAffineTransform(videoRect, transform);
//
// Use CGAffineTransformInvert to create an inverse transform for converting from the view cooridinate space to
// the video frame coordinate space.
//
// videoFrame: a rect describing the dimensions of the video frame
// video orientation: the video orientation
//
// Returns an affine transform
//
- (CGAffineTransform)affineTransformForVideoFrame:(CGRect)videoFrame orientation:(AVCaptureVideoOrientation)videoOrientation
{
    CGSize viewSize = self.view.bounds.size;
    NSString * const videoGravity = _videoPreviewLayer.videoGravity;
    CGFloat widthScale = 1.0f;
    CGFloat heightScale = 1.0f;
    
    // Move origin to center so rotation and scale are applied correctly
    CGAffineTransform t = CGAffineTransformMakeTranslation(-videoFrame.size.width / 2.0f, -videoFrame.size.height / 2.0f);
    
    switch (videoOrientation) {
        case AVCaptureVideoOrientationPortrait:
            widthScale = viewSize.width / videoFrame.size.width;
            heightScale = viewSize.height / videoFrame.size.height;
            break;
            
        case AVCaptureVideoOrientationPortraitUpsideDown:
            t = CGAffineTransformConcat(t, CGAffineTransformMakeRotation(M_PI));
            widthScale = viewSize.width / videoFrame.size.width;
            heightScale = viewSize.height / videoFrame.size.height;
            break;
            
        case AVCaptureVideoOrientationLandscapeRight:
            t = CGAffineTransformConcat(t, CGAffineTransformMakeRotation(M_PI_2));
            widthScale = viewSize.width / videoFrame.size.height;
            heightScale = viewSize.height / videoFrame.size.width;
            break;
            
        case AVCaptureVideoOrientationLandscapeLeft:
            t = CGAffineTransformConcat(t, CGAffineTransformMakeRotation(-M_PI_2));
            widthScale = viewSize.width / videoFrame.size.height;
            heightScale = viewSize.height / videoFrame.size.width;
            break;
    }
    
    // Adjust scaling to match video gravity mode of video preview
    if (videoGravity == AVLayerVideoGravityResizeAspect) {
        heightScale = MIN(heightScale, widthScale);
        widthScale = heightScale;
    }
    else if (videoGravity == AVLayerVideoGravityResizeAspectFill) {
        heightScale = MAX(heightScale, widthScale);
        widthScale = heightScale;
    }
    
    // Apply the scaling
    t = CGAffineTransformConcat(t, CGAffineTransformMakeScale(widthScale, heightScale));
    
    // Move origin back from center
    t = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(viewSize.width / 2.0f, viewSize.height / 2.0f));
                                
    return t;
}

// MARK: Private methods

// Sets up the video capture session for the specified camera, quality and grayscale mode
//
//
// camera: -1 for default, 0 for back camera, 1 for front camera
// qualityPreset: [AVCaptureSession sessionPreset] value
// grayscale: YES to capture grayscale frames, NO to capture RGBA frames
//
- (BOOL)createCaptureSessionForCamera:(NSInteger)camera qualityPreset:(NSString *)qualityPreset grayscale:(BOOL)grayscale
{
    _lastFrameTimestamp = 0;
    _frameTimesIndex = 0;
    _captureQueueFps = 0.0f;
    _fps = 0.0f;
	
    // Set up AV capture
    NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    
    if ([devices count] == 0) {
        NSLog(@"No video capture devices found");
        return NO;
    }
    
    if (camera == -1) {
        _camera = -1;
        _captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    else if (camera >= 0 && camera < [devices count]) {
        _camera = camera;
        _captureDevice = [devices objectAtIndex:camera];
    }
    else {
        _camera = -1;
        _captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        NSLog(@"Camera number out of range. Using default camera");
    }
    
    // Create the capture session
    _captureSession = [[AVCaptureSession alloc] init];
    _captureSession.sessionPreset = (qualityPreset)? qualityPreset : AVCaptureSessionPresetMedium;
    
    // Create device input
    NSError *error = nil;
    AVCaptureDeviceInput *input = [[AVCaptureDeviceInput alloc] initWithDevice:_captureDevice error:&error];
    
    // Create and configure device output
    _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    dispatch_queue_t queue = dispatch_queue_create("cameraQueue", NULL); 
    [_videoOutput setSampleBufferDelegate:self queue:queue];
    dispatch_release(queue); 
    
    _videoOutput.alwaysDiscardsLateVideoFrames = YES; 
    _videoOutput.minFrameDuration = CMTimeMake(1, 30);
    
    
    // For grayscale mode, the luminance channel from the YUV fromat is used
    // For color mode, BGRA format is used
    OSType format = kCVPixelFormatType_32BGRA;

    // Check YUV format is available before selecting it (iPhone 3 does not support it)
    if (grayscale && [_videoOutput.availableVideoCVPixelFormatTypes containsObject:
                      [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]]) {
        format = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    }
    
    _videoOutput.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:format]
                                                             forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    
    // Connect up inputs and outputs
    if ([_captureSession canAddInput:input]) {
        [_captureSession addInput:input];
    }
    
    if ([_captureSession canAddOutput:_videoOutput]) {
        [_captureSession addOutput:_videoOutput];
    }
    
    
    // Create the preview layer
    _videoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_captureSession];
    [_videoPreviewLayer setFrame:self.view.bounds];
    _videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer insertSublayer:_videoPreviewLayer atIndex:0];   //设置视频帧layer
    
    return YES;
}

- (BOOL)setupWriter
{
    NSError *error = nil;
    self.assetWriter = [[AVAssetWriter alloc]
                        initWithURL:self.tempFileURL fileType:AVFileTypeMPEG4 error:&error];
    if (error != nil) {
        NSLog(@"AVAssetWriter alloc %@:%@", error, [self.assetWriter error]);
    }
    NSParameterAssert(self.assetWriter);
    NSDictionary *outputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithInt:480], AVVideoWidthKey,
                                    [NSNumber numberWithInt:360], AVVideoHeightKey,
                                    AVVideoCodecH264,AVVideoCodecKey,nil];
    
    //是不是用AVMediaTypeVideo？
    self.assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:outputSettings];
    self.assetWriterInput.expectsMediaDataInRealTime = YES;
    NSParameterAssert(self.assetWriterInput);
    
    self.pixelBufferAdaptor = [[AVAssetWriterInputPixelBufferAdaptor alloc] initWithAssetWriterInput:self.assetWriterInput sourcePixelBufferAttributes:
                               [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange],
                                kCVPixelBufferPixelFormatTypeKey, nil]];

    //NSLog([self.tempFileURL absoluteString]);
    NSParameterAssert(self.pixelBufferAdaptor);
    if ([self.assetWriter canAddInput:self.assetWriterInput]) {
        [self.assetWriter addInput:self.assetWriterInput];
        NSLog(@"assetWriter addInput success!%@", [self.assetWriter error]);
    }
    
    return YES;
}

- (void) removeFile:(NSURL *)fileURL
{
    NSString *filePath = [fileURL path];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:filePath]) {
        NSError *error;
        if ([fileManager removeItemAtPath:filePath error:&error] == NO) {
            NSLog(@"removeItemAtPath %@ error:%@", filePath, error);
        }
    }
}

// Tear down the video capture session
- (void)destroyCaptureSession
{
    [_captureSession stopRunning];
    
    [_videoPreviewLayer removeFromSuperlayer];
    
    _videoPreviewLayer = nil;
    _videoOutput = nil;
    _captureDevice = nil;
    _captureSession = nil;
}

- (void)updateDebugInfo {
    if (_fpsLabel) {
        _fpsLabel.text = [NSString stringWithFormat:@"FPS: %0.1f", _fps];
    }
}
@end
