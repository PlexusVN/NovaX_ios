#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <errno.h>
#include <xpc/xpc.h>
#include <stdlib.h>
#include <string.h>

// Compile the production bridge. Only dynamically loaded OS functions are
// replaced; query construction, owners, exception cleanup and fallback remain
// production code. This does not call containermanagerd or issue an extension.
static void *fixture_dlopen(const char *, int);
static void *fixture_dlsym(void *, const char *);
static int fixture_open(const char *, int, ...);
#define dlopen(...) fixture_dlopen(__VA_ARGS__)
#define dlsym(...) fixture_dlsym(__VA_ARGS__)
#define open(...) fixture_open(__VA_ARGS__)
#include "../ThreeOneOSFive/exploit/mcm_bridge.m"
#undef dlopen
#undef dlsym
#undef open

bool AstraUses3105ContainerAccess(void) { return false; }

static const uint64_t rawFlags = 0x100000000ULL;
static const uint64_t leaseFlags = 0x900000000ULL;
static NSString *targetID = @"com.astra.fixture.target";
static NSString *groupID = @"group.astra.fixture.target";
static const char *dataRoot = "/var/mobile/Containers/Data/Application/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA";
static const char *canonicalRoot = "/private/var/mobile/Containers/Data/Application/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA";
static const char *groupRoot = "/var/mobile/Containers/Shared/AppGroup/BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB";
static const char *canonicalGroupRoot = "/private/var/mobile/Containers/Shared/AppGroup/BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB";

typedef NS_ENUM(NSUInteger, ThrowStage) {
    ThrowNone, ThrowResult, ThrowPath
};
typedef struct {
    uint64_t klass, flags, part;
    BOOL group, identifierSet;
    void *borrowedIdentifier;
    char *identifierText;
    char *path;
} FixtureQuery;

static NSUInteger created, freed, rawResults, leaseResults, liveQueries;
static NSUInteger copyCalls, tokenCalls, activateCalls, objectFreeCalls, libraryCalls;
static NSUInteger openCalls;
static NSUInteger checks;
static NSUInteger failCreates;
static BOOL denyRaw, denyLease;
static const char *rawPath, *leasePath;
static ThrowStage exceptionStage;
static uint64_t exceptionFlags;
static NSUInteger identifierExceptionQuery;

static void require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        abort();
    }
    checks++;
}

static void resetFixture(void) {
    require(liveQueries == 0 && created == freed, @"the previous lookup leaked a query");
    created = freed = rawResults = leaseResults = 0;
    copyCalls = tokenCalls = activateCalls = objectFreeCalls = 0;
    openCalls = 0;
    failCreates = 0;
    denyRaw = denyLease = NO;
    rawPath = leasePath = dataRoot;
    exceptionStage = ThrowNone;
    exceptionFlags = 0;
    identifierExceptionQuery = 0;
}

static void requireClean(NSUInteger expectedCreates, NSString *label) {
    require(created == expectedCreates && freed == expectedCreates && liveQueries == 0,
            [label stringByAppendingString:@": every created query must be freed"]);
    require(copyCalls == 0 && tokenCalls == 0 && activateCalls == 0 && objectFreeCalls == 0,
            [label stringByAppendingString:@": path lookup must never copy an object/token or activate an extension"]);
    require(openCalls == 0, [label stringByAppendingString:@": path lookup probed the filesystem before a worse_query grant"]);
}

static void *createQuery(void) {
    if (failCreates > 0) { failCreates--; return NULL; }
    FixtureQuery *query = calloc(1, sizeof(FixtureQuery));
    require(query != NULL, @"fixture allocation failed");
    created++; liveQueries++;
    return query;
}
static void setClass(void *pointer, uint64_t value) {
    ((FixtureQuery *)pointer)->klass = value;
}
static void setIdentifiers(void *pointer, xpc_object_t value, BOOL group) {
    FixtureQuery *query = pointer;
    query->group = group;
    query->identifierSet = YES;
    // Deliberately do not retain it: the production owner must keep this XPC
    // value alive through queryFree, including an exception after the setter.
    query->borrowedIdentifier = (__bridge void *)value;
    const char *text = xpc_string_get_string_ptr(value);
    require(text != NULL, @"the query identifier was not an XPC string");
    require(strcmp(text, (group ? groupID : targetID).UTF8String) == 0,
            @"the query identifier did not match its requested target");
    query->identifierText = strdup(text);
    if (identifierExceptionQuery != 0 && created == identifierExceptionQuery) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
            reason:@"fixture identifier setter exception" userInfo:nil];
    }
}
static void setIdentifier(void *pointer, xpc_object_t value) { setIdentifiers(pointer, value, NO); }
static void setGroupIdentifier(void *pointer, xpc_object_t value) { setIdentifiers(pointer, value, YES); }
static void setFlags(void *pointer, uint64_t value) { ((FixtureQuery *)pointer)->flags = value; }
static void setPart(void *pointer, uint64_t value) { ((FixtureQuery *)pointer)->part = value; }

