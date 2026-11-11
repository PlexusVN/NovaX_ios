#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <unistd.h>

static void *fixture_dlopen(const char *, int);
static void *fixture_dlsym(void *, const char *);
static int fixture_dlclose(void *);
static int fixture_lstat(const char *, struct stat *);
#define dlopen(...) fixture_dlopen(__VA_ARGS__)
#define dlsym(...) fixture_dlsym(__VA_ARGS__)
#define dlclose(...) fixture_dlclose(__VA_ARGS__)
#define lstat(...) fixture_lstat(__VA_ARGS__)
#include "../ThreeOneOSFive/exploit/worse_query.m"
#undef dlopen
#undef dlsym
#undef dlclose
#undef lstat

static NSURL *groupRoot;
static BOOL groupAvailable = YES, libraryAvailable = YES, rejectQuery = NO, refuseToken = NO;
static BOOL failCreate = NO, missingSymbol = NO;
static BOOL throwGroupException = NO;
static int statError = EACCES;
static int64_t consumedHandle = 42, releasedHandle = -1;
static NSUInteger created = 0, freed = 0, activeQueries = 0;
static NSUInteger opened = 0, closed = 0;
static uint64_t lastFlags = 0;
static NSString *groupID = @"group.astra.native.fixture";

@interface NSFileManager (AstraQueryFixture)
- (NSURL *)astra_fixtureGroup:(NSString *)identifier;
@end
@implementation NSFileManager (AstraQueryFixture)
- (NSURL *)astra_fixtureGroup:(NSString *)identifier {
    if (throwGroupException) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"fixture: re-signed group denied" userInfo:nil];
    return groupAvailable && [identifier isEqualToString:groupID] ? groupRoot : nil;
}
@end

typedef struct { uint64_t klass, part, flags; } FixtureQuery;
static void *createQuery(void) {
    if (failCreate) return NULL;
    created++; activeQueries++;
    NSCAssert(activeQueries == 1, @"queries using the same Caches link overlapped");
    return calloc(1, sizeof(FixtureQuery));
}
static void setClass(void *query, uint64_t value) { ((FixtureQuery *)query)->klass = value; }
static void setPart(void *query, uint64_t value) { ((FixtureQuery *)query)->part = value; }
static void setFlags(void *query, uint64_t value) { ((FixtureQuery *)query)->flags = value; lastFlags = value; }
static void setGroup(void *query, xpc_object_t value) {
    NSCAssert(strcmp(xpc_string_get_string_ptr(value), groupID.UTF8String) == 0, @"wrong App Group identifier");
}
static void *getResult(void *query) {
    FixtureQuery *q = query;
    NSCAssert(q->klass == 7 && q->part == 3, @"query does not match upstream class/part");
    NSCAssert(q->flags == 0x0000000800000000ULL || q->flags == 0x0000008000000000ULL, @"wrong token flags");
    NSString *cache = [groupRoot.path stringByAppendingPathComponent:@"Library/Caches"];
    NSString *destination = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:cache error:NULL];
    NSCAssert([destination hasPrefix:@"/private/var/mobile/Containers/"], @"query was sent before the target link existed");
    usleep(1000);
    return rejectQuery ? NULL : query;
}
static void freeQuery(void *query) { free(query); freed++; activeQueries--; }
static char *copyToken(void *query) { return refuseToken ? NULL : strdup("fixture-token"); }
static int64_t consumeToken(const char *token) {
    NSCAssert(activeQueries == 1, @"query was freed before token consumption");
    NSCAssert(strcmp(token, "fixture-token") == 0, @"token bytes changed");
    return consumedHandle;
}
static int releaseToken(int64_t handle) { releasedHandle = handle; return 0; }

static void *fixture_dlopen(const char *path, int flags) {
    if (!libraryAvailable) return NULL;
    opened++; return (void *)1;
}
static int fixture_dlclose(void *handle) { closed++; return 0; }
static int fixture_lstat(const char *path, struct stat *value) {
    if (statError) { errno = statError; return -1; }
    memset(value, 0, sizeof(*value)); return 0;
}
static void *fixture_dlsym(void *handle, const char *name) {
    if (missingSymbol && strcmp(name, "container_query_create") == 0) return NULL;
    if (strcmp(name, "container_query_create") == 0) return (void *)createQuery;
    if (strcmp(name, "container_query_set_class") == 0) return (void *)setClass;
    if (strcmp(name, "container_query_set_group_identifiers") == 0) return (void *)setGroup;
    if (strcmp(name, "container_query_operation_set_flags") == 0) return (void *)setFlags;
    if (strcmp(name, "container_query_operation_set_part") == 0) return (void *)setPart;
    if (strcmp(name, "container_query_get_single_result") == 0) return (void *)getResult;
    if (strcmp(name, "container_query_free") == 0) return (void *)freeQuery;
    if (strcmp(name, "container_copy_sandbox_token") == 0) return (void *)copyToken;
    if (strcmp(name, "sandbox_extension_consume") == 0) return (void *)consumeToken;
    if (strcmp(name, "sandbox_extension_release") == 0) return (void *)releaseToken;
    return NULL;
}

