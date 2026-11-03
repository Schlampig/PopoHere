//  PopoHere · 玻璃面板窗口的实现
//
//  职责
//    1. 创建「无边框 + 透明 + 置顶」的 NSWindow，内容为圆角毛玻璃面板；
//    2. 内嵌 WKWebView 渲染 panel.html，负责视图切换与尺寸上报；
//    3. 把页面上的交互（确认按钮、拖动、调整尺寸）转成回调交给外壳。
//
//  关键实现
//    · 圆角：NSVisualEffectView 的材质由系统在独立图层合成，仅设置 layer.cornerRadius
//      无法裁掉材质本体，因此使用 maskImage 裁切，并由容器视图再裁剪一次；
//      窗口 alpha 为圆角后，系统绘制的阴影也会随之变圆。
//    · 窗口尺寸变化后调用 invalidateShadow，避免阴影沿用旧尺寸的方形轮廓。
//    · WKWebView 子类接受 first mouse，使非 key window 上的首次点击即时生效。
//
//  构建方式见 code/build/build_app.sh


#import "PHPanel.h"

/** 面板圆角半径（pt）。与 panel.html 中 `--radius-panel` 的 16px 一一对应：
    网页层画的是圆角深色底，原生层负责把毛玻璃材质裁成同一个圆角。 */
static CGFloat const kPanelCornerRadius = 16.0;

/**
 生成毛玻璃层的圆角蒙版。

 背景：NSVisualEffectView 的材质由系统在独立的背景图层中合成，仅设置
 `layer.cornerRadius` 并不能裁掉材质本体，圆角之外会残留一圈方角，
 在浅色桌面上表现为"玻璃纸"外露的直角。

 `maskImage` 是系统为这种场景提供的裁切入口：提供一张四角透明的图，
 系统按 `capInsets` 拉伸中间区域填充整个视图，四角保持圆角轮廓。
 */
static NSImage *PHCornerMaskImage(CGFloat radius) {
    CGFloat side = radius * 2 + 1;
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(side, side)];
    [image lockFocus];
    [[NSColor blackColor] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, side, side)
                                     xRadius:radius
                                     yRadius:radius] fill];
    [image unlockFocus];
    image.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
    image.resizingMode = NSImageResizingModeStretch;
    return image;
}

/** 面板窗口通常不是 key window（提醒若抢焦点会打断用户输入），
    AppKit 默认会把"第一下点击"只用于激活窗口，表现为按钮要点两次。
    让 WKWebView 接受 first mouse，一次点击即生效。 */
@interface PHFirstMouseWebView : WKWebView
@end

@implementation PHFirstMouseWebView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
@end

@implementation PHPanelController

- (instancetype)initWithView:(NSString *)view {
    self = [super init];
    if (!self) return nil;
    _view = [view copy];
    _dismissOnResignKey = [view isEqualToString:@"menu"];
    [self buildWindow];
    [self buildWebView];
    return self;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 280, 200);
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
                                             styleMask:NSWindowStyleMaskBorderless
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    w.opaque = NO;
    w.backgroundColor = NSColor.clearColor;
    w.hasShadow = YES;                 // 阴影由窗口 alpha 推导，内容为圆角时阴影随之变圆
    w.level = NSFloatingWindowLevel;
    w.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                            NSWindowCollectionBehaviorFullScreenAuxiliary);
    w.releasedWhenClosed = NO;

    // 容器视图：把整棵视图树裁成圆角，保证窗口 alpha 也是圆角（阴影才不会方）
    NSView *container = [[NSView alloc] initWithFrame:frame];
    container.wantsLayer = YES;
    container.layer.cornerRadius = kPanelCornerRadius;
    container.layer.masksToBounds = YES;
    container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // 真毛玻璃：采样窗口背后的桌面
    NSVisualEffectView *vev = [[NSVisualEffectView alloc] initWithFrame:frame];
    vev.material = NSVisualEffectMaterialHUDWindow;
    vev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    vev.state = NSVisualEffectStateActive;
    vev.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    vev.maskImage = PHCornerMaskImage(kPanelCornerRadius);   // 材质本体裁圆角
    [container addSubview:vev];

    w.contentView = container;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowResignedKey:)
                                                 name:NSWindowDidResignKeyNotification
                                               object:w];
    _window = w;
}

- (void)buildWebView {
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:self name:@"popo"];
    cfg.userContentController = ucc;

    WKWebView *wv = [[PHFirstMouseWebView alloc] initWithFrame:self.window.contentView.bounds
                                                 configuration:cfg];
    wv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    @try {
        [wv setValue:@NO forKey:@"drawsBackground"];
    } @catch (NSException *e) {
        NSLog(@"PHPanel: 无法设置透明背景 %@", e);
    }
    wv.wantsLayer = YES;
    wv.layer.opaque = NO;
    wv.navigationDelegate = self;
    [self.window.contentView addSubview:wv];
    _web = wv;

    NSString *path = [[[NSBundle mainBundle] resourcePath]
        stringByAppendingPathComponent:@"app/panel.html"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSLog(@"PHPanel: 找不到 panel.html (%@)", path);
        return;
    }
    // 注意：不要用 file: 的 query 传参，WKWebView 对带 query 的 file URL 支持不稳定；
    // 视图切换在 didFinishNavigation 里用 JS 调用完成。
    [wv loadFileURL:[NSURL fileURLWithPath:path]
        allowingReadAccessToURL:[NSURL fileURLWithPath:[path stringByDeletingLastPathComponent]]];
}

