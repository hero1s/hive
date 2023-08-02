#include <string.h>
#include <stdio.h>
#include <time.h>
#include <stdlib.h>

#include "rsa.h"

static rsa_sk_t * sk = NULL;
static rsa_pk_t * pk = NULL;

// bignum interface
//-----------------------------------------------------------------------------
void bignum_decode(bignum_t *bn, uint32_t digits, uint8_t *hexarr, uint32_t size) {
    int j;
    bignum_t t;
    uint32_t i, u;
    for(i=0,j=size-1; i<digits && j>=0; i++) {
        t = 0;
        for(u=0; j>=0 && u<BIGNUM_DIGIT_BITS; j--, u+=8) {
            t |= ((bignum_t)hexarr[j]) << u;
        }
        bn[i] = t;
    }
    for(; i<digits; i++) bn[i] = 0;
}

void bignum_encode(uint8_t *hexarr, uint32_t size, bignum_t *bn, uint32_t digits) {
    int j;
    bignum_t t;
    uint32_t i, u;
    for(i=0,j=size-1; i<digits && j>=0; i++) {
        t = bn[i];
        for(u=0; j>=0 && u<BIGNUM_DIGIT_BITS; j--, u+=8) {
            hexarr[j] = (uint8_t)(t >> u);
        }
    }
    for(; j>=0; j--) hexarr[j] = 0;
}


void bignum_assign(bignum_t *a, bignum_t *b, uint32_t digits) {
    uint32_t i;
    for(i=0; i<digits; i++) a[i] = b[i];
}

void bignum_assign_zero(bignum_t *a, uint32_t digits) {
    uint32_t i;
    for(i=0; i<digits; i++) a[i] = 0;
}

bignum_t bignum_add(bignum_t *a, bignum_t *b, bignum_t *c, uint32_t digits) {
    uint32_t i;
    bignum_t ai;
    bignum_t carry = 0;
    for(i=0; i<digits; i++) {
        if((ai = b[i] + carry) < carry) {
            ai = c[i];
        } else if((ai += c[i]) < c[i]) {
            carry = 1;
        } else {
            carry = 0;
        }
        a[i] = ai;
    }
    return carry;
}

bignum_t bignum_sub(bignum_t *a, bignum_t *b, bignum_t *c, uint32_t digits) {
    uint32_t i;
    bignum_t ai;
    bignum_t borrow = 0;
    for(i=0; i<digits; i++) {
        if((ai = b[i] - borrow) > (BIGNUM_MAX_DIGIT - borrow)) {
            ai = BIGNUM_MAX_DIGIT - c[i];
        } else if((ai -= c[i]) > (BIGNUM_MAX_DIGIT - c[i])) {
            borrow = 1;
        } else {
            borrow = 0;
        }
        a[i] = ai;
    }
    return borrow;
}

void bignum_mul(bignum_t *a, bignum_t *b, bignum_t *c, uint32_t digits) {
    uint32_t bdigits, cdigits, i;
    bignum_t t[2*BIGNUM_MAX_DIGITS];
    bignum_assign_zero(t, 2*digits);
    bdigits = bignum_digits(b, digits);
    cdigits = bignum_digits(c, digits);

    for(i=0; i<bdigits; i++) {
        t[i+cdigits] += bignum_add_digit_mul(&t[i], &t[i], b[i], c, cdigits);
    }
    bignum_assign(a, t, 2*digits);
    // Clear potentially sensitive information
    memset((uint8_t *)t, 0, sizeof(t));
}

