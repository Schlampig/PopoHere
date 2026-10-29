//  PopoHere —— macOS 原生外壳。
//  一个透明的浮窗 + 一个 WKWebView + 菜单栏图标。
//  猫的动画与状态机全部在 Web 里实现，这里只负责：窗口、置顶、拖拽、菜单栏、偏好设置。
//
//  编译方式见 build.sh

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <mach-o/dyld.h>

static CGFloat const kPad = 16.0;   // 与 build/app/index.html 里留白一致
static CGFloat const kDragThreshold = 5.0;   // 超过这个位移才算拖拽，否则算单击
static NSString * const kSizeKey = @"PopoSize";
static NSString * const kXKey = @"PopoX";
static NSString * const kYKey = @"PopoY";
static NSString * const kHiddenKey = @"PopoHidden";

@interface PHDelegate : NSObject <NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) WKWebView *web;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic) BOOL pressing;          // 鼠标按在猫身上
@property (nonatomic) BOOL movedDuringPress;  // 本次按压已经越过拖拽阈值
@property (nonatomic) NSPoint pressMouse;     // 按下时的鼠标位置（屏幕坐标）
@property (nonatomic) NSPoint pressOrigin;    // 按下时的窗口原点
@property (nonatomic, strong) id dragMonitor; // 本地事件监视器
@end

@implementation PHDelegate

#pragma mark - 启动

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildWindow];
    [self buildWebView];
    [self buildStatusItem];
    [self restoreState];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenChanged:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];

    // 兜底：万一 webView 的 finish 回调没来，2 秒后强制显示，避免猫一直隐身
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.window.alphaValue < 1.0) {
            NSLog(@"PopoHere 兜底显示窗口");
            self.window.alphaValue = 1.0;
        }
    });
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self savePosition];
}

#pragma mark - 窗口

- (CGFloat)petSize {
    CGFloat s = [[NSUserDefaults standardUserDefaults] doubleForKey:kSizeKey];
    return s < 60 ? 220.0 : s;
}

- (NSWindow *)buildWindow {
    CGFloat total = [self petSize] + kPad * 2;
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, total, total)
                                             styleMask:NSWindowStyleMaskBorderless
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    w.opaque = NO;
    w.backgroundColor = NSColor.clearColor;
    w.hasShadow = NO;
    w.level = NSFloatingWindowLevel;
    w.ignoresMouseEvents = NO;
    w.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                            NSWindowCollectionBehaviorStationary |
                            NSWindowCollectionBehaviorFullScreenAuxiliary);
    w.alphaValue = 0.0;                       // 加载完淡入，避免首帧白块
    self.window = w;
    return w;
}

- (NSURL *)appHTMLURL {
    NSBundle *b = [NSBundle mainBundle];
    NSFileManager *fm = [NSFileManager defaultManager];
    // 依次尝试：正常的 app 包 / 直接跑二进制 / 从项目根目录调试
    NSArray *candidates = @[
        [[b resourcePath] stringByAppendingPathComponent:@"app/index.html"],
        [[b bundlePath] stringByAppendingPathComponent:@"Contents/Resources/app/index.html"],
        [[[b bundlePath] stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"Resources/app/index.html"],
        [[fm currentDirectoryPath] stringByAppendingPathComponent:@"build/app/index.html"],
    ];
    for (NSString *p in candidates) {
        if ([fm fileExistsAtPath:p]) return [NSURL fileURLWithPath:p];
    }
    return [NSURL fileURLWithPath:[candidates firstObject]];
}

- (void)buildWebView {
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:self name:@"popo"];
    cfg.userContentController = ucc;

    WKWebView *wv = [[WKWebView alloc] initWithFrame:self.window.contentView.bounds configuration:cfg];
    wv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    @try {
        [wv setValue:@NO forKey:@"drawsBackground"];  // 关键：私有 API，让透明区域真的透明
    } @catch (NSException *e) {
        NSLog(@"PopoHere: 无法设置透明背景 %@", e);
    }
    wv.wantsLayer = YES;
    wv.layer.opaque = NO;
    wv.layer.backgroundColor = CGColorGetConstantColor(kCGColorClear);
    wv.allowsMagnification = NO;
    wv.navigationDelegate = self;
    self.web = wv;
    [self.window.contentView addSubview:wv];

    NSURL *u = [self appHTMLURL];
    NSURL *root = [u URLByDeletingLastPathComponent];
    NSLog(@"PopoHere 加载 %@", u.path);
    if (![[NSFileManager defaultManager] fileExistsAtPath:u.path]) {
        NSLog(@"PopoHere 找不到 index.html");
        return;
    }
    [wv loadFileURL:u allowingReadAccessToURL:root];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"PopoHere 页面加载完成");
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL paused = [d boolForKey:@"PopoPaused"];
    [webView evaluateJavaScript:[NSString stringWithFormat:@"App.setPaused(%@)", paused ? @"true" : @"false"]
              completionHandler:nil];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.4;
        self.window.animator.alphaValue = 1.0;
    }];
}

