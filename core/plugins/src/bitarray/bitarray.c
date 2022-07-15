#include "bitarray_impl.h"
#include "lua.h"
#include "lauxlib.h"

#define BITARRAY_MT_1 "cleoold.lua.bitarray_mt1"

/* checks whether given argument is bitarray */
#define checkbitarray(L, i) (Bitarray *)luaL_checkudata(L, (i), BITARRAY_MT_1)

/* create an array and push it to the top of the stack */
static int _l_new(lua_State *L, size_t nbits)
{
    Bitarray *ba = (Bitarray *)lua_newuserdata(L, sizeof(Bitarray));
    if (bitarray_validate(ba, nbits) == 0)
        /* if fails to allocate array */
        return 0;

    luaL_getmetatable(L, BITARRAY_MT_1);
    lua_setmetatable(L, -2);
    return 1;
}

/**
 * Creates a new bit array of n bits. all fields are initialized to 0.
 * @function new
 * @tparam integer nbits number of bits of the array
 * @treturn Bitarray|nil the newly created bitarray if successful
 */
static int l_new(lua_State *L)
{
    lua_Integer nbits = luaL_checkinteger(L, 1);
    luaL_argcheck(L, nbits > 0, 1, "invalid size");

    return _l_new(L, (size_t)nbits);
}

/**
 * Creates a new bit array, identical to src.
 * @function copyfrom
 * @tparam Bitarray src
 * @treturn Bitarray|nil the newly created bitarray if successful
 */
static int l_copyfrom(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);

    if (_l_new(L, ba->size) == 0)
        return 0;
    bitarray_copyvalues(ba, (Bitarray *)lua_touserdata(L, -1));
    return 1;
}

/**
 * @type Bitarray
 */

static Bitarray *checkbitarray_and_index(lua_State *L, size_t *i)
{
    Bitarray *ba = checkbitarray(L, 1);
    lua_Integer i_ = luaL_checkinteger(L, 2) - 1;
    luaL_argcheck(L, 0 <= i_ && i_ < ba->size, 2, "index out of range");
    *i = (size_t)i_;
    return ba;
}

/* default opt chain: [,1 [,array size]] */
static Bitarray *checkbitarray_and_optrange(lua_State *L, size_t *from, size_t *to)
{
    Bitarray *ba = checkbitarray(L, 1);
    lua_Integer from_ = luaL_optinteger(L, 2, 1) - 1;
    luaL_argcheck(L, 0 <= from_ && from_ < ba->size, 2, "invalid index");
    lua_Integer to_ = luaL_optinteger(L, 3, ba->size);
    luaL_argcheck(L, to_ > from_ && to_ <= ba->size, 3, "invalid index");
    *from = (size_t)from_;
    *to = (size_t)to_;
    return ba;
}

/**
 * <i>Mutates the array.</i> <br />
 * Set the ith bit of the array. Any value other than false or nil will be
 * considered a truthy(1) bit. <br />
 * Operator __newindex is overloaded with this method.
 * @function set
 * @tparam integer i the index
 * @tparam any b the value to change to
 * @treturn Bitarray the original bit array reference
 * @usage
 * local a = Bitarray.new(10)
 * a:set(4, true)
 * a[4] = true -- same
 */
static int setbit(lua_State *L)
{
    size_t i;
    Bitarray *ba = checkbitarray_and_index(L, &i);
    luaL_checkany(L, 3);

    bitarray_set_bit(ba, i, lua_toboolean(L, 3));
    lua_pushvalue(L, 1);
    return 1;
}

/**
 * <i>Does not mutate the array.</i> <br />
 * Get the ith bit of the array. <br />
 * Operator __index is overloaded with this method.
 * @function at
 * @tparam integer i the index
 * @treturn boolean true if bit is 1, false if 0
 * @usage
 * local a = Bitarray.new(10)
 * a:at(7) -- false
 * a[7]    -- false
 */
static int getbit(lua_State *L)
{
    size_t i;
    Bitarray *ba = checkbitarray_and_index(L, &i);

    lua_pushboolean(L, bitarray_get_bit(ba, i));
    return 1;
}

/**
 * <i>Does not mutate the array.</i> <br />
 * Get the length of the array. <br />
 * Operator __len is overloaded with this method.
 * @function len
 * @treturn integer the number of bits of the array
 * @usage
 * local a = Bitarray.new(10)
 * a:len(a) -- 10
 * #a       -- 10
 */
static int len(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);
    lua_pushinteger(L, ba->size);
    return 1;
}

