#pragma once

namespace lcodec {

    struct physical_node {
        uint32_t node_id;
        std::set<uint32_t> virtual_keys;
        physical_node(uint32_t nid) : node_id(nid){}
    };

    class ketama {
        public:
            /* node_id must be unique, weight between in [0, 255] */
            bool insert(const std::string& name, uint32_t node_id, const uint8_t weight) {
                physical_node cur_physical_node(node_id);
                uint32_t virtual_numbers = static_cast<uint32_t>((double)weight / UINT8_MAX * visual_num);
                for (uint32_t i = 0; i < virtual_numbers; ++i) {
                    std::string virtual_id = name + std::to_string(i);
                    uint32_t virtual_key = push_virtual_node(virtual_id, node_id);
                    cur_physical_node.virtual_keys.insert(virtual_key);
                }
                physical_map.insert(std::make_pair(node_id, cur_physical_node));
                return true;
            }

            void remove(uint32_t node_id){
                auto physical_it = physical_map.find(node_id);
                if (physical_it != physical_map.end()) {
                    for (auto virtual_key : physical_it->second.virtual_keys) {
                        virtual_map.erase(virtual_key);
                    }
                    physical_map.erase(physical_it);
                }
            }

            uint32_t next(uint32_t virtual_key) {
                if (virtual_map.empty()) {
                    return 0;
                }
                auto it = virtual_map.upper_bound(virtual_key);
                if (it == virtual_map.end())
                    it = virtual_map.begin();
                return it->second;
            }

            uint32_t front(uint32_t virtual_key) {
                if (virtual_map.empty()) {
                    return 0;
                }
                auto it = virtual_map.upper_bound(virtual_key);
                if (it == virtual_map.begin() || it == virtual_map.end())
                    return virtual_map.rbegin()->second;
                it--;
                return it->second;
            }

            uint32_t push_virtual_node(const std::string& virtual_id, uint32_t node_id) {
                size_t length = virtual_id.length();
                const char* data = virtual_id.c_str();
                uint32_t virtual_key = fnv_1a_32(data, length, 0);
                if (physical_map.empty()) {
                    virtual_map.insert(std::make_pair(virtual_key, node_id));
                    return virtual_key;
                }
                while(true) {
                    uint32_t nnext = next(virtual_key);
                    if (nnext == node_id) {
                        virtual_key = fnv_1a_32(data, length, virtual_key);
                        continue;
                    }
                    uint32_t nfront = front(virtual_key);
                    if (nfront == node_id) {
                        virtual_key = fnv_1a_32(data, length, virtual_key);
                        continue;
                    }
                    virtual_map.insert(std::make_pair(virtual_key, node_id));
                    break;
                }
                return virtual_key;
            }
            
            void set_visual_num(uint32_t num) {
                visual_num = num;
            }

        public:
            uint32_t visual_num = 40;
            std::map<uint32_t, uint32_t> virtual_map;
            std::map<uint32_t, physical_node> physical_map;
    };
}
