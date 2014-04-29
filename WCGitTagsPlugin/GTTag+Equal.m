//
//  GTTag+Equal.m
//  WCGitTagsPlugin
//
//  Created by Wojciech Czekalski on 28.04.2014.
//  Copyright (c) 2014 Wojciech Czekalski. All rights reserved.
//

#import "GTTag+Equal.h"

@implementation GTTag (Equal)

- (BOOL)isEqual:(id)object {
    if ([object isKindOfClass:[self class]]) {
        GTTag *tag = (GTTag *)object;
        return [tag.name isEqualToString:self.name];
    }
    return NO;
}

@end
