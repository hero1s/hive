#pragma once
#include <stddef.h>
#include <stdint.h>

#define MAX_VARINT_SIZE  16

namespace luakit {

	// 将无符号整数编码到字节数组
	// 返回值: 成功,返回编码长度; 失败,返回0;
	inline size_t encode_u64(unsigned char* buffer, size_t buffer_size, uint64_t value){
		auto pos = buffer, end = buffer + buffer_size;
		do
		{
			if (pos >= end)
				return 0;
			auto code = (unsigned char)(value & 0x7F);
			value >>= 7;
			*pos++ = code | (value > 0 ? 0x80 : 0);
		} while (value > 0);
		return (size_t)(pos - buffer);
	}
	// 从字节数组解码无符号整数
	// 返回值: 成功,返回解码长度; 失败,返回0;
	inline size_t decode_u64(uint64_t* value, const unsigned char* data, size_t data_len){
		auto pos = data, end = data + data_len;
		uint64_t code = 0, number = 0;
		int bits = 0;
		// 在编码时,把数据按照7bit一组一组的编码,最多10个组,也就是10个字节
		// 第1组无需移位,第2组右移7位,第3组......,第10组(其实只有1位有效)右移了63位;
		// 所以,在解码的时候,最多左移63位就结束了:)
		while (true)
		{
			if (pos >= end || bits > 63)
				return 0;
			code = *pos & 0x7F;
			number |= (code << bits);
			if ((*pos++ & 0x80) == 0)
				break;
			bits += 7;
		}
		*value = number;
		return (size_t)(pos - data);
	}
	// 将有符号整数编码到字节数组
	// 返回值: 成功,返回编码长度; 失败,返回0;
	inline size_t encode_s64(unsigned char* buffer, size_t buffer_size, int64_t value){
		uint64_t uvalue = (uint64_t)value;
		if (value < 0) {
			--uvalue;
			uvalue = ~uvalue;
			uvalue <<= 1;
			uvalue |= 0x1;
		} else {
			uvalue <<= 1;
		}
		return encode_u64(buffer, buffer_size, uvalue);
	}
	// 从字节数组解码有符号整数
	// 返回值: 成功,返回解码长度; 失败,返回0;
	inline size_t decode_s64(int64_t* value, const unsigned char* data, size_t data_len){
		uint64_t uvalue = 0;
		size_t count = decode_u64(&uvalue, data, data_len);
		if (count == 0)	return 0;
		if (uvalue & 0x1) {
			uvalue >>= 1;
			if (uvalue == 0) {
				uvalue = 0x1ull << 63;
			}
			uvalue = ~uvalue;
			uvalue++;
		} else {
			uvalue >>= 1;
		}
		*value = (int64_t)uvalue;
		return count;
	}
}