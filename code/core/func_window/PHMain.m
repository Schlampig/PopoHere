//  PopoHere —— macOS 原生外壳。
//
//  透明的宠物浮窗 + WKWebView（猫的行为在 Web 里）+ 菜单栏图标 + 两个玻璃面板。
//  这个文件只负责"外壳"：窗口、拖拽、菜单、持久化、提醒计时。
//
//  功能模块各管各的：
//    func_reminder/PHReminder     定时提醒
//    func_checklist/PHChecklist   待办清单
//    func_window/PHPanel          玻璃面板窗口
//
//  编译方式见 code/build/build_app.sh

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <mach-o/dyld.h>

#import "PHPanel.h"
#import "PHReminder.h"
#import "PHChecklist.h"

static CGFloat const kPad = 16.0;             // 与 index.html 留白一致
static CGFloat const kDragThreshold = 5.0;    // 超过这个位移才算拖拽

static NSString * const kSizeKey = @"PopoSize";
static NSString * const kXKey = @"PopoX";
static NSString * const kYKey = @"PopoY";
static NSString * const kHiddenKey = @"PopoHidden";
static NSString * const kPausedKey = @"PopoPaused";
static NSString * const kSoundKey = @"PopoSound";
static NSString * const kStatusOpenKey = @"PopoStatusOpen";

static NSString * const kGithubURL = @"https://github.com/Schlampig/PopoHere";

// 状态 → 中文名（面板里展示用，顺序即展示顺序）
static NSArray<NSArray<NSString *> *> *StateCatalog(void) {
    static NSArray *catalog;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        catalog = @[
            @[@"idle", @"静息"],
            @[@"touch", @"被撸"],
            @[@"scratch", @"挠人"],
            @[@"play", @"自娱"],
            @[@"sleep", @"睡觉"],
            @[@"dragging", @"被抱起"],
            @[@"startled", @"惊醒"],
            @[@"landed", @"落地"],
        ];
    });
    return catalog;
}

@interface PHDelegate : NSObject <NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) WKWebView *web;
@property (nonatomic, strong) NSStatusItem *statusItem;

@property (nonatomic, strong) PHPanelController *menuPanel;
@property (nonatomic, strong) PHPanelController *statusPanel;
@property (nonatomic, strong) PHReminderStore *reminders;
@property (nonatomic, strong) PHChecklist *checklist;
@property (nonatomic, strong) NSTimer *tickTimer;

// 拖拽（宠物窗口 + 状态面板共用一套逻辑）
@property (nonatomic) BOOL pressing;
@property (nonatomic) BOOL movedDuringPress;
@property (nonatomic) NSPoint pressMouse;
@property (nonatomic) NSPoint pressOrigin;
@property (nonatomic, weak) NSWindow *dragTarget;
@property (nonatomic, strong) id dragMonitor;

@property (nonatomic) BOOL petHidden;
@end

@implementation PHDelegate

#pragma mark - 启动

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.reminders = [PHReminderStore new];
    self.checklist = [PHChecklist new];

    [self buildWindow];
    [self buildWebView];
    [self buildPanels];
    [self buildStatusItem];
    [self restoreState];

    self.tickTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                      target:self
                                                    selector:@selector(onTick:)
                                                    userInfo:nil
                                                     repeats:YES];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenChanged:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.window.alphaValue < 1.0) self.window.alphaValue = 1.0;
    });
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self savePosition];
}

#pragma mark - 宠物窗口

- (CGFloat)petSize {
    CGFloat s = [[NSUserDefaults standardUserDefaults] doubleForKey:kSizeKey];
    return s < 60 ? 220.0 : s;
}

- (void)buildWindow {
    CGFloat total = [self petSize] + kPad * 2;
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, total, total)
                                             styleMask:NSWindowStyleMaskBorderless
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    w.opaque = NO;
    w.backgroundColor = NSColor.clearColor;
    w.hasShadow = NO;
    w.level = NSFloatingWindowLevel;
    w.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                            NSWindowCollectionBehaviorStationary |
                            NSWindowCollectionBehaviorFullScreenAuxiliary);
    w.alphaValue = 0.0;
    self.window = w;
}

