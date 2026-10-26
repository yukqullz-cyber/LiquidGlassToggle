// LiquidGlassToggle v2 - botón flotante que activa/desactiva Liquid Glass (iOS 26+)
// Toque corto: activar/desactivar. Pulsación larga: copia el mapa de vistas (diagnóstico).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const kLGKey = @"LGToggleEnabled";
static NSInteger const kLGGlassTag = 0x4C47;
static NSInteger const kLGButtonTag = 0x4C48;

@interface LGHandler : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)toggle:(UIButton *)sender;
- (void)drag:(UIPanGestureRecognizer *)pan;
- (void)press:(UILongPressGestureRecognizer *)gr;
- (void)dump:(UILongPressGestureRecognizer *)gr;
- (void)install;
@end

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
    return v;
}

// Recoge el área que ocupan los botones reales de la barra (para no cubrir espacio vacío).
static void LGCollect(UIView *v, UIView *host, CGRect *u) {
    for (UIView *s in v.subviews) {
        if (s.tag == kLGGlassTag) continue;
        NSString *n = NSStringFromClass(s.class).lowercaseString;
        if (!s.hidden && s.alpha > 0.05 && [n containsString:@"tabbar"] && [n containsString:@"button"]) {
            *u = CGRectUnion(*u, [s convertRect:s.bounds toView:host]);
        } else {
            LGCollect(s, host, u);
        }
    }
}

static CGRect LGGlassFrame(UIView *host) {
    CGRect u = CGRectNull;
    LGCollect(host, host, &u);
    if (CGRectIsNull(u) || u.size.width < 100) return CGRectInset(host.bounds, 12, 4);
    return CGRectIntersection(CGRectInset(u, -16, -10), host.bounds);
}

