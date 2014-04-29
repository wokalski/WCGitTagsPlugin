//
//  WCGitTagsPlugin.m
//  WCGitTagsPlugin
//
//  Created by Wojciech Czekalski on 25.03.2014.
//    Copyright (c) 2014 Wojciech Czekalski. All rights reserved.
//

#import "WCGitTagsPlugin.h"
#import <ObjectiveGit/ObjectiveGit.h>
#import "WCTagWatchdog.h"
#import "DSUnixTaskSubProcessManager.h"

static WCGitTagsPlugin *sharedPlugin;

@interface WCGitTagsPlugin()
@property (nonatomic, strong) NSBundle *bundle;
@property (nonatomic, strong) NSWindow *addTagWindow;
@property (nonatomic, strong) NSWindow *tagsWindow;

@property (nonatomic, readonly) BOOL isGitRepository;
@property (nonatomic, strong) GTRepository *repository;

@property (nonatomic, strong) WCTagWatchdog *watchDog;

@property (nonatomic, weak) NSMenuItem *tagsItem;
@property (nonatomic, weak) NSMenuItem *refreshStatusItem;

@property (nonatomic, getter = isBeingPresented) BOOL beingPresented;

- (NSURL *)currentDirectoryPath;
- (void)loadInterface;

- (void)removeSelectedTags;

- (void)syncTags;
- (void)pushTags;
- (void)removeTag:(GTTag *)tag;

- (void)presentAddTagsPanel;

- (void)setSegmentedControlButtonsEnabled:(BOOL)enabled;

@end

@implementation WCGitTagsPlugin

#pragma mark - Life cycle

+ (void)pluginDidLoad:(NSBundle *)plugin
{
    static id sharedPlugin = nil;
    static dispatch_once_t onceToken;
    NSString *currentApplicationName = [[NSBundle mainBundle] infoDictionary][@"CFBundleName"];
    if ([currentApplicationName isEqual:@"Xcode"]) {
        dispatch_once(&onceToken, ^{
            sharedPlugin = [[self alloc] initWithBundle:plugin];
        });
    }
}

- (id)initWithBundle:(NSBundle *)plugin
{
    if (self = [super init]) {
        // reference to plugin's bundle, for resource acccess
        self.bundle = plugin;
        
        NSMenuItem *menuItem = [[NSApp mainMenu] itemWithTitle:@"Source Control"];
        if (menuItem) {
            
            NSMenuItem *actionMenuItem = [[NSMenuItem alloc] initWithTitle:@"Tags..." action:@selector(presentTagsModal:) keyEquivalent:@""];
            [actionMenuItem setTarget:self];
            
            self.refreshStatusItem = [[menuItem submenu] itemWithTitle:@"Refresh Status"];
            [self.refreshStatusItem addObserver:self forKeyPath:@"enabled" options:0 context:NULL];
            
            NSInteger indexOfRefreshStatusItem = [[menuItem submenu] indexOfItem:self.refreshStatusItem];
            if (indexOfRefreshStatusItem == -1) {
                [[menuItem submenu] addItem:[NSMenuItem separatorItem]];
                [[menuItem submenu] addItem:actionMenuItem];
            } else {
                [[menuItem submenu] insertItem:actionMenuItem atIndex:indexOfRefreshStatusItem];
            }
            
            self.tagsItem = actionMenuItem;
            [self.tagsItem setEnabled:self.refreshStatusItem.isEnabled];
            
            WCTagWatchdog *watchDog = [[WCTagWatchdog alloc] initWithWatchBlock:^{
                [self willChangeValueForKey:@"tags"];
                [self didChangeValueForKey:@"tags"];
            }];
            watchDog.gitDirectoryURL = self.repository.gitDirectoryURL;
            self.watchDog = watchDog;
            
            self.beingPresented = NO;
        }
    }
    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
        [self.tagsItem setEnabled:self.refreshStatusItem.isEnabled];
}

- (void)dealloc
{
    [self.refreshStatusItem removeObserver:self forKeyPath:@"enabled"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.watchDog invalidate];
}

