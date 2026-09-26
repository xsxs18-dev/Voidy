// voidyhelper – privileged backend for Voidy.
//
// Runs as root (spawned by the app with the root persona, or via its setuid
// bit) and speaks JSON on stdout. Works on rootless and roothide: the
// jailbreak root is derived from the helper's own location at runtime, so
// no path is hard-coded to /var/jb.

#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <fts.h>
#include <spawn.h>
#include <signal.h>
#include <unistd.h>
#include <limits.h>
#include <mach-o/dyld.h>

extern char **environ;
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

#define HELPER_SUFFIX   @"/usr/libexec/voidyhelper"
#define APP_BUNDLE_NAME @"Voidy.app"
#define SCHEDULE_LABEL  @"com.xsxs18.voidy.autoclean"
#define MOBILE_UID      501

static NSString *gJBRoot = @"";
static NSString *gSelfPath = nil;

#pragma mark - Output

static void Out(id obj) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!data) data = [@"{\"error\":\"serialization failed\"}" dataUsingEncoding:NSUTF8StringEncoding];
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static int Fail(NSString *message) {
    Out(@{ @"error": message ?: @"unknown error" });
    return 1;
}

static int OK(NSString *message) {
    Out(@{ @"ok": @YES, @"message": message ?: @"" });
    return 0;
}

#pragma mark - Paths

static NSString *JB(NSString *path) {
    if (gJBRoot.length == 0) return path;
    return [gJBRoot stringByAppendingPathComponent:path];
}

static NSString *RealPath(NSString *path) {
    char buf[PATH_MAX];
    if (realpath(path.fileSystemRepresentation, buf)) return @(buf);
    return path;
}

static BOOL Exists(NSString *path) {
    struct stat st;
    return lstat(path.fileSystemRepresentation, &st) == 0;
}

static NSString *FirstExisting(NSArray<NSString *> *paths) {
    for (NSString *p in paths) if (access(p.fileSystemRepresentation, X_OK) == 0) return p;
    return nil;
}

static void DetectPaths(void) {
    char buf[PATH_MAX];
    uint32_t size = sizeof(buf);
    if (_NSGetExecutablePath(buf, &size) == 0) {
        gSelfPath = RealPath(@(buf));
        if ([gSelfPath hasSuffix:HELPER_SUFFIX]) {
            gJBRoot = [gSelfPath substringToIndex:gSelfPath.length - HELPER_SUFFIX.length];
            return;
        }
    }
    gJBRoot = Exists(@"/var/jb") ? RealPath(@"/var/jb") : @"";
}

static NSString *Scheme(void) {
    if ([gJBRoot containsString:@".jbroot-"]) return @"roothide";
    return gJBRoot.length ? @"rootless" : @"rootful";
}

#pragma mark - Caller check

// Only root (launchd, dpkg, persona-spawned app) or the installed Voidy app may use us.
static BOOL CallerAllowed(void) {
    if (getuid() == 0) return YES;
    char path[4096] = {0};
    if (proc_pidpath(getppid(), path, sizeof(path)) <= 0) return NO;
    NSString *parent = RealPath(@(path));
    NSString *appDir = [RealPath(JB(@"/Applications")) stringByAppendingPathComponent:APP_BUNDLE_NAME];
    return [parent hasPrefix:[appDir stringByAppendingString:@"/"]];
}

#pragma mark - Processes

static int Run(NSArray<NSString *> *argv, NSString **output) {
    if (argv.count == 0 || access([argv[0] fileSystemRepresentation], X_OK) != 0) return -1;

    int fds[2];
    if (pipe(fds) != 0) return -1;

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, fds[0]);
    posix_spawn_file_actions_addclose(&actions, fds[1]);

    NSUInteger n = argv.count;
    char **cargv = calloc(n + 1, sizeof(char *));
    for (NSUInteger i = 0; i < n; i++) cargv[i] = strdup(argv[i].UTF8String);

    NSString *pathEnv = [NSString stringWithFormat:@"PATH=%@:%@:%@:%@:/usr/bin:/bin:/usr/sbin:/sbin",
                         JB(@"/usr/bin"), JB(@"/bin"), JB(@"/usr/sbin"), JB(@"/sbin")];
    char *cenv[] = { strdup(pathEnv.UTF8String), strdup("DEBIAN_FRONTEND=noninteractive"),
                     strdup("LANG=C"), NULL };

    pid_t pid = 0;
    int rc = posix_spawn(&pid, cargv[0], &actions, NULL, cargv, cenv);
    posix_spawn_file_actions_destroy(&actions);
    close(fds[1]);
    for (NSUInteger i = 0; i < n; i++) free(cargv[i]);
    free(cargv);
    for (int i = 0; cenv[i]; i++) free(cenv[i]);

    if (rc != 0) { close(fds[0]); return -1; }

    NSMutableData *data = [NSMutableData data];
    char buf[4096];
    ssize_t r;
    while ((r = read(fds[0], buf, sizeof(buf))) > 0) [data appendBytes:buf length:(NSUInteger)r];
    close(fds[0]);

    int status = 0;
    waitpid(pid, &status, 0);
    if (output) *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static NSString *Tool(NSString *name) {
    return FirstExisting(@[ JB([@"/usr/bin" stringByAppendingPathComponent:name]),
                            JB([@"/bin" stringByAppendingPathComponent:name]),
                            JB([@"/usr/sbin" stringByAppendingPathComponent:name]),
                            JB([@"/sbin" stringByAppendingPathComponent:name]),
                            [@"/usr/bin" stringByAppendingPathComponent:name],
                            [@"/bin" stringByAppendingPathComponent:name],
                            [@"/sbin" stringByAppendingPathComponent:name] ]);
}

static void KillProcess(NSString *name) {
    NSString *killall = Tool(@"killall");
    if (killall) Run(@[ killall, @"-9", name ], NULL);
}

#pragma mark - Measuring & removing

static uint64_t Allocated(const struct stat *st) {
    return (uint64_t)st->st_blocks * 512ULL;
}

static void Measure(NSString *path, uint64_t *bytes, uint64_t *files) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return;
    if (!S_ISDIR(st.st_mode)) {
        *bytes += Allocated(&st);
        *files += 1;
        return;
    }
    char *paths[] = { (char *)path.fileSystemRepresentation, NULL };
    FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
    if (!fts) return;
    FTSENT *e;
    while ((e = fts_read(fts))) {
        switch (e->fts_info) {
            case FTS_F: case FTS_SL: case FTS_SLNONE: case FTS_DEFAULT:
                *bytes += Allocated(e->fts_statp);
                *files += 1;
                break;
            default: break;
        }
    }
    fts_close(fts);
}

