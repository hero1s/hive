#pragma once

#include <deque>
#include <vector>
#include "lua_kit.h"

using namespace std;
using namespace luakit;

namespace lcodec {
    // cmd constants
    const uint8_t COM_SLEEP                 = 0x00;
    const uint8_t COM_CONNECT               = 0x0b;
    const uint8_t COM_STMT_PREPARE          = 0x16;
    const uint8_t COM_STMT_CLOSE            = 0x19;

    // constants
    //inline uint32_t CLIENT_FLAG             = 260047;   //0000 0011 1111 0111 1100 1111
    inline uint32_t CLIENT_FLAG             = 17037263; //1 0000 0011 1111 0111 1100 1111
    inline uint32_t MAX_PACKET_SIZE         = 0xffffff;
    inline uint32_t CLIENT_PLUGIN_AUTH      = 1 << 19;
    inline uint32_t CLIENT_DEPRECATE_EOF    = 1 << 24;

    // field types
    const uint16_t MYSQL_TYPE_TINY          = 0x01;
    const uint16_t MYSQL_TYPE_SHORT         = 0x02;
    const uint16_t MYSQL_TYPE_LONG          = 0x03;
    const uint16_t MYSQL_TYPE_FLOAT         = 0x04;
    const uint16_t MYSQL_TYPE_DOUBLE        = 0x05;
    const uint16_t MYSQL_TYPE_NULL          = 0x06;
    const uint16_t MYSQL_TYPE_LONGLONG      = 0x08;
    const uint16_t MYSQL_TYPE_INT24         = 0x09;
    const uint16_t MYSQL_TYPE_YEAR          = 0x0d;
    const uint16_t MYSQL_TYPE_VARCHAR       = 0x0f;
    const uint16_t MYSQL_TYPE_NEWDECIMAL    = 0xf6;

    // server status
    inline size_t SERVER_MORE_RESULTS_EXISTS    = 8;

    enum class packet_type: int
    {
        MP_OK   = 0,
        MP_ERR  = 1,
        MP_EOF  = 2,
        MP_DATA = 3,
        MP_INF  = 4,
    };

    struct mysql_cmd {
        uint8_t  cmd_id;
        size_t session_id;
    };

    struct mysql_column {
        string_view name;
        uint8_t type;
        uint16_t flags;
    };
    typedef vector<mysql_column> mysql_columns;

    class mysqlscodec : public codec_base {
    public:
        mysqlscodec(size_t session_id) {
            sessions.push_back(mysql_cmd{ COM_SLEEP, session_id });
        }

        virtual int load_packet(size_t data_len) {
            if (!m_slice) return 0;
            return data_len;
        }

        virtual uint8_t* encode(lua_State* L, int index, size_t* len) {
            m_buf->clean();
            // cmd_id
            uint8_t cmd_id = (uint8_t)lua_tointeger(L, index++);
            // session_id
            size_t session_id = lua_tointeger(L, index++);
            //4 byte header placeholder
            m_buf->write<uint32_t>(0);
            if (cmd_id != COM_CONNECT) {
                return comand_encode(L, cmd_id, session_id, index, len);
            }
            return auth_encode(L, cmd_id, session_id, index, len);
        }

        virtual size_t decode(lua_State* L) {
            int top = lua_gettop(L);
            if (sessions.empty()) {
                throw lua_exception("invalid mysql data");
            }
            size_t osize = m_slice->size();
            mysql_cmd cmd = sessions.front();
            lua_pushinteger(L, cmd.session_id);
            switch (cmd.cmd_id) {
            case COM_SLEEP:
                auth_decode(L);
                break;
            case COM_STMT_PREPARE:
                prepare_decode(L);
                break;
            default:
                command_decode(L);
                break;
            }
            sessions.pop_front();
            m_packet_len = osize - m_slice->size();
            return lua_gettop(L) - top;
        }

