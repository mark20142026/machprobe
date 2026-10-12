// Temporary touch controls for Cyberpunk 2077 on a phone without keyboard,
// mouse or controller. Every control emits the Mac key/mouse events a real
// keyboard and mouse would (mp_game_key / mp_game_modifier / mp_game_pointer),
// so the game is unchanged. A paired Bluetooth keyboard or game controller
// works directly and is the better way to play.
//   left stick  W A S D           right half drag  mouse look (pad shown)
//   SPACE jump  F use  R reload  C crouch  SHIFT sprint  TAB  ESC  ENTER
//   LMB / RMB   mouse buttons     ⌨️  iPhone keyboard (any letter/number)
//   🎮 hides/shows the whole overlay. Touches outside controls pass through,
//   so menus stay tappable.
#import <UIKit/UIKit.h>
#import "Input.h"
#import "Lifecycle.h"
extern BOOL mp_game_cursor_hidden(void);
static void key(unsigned short code,NSString *chars,BOOL down){mp_game_key(code,chars,down,0);}

@interface MPCPPassthrough:UIView @end
@implementation MPCPPassthrough
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {UIView *v=[super hitTest:p withEvent:e];return v==self?nil:v;}
@end

// Stick → W/A/S/D with a dead zone; diagonals press two keys.
@interface MPCPStick:UIView @property(nonatomic,strong) UIView *knob;@property(nonatomic) unsigned held;- (void)recenter;@end
@implementation MPCPStick
- (instancetype)initWithFrame:(CGRect)f {
    if((self=[super initWithFrame:f])){
        self.backgroundColor=[UIColor colorWithWhite:1 alpha:0.10];self.layer.cornerRadius=f.size.width/2;
        self.layer.borderWidth=2;self.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.30].CGColor;
        CGFloat k=f.size.width*0.42;self.knob=[[UIView alloc] initWithFrame:CGRectMake(0,0,k,k)];
        self.knob.backgroundColor=[UIColor colorWithWhite:1 alpha:0.40];self.knob.layer.cornerRadius=k/2;self.knob.userInteractionEnabled=NO;
        self.knob.center=CGPointMake(f.size.width/2,f.size.height/2);[self addSubview:self.knob];
    }
    return self;
}
- (void)apply:(unsigned)want {
    static const unsigned short codes[4]={0,2,13,1};static NSString *chars[4]={@"a",@"d",@"w",@"s"};  // left right up down
    for(int i=0;i<4;i++){unsigned bit=1u<<i;if((want&bit)!=(self.held&bit))key(codes[i],chars[i],(want&bit)!=0);}
    self.held=want;
}
- (void)track:(UITouch *)t {
    CGPoint c=CGPointMake(self.bounds.size.width/2,self.bounds.size.height/2),p=[t locationInView:self];
    CGFloat r=self.bounds.size.width/2,dx=p.x-c.x,dy=p.y-c.y,len=hypot(dx,dy);
    if(len>r){dx*=r/len;dy*=r/len;}
    self.knob.center=CGPointMake(c.x+dx,c.y+dy);
    CGFloat nx=dx/r,ny=dy/r,dead=0.3;unsigned want=0;
    if(nx<-dead)want|=1;if(nx>dead)want|=2;if(ny<-dead)want|=4;if(ny>dead)want|=8;
    [self apply:want];
}
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {[self track:t.anyObject];}
- (void)touchesMoved:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {[self track:t.anyObject];}
- (void)recenter {self.knob.center=CGPointMake(self.bounds.size.width/2,self.bounds.size.height/2);[self apply:0];}
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {[self recenter];}
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {[self recenter];}
@end

