#import "MetalGuestView.h"
#import "AppKitBridge.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <CoreText/CoreText.h>
#include <simd/simd.h>

typedef struct { vector_float2 position,uv;vector_float4 color; } Vertex;
@interface MetalGuestView ()
@property(strong) id<MTLDevice> device;
@property(strong) id<MTLCommandQueue> queue;
@property(strong) id<MTLRenderPipelineState> pipeline;
@property(strong) id<MTLTexture> white;
@property(strong) NSMutableDictionary<NSString *,id<MTLTexture>> *textCache;
@property(copy) NSString *rendererError;
@end
@implementation MetalGuestView
+ (Class)layerClass { return CAMetalLayer.class; }
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame]))return nil;
    self.device=MTLCreateSystemDefaultDevice();self.queue=[self.device newCommandQueue];
    self.textCache=[NSMutableDictionary dictionary];
    CAMetalLayer *layer=(CAMetalLayer *)self.layer;layer.device=self.device;layer.pixelFormat=MTLPixelFormatBGRA8Unorm;
    NSString *source=@"#include <metal_stdlib>\nusing namespace metal;\n"
      "struct V {float2 p;float2 uv;float4 c;};struct O{float4 p [[position]];float2 uv;float4 c;};"
      "vertex O vmain(uint i [[vertex_id]],constant V* v [[buffer(0)]],constant float2& size [[buffer(1)]]){"
      "O o;o.p=float4(v[i].p.x/size.x*2-1,1-v[i].p.y/size.y*2,0,1);o.uv=v[i].uv;o.c=v[i].c;return o;}"
      "fragment float4 fmain(O o [[stage_in]],texture2d<float> t [[texture(0)]]){"
      "constexpr sampler s(filter::linear,address::clamp_to_edge);return t.sample(s,o.uv)*o.c;}";
    NSError *error=nil;id<MTLLibrary> library=[self.device newLibraryWithSource:source options:nil error:&error];
    MTLRenderPipelineDescriptor *p=[MTLRenderPipelineDescriptor new];p.vertexFunction=[library newFunctionWithName:@"vmain"];p.fragmentFunction=[library newFunctionWithName:@"fmain"];
    p.colorAttachments[0].pixelFormat=layer.pixelFormat;p.colorAttachments[0].blendingEnabled=YES;
    p.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorOne;p.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    p.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;p.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    if(library)self.pipeline=[self.device newRenderPipelineStateWithDescriptor:p error:&error];
    self.rendererError=error.localizedDescription;
    uint32_t pixel=0xffffffff;self.white=[self texture:CGSizeMake(1,1) bytes:&pixel];
    self.accessibilityIdentifier=@"translated-mac-window";
    return self;
}
- (id<MTLTexture>)texture:(CGSize)size bytes:(const void *)bytes {
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:(NSUInteger)size.width height:(NSUInteger)size.height mipmapped:NO];
    d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
    id<MTLTexture> texture=[self.device newTextureWithDescriptor:d];
    if(bytes)[texture replaceRegion:MTLRegionMake2D(0,0,d.width,d.height) mipmapLevel:0 withBytes:bytes bytesPerRow:d.width*4];return texture;
}
- (id<MTLTexture>)text:(NSString *)text width:(NSUInteger)width height:(NSUInteger)height {
    NSString *key=[NSString stringWithFormat:@"%lux%lu:%@",(unsigned long)width,(unsigned long)height,text];
    id<MTLTexture> cached=self.textCache[key];if(cached)return cached;
    if(!width || !height || width>2048 || height>2048)return nil;
    void *bytes=calloc(height,width*4);CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(bytes,width,height,8,width*4,space,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);if(!context){free(bytes);return nil;}
    CTFontRef font=CTFontCreateWithName(CFSTR("Helvetica"),18,NULL);
    CGColorRef white=CGColorCreateGenericRGB(1,1,1,1);
    NSAttributedString *attributed=[[NSAttributedString alloc] initWithString:text attributes:@{(__bridge NSString *)kCTFontAttributeName:(__bridge id)font,(__bridge NSString *)kCTForegroundColorAttributeName:(__bridge id)white}];
    CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attributed);
    CGContextSetTextPosition(context,8,(height-18)/2.0+3);CTLineDraw(line,context);
    id<MTLTexture> result=[self texture:CGSizeMake(width,height) bytes:bytes];
    CFRelease(line);CGColorRelease(white);CFRelease(font);CGContextRelease(context);free(bytes);
    // Counter text changes indefinitely; bound the cache instead of retaining
    // every label ever produced by the guest.
    if(self.textCache.count>=64)[self.textCache removeAllObjects];
    if(result)self.textCache[key]=result;return result;
}
- (void)quad:(CGRect)r color:(vector_float4)c texture:(id<MTLTexture>)texture encoder:(id<MTLRenderCommandEncoder>)encoder {
    float x=r.origin.x,y=r.origin.y,w=r.size.width,h=r.size.height;
    Vertex vertices[]={{{x,y},{0,0},c},{{x+w,y},{1,0},c},{{x,y+h},{0,1},c},{{x+w,y},{1,0},c},{{x+w,y+h},{1,1},c},{{x,y+h},{0,1},c}};
    [encoder setVertexBytes:vertices length:sizeof vertices atIndex:0];[encoder setFragmentTexture:texture atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
}
- (id<MTLCommandBuffer>)encode:(id<MTLTexture>)texture size:(CGSize)size items:(NSArray<NSDictionary *> *)items drawable:(id<CAMetalDrawable>)drawable {
    if(!self.pipeline || !texture)return nil;
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=texture;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    pass.colorAttachments[0].clearColor=MTLClearColorMake(.07,.09,.13,1);
    id<MTLCommandBuffer> command=[self.queue commandBuffer];id<MTLRenderCommandEncoder> encoder=[command renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:self.pipeline];vector_float2 viewport={size.width,size.height};[encoder setVertexBytes:&viewport length:sizeof viewport atIndex:1];
    for(NSDictionary *item in items) {
        NSArray *a=item[@"rect"];CGRect r=CGRectMake([a[0] doubleValue],[a[1] doubleValue],[a[2] doubleValue],[a[3] doubleValue]);
        vector_float4 color={.15,.2,.3,1};
        if([item[@"kind"] isEqual:@"button"])color=(vector_float4){.18,.35,.62,1};
        if(item[@"color"]){NSArray *c=item[@"color"];color=(vector_float4){[c[0] floatValue],[c[1] floatValue],[c[2] floatValue],1};}
        if(![item[@"kind"] isEqual:@"label"])[self quad:r color:color texture:self.white encoder:encoder];
        if([item[@"text"] length]) {
            id<MTLTexture> text=[self text:item[@"text"] width:r.size.width height:r.size.height];
            if(text)[self quad:r color:(vector_float4){1,1,1,1} texture:text encoder:encoder];
        }
    }
    [encoder endEncoding];if(drawable)[command presentDrawable:drawable];[command commit];return command;
}
- (void)layoutSubviews { [super layoutSubviews];CGFloat scale=self.window.screen.scale?:1;((CAMetalLayer *)self.layer).drawableSize=CGSizeMake(self.bounds.size.width*scale,self.bounds.size.height*scale);[self renderGuest]; }
- (void)renderGuest {
    if(!self.window || self.bounds.size.width<=0 || self.bounds.size.height<=0)return;
    id<CAMetalDrawable> drawable=[(CAMetalLayer *)self.layer nextDrawable];if(!drawable)return;
    [self encode:drawable.texture size:mp_gui_size() items:mp_gui_draw_list() drawable:drawable];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;CGPoint p=[touches.anyObject locationInView:self];CGSize guest=mp_gui_size();
    p.x*=guest.width/self.bounds.size.width;p.y*=guest.height/self.bounds.size.height;
    if(mp_gui_touch(p) && self.inputObserved)self.inputObserved();[self renderGuest];
}
- (NSDictionary *)verifyRenderer {
    id<MTLTexture> texture=[self texture:CGSizeMake(64,64) bytes:NULL];
    NSArray *items=@[@{@"rect":@[@0,@0,@32,@64],@"color":@[@1,@0,@0]},@{@"rect":@[@32,@0,@32,@64],@"color":@[@0,@1,@0]}];
    id<MTLCommandBuffer> command=[self encode:texture size:CGSizeMake(64,64) items:items drawable:nil];[command waitUntilCompleted];
    uint8_t pixels[64*64*4]={0};if(texture)[texture getBytes:pixels bytesPerRow:64*4 fromRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0];
    BOOL passed=command && command.status==MTLCommandBufferStatusCompleted;
    for(unsigned y=0;y<64;y++)for(unsigned x=0;x<64;x++) {
        unsigned i=(y*64+x)*4;passed=passed && pixels[i]==0 && pixels[i+1]==(x>=32?255:0) && pixels[i+2]==(x<32?255:0) && pixels[i+3]==255;
    }
    return @{@"passed":@(passed),@"pixels_checked":@4096,@"device":self.device.name?:@"none",@"error":command.error.localizedDescription?:self.rendererError?:@""};
}
@end
