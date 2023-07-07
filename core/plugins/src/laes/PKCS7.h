#ifndef PKCS7_H
#define PKCS7_H

#include <stdint.h>

/* 
    Examples of commonly used block sizes for data padding.
    WARNING: block size for PKCS7 padding can be 0 < BLOCK_SIZE < 256 bytes.
*/
typedef enum {
    BLOCK_SIZE_128_BIT      = 128 / 8,  /* 16 bytes block */
    BLOCK_SIZE_256_BIT      = 256 / 8,  /* 32 bytes block */
    BLOCK_SIZE_CUSTOM_VALUE = 0         /* you can set your own constant to use */
} paddingBlockSize;                     /* can be used as third argument to the function addPadding() */


/* 
    A pointer to this structure is returned from the function addPadding().
    The structure contains result of adding PKCS7 padding.
*/
typedef struct {
    void*    dataWithPadding;        /* result of adding padding to the data */
    uint64_t dataLengthWithPadding;  /* length of the result */
    uint8_t  valueOfByteForPadding;  /* used for padding byte value */
} PKCS7_Padding;                            

/* 
    Applies PKCS7 padding to data.
    Your data at the provided address does not change. A copy is created, to which the adding padding is applied.
    WARNING: use only 0 < BLOCK_SIZE < 256
*/
PKCS7_Padding* addPadding(const void* const data, const uint64_t dataLength, const uint8_t BLOCK_SIZE);


/* 
    A pointer to this structure is returned from the function removePadding().
    The structure contains result of removing PKCS7 padding.
*/
typedef struct {
    void*    dataWithoutPadding;         /* result of remove padding from data */
    uint64_t dataLengthWithoutPadding;   /* length of the result */
    uint8_t  valueOfRemovedByteFromData; /* value of byte that was used for padding */
} PKCS7_unPadding;                              

/* 
    Remove PKCS7 padding from data.
    Your data at the provided address does not change. A copy is created, to which the removing padding is applied.
*/
PKCS7_unPadding* removePadding(const void* const data, const uint64_t dataLength);


/*
    Frees the memory that was allocated for padding structure.
*/
void freePaddingResult(PKCS7_Padding* puddingResult);

/*
    Frees the memory that was allocated for unpadding structure.
*/
void freeUnPaddingResult(PKCS7_unPadding* unPuddingResult);

#endif // PKCS7_H