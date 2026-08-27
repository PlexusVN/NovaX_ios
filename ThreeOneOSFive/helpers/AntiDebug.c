#include <sys/types.h>
#include <unistd.h>
#include <stdint.h>
#include <dlfcn.h>
#include "AntiDebug.h"

// MARK: - Manual declarations (not in iOS SDK headers, available at runtime)

typedef int (*ptrace_fn)(int, int, void*, int);
typedef int (*csops_fn)(pid_t, uint32_t, void*, size_t);

#define PT_DENY_ATTACH 31
#define CS_VALID 0x00000001

// MARK: - Anti-Debug: ptrace(PT_DENY_ATTACH) via dlsym

void prevent_debugger_attach(void) {
#if !DEBUG
    void* handle = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_NOW);
    if (!handle) return;
    ptrace_fn fn = (ptrace_fn)dlsym(handle, "ptrace");
    if (fn) {
        fn(PT_DENY_ATTACH, 0, 0, 0);
    }
    // do NOT dlclose — kernel retains reference, closing causes crash on iOS 26
#endif
}

// MARK: - Code Signature Validation via csops

int check_code_signature_valid(void) {
    void* handle = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_NOW);
    if (!handle) return 1;
    csops_fn fn = (csops_fn)dlsym(handle, "csops");
    if (!fn) return 1;
    uint32_t flags = 0;
    int result = fn(getpid(), CS_VALID, &flags, sizeof(flags));
    // do NOT dlclose
    if (result != 0) return 1; // csops not available or failed — fail-open
    return (flags & CS_VALID) != 0;
}
