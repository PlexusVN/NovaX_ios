#import <Foundation/Foundation.h>
#include <sys/fsgetpath.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <errno.h>
#include <string.h>

static BOOL allowHomeStat = YES;
static NSUInteger homeStatCalls = 0;
static uint64_t pathCalls = 0;
static int fixture_statfs(const char *path, struct statfs *result);
static ssize_t fixture_fsgetpath(char *buffer, size_t size, fsid_t *fsid, uint64_t inode);

// Compile the real production scanner. Only its OS boundary is replaced;
// range iteration, filtering, canonicalization and error handling remain real.
#define statfs(...) fixture_statfs(__VA_ARGS__)
#define fsgetpath(...) fixture_fsgetpath(__VA_ARGS__)
#include "../ThreeOneOSFive/exploit/pathleak.m"
#undef statfs
#undef fsgetpath

static NSString *root = @"/private/var/mobile/Containers/Data/Application";
static NSString *a = @"/private/var/mobile/Containers/Data/Application/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA";
static NSString *b = @"/private/var/mobile/Containers/Data/Application/BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB";
static NSString *c = @"/private/var/mobile/Containers/Data/Application/CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC";

static int fixture_statfs(const char *path, struct statfs *result) {
    if (strcmp(path, root.fileSystemRepresentation) == 0 ||
        strcmp(path, "/var/mobile/Containers/Data/Application") == 0) {
        errno = EACCES;
        return -1;
    }
    homeStatCalls++;
    if (!allowHomeStat) { errno = EPERM; return -1; }
    memset(result, 0, sizeof(*result));
    int32_t volume = 123;
    memcpy(&result->f_fsid, &volume, sizeof(volume));
    return 0;
}

static ssize_t fixture_fsgetpath(char *buffer, size_t size, fsid_t *fsid, uint64_t inode) {
    pathCalls++;
    int32_t volume = 0;
    memcpy(&volume, fsid, sizeof(volume));
    NSCAssert(volume == 123, @"scanner used a different volume");
    NSString *path = nil;
    switch (inode) {
        case 1: path = a; break;
        case 3: path = [a stringByAppendingString:@"/Documents/file"]; break;
        case 4: path = @"/private/var/mobile/Containers/Data/ApplicationExtra/invalid"; break;
        case 5: path = root; break;
        case 8: path = [a substringFromIndex:8]; break;
        case 10: path = @"/"; break;
        case 20: path = @"/private"; break;
        case 500001: path = [b substringFromIndex:8]; break;
        case 2000000: path = c; break;
        default: errno = ENOENT; return -1;
    }
    const char *value = path.fileSystemRepresentation;
    size_t count = strlen(value) + 1;
    if (count > size) { errno = ERANGE; return -1; }
    memcpy(buffer, value, count);
    return (ssize_t)count;
}

int main(void) {
    @autoreleasepool {
        NSArray *oldWindow = pathleak(root, 500000);
        NSCAssert(oldWindow.count == 1 && [oldWindow containsObject:a], @"prefix/child filtering or alias dedup failed");
        NSCAssert(![oldWindow containsObject:c], @"fixture must reproduce the old 500k cutoff");
        NSMutableSet *found = [NSMutableSet set];
        for (uint64_t first = 1; first <= 2100000; first += 250000) {
            int32_t code = -1;
            NSArray *paths = pathleak_range(root, first, MIN(first + 249999, 2100000), &code);
            NSCAssert(paths != nil && code == 0, @"range scan failed");
            [found addObjectsFromArray:paths];
        }
        NSCAssert(found.count == 3 && [found containsObject:b] && [found containsObject:c], @"high-inode containers were omitted");
        NSCAssert(homeStatCalls > 0, @"denied filter statfs never used the accessible home volume");
        pathCalls = 0;
        NSArray *two = pathleak_range(root, 500000, 500001, NULL);
        NSCAssert(pathCalls == 2 && [two isEqualToArray:@[b]], @"inclusive range bounds were not honored");
        NSArray *rootChildren = pathleak_range(@"/", 1, 20, NULL);
        NSCAssert([rootChildren isEqualToArray:@[@"/private"]], @"root must return direct children only");
        int32_t code = 0;
        NSCAssert(pathleak_range(root, 2, 1, &code) == nil && code == EINVAL, @"invalid range was silently accepted");
        allowHomeStat = NO;
        NSCAssert(pathleak_range(root, 1, 2, &code) == nil && code == EPERM, @"filesystem error was collapsed to no matches");
        puts("[PASS] production pathleak: high inodes, inclusive chunks, denied-parent fsid fallback, aliases, boundaries and errors");
    }
    return 0;
}
