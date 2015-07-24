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

- (NSURL *)currentDirectoryPath;
- (void)loadInterface;

- (void)removeSelectedTags;

- (void)syncTags;
- (void)pushTags;
- (void)removeRemoteTag:(GTTag *)tag;

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

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidFinishLaunching:)
                                                     name:NSApplicationDidFinishLaunchingNotification
                                                   object:nil];
    }
    return self;
}

-(void)applicationDidFinishLaunching:(NSNotification *)sender
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationDidFinishLaunchingNotification object:nil];
    
    NSMenuItem *menuItem = [self sourceControlItem];
    
    if (menuItem) {
        
        NSMenu *sourceControlMenu = [menuItem submenu];
        
        NSMenuItem *refreshStatusItem = [sourceControlMenu itemWithTitle:@"Refresh Status"];
        
        NSMenuItem *tagsMenuItem = [self tagsMenuItemWithTarget:self selector:@selector(presentTagsModal:) enabled:refreshStatusItem.enabled];
        
        [self insertMenuItem:tagsMenuItem inMenu:sourceControlMenu atIndex:[self indexOfItem:refreshStatusItem inMenu:sourceControlMenu]];

        [refreshStatusItem addObserver:self forKeyPath:@"enabled" options:0 context:NULL];
        
        self.tagsItem = tagsMenuItem;
        self.refreshStatusItem = refreshStatusItem;
    } else {
        NSLog(@"Initialization of WCGitTagsPlugin failed");
    }
}

- (NSInteger)indexOfItem:(NSMenuItem *)item inMenu:(NSMenu *)menu
{
    return item != nil ? [menu indexOfItem:item] : -1;
}

- (void)insertMenuItem:(NSMenuItem *)menuItem inMenu:(NSMenu *)parentMenu atIndex:(NSInteger)index
{
    if (index == -1) {
        [parentMenu addItem:[NSMenuItem separatorItem]];
        [parentMenu addItem:menuItem];
    } else {
        [parentMenu insertItem:menuItem atIndex:index];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
        [self.tagsItem setEnabled:self.refreshStatusItem.isEnabled];
}

- (void)dealloc
{
    [self.refreshStatusItem removeObserver:self forKeyPath:@"enabled"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI 
#pragma mark Loading

- (void)loadInterface {
    self.tagsWindow = [self topLevelWindowInNibNamed:@"TagsWindow" owner:self];
    self.addTagWindow = [self topLevelWindowInNibNamed:@"AddTagWindow" owner:self];
}

- (NSWindow *)topLevelWindowInNibNamed:(NSString *)nibName owner:(id)owner
{
    NSArray *topLevelObjects = nil;
    [self.bundle loadNibNamed:nibName owner:owner topLevelObjects:&topLevelObjects];
    for (id object in topLevelObjects) {
        if ([object isKindOfClass:[NSWindow class]]) {
            return object;
        }
    }
    return nil;
}


#pragma mark Presentation

- (void)presentTagsModal:(id)sender {
    
    if (self.tagsWindow.screen) {
        return;
    }
    
    GTRepository *repo = [self repositoryAtURL:[self currentDirectoryPath]];
    
    if (repo) {
        self.repository = repo;
        if (!self.tagsWindow) {
            [self loadInterface];
        }
        if (self.tagsWindow) {
            [[NSApp keyWindow] beginSheet:self.tagsWindow completionHandler:^(NSModalResponse returnCode) {
                [self.tagsWindow orderOut:self];
                self.repository = nil;
            }];
            
            self.watchDog = [self watchDogInRepositoryAtURL:repo.gitDirectoryURL];
            [self.watchDog start];
            [self syncTags];
        }
    } else { // Should never happen since Tags button is disabled
        [[self notGitRepositoryAlert] beginSheetModalForWindow:[NSApp keyWindow] completionHandler:nil];
    }
}

- (void)presentAddTagsPanel {
    [self.tagsWindow beginSheet:self.addTagWindow completionHandler:nil];
}

#pragma mark IBActions

- (IBAction)addTag:(id)sender {
    
    GTReference *headReference = [self.repository headReferenceWithError:nil];
    if (headReference) {
        
        GTObject *target = [headReference resolvedTarget];
        NSError *error = nil;
        
        if (self.lightweightTagButton.state == NSOffState) {
            if (![self.repository createTagNamed:[self.tagNameField stringValue] target:target tagger:[self.repository userSignatureForNow] message:[self.tagMessageField stringValue] error:&error]) {
                //Put a breakpoint here if debugging
            }
        } else {
            if (![self.repository createLightweightTagNamed:[self.tagNameField stringValue] target:target error:&error]) {
                //Put a breakpoint here if debugging
            }
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
    self.watchDog = nil;
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
            [self removeRemoteTag:tag];
        }
    }
    
    if([self.tags count] == 0) {
         [self.segmentedControl setEnabled:NO forSegment:1];
    }
}

#pragma mark  Command line

- (void)syncTags {
    [self.activityIndicator startAnimation:self];
    [self setSegmentedControlButtonsEnabled:NO];
    DSUnixTask *gitTask = [self gitTask];
    [gitTask setArguments:@[@"fetch", @"--tags"]];
    [gitTask setTerminationHandler:^(DSUnixTask *task) {
        [self pushTags];
        [_activityIndicator stopAnimation:self];
        [self.segmentedControl setEnabled:YES forSegment:0];
        [self.segmentedControl setEnabled:YES forSegment:3];
        if([self.tableView selectedRow] != -1) {
            [self.segmentedControl setEnabled:YES forSegment:1];
        }
    }];
    [gitTask launch];
}

- (void)pushTags {
    DSUnixTask *gitTask = [self gitTask];
    [gitTask setArguments:@[@"push", @"--tags"]];
    [gitTask launch];
}

- (void)removeRemoteTag:(GTTag *)tag {
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
            
            if (workspaceDirectoryURL) {
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
    NSArray *tags = [self.repository allTagsWithError:&error];
    
    if (error) {
        NSLog(@"Could not fetch tags: %@", error);
    }
    return tags;
}

#pragma mark -

- (WCTagWatchdog *)watchDogInRepositoryAtURL:(NSURL *)url
{
    typeof(self) __weak weakSelf = self;
    return [[WCTagWatchdog alloc] initWithGitDirectoryURL:url watchBlock:^{
        [weakSelf willChangeValueForKey:@"tags"];
        [weakSelf didChangeValueForKey:@"tags"]; // Blame it on Cocoa bindings
    }];
}

- (GTRepository *)repositoryAtURL:(NSURL *)URL {
    NSError *error = nil;
    GTRepository *repository = [GTRepository repositoryWithURL:URL error:&error];
    
    if (error) {
        NSLog(@"This repo is not a git repo: %@", error);
    }
    
    return repository;
}

- (NSMenuItem *)sourceControlItem
{
    return [[NSApp mainMenu] itemWithTitle:@"Source Control"];
}

- (NSMenuItem *)tagsMenuItemWithTarget:(id)target selector:(SEL)selector enabled:(BOOL)enabled
{
    NSMenuItem *actionMenuItem = [[NSMenuItem alloc] initWithTitle:@"Tags..." action:selector keyEquivalent:@""];
    [actionMenuItem setTarget:target];
    actionMenuItem.enabled = enabled;
    
    return actionMenuItem;
}

- (NSAlert *)notGitRepositoryAlert
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSWarningAlertStyle;
    alert.messageText = @"This repository is not a git repository.";
    return alert;
}

@end