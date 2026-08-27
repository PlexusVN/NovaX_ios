#include <sys/types.h>

// MARK: - Anti-Debug via ARM64 SVC
// Calls ptrace(PT_DENY_ATTACH) directly via syscall
// Bypasses libc → Frida cannot hook this

void prevent_debugger_attach(void) {
#if !DEBUG
    __asm__ __volatile__(
        "mov x0, #26\n"    // SYS_PTRACE
        "mov x1, #31\n"    // PT_DENY_ATTACH
        "mov x2, #0\n"
        "mov x3, #0\n"
        "mov x4, #0\n"
        "svc #0x80\n"
        ::: "x0","x1","x2","x3","x4"
    );
#endif
}