#pragma mark - JS → Native

- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *b = message.body;
    NSString *type = b[@"type"];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    if ([type isEqualToString:@"press"]) {
        [self beginPress];
    } else if ([type isEqualToString:@"release"]) {
        [self endPress];
    } else if ([type isEqualToString:@"hidden"]) {
        BOOL hidden = [b[@"value"] boolValue];
        [d setBool:hidden forKey:kHiddenKey];
        if (hidden) [self.window orderOut:nil];
        else [self.window makeKeyAndOrderFront:nil];
    } else if ([type isEqualToString:@"paused"]) {
        [d setBool:[b[@"value"] boolValue] forKey:@"PopoPaused"];
        [self syncMenuState:[b[@"value"] boolValue] hidden:[d boolForKey:kHiddenKey]];
    } else if ([type isEqualToString:@"openTheme"]) {
        [self openResources:self];
    } else if ([type isEqualToString:@"ready"]) {
        NSLog(@"PopoHere Web 就绪：状态机已跑起来");
    } else if ([type isEqualToString:@"quit"]) {
        [self savePosition];
        [NSApp terminate:nil];
    }
}

#pragma mark - 拖拽（原生跟踪，保证跟手）

// 关键：整套拖拽只用屏幕坐标推算位移，不经过网页坐标系。
// 早期版本让 JS 用 clientX 算 delta、再由这里移动窗口，会形成反馈环
// （窗口一动，视口跟着动，clientX 又被拉回原点），表现为漂移 + 剧烈抖动。

- (void)beginPress {
    self.pressing = YES;
    self.movedDuringPress = NO;
    self.pressMouse = [NSEvent mouseLocation];
    self.pressOrigin = self.window.frame.origin;
    [self installDragMonitor];
}

- (void)installDragMonitor {
    if (self.dragMonitor) return;
    __weak typeof(self) weakSelf = self;
    NSEventMask mask = NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp;
    self.dragMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask
                                                            handler:^NSEvent *(NSEvent *e) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return e;
        if (e.type == NSEventTypeLeftMouseUp) {
            [self endPress];
        } else {
            [self updateDrag];
        }
        return e;   // 不吞事件：JS 也要收到 mouseup 去推进状态机
    }];
}

- (void)updateDrag {
    if (!self.pressing) return;
    NSPoint mouse = [NSEvent mouseLocation];
    CGFloat dx = mouse.x - self.pressMouse.x;
    CGFloat dy = mouse.y - self.pressMouse.y;
    if (!self.movedDuringPress) {
        if (hypot(dx, dy) < kDragThreshold) return;   // 还在单击的抖动范围内，先不动
        self.movedDuringPress = YES;
    }
    // 位移按"按下时的绝对原点 + 累计屏幕位移"计算，不存在误差累积
    [self.window setFrameOrigin:NSMakePoint(self.pressOrigin.x + dx, self.pressOrigin.y + dy)];
}

- (void)endPress {
    self.pressing = NO;
    if (self.dragMonitor) {
        [NSEvent removeMonitor:self.dragMonitor];
        self.dragMonitor = nil;
    }
    if (self.movedDuringPress) {
        self.movedDuringPress = NO;
        [self savePosition];
    }
}

#pragma mark - 位置持久化

- (void)savePosition {
    NSPoint o = self.window.frame.origin;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setDouble:o.x forKey:kXKey];
    [d setDouble:o.y forKey:kYKey];
}

- (void)restoreState {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    id x = [d objectForKey:kXKey];
    id y = [d objectForKey:kYKey];
    if (x && y) {
        [self.window setFrameOrigin:NSMakePoint([x doubleValue], [y doubleValue])];
    } else {
        NSRect vis = [NSScreen mainScreen].visibleFrame;
        CGFloat size = self.window.frame.size.height;
        [self.window setFrameOrigin:NSMakePoint(NSMinX(vis) + 30, NSMinY(vis) + 40)];
        (void)size;
    }
    if (![d boolForKey:kHiddenKey]) {
        [self.window makeKeyAndOrderFront:nil];
    }
}

