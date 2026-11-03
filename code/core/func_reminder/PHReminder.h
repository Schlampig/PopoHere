//  PopoHere · 定时提醒
//
//  职责
//    维护提醒项（名称、文案、间隔、开关、单次/间隔模式），按秒推进计时，
//    到点时把该项交给外壳，由 PHAlert 负责弹窗表现。
//
//  计时语义
//    每 tick 一秒钟；一轮最多返回一个到点项，同时到点的项在下一秒补上，
//    因此在弹窗中会呈现为多条并列。
//    间隔取值恒为 1 或 5 的倍数，避免出现 1、6、11 这类错位数值。

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
