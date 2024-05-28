#define LUA_LIB

#include "lua_kit.h"
#include "yaml.h"
#include "yaml_private.h"

using namespace luakit;

namespace lyaml {

    thread_local unsigned char YAML_BUFFER[SHRT_MAX];

    class ydoc_guard {
    public:
        ydoc_guard(yaml_document_t* doc) : ymdoc(doc) {}
        ~ydoc_guard() { yaml_document_delete(ymdoc); }
    private:
        yaml_document_t* ymdoc = nullptr;
    };

    class yemitter_guard {
    public:
        yemitter_guard(yaml_emitter_t* par) : emitter(par) {}
        ~yemitter_guard() { yaml_emitter_delete(emitter); }
    private:
        yaml_emitter_t* emitter = nullptr;
    };

    class yparser_guard {
    public:
        yparser_guard(yaml_parser_t* par) : parser(par) {}
        ~yparser_guard() { yaml_parser_delete(parser); }
    private:
        yaml_parser_t* parser = nullptr;
    };

    inline void yaml_emitter_error(lua_State* L, yaml_emitter_t* emitter) {
        switch (emitter->error) {
        case YAML_MEMORY_ERROR:
            luaL_error(L, "error: Not enough memory for parsing");
            break;
        case YAML_WRITER_ERROR:
        case YAML_EMITTER_ERROR:
            fprintf(stderr, "error: %s", emitter->problem);
            break;
        default:
            luaL_error(L, "internal error");
            break;
        }
    }

    inline void yaml_parser_error(lua_State* L, yaml_parser_t* parser) {
        switch (parser->error) {
        case YAML_MEMORY_ERROR:
            luaL_error(L, "error: Not enough memory for parsing");
            break;
        case YAML_READER_ERROR:
            if (parser->problem_value != -1) {
                luaL_error(L, "error: %s: #%X at %d", parser->problem, parser->problem_value, parser->problem_offset);
            }
            else {
                luaL_error(L, "error: %s at %d", parser->problem, parser->problem_offset);
            }
            break;
        case YAML_COMPOSER_ERROR:
        case YAML_SCANNER_ERROR:
        case YAML_PARSER_ERROR:
            if (parser->context) {
                luaL_error(L, "error: %s at line %d, column %d, %s at line %d, column %d", parser->context, parser->context_mark.line+1,
                        parser->context_mark.column+1, parser->problem, parser->problem_mark.line+1, parser->problem_mark.column+1);
            }
            else {
                luaL_error(L, "error: %s at line %d, column %d", parser->problem, parser->problem_mark.line+1, parser->problem_mark.column+1);
            }
            break;
        default:
            luaL_error(L, "internal error");
            break;
        }
    }

    inline void decode_node(lua_State* L, yaml_document_t* doc, yaml_node_t* node);
    inline void decode_scalar(lua_State* L, yaml_node_t* node) {
        const char* value = (const char*)node->data.scalar.value;
        if (lua_stringtonumber(L, value) == 0) {
            lua_pushlstring(L, value, node->data.scalar.length);
        }
    }

    inline void decode_sequence(lua_State* L, yaml_document_t* doc, yaml_node_t* node) {
        size_t idx = 1;
        lua_createtable(L, 0, 4);
        for (yaml_node_item_t* item = node->data.sequence.items.start; item != node->data.sequence.items.top; ++item) {
            yaml_node_t* node = yaml_document_get_node(doc, *item);
            decode_node(L, doc, node);
            lua_seti(L, -2, idx++);
        }
    }

    inline void decode_refrenence(lua_State* L, yaml_document_t* doc, yaml_node_t* node) {
        for (yaml_node_pair_t* pair = node->data.mapping.pairs.start; pair != node->data.mapping.pairs.top; ++pair) {
            yaml_node_t* knode = yaml_document_get_node(doc, pair->key);
            yaml_node_t* vnode = yaml_document_get_node(doc, pair->value);
            decode_node(L, doc, knode);
            decode_node(L, doc, vnode);
            lua_settable(L, -3);
        }
    }

