//
//  FLCameraHelp.m
//  Droponto
//
//  Created by Fan Lv on 14-5-22.
//  Copyright (c) 2014年 Haoqi. All rights reserved.
//

#import "FLCameraHelp.h"
#import <ImageIO/ImageIO.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>




@interface FLCameraHelp ()<AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate>

@property (strong,nonatomic) UIImage *image;
@property (assign,nonatomic) UIImageOrientation g_orientation;
@property (assign,nonatomic) AVCaptureVideoPreviewLayer *preview;



@property (nonatomic) dispatch_queue_t videoDataOutputQueue;
@property (nonatomic) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic) AVCaptureAudioDataOutput *audioDataOutput;
@property (nonatomic) dispatch_queue_t audioQueue;


@end


@implementation FLCameraHelp
@synthesize session,captureOutput,g_orientation;
@synthesize preview,videoDataOutput;


- (void)initializeWithPreset:(NSString *)sessionPreset
{
    //1.创建会话层
    self.session = [[AVCaptureSession alloc] init];

    if ([session canSetSessionPreset:sessionPreset])
    {
        session.sessionPreset = sessionPreset;
    }
    else if ([session canSetSessionPreset:AVCaptureSessionPresetHigh])
    {
        session.sessionPreset = AVCaptureSessionPresetHigh;
    }
    else if ([session canSetSessionPreset:AVCaptureSessionPresetMedium])
    {
        session.sessionPreset = AVCaptureSessionPresetMedium;
    }
    else  if ([session canSetSessionPreset:AVCaptureSessionPresetLow])
    {
        session.sessionPreset = AVCaptureSessionPresetLow;
    }

    
    //-------------------------------------视频--------------------------------------
    //--------------------------创建、配置 视频输入设备
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    int flags = NSKeyValueObservingOptionNew; //监听自动对焦
    [device addObserver:self forKeyPath:@"adjustingFocus" options:flags context:nil];
	NSError *error;
	AVCaptureDeviceInput *captureInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
	if (!captureInput)
	{
		NSLog(@"Error: %@", error);
		return;
	}
    [self.session addInput:captureInput];

    if ([device isFlashAvailable])
    {
        if ( [device lockForConfiguration:NULL] == YES )
        {
            [device setFlashMode:AVCaptureFlashModeAuto];
            [device unlockForConfiguration];
        }
        else
        {
            NSLog(@"NO--lockForConfiguration");
        }
    }
    videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    if ([session canAddOutput:videoDataOutput])
    {
        [session addOutput:videoDataOutput];
        
        //--------------------------创建、配置输出
        _vedioConnection = [videoDataOutput connectionWithMediaType:AVMediaTypeVideo];

        // Configure your output.
        self.videoDataOutputQueue = dispatch_queue_create("videoDataOutput", NULL);
        [videoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
        
#if encodeModel
        // nv12
        NSDictionary *settings = [[NSDictionary alloc] initWithObjectsAndKeys:
                                  [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange],
                                  kCVPixelBufferPixelFormatTypeKey,
                                  nil];
#else
        // 32bgra
        NSDictionary *settings = [[NSDictionary alloc] initWithObjectsAndKeys:
                                  [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA],
                                  kCVPixelBufferPixelFormatTypeKey,
                                  nil];
#endif
        // Specify the pixel format
        videoDataOutput.videoSettings = settings;
        videoDataOutput.alwaysDiscardsLateVideoFrames = YES;
        
    }
    //-------------------------------------------------------------------------------

    //-------------------------------------音频--------------------------------------
    //---------------------------音频输出
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
    if (error) {
        NSLog(@"Error getting video input device: %@", error.description);
    }
    if ([self.session canAddInput:audioInput]) {
        [self.session addInput:audioInput];
        
        //---------------------------配置采集输出，即我们取得音频的接口
        self.audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
        
        if ([self.session canAddOutput:self.audioDataOutput]) {
            [session addOutput:self.audioDataOutput];
            // 保存Connection，用于在SampleBufferDelegate中判断数据来源（是Video/Audio？）
            self.audioConnection = [self.audioDataOutput connectionWithMediaType:AVMediaTypeAudio];
            self.audioQueue = dispatch_queue_create("Audio Capture Queue", DISPATCH_QUEUE_SERIAL);
            [self.audioDataOutput setSampleBufferDelegate:self queue:self.audioQueue];
        }
    }
    //-------------------------------------------------------------------------------
    captureOutput = [[AVCaptureStillImageOutput alloc] init];
    NSDictionary *outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys:AVVideoCodecJPEG,AVVideoCodecKey,nil];
    [captureOutput setOutputSettings:outputSettings];
	[self.session addOutput:captureOutput];
}