static void LGApply(UIView *host) {
    UIView *old = [host viewWithTag:kLGGlassTag];
    if (LGEnabled()) {
        CGRect r = LGGlassFrame(host);
        if (old) {
            old.frame = r;
            old.layer.cornerRadius = MIN(r.size.height / 2.0, 32);
            return;
        }
        UIVisualEffectView *g = LGMakeGlass();
        if (!g) return;
        g.frame = r;
        g.clipsToBounds = YES;
        g.layer.cornerRadius = MIN(r.size.height / 2.0, 32);
        [host insertSubview:g atIndex:0];
        host.backgroundColor = UIColor.clearColor;

        // Interactividad: el cristal "se hunde" al tocar la barra
        BOOL has = NO;
        for (UIGestureRecognizer *gr in host.gestureRecognizers) if ([gr.name isEqualToString:@"LGPress"]) has = YES;
        if (!has) {
            UILongPressGestureRecognizer *gr = [[UILongPressGestureRecognizer alloc]
                initWithTarget:[LGHandler shared] action:@selector(press:)];
            gr.minimumPressDuration = 0;
            gr.cancelsTouchesInView = NO;
            gr.delaysTouchesBegan = NO;
            gr.delegate = [LGHandler shared];
            gr.name = @"LGPress";
            [host addGestureRecognizer:gr];
        }
    } else {
        [old removeFromSuperview];
        for (UIGestureRecognizer *gr in [host.gestureRecognizers copy])
            if ([gr.name isEqualToString:@"LGPress"]) [host removeGestureRecognizer:gr];
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


// ---------- Modo nativo: usa el Liquid Glass real que ya trae TikTok ----------
static BOOL gNative = NO;
static char kOrigKey, kOrigH;

static void LGForce(UIView *v, CGFloat alpha, BOOL hide) {
    NSDictionary *o = objc_getAssociatedObject(v, &kOrigKey);
    if (LGEnabled()) {
        if (!o) objc_setAssociatedObject(v, &kOrigKey, @{@"a": @(v.alpha), @"h": @(v.hidden)}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        v.alpha = alpha; v.hidden = hide;
    } else if (o) {
        v.alpha = [o[@"a"] doubleValue]; v.hidden = [o[@"h"] boolValue];
        objc_setAssociatedObject(v, &kOrigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static BOOL LGFind(UIView *v, NSString *cls) {
    if ([NSStringFromClass(v.class) isEqualToString:cls]) return YES;
    for (UIView *s in v.subviews) if (LGFind(s, cls)) return YES;
    return NO;
}

// Muestra la barra de cristal del sistema y quita los fondos negros que la tapan.
static void LGNative(UIView *v) {
    NSString *n = NSStringFromClass(v.class);
    if ([n isEqualToString:@"TTKFakeTabBar"] || [n isEqualToString:@"_UIBottomTabBarGroupView"] ||
        [n isEqualToString:@"_UITabContainerView"]) {
        LGForce(v, 1.0, NO);
    } else if ([n containsString:@"TabBarBackgroundView"] || [n isEqualToString:@"TTKTabBarBlurView"] ||
               [n isEqualToString:@"TTKFeedDescBottomMaskView"]) {
        LGForce(v, 0.0, YES);
        return;
    }
    for (UIView *s in [v.subviews copy]) LGNative(s);
}

// Estira el video hasta el borde inferior para que el cristal tenga algo que refractar.
static void LGFeed(UIView *v) {
    if ([NSStringFromClass(v.class) isEqualToString:@"AWENewFeedTableView"] && v.superview) {
        CGFloat H = v.superview.bounds.size.height;
        NSNumber *orig = objc_getAssociatedObject(v, &kOrigH);
        CGRect f = v.frame;
        if (LGEnabled() && f.size.height < H && f.size.height > H * 0.8) {
            if (!orig) objc_setAssociatedObject(v, &kOrigH, @(f.size.height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            f.size.height = H; v.frame = f;
        } else if (!LGEnabled() && orig) {
            f.size.height = orig.doubleValue; v.frame = f;
            objc_setAssociatedObject(v, &kOrigH, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else return;
        if ([v isKindOfClass:[UITableView class]]) { [(UITableView *)v beginUpdates]; [(UITableView *)v endUpdates]; }
        return;
    }
    for (UIView *s in [v.subviews copy]) LGFeed(s);
}

static void LGSweepAll(UIWindow *w);

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

static void LGSweepAll(UIWindow *w) {
    gNative = LGFind(w, @"TTKFakeTabBar");
    LGFeed(w);
    if (gNative) LGNative(w); else LGSweep(w, w);
}

// Diagnóstico: vistas grandes o cercanas al borde inferior (para localizar el video y la barra).
static void LGDump(UIView *v, UIWindow *w, int d, NSMutableString *out) {
    if (d > 45 || out.length > 30000) return;
    CGRect r = [v convertRect:v.bounds toView:w];
    BOOL big = r.size.width >= w.bounds.size.width * 0.9 && r.size.height >= w.bounds.size.height * 0.4;
    BOOL low = CGRectGetMaxY(r) > w.bounds.size.height * 0.8 && r.size.width > 30 && r.size.height > 30;
    if (big || low) {
        [out appendFormat:@"%@%@ x=%.0f y=%.0f w=%.0f h=%.0f a=%.1f%@\n",
         [@"" stringByPaddingToLength:d * 2 withString:@" " startingAtIndex:0],
         NSStringFromClass(v.class), r.origin.x, r.origin.y, r.size.width, r.size.height, v.alpha, v.hidden ? @" HIDDEN" : @""];
    }
    for (UIView *s in v.subviews) LGDump(s, w, d + 1, out);
}

@implementation LGHandler

+ (instancetype)shared {
    static LGHandler *h; static dispatch_once_t t;
    dispatch_once(&t, ^{ h = [LGHandler new]; });
    return h;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return YES;
}

- (void)toggle:(UIButton *)sender {
    BOOL on = !LGEnabled();
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kLGKey];
    sender.tintColor = on ? UIColor.systemBlueColor : UIColor.whiteColor;
    UIWindow *w = LGKeyWindow();
    if (w) { LGRefreshTree(w); LGSweepAll(w); }
    [[UIImpactFeedbackGenerator new] impactOccurred];
}

- (void)press:(UILongPressGestureRecognizer *)gr {
    UIView *g = [gr.view viewWithTag:kLGGlassTag];
    if (!g) return;
    BOOL down = (gr.state == UIGestureRecognizerStateBegan || gr.state == UIGestureRecognizerStateChanged);
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ g.transform = down ? CGAffineTransformMakeScale(1.07, 1.12) : CGAffineTransformIdentity; }
                     completion:nil];
}

- (void)drag:(UIPanGestureRecognizer *)pan {
    UIView *v = pan.view;
    CGPoint t = [pan translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [pan setTranslation:CGPointZero inView:v.superview];
}

- (void)dump:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    UIWindow *w = LGKeyWindow();
    if (!w) return;
    NSMutableString *out = [NSMutableString stringWithFormat:@"screen %.0fx%.0f\n", w.bounds.size.width, w.bounds.size.height];
    LGDump(w, w, 0, out);
    [UIPasteboard generalPasteboard].string = out;
    UIViewController *top = w.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Copiado"
        message:@"Mapa de vistas copiado. Pégalo en el chat." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [top presentViewController:a animated:YES completion:nil];
}

- (void)install {
    UIWindow *w = LGKeyWindow();
    if (!w || [w viewWithTag:kLGButtonTag]) return;

    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = kLGButtonTag;
    b.frame = CGRectMake(w.bounds.size.width - 64, w.safeAreaInsets.top + 120, 48, 48);
    b.layer.cornerRadius = 24;
    b.clipsToBounds = YES;
    [b setImage:[UIImage systemImageNamed:@"sparkles"] forState:UIControlStateNormal];
    b.tintColor = LGEnabled() ? UIColor.systemBlueColor : UIColor.whiteColor;

    UIVisualEffectView *bg = LGMakeGlass();
    if (!bg) bg = [[UIVisualEffectView alloc] initWithEffect:
                   [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    bg.frame = b.bounds;
    bg.userInteractionEnabled = NO;
    [b insertSubview:bg atIndex:0];

    [b addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
    [b addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(dump:)];
    lp.minimumPressDuration = 0.8;
    [b addGestureRecognizer:lp];
    [w addSubview:b];

    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(__unused NSTimer *t) {
        UIWindow *kw = LGKeyWindow();
        if (kw) LGSweepAll(kw);
    }];
}

@end

%hook UITabBar
- (void)layoutSubviews {
    %orig;
    if (!gNative && ![NSStringFromClass(self.class) hasPrefix:@"TTK"]) LGApply(self);
}
%end

// Logos declara las clases desconocidas como NSObject; hay que decirle que es una UITableView.
@interface AWENewFeedTableView : UITableView
@end

%hook AWENewFeedTableView
- (void)setFrame:(CGRect)f {
    if (LGEnabled() && self.superview) {
        CGFloat H = self.superview.bounds.size.height;
        if (f.size.height < H && f.size.height > H * 0.8) f.size.height = H;
    }
    %orig(f);
}
%end

%ctor {
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification *n) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [[LGHandler shared] install]; });
    }];
}
