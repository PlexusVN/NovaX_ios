#ifndef AntiDebug_h
#define AntiDebug_h

// Anti-debug via dlsym ptrace (iOS 26 compatible)
void prevent_debugger_attach(void);

// Code signature validation via csops CS_VALID
int check_code_signature_valid(void);

#endif
