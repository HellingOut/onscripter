#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <stdlib.h>
#include <string.h>

// Game data layout:
//
//   Documents/ONS/<game name>/nscript.dat
//   Documents/ONS/<game name>/...
//
// A game left directly in Documents/ONS is still selectable as a legacy
// entry, so upgrading does not make an existing installation unplayable.

static BOOL directoryHasScript(NSString* directory)
{
    static NSString* const scripts[] = {
        @"0.txt", @"00.txt", @"nscript.dat",
        @"nscr_sec.dat", @"nscript.___", @"pscript.dat"
    };

    NSFileManager* fm = [NSFileManager defaultManager];
    for (unsigned i = 0; i < sizeof(scripts) / sizeof(scripts[0]); i++) {
        NSString* path = [directory stringByAppendingPathComponent:scripts[i]];
        if ([fm fileExistsAtPath:path]) return YES;
    }

    return NO;
}

@interface ONSGameSelector : UITableViewController
{
    NSString* rootPath;
    NSMutableArray* games;
    NSString* selectedPath;
    UIWindow* pickerWindow;
    volatile BOOL running;
}

- (id)initWithRootPath:(NSString*)path;
- (NSString*)selectGame;
- (void)reloadGames;

@end

@implementation ONSGameSelector

- (id)initWithRootPath:(NSString*)path
{
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        rootPath = [path copy];
        games = [[NSMutableArray alloc] init];
        selectedPath = nil;
        pickerWindow = nil;
        running = NO;
        [self reloadGames];
    }
    return self;
}

- (void)dealloc
{
    [rootPath release];
    [games release];
    [selectedPath release];
    [pickerWindow release];
    [super dealloc];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"Выбор игры";
    self.navigationItem.rightBarButtonItem =
        [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                       target:self
                                                       action:@selector(refresh:)] autorelease];

    UILabel* footer = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 64)];
    footer.backgroundColor = [UIColor clearColor];
    footer.textColor = [UIColor grayColor];
    footer.font = [UIFont systemFontOfSize:13];
    footer.textAlignment = NSTextAlignmentCenter;
    footer.numberOfLines = 2;
    footer.text = @"Каждая игра должна находиться в отдельной папке внутри Documents/ONS.";
    self.tableView.tableFooterView = footer;
    [footer release];
}

- (void)refresh:(id)sender
{
    [self reloadGames];
    [self.tableView reloadData];
}

- (void)reloadGames
{
    [games removeAllObjects];

    NSFileManager* fm = [NSFileManager defaultManager];
    NSArray* entries = [fm contentsOfDirectoryAtPath:rootPath error:NULL];
    NSMutableArray* folders = [NSMutableArray array];

    for (NSString* name in entries) {
        if ([name hasPrefix:@"."]) continue;

        NSString* path = [rootPath stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) continue;
        if (!directoryHasScript(path)) continue;

        [folders addObject:name];
    }

    [folders sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    for (NSString* name in folders) {
        NSString* path = [rootPath stringByAppendingPathComponent:name];
        [games addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                          name, @"title",
                          path, @"path",
                          @"Папка с игрой", @"detail",
                          nil]];
    }

    // Keep a game which is still directly in Documents/ONS usable.  It is
    // intentionally shown last, to encourage the folder layout.
    if (directoryHasScript(rootPath)) {
        [games addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                          @"ONS (корень)", @"title",
                          rootPath, @"path",
                          @"Игра в корне ONS — перенесите её в отдельную папку", @"detail",
                          nil]];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    return [games count];
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    static NSString* const cellIdentifier = @"ONSGameCell";

    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                       reuseIdentifier:cellIdentifier] autorelease];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    NSDictionary* game = [games objectAtIndex:indexPath.row];
    cell.textLabel.text = [game objectForKey:@"title"];
    cell.detailTextLabel.text = [game objectForKey:@"detail"];
    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary* game = [games objectAtIndex:indexPath.row];
    [selectedPath release];
    selectedPath = [[game objectForKey:@"path"] retain];
    running = NO;
}

- (NSString*)selectGame
{
    [self reloadGames];
    if ([games count] == 0) return nil;

    pickerWindow = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    UINavigationController* navigation =
        [[UINavigationController alloc] initWithRootViewController:self];
    pickerWindow.rootViewController = navigation;
    [navigation release];
    [pickerWindow makeKeyAndVisible];

    running = YES;
    while (running) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
    }

    pickerWindow.hidden = YES;
    [pickerWindow release];
    pickerWindow = nil;

    return selectedPath;
}

@end

extern "C" char* selectGameDirectory(const char* root)
{
    if (!root || !*root) return NULL;

    NSString* rootPath = [NSString stringWithUTF8String:root];
    if (!rootPath) return NULL;

    ONSGameSelector* selector = [[ONSGameSelector alloc] initWithRootPath:rootPath];
    NSString* result = [selector selectGame];

    char* path = NULL;
    if (result) path = strdup([result fileSystemRepresentation]);

    [selector release];
    return path;
}
