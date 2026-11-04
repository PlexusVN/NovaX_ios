#include "IntegrityAnchor.h"

#define ASTRA_HASH_PREFIX "ASTRA_HASH_MARKER:"

__attribute__((used, visibility("hidden")))
static const char kAstraIntegrityAnchor[] =
    ASTRA_HASH_PREFIX
    "0000000000000000000000000000000000000000000000000000000000000000";

const char *AstraExpectedTextHash(void) {
    return kAstraIntegrityAnchor + (sizeof(ASTRA_HASH_PREFIX) - 1);
}
