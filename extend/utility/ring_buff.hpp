
#pragma once

#include <assert.h>

namespace utility {
    class RingBuffer {
    public :
        RingBuffer(int bufferSize = 0)
        :m_pBuffer(NULL), m_BufferSize(bufferSize), m_Head(0), m_Tail(0) {
            if (bufferSize>0) {
                Init(bufferSize);
            }
        }
        virtual ~RingBuffer() { Release(); }
        void Init(int bufferSize) {
            m_pBuffer    = new char[bufferSize];
            m_BufferSize = bufferSize;
            m_Head       = 0;
            m_Tail       = 0;
        }
        void Release() {
            if (m_pBuffer) {
                delete[] m_pBuffer;
                m_pBuffer = NULL;
            }
            m_BufferSize = 0;
            m_Head       = 0;
            m_Tail       = 0;
        }
        void Recycle() {
            m_Head = 0;
            m_Tail = 0;
        }
        int Write(const char* pBuffer, int len) {
            if (GetFreeSize()<len) {
                return -1;
            }
            if (m_Head<=m_Tail) {
                int rightFreeSize = m_BufferSize-m_Tail;
                int writeLen      = std::min<int>(rightFreeSize, len);

                memcpy(m_pBuffer+m_Tail, pBuffer, writeLen);
                m_Tail = (m_Tail+writeLen)%m_BufferSize;

                int remainLen = len-writeLen;
                if (remainLen>0) {
                    assert(m_Tail==0);
                    memcpy(m_pBuffer, pBuffer+writeLen, remainLen);
                    m_Tail = remainLen;
                }
            }else{
                memcpy(m_pBuffer+m_Tail, pBuffer, len);
                m_Tail += len;
            }
            return len;
        }
        int Read(char* pBuffer, int len) {
            if (GetDataSize()<len) {
                return -1;
            }
            if (m_Head<m_Tail) {
                memcpy(pBuffer, m_pBuffer+m_Head, len);
                m_Head += len;
            }else{
                int writeLen = std::min<int>(len, m_BufferSize-m_Head);
                memcpy(pBuffer, m_pBuffer+m_Head, writeLen);
                m_Head = (m_Head+writeLen)%m_BufferSize;

                int remainLen = len-writeLen;
                if (remainLen>0) {
                    assert(m_Head==0);
                    memcpy(pBuffer+writeLen, m_pBuffer, remainLen);
                    m_Head += remainLen;
                }
            }
            return len;
        }
        int Peek(char* pBuffer, int len) {
            if (GetDataSize()<len) {
                return -1;
            }
            if (m_Head<m_Tail) {
                memcpy(pBuffer, m_pBuffer+m_Head, len);
            }else{
                int writeLen = std::min<int>(len, m_BufferSize-m_Head);
                memcpy(pBuffer, m_pBuffer+m_Head, writeLen);
                int remainLen = len-writeLen;
                if (remainLen>0) {
                    memcpy(pBuffer+writeLen, m_pBuffer, remainLen);
                }
            }
            return len;
        }
        int Skip(int len) {
            if (GetDataSize()<len) {
                return -1;
            }
            m_Head = (m_Head+len)%m_BufferSize;
            return len;
        }
        bool IsEmpty() const { return m_Head==m_Tail; }
        bool IsFull() const { return GetFreeSize()==0; }
        int GetBufferSize() const { return m_BufferSize; }
        int GetDataSize() const { return m_Head<=m_Tail ? m_Tail-m_Head : m_BufferSize-m_Head+m_Tail; }
        int GetFreeSize() const { return GetBufferSize()-GetDataSize()-1; }    // -1 for tail position
        char* GetContigousPtr(int& size) const
        {
            if (m_Head<=m_Tail) {
                size = m_Tail-m_Head;
                return (m_pBuffer+m_Head);
            }else{
                size = m_BufferSize-m_Head;
                return (m_pBuffer+m_Head);
            }
        }
    protected :
        char* m_pBuffer;
        int m_BufferSize;
        int m_Head;
        int m_Tail;
    };
}

	





