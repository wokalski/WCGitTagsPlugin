//
//  WCTagWatchdog.h
//  WCGitTagsPlugin
//
//  Created by Wojciech Czekalski on 28.04.2014.
//  Copyright (c) 2014 Wojciech Czekalski. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface WCTagWatchdog : NSObject

- (instancetype)initWithWatchBlock:(void (^)())watchBlock;

@property (nonatomic, strong) NSURL *gitDirectoryURL;
@property (nonatomic, copy) void (^watchblock)();

- (void)start;
- (void)stop;
- (void)invalidate;

@end
