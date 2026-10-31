#import "PHAlert.h"

/** 把字符串变成 JS 字面量（去掉 JSON 数组的外壳）。中文/全角括号都靠它转义 */
static NSString *PHJSONString(NSString *text) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[text ?: @""] options:0 error:nil];
    NSString *array = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (array.length < 2) return @"\"\"";
    return [array substringWithRange:NSMakeRange(1, array.length - 2)];
}

@interface PHAlertController ()
@property (nonatomic, strong) PHPanelController *panel;
@property (nonatomic) NSInteger totalSeconds;
@property (nonatomic) NSInteger remaining;
@property (nonatomic, copy) NSString *baseText;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic) BOOL closing;
@end

@implementation PHAlertController

- (instancetype)initWithPanel:(PHPanelController *)panel seconds:(NSInteger)seconds {
    self = [super init];
    if (!self) return nil;
    _panel = panel;
    _totalSeconds = MAX(3, seconds);      // 太短会来不及看清
    __weak typeof(self) weakSelf = self;
    panel.onAction = ^(NSString *action, id value) {
        if ([action isEqualToString:@"alertConfirm"]) [weakSelf dismiss];
    };
    return self;
}

#pragma mark - 显示

- (void)showText:(NSString *)text {
    self.baseText = text ?: @"到时间了";
    self.remaining = self.totalSeconds;
    self.closing = NO;

    [self.panel setView:@"alert"];
    [self.panel showAtTopRight];          // 右上角、不抢焦点、压在最前面
    [self refreshText];
    [self startTimer];
}

- (void)refreshText {
    NSString *text = [NSString stringWithFormat:@"%@（%lds）", self.baseText, (long)self.remaining];
    // 文案里有中文和全角括号，走 JSON 转义最稳
    NSString *js = [NSString stringWithFormat:@"Panel && Panel.setAlert(%@)", PHJSONString(text)];
    [self.panel invokeJS:js];
}

#pragma mark - 计时

- (void)startTimer {
    [self.timer invalidate];
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES
                                                   block:^(NSTimer *t) { [weakSelf tick]; }];
}

- (void)tick {
    if (self.remaining <= 1) {            // 显示到 1s 后关闭，不会停在 0s
        [self dismiss];
        return;
    }
    self.remaining -= 1;
    [self refreshText];
}

#pragma mark - 关闭

- (void)dismiss {
    if (self.closing) return;
    self.closing = YES;
    [self.timer invalidate];
    self.timer = nil;
    [self.panel hide];
    if (self.onDismiss) self.onDismiss();
    self.closing = NO;
}

- (BOOL)isShowing { return self.panel.isShown; }

@end