static void *getResult(void *pointer) {
    FixtureQuery *query = pointer;
    require(!NSThread.isMainThread, @"a path query ran on the main thread");
    require(query->klass == (query->group ? 7 : 2), @"class/identifier kind changed");
    require(query->part == 0 && query->identifierSet, @"path query part or identifier was missing");
    require(query->flags == rawFlags || query->flags == leaseFlags, @"unexpected path lookup flags");
    if (query->flags == rawFlags) rawResults++; else leaseResults++;
    if (exceptionStage == ThrowResult && query->flags == exceptionFlags) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
            reason:@"fixture result exception" userInfo:nil];
    }
    if ((query->flags == rawFlags && denyRaw) || (query->flags == leaseFlags && denyLease)) return NULL;
    return query;
}
static const char *getPath(void *pointer) {
    FixtureQuery *query = pointer;
    if (exceptionStage == ThrowPath && query->flags == exceptionFlags) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
            reason:@"fixture path exception" userInfo:nil];
    }
    const char *path = query->flags == rawFlags ? rawPath : leasePath;
    if (!path) return NULL;
    // The result buffer belongs to the query. A returned NSString must outlive
    // this buffer and the temporary fallback lease, after both are cleaned up.
    query->path = strdup(path);
    return query->path;
}
static void freeQuery(void *pointer) {
    FixtureQuery *query = pointer;
    require(liveQueries > 0, @"double query cleanup");
    if (query->borrowedIdentifier) {
        const char *text = xpc_string_get_string_ptr((__bridge xpc_object_t)query->borrowedIdentifier);
        require(text && query->identifierText && strcmp(text, query->identifierText) == 0,
                @"identifier owner died before queryFree");
    }
    free(query->identifierText);
    if (query->path) {
        memset(query->path, 0xA5, strlen(query->path));
        free(query->path);
    }
    free(query);
    freed++; liveQueries--;
}
static void *getLastError(void *query) { return NULL; }
static int getPOSIX(void *error) { return 13; }
static const char *getMessage(void *error) { return "fixture denial"; }
static void *copyObject(void *object) { copyCalls++; return NULL; }
static char *copyToken(void *object) { tokenCalls++; return NULL; }
static bool activateObject(void *object, bool flag) { activateCalls++; return false; }
static void freeObject(void *object) { objectFreeCalls++; }
static int fixture_open(const char *path, int flags, ...) {
    openCalls++;
    errno = EACCES;
    return -1;
}

static void *fixture_dlopen(const char *path, int flags) {
    libraryCalls++;
    require(strcmp(path, "/usr/lib/system/libsystem_containermanager.dylib") == 0,
            @"the fixture attempted to load a different library");
    return (void *)1;
}
static void *fixture_dlsym(void *handle, const char *name) {
    if (strcmp(name, "container_query_create") == 0) return (void *)createQuery;
    if (strcmp(name, "container_query_set_class") == 0) return (void *)setClass;
    if (strcmp(name, "container_query_set_identifiers") == 0) return (void *)setIdentifier;
    if (strcmp(name, "container_query_set_group_identifiers") == 0) return (void *)setGroupIdentifier;
    if (strcmp(name, "container_query_operation_set_flags") == 0) return (void *)setFlags;
    if (strcmp(name, "container_query_operation_set_part") == 0) return (void *)setPart;
    if (strcmp(name, "container_query_get_single_result") == 0) return (void *)getResult;
    if (strcmp(name, "container_query_get_last_error") == 0) return (void *)getLastError;
    if (strcmp(name, "container_query_free") == 0) return (void *)freeQuery;
    if (strcmp(name, "container_object_get_path") == 0) return (void *)getPath;
    if (strcmp(name, "container_object_copy") == 0) return (void *)copyObject;
    if (strcmp(name, "container_copy_sandbox_token") == 0) return (void *)copyToken;
    if (strcmp(name, "container_object_sandbox_extension_activate") == 0) return (void *)activateObject;
    if (strcmp(name, "container_object_free") == 0) return (void *)freeObject;
    if (strcmp(name, "container_error_get_posix_errno") == 0) return (void *)getPOSIX;
    if (strcmp(name, "container_error_get_message") == 0) return (void *)getMessage;
    return NULL;
}

static NSString *lookup(uint64_t klass, NSString *identifier, BOOL group, NSString **error) {
    __block NSString *path;
    __block NSString *failure;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    // A dedicated pool drains the temporary lease before counters are checked.
    // dispatch_sync may execute inline on the caller, so use async admission to
    // guarantee this exercises the production worker-thread guard honestly.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSString *detail = nil;
            path = MCMContainerPathForWorseQuery(klass, identifier, group, &detail);
            failure = detail;
        }
        dispatch_semaphore_signal(finished);
    });
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
    if (error) *error = failure;
    return path;
}