static BOOL Remove(NSString *path) {
    return [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

static void EnsureMobileDir(NSString *dir) {
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    chown(dir.fileSystemRepresentation, MOBILE_UID, MOBILE_UID);
}

#pragma mark - Containers

static NSDictionary<NSString *, NSString *> *AppContainers(void) {
    static NSDictionary *cache;
    if (cache) return cache;
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    NSString *root = @"/var/mobile/Containers/Data/Application";
    for (NSString *uuid in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil]) {
        NSString *dir = [root stringByAppendingPathComponent:uuid];
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:
                              [dir stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
        NSString *identifier = meta[@"MCMMetadataIdentifier"];
        if ([identifier isKindOfClass:[NSString class]]) map[identifier] = dir;
    }
    cache = map;
    return cache;
}

static NSString *ContainerOf(NSString *bundleID) {
    return AppContainers()[bundleID];
}

#pragma mark - Targets

typedef NS_ENUM(int, PTargetMode) {
    PTargetContents = 0,   // children of a directory
    PTargetSelf     = 1,   // the path itself
    PTargetFiles    = 2,   // regular files anywhere below a directory
};

@interface PTarget : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *label;
@property (nonatomic) PTargetMode mode;
@property (nonatomic) NSTimeInterval minAge;
@property (nonatomic, copy) BOOL (^filter)(NSString *name);
@property (nonatomic, copy) NSString *(^labeler)(NSString *name);
@property (nonatomic, copy) NSSet<NSString *> *skipDirs;
@end

@implementation PTarget
@end

static PTarget *T(NSString *path, NSString *label, PTargetMode mode) {
    PTarget *t = [PTarget new];
    t.path = path;
    t.label = label;
    t.mode = mode;
    return t;
}

static PTarget *TAge(NSString *path, NSString *label, PTargetMode mode, NSTimeInterval age) {
    PTarget *t = T(path, label, mode);
    t.minAge = age;
    return t;
}

static PTarget *TFilter(NSString *path, NSString *label, BOOL (^filter)(NSString *)) {
    PTarget *t = T(path, label, PTargetContents);
    t.filter = filter;
    return t;
}

// "SpringBoard-2026-09-20-101010.ips" -> "SpringBoard"
static NSString *CrashProcessName(NSString *file) {
    NSString *name = file.stringByDeletingPathExtension;
    NSRange r = [name rangeOfString:@"-20[0-9]{2}-" options:NSRegularExpressionSearch];
    if (r.location != NSNotFound && r.location > 0) return [name substringToIndex:r.location];
    r = [name rangeOfString:@"_20[0-9]{2}-" options:NSRegularExpressionSearch];
    if (r.location != NSNotFound && r.location > 0) return [name substringToIndex:r.location];
    return name;
}

static BOOL IsReverseDNS(NSString *name) {
    return [name componentsSeparatedByString:@"."].count >= 3;
}

static const NSTimeInterval kHour = 3600;

static NSArray<PTarget *> *TargetsForCategory(NSString *cat, NSSet<NSString *> *excluded) {
    NSMutableArray<PTarget *> *t = [NSMutableArray array];
    NSString *safari = ContainerOf(@"com.apple.mobilesafari");

    if ([cat isEqualToString:@"app_caches"]) {
        NSDictionary *containers = AppContainers();
        for (NSString *bundleID in containers) {
            if ([excluded containsObject:bundleID]) continue;
            if ([bundleID isEqualToString:@"com.apple.mobilesafari"]) continue; // owned by safari_cache
            [t addObject:T([containers[bundleID] stringByAppendingPathComponent:@"Library/Caches"], bundleID, PTargetContents)];
        }
    } else if ([cat isEqualToString:@"safari_cache"]) {
        [t addObject:T(@"/var/mobile/Library/Caches/com.apple.mobilesafari", @"Safari", PTargetContents)];
        [t addObject:T(@"/var/mobile/Library/Caches/com.apple.WebKit.Networking", @"WebKit Networking", PTargetContents)];
        [t addObject:T(@"/var/mobile/Library/Caches/com.apple.WebKit.WebContent", @"WebKit Content", PTargetContents)];
        if (safari) [t addObject:T([safari stringByAppendingPathComponent:@"Library/Caches"], @"Safari", PTargetContents)];
    } else if ([cat isEqualToString:@"safari_history"]) {
        NSArray *files = @[ @"History.db", @"History.db-wal", @"History.db-shm", @"History.db-lock", @"RecentlyClosedTabs.plist" ];
        for (NSString *f in files) {
            [t addObject:T([@"/var/mobile/Library/Safari" stringByAppendingPathComponent:f], @"Safari", PTargetSelf)];
            if (safari) [t addObject:T([[safari stringByAppendingPathComponent:@"Library/Safari"] stringByAppendingPathComponent:f], @"Safari", PTargetSelf)];
        }
    } else if ([cat isEqualToString:@"web_data"]) {
        [t addObject:T(@"/var/mobile/Library/Cookies", @"Cookies", PTargetContents)];
        [t addObject:T(@"/var/mobile/Library/WebKit/WebsiteData", @"Website Data", PTargetContents)];
        if (safari) {
            [t addObject:T([safari stringByAppendingPathComponent:@"Library/Cookies"], @"Cookies", PTargetContents)];
            [t addObject:T([safari stringByAppendingPathComponent:@"Library/WebKit"], @"Website Data", PTargetContents)];
        }
    } else if ([cat isEqualToString:@"temp"]) {
        [t addObject:TAge(@"/var/tmp", @"System", PTargetContents, 24 * kHour)];
        [t addObject:TAge(@"/var/mobile/tmp", @"Mobile", PTargetContents, 24 * kHour)];
        [t addObject:TAge(JB(@"/tmp"), @"Jailbreak", PTargetContents, 24 * kHour)];
        [t addObject:TAge(JB(@"/var/tmp"), @"Jailbreak", PTargetContents, 24 * kHour)];
        NSDictionary *containers = AppContainers();
        for (NSString *bundleID in containers) {
            if ([excluded containsObject:bundleID]) continue;
            [t addObject:TAge([containers[bundleID] stringByAppendingPathComponent:@"tmp"], bundleID, PTargetContents, kHour)];
        }
    } else if ([cat isEqualToString:@"crash_logs"]) {
        for (NSString *dir in @[ @"/var/mobile/Library/Logs/CrashReporter", @"/var/mobile/Library/Logs/DiagnosticReports" ]) {
            PTarget *x = T(dir, @"Crash", PTargetFiles);
            x.labeler = ^NSString *(NSString *name) { return CrashProcessName(name); };
            [t addObject:x];
        }
    } else if ([cat isEqualToString:@"logs"]) {
        [t addObject:TAge(JB(@"/var/log"), @"Jailbreak logs", PTargetFiles, kHour)];
        PTarget *mobile = TAge(@"/var/mobile/Library/Logs", @"System logs", PTargetFiles, kHour);
        mobile.skipDirs = [NSSet setWithObjects:@"CrashReporter", @"DiagnosticReports", nil];
        [t addObject:mobile];
    } else if ([cat isEqualToString:@"pkg_cache"]) {
        NSString *archives = JB(@"/var/cache/apt/archives");
        [t addObject:TFilter(archives, @".deb archives", ^BOOL(NSString *n) { return [n hasSuffix:@".deb"]; })];
        [t addObject:T([archives stringByAppendingPathComponent:@"partial"], @".deb archives", PTargetContents)];
        [t addObject:TFilter(JB(@"/var/cache/apt"), @"APT cache", ^BOOL(NSString *n) { return [n hasSuffix:@".bin"]; })];
        for (NSString *app in @[ @"org.coolstar.SileoStore", @"xyz.willy.Zebra", @"com.saurik.Cydia", @"com.tigisoftware.Filza" ]) {
            NSString *label = [app componentsSeparatedByString:@"."].lastObject;
            [t addObject:T([@"/var/mobile/Library/Caches" stringByAppendingPathComponent:app], label, PTargetContents)];
            [t addObject:T([JB(@"/var/mobile/Library/Caches") stringByAppendingPathComponent:app], label, PTargetContents)];
        }
    } else if ([cat isEqualToString:@"apt_lists"]) {
        NSString *lists = JB(@"/var/lib/apt/lists");
        [t addObject:TFilter(lists, @"APT lists", ^BOOL(NSString *n) {
            return ![n isEqualToString:@"lock"] && ![n isEqualToString:@"partial"] && ![n hasPrefix:@"."];
        })];
        [t addObject:T([lists stringByAppendingPathComponent:@"partial"], @"APT lists", PTargetContents)];
        [t addObject:T(JB(@"/var/lib/apt/sileolists"), @"Sileo lists", PTargetContents)];
    } else if ([cat isEqualToString:@"shared_caches"]) {
        NSSet *owned = [NSSet setWithObjects:@"org.coolstar.SileoStore", @"xyz.willy.Zebra", @"com.saurik.Cydia",
                        @"com.tigisoftware.Filza", @"com.xsxs18.voidy", nil];
        NSSet *appleSafe = [NSSet setWithObjects:@"GeoServices", @"com.apple.parsecd", nil];
        BOOL (^filter)(NSString *) = ^BOOL(NSString *n) {
            if ([owned containsObject:n] || [excluded containsObject:n]) return NO;
            if ([appleSafe containsObject:n]) return YES;
            return IsReverseDNS(n) && ![n hasPrefix:@"com.apple."];
        };
        PTarget *a = TFilter(@"/var/mobile/Library/Caches", @"", filter);
        a.labeler = ^NSString *(NSString *name) { return name; };
        PTarget *b = TFilter(JB(@"/var/mobile/Library/Caches"), @"", filter);
        b.labeler = a.labeler;
        [t addObject:a];
        [t addObject:b];
    } else if ([cat isEqualToString:@"keyboard"]) {
        [t addObject:TFilter(@"/var/mobile/Library/Keyboard", @"Keyboard", ^BOOL(NSString *n) {
            return [n hasPrefix:@"dynamic"] || [n hasSuffix:@"-dynamic.lm"] || [n hasSuffix:@"-dynamic-text.dat"];
        })];
    }
    return t;
}

static NSArray<NSString *> *AllCategories(void) {
    return @[ @"app_caches", @"safari_cache", @"temp", @"crash_logs", @"logs", @"pkg_cache",
              @"shared_caches", @"apt_lists", @"safari_history", @"web_data", @"keyboard" ];
}

static NSArray<NSString *> *ProcessesToStop(NSString *cat) {
    if ([cat hasPrefix:@"safari"] || [cat isEqualToString:@"web_data"]) return @[ @"MobileSafari" ];
    if ([cat isEqualToString:@"keyboard"]) return @[ @"kbd" ];
    if ([cat isEqualToString:@"pkg_cache"] || [cat isEqualToString:@"apt_lists"]) return @[ @"Sileo", @"Zebra" ];
    return @[];
}

static BOOL OldEnough(const struct stat *st, NSTimeInterval minAge) {
    if (minAge <= 0) return YES;
    time_t now = time(NULL);
    return (now - st->st_mtime) >= minAge;
}

// Resolves a target into concrete (path, label) pairs.
static void CollectEntries(PTarget *t, NSMutableSet<NSString *> *seen, void (^emit)(NSString *path, NSString *label)) {
    struct stat st;
    if (lstat(t.path.fileSystemRepresentation, &st) != 0) return;

    if (t.mode == PTargetSelf) {
        NSString *real = RealPath(t.path);
        if ([seen containsObject:real]) return;
        [seen addObject:real];
        if (OldEnough(&st, t.minAge)) emit(real, t.label);
        return;
    }

    NSString *root = RealPath(t.path);
    struct stat rst;
    if (stat(root.fileSystemRepresentation, &rst) != 0 || !S_ISDIR(rst.st_mode)) return;
    NSString *seenKey = [NSString stringWithFormat:@"%@|%d", root, t.mode];
    if ([seen containsObject:seenKey]) return;
    [seen addObject:seenKey];

    if (t.mode == PTargetContents) {
        for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil]) {
            if (t.filter && !t.filter(name)) continue;
            NSString *p = [root stringByAppendingPathComponent:name];
            if ([seen containsObject:p]) continue;
            struct stat cs;
            if (lstat(p.fileSystemRepresentation, &cs) != 0 || !OldEnough(&cs, t.minAge)) continue;
            [seen addObject:p];
            emit(p, t.labeler ? t.labeler(name) : t.label);
        }
        return;
    }

    char *paths[] = { (char *)root.fileSystemRepresentation, NULL };
    FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
    if (!fts) return;
    FTSENT *e;
    while ((e = fts_read(fts))) {
        if (e->fts_info == FTS_D && e->fts_level == 1 && t.skipDirs &&
            [t.skipDirs containsObject:@(e->fts_name)]) {
            fts_set(fts, e, FTS_SKIP);
            continue;
        }
        if (e->fts_info != FTS_F && e->fts_info != FTS_SL && e->fts_info != FTS_SLNONE) continue;
        NSString *name = @(e->fts_name);
        if (t.filter && !t.filter(name)) continue;
        if (!OldEnough(e->fts_statp, t.minAge)) continue;
        NSString *p = @(e->fts_path);
        if ([seen containsObject:p]) continue;
        [seen addObject:p];
        emit(p, t.labeler ? t.labeler(name) : t.label);
    }
    fts_close(fts);
}

