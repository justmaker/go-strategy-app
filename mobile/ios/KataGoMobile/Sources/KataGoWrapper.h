#import <Foundation/Foundation.h>

@interface KataGoWrapper : NSObject

+ (BOOL)startWithConfig:(NSString *)configPath model:(NSString *)modelPath;
+ (void)writeToProcess:(NSString *)data;
+ (NSString *)readFromProcess;
+ (void)stop;

@end
