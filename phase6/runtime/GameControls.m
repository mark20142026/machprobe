// Touch gamepad for keyboard-driven guests on phones without a keyboard
// (SuperTuxKart: arrows drive, Space fire, N nitro, V skid, B look back,
// Backspace rescue, Esc pause). Every control emits the same Mac key events
// a hardware keyboard produces (mp_game_key), so the game itself is unchanged.
// The overlay sits above the guest's view; touches outside controls pass
// through to the game (menus stay tappable).
#import <UIKit/UIKit.h>
#import "Input.h"
static void key(unsigned short code,NSString *chars,BOOL down){mp_game_key(code,chars,down,0);}

@interface MPPassthroughView:UIView @end
@implementation MPPassthroughView
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {UIView *v=[super hitTest:p withEvent:e];return v==self?nil:v;}
@end

// Analog stick mapped to the four arrow keys with a dead zone; diagonals
// press two keys. Key state changes only on threshold crossings.
@interface MPJoystick:UIView
@property(nonatomic,strong) UIView *knob;
@property(nonatomic) unsigned held; // bit0 left, 1 right, 2 up, 3 down
- (void)recenter;
@end
@implementation MPJoystick
- (instancetype)initWithFrame:(CGRect)f {
    if((self=[super initWithFrame:f])){
        self.backgroundColor=[UIColor colorWithWhite:1 alpha:0.12];self.layer.cornerRadius=f.size.width/2;
        self.layer.borderWidth=2;self.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.35].CGColor;
        CGFloat k=f.size.width*0.42;self.knob=[[UIView alloc] initWithFrame:CGRectMake(0,0,k,k)];
        self.knob.backgroundColor=[UIColor colorWithWhite:1 alpha:0.45];self.knob.layer.cornerRadius=k/2;self.knob.userInteractionEnabled=NO;
        self.knob.center=CGPointMake(f.size.width/2,f.size.height/2);[self addSubview:self.knob];
        self.accessibilityIdentifier=@"gamepad-joystick";
    }
    return self;
}
- (void)apply:(unsigned)want {
    static const unsigned short codes[4]={123,124,126,125};
    for(int i=0;i<4;i++){unsigned bit=1u<<i;if((want&bit)!=(self.held&bit))key(codes[i],@"",(want&bit)!=0);}
    self.held=want;
}
- (void)track:(UITouch *)t {
    CGPoint c=CGPointMake(self.bounds.size.width/2,self.bounds.size.height/2),p=[t locationInView:self];
    CGFloat r=self.bounds.size.width/2,dx=p.x-c.x,dy=p.y-c.y,len=hypot(dx,dy);
    if(len>r){dx*=r/len;dy*=r/len;}
    self.knob.center=CGPointMake(c.x+dx,c.y+dy);
    CGFloat nx=dx/r,ny=dy/r,dead=0.3;unsigned want=0;
    if(nx<-dead)want|=1;if(nx>dead)want|=2;if(ny<-dead)want|=4;if(ny>dead+0.15)want|=8;
    [self apply:want];
}
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {[self track:t.anyObject];}
- (void)touchesMoved:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {[self track:t.anyObject];}
- (void)recenter {self.knob.center=CGPointMake(self.bounds.size.width/2,self.bounds.size.height/2);[self apply:0];}
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {[self recenter];}
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {[self recenter];}
@end

// Hold-to-press button for one key.
@interface MPPadButton:UIView
@property unsigned short code;@property(copy) NSString *chars;@property BOOL down;
- (void)set:(BOOL)down;
@end
@implementation MPPadButton
+ (instancetype)button:(NSString *)title code:(unsigned short)code chars:(NSString *)chars size:(CGFloat)size {
    MPPadButton *b=[[self alloc] initWithFrame:CGRectMake(0,0,size,size)];b.code=code;b.chars=chars;
    b.backgroundColor=[UIColor colorWithWhite:1 alpha:0.14];b.layer.cornerRadius=size/2;
    b.layer.borderWidth=2;b.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.35].CGColor;
    UILabel *l=[[UILabel alloc] initWithFrame:b.bounds];l.text=title;l.textAlignment=NSTextAlignmentCenter;l.numberOfLines=2;
    l.font=[UIFont boldSystemFontOfSize:size*0.2];l.textColor=[UIColor colorWithWhite:1 alpha:0.85];l.userInteractionEnabled=NO;[b addSubview:l];
    b.accessibilityIdentifier=[@"gamepad-" stringByAppendingString:title];return b;
}
- (void)set:(BOOL)down {if(down==self.down)return;self.down=down;self.alpha=down?1.0:0.8;self.transform=down?CGAffineTransformMakeScale(0.92,0.92):CGAffineTransformIdentity;key(self.code,self.chars,down);}
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {[self set:YES];}
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {[self set:NO];}
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {[self set:NO];}
@end

