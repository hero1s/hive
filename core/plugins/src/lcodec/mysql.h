#pragma once

#include "lua_kit.h"

using namespace std;
using namespace luakit;

namespace lcodec {

    class mysqlscodec : public codec_base {
    public:
        virtual uint8_t* encode(lua_State* L, int index, size_t* len) {
            m_buf->clean();
            return m_buf->data(len);
        }

        virtual size_t decode(lua_State* L) {
            if (!m_slice) return 0;
            int top = lua_gettop(L);
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
