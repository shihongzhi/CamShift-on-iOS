//
//  CamshiftViewController.m
//  CamShift
//
//  Created by ios on 2/27/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "UIImage+OpenCV.h"
#import "CamshiftViewController.h"

@interface CamshiftViewController ()
- (void)displayEllipseBox:(CvBox2D)trackbox forVideoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)videoOrientation;
@end

@implementation CamshiftViewController

@synthesize image = _image;
@synthesize backproject = _backproject;
@synthesize hist = _hist;
@synthesize track_window = _track_window;
@synthesize track_box = _track_box;
@synthesize track_comp = _track_comp;
@synthesize hdims = _hdims;
@synthesize selection = _selection;

@synthesize selectOrigin = _selectOrigin;
@synthesize selectCGRect = _selectCGRect;
@synthesize trackObjectFlag = _trackObjectFlag;
@synthesize recordButton = _recordButton;

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    self.image = nil;
    self.hdims = 16;
    self.trackObjectFlag = 0;
    self.selectCGRect = CGRectMake(0, 0, 0, 0);
}

- (void)viewDidUnload
{
    [self setRecordButton:nil];
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;

}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (CGPoint)processFrame:(cv::Mat &)mat videoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)videOrientation {
    // Rotate video frame by 90deg to portrait by combining a transpose and a flip
    // Note that AVCaptureVideoDataOutput connection does NOT support hardware-accelerated
    // rotation and mirroring via videoOrientation and setVideoMirrored properties so we
    // need to do the rotation in software here.
    CGPoint location = CGPointMake(0, 0);
    cv::transpose(mat, mat);
    CGFloat temp = rect.size.width;
    rect.size.width = rect.size.height;
    rect.size.height = temp;
    
    if (videOrientation == AVCaptureVideoOrientationLandscapeRight)
    {
        // flip around y axis for back camera
        cv::flip(mat, mat, 1);
    }
    else {
        // Front camera output needs to be mirrored to match preview layer so no flip is required here
    }
    
    videOrientation = AVCaptureVideoOrientationPortrait;
    
    //process thing in here
    if (!self.image) {  //第一次，申请空间
        self.image = new IplImage(mat);
        
        self.backproject = cvCreateImage(cvGetSize(self.image), 8, 1);
        
        float hranges_arr[] = {16, 235};
        float* hranges = hranges_arr;
        self.hist = cvCreateHist(1, &_hdims, CV_HIST_ARRAY, &hranges, 1);
    }
    else  //每次都copy mat 数据
    {
        self.image = new IplImage(mat);
    }
    
    
    if (self.trackObjectFlag) {
        //还没有进行属性提取,进行属性提取
        if (self.trackObjectFlag < 0) {
            self.trackObjectFlag = 1;
            //对选择框坐标转换
            CGAffineTransform t = [self affineTransformForVideoFrame:rect orientation:videOrientation];
            CGAffineTransform invT = CGAffineTransformInvert(t);
            self.selectCGRect = CGRectApplyAffineTransform(self.selectCGRect, invT);
            
            CvRect tempSR;
            tempSR.x = self.selectCGRect.origin.x;
            tempSR.y = self.selectCGRect.origin.y;
            tempSR.width = self.selectCGRect.size.width;
            tempSR.height = self.selectCGRect.size.height;
            self.selection = tempSR;  //转换到video图片坐标下了
            
            float max_val = 0.0f;
            cvSetImageROI(self.image, self.selection);
            cvCalcHist(&_image, self.hist);
            cvGetMinMaxHistValue(self.hist, 0, &max_val, 0, 0);
            cvConvertScale(self.hist->bins, self.hist->bins, max_val ? 255. / max_val : 0., 0);
            cvResetImageROI(self.image);
            self.track_window = self.selection;
        }
        
        cvCalcBackProject(&_image, self.backproject, self.hist);
        cvCamShift(self.backproject, self.track_window, cvTermCriteria(CV_TERMCRIT_EPS | CV_TERMCRIT_ITER, 10, 1), &_track_comp, &_track_box);
        self.track_window = self.track_comp.rect;
        location.x = self.track_box.center.x;
        location.y = self.track_box.center.y;
        // Dispatch updating of tracker box  to main queue
        dispatch_sync(dispatch_get_main_queue(), ^{
            //display method in here
            [self displayEllipseBox:self.track_box forVideoRect:rect videoOrientation:videOrientation];
        });
    }
    //NSLog(@"location.x = %f; location.y = %f", location.x, location.y);
    return location;
}

