#import "PHChecklist.h"

@interface PHChecklist ()
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *list;
@property (nonatomic, copy) NSString *path;
@end

@implementation PHChecklist

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSString *base = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                          NSUserDomainMask, YES) firstObject];
    NSString *dir = [base stringByAppendingPathComponent:@"PopoHere"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    _path = [dir stringByAppendingPathComponent:@"checklist.json"];
    [self load];
    return self;
}

- (void)load {
    NSData *data = [NSData dataWithContentsOfFile:self.path];
    if (data) {
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([obj isKindOfClass:[NSArray class]]) {
            _list = [NSMutableArray array];
            for (NSDictionary *d in obj) {
                NSString *text = d[@"text"];
                if (![text isKindOfClass:[NSString class]] || !text.length) continue;
                [_list addObject:[@{ @"text": text, @"done": @([d[@"done"] boolValue]) } mutableCopy]];
            }
            return;
        }
    }
    _list = [NSMutableArray array];
}

- (void)save {
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.list options:0 error:nil];
    [data writeToFile:self.path atomically:YES];
}

- (NSArray<NSDictionary *> *)items { return self.list; }

- (NSInteger)undoneCount {
    NSInteger n = 0;
    for (NSDictionary *d in self.list) if (![d[@"done"] boolValue]) n++;
    return n;
}

- (BOOL)add:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return NO;
    if (self.list.count >= (NSUInteger)kMaxTodos) return NO;

    if (trimmed.length > (NSUInteger)kMaxTodoLength) {
        trimmed = [[trimmed substringToIndex:kMaxTodoLength] stringByAppendingString:@"…"];
    }
    [self.list addObject:[@{ @"text": trimmed, @"done": @NO } mutableCopy]];
    [self save];
    return YES;
}

- (void)toggle:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.list.count) return;
    NSMutableDictionary *d = self.list[index];
    d[@"done"] = @(![d[@"done"] boolValue]);
    [self save];
}

- (void)setText:(NSString *)text atIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.list.count) return;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return;
    if (trimmed.length > (NSUInteger)kMaxTodoLength) {
        trimmed = [[trimmed substringToIndex:kMaxTodoLength] stringByAppendingString:@"…"];
    }
    self.list[index][@"text"] = trimmed;
    [self save];
}

- (void)remove:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.list.count) return;
    [self.list removeObjectAtIndex:index];
    [self save];
}

- (void)clear {
    [self.list removeAllObjects];
    [self save];
}

@end
