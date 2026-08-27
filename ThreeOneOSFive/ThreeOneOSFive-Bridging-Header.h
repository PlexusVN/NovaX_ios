#import "exploit/bad_query.h"
#import "exploit/mcm_bridge.h"
#import "kexploit/kexploit_opa334.h"
#import "kexploit/sandbox_escape.h"
#import "kexploit/kutils.h"
#import "helpers/AppIconHelper.h"
#import "helpers/DisplayIdentity.h"
#import "helpers/AntiDebug.h"

extern int csops(unsigned int pid, unsigned int ops, void *useraddr, size_t usersize);
#define CS_VALID 0x00000001
