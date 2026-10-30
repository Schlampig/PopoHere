#import "PHReminder.h"

static NSString * const kStoreKey = @"PHReminders";
static const NSInteger kMinMinutes = 1;
static const NSInteger kMaxMinutes = 180;

@implementation PHReminder
@end

@interface PHReminderStore ()
@property (nonatomic, strong) NSMutableArray<PHReminder *> *list;
@end

@implementation PHReminderStore

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    [self load];
    return self;
}

- (void)defaults {
    _list = [@[
        [self makeName:@"番茄钟" minutes:25],
        [self makeName:@"喝水" minutes:45],
        [self makeName:@"久坐拉伸" minutes:60],
    ] mutableCopy];
}

- (PHReminder *)makeName:(NSString *)name minutes:(NSInteger)minutes {
    PHReminder *r = [PHReminder new];
    r.name = name;
    r.minutes = minutes;
    r.enabled = NO;                 // 默认全关，不打扰
    r.remaining = minutes * 60;
    return r;
}

- (void)load {
    NSArray *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:kStoreKey];
    if (!raw.count) { [self defaults]; return; }

    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *d in raw) {
        PHReminder *r = [PHReminder new];
        r.name = d[@"name"] ?: @"提醒";
        r.minutes = MAX(kMinMinutes, MIN(kMaxMinutes, [d[@"minutes"] integerValue]));
        r.enabled = [d[@"enabled"] boolValue];
        r.remaining = r.enabled ? r.minutes * 60 : r.minutes * 60;
        [list addObject:r];
    }
    _list = list;
}

- (void)save {
    NSMutableArray *raw = [NSMutableArray array];
    for (PHReminder *r in self.list) {
        [raw addObject:@{ @"name": r.name,
                          @"minutes": @(r.minutes),
                          @"enabled": @(r.enabled) }];
    }
    [[NSUserDefaults standardUserDefaults] setObject:raw forKey:kStoreKey];
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

- (void)adjustMinutes:(NSInteger)delta atIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.list.count) return;
    PHReminder *r = self.list[index];
    r.minutes = MAX(kMinMinutes, MIN(kMaxMinutes, r.minutes + delta));
    r.remaining = r.minutes * 60;
    [self save];
}

- (NSString *)tick {
    NSString *due = nil;
    for (PHReminder *r in self.list) {
        if (!r.enabled) continue;
        r.remaining -= 1;
        if (r.remaining <= 0) {
            due = r.name;               // 一轮只报一个，避免同时轰炸
            r.remaining = r.minutes * 60;
            break;
        }
    }
    return due;
}

- (NSArray<NSDictionary *> *)asJSON {
    NSMutableArray *out = [NSMutableArray array];
    for (PHReminder *r in self.list) {
        [out addObject:@{ @"name": r.name,
                          @"minutes": @(r.minutes),
                          @"enabled": @(r.enabled) }];
    }
    return out;
}

@end
