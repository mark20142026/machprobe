// Decode distributed asset-catalog resources; never load the app executable.
#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc!=4)return 2;
        NSBundle *bundle=[NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSArray *assets=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]] options:0 error:NULL];
        NSString *output=[NSString stringWithUTF8String:argv[3]];
        NSMutableSet *seen=[NSMutableSet set];NSMutableArray *results=[NSMutableArray array];
        for(NSDictionary *asset in assets) {
            NSString *name=asset[@"Name"],*type=asset[@"AssetType"];
            if(!name || [seen containsObject:name] || !([type isEqual:@"Image"] || [type isEqual:@"Color"]))continue;
            [seen addObject:name];
            for(NSString *appearance in @[@"light",@"dark"]) {
                NSAppearance *a=[NSAppearance appearanceNamed:[appearance isEqual:@"dark"]?NSAppearanceNameDarkAqua:NSAppearanceNameAqua];
                [a performAsCurrentDrawingAppearance:^{
                    NSMutableDictionary *record=[@{@"name":name,@"type":type,@"appearance":appearance} mutableCopy];
                    if([type isEqual:@"Image"]) {
                        NSImage *image=[bundle imageForResource:name];CGImageRef cg=[image CGImageForProposedRect:NULL context:nil hints:nil];
                        if(!cg){fprintf(stderr,"Missing image: %s\n",name.UTF8String);exit(1);}
                        NSString *file=[NSString stringWithFormat:@"asset-%lu-%@.png",(unsigned long)results.count,appearance];
                        NSURL *url=[NSURL fileURLWithPath:[output stringByAppendingPathComponent:file]];
                        CGImageDestinationRef destination=CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.png"),1,NULL);
                        if(!destination)exit(1);CGImageDestinationAddImage(destination,cg,NULL);
                        if(!CGImageDestinationFinalize(destination))exit(1);CFRelease(destination);
                        record[@"file"]=file;record[@"pixel_width"]=@(CGImageGetWidth(cg));record[@"pixel_height"]=@(CGImageGetHeight(cg));
                        record[@"point_width"]=@(image.size.width);record[@"point_height"]=@(image.size.height);
                    } else {
                        NSColor *color=[[NSColor colorNamed:name bundle:bundle] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                        if(!color)exit(1);record[@"rgba"]=@[@(color.redComponent),@(color.greenComponent),@(color.blueComponent),@(color.alphaComponent)];
                    }
                    [results addObject:record];
                }];
            }
        }
        NSData *data=[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:NULL];
        [data writeToFile:[output stringByAppendingPathComponent:@"manifest.json"] atomically:YES];
    }
}
