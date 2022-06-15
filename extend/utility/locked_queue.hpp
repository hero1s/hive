
#pragma once

#include <mutex>
#include <queue>
#include <list>

namespace utility
{
// Simple mutex-guarded queue
template<typename T>
class LockedQueue
{
private:
	std::mutex     mutex;
	std::queue<T>  queue;
public:
	void push(const T& value) {
		Add(value);
	}
	void push(T &&value) {
	    Add(std::forward<T>(value));
	}
    bool pop(T& t) {
        std::unique_lock<std::mutex> lock(mutex);
		if (queue.empty())return false;
        t = std::move(queue.front());
        queue.pop();
        return true;
    }
	bool empty() {
		std::unique_lock<std::mutex> lock(mutex);
		return queue.empty();
	}
	uint32_t size()	{
		std::unique_lock<std::mutex> lock(mutex);
		return queue.size();
	}
private:
    template<typename F>
    void Add(F &&x) {
        std::unique_lock<std::mutex> lock(mutex);
        queue.push(std::forward<F>(x));
    }

};
}