- (NSURL *)appHTMLURL {
    NSBundle *b = [NSBundle mainBundle];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *candidates = @[
        [[b resourcePath] stringByAppendingPathComponent:@"app/index.html"],
        [[b bundlePath] stringByAppendingPathComponent:@"Contents/Resources/app/index.html"],
    ];
    for (NSString *p in candidates) {
        if ([fm fileExistsAtPath:p]) return [NSURL fileURLWithPath:p];
    }
    return [NSURL fileURLWithPath:candidates.firstObject];
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
    NSLog(@"PopoHere 加载 %@", u.path);
    if (![[NSFileManager defaultManager] fileExistsAtPath:u.path]) {
        NSLog(@"PopoHere 找不到 index.html");
        return;
    }
    [wv loadFileURL:u allowingReadAccessToURL:[u URLByDeletingLastPathComponent]];
}

- (void)buildPanels {
    __weak typeof(self) weakSelf = self;

    self.menuPanel = [[PHPanelController alloc] initWithView:@"menu"];
    self.menuPanel.onAction = ^(NSString *action, id value) { [weakSelf performAction:action value:value]; };
    self.menuPanel.onHide = ^{
        [weakSelf.web evaluateJavaScript:@"App.menuClosed && App.menuClosed();" completionHandler:nil];
    };

    self.statusPanel = [[PHPanelController alloc] initWithView:@"status"];
    self.statusPanel.dismissOnResignKey = NO;
    self.statusPanel.onAction = ^(NSString *action, id value) { [weakSelf performAction:action value:value]; };
    self.statusPanel.onDragStart = ^{ [weakSelf beginPanelDrag]; };
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"PopoHere 页面加载完成 url=%@", webView.URL.path);
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL paused = [d boolForKey:kPausedKey];
    [webView evaluateJavaScript:[NSString stringWithFormat:@"App.setPaused(%@)", paused ? @"true" : @"false"]
              completionHandler:nil];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.4;
        self.window.animator.alphaValue = 1.0;
    }];
}

#pragma mark - 提醒 / 状态刷新

- (void)onTick:(NSTimer *)timer {
    NSString *due = [self.reminders tick];
    if (due) {
        if (self.petHidden) {
            [self notifyViaIcon:due];
        } else {
            NSString *js = [NSString stringWithFormat:@"App.notify('⏰ %@', 6000);", due];
            [self.web evaluateJavaScript:js completionHandler:nil];
        }
    }
    if (self.statusPanel.isShown) [self pushSnapshotToPanels];
}

- (void)notifyViaIcon:(NSString *)text {
    // 猫被藏起来了就没有气泡可弹，退化成菜单栏图标的高亮提示
    self.statusItem.button.toolTip = [NSString stringWithFormat:@"PopoHere · %@", text];
    self.statusItem.button.appearsDisabled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.statusItem.button.appearsDisabled = NO;
        self.statusItem.button.toolTip = @"PopoHere";
    });
}

#pragma mark - JS → Native

- (void)userContentController:(WKUserContentController *)ucc
      didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *b = message.body;
    if (![b isKindOfClass:[NSDictionary class]]) return;
    NSString *type = b[@"type"];

    if ([type isEqualToString:@"press"]) {
        [self beginPress];
    } else if ([type isEqualToString:@"release"]) {
        [self endPress];
    } else if ([type isEqualToString:@"jserror"]) {
        NSLog(@"PopoHere JS 异常: %@", b[@"message"]);
    } else if ([type isEqualToString:@"openMenu"]) {
        [self openMenuAtX:[b[@"x"] doubleValue] y:[b[@"y"] doubleValue]];
    } else if ([type isEqualToString:@"hidden"]) {
        [self setPetHidden:[b[@"value"] boolValue]];
    } else if ([type isEqualToString:@"paused"]) {
        [[NSUserDefaults standardUserDefaults] setBool:[b[@"value"] boolValue] forKey:kPausedKey];
        [self refreshMenuChecks];
    } else if ([type isEqualToString:@"quit"]) {
        [self savePosition];
        [NSApp terminate:nil];
    }
}

#pragma mark - 菜单

