#ifndef __RSA_H__
#define __RSA_H__

#include <stdint.h>
#include "lcrypt.h"

//big number
#define BIGNUM_DIGIT_BITS       32      // For uint32_t
#define BIGNUM_MAX_DIGITS       65      // RSA_MAX_MODULUS_LEN + 1
#define BIGNUM_MAX_DIGIT        0xFFFFFFFF
#define DIGIT_2MSB(x)           (uint32_t)(((x) >> (BIGNUM_DIGIT_BITS - 2)) & 0x03)

// RSA key lengths
#define RSA_MAX_MODULUS_BITS    1024
#define RSA_MAX_MODULUS_LEN     ((RSA_MAX_MODULUS_BITS + 7) / 8)
#define RSA_MAX_PRIME_BITS      ((RSA_MAX_MODULUS_BITS + 1) / 2)
#define RSA_MAX_PRIME_LEN       ((RSA_MAX_PRIME_BITS + 7) / 8)
#define RSA_EXPONENT_POS        RSA_MAX_MODULUS_LEN - 3

#define RSA_PEM_SEQUENCE        0x30
#define RSA_PEM_INTEGER         0x02

// Error codes
#define ERR_WRONG_DATA          0x1001
#define ERR_WRONG_LEN           0x1002

typedef uint32_t bignum_t;
typedef uint64_t bignum_dt;

void bignum_assign(bignum_t *a, bignum_t *b, uint32_t digits);                                  // a = b
void bignum_assign_zero(bignum_t *a, uint32_t digits);                                          // a = 0

int bignum_cmp(bignum_t *a, bignum_t *b, uint32_t digits);                                      // returns sign of a - b
uint32_t bignum_digits(bignum_t *a, uint32_t digits);                                           // returns significant length of a in digits

bignum_t bignum_add(bignum_t *a, bignum_t *b, bignum_t *c, uint32_t digits);                    // a = b + c, return carry
bignum_t bignum_sub(bignum_t *a, bignum_t *b, bignum_t *c, uint32_t digits);                    // a = b - c, return borrow
bignum_t bignum_shift_l(bignum_t *a, bignum_t *b, uint32_t c, uint32_t digits);                 // a = b << c (a = b * 2^c)
bignum_t bignum_shift_r(bignum_t *a, bignum_t *b, uint32_t c, uint32_t digits);                 // a = b >> c (a = b / 2^c)

void bignum_mul(bignum_t *a, bignum_t *b, bignum_t *c, uint32_t digits);                                        // a = b * c
void bignum_div(bignum_t *a, bignum_t *b, bignum_t *c, uint32_t cdigits, bignum_t *d, uint32_t ddigits);        // a = b / c, d = b % c
void bignum_mod(bignum_t *a, bignum_t *b, uint32_t bdigits, bignum_t *c, uint32_t cdigits);                     // a = b mod c
void bignum_mod_mul(bignum_t *a, bignum_t *b, bignum_t *c, bignum_t *d, uint32_t digits);                       // a = b * c mod d
void bignum_mod_exp(bignum_t *a, bignum_t *b, bignum_t *c, uint32_t cdigits, bignum_t *d, uint32_t ddigits);    // a = b ^ c mod d

uint32_t bignum_digit_bits(bignum_t a);
bignum_t bignum_sub_digit_mul(bignum_t *a, bignum_t *b, bignum_t c, bignum_t *d, uint32_t digits);
bignum_t bignum_add_digit_mul(bignum_t *a, bignum_t *b, bignum_t c, bignum_t *d, uint32_t digits);

#define BIGNUM_ASSIGN_DIGIT(a, b, digits)   {bignum_assign_zero(a, digits); a[0] = b;}

//RSA struct
typedef struct _rsa_pk_t {
    uint32_t bits;
    uint8_t  modulus[RSA_MAX_MODULUS_LEN];
    uint8_t  exponent[RSA_MAX_MODULUS_LEN];
} rsa_pk_t;

typedef struct _rsa_sk_t {
    uint32_t bits;
    uint8_t  modulus[RSA_MAX_MODULUS_LEN];
    uint8_t  public_exponet[RSA_MAX_MODULUS_LEN];
    uint8_t  exponent[RSA_MAX_MODULUS_LEN];
    uint8_t  prime1[RSA_MAX_PRIME_LEN];
    uint8_t  prime2[RSA_MAX_PRIME_LEN];
    uint8_t  prime_exponent1[RSA_MAX_PRIME_LEN];
    uint8_t  prime_exponent2[RSA_MAX_PRIME_LEN];
    uint8_t  coefficient[RSA_MAX_PRIME_LEN];
} rsa_sk_t;

int public_block_operation(uint8_t *out, uint32_t *out_len, uint8_t *in, uint32_t in_len);
int private_block_operation(uint8_t *out, uint32_t *out_len, uint8_t *in, uint32_t in_len);

int rsa_public_encrypt (uint8_t *out, uint32_t *out_len, uint8_t *in, uint32_t in_len);
int rsa_public_decrypt (uint8_t *out, uint32_t *out_len, uint8_t *in, uint32_t in_len);
int rsa_private_encrypt(uint8_t *out, uint32_t *out_len, uint8_t *in, uint32_t in_len);
int rsa_private_decrypt(uint8_t *out, uint32_t *out_len, uint8_t *in, uint32_t in_len);

int rsa_init_public_key (uint8_t *pem, uint32_t pem_len);
int rsa_init_private_key (uint8_t *pem, uint32_t pem_len);

#endif  // __RSA_H__