    protected:
        packet_type recv_packet() {
            uint32_t payload = *(uint32_t*)m_slice->read<uint32_t>();
            uint32_t length = (payload & 0xffffff);
            if (length >= 0xffffff) {
                throw lua_exception("sharded packet not suppert!");
            }
            uint8_t* data = m_slice->erase(length);
            if (!data) {
                throw length_error("mysql text not full");
            }
            m_packet.attach(data, length);
            switch (*data) {
            case 0xfb: return packet_type::MP_INF;
            case 0xfe: return packet_type::MP_EOF;
            case 0x00: return packet_type::MP_OK;
            case 0xff: return packet_type::MP_ERR;
            }
            return packet_type::MP_DATA;
        }

        uint8_t* comand_encode(lua_State* L, uint8_t cmd_id, size_t session_id, int index, size_t* len) {
            m_buf->write<uint8_t>(cmd_id);
            int top = lua_gettop(L);
            if (index <= top) {
                if (lua_type(L, index) == LUA_TNUMBER) {
                    m_buf->write<uint32_t>(lua_tointeger(L, index++));
                }
                else {
                    size_t data_len;
                    uint8_t* query = (uint8_t*)lua_tolstring(L, index++, &data_len);
                    m_buf->push_data(query, data_len);
                }
            }
            if (index <= top) {
                encode_stmt_args(L, index, top - index + 1);
            }
            // header
            uint32_t size = (m_buf->size() - 4) & 0xffffff;
            m_buf->copy(0, (uint8_t*)&size, 4);
            // cmd
            if (cmd_id != COM_STMT_CLOSE) {
                sessions.push_back(mysql_cmd{ cmd_id, session_id });
            }
            return m_buf->data(len);
        }

        uint8_t* auth_encode(lua_State* L, uint8_t cmd_id, size_t session_id, int index, size_t* len) {
            //4 byte client_flag
            m_buf->write<uint32_t>(CLIENT_FLAG);
            //4 byte max_packet_size
            m_buf->write<uint32_t>(MAX_PACKET_SIZE);
            //1 byte character_set
            m_buf->write<uint8_t>((uint8_t)lua_tointeger(L, index++));
            //23 byte filler(all 0)
            m_buf->pop_space(23);
            // username
            uint8_t* user = (uint8_t*)lua_tolstring(L, index++, len);
            m_buf->push_data(user, *len);
            m_buf->push_data((uint8_t*)"\0", 1);
            // auth_data
            uint8_t* auth_data = (uint8_t*)lua_tolstring(L, index++, len);
            m_buf->write<uint8_t>(*len);
            m_buf->push_data(auth_data, *len);
            // dbname
            const uint8_t* dbname = (const uint8_t*)lua_tolstring(L, index++, len);
            m_buf->push_data(dbname, *len);
            m_buf->push_data((uint8_t*)"\0", 1);
            // header
            uint32_t size = ((m_buf->size() - 4) & 0xffffff) | 0x01000000;
            m_buf->copy(0, (uint8_t*)&size, 4);
            // cmd
            sessions.push_back(mysql_cmd{ cmd_id, session_id });
            return m_buf->data(len);
        }

        void command_decode(lua_State* L) {
            packet_type type = recv_packet();
            switch (type) {
            case packet_type::MP_OK:
                return ok_packet_decode(L);
            case packet_type::MP_DATA:
                return data_packet_decode(L);
            case packet_type::MP_ERR:
                return err_packet_decode(L);
            default: throw lua_exception("unsuppert mysql packet type");
            }
        }

        void field_decode(mysql_columns& columns) {
            string_view catalog = decode_length_encoded_string();
            string_view schema = decode_length_encoded_string();
            string_view table = decode_length_encoded_string();
            string_view org_table = decode_length_encoded_string();
            string_view name = decode_length_encoded_string();
            string_view org_name = decode_length_encoded_string();
            // 1 byte fix length (skip)
            // 2 byte character_set (skip)
            // 4 byte column_length (skip)
            m_packet.erase(7);
            uint8_t type = *(uint8_t*)m_packet.read<uint8_t>();
            uint16_t flags = *(uint16_t*)m_packet.read<uint16_t>();
            uint8_t decimals = *(uint8_t*)m_packet.read<uint8_t>();
            columns.push_back(mysql_column { name, type, decimals });
        }

