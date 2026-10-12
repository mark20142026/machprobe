#import <UIKit/UIKit.h>
@interface MPCompatImage : NSObject
@property(nonatomic,strong) UIImage *uiImage;
+ (instancetype)imageNamed:(NSString *)name;
@end
@interface MPCompatSound : NSObject
+ (void)beep;
@end
void *mp_ios_shim(const char *library,const char *symbol);