#pragma mark - Argument parsing

static NSSet<NSString *> *ParseExcluded(NSMutableArray<NSString *> *args) {
    NSMutableSet *set = [NSMutableSet set];
    NSUInteger i = [args indexOfObject:@"--exclude"];
    if (i != NSNotFound && i + 1 < args.count) {
        for (NSString *s in [args[i + 1] componentsSeparatedByString:@","]) if (s.length) [set addObject:s];
        [args removeObjectsInRange:NSMakeRange(i, 2)];
    }
    return set;
}

static NSString *ParseOption(NSMutableArray<NSString *> *args, NSString *flag) {
    NSUInteger i = [args indexOfObject:flag];
    if (i == NSNotFound || i + 1 >= args.count) return nil;
    NSString *value = args[i + 1];
    [args removeObjectsInRange:NSMakeRange(i, 2)];
    return value;
}

static NSArray<NSString *> *ValidCategories(NSArray<NSString *> *requested) {
    NSSet *all = [NSSet setWithArray:AllCategories()];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *c in requested) if ([all containsObject:c] && ![out containsObject:c]) [out addObject:c];
    return out;
}

#pragma mark - scan / clean

static int CmdScan(NSMutableArray<NSString *> *args) {
    NSSet *excluded = ParseExcluded(args);
    NSArray *cats = ValidCategories(args.count ? args : AllCategories());
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *results = [NSMutableArray array];

    for (NSString *cat in cats) {
        __block uint64_t total = 0, files = 0;
        NSMutableDictionary<NSString *, NSMutableDictionary *> *groups = [NSMutableDictionary dictionary];
        for (PTarget *t in TargetsForCategory(cat, excluded)) {
            CollectEntries(t, seen, ^(NSString *path, NSString *label) {
                uint64_t b = 0, f = 0;
                Measure(path, &b, &f);
                total += b;
                files += f;
                NSString *key = label.length ? label : path.lastPathComponent;
                NSMutableDictionary *g = groups[key];
                if (!g) {
                    g = [@{ @"name": key, @"path": t.path, @"bytes": @0ULL, @"files": @0ULL } mutableCopy];
                    groups[key] = g;
                }
                g[@"bytes"] = @([g[@"bytes"] unsignedLongLongValue] + b);
                g[@"files"] = @([g[@"files"] unsignedLongLongValue] + f);
            });
        }
        NSArray *items = [groups.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [b[@"bytes"] compare:a[@"bytes"]];
        }];
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSDictionary *item in items) {
            if ([item[@"files"] unsignedLongLongValue] == 0) continue;
            [filtered addObject:item];
            if (filtered.count >= 60) break;
        }
        [results addObject:@{ @"id": cat, @"bytes": @(total), @"files": @(files), @"items": filtered }];
    }
    Out(@{ @"categories": results });
    return 0;
}

