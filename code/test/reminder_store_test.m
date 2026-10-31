/* 定时提醒的存储与计时语义测试
 *
 *   clang -fobjc-arc -O2 -framework Foundation \
 *     -I code/core/func_reminder \
 *     code/test/reminder_store_test.m code/core/func_reminder/PHReminder.m \
 *     -o /tmp/remtest && /tmp/remtest
 *
 * 为什么不并进 Node 测试：这段逻辑在 Objective-C 里（持久化 + 秒级计时），
 * 用 JS 重写一遍测等于测了个赝品。这里直接跑真实现。
 *
 * 注意：会写一个叫 popo-remtest 的偏好域，跑完自己删掉，不碰 PopoHere 的真实配置。
 */
#import <Foundation/Foundation.h>
#import "PHReminder.h"

static int gPass = 0, gFail = 0;

static void check(const char *label, long got, long want) {
    if (got == want) {
        gPass++;
    } else {
        gFail++;
        printf("FAIL %s: got %ld, want %ld\n", label, got, want);
    }
}

static void checkStr(const char *label, NSString *got, NSString *want) {
    BOOL same = (got == want) || [got isEqualToString:want];
    if (same) {
        gPass++;
    } else {
        gFail++;
        printf("FAIL %s: got %s, want %s\n", label,
               got.UTF8String ?: "(nil)", want.UTF8String ?: "(nil)");
    }
}

/* 每次运行用独立的 suite：NSUserDefaults 会把值缓存在进程里，
   同一个域反复 remove 不一定真的清空（第一版测试就因此时好时坏）。 */
static NSString *gSuite;
static NSUserDefaults *gDefaults;

static void setupDefaults(void) {
    gSuite = [NSString stringWithFormat:@"popo-remtest-%d", getpid()];
    gDefaults = [[NSUserDefaults alloc] initWithSuiteName:gSuite];
}

/** 按秒推进，返回每次触发时的秒数 */
static NSString *fireTimes(PHReminderStore *store, int seconds) {
    NSMutableString *out = [NSMutableString string];
    for (int i = 0; i < seconds; i++) {
        if ([store tick]) [out appendFormat:@"%d ", i + 1];
    }
    return out.length ? out : @"";
}

static void reset(void) {
    [gDefaults removePersistentDomainForName:gSuite];
    [gDefaults synchronize];
}

int main(void) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        setupDefaults();

        /* ---- 默认值 ---- */
        PHReminderStore *s = [[PHReminderStore alloc] initWithDefaults:gDefaults];
        check("默认 3 条", (long)s.items.count, 3);
        checkStr("第一条叫摸鱼", s.items[0].name, @"摸鱼");
        checkStr("摸鱼文案", s.items[0].message, @"摸鱼结束，接着干活~");
        check("默认一次性", s.items[0].repeat, 0);
        check("默认关闭", s.items[0].enabled, 0);

        /* ---- 一次性：响一次就自动关 ---- */
        [s setMinutes:1 atIndex:0];
        [s setRepeat:NO atIndex:0];
        [s setEnabled:YES atIndex:0];
        checkStr("一次性只响 60s 一次", fireTimes(s, 240), @"60 ");
        check("响完自动关闭", s.items[0].enabled, 0);
        checkStr("关掉后不再响", fireTimes(s, 120), @"");

        /* ---- 间隔：每 60 秒一次，一直运行 ---- */
        [s setRepeat:YES atIndex:0];
        [s setEnabled:YES atIndex:0];
        checkStr("间隔每 60s 响", fireTimes(s, 240), @"60 120 180 240 ");
        check("间隔模式保持开启", s.items[0].enabled, 1);

        /* ---- 时长阶梯：1 → 5 → 10 …，不会出现 6/11 ---- */
        long v = 1;
        NSMutableString *ladder = [NSMutableString string];
        for (int i = 0; i < 4; i++) {
            v = [PHReminderStore minutesFrom:v delta:5];
            [ladder appendFormat:@"%ld ", v];
        }
        checkStr("上升阶梯", ladder, @"5 10 15 20 ");
        NSMutableString *back = [NSMutableString string];
        for (int i = 0; i < 4; i++) {
            v = [PHReminderStore minutesFrom:v delta:-5];
            [back appendFormat:@"%ld ", v];
        }
        checkStr("下降阶梯回到 1", back, @"15 10 5 1 ");

        /* ---- 老数据迁移：番茄钟 → 摸鱼，tip → message ---- */
        reset();
        NSArray *legacy = @[ @{ @"name": @"番茄钟", @"tip": @"专注工作",
                                @"minutes": @26, @"enabled": @YES } ];
        [gDefaults setObject:legacy forKey:@"PHReminders"];
        [gDefaults synchronize];
        PHReminderStore *m = [[PHReminderStore alloc] initWithDefaults:gDefaults];
        checkStr("名字迁移", m.items[0].name, @"摸鱼");
        checkStr("文案迁移", m.items[0].message, @"到时间了，请去专注工作！");
        check("时长吸附到 5 的倍数", m.items[0].minutes, 25);
        check("保留开启状态", m.items[0].enabled, 1);

        reset();
        printf("\n通过 %d / 失败 %d\n", gPass, gFail);
    }
    return gFail ? 1 : 0;
}