/**
 * <i>Mutates the array.</i> <br />
 * Set all bits of the array. Any value other than false or nil will be
 * considered a truthy(1) bit. <br />
 * @function fill
 * @tparam any b the value to change to
 * @treturn Bitarray the original bit array reference
 * @usage
 * local a = Bitarray.new(10)
 * a:fill(true)  -- all bits set to 1
 */
static int fill(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);
    luaL_checkany(L, 2);

    bitarray_fill(ba, lua_toboolean(L, 2));
    lua_pushvalue(L, 1);
    return 1;
}

/**
 * <i>Mutates the array.</i> <br />
 * If argument i is present, the bit at that index is flipped, if not or
 * i is 0, all the bits are flipped.
 * @function flip
 * @tparam[opt] integer i the index
 * @treturn Bitarray the original bit array reference
 * @usage
 * local a = Bitarray.new(10)
 * a:flip()    -- all bits set to true
 * a:flip(1)   -- sets first bit to true
 */
static int flip(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);
    lua_Integer i = luaL_optinteger(L, 2, 0);
    luaL_argcheck(L, 0 <= i && i <= ba->size, 2, "index out of range");
    if (i == 0)
        bitarray_flip(ba);
    else
        bitarray_flip_bit(ba, (size_t)i - 1);
    lua_pushvalue(L, 1);
    return 1;
}

/**
 * <i>May mutate the array. </i> <br />
 * Resize the array to length n. if new size is greater, the new bits
 * are appended to the right and initialized to 0, otherwise additional
 * rightmost bits are lost.
 * @function resize
 * @tparam integer n >= 1
 * @treturn Bitarray|nil the original bit array reference if successful,
 * otherwise nil
 */
static int resize(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);
    lua_Integer i = luaL_checkinteger(L, 2);
    luaL_argcheck(L, 0 < i, 2, "invalid length");

    if (bitarray_resize(ba, (size_t)i) == 0)
        /* resize failed */
        return 0;
    lua_pushvalue(L, 1);
    return 1;
}

/**
 * <i>Mutates the array.</i> <br />
 * Reverse the contents of the array.
 * @function reverse
 * @treturn Bitarray the original bit array reference
 */
static int reverse(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);
    bitarray_reverse(ba);
    return 1;
}

/**
 * <i>Does not mutate the array.</i> <br />
 * Creates a new array with bits obtained from those at index i to n in the
 * original array, inclusive. Resultant length is n - i + 1.
 * @function slice
 * @tparam[opt] integer i the starting index, default 1
 * @tparam[optchain] integer n the ending index, default the length of the array.
 * @treturn Bitarray|nil the newly created bit array reference if successful
 * @usage
 * local a = Bitarray.new(8):set(3, true):set(5, true)
 * local b = a:slice(1, 4)
 * print(a) -- Bitarray[0,0,1,0,1,0,0,0]
 * print(b) -- Bitarray[0,0,1,0]
 */
static int slice(lua_State *L)
{
    size_t from, to;
    Bitarray *ba = checkbitarray_and_optrange(L, &from, &to);

    if (_l_new(L, to - from) == 0)
        return 0;
    bitarray_copyvalues2(ba, (Bitarray *)lua_touserdata(L, -1), from, to, 0);
    return 1;
}

/**
 * <i>Does not mutate the array.</i> <br />
 * Repeat the array n times and return the new array. <br />
 * @function rep
 * @tparam integer n >= 1
 * @treturn Bitarray|nil the newly created bit array reference if successful
 * @usage
 * local a = Bitarray.new(3):set(3, true)
 * print(a:rep(4))  -- Bitarray[0,0,1,0,0,1,0,0,1,0,0,1]
 */
static int rep(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);
    lua_Integer n = luaL_checkinteger(L, 2);
    luaL_argcheck(L, n > 0, 2, "number of repetition must be positive integer");

    if (_l_new(L, ba->size * n) == 0)
        return 0;
    Bitarray *r = (Bitarray *)lua_touserdata(L, -1);
    bitarray_copyvalues(ba, r);
    for (size_t i = 1; i < (size_t)n; ++i)
        bitarray_copyvalues2(ba, r, 0, ba->size, i * ba->size);
    return 1;
}

/**
 * <i>Does not mutate the array.</i> <br />
 * Compares whether two arrays are identical (same value and length). <br />
 * Operator __eq is overloaded with this method.
 * @function equal
 * @tparam Bitarray other
 * @treturn boolean
 * @usage
 * local a = Bitarray.new(10)
 * local b = Bitarray.copyfrom(a)
 * a:equal(b)          -- true
 * a == b:resize(1)    -- false
 */
