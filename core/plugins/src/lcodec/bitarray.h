#pragma once

#include <string>
#include <stdlib.h>

namespace lcodec {
    typedef unsigned int BWORD;

    /*  number of bits in a word */
    #define BITS_PER_BWORD      (CHAR_BIT * sizeof(BWORD))
    /* gets the word that contains the bit corresponding to a given index i */
    #define I_BWORD(i)          ((BWORD)(i) / BITS_PER_BWORD)
    /*  computes a mask to access the correct bit inside this word */
    #define I_BIT(i)            ((BWORD)1 << ((BWORD)(i) % BITS_PER_BWORD))
    /* computes how many words to store n bits */
    #define BWORDS_FOR_BITS(n)  (I_BWORD((n) - 1) + 1)

    class bitarray
    {
    public:
        ~bitarray() {
            if (values_) {
                free(values_);
                values_ = nullptr;
            }
            size_ = 0;
        }

        size_t general(size_t nbits) {
            values_ = (BWORD*)calloc(BWORDS_FOR_BITS(nbits), sizeof(BWORD));
            if (values_ != nullptr)
                return size_ = nbits;
            return 0;
        }

        /* set ith bit to 1 if b is truthy, else 0 */
        void set_bit(size_t i, size_t b) {
            raw_set_bit(check_index(i), b);
        }

        /* get ith bit (1 or 0) */
        size_t get_bit(size_t i) {
            return raw_get_bit(check_index(i));
        }

        /* 1 -> 0 and 0 -> 1 */
        void flip_bit(size_t i) {
            size_t idx = check_index(i);
            if (idx < size_) {
                BWORD mask;
                BWORD* word = get_bit_access(idx, &mask);
                *word = (*word & mask) ? (*word & ~mask) : (*word | mask);
            }
        }

        void flip() {
            size_t nwords = BWORDS_FOR_BITS(size_);
            for (size_t i = 0; i < nwords; ++i) {
                values_[i] = ~values_[i];
            }
            for (size_t i = size_; i < nwords * BITS_PER_BWORD; ++i) {
                raw_set_bit(i, 0);
            }
        }

        void fill(bool b) {
            BWORD bb = b ? (BWORD)-1 : 0;
            size_t nwords = BWORDS_FOR_BITS(size_);
            for (size_t i = 0; i < nwords; ++i) {
                values_[i] = bb;
            }
            for (size_t i = size_; i < nwords * BITS_PER_BWORD; ++i) {
                raw_set_bit(i, 0);
            }
        }
        
        /* resize the array. if new size is bigger, fill the new bit positions with 0.
        also set any unused bits to 0 (ie the gap between size and the actual end
        of WORDs). returns the new size, or 0 is returned if failed (array unchanged)*/
        size_t resize(size_t nbits) {
            if (nbits == size_)
                return nbits;
            size_t oldwords = BWORDS_FOR_BITS(size_);
            size_t newwords = BWORDS_FOR_BITS(nbits);
            if (oldwords != newwords) {
                BWORD* tmp = (BWORD* )realloc(values_, newwords * sizeof(BWORD));
                if (tmp == nullptr)
                    return 0;
                values_ = tmp;
            }
            size_ = nbits;
            size_t oldbits = size_;
            if (nbits < oldbits) {
                for (size_t i = nbits; i < newwords * BITS_PER_BWORD; ++i)
                    raw_set_bit(i, 0);
            } else {
                /* gap between oldbits and oldwords*BITS_PER_BWORD is guaranteed to be 0 */
                for (size_t i = oldwords; i < newwords; ++i)
                    values_[i] = 0;
            }
            return nbits;
        }

        void reverse() {
            for (size_t i = 0, j = size_ - 1; i < j; ++i, --j) {
                int tmp = raw_get_bit(i);
                raw_set_bit(i, raw_get_bit(j));
                raw_set_bit(j, tmp);
            }
        }

        /* copy values from ba to tg */
        void concat(bitarray* tg) {
            resize(size_ + tg->size_);
            for (size_t i = 0; i < BWORDS_FOR_BITS(size_); ++i)
                values_[size_] = tg->values_[i];
        }