void bignum_div(bignum_t *a, bignum_t *b, bignum_t *c, uint32_t cdigits, bignum_t *d, uint32_t ddigits) {
    int i;
    bignum_dt tmp;
    bignum_t ai, t, cc[2*BIGNUM_MAX_DIGITS+1], dd[BIGNUM_MAX_DIGITS];

    uint32_t dddigits = bignum_digits(d, ddigits);
    if(dddigits == 0)
        return;

    uint32_t shift = BIGNUM_DIGIT_BITS - bignum_digit_bits(d[dddigits-1]);
    bignum_assign_zero(cc, dddigits);
    cc[cdigits] = bignum_shift_l(cc, c, shift, cdigits);
    bignum_shift_l(dd, d, shift, dddigits);
    t = dd[dddigits-1];

    bignum_assign_zero(a, cdigits);
    i = cdigits - dddigits;
    for(; i>=0; i--) {
        if(t == BIGNUM_MAX_DIGIT) {
            ai = cc[i+dddigits];
        } else {
            tmp = cc[i+dddigits-1];
            tmp += (bignum_dt)cc[i+dddigits] << BIGNUM_DIGIT_BITS;
            ai = tmp / (t + 1);
        }
        cc[i+dddigits] -= bignum_sub_digit_mul(&cc[i], &cc[i], ai, dd, dddigits);
        // printf("cc[%d]: %08X\n", i, cc[i+dddigits]);
        while(cc[i+dddigits] || (bignum_cmp(&cc[i], dd, dddigits) >= 0)) {
            ai++;
            cc[i+dddigits] -= bignum_sub(&cc[i], &cc[i], dd, dddigits);
        }
        a[i] = ai;
        // printf("ai[%d]: %08X\n", i, ai);
    }
    bignum_assign_zero(b, ddigits);
    bignum_shift_r(b, cc, shift, dddigits);
    // Clear potentially sensitive information
    memset((uint8_t *)cc, 0, sizeof(cc));
    memset((uint8_t *)dd, 0, sizeof(dd));
}

bignum_t bignum_shift_l(bignum_t *a, bignum_t *b, uint32_t c, uint32_t digits) {
    uint32_t i, t;
    bignum_t bi, carry;
    if(c >= BIGNUM_DIGIT_BITS)
        return 0;

    t = BIGNUM_DIGIT_BITS - c;
    carry = 0;
    for(i=0; i<digits; i++) {
        bi = b[i];
        a[i] = (bi << c) | carry;
        carry = c ? (bi >> t) : 0;
    }
    return carry;
}

bignum_t bignum_shift_r(bignum_t *a, bignum_t *b, uint32_t c, uint32_t digits) {
    if(c >= BIGNUM_DIGIT_BITS)
        return 0;
    bignum_t bi;
    uint32_t t = BIGNUM_DIGIT_BITS - c;
    bignum_t carry = 0;
    int i = digits - 1;
    for(; i>=0; i--) {
        bi = b[i];
        a[i] = (bi >> c) | carry;
        carry = c ? (bi << t) : 0;
    }
    return carry;
}

void bignum_mod(bignum_t *a, bignum_t *b, uint32_t bdigits, bignum_t *c, uint32_t cdigits) {
    bignum_t t[2*BIGNUM_MAX_DIGITS] = {0};
    bignum_div(t, a, b, bdigits, c, cdigits);
    memset((uint8_t *)t, 0, sizeof(t));
}

void bignum_mod_mul(bignum_t *a, bignum_t *b, bignum_t *c, bignum_t *d, uint32_t digits) {
    bignum_t t[2*BIGNUM_MAX_DIGITS];
    bignum_mul(t, b, c, digits);
    bignum_mod(a, t, 2*digits, d, digits);
    memset((uint8_t *)t, 0, sizeof(t));
}

void bignum_mod_exp(bignum_t *a, bignum_t *b, bignum_t *c, uint32_t cdigits, bignum_t *d, uint32_t ddigits) {
    uint32_t ci_bits, j, s;
    bignum_t bpower[3][BIGNUM_MAX_DIGITS], ci, t[BIGNUM_MAX_DIGITS];
    bignum_assign(bpower[0], b, ddigits);
    bignum_mod_mul(bpower[1], bpower[0], b, d, ddigits);
    bignum_mod_mul(bpower[2], bpower[1], b, d, ddigits);
    BIGNUM_ASSIGN_DIGIT(t, 1, ddigits);
    cdigits = bignum_digits(c, cdigits);
    int i = cdigits - 1;
    for(; i>=0; i--) {
        ci = c[i];
        ci_bits = BIGNUM_DIGIT_BITS;
        if(i == (int)(cdigits - 1)) {
            while(!DIGIT_2MSB(ci)) {
                ci <<= 2;
                ci_bits -= 2;
            }
        }
        for(j=0; j<ci_bits; j+=2) {
            bignum_mod_mul(t, t, t, d, ddigits);
            bignum_mod_mul(t, t, t, d, ddigits);
            if((s = DIGIT_2MSB(ci)) != 0) {
                bignum_mod_mul(t, t, bpower[s-1], d, ddigits);
            }
            ci <<= 2;
        }
    }
    bignum_assign(a, t, ddigits);
    // Clear potentially sensitive information
    memset((uint8_t *)bpower, 0, sizeof(bpower));
    memset((uint8_t *)t, 0, sizeof(t));
}