static int equal(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);
    Bitarray *o = checkbitarray(L, 2);

    lua_pushboolean(L, bitarray_equal(ba, o));
    return 1;
}

/**
 * <i>Does not mutate the array.</i> <br />
 * Concatenate two arrays and return the new array. <br />
 * Operator __concat is overloaded with this method.
 * @function concat
 * @tparam Bitarray other
 * @treturn Bitarray|nil the newly created bit array reference if successful
 * @usage
 * local a = Bitarray.new(1)
 * local b = Bitarray.new(4):fill(true)
 * print(a..b)  -- Bitarray[0,1,1,1,1]
 */
static int concat(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);
    Bitarray *o = checkbitarray(L, 2);

    if (_l_new(L, ba->size + o->size) == 0)
        return 0;
    Bitarray *r = (Bitarray *)lua_touserdata(L, -1);
    bitarray_copyvalues(ba, r);
    bitarray_copyvalues2(o, r, 0, o->size, ba->size);
    return 1;
}

/**
 * <i>Does not mutate the array.</i> <br />
 * Flip all bits of the array and return the new array. <br />
 * Operator __bnot is overloaded with this method. (5.3+)
 * @function bnot
 * @treturn Bitarray|nil the newly created bit array reference if successful
 * @usage
 * local a = Bitarray.new(2):set(1, true)
 * print(~a)  -- Bitarray[0,1]
 */
static int bnot(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);

    if (_l_new(L, ba->size) == 0)
        return 0;
    Bitarray *r = (Bitarray *)lua_touserdata(L, -1);
    bitarray_copyvalues(ba, r);
    bitarray_flip(r);
    return 1;
}

#define BITARRAY_BIT_BIOP(NAME, OP) \
    static int NAME(lua_State *L) \
    { \
        Bitarray *ba = checkbitarray(L, 1); \
        Bitarray *o = checkbitarray(L, 2); \
        luaL_argcheck(L, ba->size == o->size, 2, \
            "two operands must be of same size"); \
        \
        if (_l_new(L, ba->size) == 0) \
            return 0; \
        Bitarray *r = (Bitarray *)lua_touserdata(L, -1); \
        BITARRAY_WORD_ITER(r, i, \
            r->values[i] = ba->values[i] OP o->values[i]; \
        ); \
        return 1; \
    }

/**
 * <i>Does not mutate the array.</i> <br />
 * Perform a bitwise AND and return the new array. Two arrays have to be of
 * same size. <br />
 * Operator __band is overloaded with this method. (5.3+)
 * @function band
 * @tparam Bitarray other
 * @treturn Bitarray|nil the newly created bit array reference if successful
 * @usage
 * local a = Bitarray.new(4):set(1, true):set(3, true)
 * local b = Bitarray.new(4):set(1, true)
 * print(a & b)  -- Bitarray[1,0,0,0]
 */
BITARRAY_BIT_BIOP(band, &)

/**
 * <i>Does not mutate the array.</i> <br />
 * Perform a bitwise OR and return the new array. Two arrays have to be of
 * same size. <br />
 * Operator __bor is overloaded with this method. (5.3+)
 * @see band
 * @function bor
 * @tparam Bitarray other
 * @treturn Bitarray|nil the newly created bit array reference if successful
 */
BITARRAY_BIT_BIOP(bor, |)

/**
 * <i>Does not mutate the array.</i> <br />
 * Perform a bitwise XOR and return the new array. Two arrays have to be of
 * same size. <br />
 * Operator __bxor is overloaded with this method. (5.3+)
 * @see band
 * @function bxor
 * @tparam Bitarray other
 * @treturn Bitarray|nil the newly created bit array reference if successful
 */
BITARRAY_BIT_BIOP(bxor, ^)

#undef BITARRAY_BIT_BIOP

/**
 * <i>Does not mutate the array.</i> <br />
 * Shift all content left n bits and return the new array. Extra bits are
 * discarded and empty bits are filled with 0. <br />
 * Operator __shl is overloaded with this method. (5.3+)
 * @function shiftleft
 * @tparam integer n
 * @treturn Bitarray|nil the newly created bit array reference if successful
 * @usage
 * local a = Bitarray.new(8):from_uint8(15)
 * print(a)      -- Bitarray[0,0,0,0,1,1,1,1]
 * print(a << 2) -- Bitarray[0,0,1,1,1,1,0,0]
 */