    inline void decode_mapping(lua_State* L, yaml_document_t* doc, yaml_node_t* node) {
        lua_createtable(L, 0, 4);
        for (yaml_node_pair_t* pair = node->data.mapping.pairs.start; pair != node->data.mapping.pairs.top; ++pair) {
            yaml_node_t* knode = yaml_document_get_node(doc, pair->key);
            yaml_node_t* vnode = yaml_document_get_node(doc, pair->value);
            if (knode->type == YAML_SCALAR_NODE && (strncmp((const char*)knode->data.scalar.value, "<<", 2) == 0) && vnode->type == YAML_MAPPING_NODE) {
                decode_refrenence(L, doc, vnode);
                continue;
            }
            decode_node(L, doc, knode);
            decode_node(L, doc, vnode);
            lua_settable(L, -3);
        }
    }

    inline void decode_node(lua_State* L, yaml_document_t* doc, yaml_node_t* node) {
        switch (node->type) {
        case YAML_SCALAR_NODE:
            decode_scalar(L, node);
            break;
        case YAML_SEQUENCE_NODE:
            decode_sequence(L, doc, node);
            break;
        case YAML_MAPPING_NODE:
            decode_mapping(L, doc, node);
            break;
        }
    }

    inline int decode_yaml(lua_State* L, const char* yaml) {
        size_t index = 1;
        yaml_parser_t parser;
        yaml_document_t document;
        yaml_parser_initialize(&parser);
        yaml_parser_set_input_string(&parser, (const unsigned char*)yaml, strlen(yaml));
        yparser_guard gp(&parser);
        if (!yaml_parser_load(&parser, &document)) {
            yaml_parser_error(L, &parser);
            return 0;
        }
        if (!yaml_document_get_root_node(&document)) {
            return 0;
        }
        ydoc_guard gd(&document);
        lua_createtable(L, 0, 4);
        yaml_node_t* node = yaml_document_get_root_node(&document);
        decode_node(L, &document, node);
        return 1;
    }

    inline int encode_value(lua_State* L, yaml_document_t* doc, int index);
    inline int encode_sequence(lua_State* L, yaml_document_t* doc, int index) {
        int sequence = yaml_document_add_sequence(doc, nullptr, YAML_BLOCK_SEQUENCE_STYLE);
        int raw_len = lua_rawlen(L, index);
        for (int i = 1; i <= raw_len; ++i) {
            lua_rawgeti(L, index, i);
            int item = encode_value(L, doc, -1);
            yaml_document_append_sequence_item(doc, sequence, item);
            lua_pop(L, 1);
        }
        return sequence;
    }

    inline int encode_mapping(lua_State* L, yaml_document_t* doc, int index) {
        lua_pushnil(L);
        int maping = yaml_document_add_mapping(doc, nullptr, YAML_BLOCK_MAPPING_STYLE);
        while (lua_next(L, index) != 0) {
            int key = encode_value(L, doc, -2);
            int value = encode_value(L, doc, -1);
            yaml_document_append_mapping_pair(doc, maping, key, value);
            lua_pop(L, 1);
        }
        return maping;
    }

    inline int encode_table(lua_State* L, yaml_document_t* doc, int index) {
        if (luakit::is_lua_array(L, index)) {
            return encode_sequence(L, doc, index);
        } 
        return encode_mapping(L, doc, lua_absindex(L, index));
    }

    inline int encode_value(lua_State* L, yaml_document_t* doc, int index) {
        size_t len;
        switch (lua_type(L, index)) {
        case LUA_TNIL:
            return yaml_document_add_scalar(doc, nullptr, (yaml_char_t*)"~", 1, YAML_PLAIN_SCALAR_STYLE);
        case LUA_TTABLE:
            return encode_table(L, doc, index);
        case LUA_TNUMBER: {
                yaml_char_t* nstr = (yaml_char_t*)lua_tolstring(L, index, &len);
                return yaml_document_add_scalar(doc, nullptr, nstr, len, YAML_PLAIN_SCALAR_STYLE);
            }
        case LUA_TBOOLEAN:{
                yaml_char_t* bstr = (yaml_char_t*)(lua_toboolean(L, index) ? "true" : "false");
                return yaml_document_add_scalar(doc, nullptr, bstr, strlen((const char*)bstr), YAML_PLAIN_SCALAR_STYLE);
            }
        case LUA_TSTRING: {
                yaml_char_t* sstr = (yaml_char_t*)lua_tolstring(L, index, &len);
                return yaml_document_add_scalar(doc, nullptr, sstr, len, YAML_PLAIN_SCALAR_STYLE);
            }
        }
        luaL_error(L, "unsuppert lua type");
        return 0;
    }