- (void)buildStatusItem {
    NSStatusItem *item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    NSString *iconPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"tray_icon.png"];
    NSImage *img = [[NSImage alloc] initWithContentsOfFile:iconPath];
    [img setTemplate:YES];
    [img setSize:NSMakeSize(20, 20)];
    item.button.image = img;
    item.button.toolTip = @"PopoHere";

    NSMenu *menu = [[NSMenu alloc] init];
    menu.autoenablesItems = NO;

    [menu addItem:[self item:@"定时提醒" action:@"viewReminders"]];
    [menu addItem:[self item:@"待办清单" action:@"viewTodos"]];
    [menu addItem:[NSMenuItem separatorItem]];

    [menu addItem:[self item:@"显示 / 隐藏桌宠" action:@"togglePet"]];
    NSMenuItem *status = [self item:@"显示 / 隐藏桌宠状态" action:@"toggleStatus"];
    status.tag = 201;
    [menu addItem:status];

    NSMenuItem *sizeRoot = [[NSMenuItem alloc] initWithTitle:@"大小" action:nil keyEquivalent:@""];
    NSMenu *sizes = [[NSMenu alloc] init];
    for (NSNumber *px in @[@160, @220, @300, @380]) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ px", px]
                                                   action:@selector(onMenuItem:)
                                            keyEquivalent:@""];
        mi.target = self;
        mi.representedObject = @{ @"action": @"setSize", @"value": px };
        [sizes addItem:mi];
    }
    sizeRoot.submenu = sizes;
    [menu addItem:sizeRoot];

    NSMenuItem *soundRoot = [[NSMenuItem alloc] initWithTitle:@"声音" action:nil keyEquivalent:@""];
    NSMenu *sounds = [[NSMenu alloc] init];
    for (NSNumber *on in @[@YES, @NO]) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:on.boolValue ? @"开" : @"关"
                                                   action:@selector(onMenuItem:)
                                            keyEquivalent:@""];
        mi.target = self;
        mi.representedObject = @{ @"action": @"setSound", @"value": on };
        [sounds addItem:mi];
    }
    soundRoot.submenu = sounds;
    soundRoot.tag = 202;
    [menu addItem:soundRoot];

    NSMenuItem *pause = [self item:@"暂停互动" action:@"togglePause"];
    pause.tag = 203;
    [menu addItem:pause];

    NSMenuItem *autostart = [self item:@"开机自启" action:@"toggleAutostart"];
    autostart.tag = 204;
    [menu addItem:autostart];

    [menu addItem:[self item:@"打开素材文件夹" action:@"openAssets"]];
    [menu addItem:[self item:@"重置位置" action:@"resetPos"]];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self item:@"关于 PopoHere（跳转 Github）" action:@"github"]];
    [menu addItem:[self item:@"退出" action:@"quit"]];

    item.menu = menu;
    self.statusItem = item;
    [self refreshMenuChecks];
}

- (NSMenuItem *)item:(NSString *)title action:(NSString *)action {
    NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:title
                                                action:@selector(onMenuItem:)
                                         keyEquivalent:@""];
    mi.target = self;
    mi.representedObject = @{ @"action": action };
    return mi;
}

- (void)onMenuItem:(NSMenuItem *)sender {
    NSDictionary *rep = sender.representedObject;
    [self performAction:rep[@"action"] value:rep[@"value"]];
}

- (void)openMenuAtX:(CGFloat)x y:(CGFloat)y {
    CGFloat screenHeight = [NSScreen mainScreen].frame.size.height;
    NSPoint p = NSMakePoint(x, screenHeight - y);   // JS 的 y 从顶部算
    [self pushSnapshotToPanels];
    [self.menuPanel showAtPoint:p];
}

#pragma mark - 动作分发（菜单栏与玻璃面板共用）