static int shl(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);
    long s = (long)luaL_checkinteger(L, 2);

    if (_l_new(L, ba->size) == 0)
        return 0;
    Bitarray *r = (Bitarray *)lua_touserdata(L, -1);
    bitarray_copyvalues(ba, r);
    if (s >= 0)
        bitarray_be_lshift(r, (size_t)s);
    else
        bitarray_be_rshift(r, (size_t)-s);
    return 1;
}

/**
 * <i>Does not mutate the array.</i> <br />
 * Shift all content right n bits and return the new array. Extra bits are
 * discarded and empty bits are filled with 0. The shift is unsigned. <br />
 * Operator __shr is overloaded with this method. (5.3+)
 * @see shiftleft
 * @function shiftright
 * @tparam integer n
 * @treturn Bitarray|nil the newly created bit array reference if successful
 */
static int shr(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);
    long s = (long)luaL_checkinteger(L, 2);

    if (_l_new(L, ba->size) == 0)
        return 0;
    Bitarray *r = (Bitarray *)lua_touserdata(L, -1);
    bitarray_copyvalues(ba, r);
    if (s >= 0)
        bitarray_be_rshift(r, (size_t)s);
    else
        bitarray_be_lshift(r, (size_t)-s);
    return 1;
}

static size_t checkopt_index(lua_State *L, Bitarray *ba, int nArg)
{
    lua_Integer i = luaL_optinteger(L, nArg, 1) - 1;
    luaL_argcheck(L, 0 <= i && i < ba->size, nArg, "index out of range");
    return (size_t)i;
}

#define BITARRAY_AT_TYPE(TYPE) \
    static int at_ ## TYPE(lua_State *L) \
    { \
        Bitarray *ba = checkbitarray(L, 1); \
        size_t i = checkopt_index(L, ba, 2); \
        size_t tgt = sizeof(TYPE) * CHAR_BIT; \
        luaL_argcheck(L, ba->size - i + 1 > tgt, 2, \
            "too few bits to construct this type"); \
        \
        TYPE res = 0; \
        for (size_t j = i, k = 0; k < tgt; ++j, ++k) { \
            WORD mask; \
            WORD *word = bitarray_get_bit_access(ba, j, &mask); \
            TYPE maskt = (TYPE)1 << (TYPE)(tgt-k-1); \
            res = (*word & mask) ? (res | maskt) : (res & ~maskt); \
        } \
        lua_pushinteger(L, (lua_Integer)res); \
        return 1; \
    }

/** 
 * <i>Does not mutate the array.</i> <br />
 * Converts the contents starting at index i to an uint8 (uchar) integer.
 * The array should be big enough to hold bits required to construct the
 * type.
 * The leftmost bit corresponds to the most significant digit of the number
 * and the last bit corresponds to the least significant digit (big endian).
 * @function at_uint8
 * @tparam[opt] integer i default to 1
 * @treturn integer
 * @usage
 * local a = Bitarray.new(10):set(2, 1):set(3, 1):set(4, 1):set(5, 1):set(7, 1)
 * print(a) -- Bitarray[0,1,1,1,1,0,1,0,0,0]
 * a:at_uint8(2)   -- intepreted as 11110100, which is 244
 */
BITARRAY_AT_TYPE(uint8_t)

/** 
 * <i>Does not mutate the array.</i> <br />
 * Converts the contents starting at index i to an uint16 integer.
 * @see at_uint8
 * @function at_uint16
 * @tparam[opt] integer i
 * @treturn integer
 */
BITARRAY_AT_TYPE(uint16_t)

/** 
 * <i>Does not mutate the array.</i> <br />
 * Converts the contents starting at index i to an uint32 integer.
 * @see at_uint8
 * @function at_uint32
 * @tparam[opt] integer i
 * @treturn integer
 */
BITARRAY_AT_TYPE(uint32_t)

/** 
 * <i>Does not mutate the array.</i> <br />
 * Converts the contents starting at index i to an uint64 integer.
 * @see at_uint8
 * @function at_uint64
 * @tparam[opt] integer i
 * @treturn integer
 * @usage
 * -- lua5.3 added support for displaying and manipulating unsigned integers,
 * -- prior to that this function may not work as intended always
 * local a = Bitarray.new(64):fill(true)
 * string.format('%u', a:at_uint64()) -- 18446744073709551615
 */
BITARRAY_AT_TYPE(uint64_t)

#undef BITARRAY_AT_TYPE

