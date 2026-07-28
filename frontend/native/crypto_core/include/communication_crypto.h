#ifndef COMMUNICATION_CRYPTO_H
#define COMMUNICATION_CRYPTO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CP_CRYPTO_V1_ABI_VERSION UINT32_C(1)
#define CP_CRYPTO_V1_CAPABILITIES_SIZE UINT32_C(32)

typedef enum cp_crypto_status_v1 {
  CP_CRYPTO_OK = 0,
  CP_CRYPTO_INVALID_ARGUMENT = 1,
  CP_CRYPTO_INPUT_TOO_LARGE = 2,
  CP_CRYPTO_OUTPUT_TOO_SMALL = 3,
  CP_CRYPTO_MALFORMED_INPUT = 4,
  CP_CRYPTO_INVALID_HANDLE = 5,
  CP_CRYPTO_WRONG_HANDLE_TYPE = 6,
  CP_CRYPTO_AUTHENTICATION_FAILED = 7,
  CP_CRYPTO_UNSUPPORTED_VERSION = 8,
  CP_CRYPTO_UNSUPPORTED_OPERATION = 9,
  CP_CRYPTO_RESOURCE_EXHAUSTED = 10,
  CP_CRYPTO_ENTROPY_UNAVAILABLE = 11,
  CP_CRYPTO_STATE_VIOLATION = 12,
  CP_CRYPTO_INTERNAL_FAILURE = 13,
  CP_CRYPTO_PANIC_CONTAINED = 14
} cp_crypto_status_v1;

typedef struct cp_crypto_capabilities_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  uint64_t feature_bits;
  uint32_t max_input_bytes;
  uint32_t max_cbor_depth;
  uint32_t max_cbor_items;
  uint32_t reserved;
} cp_crypto_capabilities_v1;

uint32_t cp_crypto_v1_abi_version(void);
int32_t cp_crypto_v1_capabilities(
    cp_crypto_capabilities_v1* output,
    uintptr_t output_len);
int32_t cp_crypto_v1_self_test(void);

#ifdef __cplusplus
}
#endif

#endif /* COMMUNICATION_CRYPTO_H */
