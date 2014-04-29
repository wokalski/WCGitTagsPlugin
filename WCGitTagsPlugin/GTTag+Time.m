//
//  GTTag+Time.m
//  WCGitTagsPlugin
//
//  Created by Wojciech Czekalski on 28.04.2014.
//  Copyright (c) 2014 Wojciech Czekalski. All rights reserved.
//

#import "GTTag+Time.h"

@implementation GTTag (Time)

- (NSDate *)time {
    return self.tagger.time;
}

@end