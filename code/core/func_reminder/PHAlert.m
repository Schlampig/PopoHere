//  PopoHere · 到点提醒的窗口编排
//
//  职责
//    维护当前正在展示的提醒条目，驱动每秒倒计时，处理「确认」与超时关闭，
//    并把条目列表推送给面板渲染。窗口本身由 PHPanel 提供（view = alert）。
//
//  实现要点
//    · 多条提醒共存：每条独立倒计时，全部关闭后窗口才收起；
//    · 窗口高度由页面根据卡片数量计算后回报，外壳只负责贴住右上角；
//    · 不抢占键盘焦点，用户在其他应用中输入时不会被打断。


#import "PHAlert.h"

#pragma mark - 一条提醒

@interface PHAlertEntry : NSObject
@property (nonatomic) NSInteger ident;
@property (nonatomic, copy) NSString *text;
@property (nonatomic) NSInteger remaining;
@end

@implementation PHAlertEntry
@end

#pragma mark -

@interface PHAlertController ()
@property (nonatomic, strong) PHPanelController *panel;
@property (nonatomic) NSInteger totalSeconds;
@property (nonatomic) NSInteger nextIdent;
@property (nonatomic, strong) NSMutableArray<PHAlertEntry *> *entries;
@property (nonatomic, strong, nullable) NSTimer *timer;
@end

@implementation PHAlertController

- (instancetype)initWithPanel:(PHPanelController *)panel seconds:(NSInteger)seconds {
    self = [super init];
    if (!self) return nil;
    _panel = panel;
    _totalSeconds = MAX(3, seconds);      // 太短会来不及看清
    _entries = [NSMutableArray array];
    _nextIdent = 1;
    __weak typeof(self) weakSelf = self;
    panel.onAction = ^(NSString *action, id value) {
        if ([action isEqualToString:@"alertConfirm"]) {
            [weakSelf dismissIdentifier:[value integerValue]];
        }
    };
    return self;
}

#pragma mark - 追加

- (void)pushText:(NSString *)text {
    PHAlertEntry *e = [PHAlertEntry new];
    e.ident = self.nextIdent++;
    e.text = text ?: @"到时间了";
    e.remaining = self.totalSeconds;
    [self.entries addObject:e];

    if (!self.panel.isShown) {
        [self.panel setView:@"alert"];
        [self.panel showAtTopRight];      // 右上角、不抢焦点、压在最前面
    }
    [self refresh];
    [self startTimer];
}

- (void)refresh {
    NSMutableArray *list = [NSMutableArray array];
    for (PHAlertEntry *e in self.entries) {
        [list addObject:@{ @"id": @(e.ident), @"text": e.text, @"sec": @(e.remaining) }];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:list options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [self.panel invokeJS:[NSString stringWithFormat:@"Panel && Panel.setAlerts(%@)", json]];
}

#pragma mark - 计时

- (void)startTimer {
    if (self.timer) return;
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES
                                                   block:^(NSTimer *t) { [weakSelf tick]; }];
}

- (void)tick {
    NSMutableArray<PHAlertEntry *> *alive = [NSMutableArray array];
    for (PHAlertEntry *e in self.entries) {
        e.remaining -= 1;
        if (e.remaining > 0) [alive addObject:e];   // 归零的直接丢掉
    }
    self.entries = alive;

    if (!self.entries.count) {
        [self closePanel];
        return;
    }
    [self refresh];
}

#pragma mark - 关闭

- (void)dismissIdentifier:(NSInteger)ident {
    NSMutableArray<PHAlertEntry *> *alive = [NSMutableArray array];
    for (PHAlertEntry *e in self.entries) {
        if (e.ident != ident) [alive addObject:e];
    }
    self.entries = alive;
    if (!self.entries.count) {
        [self closePanel];
    } else {
        [self refresh];                              // 剩下的继续各自倒计时
    }
}

- (void)dismissAll {
    [self.entries removeAllObjects];
    [self closePanel];
}

- (void)closePanel {
    [self.timer invalidate];
    self.timer = nil;
    [self.panel hide];
    if (self.onEmpty) self.onEmpty();
}

- (BOOL)isShowing { return self.panel.isShown; }
- (NSInteger)count { return self.entries.count; }

@end