static void AppendHistory(uint64_t freed, uint64_t files, NSArray *cats, BOOL automatic) {
    NSString *dir = JB(@"/var/mobile/Library/Voidy");
    EnsureMobileDir(dir);
    NSString *file = [dir stringByAppendingPathComponent:@"history.jsonl"];
    NSDictionary *entry = @{ @"date": @((long long)time(NULL)), @"bytes": @(freed), @"files": @(files),
                             @"categories": cats, @"auto": @(automatic) };
    NSMutableData *line = [[NSJSONSerialization dataWithJSONObject:entry options:0 error:nil] mutableCopy];
    [line appendBytes:"\n" length:1];
    if (!Exists(file)) [[NSFileManager defaultManager] createFileAtPath:file contents:nil attributes:nil];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:file];
    [h seekToEndOfFile];
    [h writeData:line];
    [h closeFile];
    chown(file.fileSystemRepresentation, MOBILE_UID, MOBILE_UID);
}

static int CmdClean(NSMutableArray<NSString *> *args, BOOL automatic) {
    NSSet *excluded = ParseExcluded(args);
    BOOL dry = [args containsObject:@"--dry-run"];
    [args removeObject:@"--dry-run"];
    NSArray *cats = ValidCategories(args);
    if (cats.count == 0) return Fail(@"No valid categories given");

    NSMutableSet *stop = [NSMutableSet set];
    for (NSString *cat in cats) [stop addObjectsFromArray:ProcessesToStop(cat)];
    if (!dry) for (NSString *p in stop) KillProcess(p);

    NSMutableSet *seen = [NSMutableSet set];
    __block uint64_t freed = 0, files = 0, errors = 0;
    NSMutableDictionary *perCat = [NSMutableDictionary dictionary];

    for (NSString *cat in cats) {
        __block uint64_t catFreed = 0;
        for (PTarget *t in TargetsForCategory(cat, excluded)) {
            CollectEntries(t, seen, ^(NSString *path, NSString *label) {
                uint64_t b = 0, f = 0;
                Measure(path, &b, &f);
                if (dry || Remove(path)) {
                    catFreed += b;
                    files += f;
                } else {
                    errors++;
                }
            });
        }
        freed += catFreed;
        perCat[cat] = @(catFreed);
    }
    if (!dry) AppendHistory(freed, files, cats, automatic);
    Out(@{ @"freed": @(freed), @"files": @(files), @"errors": @(errors), @"categories": perCat, @"dryRun": @(dry) });
    return 0;
}

#pragma mark - Large files

