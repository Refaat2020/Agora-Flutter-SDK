#import <Foundation/Foundation.h>
#import "TextureRenderer.h"
#import <AgoraRtcWrapper/iris_video_processor_cxx.h>
#import <AgoraRtcWrapper/iris_rtc_raw_data.h>
#import <Foundation/Foundation.h>

using namespace agora::iris;

@interface TextureRender ()

@property(nonatomic, weak) NSObject<FlutterTextureRegistry> *textureRegistry;
@property(nonatomic, strong) FlutterMethodChannel *channel;
@property(nonatomic) CVPixelBufferRef buffer_cache;
@property(nonatomic, strong) dispatch_semaphore_t lock;
@property(nonatomic) agora::iris::IrisVideoFrameBufferManager *videoFrameBufferManager;
@property(nonatomic) NSDictionary *cvBufferProperties;

@end

namespace {
class RendererDelegate : public IrisVideoFrameBufferDelegate {
public:
  RendererDelegate(void *renderer) : renderer_(renderer) {}

  void OnVideoFrameReceived(const IrisVideoFrame &video_frame,
                            const IrisVideoFrameBufferConfig *config,
                            bool resize) override {
    @autoreleasepool {
        TextureRender *renderer = (__bridge TextureRender *)renderer_;
        
        if (renderer.buffer_cache != NULL && resize) {
            CVBufferRelease(renderer.buffer_cache);
            renderer.buffer_cache = NULL;
        }
        
        CVPixelBufferRef buffer = renderer.buffer_cache;
        if (renderer.buffer_cache == NULL) {
            CVPixelBufferCreate(kCFAllocatorDefault, video_frame.width,
                                video_frame.height, kCVPixelFormatType_32BGRA,
                                (__bridge CFDictionaryRef)renderer.cvBufferProperties, &buffer);
            
            [renderer.channel invokeMethod:@"onSizeChanged"
                                 arguments:@{@"width": @(video_frame.width),
                                             @"height": @(video_frame.height)}];
        }
        
        CVPixelBufferLockBaseAddress(buffer, 0);
        void *copyBaseAddress = CVPixelBufferGetBaseAddress(buffer);
        memcpy(copyBaseAddress, video_frame.y_buffer,
               video_frame.y_buffer_length);
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        
        renderer.buffer_cache = buffer;

        [renderer.textureRegistry textureFrameAvailable:renderer.textureId];
    }
  }

public:
  void *renderer_;
};
}

@interface TextureRender ()

@property(nonatomic) RendererDelegate *delegate;

@end

@implementation TextureRender

- (instancetype) initWithTextureRegistry:(NSObject<FlutterTextureRegistry> *)textureRegistry
                               messenger:(NSObject<FlutterBinaryMessenger> *)messenger
                 videoFrameBufferManager:(void *)manager {
    self = [super init];
    if (self) {
      self.textureRegistry = textureRegistry;
        self.videoFrameBufferManager = (IrisVideoFrameBufferManager *)manager;
      self.textureId = [self.textureRegistry registerTexture:self];
      self.channel = [FlutterMethodChannel
          methodChannelWithName:
              [NSString stringWithFormat:@"agora_rtc_engine/texture_render_%lld",
                                         self.textureId]
                binaryMessenger:messenger];

      self.lock = dispatch_semaphore_create(1);
        
      self.cvBufferProperties = @{
          (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
          (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
          (__bridge NSString *)kCVPixelBufferOpenGLCompatibilityKey: @YES,
          (__bridge NSString *)kCVPixelBufferMetalCompatibilityKey: @YES,
        };
        
      self.delegate = new ::RendererDelegate((__bridge void *)self);
    }
    return self;
}

- (void)updateData:(NSNumber *)uid channelId:(NSString *)channelId videoSourceType:(NSNumber *)videoSourceType {
    IrisVideoFrameBuffer buffer(kVideoFrameTypeBGRA,
                                      self.delegate, 16);
    IrisVideoFrameBufferConfig config;
      
    config.id = [uid unsignedIntValue];
    config.type = (IrisVideoSourceType)[videoSourceType intValue];
    
      if (channelId && (NSNull *)channelId != [NSNull null]) {
          strcpy(config.key, [channelId UTF8String]);
          
      } else {
          strcpy(config.key, "");
      }
    
    self.videoFrameBufferManager->EnableVideoFrameBuffer(buffer, &config);
}

- (void)dispose {
    self.videoFrameBufferManager->DisableVideoFrameBuffer(self.delegate);
    if (self.delegate) {
        delete self.delegate;
    }
    [self.textureRegistry unregisterTexture:self.textureId];
    if (self.buffer_cache) {
      CVPixelBufferRelease(self.buffer_cache);
      self.buffer_cache = NULL;
    }
}

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
    return CVPixelBufferRetain(self.buffer_cache);
}

- (void)onTextureUnregistered:(NSObject<FlutterTexture> *)texture {
}

@end
    