        packet_type rows_decode(lua_State* L, mysql_columns& columns) {
            // rows
            size_t row_indx = 1;
            packet_type type = recv_packet();
            while (type == packet_type::MP_DATA){
                // row
                lua_createtable(L, 0, 8);
                for (const mysql_column& column : columns) {
                    auto value = decode_length_encoded_string();
                    lua_pushlstring(L, column.name.data(), column.name.size());
                    switch (column.type) {
                    case MYSQL_TYPE_FLOAT:
                    case MYSQL_TYPE_DOUBLE:
                        lua_pushnumber(L, strtod(value.data(), nullptr));
                        break;
                    case MYSQL_TYPE_TINY:
                    case MYSQL_TYPE_SHORT:
                    case MYSQL_TYPE_LONG:
                    case MYSQL_TYPE_INT24:
                    case MYSQL_TYPE_YEAR:
                    case MYSQL_TYPE_LONGLONG:
                    case MYSQL_TYPE_NEWDECIMAL:
                        lua_pushinteger(L, strtoll(value.data(), nullptr, 10));
                        break;
                    default:
                        lua_pushlstring(L, value.data(), value.size());
                        break;
                    }
                    lua_rawset(L, -3);
                }
                lua_seti(L, -2, row_indx++);
                type = recv_packet();
            }
            return type;
        }

        bool result_set_decode(lua_State* L, size_t top, size_t rset_idx) {
            // result set header
            lua_createtable(L, 0, 8);
            size_t column_count = decode_length_encoded_number();
            // field metadata
            mysql_columns columns;
            for (size_t i = 0; i < column_count; ++i) {
                recv_packet();
                field_decode(columns);
            }
            // field eof
            if ((m_capability & CLIENT_DEPRECATE_EOF) != CLIENT_DEPRECATE_EOF) {
                recv_packet();
                eof_packet_decode();
            }
            // rows data
            packet_type type = rows_decode(L, columns);
            lua_seti(L, -2, rset_idx);
            // terminator
            if (type == packet_type::MP_ERR) {
                lua_settop(L, top);
                err_packet_decode(L);
                return false;
            }
            // rows eof
            return eof_packet_decode();
        }

        void data_packet_decode(lua_State* L) {
            size_t rset_idx = 1;
            int top = lua_gettop(L);
            lua_pushboolean(L, true);
            //result sets
            lua_createtable(L, 0, 4);
            bool more = result_set_decode(L, top, rset_idx++);
            while (more) {
                recv_packet();
                more = result_set_decode(L, top, rset_idx++);
            }
        }

        void ok_packet_decode(lua_State* L) {
            //type
            m_packet.read<uint8_t>();
            lua_pushboolean(L, true);
            lua_createtable(L, 0, 4);
            //affected_rows
            lua_pushinteger(L, decode_length_encoded_number());
            lua_setfield(L, -2, "affected_rows");
            //last_insert_id
            lua_pushinteger(L, decode_length_encoded_number());
            lua_setfield(L, -2, "last_insert_id");
            //status_flags
            m_packet.read<uint16_t>();
            //warnings
            lua_pushinteger(L, *(uint16_t*)m_packet.read<uint16_t>());
            lua_setfield(L, -2, "warnings");
            //info
            auto info = m_packet.eof();
            lua_pushlstring(L, info.data(), info.size());
            lua_setfield(L, -2, "info");
        }

        void err_packet_decode(lua_State* L) {
            //type
            m_packet.read<uint8_t>();
            lua_pushboolean(L, false);
            lua_createtable(L, 0, 4);
            //errnoo
            lua_pushinteger(L, *(uint16_t*)m_packet.read<uint16_t>());
            lua_setfield(L, -2, "errnoo");
            //1 byte sql_state_marker (skip)
            m_packet.erase(1);
            //5 byte sql_state
            char* sql_state = (char*)m_packet.erase(5);
            lua_pushlstring(L, sql_state, 5);
            lua_setfield(L, -2, "sql_state");
            //error_message
            auto error_message = m_packet.eof();
            lua_pushlstring(L, error_message.data(), error_message.size());
            lua_setfield(L, -2, "error_message");
        }

