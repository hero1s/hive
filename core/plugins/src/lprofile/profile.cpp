#include "profile.h"
#include <chrono>
#include <assert.h>
#include <cstdio>
#include <stdio.h>
#include "lua_kit.h"

namespace lprofile
{
#ifndef SAFE_DELETE
#define SAFE_DELETE(x)  \
    if (nullptr != x) { \
        delete x;       \
        x = nullptr;    \
    }
#endif

    enum PROFILETYPE {
        PROFILETYPE_NONE = 0, //无统计
        PROFILETYPE_SIMPLE = 1, //简易
        PROFILETYPE_PRECISION = 2, //精确
    };

    inline void profileGetTime(int64_t* time)
    {
        *time = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
    }

    ProfileNode::ProfileNode(const char* node_name, ProfileNode* parent_node, ProfileManager* mgr)
        : m_total_calls(0)
        , m_recursion_counter(0)
        , m_total_time(0.0f)
        , m_peak_value(0.0f)
        , m_percent_in_parent(0.0f)
        , m_start_time(0)
        , m_node_name(node_name)
        , m_parent_node(parent_node)
        , m_child_node(NULL)
        , m_sibling_node(NULL)
        , m_mgr(mgr)
    {
        reset();
    }

    ProfileNode::~ProfileNode()
    {
        if (m_child_node) {
            SAFE_DELETE(m_child_node);
        }
        if (m_sibling_node) {
            SAFE_DELETE(m_sibling_node);
        }
    }

    ProfileNode* ProfileNode::getSubNode(const char* node_name)
    {
        if (NULL == node_name) {
            return NULL;
        }
        ProfileNode* temp_child = m_child_node;
        while (temp_child) {
            if (0 == strcmp(node_name, temp_child->getNodeName())) {
                return temp_child;
            }
            temp_child = temp_child->getSiblingNode();
        }
        //如果有没找到则新建
        ProfileNode* new_node = new ProfileNode(node_name, this, this->m_mgr);
        new_node->m_sibling_node = m_child_node;
        m_child_node = new_node;
        printf(" [%s] add new anazy node:[%s] \n", getNodeName(), node_name);
        return new_node;
    }

    ProfileNode* ProfileNode::getSubNode(int index)
    {
        ProfileNode* temp_child = m_child_node;
        while (temp_child && index--) {
            temp_child = temp_child->getSiblingNode();
        }
        return temp_child;
    }

    void ProfileNode::reset(void)
    {
        m_total_calls = 0;
        m_total_time = 0.0f;
        m_peak_value = 0.0f;
        if (m_child_node) {
            m_child_node->reset();
        }
        if (m_sibling_node) {
            m_sibling_node->reset();
        }
    }

    void ProfileNode::enter(void)
    {
        m_total_calls++;
        if (0 == m_recursion_counter++) {
            switch (m_mgr->getProfileType()) {
            case PROFILETYPE_NONE: {
                break;
            }
            case PROFILETYPE_SIMPLE: {
                profileGetTime(&m_start_time);
                break;
            }
            case PROFILETYPE_PRECISION: {
                profileGetTime(&m_start_time);
                break;
            }
            default:
                break;
            }
        }
    }

    bool ProfileNode::leave(void)
    {
        if (0 == --m_recursion_counter && 0 != m_total_calls) {
            switch (m_mgr->getProfileType()) {
            case PROFILETYPE_NONE: {
                break;
            }
            case PROFILETYPE_SIMPLE: {
                int64_t cur_time;
                profileGetTime(&cur_time);
                float real_time = (float)((cur_time - m_start_time) / 1000000.0f);
                if (real_time > m_peak_value) {
                    m_peak_value = real_time;
                }
                m_total_time += real_time;
                break;
            }
            case PROFILETYPE_PRECISION: {
                int64_t cur_time;
                profileGetTime(&cur_time);
                float real_time = (float)((cur_time - m_start_time) / 1000000.0f);
                if (real_time > m_peak_value) {
                    m_peak_value = real_time;
                }
                m_total_time += real_time;
                break;
            }
            default:
                break;
            }
        }
        return 0 == m_recursion_counter;
    }