// A held key. kind 0: key, 1: modifier (Shift), 2: left mouse, 3: right mouse.
@interface MPCPKey:UIView @property(nonatomic) unsigned short code;@property(nonatomic,copy) NSString *chars;@property(nonatomic) int kind;@property(nonatomic) BOOL down;- (void)set:(BOOL)down;@end
@implementation MPCPKey
+ (instancetype)key:(NSString *)title code:(unsigned short)code chars:(NSString *)chars kind:(int)kind size:(CGSize)size {
    MPCPKey *b=[[self alloc] initWithFrame:CGRectMake(0,0,size.width,size.height)];b.code=code;b.chars=chars;b.kind=kind;
    b.backgroundColor=[UIColor colorWithRed:0.98 green:0.93 blue:0.0 alpha:0.28];b.layer.cornerRadius=10;b.layer.borderWidth=1.5;
    b.layer.borderColor=[UIColor colorWithRed:0.98 green:0.93 blue:0.0 alpha:0.7].CGColor;b.multipleTouchEnabled=YES;
    UILabel *l=[[UILabel alloc] initWithFrame:b.bounds];l.text=title;l.textAlignment=NSTextAlignmentCenter;l.textColor=UIColor.whiteColor;
    l.font=[UIFont boldSystemFontOfSize:size.height>50?16:12];l.adjustsFontSizeToFitWidth=YES;[b addSubview:l];
    return b;
}
- (void)set:(BOOL)down {
    if(down==self.down)return;self.down=down;self.alpha=down?1.0:0.85;
    switch(self.kind) {
        case 0:key(self.code,self.chars,down);break;
        case 1:mp_game_modifier(self.code,down,down?(1UL<<17):0);break;   // NSEventModifierFlagShift
        case 2:mp_game_pointer_here(down?1:2,CGPointZero);break;
        case 3:mp_game_pointer_here(down?3:4,CGPointZero);break;
    }
}
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {[self set:YES];}
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {[self set:NO];}
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {[self set:NO];}
@end

// Drag → relative mouse motion (camera). Active only while the game hides its
// pointer (gameplay); in menus touches go straight to the game as clicks.
@interface MPCPLook:UIView @property(nonatomic) CGPoint last;@end
@implementation MPCPLook
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {self.last=[t.anyObject locationInView:self];}
- (void)touchesMoved:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    CGPoint p=[t.anyObject locationInView:self];CGFloat s=2.2;   // Points → mouse units.
    mp_game_pointer_here(5,CGPointMake((p.x-self.last.x)*s,(p.y-self.last.y)*s));self.last=p;
}
@end

// iPhone keyboard: each typed character becomes a Mac key press.
@interface MPCPTyping:UIView<UIKeyInput> @end
@implementation MPCPTyping
- (BOOL)canBecomeFirstResponder {return YES;}
- (BOOL)hasText {return NO;}
- (UIKeyboardType)keyboardType {return UIKeyboardTypeASCIICapable;}
- (UITextAutocorrectionType)autocorrectionType {return UITextAutocorrectionTypeNo;}
- (UITextAutocapitalizationType)autocapitalizationType {return UITextAutocapitalizationTypeNone;}
static unsigned short code_for(unichar c) {
    static const char letters[]="asdfhgzxcv\0bqweryt123465=97-80]ou[ip\rlj'k;\\,/nm.";  // Mac ANSI key codes 0-47.
    if(c>='A'&&c<='Z')c+=32;
    if(c==' ')return 49;if(c=='\n')return 36;if(c=='\t')return 48;
    for(unsigned short i=0;i<sizeof letters-1;i++)if(letters[i]==c && c)return i;
    return 0xffff;
}
- (void)insertText:(NSString *)text {
    for(NSUInteger i=0;i<text.length;i++){unichar c=[text characterAtIndex:i];unsigned short code=code_for(c);if(code==0xffff)continue;
        NSString *s=[NSString stringWithCharacters:&c length:1];key(code,s,YES);key(code,s,NO);}
}
- (void)deleteBackward {key(51,@"\x7f",YES);key(51,@"\x7f",NO);}
@end