int bignum_cmp(bignum_t *a, bignum_t *b, uint32_t digits) {
    int i;
    for(i=digits-1; i>=0; i--) {
        if(a[i] > b[i]) return 1;
        if(a[i] < b[i]) return -1;
    }
    return 0;
}

uint32_t bignum_digits(bignum_t *a, uint32_t digits) {
    int i;
    for(i=digits-1; i>=0; i--) {
        if(a[i]) break;
    }
    return (i + 1);
}

bignum_t bignum_add_digit_mul(bignum_t *a, bignum_t *b, bignum_t c, bignum_t *d, uint32_t digits) {
    if(c == 0)
        return 0;
    uint32_t i;
    bignum_t rh, rl;
    bignum_dt result;
    bignum_t carry = 0;
    for(i=0; i<digits; i++) {
        result = (bignum_dt)c * d[i];
        rl = result & BIGNUM_MAX_DIGIT;
        rh = (result >> BIGNUM_DIGIT_BITS) & BIGNUM_MAX_DIGIT;
        if((a[i] = b[i] + carry) < carry) {
            carry = 1;
        } else {
            carry = 0;
        }
        if((a[i] += rl) < rl) {
            carry++;
        }
        carry += rh;
    }
    return carry;
}

bignum_t bignum_sub_digit_mul(bignum_t *a, bignum_t *b, bignum_t c, bignum_t *d, uint32_t digits) {
    if(c == 0)
        return 0;
    uint32_t i;
    bignum_t rh, rl;
    bignum_dt result;
    bignum_t borrow = 0;
    for(i=0; i<digits; i++) {
        result = (bignum_dt)c * d[i];
        rl = result & BIGNUM_MAX_DIGIT;
        rh = (result >> BIGNUM_DIGIT_BITS) & BIGNUM_MAX_DIGIT;
        if((a[i] = b[i] - borrow) > (BIGNUM_MAX_DIGIT - borrow)) {
            borrow = 1;
        } else {
            borrow = 0;
        }
        if((a[i] -= rl) > (BIGNUM_MAX_DIGIT - rl)) {
            borrow++;
        }
        borrow += rh;
    }
    return borrow;
}

uint32_t bignum_digit_bits(bignum_t a) {
    uint32_t i;
    for(i=0; i<BIGNUM_DIGIT_BITS; i++) {
        if(a == 0)  break;
        a >>= 1;
    }
    return i;
}

// RSA interface
//-----------------------------------------------------------------------------
void generate_rand(uint8_t *block, uint32_t block_len) {
    uint32_t i;
    for(i=0; i<block_len; i++) {
        srand ((unsigned)time(NULL));
        block[i] = rand();
    }
}

int rsa_public_encrypt(uint8_t *out, uint32_t *out_len, uint8_t *in, uint32_t in_len) {
    int status;
    uint32_t i, modulus_len;
    uint8_t byte, pkcs_block[RSA_MAX_MODULUS_LEN];

    modulus_len = (pk->bits + 7) / 8;
    if(in_len + 11 > modulus_len) {
        return ERR_WRONG_LEN;
    }

    pkcs_block[0] = 0;
    pkcs_block[1] = 2;
    for(i=2; i<modulus_len-in_len-1; i++) {
        do {
            generate_rand(&byte, 1);
        } while(byte == 0);
        pkcs_block[i] = byte;
    }

    pkcs_block[i++] = 0;

    memcpy((uint8_t *)&pkcs_block[i], (uint8_t *)in, in_len);
    status = public_block_operation(out, out_len, pkcs_block, modulus_len);

    // Clear potentially sensitive information
    byte = 0;
    memset((uint8_t *)pkcs_block, 0, sizeof(pkcs_block));

    return status;
}

