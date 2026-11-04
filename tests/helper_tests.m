// Run on macOS. All filesystem fixtures live in a unique temporary directory.
// Process inspection is deterministic; launchctl is a local fixture executable.
#define main voidy_helper_main
#define proc_listallpids TestListPIDs
#define proc_pidpath TestPIDPath
#define proc_listpidspath TestPathUsers
#define chown TestChown
#include "../voidyhelper/main.m"
#undef main
#include <assert.h>
#include <utime.h>

static NSString *processPath;
static BOOL processListFails, pathInUse;
int TestListPIDs(void *buffer, int size) {
    if (processListFails) return -1;
    if (buffer && size >= (int)sizeof(pid_t)) ((pid_t *)buffer)[0] = 12345;
    return 1;
}
int TestPIDPath(int pid, void *buffer, uint32_t size) {
    const char *path = (processPath ?: @"/usr/bin/test-process").fileSystemRepresentation;
    strlcpy(buffer, path, size);
    return (int)strlen(path);
}
int TestPathUsers(uint32_t type, uint32_t info, const char *path, uint32_t flags, void *buffer, int size) {
    return pathInUse ? sizeof(pid_t) : 0;
}
int TestChown(const char *path, uid_t uid, gid_t gid) { return 0; }

static void Write(NSString *path, NSString *text, BOOL old) {
    assert([[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                                   withIntermediateDirectories:YES attributes:nil error:nil]);
    assert([text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    if (old) {
        struct utimbuf times = {time(NULL) - 3 * 86400, time(NULL) - 3 * 86400};
        assert(utime(path.fileSystemRepresentation, &times) == 0);
    }
}

static NSSet *Entries(PTarget *target) {
    NSMutableSet *entries = [NSMutableSet set];
    CollectEntries(target, [NSMutableSet set], ^(NSString *path, NSString *label) { [entries addObject:path]; });
    return entries;
}

static void TestFiles(NSString *root) {
    gJBRoot = root;
    NSString *cache = JB(@"/var/cache/Tést-缓存");
    NSString *old = [cache stringByAppendingPathComponent:@"nested/old.bin"];
    NSString *fresh = [cache stringByAppendingPathComponent:@"nested/new.bin"];
    Write(old, @"old cache", YES);
    Write(fresh, @"new cache", NO);
    Write([cache stringByAppendingPathComponent:@"cache.db"], @"db", YES);
    Write([cache stringByAppendingPathComponent:@"cache.db-wal"], @"wal", YES);
    Write([cache stringByAppendingPathComponent:@"data.leveldb/00001.ldb"], @"db", YES);
    NSString *outside = [root stringByAppendingPathComponent:@"Documents/keep.txt"];
    Write(outside, @"must survive", YES);
    assert(symlink(outside.fileSystemRepresentation, [cache stringByAppendingPathComponent:@"link"].fileSystemRepresentation) == 0);
    assert(symlink(outside.stringByDeletingLastPathComponent.fileSystemRepresentation,
                   [cache stringByAppendingPathComponent:@"linked-directory"].fileSystemRepresentation) == 0);
    assert(mkfifo([cache stringByAppendingPathComponent:@"pipe"].fileSystemRepresentation, 0600) == 0);
    // An old directory's mtime must not make its recent child eligible.
    struct utimbuf times = {time(NULL) - 3 * 86400, time(NULL) - 3 * 86400};
    utime(old.stringByDeletingLastPathComponent.fileSystemRepresentation, &times);
    PTarget *target = TAge(cache, @"test", PTargetContents, 86400);
    target.preserveDatabases = YES;
    assert([Entries(target) isEqualToSet:[NSSet setWithObject:RealPath(old)]]);
    CollectEntries(target, [NSMutableSet set], ^(NSString *path, NSString *label) {
        struct stat st;
        assert(lstat(path.fileSystemRepresentation, &st) == 0);
        assert(UnlinkRegularFile(path, &st, 86400));
    });
    assert(Exists(fresh) && Exists(outside) && Exists(cache) && Exists(old.stringByDeletingLastPathComponent));
    assert(Entries(T([cache stringByAppendingPathComponent:@"link"], @"", PTargetSelf)).count == 0);
    assert(Entries(T([cache stringByAppendingPathComponent:@"linked-directory"], @"", PTargetContents)).count == 0);
    assert(!SafeTargetPath([cache stringByAppendingPathComponent:@"../Documents"]));

    Write([cache stringByAppendingPathComponent:@"allowed/a"], @"a", YES);
    Write([cache stringByAppendingPathComponent:@"denied/b"], @"b", YES);
    PTarget *filtered = TFilter(cache, @"", ^BOOL(NSString *name) { return [name isEqualToString:@"allowed"]; });
    assert(Entries(filtered).count == 1);
    PTarget *logs = T(cache, @"", PTargetFiles);
    logs.skipDirs = [NSSet setWithObject:@"allowed"];
    assert(![Entries(logs) containsObject:RealPath([cache stringByAppendingPathComponent:@"allowed/a"])]);

    pathInUse = YES;
    assert(FileIsInUse(fresh));
    pathInUse = NO;
    assert(!FileIsInUse(fresh));
    assert(IsDeletableUserPath(RealPath(cache)));
    assert(CmdDelete([NSMutableArray arrayWithObject:cache]) == 0);
    assert(Exists(cache) && Exists(fresh));

    NSString *victim = [cache stringByAppendingPathComponent:@"race/keep.txt"];
    Write(victim, @"original", YES);
    struct stat original;
    assert(lstat(victim.fileSystemRepresentation, &original) == 0);
    NSString *canonicalVictim = RealPath(victim);
    assert([[NSFileManager defaultManager] moveItemAtPath:victim.stringByDeletingLastPathComponent
                                                toPath:[cache stringByAppendingPathComponent:@"parked"] error:nil]);
    assert(symlink(outside.stringByDeletingLastPathComponent.fileSystemRepresentation,
                   victim.stringByDeletingLastPathComponent.fileSystemRepresentation) == 0);
    assert(!UnlinkRegularFile(canonicalVictim, &original, 86400));
    assert(Exists(outside));
}

static void TestProcesses(NSString *root) {
    NSString *app = [root stringByAppendingPathComponent:@"Example.app"];
    NSString *extension = [app stringByAppendingPathComponent:@"PlugIns/Widget.appex"];
    Write([app stringByAppendingPathComponent:@"Info.plist"], @"", NO);
    Write([extension stringByAppendingPathComponent:@"Info.plist"], @"", NO);
    [@{@"CFBundleIdentifier": @"com.example.app"} writeToFile:[app stringByAppendingPathComponent:@"Info.plist"] atomically:YES];
    [@{@"CFBundleIdentifier": @"com.example.widget"} writeToFile:[extension stringByAppendingPathComponent:@"Info.plist"] atomically:YES];
    processPath = [extension stringByAppendingPathComponent:@"Widget"];
    NSSet *running = RunningClients();
    assert([running containsObject:@"com.example.app"] && [running containsObject:@"com.example.widget"]);
    processListFails = YES;
    assert(RunningClients() == nil);
    assert(CategoryIsBusy(@"app_caches", RunningClients()));
    processListFails = NO;
    processPath = nil;
    assert(CategoryIsBusy(@"pkg_cache", [NSSet setWithObject:@"dpkg"]));
    assert(CategoryIsBusy(@"safari_cache", [NSSet setWithObject:@"com.apple.WebKit.Networking"]));
    assert(!CategoryIsBusy(@"app_caches", [NSSet set]));
    assert(TargetsForCategory(@"safari_cache", [NSSet setWithObject:@"com.apple.mobilesafari"]).count == 0);
    for (PTarget *target in TargetsForCategory(@"pkg_cache", [NSSet setWithObject:@"com.tigisoftware.Filza"]))
        assert(![target.owner isEqualToString:@"com.tigisoftware.Filza"]);
}

static void TestSchedule(NSString *root) {
    gJBRoot = [root stringByAppendingPathComponent:@"jb"];
    gSelfPath = @"/bin/echo";
    NSString *launchctl = JB(@"/usr/bin/launchctl");
    Write(launchctl, @"#!/bin/sh\nbase=${0%/*}\ncase \"$1\" in\nprint) test -f \"$base/loaded\";;\nbootout) /bin/rm -f \"$base/loaded\";;\nenable) exit 0;;\nbootstrap) if test -f \"$base/fail-once\"; then /bin/rm \"$base/fail-once\"; exit 5; fi; /usr/bin/touch \"$base/loaded\";;\n*) exit 1;;\nesac\n", NO);
    assert(chmod(launchctl.fileSystemRepresentation, 0755) == 0);
    assert(CmdSchedule([@[@"set", @"24", @"--exclude", @"com.example.app", @"app_caches"] mutableCopy]) == 0);
    assert(ScheduleLoaded(launchctl));
    NSDictionary *previous = [NSDictionary dictionaryWithContentsOfFile:SchedulePlistPath()];
    for (NSArray *invalid in @[@[@"set", @"0", @"logs"], @[@"set", @"oops", @"logs"], @[@"set", @"169", @"logs"],
                              @[@"set", @"24", @"keyboard"], @[@"set", @"24", @"invalid"], @[@"invalid"]]) {
        assert(CmdSchedule([invalid mutableCopy]) != 0);
        assert([previous isEqual:[NSDictionary dictionaryWithContentsOfFile:SchedulePlistPath()]]);
        assert(ScheduleLoaded(launchctl));
    }
    Write(JB(@"/usr/bin/fail-once"), @"fail", NO);
    assert(CmdSchedule([@[@"set", @"6", @"logs"] mutableCopy]) != 0);
    assert([previous isEqual:[NSDictionary dictionaryWithContentsOfFile:SchedulePlistPath()]]);
    assert(ScheduleLoaded(launchctl));
    assert(CmdSchedule([@[@"exclusions", @"--exclude", @"com.example.new"] mutableCopy]) == 0);
    assert([EffectiveExclusions([NSSet setWithObject:@"old"], YES) isEqualToSet:[NSSet setWithObject:@"com.example.new"]]);
    assert(CmdSchedule([@[@"exclusions"] mutableCopy]) == 0);
    assert(EffectiveExclusions([NSSet setWithObject:@"old"], YES).count == 0);
    assert(CmdClean([@[@"keyboard"] mutableCopy], YES) != 0);
    assert(CmdSchedule([@[@"off"] mutableCopy]) == 0);
    assert(!ScheduleLoaded(launchctl) && !Exists(SchedulePlistPath()));
    Write(JB(@"/usr/bin/fail-once"), @"fail", NO);
    assert(CmdSchedule([@[@"set", @"6", @"logs"] mutableCopy]) != 0);
    assert(!ScheduleLoaded(launchctl) && !Exists(SchedulePlistPath()));
}

static void TestClean(NSString *root) {
    gJBRoot = [root stringByAppendingPathComponent:@"clean-jb"];
    NSString *file = JB(@"/var/lib/apt/lists/example_Packages");
    NSString *partial = JB(@"/var/lib/apt/lists/partial/download");
    NSString *lock = JB(@"/var/lib/apt/lists/lock");
    Write(file, @"cached list", YES);
    Write(partial, @"incomplete", YES);
    Write(lock, @"lock", YES);
    processListFails = YES;
    assert(CmdClean([@[@"apt_lists"] mutableCopy], YES) == 0 && Exists(file));
    processListFails = NO;
    processPath = @"/usr/bin/dpkg";
    assert(CmdClean([@[@"apt_lists"] mutableCopy], YES) == 0 && Exists(file));
    processPath = nil;
    pathInUse = YES;
    assert(CmdClean([@[@"apt_lists"] mutableCopy], NO) == 0 && Exists(file));
    pathInUse = NO;
    assert(CmdClean([@[@"apt_lists", @"--dry-run"] mutableCopy], NO) == 0 && Exists(file));
    assert(CmdClean([@[@"apt_lists"] mutableCopy], YES) == 0 && !Exists(file));
    assert(Exists(partial) && Exists(lock) && Exists(file.stringByDeletingLastPathComponent));
}

int main(void) {
    @autoreleasepool {
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        TestFiles(root);
        TestProcesses(root);
        TestSchedule(root);
        TestClean(root);
        assert([[NSFileManager defaultManager] removeItemAtPath:root error:nil]);
        puts("All Voidy helper regression tests passed.");
    }
    return 0;
}
