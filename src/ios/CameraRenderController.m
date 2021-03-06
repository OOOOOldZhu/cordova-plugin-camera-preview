#import "CameraRenderController.h"
#import <CoreVideo/CVOpenGLESTextureCache.h>
#import <GLKit/GLKit.h>
#import <OpenGLES/ES2/glext.h>

@implementation CameraRenderController
@synthesize context = _context;
@synthesize delegate;


- (CameraRenderController *)init {
    if (self = [super init]) {
        self.renderLock = [[NSLock alloc] init];
    }
    return self;
}

- (void)loadView {
    GLKView *glkView = [[GLKView alloc] init];
    [glkView setBackgroundColor:[UIColor blackColor]];
    [self setView:glkView];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }

    CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, self.context, NULL, &_videoTextureCache);
    if (err) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
        return;
    }
}

- (void)viewDidLayoutSubviews{

    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    view.contentMode = UIViewContentModeScaleToFill;
    // 父控件中添加子控件
    UIButton * button = [UIButton buttonWithType:UIButtonTypeCustom];
    CGFloat width = 70,height = width;
    // button.frame = CGRectMake(self.view.frame.size.width/2.0-width/2.0, self.view.frame.size.height-height-100, width, height) ;
    button.frame = CGRectMake(self.view.bounds.size.width-width-width/2,
                              self.view.bounds.size.height/2-height/2,
                              width,
                              height);
    button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    UIImage * image = [UIImage imageNamed:@"button"];
    UIEdgeInsets Imageinset = {0,0,0,0};
    [button setImageEdgeInsets:Imageinset];
    [button setImage:image forState:UIControlStateSelected];
    [button setImage:image forState:UIControlStateNormal];
    // 点上去发一下光
    button.showsTouchWhenHighlighted  = YES;
    [button addTarget:self action:@selector(onTakeBtn) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:button];

    UIButton * closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    // button.frame = CGRectMake(self.view.frame.size.width/2.0-width/2.0, self.view.frame.size.height-height-100, width, height) ;
    closeBtn.frame = CGRectMake(self.view.bounds.size.width-width-width/2,
                                height/2,
                                50,
                                50);
    [closeBtn setImageEdgeInsets:Imageinset];
    UIImage * image1 = [UIImage imageNamed:@"close"];
    [closeBtn setImage:image1 forState:UIControlStateSelected];
    [closeBtn setImage:image1 forState:UIControlStateNormal];
    closeBtn.showsTouchWhenHighlighted  = YES;
    [closeBtn addTarget:self action:@selector(onCloseBtn) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:closeBtn];

    UIButton * turnBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    // button.frame = CGRectMake(self.view.frame.size.width/2.0-width/2.0, self.view.frame.size.height-height-100, width, height) ;
    turnBtn.frame = CGRectMake(self.view.bounds.size.width-width-width/2,
                               self.view.bounds.size.height - height*1.5,
                               50,
                               50);
    [turnBtn setImageEdgeInsets:Imageinset];
    UIImage * image2 = [UIImage imageNamed:@"turn"];
    [turnBtn setImage:image2 forState:UIControlStateSelected];
    [turnBtn setImage:image2 forState:UIControlStateNormal];
    turnBtn.showsTouchWhenHighlighted  = YES;
    [turnBtn addTarget:self action:@selector(onTurnBtn) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:turnBtn];

    glGenRenderbuffers(1, &_renderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _renderBuffer);

    self.ciContext = [CIContext contextWithEAGLContext:self.context];

    if (self.dragEnabled) {
        //add drag action listener
        NSLog(@"Enabling view dragging");
        UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self.view addGestureRecognizer:drag];
    }

    if (self.tapToFocus && self.tapToTakePicture){
        //tap to focus and take picture
        UITapGestureRecognizer *tapToFocusAndTakePicture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector (handleFocusAndTakePictureTap:)];
        [self.view addGestureRecognizer:tapToFocusAndTakePicture];

    } else if (self.tapToFocus){
        // tap to focus
        UITapGestureRecognizer *tapToFocusGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector (handleFocusTap:)];
        [self.view addGestureRecognizer:tapToFocusGesture];

    } else if (self.tapToTakePicture) {
        //tap to take picture
        // UITapGestureRecognizer *takePictureTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTakePictureTap:)];
        // [self.view addGestureRecognizer:takePictureTap];
    }

    self.view.userInteractionEnabled = self.dragEnabled || self.tapToTakePicture || self.tapToFocus;

}



- (void) onCloseBtn{
    NSLog(@"onCloseBtn -----");
    // CDVInvokedUrlCommand *command  = [[CDVInvokedUrlCommand alloc] init];
    [self.delegate stopCamera:NULL];

    [self.delegate sendDataToJs:@"close"];
}
- (void) onTakeBtn{
    NSLog(@"onTakeBtn -----");
    [self.delegate takePicture:NULL];
}
- (void) onTurnBtn{
    NSLog(@"onTurnBtn-----");
    CDVInvokedUrlCommand *command  = [[CDVInvokedUrlCommand alloc] init];
    [self.delegate switchCamera:command];
}
- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appplicationIsActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationEnteredForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];

    dispatch_async(self.sessionManager.sessionQueue, ^{
        NSLog(@"Starting session");
        [self.sessionManager.session startRunning];
    });
}