- (void)performAction:(NSString *)action value:(id)value {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    if ([action isEqualToString:@"togglePet"]) {
        [self setPetHidden:!self.petHidden];

    } else if ([action isEqualToString:@"toggleStatus"]) {
        if (self.petHidden) return;                 // 桌宠不在，面板没有意义
        [self toggleStatusPanel];

    } else if ([action isEqualToString:@"setSize"]) {
        [self applySize:[value doubleValue]];

    } else if ([action isEqualToString:@"setSound"]) {
        [d setBool:[value boolValue] forKey:kSoundKey];
        [self refreshMenuChecks];

    } else if ([action isEqualToString:@"togglePause"]) {
        [self togglePause];

    } else if ([action isEqualToString:@"toggleAutostart"]) {
        [self toggleAutostart];

    } else if ([action isEqualToString:@"openAssets"]) {
        [self openResources:self];

    } else if ([action isEqualToString:@"resetPos"]) {
        NSRect vis = [NSScreen mainScreen].visibleFrame;
        [self.window setFrameOrigin:NSMakePoint(NSMinX(vis) + 30, NSMinY(vis) + 40)];
        [self savePosition];

    } else if ([action isEqualToString:@"github"]) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kGithubURL]];

    } else if ([action isEqualToString:@"quit"]) {
        [self savePosition];
        [NSApp terminate:nil];

    } else if ([action isEqualToString:@"viewReminders"] || [action isEqualToString:@"viewTodos"]) {
        [self pushSnapshotToPanels];
        if (!self.menuPanel.isShown) {
            NSPoint p = NSMakePoint(NSMidX(self.statusItem.button.window.frame),
                                    NSMaxY(NSScreen.mainScreen.frame) - 24);
            [self.menuPanel showAtPoint:p];
        }
        NSString *view = [action isEqualToString:@"viewReminders"] ? @"reminders" : @"todos";
        [self.menuPanel.web evaluateJavaScript:
            [NSString stringWithFormat:@"Panel.setView('%@')", view] completionHandler:nil];

    } else if ([action isEqualToString:@"remToggle"]) {
        [self.reminders setEnabled:![[self.reminders items][[value integerValue]] enabled]
                           atIndex:[value integerValue]];
        [self pushSnapshotToPanels];

    } else if ([action isEqualToString:@"remMinus"] || [action isEqualToString:@"remPlus"]) {
        NSInteger delta = [action isEqualToString:@"remPlus"] ? 5 : -5;
        [self.reminders adjustMinutes:delta atIndex:[value integerValue]];
        [self pushSnapshotToPanels];

    } else if ([action isEqualToString:@"todoToggle"]) {
        [self.checklist toggle:[value integerValue]];
        [self pushSnapshotToPanels];

    } else if ([action isEqualToString:@"todoAddPrompt"]) {
        [self promptAddTodo];

    } else if ([action isEqualToString:@"todoEdit"]) {
        [self promptEditTodo:[value integerValue]];

    } else if ([action isEqualToString:@"todoClear"]) {
        [self confirmClearTodos];

    } else if ([action isEqualToString:@"forceState"]) {
        [self.web evaluateJavaScript:
            [NSString stringWithFormat:@"App.force('%@')", value] completionHandler:nil];

    } else if ([action isEqualToString:@"closePanel"]) {
        [self.menuPanel hide];

    } else if ([action isEqualToString:@"back"]) {
        [self.menuPanel.web evaluateJavaScript:@"Panel.setView('menu')" completionHandler:nil];
    }

    [self refreshMenuChecks];
}

#pragma mark - 桌宠显隐 / 状态面板

- (void)setPetHidden:(BOOL)hidden {
    _petHidden = hidden;          // 注意：不能写 self.petHidden，会无限递归
    [[NSUserDefaults standardUserDefaults] setBool:hidden forKey:kHiddenKey];
    if (hidden) {
        [self.window orderOut:nil];
        // 面板从属于桌宠：一起收起，但记住"它之前是开着的"
        if (self.statusPanel.isShown) [self.statusPanel hide];
    } else {
        [self.window makeKeyAndOrderFront:nil];
        if ([[NSUserDefaults standardUserDefaults] boolForKey:kStatusOpenKey]) {
            [self showStatusPanel];
        }
    }
    [self.web evaluateJavaScript:[NSString stringWithFormat:@"App.show(%@)", hidden ? @"false" : @"true"]
               completionHandler:nil];
    [self refreshMenuChecks];
}

- (void)toggleStatusPanel {
    if (self.statusPanel.isShown) {
        [self.statusPanel hide];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kStatusOpenKey];
    } else {
        [self showStatusPanel];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kStatusOpenKey];
    }
    [self refreshMenuChecks];
}