- (void)applyView {
    NSString *js = [NSString stringWithFormat:@"Panel && Panel.setView('%@')", self.view ?: @"menu"];
    [self.web evaluateJavaScript:js completionHandler:nil];
}

/* 视图的唯一入口：修改属性即同步页面。
   若页面与属性各自维护视图状态，面板可能停留在此前的子页面，
   而外壳仍认为它处于主菜单；由属性驱动可保证两侧始终一致。 */
- (void)setView:(NSString *)view {
    _view = [view copy];
    [self applyView];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self applyView];      // 页面刚加载完，把当前视图推过去
}

#pragma mark - 显示

- (BOOL)isShown { return self.window.isVisible; }

- (void)showAtPoint:(NSPoint)point {
    NSSize size = self.window.frame.size;
    NSRect vis = [NSScreen mainScreen].visibleFrame;

    CGFloat x = point.x;
    CGFloat y = point.y - size.height;          // point 是左上角，AppKit 原点在左下

    // 贴边时往里收，别跑出屏幕
    x = MAX(NSMinX(vis) + 4, MIN(x, NSMaxX(vis) - size.width - 4));
    y = MAX(NSMinY(vis) + 4, MIN(y, NSMaxY(vis) - size.height - 4));

    [self.window setFrame:NSMakeRect(x, y, size.width, size.height) display:YES];
    [self.window invalidateShadow];
    [self.window makeKeyAndOrderFront:nil];
    if (self.onShow) self.onShow();
}

- (void)showAtTopRight {
    self.anchorTopRight = YES;
    self.anchorRight = NO;
    NSSize size = self.window.frame.size;
    NSRect vis = [NSScreen mainScreen].visibleFrame;
    CGFloat x = NSMaxX(vis) - size.width - 16;
    CGFloat y = NSMaxY(vis) - size.height - 16;
    [self.window setFrame:NSMakeRect(x, y, size.width, size.height) display:YES];
    [self.window invalidateShadow];
    [self.window orderFrontRegardless];      // 提醒要压住其它窗口，但不抢键盘焦点
    if (self.onShow) self.onShow();
}

- (void)invokeJS:(NSString *)js {
    if (!js.length || !self.web) return;
    [self.web evaluateJavaScript:js completionHandler:nil];
}

- (void)showAtBottomRight {
    self.anchorRight = YES;
    self.anchorTopRight = NO;
    NSSize size = self.window.frame.size;
    NSRect vis = [NSScreen mainScreen].visibleFrame;
    // 紧贴屏幕右侧与底部
    CGFloat x = NSMaxX(vis) - size.width;
    CGFloat y = NSMinY(vis);
    [self.window setFrame:NSMakeRect(x, y, size.width, size.height) display:YES];
    [self.window invalidateShadow];
    [self.window orderFront:nil];                // 不抢焦点
    if (self.onShow) self.onShow();
}

/** 尺寸变了：菜单保持左上角不动，状态面板保持贴右下角；两者都不许跑出屏幕 */
- (void)applySize:(NSSize)size {
    NSRect vis = [NSScreen mainScreen].visibleFrame;
    NSRect f = self.window.frame;
    CGFloat top = NSMaxY(f);

    f.size = size;
    if (self.anchorTopRight) {
        f.origin.x = NSMaxX(vis) - size.width - 16;
        f.origin.y = NSMaxY(vis) - size.height - 16;
    } else if (self.anchorRight) {
        f.origin.x = NSMaxX(vis) - size.width;
        f.origin.y = NSMinY(vis);
    } else {
        f.origin.y = top - size.height;
    }
    f.origin.x = MAX(NSMinX(vis), MIN(f.origin.x, NSMaxX(vis) - size.width));
    f.origin.y = MAX(NSMinY(vis), MIN(f.origin.y, NSMaxY(vis) - size.height));
    [self.window setFrame:f display:YES];
    [self.window invalidateShadow];
}

- (void)hide {
    if (!self.window.isVisible) return;
    [self.window orderOut:nil];
    if (self.onHide) self.onHide();
}

- (void)windowResignedKey:(NSNotification *)note {
    if (self.dismissOnResignKey) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self hide]; });
    }
}

#pragma mark - 与页面通信

- (void)userContentController:(WKUserContentController *)ucc
      didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *body = message.body;
    if (![body isKindOfClass:[NSDictionary class]]) return;
    NSString *type = body[@"type"];

    if ([type isEqualToString:@"panelResize"]) {
        CGFloat w = [body[@"width"] doubleValue];
        CGFloat h = [body[@"height"] doubleValue];
        if (w < 40 || h < 40) return;
        [self applySize:NSMakeSize(w, h)];
        return;
    }
    if ([type isEqualToString:@"panelDragStart"]) {
        if (self.onDragStart) self.onDragStart();
        return;
    }
    if ([type isEqualToString:@"action"]) {
        NSString *action = body[@"action"];
        id value = body[@"value"];
        if ([action isEqualToString:@"closePanel"]) { [self hide]; return; }
        if (self.onAction) self.onAction(action, value);
        return;
    }
}

- (void)update:(NSDictionary *)snapshot {
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:&err];
    if (!data) return;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *js = [NSString stringWithFormat:@"window.Panel && Panel.update(%@);", json];
    [self.web evaluateJavaScript:js completionHandler:nil];
}

@end
