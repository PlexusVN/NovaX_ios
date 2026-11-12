#import <Foundation/Foundation.h>
#include <sys/mount.h>
#include <sys/fsgetpath.h>
#include <errno.h>
#include <string.h>

static uint64_t scanned = 0;
static int fixture_statfs(const char *path, struct statfs *out) {
    memset(out, 0, sizeof(*out));
    return 0;
}
static ssize_t fixture_fsgetpath(char *buffer, size_t size, fsid_t *fsid, uint64_t inode) {
    scanned++;
    const char *path = NULL;
    if (inode == 5) path = "/private/var/mobile/Containers/Data/Application/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA";
    if (inode == 100001) path = "/var/mobile/Containers/Data/Application/BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB";
    if (inode == 2000000) path = "/var/mobile/Containers/Data/Application/CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC";
    if (!path) { errno = ENOENT; return -1; }
    size_t length = strlen(path) + 1;
    if (length > size) { errno = ERANGE; return -1; }
    memcpy(buffer, path, length);
    return (ssize_t)length;
}

// Execute the production C scanner; only filesystem syscalls are replaced.
// The containermanager query functions are compiled but never executed here.
#define statfs(...) fixture_statfs(__VA_ARGS__)
#define fsgetpath(...) fixture_fsgetpath(__VA_ARGS__)
#include "../ThreeOneOSFive/exploit/bad_query.c"
#undef statfs
#undef fsgetpath

int main(void) {
    @autoreleasepool {
        char *root = "/var/mobile/Containers/Data/Application";
        char *result = bad_query_list(root, 2000000);
        NSCAssert(result && scanned == 2000000, @"production scanner truncated the requested upstream range");
        NSCAssert(strstr(result, "AAAAAAAA") && strstr(result, "BBBBBBBB") && strstr(result, "CCCCCCCC"),
                  @"legacy discovery missed containers past 100k");
        free(result);
        uint64_t before = scanned;
        NSCAssert(bad_query_list(root, 0) == NULL && errno == EINVAL, @"zero range was not rejected");
        NSCAssert(bad_query_list(root, -1) == NULL && errno == EINVAL, @"negative range was not rejected");
        NSCAssert(bad_query_list(NULL, 2000000) == NULL && errno == EINVAL, @"NULL path was not rejected");
        NSCAssert(scanned == before, @"invalid input started scanning");
        puts("[PASS] production 3105 bad_query enumeration: honors 2M range, finds containers past 100k, rejects invalid input");
    }
    return 0;
}
