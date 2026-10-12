// Workaround for a measured GPU defect: on the vphone "Apple Paravirtual
// device GPU", indexed draws use baseVertex & 0xFFFF (65536 -> 0, 182000 ->
// 50928; phase6 VertexFormatProbe baseVertex sweep). Guests that pack many
// meshes in one vertex buffer (SuperTuxKart via MoltenVK) then fetch another
// mesh's vertices. Equivalent rewrite: advance every per-vertex buffer by
// baseVertex*stride, draw with baseVertex 0, restore the offsets. Enabled
// only if a startup draw shows the defect. Limitation: [[vertex_id]] then
// excludes the base (Vulkan gl_VertexIndex would include it).
#import <Metal/Metal.h>
#include <pthread.h>
extern void mp_game_trace(NSString *);
static BOOL defectPresent;static uint64_t rewrittenDraws;
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static NSMapTable *layouts; // pipeline -> NSData of 31 NSUInteger strides (0 = not per-vertex)
NSDictionary *mp_base_vertex_stats(void){pthread_mutex_lock(&lock);uint64_t n=rewrittenDraws;pthread_mutex_unlock(&lock);return @{@"defect_detected":@(defectPresent),@"rewritten_draws":@(n)};}
void mp_base_vertex_note_pipeline(id pipeline,MTLRenderPipelineDescriptor *d) {
    if(!defectPresent || !pipeline || !d.vertexDescriptor)return;
    NSUInteger strides[31]={0};
    for(int b=0;b<31;b++){MTLVertexBufferLayoutDescriptor *l=d.vertexDescriptor.layouts[b];if(l.stride && l.stepFunction==MTLVertexStepFunctionPerVertex)strides[b]=l.stride;}
    pthread_mutex_lock(&lock);if(!layouts)layouts=[NSMapTable weakToStrongObjectsMapTable];[layouts setObject:[NSData dataWithBytes:strides length:sizeof strides] forKey:pipeline];pthread_mutex_unlock(&lock);
}
// Startup detection on the real device: a 4-vertex draw with baseVertex 65536.
void mp_base_vertex_detect(id<MTLDevice> device) {
    NSString *src=@"#include <metal_stdlib>\nusing namespace metal;\nstruct I { float p [[attribute(0)]]; };\n"
        "vertex void d(I in [[stage_in]], uint i [[instance_id]], device float *o [[buffer(1)]], uint v [[vertex_id]]) { o[v & 3]=in.p; }\n";
    NSError *e=nil;id<MTLLibrary> lib=[device newLibraryWithSource:src options:nil error:&e];if(!lib)return;
    MTLVertexDescriptor *vd=[MTLVertexDescriptor vertexDescriptor];vd.attributes[0].format=MTLVertexFormatFloat;vd.attributes[0].bufferIndex=0;vd.layouts[0].stride=4;
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[lib newFunctionWithName:@"d"];pd.vertexDescriptor=vd;pd.rasterizationEnabled=NO;pd.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
    id<MTLRenderPipelineState> ps=[device newRenderPipelineStateWithDescriptor:pd error:&e];if(!ps)return;
    id<MTLBuffer> vb=[device newBufferWithLength:(65536+4)*4 options:MTLResourceStorageModeShared];
    float *f=vb.contents;for(unsigned v=0;v<65540;v++)f[v]=v;
    uint16_t idx[4]={0,1,2,3};id<MTLBuffer> ib=[device newBufferWithBytes:idx length:8 options:MTLResourceStorageModeShared];
    id<MTLBuffer> o=[device newBufferWithLength:16 options:MTLResourceStorageModeShared];
    MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1 height:1 mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModePrivate;
    MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor renderPassDescriptor];rp.colorAttachments[0].texture=[device newTextureWithDescriptor:td];
    id<MTLCommandBuffer> cb=[[device newCommandQueue] commandBuffer];id<MTLRenderCommandEncoder> enc=[cb renderCommandEncoderWithDescriptor:rp];
    [enc setRenderPipelineState:ps];[enc setVertexBuffer:vb offset:0 atIndex:0];[enc setVertexBuffer:o offset:0 atIndex:1];
    [enc drawIndexedPrimitives:MTLPrimitiveTypePoint indexCount:4 indexType:MTLIndexTypeUInt16 indexBuffer:ib indexBufferOffset:0 instanceCount:1 baseVertex:65536 baseInstance:0];
    [enc endEncoding];[cb commit];[cb waitUntilCompleted];
    const float *r=o.contents;defectPresent=r[0]!=65536.0f;
    mp_game_trace([NSString stringWithFormat:@"GPU baseVertex check: draw at 65536 fetched vertex %.0f -> %@",r[0],defectPresent?@"16-bit truncation present, rewrite enabled":@"correct"]);
}
@interface MPBaseVertexEncoder:NSObject
@property(nonatomic,strong) id<MTLRenderCommandEncoder> native;
@end
@implementation MPBaseVertexEncoder {
    NSUInteger strides[31];id<MTLBuffer> buffers[31];NSUInteger offsets[31],attrStrides[31];BOOL dynamicStride[31];
}
- (id)forwardingTargetForSelector:(SEL)s {return self.native;}
- (BOOL)respondsToSelector:(SEL)s {return [super respondsToSelector:s] || [self.native respondsToSelector:s];}
- (BOOL)conformsToProtocol:(Protocol *)p {return [super conformsToProtocol:p] || [self.native conformsToProtocol:p];}
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)p {
    pthread_mutex_lock(&lock);NSData *d=[layouts objectForKey:p];pthread_mutex_unlock(&lock);
    if(d)memcpy(strides,d.bytes,sizeof strides);else memset(strides,0,sizeof strides);
    [self.native setRenderPipelineState:p];
}
- (void)setVertexBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o atIndex:(NSUInteger)i {if(i<31){buffers[i]=b;offsets[i]=o;dynamicStride[i]=NO;}[self.native setVertexBuffer:b offset:o atIndex:i];}
- (void)setVertexBufferOffset:(NSUInteger)o atIndex:(NSUInteger)i {if(i<31){offsets[i]=o;dynamicStride[i]=NO;}[self.native setVertexBufferOffset:o atIndex:i];}
- (void)setVertexBuffers:(id<MTLBuffer> const *)b offsets:(const NSUInteger *)o withRange:(NSRange)r {
    for(NSUInteger k=0;k<r.length;k++)if(r.location+k<31){buffers[r.location+k]=b[k];offsets[r.location+k]=o[k];dynamicStride[r.location+k]=NO;}
    [self.native setVertexBuffers:b offsets:o withRange:r];
}
- (void)setVertexBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o attributeStride:(NSUInteger)st atIndex:(NSUInteger)i {
    if(i<31){buffers[i]=b;offsets[i]=o;attrStrides[i]=st;dynamicStride[i]=YES;}[self.native setVertexBuffer:b offset:o attributeStride:st atIndex:i];
}
- (void)setVertexBufferOffset:(NSUInteger)o attributeStride:(NSUInteger)st atIndex:(NSUInteger)i {
    if(i<31){offsets[i]=o;attrStrides[i]=st;dynamicStride[i]=YES;}[self.native setVertexBufferOffset:o attributeStride:st atIndex:i];
}
- (void)setVertexBuffers:(id<MTLBuffer> const *)b offsets:(const NSUInteger *)o attributeStrides:(const NSUInteger *)st withRange:(NSRange)r {
    for(NSUInteger k=0;k<r.length;k++)if(r.location+k<31){buffers[r.location+k]=b[k];offsets[r.location+k]=o[k];attrStrides[r.location+k]=st[k];dynamicStride[r.location+k]=YES;}
    [self.native setVertexBuffers:b offsets:o attributeStrides:st withRange:r];
}
- (NSUInteger)strideAt:(unsigned)i {
    // MTLAttributeStrideStatic (NSUIntegerMax) means "use the pipeline's".
    if(dynamicStride[i] && attrStrides[i]!=NSUIntegerMax)return strides[i]?attrStrides[i]:0;
    return strides[i];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)n indexType:(MTLIndexType)it indexBuffer:(id<MTLBuffer>)ib indexBufferOffset:(NSUInteger)io instanceCount:(NSUInteger)ic baseVertex:(NSInteger)bv baseInstance:(NSUInteger)bi {
    if(bv<65536){[self.native drawIndexedPrimitives:t indexCount:n indexType:it indexBuffer:ib indexBufferOffset:io instanceCount:ic baseVertex:bv baseInstance:bi];return;}
    NSUInteger saved[31];BOOL moved[31]={NO};
    for(unsigned i=0;i<31;i++){NSUInteger s=[self strideAt:i];if(!s || !buffers[i])continue;
        saved[i]=offsets[i];moved[i]=YES;NSUInteger shifted=offsets[i]+(NSUInteger)bv*s;
        if(dynamicStride[i])[self.native setVertexBufferOffset:shifted attributeStride:attrStrides[i] atIndex:i];else [self.native setVertexBufferOffset:shifted atIndex:i];}
    [self.native drawIndexedPrimitives:t indexCount:n indexType:it indexBuffer:ib indexBufferOffset:io instanceCount:ic baseVertex:0 baseInstance:bi];
    for(unsigned i=0;i<31;i++)if(moved[i]){if(dynamicStride[i])[self.native setVertexBufferOffset:saved[i] attributeStride:attrStrides[i] atIndex:i];else [self.native setVertexBufferOffset:saved[i] atIndex:i];}
    pthread_mutex_lock(&lock);rewrittenDraws++;pthread_mutex_unlock(&lock);
}
@end
id mp_base_vertex_wrap(id encoder) {
    if(!defectPresent || !encoder)return encoder;
    MPBaseVertexEncoder *e=[MPBaseVertexEncoder new];e.native=encoder;return e;
}