#pragma mark - UI 
#pragma mark Loading

- (void)loadInterface {
    NSArray *topLevelObjects = nil;
    [self.bundle loadNibNamed:@"View" owner:self topLevelObjects:&topLevelObjects];
    for (id object in topLevelObjects) {
        // Defensive way of doing things.
        if ([object isKindOfClass:[NSWindow class]]) {
            NSWindow *window = (NSWindow *)object;
            if ([window.identifier isEqualToString:@"Add tag window"]) {
                self.addTagWindow = window;
            } else if ([window.identifier isEqualToString:@"Tags window"]) {
                self.tagsWindow = window;
            }
        }
    }
}

#pragma mark Presentation

- (void)presentTagsModal:(id)sender {
    
    if (self.isBeingPresented) {
        return;
    }
    
    if (self.isGitRepository) {
        if (!self.tagsWindow) {
            [self loadInterface];
        }
        
        self.beingPresented = YES;
        [[NSApp keyWindow] beginSheet:self.tagsWindow completionHandler:^(NSModalResponse returnCode) {
            [self.tagsWindow orderOut:self];
            self.repository = nil;
            self.beingPresented = NO;
        }];
        
        self.watchDog.gitDirectoryURL = self.repository.gitDirectoryURL;
        [self.watchDog start];
        [self syncTags];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSWarningAlertStyle;
        alert.messageText = @"This repository is not a git repository.";
        [alert beginSheetModalForWindow:[NSApp keyWindow] completionHandler:nil];
    }
}

- (void)presentAddTagsPanel {
    [self.tagsWindow beginSheet:self.addTagWindow completionHandler:^(NSModalResponse returnCode) {
        [self.tagsWindow orderOut:self];
    }];
}

#pragma mark IBActions

- (IBAction)addTag:(id)sender {
    
    GTReference *headReference = [self.repository headReferenceWithError:nil];
    if (headReference) {
        
        GTObject *target = [headReference resolvedTarget];
        
        if (self.lightweightTagButton.state == NSOffState) {
            [self.repository createTagNamed:[self.tagNameField stringValue] target:target tagger:[self.repository userSignatureForNow] message:[self.tagMessageField stringValue] error:nil];
        } else {
            [self.repository createLightweightTagNamed:[self.tagNameField stringValue] target:target error:nil];
        }
        
        [self pushTags];
    }
    
    [self.addTagWindow close];
    [self.tagsWindow endSheet:self.addTagWindow];
}

- (IBAction)cancelAddTagPanel:(id)sender {
    [self.addTagWindow close];
    [self.tagsWindow endSheet:self.addTagWindow];
}

- (IBAction)segmentedControlClicked:(NSSegmentedControl *)sender {
    if (sender.selectedSegment == 0) {
        // Show add tag Panel
        [self presentAddTagsPanel];
    } else if (sender.selectedSegment == 1) {
        [self removeSelectedTags];
    } else if (sender.selectedSegment == 3) {
        [self refreshTags:nil];
    }
}

- (IBAction)refreshTags:(id)sender {
    [self syncTags];
}

- (IBAction)lightweightTagClicked:(NSButton *)sender {
    if (sender.state == NSOnState) {
        [self.tagMessageField setEnabled:NO];
        self.addTagButton.enabled = ([self.tagNameField stringValue].length > 0);
    } else if (sender.state == NSOffState) {
        [self.tagMessageField setEnabled:YES];
        self.addTagButton.enabled = ([self.tagNameField stringValue].length > 0 && [self.tagMessageField stringValue].length > 0);
    }
}

- (IBAction)endSheet:(id)sender {
    [self.watchDog invalidate];
    NSWindow *sheetWindow = self.tagsWindow.sheetParent;
    [self.tagsWindow close];
    [sheetWindow endSheet:self.tagsWindow];
}

#pragma mark Other

- (void)setSegmentedControlButtonsEnabled:(BOOL)enabled {
    [self.segmentedControl setEnabled:enabled forSegment:0];
    [self.segmentedControl setEnabled:enabled forSegment:1];
    [self.segmentedControl setEnabled:enabled forSegment:3];
}

