#pragma once

#include <string>
#include <unordered_map>
#include <chrono>

namespace lprofiler {

    class ProfileManager;

    class ProfileNode {
    public:
        ProfileNode(const char* node_name, ProfileNode* parent_node, ProfileManager* mgr);

        virtual ~ProfileNode(void);
        ProfileNode* getSubNode(const char* node_name);
        ProfileNode* getSubNode(int index);
        inline ProfileNode* getParentNode(void) { return m_parent_node; };
        ProfileNode* getSiblingNode(void) { return m_sibling_node; };
        ProfileNode* getChildNode(void) { return m_child_node; };
        void reset(void);
        void enter(void);
        bool leave(void);
        const char* getNodeName(void) const { return m_node_name.c_str(); };
        int getTotalCalls(void) const { return m_total_calls; };
        float getPeakValue(void) const { return m_peak_value; };
        float getTotalTime(void) const { return m_total_time; };
        float getPercentInParent(void) const { return m_percent_in_parent; };
        size_t getCurThreadID() const { return m_cur_threadid; };
        void setCurThreadID(size_t threadid) { m_cur_threadid = threadid; };
        bool saveData(std::string& outStr, uint32_t layer /*= 0*/);
        void statInfo(uint32_t flag);

    private:
        size_t      m_cur_threadid;         //当前线程ID
        uint32_t    m_total_calls;          //总调用次数
        int         m_recursion_counter;    //递归调用计数
        float       m_total_time;           //总时间
        float       m_peak_value;           //此节点执行时间峰值
        float       m_percent_in_parent;    //占用父节点的时间百分比
        int64_t     m_start_time;           //开始时间

        std::string  m_node_name;           //节点名称
        ProfileNode* m_parent_node;         //父节点
        ProfileNode* m_child_node;          //子节点
        ProfileNode* m_sibling_node;        //兄弟节点
        ProfileManager* m_mgr;

        friend class ProfileManager;
    };

    class ProfileManager {
    public:
        enum {
            flag_stat_percentinparent = 1,
        };
        ProfileManager(void);
        virtual ~ProfileManager(void);
        void init();
        void shutdown();
        int  startProfile(size_t thread_id, const char* node_name, std::string& err);
        int  stopProfile(size_t thread_id, const char* node_name, std::string& err);
        void statInfo(uint32_t flag /*= flag_stat_percentinparent */);
        void reset(void);
        void increaseFrameCount(void) { ++m_frame_counter; };
        uint32_t getFrameCount(void) { return m_frame_counter; };
        ProfileNode* getRootNode(void) { return m_root_node; };
        void setProfileType(uint8_t profile_type) { m_profile_type = profile_type; };
        uint8_t getProfileType(void) { return m_profile_type; };
        float getTimeSinceReset();
        std::string info();

    private:
        ProfileNode* m_root_node;       //根节点
        ProfileNode* m_cur_node;        //当前节点
        uint8_t      m_profile_type;    //性能统计类型
        uint32_t     m_frame_counter;   //帧数
        int64_t      m_reset_time;      //开始计时时间
    };
}