        bool eof_packet_decode() {
            //type
            m_packet.read<uint8_t>();
            if ((m_capability & CLIENT_DEPRECATE_EOF) == CLIENT_DEPRECATE_EOF) {
                size_t affected_rows = decode_length_encoded_number();
                size_t last_insert_id = decode_length_encoded_number();
                uint16_t status_flags = *(uint16_t*)m_packet.read<uint16_t>();
                uint16_t warnings = *(uint16_t*)m_packet.read<uint16_t>();
                auto info = m_packet.eof();
                return ((status_flags & SERVER_MORE_RESULTS_EXISTS) == SERVER_MORE_RESULTS_EXISTS);
            }
            else {
                uint16_t warnings = *(uint16_t*)m_packet.read<uint16_t>();
                uint16_t status_flags = *(uint16_t*)m_packet.read<uint16_t>();
                return ((status_flags & SERVER_MORE_RESULTS_EXISTS) == SERVER_MORE_RESULTS_EXISTS);
            }
        }

        void prepare_decode(lua_State* L) {
            recv_packet();
            uint8_t status = *(uint8_t*)m_packet.read<uint8_t>();
            uint32_t statement_id = *(uint32_t*)m_packet.read<uint32_t>();
            uint16_t num_columns = *(uint16_t*)m_packet.read<uint16_t>();
            uint16_t num_params = *(uint16_t*)m_packet.read<uint16_t>();
            int top = lua_gettop(L);
            lua_pushinteger(L, statement_id);
            lua_pushinteger(L, num_columns);
            lua_pushinteger(L, num_params);
        }

        void auth_decode(lua_State* L) {
            recv_packet();
            //1 byte protocol version
            uint8_t proto = *(uint8_t*)m_packet.read<uint8_t>();
            //n byte server version
            size_t data_len;
            const char* version = read_cstring(m_packet, data_len);
            //4 byte thread_id
            uint32_t thread_id = *(uint32_t*)m_packet.read<uint32_t>();
            //8 byte auth-plugin-data-part-1
            uint8_t* scramble1 = m_packet.peek(8);
            //8 byte auth-plugin-data-part-1 + 1 byte filler
            m_packet.erase(9);
            //2 byte capability_flags_1
            uint16_t capability_flag_1 = *(uint16_t*)m_packet.read<uint16_t>();
            //1 byte character_set
            uint8_t character_set = *(uint8_t*)m_packet.read<uint8_t>();
            lua_pushinteger(L, character_set);
            //2 byte status_flags
            uint16_t status_flags = *(uint16_t*)m_packet.read<uint16_t>();
            //2 byte capability_flags_2
            uint16_t capability_flag_2 = *(uint16_t*)m_packet.read<uint16_t>();
            m_capability = CLIENT_FLAG & (capability_flag_2 << 16 | capability_flag_1);
            //1 byte character_set
            uint8_t auth_plugin_data_len = *(uint8_t*)m_packet.read<uint8_t>();
            //10 byte reserved (all 0)
            m_packet.erase(10);
            //auth-plugin-data-part-2
            char* scramble2 = nullptr;
            auth_plugin_data_len = std::max(13, auth_plugin_data_len - 8);
            scramble2 = (char*)m_packet.erase(auth_plugin_data_len);
            lua_pushlstring(L, (char*)scramble1, 8);
            lua_pushlstring(L, scramble2, 12);
            //auth_plugin_name
            const char* auth_plugin_name = nullptr;
            if ((m_capability & CLIENT_PLUGIN_AUTH) == CLIENT_PLUGIN_AUTH) {
                auth_plugin_name = read_cstring(m_packet, data_len);
                lua_pushlstring(L, auth_plugin_name, data_len);
            }
        }