#define BITARRAY_FROM_TYPE(TYPE) \
    static int from_ ## TYPE(lua_State *L) \
    { \
        Bitarray *ba = checkbitarray(L, 1); \
        TYPE src = (TYPE)luaL_checkinteger(L, 2); \
        size_t i = checkopt_index(L, ba, 3); \
        size_t tgt = sizeof(TYPE) * CHAR_BIT; \
        luaL_argcheck(L, ba->size - i + 1 > tgt, 3, \
            "too few bits to contain this type"); \
        \
        for (size_t j = i, k = 0; k < tgt; ++j, ++k) { \
            TYPE maskt = (TYPE)1 << (TYPE)(tgt-k-1); \
            int b = !!(src & maskt); \
            bitarray_set_bit(ba, j, b); \
        } \
        lua_pushvalue(L, 1); \
        return 1; \
    }

/** 
 * <i>Mutates the array.</i> <br />
 * Assign the array from index i from an uint8 (uchar) integer. The array should
 * be big enough to store the representation.
 * The leftmost bit corresponds to the most significant digit of the number
 * and the last bit corresponds to the least significant digit (big endian).
 * @function from_uint8
 * @tparam integer src the source integer to convert from
 * @tparam[opt] integer i the index in this array where the first bit gets
 * copied from src. default 1
 * @treturn Bitarray the original bit array reference
 * @usage
 * local a = Bitarray.new(8):from_uint8(253)
 * print(a) -- Bitarray[1,1,1,1,1,1,0,1]
 * local b = Bitarray.new(16):from_uint8(255, 9)
 * print(b) -- Bitarray[0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1]
 */
BITARRAY_FROM_TYPE(uint8_t)

/** 
 * <i>Mutates the array.</i> <br />
 * Assign the array from index i from an uint16 integer. The array should
 * be big enough to store the representation.
 * @see from_uint8
 * @function from_uint16
 * @tparam integer src
 * @tparam[opt] integer i
 * @treturn Bitarray the original bit array reference
 */
BITARRAY_FROM_TYPE(uint16_t)

/** 
 * <i>Mutates the array.</i> <br />
 * Assign the array from index i from an uint32 integer. The array should
 * be big enough to store the representation.
 * @see from_uint8
 * @function from_uint32
 * @tparam integer src
 * @tparam[opt] integer i
 * @treturn Bitarray the original bit array reference
 */
BITARRAY_FROM_TYPE(uint32_t)

/** 
 * <i>Mutates the array.</i> <br />
 * Assign the array from index i from an uint64 integer. The array should
 * be big enough to store the representation.
 * @see from_uint8
 * @see at_uint64
 * @function from_uint64
 * @tparam integer src
 * @tparam[opt] integer i
 * @treturn Bitarray the original bit array reference
 */
BITARRAY_FROM_TYPE(uint64_t)

#undef BITARRAY_FROM_TYPE

/**
 * <i>Mutates the array.</i> <br />
 * Copy the content from bitarray src to the operand. The array's ith, i+1th,
 * ... bit will be the bits from src starting from 1st to the last. The array
 * needs to be big enough to hold the data.
 * @function from_bitarray
 * @tparam Bitarray src
 * @tparam[opt] integer i the index in this array where the first bit gets
 * copied from src. default 1
 * @treturn Bitarray the original bit array reference
 * @usage
 * local a = Bitarray.new(10)
 *  :from_bitarray(Bitarray.new(5):fill(true):set(3, false), 6)
 * print(a) -- Bitarray[0,0,0,0,0,1,1,0,1,1]
 */
static int from_bitarray(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);
    Bitarray *src = checkbitarray(L, 2);
    size_t i = checkopt_index(L, ba, 3);
    luaL_argcheck(L, ba->size - i + 1 > src->size, 3, "not enough space");

    bitarray_copyvalues2(src, ba, 0, src->size, i);
    lua_pushvalue(L, 1);
    return 1;
}

/**
 * <i>Mutates the array.</i> <br />
 * Copy the content from a binary string to the operand. Given the string
 * consisting of only 0 and 1's, the array's ith, i+1th, ... bit will be
 * the false/true values represented by chars in this string. The array
 * needs to be big enough to hold the data.
 * @function from_binarystring
 * @tparam string src
 * @tparam[opt] integer i the index in this array where the first bit gets
 * copied from src. default 1
 * @treturn Bitarray the original bit array reference
 * @usage
 * local a = Bitarray.new(12)
 *  :from_binarystring('001100'):from_binarystring('111111', 7)
 * print(a) -- Bitarray[0,0,1,1,0,0,1,1,1,1,1,1]
 * -- a:from_binarystring('10x0') error! invalid string
 */