static BOOL IsProtectedPath(NSString *real) {
    NSArray *denied = @[ @"/private/var/mobile/Media/DCIM", @"/private/var/mobile/Media/PhotoData",
                         @"/private/var/mobile/Library/SMS", @"/private/var/mobile/Library/Keychains",
                         @"/private/var/mobile/Library/AddressBook", @"/private/var/mobile/Library/Accounts",
                         @"/private/var/mobile/Library/Health", @"/private/var/mobile/Library/Mail",
                         @"/private/var/mobile/Library/Preferences", @"/private/var/mobile/Library/Calendar",
                         @"/private/var/mobile/Library/CallHistoryDB", @"/private/var/mobile/Library/Notes",
                         RealPath(JB(@"/var/lib")), RealPath(JB(@"/Library")), RealPath(JB(@"/usr")) ];
    for (NSString *d in denied) {
        if ([real isEqualToString:d] || [real hasPrefix:[d stringByAppendingString:@"/"]]) return YES;
    }
    return NO;
}

static BOOL IsDeletableUserPath(NSString *real) {
    if (IsProtectedPath(real)) return NO;
    NSArray *allowed = @[ @"/private/var/mobile/", [RealPath(JB(@"/var")) stringByAppendingString:@"/"],
                          [RealPath(JB(@"/tmp")) stringByAppendingString:@"/"] ];
    for (NSString *a in allowed) if ([real hasPrefix:a]) return YES;
    return NO;
}

static int CmdLarge(NSMutableArray<NSString *> *args) {
    unsigned long long minBytes = [ParseOption(args, @"--min") ?: @"104857600" longLongValue];
    NSUInteger limit = (NSUInteger)[ParseOption(args, @"--limit") ?: @"200" integerValue];

    NSMutableDictionary<NSString *, NSString *> *containerOwners = [NSMutableDictionary dictionary];
    [AppContainers() enumerateKeysAndObjectsUsingBlock:^(NSString *bundleID, NSString *dir, BOOL *stop) {
        containerOwners[RealPath(dir)] = bundleID;
    }];

    NSMutableArray *found = [NSMutableArray array];
    NSArray *roots = @[ RealPath(@"/var/mobile"), RealPath(JB(@"/var")) ];
    NSMutableSet *seenRoots = [NSMutableSet set];
    for (NSString *root in roots) {
        if ([seenRoots containsObject:root]) continue;
        [seenRoots addObject:root];
        char *paths[] = { (char *)root.fileSystemRepresentation, NULL };
        FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
        if (!fts) continue;
        FTSENT *e;
        while ((e = fts_read(fts))) {
            if (e->fts_info == FTS_D) {
                if (IsProtectedPath(@(e->fts_path))) fts_set(fts, e, FTS_SKIP);
                continue;
            }
            if (e->fts_info != FTS_F) continue;
            uint64_t size = Allocated(e->fts_statp);
            if (size < minBytes) continue;
            NSString *p = @(e->fts_path);
            NSString *owner = nil;
            for (NSString *dir in containerOwners) {
                if ([p hasPrefix:[dir stringByAppendingString:@"/"]]) { owner = containerOwners[dir]; break; }
            }
            NSMutableDictionary *item = [@{ @"path": p, @"bytes": @(size),
                                            @"modified": @((double)e->fts_statp->st_mtime) } mutableCopy];
            if (owner) item[@"owner"] = owner;
            [found addObject:item];
        }
        fts_close(fts);
    }
    [found sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"bytes"] compare:a[@"bytes"]];
    }];
    if (found.count > limit) [found removeObjectsInRange:NSMakeRange(limit, found.count - limit)];
    Out(@{ @"files": found });
    return 0;
}

static int CmdDelete(NSMutableArray<NSString *> *args) {
    uint64_t freed = 0, files = 0;
    NSMutableArray *refused = [NSMutableArray array];
    for (NSString *path in args) {
        NSString *real = RealPath(path);
        if (!path.isAbsolutePath || !IsDeletableUserPath(real)) { [refused addObject:path]; continue; }
        uint64_t b = 0, f = 0;
        Measure(real, &b, &f);
        if (Remove(real)) { freed += b; files += f; } else [refused addObject:path];
    }
    Out(@{ @"freed": @(freed), @"files": @(files), @"errors": @(refused.count), @"refused": refused,
           @"categories": @{} });
    return 0;
}

#pragma mark - Tweaks

static NSString *TweakDir(void) {
    for (NSString *p in @[ JB(@"/usr/lib/TweakInject"), JB(@"/Library/MobileSubstrate/DynamicLibraries") ]) {
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&isDir] && isDir) return RealPath(p);
    }
    return nil;
}

// Maps "Foo.dylib" -> dpkg package id using the dpkg file lists.
static NSDictionary<NSString *, NSString *> *DylibPackages(void) {
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    NSString *info = JB(@"/var/lib/dpkg/info");
    for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:info error:nil]) {
        if (![file hasSuffix:@".list"]) continue;
        NSString *contents = [NSString stringWithContentsOfFile:[info stringByAppendingPathComponent:file]
                                                       encoding:NSUTF8StringEncoding error:nil];
        if (![contents containsString:@".dylib"]) continue;
        NSString *pkg = [file stringByDeletingPathExtension];
        NSRange colon = [pkg rangeOfString:@":"];
        if (colon.location != NSNotFound) pkg = [pkg substringToIndex:colon.location];
        for (NSString *line in [contents componentsSeparatedByString:@"\n"]) {
            if (![line hasSuffix:@".dylib"]) continue;
            if (![line containsString:@"TweakInject"] && ![line containsString:@"DynamicLibraries"]) continue;
            map[line.lastPathComponent.stringByDeletingPathExtension] = pkg;
        }
    }
    return map;
}

