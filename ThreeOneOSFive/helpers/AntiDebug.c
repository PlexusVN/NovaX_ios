#include <sys/types.h>
#include <unistd.h>
#include <stdint.h>
#include <dlfcn.h>
#include "AntiDebug.h"

// MARK: - Manual declarations (not in iOS SDK headers, available at runtime)

typedef int (*csops_fn)(pid_t, uint32_t, void*, size_t);

#define CS_VALID 0x00000001

// MARK: - ptrace REMOVED
// ptrace(PT_DENY_ATTACH) via dlsym crashes after KSign re-signing
// because the kernel detects code signature inconsistency.
// Use sysctl-based debugger detection in Swift instead (read-only, safe).

// MARK: - Code Signature Validation via csops (crash-safe)

int check_code_signature_valid(void) {
    // After KSign re-signing, csops may return unexpected results.
    // Use fail-open: if anything goes wrong, report as valid.
    void* handle = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_NOW);
    if (!handle) return 1;

    csops_fn fn = (csops_fn)dlsym(handle, "csops");
    if (!fn) return 1;

    uint32_t flags = 0;
    // csops can fail after re-signing — treat failure as valid (fail-open)
    int result = fn(getpid(), CS_VALID, &flags, sizeof(flags));
    // do NOT dlclose

    if (result != 0) return 1;  // csops failed — fail-open
    return (flags & CS_VALID) != 0;
}