int rsa_public_decrypt(uint8_t *out, uint32_t *out_len, uint8_t *in, uint32_t in_len) {
    int status;
    uint8_t pkcs_block[RSA_MAX_MODULUS_LEN];
    uint32_t i, modulus_len, pkcs_block_len;

    modulus_len = (pk->bits + 7) / 8;
    if(in_len > modulus_len)
        return ERR_WRONG_LEN;

    status = public_block_operation(pkcs_block, &pkcs_block_len, in, in_len);
    if(status != 0)
        return status;

    if(pkcs_block_len != modulus_len)
        return ERR_WRONG_LEN;

    if((pkcs_block[0] != 0) || (pkcs_block[1] != 1))
        return ERR_WRONG_DATA;

    for(i=2; i<modulus_len-1; i++) {
        if(pkcs_block[i] != 0xFF)   break;
    }

    if(pkcs_block[i++] != 0)
        return ERR_WRONG_DATA;

    *out_len = modulus_len - i;
    if(*out_len + 11 > modulus_len)
        return ERR_WRONG_DATA;

    memcpy((uint8_t *)out, (uint8_t *)&pkcs_block[i], *out_len);

    // Clear potentially sensitive information
    memset((uint8_t *)pkcs_block, 0, sizeof(pkcs_block));

    return status;
}

int rsa_private_encrypt(uint8_t *out, uint32_t *out_len, uint8_t *in, uint32_t in_len) {
    int status;
    uint8_t pkcs_block[RSA_MAX_MODULUS_LEN];
    uint32_t i, modulus_len;

    modulus_len = (sk->bits + 7) / 8;
    if(in_len + 11 > modulus_len)
        return ERR_WRONG_LEN;

    pkcs_block[0] = 0;
    pkcs_block[1] = 1;
    for(i=2; i<modulus_len-in_len-1; i++) {
        pkcs_block[i] = 0xFF;
    }

    pkcs_block[i++] = 0;

    memcpy((uint8_t *)&pkcs_block[i], (uint8_t *)in, in_len);

    status = private_block_operation(out, out_len, pkcs_block, modulus_len);

    // Clear potentially sensitive information
    memset((uint8_t *)pkcs_block, 0, sizeof(pkcs_block));

    return status;
}

int rsa_private_decrypt(uint8_t *out, uint32_t *out_len, uint8_t *in, uint32_t in_len) {
    int status;
    uint8_t pkcs_block[RSA_MAX_MODULUS_LEN];
    uint32_t i, modulus_len, pkcs_block_len;

    modulus_len = (sk->bits + 7) / 8;
    if(in_len > modulus_len)
        return ERR_WRONG_LEN;

    status = private_block_operation(pkcs_block, &pkcs_block_len, in, in_len);
    if(status != 0)
        return status;

    if(pkcs_block_len != modulus_len)
        return ERR_WRONG_LEN;

    if((pkcs_block[0] != 0) || (pkcs_block[1] != 2))
        return ERR_WRONG_DATA;

    for(i=2; i<modulus_len-1; i++) {
        if(pkcs_block[i] == 0)  break;
    }

    i++;
    if(i >= modulus_len)
        return ERR_WRONG_DATA;
    *out_len = modulus_len - i;
    if(*out_len + 11 > modulus_len)
        return ERR_WRONG_DATA;
    memcpy((uint8_t *)out, (uint8_t *)&pkcs_block[i], *out_len);
    // Clear potentially sensitive information
    memset((uint8_t *)pkcs_block, 0, sizeof(pkcs_block));

    return status;
}