- (void)screenChanged:(NSNotification *)n {
    // 屏幕变化时把猫拉回可见区域
    NSRect vis = [NSScreen mainScreen].visibleFrame;
    NSRect f = self.window.frame;
    f.origin.x = MAX(NSMinX(vis), MIN(f.origin.x, NSMaxX(vis) - NSWidth(f)));
    f.origin.y = MAX(NSMinY(vis), MIN(f.origin.y, NSMaxY(vis) - NSHeight(f)));
    [self.window setFrameOrigin:f.origin];
}

#pragma mark - 菜单栏

- (NSStatusItem *)buildStatusItem {
    NSStatusItem *item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    NSImage *img = [[NSImage alloc] initWithContentsOfFile:
                    [[NSBundle mainBundle] pathForResource:@"tray_icon" ofType:@"png"]];
    [img setTemplate:YES];                    // 模板图标，自动适配明暗菜单栏
    [img setSize:NSMakeSize(20, 20)];
    item.button.image = img;
    item.button.toolTip = @"PopoHere";

    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *toggle = [[NSMenuItem alloc] initWithTitle:@"隐藏 Popo"
                                                   action:@selector(toggleHidden:)
                                            keyEquivalent:@""];
    toggle.tag = 101;
    [menu addItem:toggle];
    [menu addItemWithTitle:@"暂停互动" action:@selector(togglePaused:) keyEquivalent:@""].tag = 102;
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *sizeItem = [[NSMenuItem alloc] initWithTitle:@"大小" action:nil keyEquivalent:@""];
    NSMenu *sizes = [[NSMenu alloc] init];
    for (NSNumber *s in @[@160, @220, @300, @380]) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ px", s]
                                                   action:@selector(setSizeFromMenu:)
                                            keyEquivalent:@""];
        mi.representedObject = s;
        [sizes addItem:mi];
    }
    sizeItem.submenu = sizes;
    [menu addItem:sizeItem];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"打开素材目录" action:@selector(openResources:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"退出" action:@selector(quit:) keyEquivalent:@"q"];
    menu.autoenablesItems = NO;

    for (NSMenuItem *mi in menu.itemArray) { mi.target = self; }
    item.menu = menu;
    self.statusItem = item;

    [self syncMenuState:[[NSUserDefaults standardUserDefaults] boolForKey:@"PopoPaused"]
                hidden:[[NSUserDefaults standardUserDefaults] boolForKey:kHiddenKey]];
    return item;
}

- (void)syncMenuState:(BOOL)paused hidden:(BOOL)hidden {
    NSMenu *m = self.statusItem.menu;
    for (NSMenuItem *mi in m.itemArray) {
        if (mi.tag == 101) mi.title = hidden ? @"显示 Popo" : @"隐藏 Popo";
        if (mi.tag == 102) mi.state = paused ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)toggleHidden:(id)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL hidden = ![d boolForKey:kHiddenKey];
    [d setBool:hidden forKey:kHiddenKey];
    if (hidden) [self.window orderOut:nil];
    else [self.window makeKeyAndOrderFront:nil];
    [self.web evaluateJavaScript:[NSString stringWithFormat:@"App.show(%@)", hidden ? @"false" : @"true"]
               completionHandler:nil];
    [self syncMenuState:[d boolForKey:@"PopoPaused"] hidden:hidden];
}

- (void)togglePaused:(id)sender {
    [self.web evaluateJavaScript:@"App.togglePaused()" completionHandler:^(id v, NSError *e) {
        BOOL paused = [v boolValue];
        [[NSUserDefaults standardUserDefaults] setBool:paused forKey:@"PopoPaused"];
        [self syncMenuState:paused hidden:[[NSUserDefaults standardUserDefaults] boolForKey:kHiddenKey]];
    }];
}

- (void)setSizeFromMenu:(id)sender {
    CGFloat newSize = [((NSMenuItem *)sender).representedObject doubleValue];
    [[NSUserDefaults standardUserDefaults] setDouble:newSize forKey:kSizeKey];
    CGFloat total = newSize + kPad * 2;
    NSRect f = self.window.frame;
    f.origin.y += (NSHeight(f) - total);      // 底边不动
    f.size = NSMakeSize(total, total);
    [self.window setFrame:f display:YES animate:YES];
    [self.web evaluateJavaScript:[NSString stringWithFormat:@"App.setSize(%f)", newSize]
               completionHandler:nil];
}

- (void)openResources:(id)sender {
    NSURL *dir = [[[NSBundle mainBundle] resourceURL] URLByAppendingPathComponent:@"app" isDirectory:YES];
    [[NSWorkspace sharedWorkspace] openURL:dir];
}

- (void)quit:(id)sender {
    [self savePosition];
    [NSApp terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];  // 不在 Dock 里显示
        PHDelegate *d = [PHDelegate new];
        app.delegate = d;
        [app run];
    }
    return 0;
}
