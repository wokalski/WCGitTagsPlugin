//
//  GTTag+Time.h
//  WCGitTagsPlugin
//
//  Created by Wojciech Czekalski on 28.04.2014.
//  Copyright (c) 2014 Wojciech Czekalski. All rights reserved.
//

#import <ObjectiveGit/ObjectiveGit.h>

@interface GTTag (Time)
@property (nonatomic, readonly) NSDate *time;
@end