#import "Probe.h"
int main(int argc,char **argv) {
    if(argc!=3)return 2;
    @autoreleasepool {
        NSDictionary *r=MPProbe([NSString stringWithUTF8String:argv[1]],[NSString stringWithUTF8String:argv[2]],NO);
        NSData *data=[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:NULL];
        fwrite(data.bytes,1,data.length,stdout);puts("");
    }
}