- (void) viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidBecomeActiveNotification
                                                  object:nil];

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationWillEnterForegroundNotification
                                                  object:nil];

    dispatch_async(self.sessionManager.sessionQueue, ^{
        NSLog(@"Stopping session");
        [self.sessionManager.session stopRunning];
    });
}

- (void) handleFocusAndTakePictureTap:(UITapGestureRecognizer*)recognizer {
    NSLog(@"handleFocusAndTakePictureTap");

    // let the delegate take an image, the next time the image is in focus.
    [self.delegate invokeTakePictureOnFocus];

    // let the delegate focus on the tapped point.
    [self handleFocusTap:recognizer];
}

- (void) handleTakePictureTap:(UITapGestureRecognizer*)recognizer {
    NSLog(@"handleTakePictureTap");
    [self.delegate invokeTakePicture];
}

- (void) handleFocusTap:(UITapGestureRecognizer*)recognizer {
    NSLog(@"handleTapFocusTap");

    if (recognizer.state == UIGestureRecognizerStateEnded)    {
        CGPoint point = [recognizer locationInView:self.view];
        [self.delegate invokeTapToFocus:point];
    }
}

- (void) onFocus{
    [self.delegate invokeTakePicture];
}

- (IBAction)handlePan:(UIPanGestureRecognizer *)recognizer {
    CGPoint translation = [recognizer translationInView:self.view];
    recognizer.view.center = CGPointMake(recognizer.view.center.x + translation.x,
                                         recognizer.view.center.y + translation.y);
    [recognizer setTranslation:CGPointMake(0, 0) inView:self.view];
}

- (void) appplicationIsActive:(NSNotification *)notification {
    dispatch_async(self.sessionManager.sessionQueue, ^{
        NSLog(@"Starting session");
        [self.sessionManager.session startRunning];
    });
}

- (void) applicationEnteredForeground:(NSNotification *)notification {
    dispatch_async(self.sessionManager.sessionQueue, ^{
        NSLog(@"Stopping session");
        [self.sessionManager.session stopRunning];
    });
}

-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if ([self.renderLock tryLock]) {
        CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
        CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];


        CGFloat scaleHeight = self.view.frame.size.height/image.extent.size.height;
        CGFloat scaleWidth = self.view.frame.size.width/image.extent.size.width;

        CGFloat scale, x, y;
        if (scaleHeight < scaleWidth) {
            scale = scaleWidth;
            x = 0;
            y = ((scale * image.extent.size.height) - self.view.frame.size.height ) / 2;
        } else {
            scale = scaleHeight;
            x = ((scale * image.extent.size.width) - self.view.frame.size.width )/ 2;
            y = 0;
        }

        // scale - translate
        CGAffineTransform xscale = CGAffineTransformMakeScale(scale, scale);
        CGAffineTransform xlate = CGAffineTransformMakeTranslation(-x, -y);
        CGAffineTransform xform =  CGAffineTransformConcat(xscale, xlate);

        CIFilter *centerFilter = [CIFilter filterWithName:@"CIAffineTransform"  keysAndValues:
                                  kCIInputImageKey, image,
                                  kCIInputTransformKey, [NSValue valueWithBytes:&xform objCType:@encode(CGAffineTransform)],
                                  nil];

        CIImage *transformedImage = [centerFilter outputImage];

        // crop
        CIFilter *cropFilter = [CIFilter filterWithName:@"CICrop"];
        CIVector *cropRect = [CIVector vectorWithX:0 Y:0 Z:self.view.frame.size.width W:self.view.frame.size.height];
        [cropFilter setValue:transformedImage forKey:kCIInputImageKey];
        [cropFilter setValue:cropRect forKey:@"inputRectangle"];
        CIImage *croppedImage = [cropFilter outputImage];

        //fix front mirroring
        if (self.sessionManager.defaultCamera == AVCaptureDevicePositionFront) {
            CGAffineTransform matrix = CGAffineTransformTranslate(CGAffineTransformMakeScale(-1, 1), 0, croppedImage.extent.size.height);
            croppedImage = [croppedImage imageByApplyingTransform:matrix];
        }

        self.latestFrame = croppedImage;

        CGFloat pointScale;
        if ([[UIScreen mainScreen] respondsToSelector:@selector(nativeScale)]) {
            pointScale = [[UIScreen mainScreen] nativeScale];
        } else {
            pointScale = [[UIScreen mainScreen] scale];
        }
        CGRect dest = CGRectMake(0, 0, self.view.frame.size.width*pointScale, self.view.frame.size.height*pointScale);

        [self.ciContext drawImage:croppedImage inRect:dest fromRect:[croppedImage extent]];
        [self.context presentRenderbuffer:GL_RENDERBUFFER];
        [(GLKView *)(self.view)display];
        [self.renderLock unlock];
    }
}

- (void)viewDidUnload {
    [super viewDidUnload];

    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
    self.context = nil;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc. that aren't in use.
}

- (BOOL)shouldAutorotate {
    return YES;
}

-(void) willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [self.sessionManager updateOrientation:[self.sessionManager getCurrentOrientation:toInterfaceOrientation]];
}

@end
