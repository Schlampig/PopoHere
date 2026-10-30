#import "PHPanel.h"

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
    w.hasShadow = YES;                 // 透明窗口的阴影会跟着内容 alpha（圆角）走
    w.level = NSFloatingWindowLevel;
    w.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                            NSWindowCollectionBehaviorFullScreenAuxiliary);
    w.releasedWhenClosed = NO;

    // 真毛玻璃：采样窗口背后的桌面
    NSVisualEffectView *vev = [[NSVisualEffectView alloc] initWithFrame:frame];
    vev.material = NSVisualEffectMaterialHUDWindow;
    vev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    vev.state = NSVisualEffectStateActive;
    vev.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    // 关键：把毛玻璃裁成圆角，否则窗口 alpha 是方的，阴影也是方的
    vev.wantsLayer = YES;
    vev.layer.cornerRadius = 16.0;
    vev.layer.masksToBounds = YES;
    w.contentView = vev;

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

    WKWebView *wv = [[WKWebView alloc] initWithFrame:self.window.contentView.bounds configuration:cfg];
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

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [webView evaluateJavaScript:[NSString stringWithFormat:@"Panel.setView('%@')", self.view]
             completionHandler:nil];
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
    [self.window makeKeyAndOrderFront:nil];
    if (self.onShow) self.onShow();
}

- (void)showAtBottomRight {
    self.anchorRight = YES;
    NSSize size = self.window.frame.size;
    NSRect vis = [NSScreen mainScreen].visibleFrame;
    // 紧贴屏幕右侧与底部
    CGFloat x = NSMaxX(vis) - size.width;
    CGFloat y = NSMinY(vis);
    [self.window setFrame:NSMakeRect(x, y, size.width, size.height) display:YES];
    [self.window orderFront:nil];                // 不抢焦点
    if (self.onShow) self.onShow();
}

/** 尺寸变了：菜单保持左上角不动，状态面板保持贴右下角；两者都不许跑出屏幕 */
- (void)applySize:(NSSize)size {
    NSRect vis = [NSScreen mainScreen].visibleFrame;
    NSRect f = self.window.frame;
    CGFloat top = NSMaxY(f);

    f.size = size;
    if (self.anchorRight) {
        f.origin.x = NSMaxX(vis) - size.width;
        f.origin.y = NSMinY(vis);
    } else {
        f.origin.y = top - size.height;
    }
    f.origin.x = MAX(NSMinX(vis), MIN(f.origin.x, NSMaxX(vis) - size.width));
    f.origin.y = MAX(NSMinY(vis), MIN(f.origin.y, NSMaxY(vis) - size.height));
    [self.window setFrame:f display:YES];
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