static int CmdTweaksList(void) {
    NSString *dir = TweakDir();
    if (!dir) { Out(@{ @"tweaks": @[] }); return 0; }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [fm contentsOfDirectoryAtPath:dir error:nil];
    NSSet *nameSet = [NSSet setWithArray:names];
    NSMutableSet *tweakNames = [NSMutableSet set];
    for (NSString *n in names) {
        if ([n hasSuffix:@".dylib"]) [tweakNames addObject:n.stringByDeletingPathExtension];
        else if ([n hasSuffix:@".disabled"] && ![n hasSuffix:@".plist.disabled"]) [tweakNames addObject:n.stringByDeletingPathExtension];
    }
    NSDictionary *packages = DylibPackages();
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in tweakNames) {
        BOOL hasDylib = [nameSet containsObject:[name stringByAppendingString:@".dylib"]];
        BOOL legacyDisabled = [nameSet containsObject:[name stringByAppendingString:@".disabled"]];
        BOOL hasPlist = [nameSet containsObject:[name stringByAppendingString:@".plist"]];
        BOOL plistDisabled = [nameSet containsObject:[name stringByAppendingString:@".plist.disabled"]];
        if (!hasPlist && !plistDisabled) continue; // loader libraries without filters aren't tweaks
        BOOL enabled = hasDylib && hasPlist;

        NSString *plistPath = [dir stringByAppendingPathComponent:
                               [name stringByAppendingString:hasPlist ? @".plist" : @".plist.disabled"]];
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        NSDictionary *filter = [plist[@"Filter"] isKindOfClass:[NSDictionary class]] ? plist[@"Filter"] : nil;
        NSArray *bundles = [filter[@"Bundles"] isKindOfClass:[NSArray class]] ? filter[@"Bundles"] : @[];
        NSArray *executables = [filter[@"Executables"] isKindOfClass:[NSArray class]] ? filter[@"Executables"] : @[];

        NSString *binary = [dir stringByAppendingPathComponent:
                            [name stringByAppendingString:hasDylib ? @".dylib" : @".disabled"]];
        struct stat st;
        uint64_t bytes = lstat(binary.fileSystemRepresentation, &st) == 0 ? (uint64_t)st.st_size : 0;
        double modified = lstat(binary.fileSystemRepresentation, &st) == 0 ? (double)st.st_mtime : 0;

        NSMutableDictionary *item = [@{ @"name": name, @"enabled": @(enabled), @"filters": bundles,
                                        @"executables": executables, @"bytes": @(bytes),
                                        @"modified": @(modified), @"legacy": @(legacyDisabled) } mutableCopy];
        if (packages[name]) item[@"package"] = packages[name];
        [out addObject:item];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] caseInsensitiveCompare:b[@"name"]];
    }];
    Out(@{ @"tweaks": out });
    return 0;
}

static BOOL SetTweak(NSString *dir, NSString *name, BOOL enable) {
    if (name.length == 0 || [name containsString:@"/"] || [name hasPrefix:@"."]) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dylib = [dir stringByAppendingPathComponent:[name stringByAppendingString:@".dylib"]];
    NSString *legacy = [dir stringByAppendingPathComponent:[name stringByAppendingString:@".disabled"]];
    NSString *plist = [dir stringByAppendingPathComponent:[name stringByAppendingString:@".plist"]];
    NSString *plistOff = [dir stringByAppendingPathComponent:[name stringByAppendingString:@".plist.disabled"]];
    if (enable) {
        BOOL ok = YES;
        if (Exists(legacy) && !Exists(dylib)) ok &= [fm moveItemAtPath:legacy toPath:dylib error:nil];
        if (Exists(plistOff) && !Exists(plist)) ok &= [fm moveItemAtPath:plistOff toPath:plist error:nil];
        return ok && Exists(dylib) && Exists(plist);
    }
    if (Exists(plist)) {
        [fm removeItemAtPath:plistOff error:nil];
        return [fm moveItemAtPath:plist toPath:plistOff error:nil];
    }
    return Exists(plistOff);
}

static int CmdTweaksSet(NSMutableArray<NSString *> *args) {
    if (args.count < 2) return Fail(@"usage: tweaks set on|off <name>...");
    BOOL enable = [args[0] isEqualToString:@"on"];
    NSString *dir = TweakDir();
    if (!dir) return Fail(@"Tweak directory not found");
    NSMutableArray *failed = [NSMutableArray array];
    for (NSString *name in [args subarrayWithRange:NSMakeRange(1, args.count - 1)]) {
        if (!SetTweak(dir, name, enable)) [failed addObject:name];
    }
    if (failed.count) return Fail([NSString stringWithFormat:@"Could not change: %@", [failed componentsJoinedByString:@", "]]);
    return OK(nil);
}

#pragma mark - Launch daemons

static NSString *DaemonDir(void) { return JB(@"/Library/LaunchDaemons"); }
static NSString *DisabledDaemonDir(void) { return JB(@"/Library/Voidy/DisabledDaemons"); }

static BOOL IsLockedDaemon(NSString *label) {
    for (NSString *prefix in @[ @"com.opa334.", @"com.roothide.", @"com.apple.", @"com.ellekit", @"com.xsxs18.voidy",
                                @"com.hrtowii.", @"com.nathan.", @"com.serena." ]) {
        if ([label hasPrefix:prefix]) return YES;
    }
    return NO;
}

static NSString *Launchctl(void) {
    return FirstExisting(@[ JB(@"/usr/bin/launchctl"), JB(@"/bin/launchctl"), @"/bin/launchctl", @"/usr/bin/launchctl" ]);
}

static int CmdDaemonsList(void) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSNumber *enabled in @[ @YES, @NO ]) {
        NSString *dir = enabled.boolValue ? DaemonDir() : DisabledDaemonDir();
        for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
            if (![file hasSuffix:@".plist"]) continue;
            NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:file]];
            NSString *label = [plist[@"Label"] isKindOfClass:[NSString class]] ? plist[@"Label"] : file.stringByDeletingPathExtension;
            NSString *program = plist[@"Program"];
            NSArray *arguments = plist[@"ProgramArguments"];
            if (![program isKindOfClass:[NSString class]]) {
                program = [arguments isKindOfClass:[NSArray class]] && arguments.count ? arguments[0] : @"";
            }
            [out addObject:@{ @"file": file, @"label": label, @"program": program ?: @"",
                              @"enabled": enabled, @"locked": @(IsLockedDaemon(label)) }];
        }
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"label"] caseInsensitiveCompare:b[@"label"]];
    }];
    Out(@{ @"daemons": out });
    return 0;
}