int public_block_operation(uint8_t *out, uint32_t *out_len, uint8_t *in, uint32_t in_len) {
    uint32_t edigits, ndigits;
    bignum_t c[BIGNUM_MAX_DIGITS], e[BIGNUM_MAX_DIGITS], m[BIGNUM_MAX_DIGITS], n[BIGNUM_MAX_DIGITS];

    bignum_decode(m, BIGNUM_MAX_DIGITS, in, in_len);
    bignum_decode(n, BIGNUM_MAX_DIGITS, pk->modulus, RSA_MAX_MODULUS_LEN);
    bignum_decode(e, BIGNUM_MAX_DIGITS, pk->exponent, RSA_MAX_MODULUS_LEN);

    ndigits = bignum_digits(n, BIGNUM_MAX_DIGITS);
    edigits = bignum_digits(e, BIGNUM_MAX_DIGITS);

    if(bignum_cmp(m, n, ndigits) >= 0) {
        return ERR_WRONG_DATA;
    }

    bignum_mod_exp(c, m, e, edigits, n, ndigits);

    *out_len = (pk->bits + 7) / 8;
    bignum_encode(out, *out_len, c, ndigits);

    // Clear potentially sensitive information
    memset((uint8_t *)c, 0, sizeof(c));
    memset((uint8_t *)m, 0, sizeof(m));

    return 0;
}

int private_block_operation(uint8_t *out, uint32_t *out_len, uint8_t *in, uint32_t in_len) {
    uint32_t cdigits, ndigits, pdigits;
    bignum_t c[BIGNUM_MAX_DIGITS], cp[BIGNUM_MAX_DIGITS], cq[BIGNUM_MAX_DIGITS];
    bignum_t dp[BIGNUM_MAX_DIGITS], dq[BIGNUM_MAX_DIGITS], mp[BIGNUM_MAX_DIGITS], mq[BIGNUM_MAX_DIGITS];
    bignum_t n[BIGNUM_MAX_DIGITS], p[BIGNUM_MAX_DIGITS], q[BIGNUM_MAX_DIGITS], q_inv[BIGNUM_MAX_DIGITS], t[BIGNUM_MAX_DIGITS];

    bignum_decode(c, BIGNUM_MAX_DIGITS, in, in_len);
    bignum_decode(n, BIGNUM_MAX_DIGITS, sk->modulus, RSA_MAX_MODULUS_LEN);
    bignum_decode(p, BIGNUM_MAX_DIGITS, sk->prime1, RSA_MAX_PRIME_LEN);
    bignum_decode(q, BIGNUM_MAX_DIGITS, sk->prime2, RSA_MAX_PRIME_LEN);
    bignum_decode(dp, BIGNUM_MAX_DIGITS, sk->prime_exponent1, RSA_MAX_PRIME_LEN);
    bignum_decode(dq, BIGNUM_MAX_DIGITS, sk->prime_exponent2, RSA_MAX_PRIME_LEN);
    bignum_decode(q_inv, BIGNUM_MAX_DIGITS, sk->coefficient, RSA_MAX_PRIME_LEN);

    cdigits = bignum_digits(c, BIGNUM_MAX_DIGITS);
    ndigits = bignum_digits(n, BIGNUM_MAX_DIGITS);
    pdigits = bignum_digits(p, BIGNUM_MAX_DIGITS);

    if(bignum_cmp(c, n, ndigits) >= 0)
        return ERR_WRONG_DATA;

    bignum_mod(cp, c, cdigits, p, pdigits);
    bignum_mod(cq, c, cdigits, q, pdigits);
    bignum_mod_exp(mp, cp, dp, pdigits, p, pdigits);
    bignum_assign_zero(mq, ndigits);
    bignum_mod_exp(mq, cq, dq, pdigits, q, pdigits);

    if(bignum_cmp(mp, mq, pdigits) >= 0) {
        bignum_sub(t, mp, mq, pdigits);
    } else {
        bignum_sub(t, mq, mp, pdigits);
        bignum_sub(t, p, t, pdigits);
    }

    bignum_mod_mul(t, t, q_inv, p, pdigits);
    bignum_mul(t, t, q, pdigits);
    bignum_add(t, t, mq, ndigits);

    *out_len = (sk->bits + 7) / 8;
    bignum_encode(out, *out_len, t, ndigits);

    // Clear potentially sensitive information
    memset((uint8_t *)c, 0, sizeof(c));
    memset((uint8_t *)cp, 0, sizeof(cp));
    memset((uint8_t *)cq, 0, sizeof(cq));
    memset((uint8_t *)dp, 0, sizeof(dp));
    memset((uint8_t *)dq, 0, sizeof(dq));
    memset((uint8_t *)mp, 0, sizeof(mp));
    memset((uint8_t *)mq, 0, sizeof(mq));
    memset((uint8_t *)p, 0, sizeof(p));
    memset((uint8_t *)q, 0, sizeof(q));
    memset((uint8_t *)q_inv, 0, sizeof(q_inv));
    memset((uint8_t *)t, 0, sizeof(t));
    return 0;
}