@interface MPCPOverlay:MPCPPassthrough @property(nonatomic,strong) MPCPPassthrough *pad;@property(nonatomic,strong) MPCPLook *look;@property(nonatomic,strong) MPCPTyping *typing;@end
@implementation MPCPOverlay
- (void)poll {self.look.hidden=self.pad.hidden;} // Cyberpunk always hides the system cursor: camera look only with the pad shown.
- (void)toggle:(id)sender {
    if(!self.pad.hidden)for(UIView *v in self.pad.subviews){if([v isKindOfClass:MPCPStick.class])[(MPCPStick *)v recenter];if([v isKindOfClass:MPCPKey.class])[(MPCPKey *)v set:NO];}
    self.pad.hidden=!self.pad.hidden;[self poll];
}
- (void)keyboard:(id)sender {if(self.typing.isFirstResponder)[self.typing resignFirstResponder];else [self.typing becomeFirstResponder];}
- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets in=self.window.safeAreaInsets;CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
    CGFloat left=MAX(in.left,14),right=MAX(in.right,14),bottom=MAX(in.bottom,10),top=MAX(in.top,8);
    self.pad.frame=self.bounds;self.look.frame=CGRectMake(w*0.45,0,w*0.55,h);
    for(UIView *v in self.pad.subviews) {
        if([v isKindOfClass:MPCPStick.class]){v.center=CGPointMake(left+v.bounds.size.width/2+6,h-bottom-v.bounds.size.height/2-6);continue;}
        if(![v isKindOfClass:MPCPKey.class])continue;
        MPCPKey *k=(MPCPKey *)v;CGFloat rx=w-right,by=h-bottom;
        switch(k.kind==2?1000:k.kind==3?1001:k.code) {
            case 49:k.center=CGPointMake(rx-50,by-36);break;          // SPACE
            case 3: k.center=CGPointMake(rx-130,by-30);break;         // F
            case 15:k.center=CGPointMake(rx-130,by-90);break;         // R
            case 8: k.center=CGPointMake(rx-200,by-30);break;         // C
            case 56:k.center=CGPointMake(left+30,by-180);break;       // SHIFT, above the stick
            case 1000:k.center=CGPointMake(rx-50,by-112);break;       // LMB
            case 1001:k.center=CGPointMake(rx-50,by-180);break;       // RMB
            case 53:k.center=CGPointMake(left+30,top+22);break;       // ESC
            case 48:k.center=CGPointMake(left+90,top+22);break;       // TAB
            case 36:k.center=CGPointMake(rx-120,top+22);break;        // ENTER
        }
    }
}
@end

static MPCPOverlay *overlay;
static void install(UIWindow *window) {
    overlay=[[MPCPOverlay alloc] initWithFrame:window.bounds];overlay.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;overlay.multipleTouchEnabled=YES;
    overlay.look=[[MPCPLook alloc] initWithFrame:CGRectZero];overlay.look.hidden=YES;overlay.look.multipleTouchEnabled=NO;[overlay addSubview:overlay.look];
    overlay.pad=[[MPCPPassthrough alloc] initWithFrame:window.bounds];overlay.pad.multipleTouchEnabled=YES;[overlay addSubview:overlay.pad];
    [overlay.pad addSubview:[[MPCPStick alloc] initWithFrame:CGRectMake(0,0,140,140)]];
    CGSize big={64,64},small={54,40};
    NSArray *specs=@[@[@"SPACE",@49,@" ",@0,@YES],@[@"F",@3,@"f",@0,@NO],@[@"R",@15,@"r",@0,@NO],@[@"C",@8,@"c",@0,@NO],@[@"SHIFT",@56,@"",@1,@NO],
                     @[@"LMB",@0,@"",@2,@YES],@[@"RMB",@0,@"",@3,@NO],@[@"ESC",@53,@"\x1b",@0,@NO],@[@"TAB",@48,@"\t",@0,@NO],@[@"ENTER",@36,@"\r",@0,@NO]];
    for(NSArray *s in specs)[overlay.pad addSubview:[MPCPKey key:s[0] code:[s[1] unsignedShortValue] chars:s[2] kind:[s[3] intValue] size:[s[4] boolValue]?big:small]];
    overlay.typing=[[MPCPTyping alloc] initWithFrame:CGRectZero];[overlay addSubview:overlay.typing];
    UIButton *(^button)(NSString *,SEL)=^(NSString *title,SEL action){UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:title forState:UIControlStateNormal];
        b.titleLabel.font=[UIFont systemFontOfSize:20];b.frame=CGRectMake(0,0,44,44);b.backgroundColor=[UIColor colorWithWhite:0 alpha:0.3];b.layer.cornerRadius=22;
        [b addTarget:overlay action:action forControlEvents:UIControlEventTouchUpInside];b.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;[overlay addSubview:b];return b;};
    UIEdgeInsets in=window.safeAreaInsets;CGFloat w=window.bounds.size.width,top=MAX(in.top,8)+22,right=MAX(in.right,14);
    button(@"🎮",@selector(toggle:)).center=CGPointMake(w-right-22,top);
    button(@"⌨️",@selector(keyboard:)).center=CGPointMake(w-right-74,top);
    [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *t){[overlay poll];if(overlay.superview)[overlay.superview bringSubviewToFront:overlay];}];
    [window addSubview:overlay];
}
// Installs once the game's view is on screen.
void mp_cp_install_controls(void) {
    [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t){
        UIWindow *w=mp_game_host_view().window;if(!w)return;
        [t invalidate];install(w);
        extern void mp_cp_cursor_trace_install(void);mp_cp_cursor_trace_install();
        extern void mp_cp_engine_cursor_trace(void);mp_cp_engine_cursor_trace();
        extern void mp_cp_key_state_log(void);mp_cp_key_state_log();
        extern void mp_cp_refocus(void);dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{mp_cp_refocus();});
    }];
}

