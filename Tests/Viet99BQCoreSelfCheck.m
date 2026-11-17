#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <dirent.h>
#include <string.h>

static NSMutableArray<NSNumber *> *events;
static uint64_t cls;
static int64_t class13Result, class7Result, class12Result;
static BOOL readable, throwsQuery;
static NSUInteger queryFrees, identityFrees, releases, consumed;
static void *Create(void) { return (void *)1; }
static void SetClass(void *q, uint64_t value) { cls = value; [events addObject:@(value)]; }
static void SetPart(void *q, uint64_t value) { NSCAssert(value == 3, @"wrong part"); }
static void SetFlags(void *q, uint64_t value) { NSCAssert(value == 0x8100000000ULL, @"wrong donor flags"); }
static void SetID(void *q, void *value) { NSCAssert(value == (void *)3, @"wrong identifier"); }
static void SetDomain(void *q, const char *value) { NSCAssert(strstr(value, "../../") == value, @"missing donor traversal"); }
static void *Result(void *q) {
    if (throwsQuery) @throw [NSException exceptionWithName:@"Fixture" reason:@"query" userInfo:nil];
    return (cls == 13 ? class13Result : class12Result) >= 0 ? (void *)2 : NULL;
}
static char *Token(void *r) { return strdup("fixture-token-never-used-on-device"); }
static int64_t Consume(const char *t) { consumed++; return cls == 13 ? class13Result : class12Result; }
static int Release(int64_t h) { releases++; return 0; }
static void FreeQuery(void *q) { queryFrees++; }
static void *XPCString(const char *s) { return (void *)3; }
static void FreeIdentity(void *x) { identityFrees++; }
static void *OpenLibrary(const char *p, int flags) { return (void *)4; }
static int CloseLibrary(void *p) { return 0; }
static void *Symbol(void *h, const char *name) {
    if (!strcmp(name, "container_query_create")) return (void *)Create;
    if (!strcmp(name, "container_query_set_class")) return (void *)SetClass;
    if (!strcmp(name, "container_query_operation_set_part")) return (void *)SetPart;
    if (!strcmp(name, "container_query_operation_set_flags")) return (void *)SetFlags;
    if (!strcmp(name, "container_query_operation_set_part_domain")) return (void *)SetDomain;
    if (!strcmp(name, "container_query_set_group_identifiers") || !strcmp(name, "container_query_set_identifiers")) return (void *)SetID;
    if (!strcmp(name, "container_query_get_single_result")) return (void *)Result;
    if (!strcmp(name, "container_copy_sandbox_token")) return (void *)Token;
    if (!strcmp(name, "container_query_free")) return (void *)FreeQuery;
    if (!strcmp(name, "sandbox_extension_consume")) return (void *)Consume;
    if (!strcmp(name, "sandbox_extension_release")) return (void *)Release;
    if (!strcmp(name, "xpc_string_create")) return (void *)XPCString;
    if (!strcmp(name, "xpc_release")) return (void *)FreeIdentity;
    return NULL;
}
static int Stat(const char *p, struct stat *s) { memset(s, 0, sizeof(*s)); s->st_mode = S_IFDIR; return 0; }
static DIR *OpenDirectory(const char *p) { return readable ? (DIR *)5 : NULL; }
static int CloseDirectory(DIR *d) { return 0; }
NSString *worse_query_group_path(NSString *group) { return group.length ? @"/fixture/group" : nil; }
int64_t worse_query(NSString *target, NSString *group, bool alt, bool create) {
    [events addObject:@7]; NSCAssert(!alt && !create, @"unexpected broad mode"); return class7Result;
}
void worse_query_release(int64_t h) { releases++; }

#define dlopen OpenLibrary
#define dlclose CloseLibrary
#define dlsym Symbol
#define lstat Stat
#define opendir OpenDirectory
#define closedir CloseDirectory
#include "../ThreeOneOSFive/exploit/Viet99BQCore.m"
#undef dlopen
#undef dlclose
#undef dlsym
#undef lstat
#undef opendir
#undef closedir

static void Reset(void) {
    events = [NSMutableArray array]; class13Result = class7Result = class12Result = -5;
    readable = YES; throwsQuery = NO; queryFrees = identityFrees = releases = consumed = 0;
}

int main(void) {
    @autoreleasepool {
        NSString *target = @"/private/var/mobile/Containers/Data/Application/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA";
        NSCAssert(AstraBQAcquireAccess(target, @"group.fixture") == -8, @"main-thread request allowed");
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                Reset(); class13Result = 11;
                NSCAssert(AstraBQAcquireAccess(target, @"group.fixture") == 11 && [events isEqual:@[@13]], @"class13 route failed");
                NSCAssert(queryFrees == 1 && identityFrees == 1 && releases == 0, @"success lifetime incorrect");
                Reset(); class7Result = 22;
                NSCAssert((AstraBQAcquireAccess(target, @"group.fixture") == 22 && [events isEqual:@[@13,@7]]), @"class7 order incorrect");
                Reset(); class12Result = 33;
                NSCAssert((AstraBQAcquireAccess(target, @"group.fixture") == 33 && [events isEqual:@[@13,@7,@12]]), @"class12 fallback missing");
                NSCAssert(queryFrees == 2 && identityFrees == 2, @"query/identifier cleanup incomplete");
                Reset(); readable = NO; class13Result = 11; class7Result = 22; class12Result = 33;
                NSCAssert(AstraBQAcquireAccess(target, @"group.fixture") < 0 && releases == 3, @"unreadable token treated as ready");
                Reset(); class7Result = -4;
                NSCAssert((AstraBQAcquireAccess(target, @"group.fixture") == -4 && [events isEqual:@[@13,@7]]), @"cache repair error bypassed");
                Reset(); throwsQuery = YES;
                NSCAssert(AstraBQAcquireAccess(target, @"group.fixture") == -8 && queryFrees == 1 && identityFrees == 1, @"exception lifetime incorrect");
                for (NSString *bad in @[@"/", @"/var/mobile/Containers/Data/Application", @"/etc/passwd",
                    @"/var/mobile/Containers/Data/Application/invalid", [target stringByAppendingString:@"/Documents"]]) {
                    Reset(); NSCAssert(AstraBQAcquireAccess(bad, @"group.fixture") == -10 && events.count == 0, @"broad scope allowed");
                }
                Reset(); NSCAssert(AstraBQAcquireAccess(target, @"") == -1 && events.count == 0, @"missing group allowed");
                puts("[PASS] Viet99 production adapter: strategy order, scoped roots, real read boundary, query/XPC ownership, exception and repair failures");
            }
            dispatch_semaphore_signal(done);
        });
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    }
    return 0;
}