- (void)showStatusPanel {
    [self pushSnapshotToPanels];
    [self.statusPanel showAtBottomRight];
}

- (void)refreshMenuChecks {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for (NSMenuItem *mi in self.statusItem.menu.itemArray) {
        if (mi.tag == 201) mi.enabled = !self.petHidden;
        if (mi.tag == 202) {
            BOOL hasAudio = NO;             // v2.0 还没有音频素材
            mi.enabled = hasAudio;
        }
        if (mi.tag == 203) mi.state = [d boolForKey:kPausedKey] ? NSControlStateValueOn : NSControlStateValueOff;
        if (mi.tag == 204) {
            mi.state = [self autostartEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
}

#pragma mark - 尺寸 / 暂停 / 自启

- (void)applySize:(CGFloat)newSize {
    if (newSize < 60) return;
    [[NSUserDefaults standardUserDefaults] setDouble:newSize forKey:kSizeKey];
    CGFloat total = newSize + kPad * 2;
    NSRect f = self.window.frame;
    f.origin.y += (NSHeight(f) - total);
    f.size = NSMakeSize(total, total);
    [self.window setFrame:f display:YES animate:YES];
    [self.web evaluateJavaScript:[NSString stringWithFormat:@"App.setSize(%f)", newSize]
               completionHandler:nil];
}

- (void)togglePause {
    [self.web evaluateJavaScript:@"App.togglePaused()" completionHandler:^(id v, NSError *e) {
        [[NSUserDefaults standardUserDefaults] setBool:[v boolValue] forKey:kPausedKey];
        [self refreshMenuChecks];
    }];
}

- (NSString *)launchAgentPath {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents"];
    return [dir stringByAppendingPathComponent:@"com.popohere.pet.plist"];
}

- (BOOL)autostartEnabled {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self launchAgentPath]];
}

- (void)toggleAutostart {
    NSString *path = [self launchAgentPath];
    NSFileManager *fm = [NSFileManager defaultManager];

    if ([fm fileExistsAtPath:path]) {
        [fm removeItemAtPath:path error:nil];
        [self refreshMenuChecks];
        return;
    }

    NSString *exe = [[NSBundle mainBundle] executablePath];
    NSDictionary *plist = @{
        @"Label": @"com.popohere.pet",
        @"ProgramArguments": @[exe],
        @"RunAtLoad": @YES,
        @"KeepAlive": @NO,
    };
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                             format:NSPropertyListXMLFormat_v1_0
                                                            options:0 error:nil];
    [data writeToFile:path atomically:YES];
    [self refreshMenuChecks];
}

- (void)openResources:(id)sender {
    NSURL *dir = [[[NSBundle mainBundle] resourceURL] URLByAppendingPathComponent:@"app" isDirectory:YES];
    [[NSWorkspace sharedWorkspace] openURL:dir];
}

#pragma mark - 待办编辑

- (void)promptAddTodo {
    if (self.checklist.items.count >= (NSUInteger)10) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"添加待办";
    alert.informativeText = @"最多 10 条，每条不超过 50 字。";
    [alert addButtonWithTitle:@"添加"];
    [alert addButtonWithTitle:@"取消"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    field.placeholderString = @"要做什么？";
    alert.accessoryView = field;
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [self.checklist add:field.stringValue];
        [self pushSnapshotToPanels];
    }
}

- (void)promptEditTodo:(NSInteger)index {
    NSArray *items = self.checklist.items;
    if (index < 0 || index >= (NSInteger)items.count) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"编辑待办";
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"删除"];
    [alert addButtonWithTitle:@"取消"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    field.stringValue = items[index][@"text"];
    alert.accessoryView = field;
    NSModalResponse r = [alert runModal];
    if (r == NSAlertFirstButtonReturn) {
        [self.checklist setText:field.stringValue atIndex:index];
    } else if (r == NSAlertSecondButtonReturn) {
        [self.checklist remove:index];
    }
    [self pushSnapshotToPanels];
}