@interface MPGamepad:MPPassthroughView
@property(nonatomic,strong) MPPassthroughView *pad;
@end
extern BOOL mp_game_cursor_hidden(void);
@implementation MPGamepad {BOOL lastGameplay;BOOL overridden;}
// Auto mode: the game hides its pointer while racing and shows it in menus,
// so the pad appears only in gameplay and never covers menu buttons. The 🎮
// button overrides until the game's pointer state next changes.
- (void)poll {
    BOOL gameplay=mp_game_cursor_hidden();
    if(gameplay!=lastGameplay){lastGameplay=gameplay;overridden=NO;}
    if(!overridden){BOOL hide=!gameplay;if(hide && !self.pad.hidden)[self releaseAll];self.pad.hidden=hide;}
}
- (void)releaseAll {for(UIView *v in self.pad.subviews){if([v isKindOfClass:MPJoystick.class])[(MPJoystick *)v recenter];if([v isKindOfClass:MPPadButton.class])[(MPPadButton *)v set:NO];}}
- (void)toggle:(UIButton *)b {overridden=YES;if(!self.pad.hidden)[self releaseAll];self.pad.hidden=!self.pad.hidden;}
- (void)layoutForBounds:(CGRect)bounds insets:(UIEdgeInsets)in {
    self.pad.frame=bounds;
    CGFloat left=MAX(in.left,16),right=MAX(in.right,16),bottom=MAX(in.bottom,12),h=bounds.size.height,w=bounds.size.width;
    MPJoystick *stick=nil;NSMutableArray<MPPadButton *> *buttons=[NSMutableArray array];MPPadButton *pause=nil;
    for(UIView *v in self.pad.subviews){if([v isKindOfClass:MPJoystick.class])stick=(MPJoystick *)v;else if([v isKindOfClass:MPPadButton.class]){MPPadButton *b=(MPPadButton *)v;if(b.code==53)pause=b;else [buttons addObject:b];}}
    CGFloat s=stick.bounds.size.width;stick.center=CGPointMake(left+s/2+8,h-bottom-s/2-8);
    // Right cluster: Fire big, Nitro above, Drift left of Fire, Look/Rescue small.
    CGFloat fx=w-right-60,fy=h-bottom-60;
    for(MPPadButton *b in buttons) {
        switch(b.code) {
            case 49:b.center=CGPointMake(fx,fy);break;                 // Fire
            case 45:b.center=CGPointMake(fx,fy-110);break;             // Nitro
            case 9: b.center=CGPointMake(fx-110,fy+5);break;           // Drift
            case 11:b.center=CGPointMake(fx-95,fy-95);break;           // Look back
            case 51:b.center=CGPointMake(fx-195,fy+15);break;          // Rescue
        }
    }
    pause.center=CGPointMake(w-right-30,MAX(in.top,10)+30);
}
@end

static MPGamepad *gamepad;
void mp_install_gamepad(UIWindow *window) {
    if(gamepad || !window)return;
    gamepad=[[MPGamepad alloc] initWithFrame:window.bounds];gamepad.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    gamepad.pad=[[MPPassthroughView alloc] initWithFrame:window.bounds];gamepad.pad.multipleTouchEnabled=YES;[gamepad addSubview:gamepad.pad];
    gamepad.multipleTouchEnabled=YES;
    [gamepad.pad addSubview:[[MPJoystick alloc] initWithFrame:CGRectMake(0,0,150,150)]];
    for(NSArray *spec in @[@[@"FIRE",@49,@" ",@96],@[@"NITRO",@45,@"n",@74],@[@"DRIFT",@9,@"v",@74],@[@"LOOK\nBACK",@11,@"b",@58],@[@"RESCUE",@51,@"\x7f",@58],@[@"II",@53,@"\x1b",@46]])
        [gamepad.pad addSubview:[MPPadButton button:spec[0] code:[spec[1] unsignedShortValue] chars:spec[2] size:[spec[3] doubleValue]]];
    UIButton *toggle=[UIButton buttonWithType:UIButtonTypeSystem];[toggle setTitle:@"🎮" forState:UIControlStateNormal];toggle.titleLabel.font=[UIFont systemFontOfSize:22];
    toggle.frame=CGRectMake(0,0,44,44);toggle.backgroundColor=[UIColor colorWithWhite:0 alpha:0.25];toggle.layer.cornerRadius=22;toggle.alpha=0.9;
    toggle.accessibilityIdentifier=@"gamepad-toggle";[toggle addTarget:gamepad action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];[gamepad addSubview:toggle];
    gamepad.pad.hidden=YES; // Until the game enters gameplay (pointer hidden).
    [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *t){[gamepad poll];}];
    [window addSubview:gamepad];
    UIEdgeInsets in=window.safeAreaInsets;[gamepad layoutForBounds:window.bounds insets:in];
    toggle.center=CGPointMake(window.bounds.size.width-MAX(in.right,16)-90,MAX(in.top,10)+30);
    // Keep the gamepad above the guest view as it is (re)presented and rotated.
    [NSNotificationCenter.defaultCenter addObserverForName:@"NSWindowDidBecomeKeyNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){[gamepad.superview bringSubviewToFront:gamepad];}];
    [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
        dispatch_async(dispatch_get_main_queue(),^{UIEdgeInsets i=gamepad.window.safeAreaInsets;[gamepad layoutForBounds:gamepad.bounds insets:i];toggle.center=CGPointMake(gamepad.bounds.size.width-MAX(i.right,16)-90,MAX(i.top,10)+30);});}];
}
