//  PopoHere · 定时提醒的实现
//
//  职责
//    1. 维护提醒项的集合，并在首次运行时写入默认的三条预置；
//    2. 以秒为单位推进计时，到点时把该条目返回给调用方；
//    3. 通过 NSUserDefaults 持久化，并兼容早期版本留下的字段。
//
//  实现要点
//    · 一轮最多返回一个到点项，同时到点的其余项在下一秒返回，
//      在弹窗侧呈现为多条并列；
//    · 间隔值统一收敛到「1 或 5 的倍数」，避免出现 1、6、11 这类错位数值；
//    · 一次性提醒触发后会自动关闭自身开关，间隔提醒则重新计时。
//
#import "PHReminder.h"

static NSString * const kStoreKey = @"PHReminders";
static const NSInteger kMinMinutes = 1;
static const NSInteger kMaxMinutes = 180;
/* 加减步长。最小档 1 单独存在，其余均为 5 的倍数：1 → 5 → 10 → 15 …
   若直接对当前值加 5，从最小档开始会得到 1、6、11、16 这类非整五值，
   因此递增必须落到下一个合法档位，而不是简单相加。 */
static const NSInteger kStepMinutes = 5;

/** 相邻的合法取值（保证 +5/-5 之后仍是 5 的倍数，且 1 和 5 之间是直接跳） */
static NSInteger PHStepMinutesFrom(NSInteger current, NSInteger delta) {
    if (delta > 0) {
        if (current < kStepMinutes) return kStepMinutes;
        return ((current / kStepMinutes) + 1) * kStepMinutes;
    }
    if (delta < 0) {
        if (current <= kStepMinutes) return kMinMinutes;
        return ((current - 1) / kStepMinutes) * kStepMinutes;
    }
    return current;
}

/* v2.0 第二轮改过命名：番茄钟 → 摸鱼。老数据要跟着迁移，否则面板里还留着旧名字。 */
static NSString *PHMigrateName(NSString *name) {
    if ([name isEqualToString:@"番茄钟"]) return @"摸鱼";
    return name;
}

/* 老数据没有 message：按名字补一句完整文案 */
static NSString *PHDefaultMessage(NSString *name) {
    if ([name isEqualToString:@"摸鱼"]) return @"摸鱼结束，接着干活~";
    if ([name isEqualToString:@"喝水"]) return @"到时间了，请去喝口水！";
    if ([name isEqualToString:@"久坐拉伸"]) return @"到时间了，请去拉伸一下！";
    return [NSString stringWithFormat:@"到时间了，请去%@！", name];
}

/** 把历史数据里"1、6、11"这类错位值吸到最近的 5 的倍数（1 保留） */
static NSInteger PHNormalizeMinutes(NSInteger m) {
    m = MAX(kMinMinutes, MIN(kMaxMinutes, m));
    if (m == kMinMinutes || m % kStepMinutes == 0) return m;
    NSInteger snapped = (NSInteger)((m / (double)kStepMinutes) + 0.5) * kStepMinutes;
    return MAX(kStepMinutes, MIN(kMaxMinutes, snapped));
}

@implementation PHReminder
@end

@interface PHReminderStore ()
@property (nonatomic, strong) NSMutableArray<PHReminder *> *list;
@property (nonatomic, strong) NSUserDefaults *defaults;
@end

@implementation PHReminderStore

- (instancetype)init {
    return [self initWithDefaults:[NSUserDefaults standardUserDefaults]];
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (!self) return nil;
    _defaults = defaults;
    [self load];
    return self;
}

- (void)loadDefaults {
    _list = [@[
        [self makeName:@"摸鱼" minutes:25 message:@"摸鱼结束，接着干活~"],
        [self makeName:@"喝水" minutes:45 message:@"到时间了，请去喝口水！"],
        [self makeName:@"久坐拉伸" minutes:60 message:@"到时间了，请去拉伸一下！"],
    ] mutableCopy];
}