        /* copy values from ba to tg */
        bitarray* clone() {
            bitarray* ba = new bitarray();
            if (!ba->general(size_)) {
                delete ba;
                return nullptr;
            }
            for (size_t i = 0; i < BWORDS_FOR_BITS(size_); ++i) {
                ba->values_[i] = values_[i];
            }
            return ba;
        }

        bitarray* slice(size_t from, size_t to) {
            size_t ifrom = check_index(from);
            size_t ito = check_index(to, true);
            size_t len = ito - ifrom + 1;
            bitarray* ba = new bitarray();
            if (!ba->general(len)) {
                delete ba;
                return nullptr;
            }
            for(size_t i = 0; i < len; ++i) {
                ba->raw_set_bit(i, raw_get_bit(ifrom + i));
            }
            return ba;
        }

        void from_string(std::string str, size_t i) {
            size_t idx = check_index(i);
            size_t slen = str.size(); 
            resize(i + slen);
            for (size_t j = 0; j < slen; ++j)
                raw_set_bit(idx + j, str[j] != '0');
        }

        template<typename T>
        void from_number(T src, size_t i) {
            size_t idx = check_index(i);
            size_t tgt = sizeof(T) * CHAR_BIT;
            resize(i + tgt);
            for (size_t j = idx, k = 0; k < tgt; ++j, ++k) {
                T maskt = (T)1 << (T)(tgt - k - 1);
                size_t b = !!(src & maskt);
                raw_set_bit(j, b);
            }
        }
        
        template<typename T>
        T to_number(size_t i) {
            T res = 0;
            size_t idx = check_index(i);
            size_t tgt = sizeof(T) * CHAR_BIT;
            for (size_t j = idx, k = 0; k < tgt; ++j, ++k) {
                BWORD mask;
                BWORD* word = get_bit_access(j, &mask);
                T maskt = (T)1 << (T)(tgt - k - 1);
                res = (*word & mask) ? (res | maskt) : (res & ~maskt);
            }
            return res;
        }

        std::string to_string(size_t i) {
            std::string str = "bitarray<";
            str.append(std::to_string(size_));
            str.append(">[");
            for (size_t i = 0; i < size_; ++i) {
                str.append(raw_get_bit(i) ? "1," : "0,");
            }
            return str;
        }

        bool equal(bitarray *r) {
            if (size_ != r->size_)
                return false;
            for (size_t i = 0; i < BWORDS_FOR_BITS(size_); ++i)
                if (values_[i] != r->values_[i])
                    return false;
            return true;
        }

        void lshift(size_t s) {
            size_t sz = size_;
            for (size_t i = 0; i + s < sz; ++i)
                raw_set_bit(i, raw_get_bit(i + s));
            for (size_t i = sz > s ? sz - s : 0; i < sz; ++i)
                raw_set_bit(i, 0);
        }

        void rshift(size_t s) {
            size_t sz = size_;
            for (size_t i = 0; i + s < sz; ++i)
                raw_set_bit(sz - i - 1, raw_get_bit(sz - i - 1 - s));
            for (size_t i = sz > s ? sz - s : 0; i < sz; ++i)
                raw_set_bit(sz - i - 1, 0);
        }

        size_t length() {
            return size_;
        }
        
    private:
        size_t check_index(size_t i, bool tail = false) {
            if (tail) {
                return (i > 0 && i <= size_) ? i - 1 : size_ - 1;
            }
            return i > 0 ? i - 1 : 0;
        }

        /* set ith bit to 1 if b is truthy, else 0 */
        void raw_set_bit(size_t i, size_t b) {
              if (i < size_) {
                BWORD mask;
                BWORD* word = get_bit_access(i, &mask);
                if (b)
                    *word |= mask;  /* set bit */
                else
                    *word &= ~mask; /* reset bit */
            }
        }

        /* get ith bit (1 or 0) */
        size_t raw_get_bit(size_t i) {
            if (i < size_) {
                BWORD mask;
                BWORD* word = get_bit_access(i, &mask);
                return (*word & mask) ? 1 : 0;
            }
            return -1;
        }

        /* given an index, returns the word address and the mask to access the bit */
        BWORD* get_bit_access(size_t i, BWORD* mask) {
            if (mask != nullptr)
                *mask = I_BIT(i);
            return &values_[I_BWORD(i)];
        }

    private:
        size_t size_;
        BWORD* values_; /* uses little endian to store bits */
    };

}
