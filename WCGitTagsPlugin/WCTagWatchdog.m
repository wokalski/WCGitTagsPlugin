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
@property (nonatomic, assign) FSEventStreamRef stream;
static void tagDirectoryChangeCallback(ConstFSEventStreamRef streamRef, void *clientCallBackInfo, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[]);
@end
@implementation WCTagWatchdog

- (instancetype)initWithWatchBlock:(void (^)())watchBlock {
    self = [self init];
    if (self) {
        self.watchblock = watchBlock;
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.stream = NULL;
    }
    return self;
}

- (void)stop {
    FSEventStreamStop(self.stream);
}

- (void)start {
    self.watchblock();
    if (self.stream) {
        FSEventStreamStart(self.stream);
    }
}

- (void)invalidate {
    [self stop];
    FSEventStreamInvalidate(self.stream);
    FSEventStreamRelease(self.stream);
    self.stream = NULL;
}

- (FSEventStreamRef)stream {
    if (_stream == NULL) {
        NSString *path = [self.gitDirectoryURL.path stringByAppendingPathComponent:@"refs/tags"];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            NSArray *paths = [[NSArray alloc] initWithObjects:path, nil];
            CFAbsoluteTime latency = .5; /* Latency in seconds */
            
            FSEventStreamContext context;
            context.version = 0;
            context.info = (__bridge void *)(self);
            context.retain = NULL;
            context.release = NULL;
            context.copyDescription = NULL;
            
            /* Create the stream, passing in a callback */
            FSEventStreamRef stream = FSEventStreamCreate(NULL,
                                          &tagDirectoryChangeCallback,
                                          &context,
                                          (__bridge CFArrayRef)(paths),
                                          kFSEventStreamEventIdSinceNow, /* Or a previous event ID */
                                          latency,
                                          kFSEventStreamCreateFlagNone /* Flags explained in reference */
                                          );
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
            
            _stream = stream;
        }
    }
    return _stream;
}

- (void)dealloc {
    [self invalidate];
}

static void tagDirectoryChangeCallback(ConstFSEventStreamRef streamRef, void *clientCallBackInfo, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[]) {
    WCTagWatchdog *watchDog = (__bridge WCTagWatchdog *)clientCallBackInfo;
    watchDog.watchblock();
}

@end
