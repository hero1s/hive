#pragma once
#include <algorithm>
#include <cstdint>
#include <array>
#include <cmath>

template<typename ValueType>
class rect
{
public:
    using value_type = ValueType;

    value_type x = value_type{};
    value_type y = value_type{};
    value_type width = {};
    value_type height = {};

    rect() = default;

    constexpr rect(value_type x_, value_type y_, value_type width_, value_type height_)
        :x(x_), y(y_), width(width_), height(height_)
    {
    }
    rect(const rect& other) {
        set(other.x, other.y, other.width, other.height);
    }
    void set(value_type x_, value_type y_, value_type width_, value_type height_) {
        x = x_;
        y = y_;
        width = width_;
        height = height_;
    }
    value_type left() const {
        return x;
    }
    value_type bottom() const {
        return y;
    }
    value_type top() const {
        return y + height;
    }
    value_type right() const {
        return x + width;
    }
    friend bool operator==(const rect& l, const rect& r) {
        return l.x == r.x && l.y == r.y && l.width == r.width &&l.height == r.height;
    }
    bool empty() const {
        return (width <= std::numeric_limits<value_type>::epsilon()
            || height <= std::numeric_limits<value_type>::epsilon());
    }
    bool contains(value_type pointx, value_type pointy) const {
        return (pointx >= x && pointx <= right()
            && pointy >= y && pointy <= top());
    }
    bool contains(const rect& rc) const {
        return (x <= rc.x
            && y <= rc.y
            && rc.right() <= right()
            && rc.top() <= top());
    }
    bool intersects(const rect& rc) const {
        return !(right() < rc.x || rc.right() < x || top() < rc.y || rc.top() < y);
    }
};
