/**
* 消息内存队列
*/

#pragma once

#include "code_queue.hpp"
namespace utility
{
	class CMsgQueue
	{
	protected:
		CTCodeQueue*		m_pstRecvQueue;        ///< 我的接收队列
		CTCodeQueue*		m_pstSendQueue;        ///< 我的发送队列
		char*				m_pMemBuff;			   ///< 内存buf
		int					m_iMemSize;			   ///< 内存大小		
	public:
		CMsgQueue() 
		:m_pstRecvQueue(NULL)
		,m_pstSendQueue(NULL)
		,m_pMemBuff(NULL)
		,m_iMemSize(0)
		{
		}
		virtual ~CMsgQueue()
		{
		}
		/**
		* 初始化	
		* @param[in] iShmSize 内存的大小(这里是内存的总大小，单向队列的大小是1/2)
		* @return 0=成功
		*/
		int Init(int iShmSize)
		{
			int iRet = 0;
			// 初始化内存大小
			m_iMemSize = iShmSize;
			m_pMemBuff = new char[m_iMemSize];

			// 初始化消息队列
			const int iQueueSize = m_iMemSize / 2;
			m_pstRecvQueue = (CTCodeQueue*)(m_pMemBuff + 0); 				
			iRet = m_pstRecvQueue->Init(iQueueSize);	
			m_pstSendQueue = (CTCodeQueue*)(m_pMemBuff + iQueueSize); 				
			iRet = m_pstSendQueue->Init(iQueueSize);

			return iRet;
		}

		// 向发送队列中放入一个Code
		int PutOneCode(const char* p, int len,bool bFront)
		{
			if(bFront){
				return m_pstSendQueue->Put(p, len);
			}else{
				return m_pstRecvQueue->Put(p,len);
			}
		}

		// 把两块缓冲区合并成一个Code放入队列中.这个函数的作用是为了减少1次内存拷贝
		int PutOneCode(const char* p1, int len1, const char* p2, int len2,bool bFront)
		{
			if(bFront){
				return m_pstSendQueue->Put(p1, len1, p2, len2);
			}else{
				return m_pstRecvQueue->Put(p1,len1,p2,len2);
			}
		}

		// 从接收队列中获取一个Code
		int GetOneCode(char* p, int buflen, int& len,bool bFront)
		{
			if(bFront){
				return m_pstRecvQueue->Get(p, buflen, len);
			}else{
				return m_pstSendQueue->Get(p,buflen,len);
			}
		}
		// 删除接收队列中的下一个Code
		int Remove(bool bFront)
		{
			if(bFront){
				return m_pstRecvQueue->Remove();
			}else{
				return m_pstSendQueue->Remove();
			}
		}

		// 删除recv中的内容
		int RemoveAllRecv(bool bFront)
		{
			if(bFront){
				return m_pstRecvQueue->RemoveAll();
			}else{
				return m_pstSendQueue->RemoveAll();
			}
		}
		// 判断接收队列中有没有Code
		bool HasCode(bool bFront) const
		{
			if(bFront){
				return m_pstRecvQueue->GetCodeLen() > 0;
			}else{
				return m_pstSendQueue->GetCodeLen() > 0;
			}
		}
	};

} 