static int from_binarystring(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);
    size_t slen;
    const char *s = luaL_checklstring(L, 2, &slen);
    size_t i = checkopt_index(L, ba, 3);

    for (size_t j = 0; j < slen; ++j) {
        if (s[j] != '1' && s[j] != '0')
            luaL_argerror(L, 2, "invalid binary string");
    }
    luaL_argcheck(L, ba->size - i + 1 > slen, 3, "not enough space");

    for (size_t j = 0; j < slen; ++j)
        bitarray_set_bit(ba, i + j, s[j] == '1');
    lua_pushvalue(L, 1);
    return 1;
}

/**
 * <i>Does not mutate the array.</i> <br />
 * Returns the string representation for the array. <br />
 * Metamethod __tostring is overloaded with this method so it can be implicitly
 * called if string is needed. The full array is not displayed if it is too long.
 * @function tostring
 * @treturn string
 * @usage
 * local a = Bitarray.new(8):set(8, true)
 * print(a)
 * -- Bitarray[0,0,0,0,0,0,0,1]
 * a:resize(65)
 * print(a)
 * -- Bitarray[...]
 */
static int tostring(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);
    luaL_Buffer buf;
    luaL_buffinit(L, &buf);
    luaL_addstring(&buf, "Bitarray[");
    if (ba->size > (size_t)64) {
        luaL_addstring(&buf, "...]");
        goto push;
    }
    for (size_t i = 0; i < ba->size-1; ++i) {
        luaL_addstring(&buf, bitarray_get_bit(ba, i) ? "1," : "0,");
    }
    /* size cannot be 0 in this context */
    luaL_addstring(&buf, bitarray_get_bit(ba, ba->size-1) ? "1]" : "0]");
push:
    luaL_addvalue(&buf);
    luaL_pushresult(&buf);
    return 1;
}

/* finalizer for bitarray */
static int gc(lua_State *L)
{
    Bitarray *ba = checkbitarray(L, 1);
    bitarray_invalidate(ba);
    return 0;
}

/* actual __index, if param if number it returns result of get(), otherwise
   looks up for fields */
static int get(lua_State *L)
{
#if LUA_VERSION_NUM >= 503
    if (lua_isinteger(L, 2))
#else
    if (lua_isnumber(L, 2))
#endif
        return getbit(L);
    luaL_getmetatable(L, BITARRAY_MT_1);
    lua_pushvalue(L, 2);
    lua_rawget(L, -2);
    return 1;
}

static const struct luaL_Reg bitarraylib_f[] =
{
    { "new", l_new },
    { "copyfrom", l_copyfrom },
    { NULL, NULL }
};

static const struct luaL_Reg bitarraylib_m1[] =
{
    { "at", getbit },
    { "set", setbit },
    { "len", len },
    { "fill", fill },
    { "flip", flip },
    { "equal", equal },
    { "concat", concat },
    { "bnot", bnot },
    { "band", band },
    { "bor", bor },
    { "bxor", bxor },
    { "shiftleft", shl },
    { "shiftright", shr },
    { "resize", resize },
    { "reverse", reverse },
    { "slice", slice },
    { "rep", rep },
    { "at_uint8", at_uint8_t },
    { "at_uint16", at_uint16_t },
    { "at_uint32", at_uint32_t },
    { "at_uint64", at_uint64_t },
    { "from_bitarray", from_bitarray },
    { "from_binarystring", from_binarystring },
    { "from_uint8", from_uint8_t },
    { "from_uint16", from_uint16_t },
    { "from_uint32", from_uint32_t },
    { "from_uint64", from_uint64_t },
    { "tostring", tostring },
    { "__index", get },
    { "__newindex", setbit },
    { "__len", len },
    { "__eq", equal },
    { "__concat", concat },

    { "__bnot", bnot },
    { "__band", band },
    { "__bor", bor },
    { "__bxor", bxor },
    { "__shl", shl },
    { "__shr", shr },

    { "__gc", gc },
    { "__tostring", tostring },
    { NULL, NULL }
};

LUALIB_API int luaopen_bitarray(lua_State *L)
{
    luaL_newmetatable(L, BITARRAY_MT_1);
    luaL_setfuncs(L, bitarraylib_m1, 0);
    luaL_newlib(L, bitarraylib_f);
    return 1;
}
