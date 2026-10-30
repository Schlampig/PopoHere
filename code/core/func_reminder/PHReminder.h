//  PopoHere · 定时提醒
//
//  番茄钟 / 喝水 / 久坐，本质都是"到点叫你一声"，合并成一个可配置的提醒器。
//  状态存在 NSUserDefaults，每秒 tick 一次，到点时由外壳弹气泡。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PHReminder : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) NSInteger minutes;
@property (nonatomic) BOOL enabled;
@property (nonatomic) NSInteger remaining;   // 秒
@end

@interface PHReminderStore : NSObject

- (NSArray<PHReminder *> *)items;
- (NSInteger)runningCount;

- (void)setEnabled:(BOOL)enabled atIndex:(NSInteger)index;
- (void)setMinutes:(NSInteger)minutes atIndex:(NSInteger)index;
- (void)adjustMinutes:(NSInteger)delta atIndex:(NSInteger)index;

/** 推进 1 秒；返回本轮到期的提醒名（没有则 nil） */
- (nullable NSString *)tick;
/** 供面板渲染的数组 */
- (NSArray<NSDictionary *> *)asJSON;

@end

NS_ASSUME_NONNULL_END
