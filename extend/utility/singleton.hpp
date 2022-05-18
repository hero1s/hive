
#pragma once

#include "noncopyable.hpp"

// 自动释放
// 谨慎使用，不当的使用会在释放析构顺序上产生问题
template <typename TYPE, typename REFTYPE = TYPE>
class AutoDeleteSingleton : public utility::noncopyable {
public:
    static REFTYPE&
    Instance()
    {
        static TYPE s_SingleObj;
        return s_SingleObj;
    }

protected:
    AutoDeleteSingleton() {};

    virtual ~AutoDeleteSingleton() {};
};