//parse pem token
uint32_t parse_pem_token(uint8_t* data, uint32_t* tlen) {
    int len = 0;
    int size = 1;
    if (data[0] & 0x80) {
        size += (data[0] & 0x7F);
        // big endian decode
        for (int i = 1; i < size; ++i) {
            len <<= 8;
            len |= (int)data[i];
        }
    }
    else len = data[0];
    if (tlen) *tlen = size;
    return len;
}

uint8_t* parse_pem_sequence(uint8_t* data, uint32_t* pem_len) {
    uint32_t token_len;
    if (data[0] == 0) data++;
    uint32_t seq_len = parse_pem_token(++data, &token_len);
    if (pem_len && *pem_len < token_len + seq_len) return NULL;
    data += token_len;
    return data;
}

uint8_t* parse_pem_param(uint8_t* data, uint8_t* target) {
    uint32_t token_len;
    uint32_t seq_len = parse_pem_token(++data, &token_len);
    data += token_len;
    if (data[0] == 0) { data++; seq_len--; }
    if (target) memcpy(target, data, seq_len);
    data += seq_len;
    return data;
}

int rsa_init_public_key(uint8_t *pem, uint32_t pem_len){
    if (pk != NULL) return 0;
    if (pem[0] != RSA_PEM_SEQUENCE) return ERR_WRONG_DATA;
    //30819e
    uint8_t * cur = parse_pem_sequence(pem, &pem_len);
    if (cur == NULL) return ERR_WRONG_LEN;
    //300d
    cur = parse_pem_param(cur, NULL);
    //03818c
    cur = parse_pem_sequence(cur, NULL);
    //00 308188
    cur = parse_pem_sequence(cur, NULL);
    //build
    pk = (rsa_pk_t*)malloc(sizeof(rsa_pk_t));
    memset(pk, 0, sizeof(rsa_pk_t));
    pk->bits = RSA_MAX_MODULUS_BITS;
    //modules
    cur = parse_pem_param(cur, pk->modulus);
    //exponent
    parse_pem_param(cur, &pk->exponent[RSA_EXPONENT_POS]);
    return 0;
}

int rsa_init_private_key(uint8_t *pem, uint32_t pem_len) {
    if (sk != NULL) return 0;
    if (pem[0] != RSA_PEM_SEQUENCE) return ERR_WRONG_DATA;
    //3082025c
    uint8_t* cur = parse_pem_sequence(pem, &pem_len);
    if (cur == NULL) return ERR_WRONG_LEN;
    //020100
    cur = parse_pem_param(cur, NULL);
    //build
    sk = (rsa_sk_t*)malloc(sizeof(rsa_sk_t));
    memset(sk, 0, sizeof(rsa_sk_t));
    sk->bits = RSA_MAX_MODULUS_BITS;
    //modules
    cur = parse_pem_param(cur, sk->modulus);
    //public_exponet
    cur = parse_pem_param(cur, &sk->public_exponet[RSA_EXPONENT_POS]);
    //exponent
    cur = parse_pem_param(cur, sk->exponent);
    //prime1
    cur = parse_pem_param(cur, sk->prime1);
    //prime2
    cur = parse_pem_param(cur, sk->prime2);
    //prime_exponent1
    cur = parse_pem_param(cur, sk->prime_exponent1);
    //prime_exponent2
    cur = parse_pem_param(cur, sk->prime_exponent2);
    //coefficient
    parse_pem_param(cur, sk->coefficient);
    return 0;
}