- (void)displayEllipseBox:(CvBox2D)trackbox forVideoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)videoOrientation{
    NSArray *sublayers = [NSArray arrayWithArray:[self.view.layer sublayers]];
    int sublayersCount = [sublayers count];
    int currentSublayer = 0;
    
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    
    //hide
    for (CALayer *layer in sublayers) {
        NSString *layerName = [layer name];
        if ([layerName isEqualToString:@"camshift"]) {
            [layer setHidden:YES];
        }
    }
    
    CGAffineTransform t = [self affineTransformForVideoFrame:rect orientation:videoOrientation];
    CGRect targetRect; 
    targetRect.origin.x = trackbox.center.x - trackbox.size.width / 2;
    targetRect.origin.y = trackbox.center.y - trackbox.size.height / 2;
    targetRect.size.width = trackbox.size.width;
    targetRect.size.height = trackbox.size.height;
    //显示框转换到view坐标下
    targetRect = CGRectApplyAffineTransform(targetRect, t);
    
    CALayer *featurelayer = nil;
    while (!featurelayer && (currentSublayer < sublayersCount)) {
        CALayer *currentlayer = [sublayers objectAtIndex:currentSublayer++];
        if ([[currentlayer name] isEqualToString:@"camshift"]) {
            featurelayer = currentlayer;
            [currentlayer setHidden:NO];
        }
    }
    if (!featurelayer) {
        featurelayer = [[CALayer alloc] init];
        featurelayer.name = @"camshift";
        featurelayer.borderColor = [[UIColor redColor] CGColor];
        featurelayer.borderWidth = 10.0f;
        [self.view.layer addSublayer:featurelayer];
        //[featurelayer release];
    }
    featurelayer.frame = targetRect;
    
    [CATransaction commit];
    
}

- (IBAction)toggleRecord:(id)sender {
    //start record video
    if (!self.isRecoding) {
        if ([self.assetWriter status] == AVAssetWriterStatusCompleted) {
            NSError *error = nil;
            self.assetWriter = [[AVAssetWriter alloc]
                                initWithURL:self.tempFileURL fileType:AVFileTypeMPEG4 error:&error];
            if ([self.assetWriter canAddInput:self.assetWriterInput]) {
                [self.assetWriter addInput:self.assetWriterInput];
                NSLog(@"assetWriter addInput success!%@", [self.assetWriter error]);
            }
        }
        self.frameNumber = 0;
        
        NSLog(@"start video recording...");
        if (!self.assetWriter) {
            NSLog(@"Setup writer failed");
            return;
        }
        self.isRecoding = YES;
        [self.recordButton setTitle:@"Stop" forState:UIControlStateNormal];
        //caution
        [self removeFile:self.tempFileURL];
        [self.lightPath removeAllObjects];
        if(![self.assetWriter startWriting]){
            NSLog(@"assetWriter startWriting error!");
            NSLog(@"%@", [self.assetWriter error]);
        }
        [self.assetWriter startSessionAtSourceTime:kCMTimeZero];
    }
    else //finish the record
    {
        NSLog(@"finish video recording...");
        self.isRecoding = NO;
        [self.recordButton setTitle:@"Record" forState:UIControlStateNormal];
        if (![self.assetWriter finishWriting]) {
            NSLog(@"assetWriter finishWriting error!");
        }
        NSLog(@"stopped record");
        ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
		[library writeVideoAtPathToSavedPhotosAlbum:self.tempFileURL
									completionBlock:^(NSURL *assetURL, NSError *error) {
										if (error) {
											NSLog(@"writeVideoAtPathToSavedPhotosAlbum%@", error);										
										}
										
									}];
    }
}

- (IBAction)toggleTorch:(id)sender {
    self.torchOn = !self.torchOn;
}

- (IBAction)toggleCamera:(id)sender {
    if (self.camera == 1) {
        self.camera = 0;
    }
    else{
        self.camera = 1;
    }
}

- (IBAction)toggleFps:(id)sender {
    self.showDebugInfo = !self.showDebugInfo;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	NSLog(@"touchesBegan");
    UITouch *touch = [touches anyObject];
    CGPoint pt = [touch locationInView:[touch view]];
    NSLog(@"point = %1f, %1f", pt.x, pt.y);
    self.selectOrigin = pt;
    self.trackObjectFlag = 0;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
	NSLog(@"touchesMoved");
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    //还没有加入其他坐标大小比较情况
	NSLog(@"touchesEnded");
    UITouch *touch = [touches anyObject];
    CGPoint pt = [touch locationInView:[touch view]];
    NSLog(@"point = %1f, %1f", pt.x, pt.y);
    //判断各种选择情况
    float minX, minY, sWidth, sHeight;
    if (pt.x < self.selectOrigin.x) {
        minX = pt.x;
        sWidth = self.selectOrigin.x - pt.x;
    }
    else{
        minX = self.selectOrigin.x;
        sWidth = pt.x - self.selectOrigin.x;
    }
    if (pt.y < self.selectOrigin.y) {
        minY = pt.y;
        sHeight = self.selectOrigin.y - pt.y;
    }
    else{
        minY = self.selectOrigin.y;
        sHeight = pt.y - self.selectOrigin.y;
    }
    if (minX < 0) {
        minX = 0;
    }
    if (minY < 0) {
        minY = 0;
    }
    if (sWidth > 320.0) {
        sWidth = 320.0;
    }
    if (sHeight > 460.0) {
        sHeight = 460.0;
    }

    if (sWidth > 0 && sHeight > 0) {
        self.selectCGRect = CGRectMake(minX,minY, sWidth, sHeight);
        self.trackObjectFlag = -1;
    }
}

@end