static int CmdDaemonsSet(NSMutableArray<NSString *> *args) {
    if (args.count != 2) return Fail(@"usage: daemons set on|off <file.plist>");
    BOOL enable = [args[0] isEqualToString:@"on"];
    NSString *file = args[1];
    if ([file containsString:@"/"] || ![file hasSuffix:@".plist"]) return Fail(@"Invalid daemon file");

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *active = [DaemonDir() stringByAppendingPathComponent:file];
    NSString *parked = [DisabledDaemonDir() stringByAppendingPathComponent:file];
    NSString *source = enable ? parked : active;
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:source];
    NSString *label = plist[@"Label"] ?: file.stringByDeletingPathExtension;
    if (IsLockedDaemon(label)) return Fail(@"This daemon is protected");
    NSString *launchctl = Launchctl();

    if (enable) {
        if (![fm moveItemAtPath:parked toPath:active error:nil]) return Fail(@"Could not restore daemon");
        if (launchctl) Run(@[ launchctl, @"bootstrap", @"system", active ], NULL);
    } else {
        [fm createDirectoryAtPath:DisabledDaemonDir() withIntermediateDirectories:YES attributes:nil error:nil];
        if (launchctl) Run(@[ launchctl, @"bootout", [@"system/" stringByAppendingString:label] ], NULL);
        [fm removeItemAtPath:parked error:nil];
        if (![fm moveItemAtPath:active toPath:parked error:nil]) return Fail(@"Could not disable daemon");
    }
    return OK(nil);
}

#pragma mark - Orphaned packages

static int CmdOrphans(NSMutableArray<NSString *> *args) {
    NSString *aptGet = Tool(@"apt-get");
    if (!aptGet) return Fail(@"apt-get not found");
    BOOL remove = args.count && [args[0] isEqualToString:@"remove"];
    NSString *output = nil;
    if (remove) {
        int rc = Run(@[ aptGet, @"-y", @"--allow-remove-essential", @"autoremove" ], &output);
        if (rc != 0) return Fail([NSString stringWithFormat:@"apt-get failed (%d): %@", rc,
                                  [output substringFromIndex:output.length > 600 ? output.length - 600 : 0]]);
        return OK(@"Orphaned packages removed");
    }
    Run(@[ aptGet, @"-s", @"autoremove" ], &output);
    NSMutableArray *orphans = [NSMutableArray array];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^Remv (\\S+)(?: \\[([^\\]]+)\\])?"
                                                                        options:NSRegularExpressionAnchorsMatchLines error:nil];
    for (NSTextCheckingResult *m in [re matchesInString:output ?: @"" options:0 range:NSMakeRange(0, output.length)]) {
        NSString *name = [output substringWithRange:[m rangeAtIndex:1]];
        NSString *version = [m rangeAtIndex:2].location != NSNotFound ? [output substringWithRange:[m rangeAtIndex:2]] : @"";
        [orphans addObject:@{ @"name": name, @"version": version }];
    }
    Out(@{ @"orphans": orphans });
    return 0;
}

#pragma mark - Language files

static NSString *NormalizeLanguage(NSString *lproj) {
    NSDictionary *legacy = @{ @"English": @"en", @"German": @"de", @"French": @"fr", @"Spanish": @"es",
                              @"Italian": @"it", @"Japanese": @"ja", @"Dutch": @"nl" };
    NSString *base = lproj.stringByDeletingPathExtension;
    if (legacy[base]) return legacy[base];
    return [[base componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-_"]]
            .firstObject lowercaseString];
}

static NSArray<NSString *> *LanguageBundles(void) {
    NSMutableArray *bundles = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *roots = @[ JB(@"/Applications"), JB(@"/Library/PreferenceBundles"), JB(@"/Library/Application Support") ];
    for (NSString *root in roots) {
        for (NSString *n in [fm contentsOfDirectoryAtPath:root error:nil]) {
            NSString *p = [root stringByAppendingPathComponent:n];
            if ([n hasSuffix:@".app"] || [n hasSuffix:@".bundle"]) { [bundles addObject:p]; continue; }
            for (NSString *sub in [fm contentsOfDirectoryAtPath:p error:nil]) {
                if ([sub hasSuffix:@".bundle"]) [bundles addObject:[p stringByAppendingPathComponent:sub]];
            }
        }
    }
    return bundles;
}

static int CmdLanguages(NSMutableArray<NSString *> *args) {
    BOOL clean = args.count && [args[0] isEqualToString:@"clean"];
    NSMutableSet *keep = [NSMutableSet setWithObjects:@"en", @"base", nil];
    for (NSString *k in [ParseOption(args, @"--keep") componentsSeparatedByString:@","]) {
        if (k.length) [keep addObject:NormalizeLanguage(k)];
    }
    uint64_t total = 0, count = 0, removed = 0;
    NSMutableDictionary *perLang = [NSMutableDictionary dictionary];
    for (NSString *bundle in LanguageBundles()) {
        for (NSString *n in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundle error:nil]) {
            if (![n hasSuffix:@".lproj"]) continue;
            NSString *lang = NormalizeLanguage(n);
            if ([keep containsObject:lang]) continue;
            NSString *p = [bundle stringByAppendingPathComponent:n];
            uint64_t b = 0, f = 0;
            Measure(p, &b, &f);
            if (clean) {
                if (!Remove(p)) continue;
                removed += b;
            }
            total += b;
            count++;
            perLang[lang] = @([perLang[lang] unsignedLongLongValue] + b);
        }
    }
    Out(@{ @"bytes": @(total), @"count": @(count), @"freed": @(removed), @"languages": perLang });
    return 0;
}

#pragma mark - Power

static int CmdPower(NSMutableArray<NSString *> *args) {
    if (!args.count) return Fail(@"usage: power respring|uicache|userspace|reboot|ldrestart");
    NSString *action = args[0];
    NSString *launchctl = Launchctl();
    if ([action isEqualToString:@"respring"]) {
        NSString *sbreload = Tool(@"sbreload");
        if (sbreload && Run(@[ sbreload ], NULL) == 0) return OK(nil);
        KillProcess(@"SpringBoard");
        return OK(nil);
    }
    if ([action isEqualToString:@"uicache"]) {
        NSString *uicache = Tool(@"uicache");
        if (!uicache) return Fail(@"uicache not found – install uikittools");
        NSString *out = nil;
        int rc = Run(@[ uicache, @"-a" ], &out);
        return rc == 0 ? OK(nil) : Fail(out);
    }
    if ([action isEqualToString:@"userspace"]) {
        if (!launchctl) return Fail(@"launchctl not found");
        Run(@[ launchctl, @"reboot", @"userspace" ], NULL);
        return OK(nil);
    }
    if ([action isEqualToString:@"reboot"]) {
        NSString *reboot = Tool(@"reboot");
        if (reboot) Run(@[ reboot ], NULL);
        else if (launchctl) Run(@[ launchctl, @"reboot" ], NULL);
        return OK(nil);
    }
    if ([action isEqualToString:@"ldrestart"]) {
        NSString *ldrestart = Tool(@"ldrestart");
        if (!ldrestart) return Fail(@"ldrestart not found");
        Run(@[ ldrestart ], NULL);
        return OK(nil);
    }
    return Fail(@"Unknown power action");
}