int main(void) {
    @autoreleasepool {
        NSString *error = nil;
        require(MCMContainerPathForWorseQuery(2, targetID, NO, &error) == nil,
                @"the main thread was allowed to query MCM");
        require([error containsString:@"worker"] && created == 0 && libraryCalls == 0,
                @"main-thread rejection performed native work or hid its reason");

        resetFixture();
        require([lookup(2, targetID, NO, &error) isEqualToString:[NSString stringWithUTF8String:canonicalRoot]],
                @"raw lookup failed or did not canonicalize /var");
        require(rawResults == 1 && leaseResults == 0, @"raw success unnecessarily entered the lease fallback");
        requireClean(1, @"raw success");

        resetFixture();
        rawPath = groupRoot;
        require([lookup(7, groupID, YES, &error) isEqualToString:[NSString stringWithUTF8String:canonicalGroupRoot]],
                @"App Group lookup used the wrong identifier setter");
        requireClean(1, @"group success");

        resetFixture(); denyRaw = YES;
        require([lookup(2, targetID, NO, &error) isEqualToString:[NSString stringWithUTF8String:canonicalRoot]],
                @"lease path fallback failed after raw denial");
        require(rawResults == 1 && leaseResults == 1, @"raw denial did not try one lease lookup");
        requireClean(2, @"lease success");

        resetFixture(); denyRaw = YES; leasePath = groupRoot;
        require([lookup(7, groupID, YES, &error) isEqualToString:[NSString stringWithUTF8String:canonicalGroupRoot]],
                @"lease fallback lost its App Group identifier kind");
        requireClean(2, @"group lease success");

        resetFixture(); rawPath = "relative/path";
        require([lookup(2, targetID, NO, &error) isEqualToString:[NSString stringWithUTF8String:canonicalRoot]],
                @"relative raw result bypassed the absolute-path guard");
        requireClean(2, @"relative raw path");

        resetFixture(); rawPath = NULL;
        require([lookup(2, targetID, NO, &error) isEqualToString:[NSString stringWithUTF8String:canonicalRoot]],
                @"missing raw path did not try the fallback");
        requireClean(2, @"empty raw path");

        resetFixture(); denyRaw = denyLease = YES; error = nil;
        require(lookup(2, targetID, NO, &error) == nil && error.length > 0,
                @"two denials became a valid container or lost their error");
        requireClean(2, @"denied lookups");

        resetFixture(); denyRaw = YES; leasePath = "relative/path"; error = nil;
        require(lookup(2, targetID, NO, &error) == nil && error.length > 0,
                @"relative lease path was accepted");
        requireClean(2, @"relative lease path");

        resetFixture(); failCreates = 2; error = nil;
        require(lookup(2, targetID, NO, &error) == nil && error.length > 0,
                @"failed query creation was accepted");
        requireClean(0, @"query creation failure");

        resetFixture(); identifierExceptionQuery = 1; error = nil;
        require(lookup(2, targetID, NO, &error) == nil && [error containsString:@"exception"],
                @"identifier setter exception escaped or was hidden");
        requireClean(1, @"identifier setter exception");

        resetFixture(); denyRaw = YES; identifierExceptionQuery = 2; error = nil;
        require(lookup(2, targetID, NO, &error) == nil && [error containsString:@"exception"],
                @"lease identifier setter exception escaped or was hidden");
        requireClean(2, @"lease identifier setter exception");

        for (NSNumber *stage in @[@(ThrowResult), @(ThrowPath)]) {
            resetFixture(); exceptionStage = stage.unsignedIntegerValue; exceptionFlags = rawFlags; error = nil;
            require(lookup(2, targetID, NO, &error) == nil && [error containsString:@"exception"],
                    @"raw lookup exception escaped the bridge");
            requireClean(1, @"raw exception");

            resetFixture(); denyRaw = YES; exceptionStage = stage.unsignedIntegerValue; exceptionFlags = leaseFlags; error = nil;
            require(lookup(2, targetID, NO, &error) == nil && [error containsString:@"exception"],
                    @"lease lookup exception escaped the bridge");
            requireClean(2, @"lease exception");
        }

        NSArray *invalid = @[@"", @".", @"..", @"com.astra/invalid", @"com.astra\ninvalid",
            [@"a" stringByPaddingToLength:256 withString:@"a" startingAtIndex:0]];
        for (NSString *identifier in invalid) {
            resetFixture(); error = nil;
            require(lookup(2, identifier, NO, &error) == nil && [error containsString:@"identifier"],
                    @"unsafe identifier reached a query");
            requireClean(0, @"invalid identifier");
        }
        resetFixture();
        require(MCMActivateContainerPath(2, targetID, NO, &error) == nil,
                @"path-only lookup accidentally enabled legacy activation");
        requireClean(0, @"legacy route remains inactive");
        printf("[PASS] production MCM path lookup: %lu checks; raw/lease path-only routing, worker guard, ownership and exception cleanup\n",
               (unsigned long)checks);
    }
    return 0;
}
