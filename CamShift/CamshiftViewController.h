//
//  CamshiftViewController.h
//  CamShift
//
//  Created by ios on 2/27/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "VideoCaptureViewController.h"

@interface CamshiftViewController : VideoCaptureViewController

//YUV格式中的 Y单通道 
@property (nonatomic) IplImage *image;
//反向投影
@property (nonatomic) IplImage *backproject;
//直方图
@property (nonatomic) CvHistogram *hist;


@property (nonatomic) CvRect track_window;
//捕捉到的box，在video image空间下
@property (nonatomic) CvBox2D track_box;
@property (nonatomic) CvConnectedComp track_comp;
//直方图bin个数
@property (nonatomic) int hdims;
//初始跟踪框，在video image空间下的坐标
@property (nonatomic) CvRect selection;

//手触选择的远点
@property (nonatomic) CGPoint selectOrigin;
//手触选择的Rect，也就是初始跟踪框， 在view空间下的坐标
@property (nonatomic) CGRect selectCGRect;

//  0 -- 在选择物体
// -1 -- 跟踪状态，但还没有进行属性提取
//  1 -- 跟踪状态，且已经进行了属性提取
@property (nonatomic) int trackObjectFlag;


- (IBAction)toggleTorch:(id)sender;
- (IBAction)toggleCamera:(id)sender;
- (IBAction)toggleFps:(id)sender;
@end