#pragma mark - Schedule

static NSString *SchedulePlistPath(void) {
    return [DaemonDir() stringByAppendingPathComponent:[SCHEDULE_LABEL stringByAppendingString:@".plist"]];
}

static int CmdSchedule(NSMutableArray<NSString *> *args) {
    NSString *sub = args.count ? args[0] : @"status";
    NSString *path = SchedulePlistPath();
    NSString *launchctl = Launchctl();

    if ([sub isEqualToString:@"status"]) {
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
        if (!plist) { Out(@{ @"enabled": @NO, @"hours": @0, @"categories": @[] }); return 0; }
        NSArray *pa = plist[@"ProgramArguments"];
        NSMutableArray *cats = [NSMutableArray array];
        for (NSUInteger i = 2; i < pa.count; i++) {
            if ([pa[i] isEqualToString:@"--exclude"]) { i++; continue; }
            [cats addObject:pa[i]];
        }
        Out(@{ @"enabled": @YES, @"hours": @([plist[@"StartInterval"] integerValue] / 3600), @"categories": cats });
        return 0;
    }

    if (launchctl) Run(@[ launchctl, @"bootout", [@"system/" stringByAppendingString:SCHEDULE_LABEL] ], NULL);
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    if ([sub isEqualToString:@"off"]) return OK(nil);

    if (![sub isEqualToString:@"set"] || args.count < 3) return Fail(@"usage: schedule set <hours> [--exclude ids] <categories>");
    [args removeObjectAtIndex:0];
    NSInteger hours = MAX(1, [args[0] integerValue]);
    [args removeObjectAtIndex:0];
    NSSet *excluded = ParseExcluded(args);
    NSArray *cats = ValidCategories(args);
    if (!cats.count) return Fail(@"No valid categories given");

    NSMutableArray *programArgs = [NSMutableArray arrayWithObjects:gSelfPath, @"autoclean", nil];
    if (excluded.count) [programArgs addObjectsFromArray:@[ @"--exclude", [excluded.allObjects componentsJoinedByString:@","] ]];
    [programArgs addObjectsFromArray:cats];
    NSDictionary *plist = @{ @"Label": SCHEDULE_LABEL, @"ProgramArguments": programArgs,
                             @"StartInterval": @(hours * 3600), @"RunAtLoad": @NO,
                             @"UserName": @"root", @"LowPriorityIO": @YES, @"Nice": @10,
                             @"ProcessType": @"Background" };
    if (![plist writeToFile:path atomically:YES]) return Fail(@"Could not write launch daemon");
    chown(path.fileSystemRepresentation, 0, 0);
    chmod(path.fileSystemRepresentation, 0644);
    if (launchctl) Run(@[ launchctl, @"bootstrap", @"system", path ], NULL);
    return OK(nil);
}

// Undo everything Voidy parked, used when the package is removed.
static int CmdRestoreAll(void) {
    NSString *dir = TweakDir();
    NSFileManager *fm = [NSFileManager defaultManager];
    if (dir) {
        for (NSString *n in [fm contentsOfDirectoryAtPath:dir error:nil]) {
            if ([n hasSuffix:@".plist.disabled"]) SetTweak(dir, [n substringToIndex:n.length - @".plist.disabled".length], YES);
        }
    }
    NSString *launchctl = Launchctl();
    for (NSString *file in [fm contentsOfDirectoryAtPath:DisabledDaemonDir() error:nil]) {
        NSString *active = [DaemonDir() stringByAppendingPathComponent:file];
        if ([fm moveItemAtPath:[DisabledDaemonDir() stringByAppendingPathComponent:file] toPath:active error:nil] && launchctl) {
            Run(@[ launchctl, @"bootstrap", @"system", active ], NULL);
        }
    }
    NSMutableArray *off = [NSMutableArray arrayWithObject:@"off"];
    CmdSchedule(off);
    return 0;
}

#pragma mark - main

int main(int argc, char *argv[]) {
    @autoreleasepool {
        DetectPaths();
        if (!CallerAllowed()) return Fail(@"Permission denied");
        setgid(0);
        setuid(0);
        if (getuid() != 0) return Fail(@"Helper is not running as root – reinstall Voidy");

        NSMutableArray<NSString *> *args = [NSMutableArray array];
        for (int i = 1; i < argc; i++) [args addObject:@(argv[i])];
        if (!args.count) return Fail(@"No command");
        NSString *cmd = args[0];
        [args removeObjectAtIndex:0];

        if ([cmd isEqualToString:@"info"]) {
            Out(@{ @"jbroot": gJBRoot, @"scheme": Scheme(), @"helper": gSelfPath ?: @"", @"version": @"1.0" });
            return 0;
        }
        if ([cmd isEqualToString:@"scan"]) return CmdScan(args);
        if ([cmd isEqualToString:@"clean"]) return CmdClean(args, NO);
        if ([cmd isEqualToString:@"autoclean"]) return CmdClean(args, YES);
        if ([cmd isEqualToString:@"large"]) return CmdLarge(args);
        if ([cmd isEqualToString:@"delete"]) return CmdDelete(args);
        if ([cmd isEqualToString:@"tweaks"]) {
            NSString *sub = args.count ? args[0] : @"list";
            if (args.count) [args removeObjectAtIndex:0];
            if ([sub isEqualToString:@"set"]) return CmdTweaksSet(args);
            return CmdTweaksList();
        }
        if ([cmd isEqualToString:@"daemons"]) {
            NSString *sub = args.count ? args[0] : @"list";
            if (args.count) [args removeObjectAtIndex:0];
            if ([sub isEqualToString:@"set"]) return CmdDaemonsSet(args);
            return CmdDaemonsList();
        }
        if ([cmd isEqualToString:@"orphans"]) return CmdOrphans(args);
        if ([cmd isEqualToString:@"languages"]) return CmdLanguages(args);
        if ([cmd isEqualToString:@"power"]) return CmdPower(args);
        if ([cmd isEqualToString:@"schedule"]) return CmdSchedule(args);
        if ([cmd isEqualToString:@"restore-all"]) return CmdRestoreAll();
        return Fail([NSString stringWithFormat:@"Unknown command: %@", cmd]);
    }
}
