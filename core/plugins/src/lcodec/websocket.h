#pragma once

#include "lua_kit.h"

using namespace std;
using namespace luakit;

namespace lcodec {

    inline uint64_t byteswap8(uint64_t const u64) {
        uint8_t* data = (uint8_t*) &u64;
        return ((uint64_t)data[7] << 0)
            | ((uint64_t)data[6] << 8)
            | ((uint64_t)data[5] << 16)
            | ((uint64_t)data[4] << 24)
            | ((uint64_t)data[3] << 32)
            | ((uint64_t)data[2] << 40)
            | ((uint64_t)data[1] << 48)
            | ((uint64_t)data[0] << 56);
    }

    inline uint16_t byteswap2(uint16_t const u16) {
        uint8_t* data = (uint8_t*)&u16;
        return ((uint16_t)data[1] << 0)
            | ((uint16_t)data[0] << 8);
    }

    class wsscodec : public codec_base {
    public:
        virtual int load_packet(size_t data_len) {
            if (!m_slice) return 0;
            uint8_t* payload = (uint8_t*)m_slice->peek(sizeof(uint8_t), 1);
            if (!payload) return 0;
            uint8_t masklen = (((*payload) & 0x80) == 0x80) ? 4 : 0;
            uint8_t payloadlen = (*payload) & 0x7f;
            if (payloadlen < 0x7e) {
                m_packet_len = masklen + payloadlen + sizeof(uint16_t);
                return m_packet_len;
            }
            size_t ext_len = (payloadlen == 0x7f) ? 8 : 2;
            uint8_t* data = m_slice->peek(ext_len, sizeof(uint16_t));
            if (!data) return 0;
            size_t length = (payloadlen == 0x7f) ? byteswap8(*(uint64_t*)data) : byteswap2(*(uint16_t*)data);
            m_packet_len = masklen + ext_len + length + sizeof(uint16_t);
            if (m_packet_len > m_slice->size()) return 0;
            return m_packet_len;
        }

        virtual uint8_t* encode(lua_State* L, int index, size_t* len) {
            m_buf->clean();
            uint8_t* body = nullptr;
            size_t opcode = lua_tointeger(L, index);
            if (lua_type(L, index + 1) == LUA_TTABLE) {
                body = m_jcodec->encode(L, index + 1, len);
            } else {
                body = (uint8_t*)lua_tolstring(L, index + 1, len);
            }
            m_buf->write<uint8_t>((0x80 | opcode));
            if (*len < 0x7e) {
                m_buf->write<uint8_t>(*len);
            } else if (*len <= 0xffff) {
                m_buf->write<uint8_t>(0x7e);
                m_buf->write<uint16_t>(byteswap2(*len));
            } else {
                m_buf->write<uint8_t>(0x7f);
                m_buf->write<uint64_t>(byteswap8(*len));
            }
            m_buf->push_data(body, *len);
            return m_buf->data(len);
        }

        virtual size_t decode(lua_State* L) {
            uint8_t head = *(uint8_t*)m_slice->read<uint8_t>();
            if ((head & 0x80) != 0x80) throw lua_exception("sharded packet not suppert!");
            uint8_t payload  = *(uint8_t*)m_slice->read<uint8_t>();
            uint8_t opcode = head & 0xf;
            bool mask = ((payload & 0x80) == 0x80);
            payload = payload & 0x7f;
            if (payload >= 0x7e) {
                m_slice->erase((payload == 0x7f) ? 8 : 2);
            }
            int top = lua_gettop(L);
            lua_pushstring(L, "WSS");
            lua_pushinteger(L, opcode);
            if (mask) {
                size_t data_len;
                char* maskkey = (char*)m_slice->erase(4);
                char* data = (char*)m_slice->data(&data_len);
                xor_byte(data, maskkey, data_len, 4);
            }
            size_t osize = m_slice->size();
            if (opcode == 0x02) {
                m_jcodec->set_slice(m_slice);
                m_jcodec->decode(L);
            } else {
                lua_pushlstring(L, (char*)m_slice->head(), osize);
            }
            m_slice->erase(osize);
            return lua_gettop(L) - top;
        }

        void set_codec(codec_base* codec) {
            m_jcodec = codec;
        }

    protected:
        char* xor_byte(char* buffer, char* mask, size_t blen, size_t mlen) {
            for (size_t i = 0; i < blen; i++) {
                buffer[i] = buffer[i] ^ mask[i % mlen];
            }
            return buffer;
        }

    protected:
        codec_base* m_jcodec = nullptr;
    };
}
