#pragma once

#include "lua_kit.h"

using namespace std;
using namespace luakit;

namespace lcodec {

    class wsscodec : public codec_base {
    public:
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
            if (*len < 126) {
                m_buf->write<uint8_t>(*len);
            } else if (*len < 0xffff) {
                m_buf->write<uint8_t>(126);
                m_buf->write<uint16_t>(*len);
            } else {
                m_buf->write<uint8_t>(127);
                m_buf->write<uint64_t>(*len);
            }
            m_buf->push_data(body, *len);
            return m_buf->data(len);
        }

        virtual size_t decode(lua_State* L) {
            if (!m_slice) return 0;
            uint8_t head = *(uint8_t*)m_slice->read<uint8_t>();
            if ((head & 0x80) != 0x80) throw length_error("shared packet not suppert!");
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
                char* maskkey = (char*)m_slice->peek(4);
                m_slice->erase(4);
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

        void set_buff(luabuf* buf) {
            m_buf = buf;
        }

    protected:
        char* xor_byte(char* buffer, char* mask, size_t blen, size_t mlen) {
            for (int i = 0; i < blen; i++) {
                buffer[i] = buffer[i] ^ mask[i % mlen];
            }
            return buffer;
        }

    protected:
        luabuf*     m_buf = nullptr;
        codec_base* m_jcodec = nullptr;
    };
}