    bool ProfileNode::saveData(std::string& stream, uint32_t layer)
    {
        if (layer >= 1024) {
            printf("saveData layer >= 1024 \n");
            return false;
        }

        char space[1024] = { '\0' };
        for (uint32_t i = 0; i < layer; ++i) {
            space[i] = '\t';
        }

        char text[1024] = { '\0' };
        sprintf(text, "[%u]Name:%s\tPercent:%0.3f%%\tTotalTime:%.6f(s)\tAvgTime:%.6f(s)\tMaxTime:%.6f(s)\tCount:%u\t\n",
            layer, getNodeName(), getPercentInParent() * 100.0f, getTotalTime(), getTotalTime() / getTotalCalls(),
            getPeakValue(), getTotalCalls());

        char enum_begin[256] = { '\0' };
        sprintf(enum_begin, "{\n");

        char enum_end[256] = { '\n' };
        sprintf(enum_end, "}\n");

        stream.append(space).append(text);
        ProfileNode* node = getChildNode();
        if (NULL != node) {
            stream.append(space).append(enum_begin);
            while (NULL != node) {
                node->saveData(stream, layer + 1);
                node = node->getSiblingNode();
            }
            stream.append(space).append(enum_end);
        }

        return true;
    }

    void ProfileNode::statInfo(uint32_t flag)
    {
        ProfileNode* child_node = m_child_node;
        while (NULL != child_node) {
            if (flag & ProfileManager::flag_stat_percentinparent && getTotalTime() > 0.000000001f) {
                child_node->m_percent_in_parent = child_node->getTotalTime() / getTotalTime();
            }
            child_node->statInfo(flag);
            child_node = child_node->getSiblingNode();
        }
    }

    ProfileManager::ProfileManager(void)
        : m_root_node(NULL)
        , m_cur_node(NULL)
        , m_profile_type(PROFILETYPE_PRECISION)
        , m_frame_counter(0)
        , m_reset_time(0)
    {
    }

    ProfileManager::~ProfileManager(void)
    {
    }

    void ProfileManager::init()
    {
        if (NULL == m_root_node) {
            m_root_node = new ProfileNode("Root", NULL, this);
            reset();
            m_cur_node = m_root_node;
            m_cur_node->enter();
        }
    }

    std::string ProfileManager::shutdown()
    {
        saveData();
        if (NULL != m_root_node) {
            m_root_node->leave();
            SAFE_DELETE(m_root_node);
            m_root_node = NULL;
            m_cur_node = NULL;
        }
        return m_stream;
    }

    std::string ProfileManager::report()
    {
        saveData();
        return m_stream;
    }

    void ProfileManager::startProfile(const char* node_name)
    {
        if (NULL == node_name || NULL == m_cur_node) {
            return;
        }
        if (0 != strcmp(node_name, m_cur_node->getNodeName())) {
            m_cur_node = m_cur_node->getSubNode(node_name);
        }
        if (NULL != m_cur_node) {
            m_cur_node->enter();
        }
    }

    void ProfileManager::stopProfile(const char* node_name)
    {
        if (NULL == m_cur_node || NULL == node_name) {
            return;
        }
        if (0 != strcmp(node_name, m_cur_node->getNodeName())) {
            printf("node:[%s],curnode:[%s] \n", node_name, m_cur_node->getNodeName());
            return;
        }
        if (m_cur_node->leave()) {
            m_cur_node = m_cur_node->getParentNode();
        }
    }

    void ProfileManager::statInfo(uint32_t flag)
    {
        if (NULL == m_root_node) {
            return;
        }
        m_root_node->m_total_time = getTimeSinceReset();
        m_root_node->statInfo(flag);
    }

    void ProfileManager::reset(void)
    {
        if (NULL == m_root_node) {
            return;
        }
        m_root_node->reset();
        m_frame_counter = 0;
        profileGetTime(&m_reset_time);
    }

    float ProfileManager::getTimeSinceReset()
    {
        int64_t time;
        profileGetTime(&time);
        return (float)((time - m_reset_time) / 1000000.0f);
    }

    bool ProfileManager::saveData()
    {
        if (NULL == m_root_node) {
            printf("root node is null \n");
            return false;
        }
        ProfileManager::setProfileType(PROFILETYPE_NONE);
        statInfo(flag_stat_percentinparent);
        m_stream.clear();
        m_root_node->saveData(m_stream, 0);
        return true;
    }

    luakit::lua_table open_lprof(lua_State* L) {
        luakit::kit_state lua(L);
        auto luaprof = lua.new_table();
        lua.new_class<ProfileManager>(
            "init", &ProfileManager::init,
            "shutdown", &ProfileManager::shutdown,
            "report",&ProfileManager::report,
            "start", &ProfileManager::startProfile,
            "stop", &ProfileManager::stopProfile);
        luaprof.set_function("new", []() { return new ProfileManager(); });
        return luaprof;
    }
}

extern "C" {
    LUAMOD_API int luaopen_lprof(lua_State* L) {
        return lprofile::open_lprof(L).push_stack();
    }
}
