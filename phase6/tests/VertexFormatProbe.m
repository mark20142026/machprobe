// Independent iOS Metal probe (no guest code): do integer and half-float
// vertex attributes reach a vertex function with their exact values on this
// GPU? Skinned meshes are the only STK draws using int4 joint attributes.
// Each case feeds known values through one MTLVertexFormat into a
// rasterization-disabled vertex function that writes what it received.
#import <Metal/Metal.h>
static NSString *const source=@"#include <metal_stdlib>\nusing namespace metal;\n"
 "struct I { int4 i [[attribute(0)]]; float4 f [[attribute(1)]]; };\n"
 "vertex void probe(I in [[stage_in]], uint v [[vertex_id]], device int4 *oi [[buffer(1)]], device float4 *of [[buffer(2)]]) { oi[v]=in.i; of[v]=in.f; }\n";
NSDictionary *mp_vertex_format_probe(void) {
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();NSError *error=nil;
    id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];
    if(!library)return @{@"passed":@NO,@"error":error.description?:@"library"};
    struct Case {const char *name;MTLVertexFormat format;unsigned size;int isSigned;};
    struct Case cases[]={{"short4",MTLVertexFormatShort4,2,1},{"ushort4",MTLVertexFormatUShort4,2,0},{"char4",MTLVertexFormatChar4,1,1},
                         {"uchar4",MTLVertexFormatUChar4,1,0},{"int4",MTLVertexFormatInt4,4,1}};
    const int values[4][4]={{0,1,2,3},{-1,-1,5,7},{12,34,-1,0},{100,63,17,-1}};
    const float weights[4][4]={{1,0,0,0},{0.5f,0.25f,0.125f,0.125f},{0.75f,0.25f,0,0},{0.1f,0.2f,0.3f,0.4f}};
    NSMutableDictionary *results=[NSMutableDictionary dictionary];BOOL all=YES;
    for(unsigned c=0;c<sizeof cases/sizeof *cases;c++) {
        struct Case k=cases[c];
        // Interleaved like STK's skinned vertex: integers, then half4 weights.
        unsigned stride=((k.size*4+8)+3)&~3u;unsigned char vertices[4*64]={0};
        for(int v=0;v<4;v++) {
            unsigned char *p=vertices+v*stride;
            for(int j=0;j<4;j++) {
                int value=k.isSigned?values[v][j]:(values[v][j]<0?(k.size==1?255:65535):values[v][j]);
                if(k.size==1)p[j]=(unsigned char)value;else if(k.size==2)((int16_t *)p)[j]=(int16_t)value;else ((int32_t *)p)[j]=value;
            }
            for(int j=0;j<4;j++)((__fp16 *)(p+k.size*4))[j]=(__fp16)weights[v][j];
        }
        MTLVertexDescriptor *vd=[MTLVertexDescriptor vertexDescriptor];
        vd.attributes[0].format=k.format;vd.attributes[0].offset=0;vd.attributes[0].bufferIndex=0;
        vd.attributes[1].format=MTLVertexFormatHalf4;vd.attributes[1].offset=k.size*4;vd.attributes[1].bufferIndex=0;
        vd.layouts[0].stride=stride;
        MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];
        pd.vertexFunction=[library newFunctionWithName:@"probe"];pd.vertexDescriptor=vd;pd.rasterizationEnabled=NO;
        pd.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
        id<MTLRenderPipelineState> pipeline=[device newRenderPipelineStateWithDescriptor:pd error:&error];
        if(!pipeline){results[@(k.name)]=@{@"error":error.description?:@"pipeline"};all=NO;continue;}
        id<MTLBuffer> vb=[device newBufferWithBytes:vertices length:4*stride options:MTLResourceStorageModeShared];
        id<MTLBuffer> oi=[device newBufferWithLength:4*16 options:MTLResourceStorageModeShared],of=[device newBufferWithLength:4*16 options:MTLResourceStorageModeShared];
        memset(oi.contents,0x7f,64);memset(of.contents,0x7f,64);
        MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:4 height:4 mipmapped:NO];
        td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModePrivate;
        MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor renderPassDescriptor];rp.colorAttachments[0].texture=[device newTextureWithDescriptor:td];
        id<MTLCommandQueue> q=[device newCommandQueue];id<MTLCommandBuffer> cb=[q commandBuffer];
        id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:rp];
        [e setRenderPipelineState:pipeline];[e setVertexBuffer:vb offset:0 atIndex:0];[e setVertexBuffer:oi offset:0 atIndex:1];[e setVertexBuffer:of offset:0 atIndex:2];
        [e drawPrimitives:MTLPrimitiveTypePoint vertexStart:0 vertexCount:4];[e endEncoding];[cb commit];[cb waitUntilCompleted];
        int mismatches=0;NSMutableArray *got=[NSMutableArray array];
        for(int v=0;v<4;v++) {
            const int32_t *r=(const int32_t *)oi.contents+v*4;const float *w=(const float *)of.contents+v*4;
            for(int j=0;j<4;j++) {
                int expect=k.isSigned?values[v][j]:(values[v][j]<0?(k.size==1?255:65535):values[v][j]);
                if(r[j]!=expect)mismatches++;
                if(fabsf(w[j]-weights[v][j])>1e-3f)mismatches++;
            }
            [got addObject:[NSString stringWithFormat:@"%d,%d,%d,%d | %.3f,%.3f,%.3f,%.3f",r[0],r[1],r[2],r[3],w[0],w[1],w[2],w[3]]];
        }
        results[@(k.name)]=@{@"mismatches":@(mismatches),@"received":got,@"gpu_status":@(cb.status)};
        if(mismatches)all=NO;
    }
    // STK skinned layout: stream A (stride 48, float3 position) at offset 0 and
    // stream B (stride 16, short4 joints + half4 weights) at a large offset in
    // the SAME buffer; indexed draw with baseVertex, which Metal applies to both.
    {
        NSString *src2=@"#include <metal_stdlib>\nusing namespace metal;\nstruct I { float3 p [[attribute(0)]]; int4 j [[attribute(6)]]; float4 w [[attribute(7)]]; };\n"
            "vertex void probe2(I in [[stage_in]], uint v [[vertex_id]], device float4 *op [[buffer(1)]], device int4 *oj [[buffer(2)]]) { op[v]=float4(in.p,1); oj[v]=in.j; }\n";
        id<MTLLibrary> lib2=[device newLibraryWithSource:src2 options:nil error:&error];
        const unsigned N=64,A=48,B=16,base=40;const NSUInteger offB=1<<20;
        id<MTLBuffer> vb=[device newBufferWithLength:offB+N*B options:MTLResourceStorageModeShared];
        for(unsigned v=0;v<N;v++){float *p=(float *)((char *)vb.contents+v*A);p[0]=v;p[1]=v*2;p[2]=v*3;
            int16_t *j=(int16_t *)((char *)vb.contents+offB+v*B);j[0]=v;j[1]=v+100;j[2]=-1;j[3]=7;}
        MTLVertexDescriptor *vd=[MTLVertexDescriptor vertexDescriptor];
        vd.attributes[0].format=MTLVertexFormatFloat3;vd.attributes[0].bufferIndex=30;
        vd.attributes[6].format=MTLVertexFormatShort4;vd.attributes[6].bufferIndex=29;
        vd.attributes[7].format=MTLVertexFormatHalf4;vd.attributes[7].offset=8;vd.attributes[7].bufferIndex=29;
        vd.layouts[30].stride=A;vd.layouts[29].stride=B;
        MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[lib2 newFunctionWithName:@"probe2"];pd.vertexDescriptor=vd;pd.rasterizationEnabled=NO;
        pd.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
        id<MTLRenderPipelineState> ps=[device newRenderPipelineStateWithDescriptor:pd error:&error];
        NSMutableDictionary *two=[NSMutableDictionary dictionary];
        if(!ps){two[@"error"]=error.description?:@"pipeline";all=NO;}
        else for(NSString *mode in @[@"static-stride",@"dynamic-stride"]) {
            uint16_t idx[8]={0,1,2,3,4,5,6,7};id<MTLBuffer> ib=[device newBufferWithBytes:idx length:sizeof idx options:MTLResourceStorageModeShared];
            id<MTLBuffer> op=[device newBufferWithLength:N*16 options:MTLResourceStorageModeShared],oj=[device newBufferWithLength:N*16 options:MTLResourceStorageModeShared];
            memset(op.contents,0xff,N*16);memset(oj.contents,0xff,N*16);
            MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:4 height:4 mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModePrivate;
            MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor renderPassDescriptor];rp.colorAttachments[0].texture=[device newTextureWithDescriptor:td];
            id<MTLCommandBuffer> cb=[[device newCommandQueue] commandBuffer];id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:rp];
            [e setRenderPipelineState:ps];
            [e setVertexBuffer:vb offset:0 atIndex:30];[e setVertexBuffer:vb offset:offB atIndex:29];
            [e setVertexBuffer:op offset:0 atIndex:1];[e setVertexBuffer:oj offset:0 atIndex:2];
            [e drawIndexedPrimitives:MTLPrimitiveTypePoint indexCount:8 indexType:MTLIndexTypeUInt16 indexBuffer:ib indexBufferOffset:0 instanceCount:1 baseVertex:base baseInstance:0];
            [e endEncoding];[cb commit];[cb waitUntilCompleted];
            int bad=0;NSMutableArray *got=[NSMutableArray array];
            for(unsigned k=0;k<8;k++){unsigned v=base+k;const float *p=(const float *)op.contents+v*4;const int32_t *j=(const int32_t *)oj.contents+v*4;
                if(p[0]!=v||p[1]!=v*2||j[0]!=(int)v||j[1]!=(int)v+100||j[2]!=-1||j[3]!=7)bad++;
                if(k<3)[got addObject:[NSString stringWithFormat:@"v%u pos=%.0f,%.0f joints=%d,%d,%d,%d",v,p[0],p[1],j[0],j[1],j[2],j[3]]];}
            two[mode]=@{@"bad_vertices":@(bad),@"sample":got,@"status":@(cb.status)};if(bad)all=NO;
            break; // Dynamic stride requires a different pipeline; static case first.
        }
        results[@"two_stream_baseVertex"]=two;
    }
    // Exact STK skinned layout (recorded from the guest's skinned pipelines):
    // stream 30 stride 32: float3 pos, int1010102n normal, uchar4n color,
    // half2 uv, half2 uv2, int1010102n tangent; stream 29 stride 16 at a
    // large offset of the same buffer: short4 joints, half4 weights.
    {
        NSString *src3=@"#include <metal_stdlib>\nusing namespace metal;\nstruct I { float3 p [[attribute(0)]]; float4 n [[attribute(1)]]; float4 c [[attribute(2)]]; float2 uv [[attribute(3)]]; float2 uv2 [[attribute(4)]]; float4 t [[attribute(5)]]; int4 j [[attribute(6)]]; float4 w [[attribute(7)]]; };\n"
            "vertex void probe3(I in [[stage_in]], uint v [[vertex_id]], device float4 *o [[buffer(1)]], device int4 *oj [[buffer(2)]]) { o[v*4]=float4(in.p,in.uv.x); o[v*4+1]=in.w; o[v*4+2]=in.n; o[v*4+3]=in.c; oj[v]=in.j; }\n";
        id<MTLLibrary> lib3=[device newLibraryWithSource:src3 options:nil error:&error];
        const NSUInteger total=200000,base=182000,count=16,offB=6513048;
        id<MTLBuffer> vb=[device newBufferWithLength:offB+total*16 options:MTLResourceStorageModeShared];
        for(NSUInteger v=base;v<base+count;v++){
            char *a=(char *)vb.contents+v*32;float *p=(float *)a;p[0]=v;p[1]=1;p[2]=2;
            *(uint32_t *)(a+12)=(511u)|(0u<<10)|(0u<<20); // normal (1,0,0)
            *(uint32_t *)(a+16)=0xff00ff00u;((__fp16 *)(a+20))[0]=0.5f;((__fp16 *)(a+20))[1]=0.25f;((__fp16 *)(a+24))[0]=0;((__fp16 *)(a+24))[1]=0;*(uint32_t *)(a+28)=511u;
            char *b=(char *)vb.contents+offB+v*16;int16_t *j=(int16_t *)b;j[0]=3;j[1]=1;j[2]=-1;j[3]=0;
            __fp16 *w=(__fp16 *)(b+8);w[0]=0.75f;w[1]=0.25f;w[2]=0;w[3]=0;
        }
        MTLVertexDescriptor *vd=[MTLVertexDescriptor vertexDescriptor];
        MTLVertexFormat f[8]={MTLVertexFormatFloat3,MTLVertexFormatInt1010102Normalized,MTLVertexFormatUChar4Normalized,MTLVertexFormatHalf2,MTLVertexFormatHalf2,MTLVertexFormatInt1010102Normalized,MTLVertexFormatShort4,MTLVertexFormatHalf4};
        NSUInteger off[8]={0,12,16,20,24,28,0,8},buf[8]={30,30,30,30,30,30,29,29};
        for(int k=0;k<8;k++){vd.attributes[k].format=f[k];vd.attributes[k].offset=off[k];vd.attributes[k].bufferIndex=buf[k];}
        vd.layouts[30].stride=32;vd.layouts[29].stride=16;
        MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[lib3 newFunctionWithName:@"probe3"];pd.vertexDescriptor=vd;pd.rasterizationEnabled=NO;pd.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
        id<MTLRenderPipelineState> ps=[device newRenderPipelineStateWithDescriptor:pd error:&error];
        NSMutableDictionary *exact=[NSMutableDictionary dictionary];
        if(!ps){exact[@"error"]=error.description?:@"pipeline";all=NO;}
        else {
            uint32_t idx[count];for(unsigned k=0;k<count;k++)idx[k]=k;
            id<MTLBuffer> ib=[device newBufferWithBytes:idx length:sizeof idx options:MTLResourceStorageModeShared];
            id<MTLBuffer> o=[device newBufferWithLength:(base+count)*64 options:MTLResourceStorageModeShared],oj=[device newBufferWithLength:(base+count)*16 options:MTLResourceStorageModeShared];
            MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:4 height:4 mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModePrivate;
            MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor renderPassDescriptor];rp.colorAttachments[0].texture=[device newTextureWithDescriptor:td];
            id<MTLCommandBuffer> cb=[[device newCommandQueue] commandBuffer];id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:rp];
            [e setRenderPipelineState:ps];[e setVertexBuffer:vb offset:0 atIndex:30];[e setVertexBuffer:vb offset:offB atIndex:29];
            [e setVertexBuffer:o offset:0 atIndex:1];[e setVertexBuffer:oj offset:0 atIndex:2];
            [e drawIndexedPrimitives:MTLPrimitiveTypePoint indexCount:count indexType:MTLIndexTypeUInt32 indexBuffer:ib indexBufferOffset:0 instanceCount:1 baseVertex:base baseInstance:0];
            [e endEncoding];[cb commit];[cb waitUntilCompleted];
            int bad=0;NSMutableArray *got=[NSMutableArray array];
            for(NSUInteger v=base;v<base+count;v++){const float *r=(const float *)o.contents+v*16;const int32_t *j=(const int32_t *)oj.contents+v*4;
                BOOL ok=r[0]==v && r[3]==0.5f && fabsf(r[4]-0.75f)<1e-3 && fabsf(r[5]-0.25f)<1e-3 && r[6]==0 && r[7]==0 && fabsf(r[8]-1)<1e-2 && j[0]==3 && j[1]==1 && j[2]==-1;
                if(!ok)bad++;
                if(v<base+2)[got addObject:[NSString stringWithFormat:@"v%lu pos.x=%.0f uv.x=%.2f w=%.3f,%.3f,%.3f,%.3f n.x=%.2f j=%d,%d,%d,%d",(unsigned long)v,r[0],r[3],r[4],r[5],r[6],r[7],r[8],j[0],j[1],j[2],j[3]]];}
            exact=[@{@"bad_vertices":@(bad),@"sample":got,@"status":@(cb.status)} mutableCopy];if(bad)all=NO;
        }
        results[@"stk_exact_layout"]=exact;
    }
    // baseVertex sweep: does vertex fetch and [[vertex_id]] honour large
    // baseVertex values? Output slot = vertex_id & 15; records vertex_id too.
    {
        NSString *src4=@"#include <metal_stdlib>\nusing namespace metal;\nstruct I { float p [[attribute(0)]]; };\n"
            "vertex void probe4(I in [[stage_in]], uint v [[vertex_id]], device float2 *o [[buffer(1)]]) { o[v & 15]=float2(in.p, float(v)); }\n";
        id<MTLLibrary> lib4=[device newLibraryWithSource:src4 options:nil error:&error];
        MTLVertexDescriptor *vd=[MTLVertexDescriptor vertexDescriptor];vd.attributes[0].format=MTLVertexFormatFloat;vd.attributes[0].bufferIndex=30;vd.layouts[30].stride=4;
        MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[lib4 newFunctionWithName:@"probe4"];pd.vertexDescriptor=vd;pd.rasterizationEnabled=NO;pd.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
        id<MTLRenderPipelineState> ps=[device newRenderPipelineStateWithDescriptor:pd error:&error];
        const NSUInteger maxV=1<<20;id<MTLBuffer> vb=[device newBufferWithLength:maxV*4 options:MTLResourceStorageModeShared];
        for(NSUInteger v=0;v<maxV;v++)((float *)vb.contents)[v]=v;
        NSMutableDictionary *sweep=[NSMutableDictionary dictionary];
        for(NSNumber *bn in @[@40,@32767,@32768,@65535,@65536,@65537,@100000,@131071,@131072,@131073,@182000,@262144,@500000]) for(NSNumber *ty in @[@16,@32]) {
            NSUInteger b=bn.unsignedIntegerValue;BOOL wide=ty.intValue==32;
            uint32_t i32[4]={0,1,2,3};uint16_t i16[4]={0,1,2,3};
            id<MTLBuffer> ib=wide?[device newBufferWithBytes:i32 length:16 options:MTLResourceStorageModeShared]:[device newBufferWithBytes:i16 length:8 options:MTLResourceStorageModeShared];
            id<MTLBuffer> o=[device newBufferWithLength:16*8 options:MTLResourceStorageModeShared];memset(o.contents,0,128);
            MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:4 height:4 mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModePrivate;
            MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor renderPassDescriptor];rp.colorAttachments[0].texture=[device newTextureWithDescriptor:td];
            id<MTLCommandBuffer> cb=[[device newCommandQueue] commandBuffer];id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:rp];
            [e setRenderPipelineState:ps];[e setVertexBuffer:vb offset:0 atIndex:30];[e setVertexBuffer:o offset:0 atIndex:1];
            [e drawIndexedPrimitives:MTLPrimitiveTypePoint indexCount:4 indexType:wide?MTLIndexTypeUInt32:MTLIndexTypeUInt16 indexBuffer:ib indexBufferOffset:0 instanceCount:1 baseVertex:b baseInstance:0];
            [e endEncoding];[cb commit];[cb waitUntilCompleted];
            const float *r=(const float *)o.contents;NSMutableArray *seen=[NSMutableArray array];
            for(int k=0;k<16;k++)if(r[k*2] || r[k*2+1])[seen addObject:[NSString stringWithFormat:@"fetched=%.0f vid=%.0f",r[k*2],r[k*2+1]]];
            BOOL ok=seen.count==4;for(NSUInteger k=0;k<4 && ok;k++){const float *x=r+((b+k)&15)*2;if(x[0]!=b+k || x[1]!=b+k)ok=NO;}
            sweep[[NSString stringWithFormat:@"base%lu_u%d",(unsigned long)b,ty.intValue]]=ok?@"ok":[seen componentsJoinedByString:@"; "]?:@"nothing";
            if(!ok)all=NO;
        }
        results[@"baseVertex_sweep"]=sweep;
    }
    return @{@"passed":@(all),@"device":device.name?:@"",@"cases":results};
}