static void checkClean(void) {
    NSString *cache = [groupRoot.path stringByAppendingPathComponent:@"Library/Caches"];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:cache error:NULL];
    NSCAssert([attributes[NSFileType] isEqual:NSFileTypeDirectory], @"Caches link was not restored to a directory");
    NSCAssert(created == freed && activeQueries == 0, @"query resources leaked");
    NSCAssert(opened == closed, @"library handle leaked");
}

int main(void) {
    @autoreleasepool {
        NSFileManager *files = [NSFileManager defaultManager];
        NSURL *base = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
            [@"astra-wq-native-" stringByAppendingString:NSUUID.UUID.UUIDString]]];
        groupRoot = [base URLByAppendingPathComponent:@"group"];
        [files createDirectoryAtURL:[groupRoot URLByAppendingPathComponent:@"Library/Caches"]
            withIntermediateDirectories:YES attributes:nil error:NULL];
        Method original = class_getInstanceMethod(object_getClass(files), @selector(containerURLForSecurityApplicationGroupIdentifier:));
        Method replacement = class_getInstanceMethod(NSFileManager.class, @selector(astra_fixtureGroup:));
        method_exchangeImplementations(original, replacement);
        @try {
            NSString *target = @"/private/var/mobile/Containers/Data/Application/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA";
            NSCAssert(worse_query_group_path(groupID) != nil, @"valid App Group lookup failed");
            throwGroupException = YES;
            NSCAssert(worse_query_group_path(groupID) == nil, @"Foundation exception escaped into Swift");
            NSCAssert(worse_query(target, groupID, NO, NO) == -1, @"native query did not handle group exception");
            throwGroupException = NO;
            NSCAssert(worse_query(target, groupID, NO, NO) == 42, @"EACCES prevented token acquisition");
            NSCAssert(lastFlags == 0x0000008000000000ULL, @"default flag differs from upstream");
            checkClean();
            statError = EPERM;
            NSCAssert(worse_query(target, groupID, YES, NO) == 42, @"EPERM prevented token acquisition");
            NSCAssert(lastFlags == 0x0000000800000000ULL, @"alternate flag differs from upstream");
            statError = ENOENT;
            NSUInteger prior = created;
            NSCAssert(worse_query(target, groupID, NO, NO) == -255 && prior == created, @"nonexistent target reached query");
            NSCAssert(worse_query(target, groupID, NO, YES) == 42, @"create_dir did not skip the existence precheck");
            statError = EACCES;
            groupAvailable = NO;
            NSCAssert(worse_query(target, groupID, NO, NO) == -1, @"missing App Group not reported");
            groupAvailable = YES; libraryAvailable = NO;
            NSCAssert(worse_query(target, groupID, NO, NO) == -2, @"missing library not reported");
            libraryAvailable = YES; missingSymbol = YES;
            NSCAssert(worse_query(target, groupID, NO, NO) == -2, @"missing symbol not reported");
            missingSymbol = NO; failCreate = YES;
            NSCAssert(worse_query(target, groupID, NO, NO) == -3, @"query creation error not reported");
            checkClean(); failCreate = NO; rejectQuery = YES;
            NSCAssert(worse_query(target, groupID, NO, NO) == -5, @"query rejection not propagated");
            checkClean(); rejectQuery = NO; refuseToken = YES;
            NSCAssert(worse_query(target, groupID, NO, NO) == -6, @"missing token not propagated");
            checkClean(); refuseToken = NO; consumedHandle = -1;
            NSCAssert(worse_query(target, groupID, NO, NO) == -7, @"consume failure was confused with a missing group");
            checkClean(); consumedHandle = 0;
            NSCAssert(worse_query(target, groupID, NO, NO) == 0, @"zero is a valid nonnegative handle");
            worse_query_release(0);
            NSCAssert(releasedHandle == 0, @"zero handle was not released");
            worse_query_release(-1);
            NSCAssert(releasedHandle == 0, @"negative handle reached release API");
            NSURL *validGroup = groupRoot;
            groupRoot = [base URLByAppendingPathComponent:@"not-a-directory"];
            [@"fixture" writeToURL:groupRoot atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            NSCAssert(worse_query(target, groupID, NO, NO) == -4, @"symlink failure was not reported");
            NSCAssert(created == freed, @"symlink failure leaked a query");
            groupRoot = validGroup; consumedHandle = 42;
            dispatch_apply(12, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t index) {
                @autoreleasepool {
                    NSString *path = [target stringByAppendingFormat:@"-%zu", index];
                    NSCAssert(worse_query(path, groupID, NO, NO) == 42, @"parallel query failed");
                }
            });
            checkClean();
            puts("[PASS] production worse_query C: query/flags/link order, denied stat, cleanup, errors, zero handle, release and serialization");
        } @finally {
            method_exchangeImplementations(original, replacement);
            [files removeItemAtURL:base error:NULL];
        }
    }
    return 0;
}
