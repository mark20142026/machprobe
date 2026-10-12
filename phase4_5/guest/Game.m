// Native macOS game: AppKit lifecycle/events, MetalKit presentation, Metal rendering.
// There is no iOS target or compatibility renderer in this translation unit.
#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>
#import <objc/runtime.h>
#include <time.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

typedef struct {vector_float4 position,normal,uv;} Vertex;
typedef struct {matrix_float4x4 mvp,model;vector_float4 tint;} Uniforms;
static NSWindow *window;static MTKView *view;static id delegate,monitor;
static Class delegateClass;
static id<MTLDevice> device;static id<MTLCommandQueue> queue;
static id<MTLRenderPipelineState> pipeline;static id<MTLDepthStencilState> depth,always;
static id<MTLBuffer> vertices,indices;static id<MTLTexture> checker;
static id<MTLCommandBuffer> pending[3];
static uint64_t frames,completed,errors,skips,events,actions,draws;
static unsigned libraries,pipelines,buffers,textures,waits;
static double start,last,totalCPU,maxFrame,gpuSeconds,compileSeconds;
static float cameraX,cameraZ=6,yaw,angle;static BOOL keys[128],spinning=YES;
static NSString *failure;static BOOL running;
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec*1e-9;}
static double cpu(void){struct timespec t;clock_gettime(CLOCK_THREAD_CPUTIME_ID,&t);return t.tv_sec+t.tv_nsec*1e-9;}
static matrix_float4x4 identity(void){return matrix_identity_float4x4;}
static matrix_float4x4 translate(float x,float y,float z){matrix_float4x4 m=identity();m.columns[3]=(vector_float4){x,y,z,1};return m;}
static matrix_float4x4 scale(float x,float y,float z){matrix_float4x4 m=identity();m.columns[0].x=x;m.columns[1].y=y;m.columns[2].z=z;return m;}
static matrix_float4x4 rotate(float a){float c=cosf(a),s=sinf(a);matrix_float4x4 m=identity();m.columns[0]=(vector_float4){c,0,-s,0};m.columns[2]=(vector_float4){s,0,c,0};return m;}
static matrix_float4x4 perspective(float aspect){float y=1/tanf(.55f),z=60.0f/(.1f-60.0f);return (matrix_float4x4){{{y/aspect,0,0,0},{0,y,0,0},{0,0,z,-1},{0,0,z*.1f,0}}};}
static void retire(unsigned slot,BOOL wait){
    id<MTLCommandBuffer> c=pending[slot];if(!c)return;
    if(wait){[c waitUntilCompleted];waits++;}
    if(c.status==MTLCommandBufferStatusCompleted || c.status==MTLCommandBufferStatusError){
        if(c.status==MTLCommandBufferStatusError){errors++;[failure release];failure=[c.error.description copy];}
        else {completed++;if(c.GPUEndTime>=c.GPUStartTime)gpuSeconds+=c.GPUEndTime-c.GPUStartTime;}
        [c release];pending[slot]=nil;
    }
}
static void object(id<MTLRenderCommandEncoder> e,matrix_float4x4 vp,matrix_float4x4 model,vector_float4 tint){
    Uniforms u={simd_mul(vp,model),model,tint};
    [e setVertexBytes:&u length:sizeof u atIndex:1];
    [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:36 indexType:MTLIndexTypeUInt16 indexBuffer:indices indexBufferOffset:0];draws++;
}
static void encode(id<MTLRenderCommandEncoder> e,float aspect,BOOL verification,BOOL useDepth){
    [e setRenderPipelineState:pipeline];[e setDepthStencilState:useDepth?depth:always];
    [e setVertexBuffer:vertices offset:0 atIndex:0];[e setFragmentTexture:checker atIndex:0];
    matrix_float4x4 p=perspective(aspect);
    if(verification){
        // Near red cube first, farther blue cube last: a disabled depth test must change the center pixel.
        object(e,p,translate(0,0,-3),(vector_float4){1,.05,.05,1});
        object(e,p,simd_mul(translate(0,0,-5),scale(2,2,2)),(vector_float4){.05,.05,1,1});
        return;
    }
    matrix_float4x4 vp=simd_mul(p,simd_mul(rotate(-yaw),translate(-cameraX,-2,-cameraZ)));
    object(e,vp,simd_mul(translate(0,-.4,0),scale(8,.3,8)),(vector_float4){.5,.8,.55,1});
    object(e,vp,simd_mul(translate(0,1,-5),scale(8,3,.3)),(vector_float4){.45,.5,.65,1});
    for(int i=0;i<4;i++) {
        matrix_float4x4 model=simd_mul(translate((i-1.5f)*1.65f,.55f+.15f*sinf(angle+i),-i*.6f),rotate(angle+i));
        object(e,vp,model,(vector_float4){.35f+.2f*i,.85f-.15f*i,.9f-.16f*i,1});
    }
}
static void draw(id self,SEL sel,MTKView *v){
    (void)self;(void)sel;if(!running || !pipeline)return;
    @autoreleasepool {
        double begin=now(),cpuStart=cpu();unsigned slot=(unsigned)(frames%3);retire(slot,NO);
        if(pending[slot]){skips++;return;}
        double dt=last?begin-last:1.0/30;last=begin;if(dt>maxFrame)maxFrame=dt;float step=fmin(dt,.1);
        float forward=(keys['w']?1:0)-(keys['s']?1:0),side=(keys['d']?1:0)-(keys['a']?1:0);
        cameraX+=(sinf(yaw)*forward+cosf(yaw)*side)*step*2;
        cameraZ+=(-cosf(yaw)*forward+sinf(yaw)*side)*step*2;
        yaw+=((keys['l']?1:0)-(keys['j']?1:0))*step;
        cameraX=fmaxf(-6,fminf(6,cameraX));cameraZ=fmaxf(1,fminf(10,cameraZ));
        if(spinning)angle+=step*.7;
        MTLRenderPassDescriptor *pass=v.currentRenderPassDescriptor;id<CAMetalDrawable> drawable=v.currentDrawable;
        if(!pass || !drawable){skips++;return;}
        id<MTLCommandBuffer> c=[queue commandBuffer];c.label=@"Guest 3D frame";
        id<MTLRenderCommandEncoder> e=[c renderCommandEncoderWithDescriptor:pass];
        encode(e,v.drawableSize.width/v.drawableSize.height,NO,YES);[e endEncoding];
        [c presentDrawable:drawable];[c commit];pending[slot]=[c retain];frames++;totalCPU+=cpu()-cpuStart;
    }
}
static void resized(id self,SEL sel,MTKView *v,CGSize size){(void)self;(void)sel;(void)v;(void)size;}
static NSEvent *input(NSEvent *event){
    events++;
    if(event.type==NSEventTypeLeftMouseDragged){yaw+=event.deltaX*.006f;return event;}
    NSString *s=event.charactersIgnoringModifiers.lowercaseString;
    if(s.length){unichar c=[s characterAtIndex:0];if(c<128)keys[c]=event.type==NSEventTypeKeyDown;
        if(event.type==NSEventTypeKeyDown && !event.isARepeat && c==' '){spinning=!spinning;actions++;NSBeep();}
        if(event.type==NSEventTypeKeyDown && c=='r'){cameraX=0;cameraZ=6;yaw=0;}
    }return event;
}
NSDictionary *game_snapshot(void){
    for(unsigned i=0;i<3;i++)retire(i,NO);
    double elapsed=start?now()-start:0;
    return @{@"running":@(running),@"device_class":device?NSStringFromClass([device class]):@"released",@"device":device.name?:@"released",@"frames":@(frames),@"completed":@(completed),@"gpu_errors":@(errors),@"skipped":@(skips),@"events":@(events),@"actions":@(actions),@"camera_x":@(cameraX),@"camera_z":@(cameraZ),@"yaw":@(yaw),@"angle":@(angle),@"spinning":@(spinning),@"elapsed":@(elapsed),@"fps":@(elapsed?frames/elapsed:0),@"guest_cpu_seconds":@(totalCPU),@"max_frame_interval":@(maxFrame),@"gpu_seconds":@(gpuSeconds),@"library_compiles":@(libraries),@"pipeline_creations":@(pipelines),@"static_buffers":@(buffers),@"asset_textures":@(textures),@"draws":@(draws),@"uniform_bytes_per_draw":@(sizeof(Uniforms)),@"sync_waits":@(waits),@"compile_seconds":@(compileSeconds),@"error":failure?:@""};
}
NSDictionary *game_verify(void){
    if(!pipeline)return @{@"passed":@NO};
    NSMutableArray *centers=[NSMutableArray array];NSMutableArray *ranges=[NSMutableArray array];
    for(unsigned enabled=0;enabled<2;enabled++)@autoreleasepool {
        MTLTextureDescriptor *t=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:128 height:128 mipmapped:NO];
        t.usage=MTLTextureUsageRenderTarget;t.storageMode=MTLStorageModeShared;id<MTLTexture> color=[device newTextureWithDescriptor:t];
        t.pixelFormat=MTLPixelFormatDepth32Float;t.storageMode=MTLStorageModePrivate;id<MTLTexture> z=[device newTextureWithDescriptor:t];
        MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=color;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
        pass.depthAttachment.texture=z;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.storeAction=MTLStoreActionDontCare;pass.depthAttachment.clearDepth=1;
        id<MTLCommandBuffer> c=[queue commandBuffer];id<MTLRenderCommandEncoder> e=[c renderCommandEncoderWithDescriptor:pass];encode(e,1,YES,enabled);[e endEncoding];[c commit];[c waitUntilCompleted];waits++;
        uint8_t pixels[128*128*4];[color getBytes:pixels bytesPerRow:512 fromRegion:MTLRegionMake2D(0,0,128,128) mipmapLevel:0];
        unsigned index=(64*128+64)*4;[centers addObject:@[@(pixels[index+2]),@(pixels[index+1]),@(pixels[index])]];
        unsigned low=255,high=0;for(unsigned y=54;y<74;y++)for(unsigned x=54;x<74;x++){unsigned v=pixels[(y*128+x)*4+(enabled?2:0)];low=MIN(low,v);high=MAX(high,v);}
        [ranges addObject:@[@(low),@(high)]];if(c.status==MTLCommandBufferStatusError)errors++;
        [color release];[z release];
    }
    BOOL pass=[centers[0][2] intValue]>[centers[0][0] intValue]*3 && [centers[1][0] intValue]>[centers[1][2] intValue]*3 && [ranges[1][1] intValue]>[ranges[1][0] intValue]+20;
    return @{@"passed":@(pass),@"depth_off_rgb":centers[0],@"depth_on_rgb":centers[1],@"texture_ranges":ranges,@"pixels":@16384};
}
void game_stop(void){
    running=NO;view.paused=YES;view.delegate=nil;
    if(monitor){[NSEvent removeMonitor:monitor];[monitor release];monitor=nil;}
    for(unsigned i=0;i<3;i++)retire(i,YES);
    [window close];[window release];window=nil;[view release];view=nil;
    [delegate release];delegate=nil;if(delegateClass)objc_disposeClassPair(delegateClass);delegateClass=Nil;
    [vertices release];vertices=nil;[indices release];indices=nil;[checker release];checker=nil;
    [pipeline release];pipeline=nil;[depth release];depth=nil;[always release];always=nil;[queue release];queue=nil;[device release];device=nil;[failure release];failure=nil;
}
int main(int argc,char **argv){@autoreleasepool {
    device=MTLCreateSystemDefaultDevice();if(!device)return 2;queue=[device newCommandQueue];
    NSString *path=[NSBundle.mainBundle pathForResource:@"scene" ofType:@"metal"];NSError *error=nil;
    NSString *source=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    double compile=now();id<MTLLibrary> library=source?[device newLibraryWithSource:source options:nil error:&error]:nil;libraries++;
    if(!library){failure=[error.description copy];return 3;}
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[library newFunctionWithName:@"scene_vertex"];pd.fragmentFunction=[library newFunctionWithName:@"scene_fragment"];
    pd.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;pd.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
    pipeline=[device newRenderPipelineStateWithDescriptor:pd error:&error];pipelines++;[pd.vertexFunction release];[pd.fragmentFunction release];[pd release];[library release];compileSeconds=now()-compile;
    if(!pipeline){failure=[error.description copy];return 4;}
    MTLDepthStencilDescriptor *ds=[MTLDepthStencilDescriptor new];ds.depthCompareFunction=MTLCompareFunctionLess;ds.depthWriteEnabled=YES;depth=[device newDepthStencilStateWithDescriptor:ds];ds.depthCompareFunction=MTLCompareFunctionAlways;always=[device newDepthStencilStateWithDescriptor:ds];[ds release];
    Vertex v[24];uint16_t ind[36];
    const vector_float3 normals[6]={{0,0,1},{0,0,-1},{1,0,0},{-1,0,0},{0,1,0},{0,-1,0}};
    const vector_float3 horizontal[6]={{1,0,0},{-1,0,0},{0,0,-1},{0,0,1},{1,0,0},{1,0,0}};
    for(unsigned f=0;f<6;f++){vector_float3 n=normals[f],h=horizontal[f],up=simd_cross(n,h);for(unsigned j=0;j<4;j++){float x=(j==1||j==2)?1:-1,y=j>=2?1:-1;vector_float3 p=(n+h*x+up*y)*.5f;v[f*4+j]=(Vertex){{p.x,p.y,p.z,1},{n.x,n.y,n.z,0},{(x+1)*2,(y+1)*2,0,0}};}unsigned a=f*4,k=f*6;ind[k]=a;ind[k+1]=a+1;ind[k+2]=a+2;ind[k+3]=a;ind[k+4]=a+2;ind[k+5]=a+3;}
    vertices=[device newBufferWithBytes:v length:sizeof v options:MTLResourceStorageModeShared];indices=[device newBufferWithBytes:ind length:sizeof ind options:MTLResourceStorageModeShared];buffers=2;
    NSData *pixels=[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"checker" ofType:@"rgba"]];if(pixels.length!=16*16*4)return 5;
    MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:16 height:16 mipmapped:NO];td.usage=MTLTextureUsageShaderRead;td.storageMode=MTLStorageModeShared;checker=[device newTextureWithDescriptor:td];[checker replaceRegion:MTLRegionMake2D(0,0,16,16) mipmapLevel:0 withBytes:pixels.bytes bytesPerRow:64];textures=1;
    NSApplication *app=NSApplication.sharedApplication;[app setActivationPolicy:NSApplicationActivationPolicyRegular];
    window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,800,600) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];[window setReleasedWhenClosed:NO];window.title=@"Native macOS Metal arena — WASD, drag/JL, Space";
    view=[[MTKView alloc] initWithFrame:NSMakeRect(0,0,800,600) device:device];view.colorPixelFormat=MTLPixelFormatBGRA8Unorm;view.depthStencilPixelFormat=MTLPixelFormatDepth32Float;view.clearColor=MTLClearColorMake(.035,.055,.09,1);view.preferredFramesPerSecond=30;view.paused=NO;view.enableSetNeedsDisplay=NO;
    delegateClass=objc_allocateClassPair(NSObject.class,"ArenaRendererDelegate",0);if(!delegateClass)return 6;
    class_addMethod(delegateClass,@selector(drawInMTKView:),(IMP)draw,"v@:@");class_addMethod(delegateClass,@selector(mtkView:drawableSizeWillChange:),(IMP)resized,"v@:@{CGSize=dd}");objc_registerClassPair(delegateClass);delegate=[delegateClass new];view.delegate=delegate;
    window.contentView=view;[window center];[window makeKeyAndOrderFront:nil];[app activateIgnoringOtherApps:YES];
    monitor=[[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown|NSEventMaskKeyUp|NSEventMaskLeftMouseDragged handler:^NSEvent *(NSEvent *event){return input(event);}] retain];
    start=now();last=0;running=YES;
    if(argc>1 && !strcmp(argv[1],"--verify")) {
        NSDictionary *result=game_verify();
        NSData *json=[NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
        fwrite(json.bytes,1,json.length,stdout);fputc('\n',stdout);
        BOOL pass=[result[@"passed"] boolValue];game_stop();return pass?0:7;
    }
    [app run];
}return 0;}
