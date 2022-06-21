
#pragma once

#include <vector>
#include <cstring>

namespace utility {
    class ByteBuffer {
        typedef std::vector<char>::size_type size_type;
    public:
        ByteBuffer() : wpos_(0), rpos_(0), storage_() { storage_.resize(8 * 1024); }
        explicit ByteBuffer(std::size_t size) : wpos_(0), rpos_(0), storage_() { storage_.resize(size); }
        ByteBuffer(const ByteBuffer &rhs) : wpos_(rhs.wpos_), rpos_(rhs.rpos_), storage_(rhs.storage_) {}
        ByteBuffer(ByteBuffer &&rhs) : wpos_(rhs.wpos_), rpos_(rhs.rpos_), storage_(rhs.Move()) {}
        ByteBuffer &operator=(const ByteBuffer &rhs) {
            if (this != &rhs) {
                wpos_ = rhs.wpos_;
                rpos_ = rhs.rpos_;
                storage_ = rhs.storage_;
            }
            return *this;
        }
        ByteBuffer &operator=(ByteBuffer &&rhs) {
            if (this != &rhs) {
                wpos_ = rhs.wpos_;
                rpos_ = rhs.rpos_;
                storage_ = rhs.Move();
            }
            return *this;
        }
        void Swap(ByteBuffer &rhs) {
            storage_.swap(rhs.storage_);
            std::swap(wpos_, rhs.wpos_);
            std::swap(rpos_, rhs.rpos_);
        }
        void Reset() {
            wpos_ = 0;
            rpos_ = 0;
        }
        void Resize(size_type bytes) { storage_.resize(bytes); }
        char *Data() { return storage_.data(); }
        char *ReadBegin() { return Data() + rpos_; }
        char *WriteBegin() { return Data() + wpos_; }
        void ReadBytes(size_type bytes) { rpos_ += bytes; }
        void WriteBytes(size_type bytes) { wpos_ += bytes; }
        size_type Size() const { return wpos_ - rpos_; }
        size_type ValidSize() const { return storage_.size() - wpos_; }
        size_type Capacity() const { return storage_.size(); }
        void Normalize() {
            if (rpos_ > 0) {
                if (rpos_ != wpos_) {
                    memmove(Data(), ReadBegin(), Size());
                }
                wpos_ -= rpos_;
                rpos_ = 0;
            }
        }
        void EnsureValidSize() {
            // resize buffer if it's already full
            if (ValidSize() == 0) {
                storage_.resize(storage_.size() * 3 / 2);
            }
        }
        void EstimateSize(std::size_t size) {
            if (ValidSize() < size) {
                storage_.resize((storage_.size() + size) * 3 / 2);
            }
        }
        inline void write(const char *data, std::size_t size) {
            if (size > 0) {
                EstimateSize(size);
                memcpy(WriteBegin(), data, size);
                WriteBytes(size);
            }
        }
        inline bool read(uint32_t uBytes, void *outBuffer) {
            if (Size() < uBytes) return false;
            memcpy(outBuffer, ReadBegin(), uBytes);
            ReadBytes(uBytes);
            return true;
        }
        template<typename T>
        inline void Write(const T &t){ return write((const char*)&t,sizeof(T)); }
        template<typename T>
        inline bool Read(T &t) { return read(sizeof(T), &t); }
    private:
        std::vector<char> &&Move() {
            wpos_ = 0;
            rpos_ = 0;
            return std::move(storage_);
        }
    private:
        size_type wpos_;
        size_type rpos_;
        std::vector<char> storage_;
    };
}

