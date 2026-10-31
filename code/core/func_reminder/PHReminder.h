//  PopoHere · 定时提醒
//
//  番茄钟 / 喝水 / 久坐，本质都是"到点叫你一声"，合并成一个可配置的提醒器。
//  状态存在 NSUserDefaults，每秒 tick 一次，到点时由外壳弹气泡。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PHReminder : NSObject
@property (nonatomic, copy) NSString *name;
/** 到点时弹窗里的完整句子（不含倒计时）。名字是名词时直接拼句子会别扭，所以单独存一条文案 */
@property (nonatomic, copy) NSString *message;
/** YES = 间隔提醒（循环到用户自己关掉）；NO = 一次性（响过就自动关闭） */
@property (nonatomic) BOOL repeat;
@property (nonatomic) NSInteger minutes;
@property (nonatomic) BOOL enabled;
@property (nonatomic) NSInteger remaining;   // 秒
@end

@interface PHReminderStore : NSObject

/** 默认用 standardUserDefaults；测试可传一个独立 suite，避免污染真实配置 */
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

- (NSArray<PHReminder *> *)items;
- (NSInteger)runningCount;

/** 纯计算：从 current 走一步 delta 后的合法值（不碰存储，方便测） */
+ (NSInteger)minutesFrom:(NSInteger)current delta:(NSInteger)delta;

- (void)setEnabled:(BOOL)enabled atIndex:(NSInteger)index;
- (void)setMinutes:(NSInteger)minutes atIndex:(NSInteger)index;
- (void)setRepeat:(BOOL)repeat atIndex:(NSInteger)index;
- (void)adjustMinutes:(NSInteger)delta atIndex:(NSInteger)index;

/** 推进 1 秒；返回本轮到期的提醒项（没有则 nil） */
- (nullable PHReminder *)tick;
/** 供面板渲染的数组 */
- (NSArray<NSDictionary *> *)asJSON;

@end

NS_ASSUME_NONNULL_END