#pragma mark - Delegates
#pragma mark NSTextField
- (void)controlTextDidChange:(NSNotification *)obj {
    
    if (self.lightweightTagButton.state == NSOnState) {
        self.addTagButton.enabled = ([self.tagNameField stringValue].length > 0);
    } else {
        self.addTagButton.enabled = ([self.tagNameField stringValue].length > 0 && [self.tagMessageField stringValue].length > 0);
    }
}

#pragma mark NSTableView

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *tableView = notification.object;
    if (tableView.selectedRowIndexes.count > 0) {
        [self.segmentedControl setEnabled:YES forSegment:1];
    } else {
        [self.segmentedControl setEnabled:NO forSegment:1];
    }
}

#pragma mark - Git
#pragma mark  libgit2

- (void)removeSelectedTags {
    NSArray *selectedTags = [self.tags objectsAtIndexes:self.tableView.selectedRowIndexes];
    
    for (GTTag *tag in selectedTags) {
        int success = git_tag_delete(self.repository.git_repository, [[tag name] UTF8String]);
        if (success == GIT_EINVALIDSPEC) {
            NSLog(@"ERROR: Could not remove tag: %@", tag);
        } else {
            [self removeTag:tag];
        }
    }
}

#pragma mark  Command line

- (void)syncTags {
    [self setSegmentedControlButtonsEnabled:NO];
    DSUnixTask *gitTask = [self gitTask];
    [gitTask setArguments:@[@"fetch", @"--tags"]];
    [gitTask setTerminationHandler:^(DSUnixTask *task) {
        [self pushTags];
        [self setSegmentedControlButtonsEnabled:YES];
    }];
    [gitTask launch];
}

- (void)pushTags {
    DSUnixTask *gitTask = [self gitTask];
    [gitTask setArguments:@[@"push", @"--tags"]];
    [gitTask launch];
}

- (void)removeTag:(GTTag *)tag {
    DSUnixTask *gitTask = [self gitTask];
    [gitTask setArguments:@[@"push", @"origin", [NSString stringWithFormat:@":refs/tags/%@", tag.name]]];
    [gitTask launch];
}

- (DSUnixTask *)gitTask {
    DSUnixTask *gitTask = [DSUnixTaskSubProcessManager shellTask];
    gitTask.workingDirectory = [[self.repository.gitDirectoryURL path] stringByDeletingLastPathComponent];
    [gitTask setCommand:@"git"];
    return gitTask;
}

#pragma mark - Getters

- (NSURL *)currentDirectoryPath
{
    for (NSDocument *document in [NSApp orderedDocuments]) {
        @try {
            //        _workspace(IDEWorkspace) -> representingFilePath(DVTFilePath) -> relativePathOnVolume(NSString)
            NSURL *workspaceDirectoryURL = [[[document valueForKeyPath:@"_workspace.representingFilePath.fileURL"] URLByDeletingLastPathComponent] filePathURL];
            
            if(workspaceDirectoryURL) {
                return workspaceDirectoryURL;
            }
        }
        @catch (NSException *exception) {
            NSLog(@"WCGitTagsPlugin Xcode plugin: Raised an exception while asking for the documents '_workspace.representingFilePath.relativePathOnVolume' key path: %@", exception);
        }
    }
    return nil;
}

- (NSArray *)tags {
    NSError *error = nil;
    _tags = [self.repository allTagsWithError:&error];
    if (error) {
        NSLog(@"Could not fetch tags: %@",error);
    }
    return _tags;
}

- (GTRepository *)repository {
    if (!_repository) {
        NSError *error = nil;
        _repository = [GTRepository repositoryWithURL:[self currentDirectoryPath] error:&error];
        if (error) {
            NSLog(@"This repo is not a git repo: %@", error);
        }
    }
    return _repository;
}

- (BOOL)isGitRepository {
    if (self.repository) {
        return YES;
    }
    return NO;
}

@end