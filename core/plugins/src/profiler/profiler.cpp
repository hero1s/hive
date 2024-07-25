#include "profiler.h"
#include <fmt/core.h>
#include <iostream>

namespace lprofiler {

    constexpr uint32_t MAX_LAYER_DEPTH = 1024;

    enum PROFILETYPE {
        PROFILETYPE_NONE        = 0, //无统计
        PROFILETYPE_SIMPLE      = 1, //简易
        PROFILETYPE_PRECISION   = 2, //精确
    };

    inline void profileGetTime(int64_t* time)
    {
        auto now = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(now.time_since_epoch());
        *time = duration.count();
    }

    ProfileNode::ProfileNode(const char* node_name, ProfileNode* parent_node, ProfileManager* mgr)
        :m_cur_threadid(0)
        , m_total_calls(0)
        , m_recursion_counter(0)
        , m_total_time(0.0f)
        , m_peak_value(0.0f)
        , m_percent_in_parent(0.0f)
        , m_start_time(0)
        , m_node_name(node_name)
        , m_parent_node(parent_node)
        , m_child_node(nullptr)
        , m_sibling_node(nullptr)
        , m_mgr(mgr)
    {
        reset();
    }

    ProfileNode::~ProfileNode() {
        if (m_child_node) {
            delete m_child_node;
            m_child_node = nullptr;
        }
        if (m_sibling_node) {
            delete m_sibling_node;
            m_sibling_node = nullptr;
        }
    }

    ProfileNode* ProfileNode::getSubNode(const char* node_name) {
        if (nullptr == node_name) {
            return nullptr;
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
        new_node->setCurThreadID(m_mgr->getRootNode()->getCurThreadID());
        m_child_node = new_node;
        std::cout << fmt::format(" {} add new anazy node:{} ", getNodeName(), node_name) << std::endl;
        return new_node;
    }

    ProfileNode* ProfileNode::getSubNode(int index) {
        ProfileNode* temp_child = m_child_node;
        while (temp_child && index--) {
            temp_child = temp_child->getSiblingNode();
        }
        return temp_child;
    }

    void ProfileNode::reset(void) {
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

    void ProfileNode::enter(void) {
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

    bool ProfileNode::leave(void) {
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

    bool ProfileNode::saveData(std::string& outStr, uint32_t layer /*= 0*/) {
        if (layer >= MAX_LAYER_DEPTH) {
            std::cout << fmt::format("saveData f is null or layer >= 1024") << std::endl;
            return false;
        }
        std::string space;
        space.reserve(layer * sizeof("\t"));
        for (uint32_t i = 0; i < layer; ++i) {
            space.append("  ");
        }
        std::string text = fmt::format("{:<18} Percent:{:<8} Total:{:<16} Avg:{:<12} Max:{:<12} Count:{}\n",
            fmt::format("[{}]:{}", layer, getNodeName()),
            fmt::format("{:.3f}%",getPercentInParent() * 100.0f), 
            fmt::format("{:.6f}(s)", getTotalTime()), 
            fmt::format("{:.6f}(s)", getTotalTime() / getTotalCalls()), 
            fmt::format("{:.6f}(s)", getPeakValue()), getTotalCalls());

        outStr.append(space);
        outStr.append(text);

        ProfileNode* node = getChildNode();
        if (nullptr != node) {
            outStr.append(space);
            outStr.append("{\n");

            while (nullptr != node) {
                node->saveData(outStr, layer + 1);
                node = node->getSiblingNode();
            }

            outStr.append(space);
            outStr.append("}\n");
        }
        return true;
    }

    void ProfileNode::statInfo(uint32_t flag) {
        ProfileNode* child_node = m_child_node;
        while (nullptr != child_node) {
            if (flag & ProfileManager::flag_stat_percentinparent && getTotalTime() > 0.000000001f) {
                child_node->m_percent_in_parent = child_node->getTotalTime() / getTotalTime();
            }
            child_node->statInfo(flag);
            child_node = child_node->getSiblingNode();
        }
    }

    ProfileManager::ProfileManager(void)
        : m_root_node(nullptr)
        , m_cur_node(nullptr)
        , m_profile_type(PROFILETYPE_PRECISION)
        , m_frame_counter(0)
        , m_reset_time(0)
    {
    }

    ProfileManager::~ProfileManager(void) {
        shutdown();
    }

    void ProfileManager::init() {
        shutdown();
        if (nullptr == m_root_node) {
            m_root_node = new ProfileNode("Root", nullptr, this);
            reset();
            m_cur_node = m_root_node;
            m_cur_node->enter();
        }
    }

    void ProfileManager::shutdown() {
        if (nullptr != m_root_node) {
            m_root_node->leave();
            delete m_root_node;
            m_root_node = nullptr;
            m_cur_node = nullptr;
        }
    }

    int ProfileManager::startProfile(size_t thread_id, const char* node_name, std::string& err) {
        if (nullptr == node_name || nullptr == m_cur_node) {
            return 0;
        }
        if (thread_id != m_cur_node->getCurThreadID()) {
            if (m_cur_node == m_root_node) {
                m_root_node->setCurThreadID(thread_id);
            } else {
                err = fmt::format("start thread_id : {} != {}", thread_id, m_cur_node->getCurThreadID());
                return 0;
            }            
        }
        if (0 != strcmp(node_name, m_cur_node->getNodeName())) {
            m_cur_node = m_cur_node->getSubNode(node_name);
        }
        if (nullptr != m_cur_node) {
            m_cur_node->enter();
        }
        return 1;
    }

    int ProfileManager::stopProfile(size_t thread_id, const char* node_name, std::string& err) {
        if (nullptr == m_cur_node || nullptr == node_name) {
            return 0;
        }
        if (thread_id != m_cur_node->getCurThreadID()) {
            err = fmt::format("stop thread_id : {} != {}", thread_id, m_cur_node->getCurThreadID());
            return 0;
        }
        if (0 != strcmp(node_name, m_cur_node->getNodeName())) {
            err = fmt::format("node:{},curnode:{}", node_name, m_cur_node->getNodeName());
            return 0;
        }
        if (m_cur_node->leave()) {
            m_cur_node = m_cur_node->getParentNode();
        }
        return 1;
    }

    void ProfileManager::statInfo(uint32_t flag /*= flag_stat_percentinparent */) {
        if (nullptr == m_root_node) {
            return;
        }
        m_root_node->m_total_time = getTimeSinceReset();
        m_root_node->statInfo(flag);
    }

    void ProfileManager::reset(void) {
        if (nullptr == m_root_node) {
            return;
        }
        m_root_node->reset();
        m_frame_counter = 0;
        profileGetTime(&m_reset_time);
    }

    float ProfileManager::getTimeSinceReset() {
        int64_t time;
        profileGetTime(&time);
        return (float)((time - m_reset_time) / 1000000.0f);
    }

    std::string ProfileManager::info() {
        std::string outStr;
        if (nullptr == m_root_node) {            
            return outStr;
        }
        ProfileManager::setProfileType(PROFILETYPE_NONE);
        statInfo(flag_stat_percentinparent);

        m_root_node->saveData(outStr, 0);
        return outStr;
    }
}