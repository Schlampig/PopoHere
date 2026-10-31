//  PopoHere · 玻璃面板窗口
//
//  一个可复用的透明浮窗，里面装 WKWebView 渲染 panel.html。
//  两个实例：
//    - 右键菜单（menu）：贴着光标弹出，失焦即收
//    - 状态面板（status）：常驻右下角，可拖动，失焦不消失
//
//  真正的毛玻璃来自 NSVisualEffectView（blendingMode = behindWindow），
//  CSS 的 backdrop-filter 在透明窗口里采样不到桌面，只负责压暗和描边。

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PHPanelController : NSObject <WKScriptMessageHandler, WKNavigationDelegate>

@property (nonatomic, strong, readonly) NSWindow *window;
@property (nonatomic, strong, readonly) WKWebView *web;
/** 面板当前显示哪个视图（"menu" / "reminders" / "todos" / "status"）。
    给它赋值会同步通知页面切页，所以不要绕过它直接调 JS。 */
@property (nonatomic, copy) NSString *view;
@property (nonatomic) BOOL dismissOnResignKey;
/** 状态面板：尺寸变化后仍贴住屏幕右下角 */
@property (nonatomic) BOOL anchorRight;
/** 到点提醒：尺寸变化后仍贴住屏幕右上角 */
@property (nonatomic) BOOL anchorTopRight;

/** 面板里点了某个动作 */
@property (nonatomic, copy) void (^onAction)(NSString *action, id _Nullable value);
/** 面板真正收起时（菜单需要让状态机回到 idle） */
@property (nonatomic, copy) void (^onHide)(void);
/** 面板真正显示后（菜单需要让状态机进入 menu） */
@property (nonatomic, copy) void (^onShow)(void);
/** 开始拖动面板（状态面板的标题栏） */
@property (nonatomic, copy) void (^onDragStart)(void);

- (instancetype)initWithView:(NSString *)view;

- (void)showAtPoint:(NSPoint)screenPoint;   // AppKit 屏幕坐标，面板左上角对齐该点
- (void)showAtBottomRight;
- (void)showAtTopRight;                     // 屏幕右上角，不抢焦点
/** 给面板页面发一条 JS（页面侧只暴露 Panel.* 这几个 API） */
- (void)invokeJS:(NSString *)js;
- (void)hide;
- (BOOL)isShown;

/** 把状态快照推给面板（settings / reminders / todos / state…） */
- (void)update:(NSDictionary *)snapshot;

@end

NS_ASSUME_NONNULL_END