- (id) init
{
	if (self = [super init])
        [self initializeWithPreset:@""];
	return self;
}

- (id)initWithPreset:(NSString *)preset
{
    if (self = [super init])
        [self initializeWithPreset:preset];
    return self;
}


- (BOOL)switchCamera
{
    //Change camera source
    if(self.session)
    {
        //Indicate that some changes will be made to the session
        [self.session beginConfiguration];
        //Remove existing input
        AVCaptureInput* currentCameraInput = [self.session.inputs objectAtIndex:0];
        //Get new input
        AVCaptureDevice *newCamera = nil;
        if(((AVCaptureDeviceInput*)currentCameraInput).device.position == AVCaptureDevicePositionBack)
        {
            newCamera = [self cameraWithPosition:AVCaptureDevicePositionFront];
        }
        else
        {
            newCamera = [self cameraWithPosition:AVCaptureDevicePositionBack];
        }
        if(newCamera)
        {
            [self.session removeInput:currentCameraInput];
            //Add input to session
            AVCaptureDeviceInput *newVideoInput = [[AVCaptureDeviceInput alloc] initWithDevice:newCamera error:nil];
            [self.session addInput:newVideoInput];
            //Commit all the configuration changes at once
            [self.session commitConfiguration];
            return YES;
        }
        else
        {
            NSLog(@"不能切换摄像头");
        }
    }
    
    return NO;
}

// Find a camera with the specified AVCaptureDevicePosition, returning nil if one is not found
- (AVCaptureDevice *) cameraWithPosition:(AVCaptureDevicePosition) position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices)
    {
        if ([device position] == position) return device;
    }
    return nil;
}


//对焦回调
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if( [keyPath isEqualToString:@"adjustingFocus"] ){
        BOOL adjustingFocus = [ [change objectForKey:NSKeyValueChangeNewKey] isEqualToNumber:[NSNumber numberWithInt:1] ];
//        NSLog(@"Is adjusting focus? %@", adjustingFocus ? @"YES" : @"NO" );
//        NSLog(@"Change dictionary: %@", change);
        if (self.delegate && [self.delegate respondsToSelector:@selector(foucusStatus:)]) {
            [self.delegate foucusStatus:adjustingFocus];
        }
    }
}


-(void) embedPreviewInView: (UIView *) aView {
    if (!session) return;
    //设置取景
    preview = [AVCaptureVideoPreviewLayer layerWithSession: session];
    preview.frame = aView.bounds;
    preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [aView.layer addSublayer: preview];
}

- (void)changePreviewOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (!preview) {
        return;
    }
    [CATransaction begin];
    if (interfaceOrientation == UIInterfaceOrientationLandscapeRight) {
        g_orientation = UIImageOrientationUp;
        preview.connection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
        
    }else if (interfaceOrientation == UIInterfaceOrientationLandscapeLeft){
        g_orientation = UIImageOrientationDown;
        preview.connection.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
        
    }else if (interfaceOrientation == UIDeviceOrientationPortrait){
        g_orientation = UIImageOrientationRight;
        preview.connection.videoOrientation = AVCaptureVideoOrientationPortrait;
        
    }else if (interfaceOrientation == UIDeviceOrientationPortraitUpsideDown){
        g_orientation = UIImageOrientationLeft;
        preview.connection.videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
    }
    [CATransaction commit];
}

-(void)giveImg2Delegate
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(didFinishedCapture:)]) {
        [self.delegate didFinishedCapture:_image];
    }
}

-(void)Captureimage
{
    //get connection
    AVCaptureConnection *videoConnection = nil;
    for (AVCaptureConnection *connection in captureOutput.connections) {
        for (AVCaptureInputPort *port in [connection inputPorts]) {
            if ([[port mediaType] isEqual:AVMediaTypeVideo] ) {
                videoConnection = connection;
                break;
            }
        }
        if (videoConnection) { break; }
    }
    
    //get UIImage
    [captureOutput captureStillImageAsynchronouslyFromConnection:videoConnection completionHandler:
     ^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
         CFDictionaryRef exifAttachments =
         CMGetAttachment(imageSampleBuffer, kCGImagePropertyExifDictionary, NULL);
         if (exifAttachments) {
             // Do something with the attachments.
         }
         
         
         @try {
             if (imageSampleBuffer != nil)
             {
                 // Continue as appropriate.
                 NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageSampleBuffer];
                 UIImage *t_image = [UIImage imageWithData:imageData];
                 _image = [[UIImage alloc]initWithCGImage:t_image.CGImage scale:1.0 orientation:g_orientation];

             }

         }
         @catch (NSException *exception) {
             NSLog(@"exception : %@",exception);
         }
         @finally {
             [self giveImg2Delegate];
         }
         
     }];
}

