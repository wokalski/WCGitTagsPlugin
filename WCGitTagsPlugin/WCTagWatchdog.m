//
//  WCTagWatchdog.m
//  WCGitTagsPlugin
//
//  Created by Wojciech Czekalski on 28.04.2014.
//  Copyright (c) 2014 Wojciech Czekalski. All rights reserved.
//

#import "WCTagWatchdog.h"
#import <CoreServices/CoreServices.h>

@interface WCTagWatchdog ()
@property (nonatomic, assign, readonly) FSEventStreamRef stream;
@end
@implementation WCTagWatchdog

- (instancetype)initWithGitDirectoryURL:(NSURL *)gitDirectoryURL watchBlock:(void (^)(void))watchBlock
{
    NSParameterAssert(gitDirectoryURL);
    NSParameterAssert(watchBlock);
    
    self = [super init];
    if (self) {
        _watchblock = watchBlock;
        _gitDirectoryURL = gitDirectoryURL;
        _stream = [self streamAtPath:[gitDirectoryURL.path stringByAppendingPathComponent:@"refs/tags"]];
    }
    return self;
}

- (void)dealloc {
    [self stop];
    FSEventStreamInvalidate(self.stream);
    FSEventStreamRelease(self.stream);
}

#pragma mark - 

- (void)stop {
    FSEventStreamStop(self.stream);
}

- (void)start {
    self.watchblock();
    FSEventStreamStart(self.stream);
}

- (FSEventStreamRef)streamAtPath:(NSString *)path
{
    FSEventStreamRef stream = NULL;
    
    NSAssert([[NSFileManager defaultManager] fileExistsAtPath:path], @"There's no file at path: %@, cannot read tags from this directory.", path);

    NSArray *paths = [[NSArray alloc] initWithObjects:path, nil];
    CFAbsoluteTime latency = .5; /* Latency in seconds */
    
    FSEventStreamContext context;
    context.version = 0;
    context.info = (__bridge void *)(self);
    context.retain = NULL;
    context.release = NULL;
    context.copyDescription = NULL;
    
    /* Create the stream, passing in a callback */
    stream = FSEventStreamCreate(NULL,
                                  &tagDirectoryChangeCallback,
                                  &context,
                                  (__bridge CFArrayRef)(paths),
                                  kFSEventStreamEventIdSinceNow, /* Or a previous event ID */
                                  latency,
                                  kFSEventStreamCreateFlagNone /* Flags explained in reference */
                                  );
    FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    return stream;
}

static void tagDirectoryChangeCallback(ConstFSEventStreamRef streamRef, void *clientCallBackInfo, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[]) {
    
    WCTagWatchdog *watchDog = (__bridge WCTagWatchdog *)clientCallBackInfo;
    if (watchDog.watchblock) {
        watchDog.watchblock();
    }
    
}

@end
