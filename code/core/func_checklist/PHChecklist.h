//  PopoHere · 待办清单
//
//  极简 checklist：最多 10 条、每条 ≤50 个中文字、可勾选、可一键清空。
//  存在 ~/Library/Application Support/PopoHere/checklist.json。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

static const NSInteger kMaxTodos = 10;
static const NSInteger kMaxTodoLength = 50;

@interface PHChecklist : NSObject

- (NSArray<NSDictionary *> *)items;      // [{text, done}]
- (NSInteger)undoneCount;

/** 返回是否添加成功（超上限或空文本会失败） */
- (BOOL)add:(NSString *)text;
- (void)toggle:(NSInteger)index;
- (void)setText:(NSString *)text atIndex:(NSInteger)index;
- (void)remove:(NSInteger)index;
- (void)clear;

@end

NS_ASSUME_NONNULL_END
