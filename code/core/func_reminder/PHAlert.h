//  PopoHere · 到点提醒弹窗
//
//  为什么单独做一个窗口：提醒必须在「桌宠被隐藏 / 没有音频素材 / 没有动画」时也能到达用户。
//  所以它不挂在宠物窗口上，而是屏幕右上角一个独立玻璃面板。
//
//  多条提醒**叠在同一个面板里**，各自倒计时、各自「确认」，用户先关哪条都行。
//  全部关完（或全部超时）面板才收起。

#import <Foundation/Foundation.h>
#import "PHPanel.h"

NS_ASSUME_NONNULL_BEGIN

@interface PHAlertController : NSObject

/** 最后一条也关掉时回调（此时面板已收起） */
@property (nonatomic, copy, nullable) void (^onEmpty)(void);

- (instancetype)initWithPanel:(PHPanelController *)panel seconds:(NSInteger)seconds;

/** 追加一条提醒（文案不含倒计时）；面板已开就直接叠上去 */
- (void)pushText:(NSString *)text;

/** 关掉某一条：点「确认」或倒计时归零都走这里 */
- (void)dismissIdentifier:(NSInteger)ident;

/** 全部关掉（退出时用） */
- (void)dismissAll;

- (BOOL)isShowing;
- (NSInteger)count;

@end

NS_ASSUME_NONNULL_END