- (void) dealloc
{
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [device removeObserver:self forKeyPath:@"adjustingFocus"];
    
	self.session = nil;
	self.image = nil;
    
    self.videoDataOutput=nil;
    self.videoDataOutputQueue=nil;
    [self.preview removeFromSuperlayer];
    self.session=nil;
    self.preview=nil;
    
}

#pragma mark Class Interface


- (void) startRunning
{
	[[self session] startRunning];
}

- (void) stopRunning
{
	[[self session] stopRunning];
}

-(void)captureStillImage
{
    [self  Captureimage];
}

- (void)setFlashLightMode:(int)mode
{
    AVCaptureInput* currentCameraInput = [self.session.inputs objectAtIndex:0];
    AVCaptureDevice *device = ((AVCaptureDeviceInput*)currentCameraInput).device;
    if ([device isFlashAvailable])
    {
        if ( [device lockForConfiguration:NULL] == YES )
        {
            [device setFlashMode:mode];
            [device unlockForConfiguration];
        }
    }

}


#pragma mark - VideoData OutputSampleBuffer Delegate


//NSData* imageToBuffer(CMSampleBufferRef source)

- (NSData*)cmSampleBufferRefToData:(CMSampleBufferRef)source
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(source);
    CVPixelBufferLockBaseAddress(imageBuffer,0);
    
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
//    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    void *src_buff = CVPixelBufferGetBaseAddress(imageBuffer);
    
    NSData *data = [NSData dataWithBytes:src_buff length:bytesPerRow * height];
    
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    return data ;
}



- (void)captureOutput:(AVCaptureFileOutput *)captureOutput1 didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)])
    {
        [self.delegate captureOutput:captureOutput1 didOutputSampleBuffer:sampleBuffer fromConnection:connection];
    }
    
    if(self.delegate && [self.delegate respondsToSelector:@selector(onOutputDataSteam:)]){
        NSData *data = [self cmSampleBufferRefToData:sampleBuffer];
        [self.delegate onOutputDataSteam:data];
    }
    
    if(self.delegate && [self.delegate respondsToSelector:@selector(onOutputImageSteam:)]){
        UIImage *t_image = [self imageFromSampleBuffer:sampleBuffer];
        
        // Continue as appropriate.
//        NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:sampleBuffer];
//        UIImage *t_image = [UIImage imageWithData:imageData];
        _image = [[UIImage alloc] initWithCGImage:t_image.CGImage scale:1.0 orientation:g_orientation];
        [self.delegate onOutputImageSteam:_image];
        
    }
}


// 通过抽样缓存数据创建一个UIImage对象
- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer
{
    // 为媒体数据设置一个CMSampleBuffer的Core Video图像缓存对象
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // 锁定pixel buffer的基地址
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // 得到pixel buffer的基地址
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // 得到pixel buffer的行字节数
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // 得到pixel buffer的宽和高
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    // 创建一个依赖于设备的RGB颜色空间
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // 用抽样缓存的数据创建一个位图格式的图形上下文（graphics context）对象
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // 根据这个位图context中的像素数据创建一个Quartz image对象
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // 解锁pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    // 释放context和颜色空间
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // 用Quartz image创建一个UIImage对象image
    UIImage *imageTemp = [UIImage imageWithCGImage:quartzImage];
    
    // 释放Quartz image对象
    CGImageRelease(quartzImage);
    
    return imageTemp;
}


//    NSArray *devices = [AVCaptureDevice devices];
//
//    for (AVCaptureDevice *device in devices)
//    {
//        NSLog(@"Device name: %@", [device localizedName]);
//        if ([device hasMediaType:AVMediaTypeVideo])
//        {
//            if ([device position] == AVCaptureDevicePositionBack)
//            {
//                NSLog(@"Device position : back");
//                backFacingCameraDeviceInput =[AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
//            }
//            else
//            {
//                NSLog(@"Device position : front");
//                frontFacingCameraDeviceInput =[AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
//            }
//        }
//
//    }


@end
