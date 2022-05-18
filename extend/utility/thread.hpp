
#pragma once

#include <thread>
#include <memory>
#include <condition_variable>
#include <chrono>
#include <functional>

namespace utility
{
    class Thread
    {
    public :
        Thread()
        :started(false),
        thread(new std::thread(std::bind(&Thread::begin_run,this)))
        {
        }
        //Thread 类总是被继承，虚析构会安全。
        virtual ~Thread(){}
        void start(){
            std::unique_lock<std::mutex> lock(mutex);
            started = true;
            condtion.notify_one();
        }
        void join(){
            if (thread->joinable()) {
                thread->join();
            }
        }
        void stop(){
            started = false;
            wakeup();
        }
        static std::thread::id thread_id(){
            return std::this_thread::get_id();
        }
        bool is_started(){ return started; }
        //该函数为实际线程函数，子类需要实现。
        virtual void run()=0;
    protected:
        //延迟函数只有在线程或者继承类中使用比较安全
        void sleep(int ms){
            std::this_thread::sleep_for(std::chrono::milliseconds(ms));
        }
        int64_t cur_time(){
            return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
        }
        void wait_time(int ms) {
            std::unique_lock<std::mutex> lock(mutex);
            condtion.wait_for(lock,std::chrono::milliseconds(ms));
        }
        void wakeup() {
            std::unique_lock<std::mutex> lock(mutex);
            condtion.notify_one();
        }
    private:
        //在该函数内阻塞，直到用start()函数。
        void begin_run(){
            std::unique_lock<std::mutex> lock(mutex);
            //如果在wait函数执行前执行notify则不会有效，所以需要先判断started状态。
            if(!started){
                //如果在这里还未执行wait时，notify被执行，则这里会永远阻塞。所以需要加锁
                condtion.wait(lock);
            }
            run();
        }
    protected:
        bool started = false;
        std::mutex mutex;
        std::condition_variable  condtion;
        std::shared_ptr<std::thread> thread;
    };
}


