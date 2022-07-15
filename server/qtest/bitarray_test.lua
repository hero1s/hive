local Bitarray = require('bitarray')

local function check(expr)
    if not expr then error('test failed', 2) end
end

local function checkerror(exprf)
    if pcall(exprf) then error('test failed', 2) end
end

-- array creation and set/get bit
do
    local a = Bitarray.new(1)
    check(a:len() == 1)
    check(a.__gc)
    local b = Bitarray.new(2)
    check(b:len() == 2)
    local c = Bitarray.new(7)
    check(#c == 7)
    checkerror(function() return c[8] end)
    local d = Bitarray.new(8)
    d:set(7, true)
    check(d:at(6) == false)
    check(d:at(7) == true)
    check(d:at(8) == false)
    local e = Bitarray.new(9)
    e[8] = true
    e[9] = false
    check(e[8] == true)
    check(e[9] == false)
    local f = Bitarray.new(32)
    f[32] = true
    for i = 1, #f-1 do check(f[i] == false) end
    check(f[32] == true)
    -- chain sets
    f:set(1, true):set(2, false):set(3, true)
    check(f[1] and not f[2] and f[3])
end

-- fill, flip and copy
-- note not only the below resize, `BITARRAY_WORD_ITER` have to be checked
-- for out-of-range modification as well
do
    local a = Bitarray.new(279)
    a:flip()
    for i = 1, 279 do check(a[i]) end
    a:flip(1):flip(279)
    check(not a[1] and a[278] and not a[279])
    a:fill(false)
    for i = 1, 279 do check(not a[i]) end
    local b = Bitarray.copyfrom(a)
    check(#b == #a)
    for i = 1, 279 do check(not b[i]) end
    b:fill(true)
    for i = 1, 279 do check(b[i]) end
    for i = 1, 279 do check(not a[i]) end
end

-- resize
do
    local a = Bitarray.new(1)
    a:resize(4)
    check(not a[1] and not a[2] and not a[3] and not a[4])
    a[4] = true
    a:resize(400)
    check(a[4] and not a[5] and not a[16] and not a[32] and not a[400])
    for i = 210, 400 do a[i] = true end
    a:resize(217)
    check(not a[209] and a[210] and a[217])
    check(#a == 217)
    local b = Bitarray.new(32)
    b:resize(10000)
    for i = 1, 10000 do check(not b[i]) end
    checkerror(function() return b[10001] end)
    b:fill(true)
    b:resize(1024)
    for i = 1, 1024 do check(b[i]) end
    b:resize(10000)
    for i = 1025, 10000 do check(not b[i]) end
    local c = Bitarray.new(32)
    c:fill(true)
    c:resize(16)
    c:resize(32)
    for i = 17, 32 do check(not c[i]) end
end

-- eq
do
    local a = Bitarray.new(10)
    a:resize(144)
    local b = Bitarray.new(144)
    check(a:equal(b))
    b[5] = true
    check(not a:equal(b))
    a:flip()
    check(a ~= b)
    b:fill(true)
    check(a == b)
    b:resize(143)
    check(a ~= b)
end

-- reverse
do
    local a = Bitarray.new(50)
    local b = Bitarray.copyfrom(a):reverse()
    check(a == b)
    a:set(1, true):set(3, true):set(4, true):set(44, true)
    b:set(50, true):set(48, true):set(47, true):set(7, true):reverse()
    check(a == b)
end

-- slice, concat, rep and from_bitarray
do
    local a = Bitarray.new(167):fill(true)
    check(a == a:slice() and a == a:slice(1))
    local b = a:slice(7, 7)
    check(b[1])
    local c = a:slice(1, 128)
    for i = 1, 128 do check(c[i]) end
    local d = a:slice(1, 130)
    for i = 1, 130 do check(d[i]) end
    a[66] = false
    local e = a:slice(26, 68)
    for i = 1, 40 do check(e[i]) end
    check(not e[41])
    for i = 42, 43 do check(e[i]) end
    local f = Bitarray.new(44):from_bitarray(Bitarray.new(22):fill(true))
    check(#f == 44)
    for i = 1, 22 do check(f[i]) end
    for i = 23, 44 do check(not f[i]) end
    local _g = Bitarray.new(5):fill(true):set(3, false)
    local g = Bitarray.new(10):from_bitarray(_g, 6)
    check(g == Bitarray.new(10):set(6, true):set(7, true):set(9, true):set(10, true))
    check(g == Bitarray.new(5):concat(_g))
    check(g:rep(1) == g)
    local h = g:slice(6):set(3, true)
    check(h..h..h == Bitarray.new(15):flip())
    check(g:rep(5) == g..g..g..g..g)
end

-- from/to uints
do
    local a = Bitarray.new(32):from_uint32(402654856)
    check(a == Bitarray.new(32):set(4, true):set(5, true):set(22, true):set(23, true):set(25, true):set(29, true))
    check(a:at_uint32(1) == 402654856)
    local b = Bitarray.new(64):from_uint32(0x7FFFFFFF, 33)
    check(b == Bitarray.new(33)..Bitarray.new(31):fill(true))
end

-- from_binarystring
do
    local a = Bitarray.new(1):from_binarystring('1')
    check(a[1])
    local b = Bitarray.new(16):from_binarystring('11001100'):from_binarystring('11111111', 9)
    check(b:at_uint16() == 0xCCFF)
    checkerror(function() b:from_binarystring('0x11') end)
end

-- bitwise
do
    local a = Bitarray.new(177)
    local b = Bitarray.new(177)
    for i = 1, 177, 2 do a[i] = true end
    for i = 2, 177, 2 do b[i] = true end
    check(a:bnot() == b)
    check(b:bnot() == a)
    check(a:band(b) == Bitarray.new(177))
    check(a:bor(b) == Bitarray.new(177):fill(true))
    check(a:bxor(b) == Bitarray.new(177):fill(true))
    b:fill(false)
    check(a:bor(b) == a)
    local c = Bitarray.new(10):set(3, 1):set(7, 1)
    check(c:bxor(a:slice(1, 10)) == Bitarray.new(10):set(1, true):set(5, true):set(9, true))
    local d = Bitarray.new(10):fill(true)
    check(d == d:shiftleft(0))
    check(d:shiftleft(1) == d:slice():set(10, false))
    check(d:shiftleft(9) == Bitarray.new(10):set(1, true))
    check(d:shiftleft(10) == Bitarray.new(10))
    check(d:shiftleft(11) == Bitarray.new(10))
    check(d == d:shiftright(0))
    check(d:shiftright(1) == d:slice():set(1, false))
    check(d:shiftright(9) == Bitarray.new(10):set(10, true))
    check(d:shiftright(10) == Bitarray.new(10))
    check(d:shiftright(11) == Bitarray.new(10))
    check(d:shiftleft(4) == d:shiftright(-4))
    local e = Bitarray.new(32):from_uint32(146)
    check(e:shiftleft(6):at_uint32(1) == 9344)
    check(e:shiftright(6):at_uint32(1) == 2)
    check(e:shiftright(-4) == e:shiftleft(4))
    local f = Bitarray.new(15):fill(true)
    f = f:bor(f)
    f:resize(32)
    for i = 16, 32 do check(not f[i]) end
end

print('all tests passed!')
