
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
        virtual ~Thread(){}
        
        //该函数为实际线程函数，子类需要实现。
        virtual void run() = 0;

        void start(){
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
        bool is_started() { return started; }

        static std::thread::id thread_id(){
            return std::this_thread::get_id();
        }  
        static int64_t cur_time(){
            return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
        }
        void wait_time(int ms) {
            std::unique_lock<std::mutex> lock(mutex);
            condtion.wait_for(lock,std::chrono::milliseconds(ms));
        }
        void wakeup() {
            condtion.notify_one();
        }
    protected:
        //延迟函数只有在线程或者继承类中使用比较安全
        void sleep(int ms) {
            std::this_thread::sleep_for(std::chrono::milliseconds(ms));
        }

    private:
        //在该函数内阻塞，直到用start()函数。
        void begin_run(){            
            if(!started){
                std::unique_lock<std::mutex> lock(mutex);                
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


