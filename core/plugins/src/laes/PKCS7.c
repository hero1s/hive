#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "PKCS7.h"

PKCS7_Padding* addPadding(const void* const data, const uint64_t dataLength, const uint8_t BLOCK_SIZE)
{
    if (0 == BLOCK_SIZE)
    {
        puts("ERROR: block size value must be 0 < BLOCK_SIZE < 256");
        return NULL;
    }
    
    PKCS7_Padding* paddingResult = (PKCS7_Padding*) malloc(sizeof(PKCS7_Padding));
    if (NULL == paddingResult)
    {
        perror("problem with PKCS7_Padding* paddingResult");    /* if memory allocation failed */
        return NULL;
    }

    uint8_t paddingBytesAmount           = BLOCK_SIZE - (dataLength % BLOCK_SIZE);  /* number of bytes to be appended */
    paddingResult->valueOfByteForPadding = paddingBytesAmount;                      /* according to the PKCS7 */
    paddingResult->dataLengthWithPadding = dataLength + paddingBytesAmount;         /* size of the final result */
    
    uint8_t* dataWithPadding = (uint8_t*) malloc(paddingResult->dataLengthWithPadding);
    if (NULL == paddingResult)
    {
        perror("problem with uint8_t* dataWithPadding");  /* if memory allocation failed */
        free(paddingResult);
        return NULL;
    }
    
    memcpy(dataWithPadding, data, dataLength);  /* copying the original data for further adding padding */
    for (uint8_t i = 0; i < paddingBytesAmount; i++)
    {
        dataWithPadding[dataLength + i] = paddingResult->valueOfByteForPadding;   /* adding padding bytes */
    }
    paddingResult->dataWithPadding = dataWithPadding;

    return paddingResult;
}

PKCS7_unPadding* removePadding(const void* const data, const uint64_t dataLength)
{
    PKCS7_unPadding* unpaddingResult = (PKCS7_unPadding*) malloc(sizeof(PKCS7_unPadding));
    if (NULL == unpaddingResult)
    {
        perror("problem with PKCS7_Padding* unpaddingResult");  /* if memory allocation failed */
        return NULL;
    }
    
    uint8_t paddingBytesAmount                  = *((uint8_t *)data + dataLength - 1);  /* last byte contains length of data to be deleted */
    unpaddingResult->valueOfRemovedByteFromData = paddingBytesAmount;                   /* according to the PKCS7 */
    unpaddingResult->dataLengthWithoutPadding   = dataLength - paddingBytesAmount;      /* size of the final result */
    uint8_t* dataWithoutPadding = (uint8_t*) malloc(unpaddingResult->dataLengthWithoutPadding);
    if (NULL == dataWithoutPadding)
    {
        perror("problem with uint8_t* dataWithoutPadding");   /* if memory allocation failed */
        free(unpaddingResult);
        return NULL;
    }

    memcpy(dataWithoutPadding, data, unpaddingResult->dataLengthWithoutPadding);    /* taking data without bytes containing the padding value */
    unpaddingResult->dataWithoutPadding = dataWithoutPadding;

    return unpaddingResult;
}

void freePaddingResult(PKCS7_Padding* puddingResult)
{
    free(puddingResult->dataWithPadding);
    free(puddingResult);
}

void freeUnPaddingResult(PKCS7_unPadding* unPuddingResult)
{
    free(unPuddingResult->dataWithoutPadding);
    free(unPuddingResult);
}