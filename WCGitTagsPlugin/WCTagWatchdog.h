//
//  WCTagWatchdog.h
//  WCGitTagsPlugin
//
//  Created by Wojciech Czekalski on 28.04.2014.
//  Copyright (c) 2014 Wojciech Czekalski. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface WCTagWatchdog : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithGitDirectoryURL:(NSURL *)gitDirectoryURL watchBlock:(void (^)(void))watchBlock __attribute__((nonnull));

@property (nonatomic, strong, readonly) NSURL *gitDirectoryURL;
@property (nonatomic, copy, readonly) void (^watchblock)();

- (void)start;
- (void)stop;

@end