    inline int encode_yaml(lua_State* L) {
        yaml_document_t document;
        if (!yaml_document_initialize(&document, nullptr, nullptr, nullptr, 0, 0)) {
            luaL_error(L, "error: Not enough memory for parsing");
        }
        ydoc_guard gd(&document);
        encode_table(L, &document, 1);

        yaml_emitter_t emitter;
        if (!yaml_emitter_initialize(&emitter)) {
            yaml_emitter_error(L, &emitter);
        }
        size_t data_len;
        yemitter_guard ge(&emitter);
        yaml_emitter_set_output_string(&emitter, YAML_BUFFER, SHRT_MAX, &data_len);
        yaml_emitter_set_unicode(&emitter, 1);

        if (!yaml_emitter_dump(&emitter, &document)) {
            yaml_emitter_error(L, &emitter);
        }
        lua_pushlstring(L, (const char*)YAML_BUFFER, data_len);
        return 1;
    }

    inline FILE* fopenyaml(const char* filepath, const char* mode) {
#if defined(_MSC_VER)
        FILE* fp = 0;
        const errno_t err = fopen_s(&fp, filepath, mode);
        if (err) return nullptr;
#else
        FILE* fp = fopen(filepath, mode);
#endif
        return fp;
    }

    inline int open_yaml(lua_State* L, const char* yamlfile) {
        FILE* fp = fopenyaml(yamlfile, "r");
        if (fp == nullptr) {
            luaL_error(L, "open file error");
            return 0;
        }
        size_t index = 1;
        yaml_parser_t parser;
        yaml_document_t document;
        yaml_parser_initialize(&parser);
        yaml_parser_set_input_file(&parser, fp);
        yparser_guard gp(&parser);
        int ok = yaml_parser_load(&parser, &document);
        fclose(fp);
        if (!ok) {
            yaml_parser_error(L, &parser);
            return 0;
        }
        if (!yaml_document_get_root_node(&document)) {
            return 0;
        }
        ydoc_guard gd(&document);
        lua_createtable(L, 0, 4);
        yaml_node_t* node = yaml_document_get_root_node(&document);
        decode_node(L, &document, node);
        return 1;
    }

    static int save_yaml(lua_State* L, const char* yamlfile) {
        yaml_document_t document;
        if (!yaml_document_initialize(&document, nullptr, nullptr, nullptr, 0, 0)) {
            luaL_error(L, "error: Not enough memory for parsing");
        }
        ydoc_guard gd(&document);
        encode_table(L, &document, 2);

        yaml_emitter_t emitter;
        if (!yaml_emitter_initialize(&emitter)) {
            yaml_emitter_error(L, &emitter);
        }
        yemitter_guard ge(&emitter);
        yaml_emitter_set_unicode(&emitter, 1);
        FILE* fp = fopenyaml(yamlfile, "w");
        if (fp == nullptr) {
            lua_pushboolean(L, false);
            lua_pushstring(L, "open file error");
            return 2;
        }
        yaml_emitter_set_output_file(&emitter, fp);
        int ok = yaml_emitter_dump(&emitter, &document);
        fclose(fp);
        if (!ok) {
            yaml_emitter_error(L, &emitter);
        }
        lua_pushboolean(L, true);
        fclose(fp);
        return 1;
    }

    lua_table open_lyaml(lua_State* L) {
        kit_state kit_state(L);
        lua_table yaml = kit_state.new_table("yaml");
        yaml.set_function("decode", decode_yaml);
        yaml.set_function("encode", encode_yaml);
        yaml.set_function("open", open_yaml);
        yaml.set_function("save", save_yaml);
        return yaml;
    }
}

extern "C" {
    LUALIB_API int luaopen_lyaml(lua_State* L) {
        auto yaml = lyaml::open_lyaml(L);
        return yaml.push_stack();
    }
}
