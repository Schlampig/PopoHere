//  PopoHere · 到点提醒弹窗
//
//  为什么单独做一个窗口：提醒必须在「桌宠被隐藏 / 没有音频素材 / 没有动画」时也能到达用户。
//  所以它不挂在宠物窗口上，而是屏幕右上角一个独立玻璃面板，10 秒倒计时自动消失。
//
//  文案由调用方给（形如「到时间了，请去喝水！」），倒计时括号由本类每秒补上。

#import <Foundation/Foundation.h>
#import "PHPanel.h"

NS_ASSUME_NONNULL_BEGIN

@interface PHAlertController : NSObject

/** 一条提醒关闭后回调（用来播放排队中的下一条） */
@property (nonatomic, copy, nullable) void (^onDismiss)(void);

- (instancetype)initWithPanel:(PHPanelController *)panel seconds:(NSInteger)seconds;

/** 显示一条提醒；重复调用会重置倒计时 */
- (void)showText:(NSString *)text;

/** 用户点「确认」或倒计时归零，都走这里 */
- (void)dismiss;

- (BOOL)isShowing;

@end

NS_ASSUME_NONNULL_END
