//
//  WCGitTagsPlugin.h
//  WCGitTagsPlugin
//
//  Created by Wojciech Czekalski on 25.03.2014.
//  Copyright (c) 2014 Wojciech Czekalski. All rights reserved.
//

#import <AppKit/AppKit.h>

@interface WCGitTagsPlugin : NSObject <NSTableViewDelegate, NSTextFieldDelegate>

@property (nonatomic) IBOutlet NSArray *tags;

- (IBAction)endSheet:(id)sender;
- (IBAction)addTag:(id)sender;
- (IBAction)cancelAddTagPanel:(id)sender;
- (IBAction)segmentedControlClicked:(NSSegmentedControl *)sender;
- (IBAction)refreshTags:(id)sender;
- (IBAction)lightweightTagClicked:(id)sender;


@property (weak) IBOutlet NSButton *lightweightTagButton;
@property (weak) IBOutlet NSTextField *tagNameField;
@property (weak) IBOutlet NSTextField *tagMessageField;
@property (weak) IBOutlet NSSegmentedControl *segmentedControl;
@property (weak) IBOutlet NSTableView *tableView;
@property (weak) IBOutlet NSButton *addTagButton;
@property (weak) IBOutlet NSProgressIndicator *activityIndicator;

@end