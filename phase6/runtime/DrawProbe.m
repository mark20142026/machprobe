// Diagnostics only (env MP_DRAW_PROBE=1): wraps the guest's Metal render
// encoders and snapshots what the first draws binding a vertex-stage
// buffer(3) (STK's skinning matrices) actually reference at encode time.
#import <Metal/Metal.h>
#include <stdlib.h>
static NSMutableArray *captures;static NSLock *lock;
NSArray *mp_draw_probe_results(void){[lock lock];NSArray *r=[captures copy];[lock unlock];return r?:@[];}
static NSString *floats(id<MTLBuffer> b,NSUInteger offset,unsigned count) {
    if(!b || b.storageMode==MTLStorageModePrivate)return @"(private)";
    if(offset+count*4>b.length)return [NSString stringWithFormat:@"(offset %lu beyond length %lu)",(unsigned long)offset,(unsigned long)b.length];
    const float *f=(const float *)((const char *)b.contents+offset);NSMutableArray *a=[NSMutableArray array];
    for(unsigned i=0;i<count;i++)[a addObject:[NSString stringWithFormat:@"%.3g",f[i]]];
    return [a componentsJoinedByString:@" "];
}
static NSString *words(id<MTLBuffer> b,NSUInteger offset,unsigned count) {
    if(!b || b.storageMode==MTLStorageModePrivate)return @"(private)";
    if(offset+count*4>b.length)return @"(beyond length)";
    const int32_t *w=(const int32_t *)((const char *)b.contents+offset);NSMutableArray *a=[NSMutableArray array];
    for(unsigned i=0;i<count;i++)[a addObject:[NSString stringWithFormat:@"%d",w[i]]];
    return [a componentsJoinedByString:@" "];
}
static NSMapTable *skinnedPipelines;static unsigned skinnedCount,pipelineCount;static NSArray *skinnedLayout;
NSDictionary *mp_draw_probe_pipelines(void){return @{@"pipelines":@(pipelineCount),@"skinned":@(skinnedCount),@"skinned_layout":skinnedLayout?:@[]};}
void mp_draw_probe_note_pipeline(id pipeline,MTLRenderPipelineDescriptor *d) {
    if(!lock || !pipeline)return;
    pipelineCount++;
    if(d.vertexDescriptor.attributes[6].format==MTLVertexFormatInvalid)return;
    NSMutableArray *layout=[NSMutableArray array];
    for(int a=0;a<16;a++){MTLVertexAttributeDescriptor *x=d.vertexDescriptor.attributes[a];if(x.format!=MTLVertexFormatInvalid)[layout addObject:[NSString stringWithFormat:@"attr%d fmt=%lu off=%lu buf=%lu",a,(unsigned long)x.format,(unsigned long)x.offset,(unsigned long)x.bufferIndex]];}
    for(int b=0;b<31;b++){MTLVertexBufferLayoutDescriptor *l=d.vertexDescriptor.layouts[b];if(l.stride)[layout addObject:[NSString stringWithFormat:@"layout%d stride=%lu step=%lu rate=%lu",b,(unsigned long)l.stride,(unsigned long)l.stepFunction,(unsigned long)l.stepRate]];}
    [lock lock];if(!skinnedPipelines)skinnedPipelines=[NSMapTable weakToStrongObjectsMapTable];[skinnedPipelines setObject:@YES forKey:pipeline];skinnedCount++;if(!skinnedLayout)skinnedLayout=layout;[lock unlock];
}
@interface MPProbeEncoder:NSObject
@property(nonatomic,strong) id<MTLRenderCommandEncoder> native;
@property(nonatomic,strong) NSMutableDictionary<NSNumber *,NSArray *> *vertexBuffers;
@property(nonatomic) BOOL skinnedPipeline;
@end
@implementation MPProbeEncoder
- (id)forwardingTargetForSelector:(SEL)s {return self.native;}
- (BOOL)respondsToSelector:(SEL)s {return [super respondsToSelector:s] || [self.native respondsToSelector:s];}
- (BOOL)conformsToProtocol:(Protocol *)p {return [super conformsToProtocol:p] || [self.native conformsToProtocol:p];}
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)p {[lock lock];self.skinnedPipeline=[skinnedPipelines objectForKey:p]!=nil;[lock unlock];[self.native setRenderPipelineState:p];}
- (void)setVertexBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o atIndex:(NSUInteger)i {self.vertexBuffers[@(i)]=b?@[b,@(o)]:@[];[self.native setVertexBuffer:b offset:o atIndex:i];}
- (void)setVertexBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o attributeStride:(NSUInteger)st atIndex:(NSUInteger)i {self.vertexBuffers[@(i)]=b?@[b,@(o),@(st)]:@[];[self.native setVertexBuffer:b offset:o attributeStride:st atIndex:i];}
- (void)setVertexBufferOffset:(NSUInteger)o attributeStride:(NSUInteger)st atIndex:(NSUInteger)i {NSArray *e=self.vertexBuffers[@(i)];if(e.count)self.vertexBuffers[@(i)]=@[e[0],@(o),@(st)];[self.native setVertexBufferOffset:o attributeStride:st atIndex:i];}
- (void)setVertexBuffers:(id<MTLBuffer> const *)b offsets:(const NSUInteger *)o attributeStrides:(const NSUInteger *)st withRange:(NSRange)r {
    for(NSUInteger k=0;k<r.length;k++)self.vertexBuffers[@(r.location+k)]=b[k]?@[b[k],@(o[k]),@(st[k])]:@[];
    [self.native setVertexBuffers:b offsets:o attributeStrides:st withRange:r];
}
- (void)setVertexBufferOffset:(NSUInteger)o atIndex:(NSUInteger)i {NSArray *e=self.vertexBuffers[@(i)];if(e.count)self.vertexBuffers[@(i)]=@[e[0],@(o)];[self.native setVertexBufferOffset:o atIndex:i];}
- (void)setVertexBuffers:(id<MTLBuffer> const *)b offsets:(const NSUInteger *)o withRange:(NSRange)r {
    for(NSUInteger k=0;k<r.length;k++)self.vertexBuffers[@(r.location+k)]=b[k]?@[b[k],@(o[k])]:@[];
    [self.native setVertexBuffers:b offsets:o withRange:r];
}
static NSCountedSet *drawKinds;
NSDictionary *mp_draw_probe_kinds(void){[lock lock];NSMutableDictionary *d=[NSMutableDictionary dictionary];for(id k in drawKinds)d[k]=@([drawKinds countForObject:k]);[lock unlock];return d;}
- (void)capture:(NSDictionary *)draw {
    NSString *kind=[NSString stringWithFormat:@"%@ slots=%@",draw[@"draw"],[[self.vertexBuffers.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]];
    [lock lock];if(!drawKinds)drawKinds=[NSCountedSet new];if(drawKinds.count<40)[drawKinds addObject:kind];[lock unlock];
    NSArray *skin=self.vertexBuffers[@3];if(!skin.count)return;
    // Only skinned objects: ObjectData word 12 is m_skinning_offset (>=0).
    NSArray *objEntry=self.vertexBuffers[@2];if(!objEntry.count)return;
    id<MTLBuffer> objBuf=objEntry[0];NSUInteger objOff=[objEntry[1] unsignedIntegerValue];
    if(objBuf.storageMode==MTLStorageModePrivate || objOff+64>objBuf.length)return;
    NSUInteger baseInstance=[draw[@"baseInstance"] unsignedIntegerValue];
    const int32_t *object=(const int32_t *)((const char *)objBuf.contents+objOff)+baseInstance*16;
    if(!self.skinnedPipeline)return;
    int skinOffset=object[12];
    [lock lock];BOOL full=captures.count>=6;[lock unlock];if(full)return;
    NSMutableDictionary *c=[draw mutableCopy];
    id<MTLBuffer> sb=skin[0];NSUInteger so=[skin[1] unsignedIntegerValue];
    c[@"skin_buffer"]=[NSString stringWithFormat:@"len=%lu off=%lu mode=%lu",(unsigned long)sb.length,(unsigned long)so,(unsigned long)sb.storageMode];
    c[@"skinning_offset"]=@(skinOffset);
    for(int k=0;k<3;k++)c[[NSString stringWithFormat:@"joint_mat%d",k]]=floats(sb,so+(NSUInteger)(skinOffset+k)*64,16);
    c[@"object_words"]=words(objBuf,objOff+baseInstance*64,16);
    NSArray *obj=self.vertexBuffers[@2];
    if(obj.count){id<MTLBuffer> ob=obj[0];NSUInteger oo=[obj[1] unsignedIntegerValue];c[@"object_buffer"]=[NSString stringWithFormat:@"len=%lu off=%lu",(unsigned long)ob.length,(unsigned long)oo];c[@"object0_words"]=words(ob,oo,24);}
    NSMutableDictionary *vb=[NSMutableDictionary dictionary];
    for(NSNumber *i in self.vertexBuffers){if([i intValue]<8)continue;NSArray *e=self.vertexBuffers[i];if(!e.count)continue;id<MTLBuffer> b=e[0];NSUInteger o=[e[1] unsignedIntegerValue];
        vb[i.stringValue]=@{@"len":@(b.length),@"off":@(o),@"stride":e.count>2?e[2]:@"static",@"first48_words":words(b,o,12)};}
    c[@"vertex_streams"]=vb;
    [lock lock];[captures addObject:c];[lock unlock];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)n indexType:(MTLIndexType)it indexBuffer:(id<MTLBuffer>)ib indexBufferOffset:(NSUInteger)io instanceCount:(NSUInteger)ic baseVertex:(NSInteger)bv baseInstance:(NSUInteger)bi {
    [self capture:@{@"draw":@"indexed",@"indexCount":@(n),@"instanceCount":@(ic),@"baseVertex":@(bv),@"baseInstance":@(bi),@"indices":words(ib,io,4)}];
    [self.native drawIndexedPrimitives:t indexCount:n indexType:it indexBuffer:ib indexBufferOffset:io instanceCount:ic baseVertex:bv baseInstance:bi];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexType:(MTLIndexType)it indexBuffer:(id<MTLBuffer>)ib indexBufferOffset:(NSUInteger)io indirectBuffer:(id<MTLBuffer>)ind indirectBufferOffset:(NSUInteger)ino {
    [self capture:@{@"draw":@"indexed-indirect",@"indirect_args":words(ind,ino,5)}];
    [self.native drawIndexedPrimitives:t indexType:it indexBuffer:ib indexBufferOffset:io indirectBuffer:ind indirectBufferOffset:ino];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)n indexType:(MTLIndexType)it indexBuffer:(id<MTLBuffer>)ib indexBufferOffset:(NSUInteger)io instanceCount:(NSUInteger)ic {
    [self capture:@{@"draw":@"indexed-noBase",@"indexCount":@(n),@"instanceCount":@(ic)}];
    [self.native drawIndexedPrimitives:t indexCount:n indexType:it indexBuffer:ib indexBufferOffset:io instanceCount:ic];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)n indexType:(MTLIndexType)it indexBuffer:(id<MTLBuffer>)ib indexBufferOffset:(NSUInteger)io {
    [self capture:@{@"draw":@"indexed-single",@"indexCount":@(n)}];
    [self.native drawIndexedPrimitives:t indexCount:n indexType:it indexBuffer:ib indexBufferOffset:io];
}
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n instanceCount:(NSUInteger)ic baseInstance:(NSUInteger)bi {
    [self capture:@{@"draw":@"array",@"vertexCount":@(n),@"instanceCount":@(ic),@"baseInstance":@(bi)}];
    [self.native drawPrimitives:t vertexStart:s vertexCount:n instanceCount:ic baseInstance:bi];
}
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n instanceCount:(NSUInteger)ic {
    [self capture:@{@"draw":@"array-noBase",@"vertexCount":@(n),@"instanceCount":@(ic)}];
    [self.native drawPrimitives:t vertexStart:s vertexCount:n instanceCount:ic];
}
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n {
    [self capture:@{@"draw":@"array-single",@"vertexCount":@(n)}];
    [self.native drawPrimitives:t vertexStart:s vertexCount:n];
}
- (void)drawPrimitives:(MTLPrimitiveType)t indirectBuffer:(id<MTLBuffer>)ind indirectBufferOffset:(NSUInteger)o {
    [self capture:@{@"draw":@"array-indirect",@"indirect_args":words(ind,o,4)}];
    [self.native drawPrimitives:t indirectBuffer:ind indirectBufferOffset:o];
}
- (void)executeCommandsInBuffer:(id)icb withRange:(NSRange)r {
    [self capture:@{@"draw":@"indirect-command-buffer",@"range":NSStringFromRange(r)}];
    [self.native executeCommandsInBuffer:icb withRange:r];
}
@end
id mp_draw_probe_wrap(id encoder) {
    static int enabled=-1;if(enabled<0){enabled=getenv("MP_DRAW_PROBE")!=NULL;if(enabled){captures=[NSMutableArray array];lock=[NSLock new];}}
    if(!enabled || !encoder)return encoder;
    MPProbeEncoder *p=[MPProbeEncoder new];p.native=encoder;p.vertexBuffers=[NSMutableDictionary dictionary];return p;
}