- (void)confirmClearTodos {
    if (!self.checklist.items.count) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"清空全部待办？";
    alert.informativeText = @"这一步不能撤销。";
    [alert addButtonWithTitle:@"清空"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [self.checklist clear];
        [self pushSnapshotToPanels];
    }
}

#pragma mark - 面板数据

- (void)pushSnapshotToPanels {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSMutableArray *states = [NSMutableArray array];
    for (NSArray *pair in StateCatalog()) {
        [states addObject:@{ @"id": pair[0], @"cn": pair[1] }];
    }

    NSMutableDictionary *snap = [@{
        @"version": @(1),
        @"size": @([self petSize]),
        @"sound": @([d boolForKey:kSoundKey]),
        @"soundAvailable": @NO,
        @"paused": @([d boolForKey:kPausedKey]),
        @"autostart": @([self autostartEnabled]),
        @"petHidden": @(self.petHidden),
        @"statusOpen": @(self.statusPanel.isShown),
        @"states": states,
        @"reminders": [self.reminders asJSON],
        @"todos": [self.checklist items],
    } mutableCopy];

    // 版本号与实时状态要从包信息和 Web 里拿
    snap[@"version"] = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"2.0.0";
    [self.web evaluateJavaScript:@"JSON.stringify({state: App.state(), elapsed: +App.elapsed().toFixed(1)})"
               completionHandler:^(id result, NSError *error) {
        if ([result isKindOfClass:[NSString class]] && [(NSString *)result length]) {
            NSData *data = [(NSString *)result dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *live = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (live) [snap addEntriesFromDictionary:live];
        }
        [self.statusPanel update:snap];
        [self.menuPanel update:snap];
    }];
}

#pragma mark - 拖拽（宠物窗口 / 状态面板共用）

- (void)beginPress {
    [self startDragForWindow:self.window];
}

- (void)beginPanelDrag {
    [self startDragForWindow:self.statusPanel.window];
}

- (void)startDragForWindow:(NSWindow *)target {
    if (!target) return;
    self.pressing = YES;
    self.movedDuringPress = NO;
    self.dragTarget = target;
    self.pressMouse = [NSEvent mouseLocation];
    self.pressOrigin = target.frame.origin;
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
        if (e.type == NSEventTypeLeftMouseUp) [self endPress];
        else [self updateDrag];
        return e;
    }];
}

- (void)updateDrag {
    if (!self.pressing || !self.dragTarget) return;
    NSPoint mouse = [NSEvent mouseLocation];
    CGFloat dx = mouse.x - self.pressMouse.x;
    CGFloat dy = mouse.y - self.pressMouse.y;
    if (!self.movedDuringPress) {
        if (hypot(dx, dy) < kDragThreshold) return;
        self.movedDuringPress = YES;
    }
    [self.dragTarget setFrameOrigin:NSMakePoint(self.pressOrigin.x + dx, self.pressOrigin.y + dy)];
}

- (void)endPress {
    self.pressing = NO;
    if (self.dragMonitor) {
        [NSEvent removeMonitor:self.dragMonitor];
        self.dragMonitor = nil;
    }
    if (self.movedDuringPress) {
        self.movedDuringPress = NO;
        if (self.dragTarget == self.window) [self savePosition];
    }
    self.dragTarget = nil;
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
        [self.window setFrameOrigin:NSMakePoint(NSMinX(vis) + 30, NSMinY(vis) + 40)];
    }

    self.petHidden = [d boolForKey:kHiddenKey];
    if (!self.petHidden) [self.window makeKeyAndOrderFront:nil];

    if ([d boolForKey:kStatusOpenKey] && !self.petHidden) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self showStatusPanel]; });
    }
}

- (void)screenChanged:(NSNotification *)n {
    NSRect vis = [NSScreen mainScreen].visibleFrame;
    NSRect f = self.window.frame;
    f.origin.x = MAX(NSMinX(vis), MIN(f.origin.x, NSMaxX(vis) - NSWidth(f)));
    f.origin.y = MAX(NSMinY(vis), MIN(f.origin.y, NSMaxY(vis) - NSHeight(f)));
    [self.window setFrameOrigin:f.origin];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        PHDelegate *d = [PHDelegate new];
        app.delegate = d;
        [app run];
    }
    return 0;
}
