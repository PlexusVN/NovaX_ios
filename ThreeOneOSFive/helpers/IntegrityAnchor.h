#ifndef ASTRA_INTEGRITY_ANCHOR_H
#define ASTRA_INTEGRITY_ANCHOR_H

#ifdef __cplusplus
extern "C" {
#endif

/// Returns the 64-byte lowercase SHA-256 hex string embedded after linking and
/// before code signing. The backing anchor is deliberately outside __text so
/// replacing the placeholder does not change the measured section.
const char *AstraExpectedTextHash(void);

#ifdef __cplusplus
}
#endif

#endif