- (PHReminder *)makeName:(NSString *)name minutes:(NSInteger)minutes message:(NSString *)message {
    PHReminder *r = [PHReminder new];
    r.name = name;
    r.message = message;
    r.minutes = minutes;
    r.enabled = NO;                 // 默认全关，不打扰
    r.repeat = NO;                  // 默认一次性
    r.remaining = minutes * 60;
    return r;
}

- (void)load {
    NSArray *raw = [self.defaults arrayForKey:kStoreKey];
    if (!raw.count) { [self loadDefaults]; return; }

    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *d in raw) {
        PHReminder *r = [PHReminder new];
        r.name = PHMigrateName(d[@"name"] ?: @"提醒");
        // 旧字段是 tip（短语），新字段是 message（整句）；两者都可能出现
        r.message = d[@"message"] ?: (d[@"tip"] ? [NSString stringWithFormat:@"到时间了，请去%@！", d[@"tip"]]
                                               : PHDefaultMessage(r.name));
        r.minutes = PHNormalizeMinutes([d[@"minutes"] integerValue]);
        r.enabled = [d[@"enabled"] boolValue];
        r.repeat = [d[@"repeat"] boolValue];
        r.remaining = r.minutes * 60;
        [list addObject:r];
    }
    _list = list;
}

- (void)save {
    NSMutableArray *raw = [NSMutableArray array];
    for (PHReminder *r in self.list) {
        [raw addObject:@{ @"name": r.name,
                          @"message": r.message ?: PHDefaultMessage(r.name),
                          @"minutes": @(r.minutes),
                          @"enabled": @(r.enabled),
                          @"repeat": @(r.repeat) }];
    }
    [self.defaults setObject:raw forKey:kStoreKey];
}

- (NSArray<PHReminder *> *)items { return self.list; }

- (NSInteger)runningCount {
    NSInteger n = 0;
    for (PHReminder *r in self.list) if (r.enabled) n++;
    return n;
}

- (void)setEnabled:(BOOL)enabled atIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.list.count) return;
    PHReminder *r = self.list[index];
    r.enabled = enabled;
    r.remaining = r.minutes * 60;   // 开关都重置计时，避免"刚开就响"
    [self save];
}

+ (NSInteger)minutesFrom:(NSInteger)current delta:(NSInteger)delta {
    return PHStepMinutesFrom(current, delta);
}

- (void)setMinutes:(NSInteger)minutes atIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.list.count) return;
    PHReminder *r = self.list[index];
    r.minutes = MAX(kMinMinutes, MIN(kMaxMinutes, minutes));
    r.remaining = r.minutes * 60;
    [self save];
}

- (void)setRepeat:(BOOL)repeat atIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.list.count) return;
    self.list[index].repeat = repeat;
    [self save];
}

- (void)adjustMinutes:(NSInteger)delta atIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.list.count) return;
    NSInteger next = PHStepMinutesFrom(self.list[index].minutes, delta);
    [self setMinutes:next atIndex:index];
}

- (PHReminder *)tick {
    PHReminder *due = nil;
    for (PHReminder *r in self.list) {
        if (!r.enabled) continue;
        r.remaining -= 1;
        if (r.remaining > 0) continue;

        due = r;                        // 一轮只报一个；同时到点的会在下一秒补上
        r.remaining = r.minutes * 60;
        if (!r.repeat) r.enabled = NO;  // 一次性：响过就关，下次不再提醒
        [self save];                    // enabled 变了必须落盘
        break;
    }
    return due;
}

- (NSArray<NSDictionary *> *)asJSON {
    NSMutableArray *out = [NSMutableArray array];
    for (PHReminder *r in self.list) {
        [out addObject:@{ @"name": r.name,
                          @"message": r.message ?: PHDefaultMessage(r.name),
                          @"minutes": @(r.minutes),
                          @"enabled": @(r.enabled),
                          @"repeat": @(r.repeat) }];
    }
    return out;
}

@end
