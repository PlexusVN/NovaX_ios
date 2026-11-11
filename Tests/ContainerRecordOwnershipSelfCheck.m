// Isolated Foundation fixtures; the production functions are inserted below.
#import <assert.h>

static NSUInteger mode;
static NSUInteger allocations;
static NSUInteger deallocations;
static NSDictionary *fallback;
static NSString * const validPath = @"/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555";
static NSString * const canonicalPath = @"/private/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555";

static void ensureLaunchServicesLoaded(void) {}
static NSDictionary *installedAppInfo(void) { return fallback ?: @{}; }

@interface AstraCrashFixtureProxy : NSObject
+ (id)applicationProxyForIdentifier:(NSString *)identifier;
@end
@implementation AstraCrashFixtureProxy
+ (id)applicationProxyForIdentifier:(NSString *)identifier { return nil; }
@end

@interface AstraCrashFixtureReplacement : NSObject
- (NSURL *)dataContainerURL;
@end
@implementation AstraCrashFixtureReplacement
- (NSURL *)dataContainerURL { return [NSURL fileURLWithPath:validPath]; }
@end

@interface AstraCrashFixtureRecord : NSObject <AstraApplicationRecordInitializing>
- (NSURL *)dataContainerURL;
@end
@implementation AstraCrashFixtureRecord
- (instancetype)initWithBundleIdentifier:(NSString *)identifier
                        allowPlaceholder:(BOOL)allowPlaceholder
                                   error:(NSError *__autoreleasing *)error {
    self = [super init];
    if (!self) return nil;
    allocations++;
    assert([identifier isEqualToString:@"fixture.missing.game"]);
    assert(!allowPlaceholder);
    if (mode == 0) {
        if (error) *error = [NSError errorWithDomain:@"fixture" code:404 userInfo:nil];
        return nil;
    }
    if (mode == 2) return (id)[AstraCrashFixtureReplacement new];
    if (mode == 3) @throw [NSException exceptionWithName:@"FixtureFailure" reason:@"missing record" userInfo:nil];
    return self;
}
- (NSURL *)dataContainerURL {
    return [NSURL fileURLWithPath:mode == 4 ? @"/var/mobile/Containers/Data/Application/not-a-uuid" : validPath];
}
- (void)dealloc { deallocations++; }
@end

// ACTUAL PRODUCTION RESOLVER

int main(void) {
    @autoreleasepool {
        for (mode = 0; mode < 5; mode++) {
            for (NSUInteger i = 0; i < 1000; i++) {
                @autoreleasepool {
                    // Even failure paths must retain the existing installed-app
                    // fallback. Alternating this also exercises nil cleanup.
                    fallback = i % 2 == 0 ? @{@"fixture.missing.game": @{@"container": validPath}} : nil;
                    NSString *result = containerPathForBundleID(@"fixture.missing.game");
                    BOOL expected = mode == 1 || mode == 2 || fallback != nil;
                    assert(expected ? [result isEqualToString:canonicalPath] : result == nil);
                    fallback = nil;
                }
                assert(allocations == deallocations);
            }
        }
        assert(allocations == 5000);
        puts("[PASS] actual container resolver ARC ownership: 5000 cases (nil/error, self, replacement, exception, invalid path, installed-app fallback)");
    }
    return 0;
}
