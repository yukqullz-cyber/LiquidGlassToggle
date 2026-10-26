// LiquidGlassToggle - botón flotante que activa/desactiva Liquid Glass (iOS 26+)
// Aplica el efecto SOLO a: la barra inferior y al propio botón.
#import <UIKit/UIKit.h>

static NSString *const kLGKey = @"LGToggleEnabled";
static NSInteger const kLGGlassTag = 0x4C47;
static NSInteger const kLGButtonTag = 0x4C48;

static BOOL LGEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kLGKey];
}

// UIGlassEffect existe solo en iOS 26+. Se usa por runtime para compilar con cualquier SDK.
static UIVisualEffectView *LGMakeGlass(void) {
    Class glass = NSClassFromString(@"UIGlassEffect");
    if (!glass) return nil;
    UIVisualEffect *effect = [[glass alloc] init];
    @try { [effect setValue:@YES forKey:@"interactive"]; } @catch (__unused NSException *e) {}
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:effect];
    v.tag = kLGGlassTag;
    v.userInteractionEnabled = NO;
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    return v;
}

static void LGApply(UIView *host) {
    UIView *old = [host viewWithTag:kLGGlassTag];
    if (LGEnabled()) {
        CGRect r = CGRectInset(host.bounds, 12, 4);
        if (old) { old.frame = r; return; }
        UIVisualEffectView *g = LGMakeGlass();
        if (!g) return;
        g.frame = r;
        g.clipsToBounds = YES;
        g.layer.cornerRadius = MIN(r.size.height / 2.0, 32);
        [host insertSubview:g atIndex:0];
        host.backgroundColor = UIColor.clearColor;
    } else {
        [old removeFromSuperview];
    }
}

// Detecta la barra inferior de TikTok (clase propia) por nombre y posición.
static BOOL LGLooksLikeTabBar(UIView *v, UIWindow *w) {
    NSString *n = NSStringFromClass(v.class).lowercaseString;
    if (![n containsString:@"tabbar"]) return NO;
    for (NSString *bad in @[@"button", @"item", @"cell", @"model", @"controller", @"bubble",
                            @"delegate", @"sliding", @"category", @"anchor", @"sticker",
                            @"filter", @"lynx", @"config", @"protocol"]) {
        if ([n containsString:bad]) return NO;
    }
    CGRect r = [v convertRect:v.bounds toView:w];
    return r.size.width >= w.bounds.size.width * 0.8 &&
           r.size.height >= 40 && r.size.height <= 140 &&
           CGRectGetMaxY(r) >= w.bounds.size.height * 0.9;
}

static void LGSweep(UIView *v, UIWindow *w) {
    if (v.tag == kLGGlassTag || v.tag == kLGButtonTag) return;
    if (![v isKindOfClass:[UITabBar class]] && LGLooksLikeTabBar(v, w)) LGApply(v);
    for (UIView *s in [v.subviews copy]) LGSweep(s, w);
}

static void LGRefreshTree(UIView *v) {
    if ([v isKindOfClass:[UITabBar class]]) [v setNeedsLayout];
    for (UIView *s in v.subviews) LGRefreshTree(s);
}

static UIWindow *LGKeyWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) return w;
    }
    return nil;
}

@interface LGHandler : NSObject
+ (void)toggle:(UIButton *)sender;
+ (void)drag:(UIPanGestureRecognizer *)pan;
+ (void)install;
@end

@implementation LGHandler

+ (void)toggle:(UIButton *)sender {
    BOOL on = !LGEnabled();
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kLGKey];
    sender.tintColor = on ? UIColor.systemBlueColor : UIColor.whiteColor;
    UIWindow *w = LGKeyWindow();
    if (w) { LGRefreshTree(w); LGSweep(w, w); }
    [[UIImpactFeedbackGenerator new] impactOccurred];
}

+ (void)drag:(UIPanGestureRecognizer *)pan {
    UIView *v = pan.view;
    CGPoint t = [pan translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [pan setTranslation:CGPointZero inView:v.superview];
}

+ (void)install {
    UIWindow *w = LGKeyWindow();
    if (!w || [w viewWithTag:kLGButtonTag]) return;

    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = kLGButtonTag;
    b.frame = CGRectMake(w.bounds.size.width - 64, w.safeAreaInsets.top + 120, 48, 48);
    b.layer.cornerRadius = 24;
    b.clipsToBounds = YES;
    [b setImage:[UIImage systemImageNamed:@"sparkles"] forState:UIControlStateNormal];
    b.tintColor = LGEnabled() ? UIColor.systemBlueColor : UIColor.whiteColor;

    // Fondo del botón: Liquid Glass en iOS 26, blur normal en versiones anteriores
    UIVisualEffectView *bg = LGMakeGlass();
    if (!bg) bg = [[UIVisualEffectView alloc] initWithEffect:
                   [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    bg.frame = b.bounds;
    bg.userInteractionEnabled = NO;
    [b insertSubview:bg atIndex:0];

    [b addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
    [b addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    [w addSubview:b];

    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(__unused NSTimer *t) {
        UIWindow *kw = LGKeyWindow();
        if (kw) LGSweep(kw, kw);
    }];
}

@end

// Liquid Glass solo en la barra inferior.
// Si la app usa una barra personalizada, añade aquí su clase (ver README).
%hook UITabBar
- (void)layoutSubviews {
    %orig;
    LGApply(self);
}
%end

%ctor {
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification *n) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [LGHandler install]; });
    }];
}