// MP_AUTOPRESS="15:49,30:36" presses key 49 (Space) at 15 s and 36 (Return) at
// 30 s after launch: lets a debugging run reach the same state unattended.
__attribute__((constructor)) static void autopress(void) {
    const char *spec=getenv("MP_AUTOPRESS");if(!spec)return;
    for(NSString *item in [@(spec) componentsSeparatedByString:@","]) {
        NSArray *p=[item componentsSeparatedByString:@":"];if(p.count!=2)continue;
        double at=[p[0] doubleValue];unsigned short code=(unsigned short)[p[1] intValue];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(at*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            fprintf(stderr,"[auto] key %u\n",code);key(code,code==49?@" ":code==36?@"\r":@"",YES);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.15*NSEC_PER_SEC)),dispatch_get_main_queue(),^{key(code,code==49?@" ":code==36?@"\r":@"",NO);});
        });
    }
}

// MP_AUTOTAP="20:437,300,30:437,120": a finger tap at view point (x,y) at 20 s
// and 30 s, through the same path as a real touch (move, press, release).
extern void mp_game_pointer_to(NSUInteger type,CGPoint p);
__attribute__((constructor)) static void autotap(void) {
    const char *spec=getenv("MP_AUTOTAP");if(!spec)return;
    NSArray *parts=[@(spec) componentsSeparatedByString:@","];
    for(NSUInteger i=0;i+1<parts.count;i+=2) {
        NSArray *tx=[parts[i] componentsSeparatedByString:@":"];if(tx.count!=2)continue;
        double at=[tx[0] doubleValue];CGPoint p=CGPointMake([tx[1] doubleValue],[parts[i+1] doubleValue]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(at*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            fprintf(stderr,"[auto] tap %.0f,%.0f\n",p.x,p.y);extern void mp_game_touch_began(void);mp_game_touch_began();mp_game_pointer_to(5,p);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.05*NSEC_PER_SEC)),dispatch_get_main_queue(),^{mp_game_pointer_to(1,p);});
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.12*NSEC_PER_SEC)),dispatch_get_main_queue(),^{mp_game_pointer_to(2,p);});
        });
    }
}

// Game controllers: iOS claims Menu/Options/Home presses for system gestures
// (Games overlay, search) unless the app opts out per button; a macOS game
// never does. Every connected controller's buttons go to the game.
#import <GameController/GameController.h>
static void claim_buttons(GCController *c) {
    if(@available(iOS 14.0,*))for(GCControllerButtonInput *b in c.physicalInputProfile.buttons.allValues)b.preferredSystemGestureState=GCSystemGestureStateDisabled;
}
__attribute__((constructor)) static void claim_controllers(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        for(GCController *c in GCController.controllers)claim_buttons(c);
        [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidConnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){claim_buttons(n.object);}];
    });
}