        void encode_stmt_args(lua_State* L, int index, int argnum) {
            //enum_cursor_type
            m_buf->write<uint8_t>(0);
            //iteration_count
            m_buf->write<uint32_t>(1);
            //null_bitmap, length= (argnum + 7) / 8
            int argpos = 0;
            int argbyte = (argnum + 7) / 8;
            for (int i = 0; i < argbyte; ++i) {
                uint8_t byte = 0;
                for (int j = 0; j < 7; ++j) {
                    int aindex = index + argpos++;
                    if (aindex < argnum) {
                        uint8_t bit = lua_isnil(L, aindex) ? 0 : 1;
                        byte |= (bit < j);
                    }
                }
                m_buf->write<uint8_t>(byte);
            }
            //new_params_bind_flag
            m_buf->write<uint8_t>(1);
            //parameter_type
            for (int i = 0; i < argnum; ++i) {
                encode_args_type(L, index + i);
            }
            //parameter_values
            for (int i = 0; i < argnum; ++i) {
                encode_args_value(L, index + i);
            }
        }

        void encode_args_type(lua_State* L, int index) {
            int type = lua_type(L, index);
            switch (type) {
            case LUA_TNIL:
                m_buf->write<uint16_t>(MYSQL_TYPE_NULL);
                break;
            case LUA_TBOOLEAN:
                m_buf->write<uint16_t>(MYSQL_TYPE_TINY);
                break;
            case LUA_TSTRING:
                m_buf->write<uint16_t>(MYSQL_TYPE_VARCHAR);
                break;
            case LUA_TNUMBER:
                m_buf->write<uint16_t>(lua_isinteger(L, index) ? MYSQL_TYPE_LONGLONG : MYSQL_TYPE_DOUBLE);
                break;
            default:
                throw lua_exception("invalid mysql stmt args type");
            }
        }

        void encode_args_value(lua_State* L, int index) {
            switch (lua_type(L, index)) {
            case LUA_TBOOLEAN:
                m_buf->write<uint8_t>(lua_toboolean(L, index) ? 1 : 0);
                break;
            case LUA_TNUMBER:
                lua_isinteger(L, index) ? m_buf->write<uint64_t>(lua_tointeger(L, index)) : m_buf->write<double>(lua_tonumber(L, index));
                break;
            case LUA_TSTRING: {
                    uint32_t data_len;
                    uint8_t* data = (uint8_t*)lua_tolstring(L, index, (size_t*)&data_len);
                    if (data_len < 0xfb) {
                        m_buf->write<uint8_t>(data_len);
                    }
                    else if (data_len < 0xffff) {
                        m_buf->write<uint8_t>(0xfc);
                        m_buf->write<uint16_t>(data_len);
                    }
                    else if (data_len < 0xffffff) {
                        m_buf->write<uint32_t>((0xfd << 24) | data_len);
                    }
                    else {
                        m_buf->write<uint8_t>(0xfe);
                        m_buf->write<uint64_t>(data_len);
                    }
                    m_buf->push_data(data, data_len);
                }
                break;
            }
        }

        size_t decode_length_encoded_number() {
            uint8_t nbyte = *(uint8_t*)m_packet.read<uint8_t>();
            if (nbyte < 0xfb) return nbyte;
            if (nbyte == 0xfc) return *(uint16_t*)m_packet.read<uint16_t>();
            if (nbyte == 0xfd) return *(uint32_t*)m_packet.read<uint32_t>();
            if (nbyte == 0xfe) return *(uint64_t*)m_packet.read<uint64_t>();
            return 0;
        }

        string_view decode_length_encoded_string() {
            size_t length = decode_length_encoded_number();
            if (length > 0) {
                char* data = (char*)m_packet.erase(length);
                if (!data) throw lua_exception("invalid length coded string");
                return string_view(data, length);
            }
            return "";
        }

        const char* read_cstring(slice& slice, size_t& l) {
            size_t sz;
            const char* dst = (const char*)slice.data(&sz);
            for (l = 0; l < sz; ++l) {
                if (dst[l] == '\0') {
                    slice.erase(l + 1);
                    return dst;
                }
                if (l == sz - 1) throw lua_exception("invalid mysql block : cstring");
            }
            throw lua_exception("invalid mysql block : cstring");
            return "";
        }

    protected:
        deque<mysql_cmd> sessions;
        uint32_t m_capability = 0;
        slice m_packet;
    };
}
