#pragma once

#include <string>
#include <vector>
#include <utility>
#include <list>
#include "curl/curl.h"
 
#define SKIP_PEER_VERIFICATION  
#define SKIP_HOSTNAME_VERIFICATION  
 
class SmtpSendMail {
public:
	SmtpSendMail(const std::string & charset = "UTF-8"); // 也可以传入utf
 
	//设置stmp用户名、密码、服务器、端口（端口其实不用指定，libcurl默认25，但如果是smtps则默认是465）  
	void SetSmtpServer(const std::string username, const std::string password, const std::string servername, const std::string port = "25");
	//发送者姓名，可以不用  
 
	void SetSendName(const std::string sendname);
 
	//发送者邮箱   
	void SetSendMail(const std::string sendmail);
 
	//添加收件人  
	void AddRecvMail(const std::string recvmail);
 
	//设置主题  
	void SetSubject(const std::string subject);
 
	//设置正文内容  
	void SetBodyContent(const std::string content);
 
	//添加附件  
	void AddAttachment(const std::string filename);
 
	//发送邮件  
	bool SendMail();
private:
 
	//回调函数，将MIME协议的拼接的字符串由libcurl发出  
	static size_t payload_source(void *ptr, size_t size, size_t nmemb, void *stream);
 
	//创建邮件MIME内容  
	void CreatMessage();
 
	//获取文件类型  
	int GetFileType(std::string const& stype);
 
	//设置文件名  
	void SetFileName(const std::string& FileName);
 
	//设置文件的contenttype  
	void SetContentType(std::string const& stype);
 
	//得到文件名  
	void GetFileName(const std::string& file, std::string& filename);
 
	//得到文件类型  
	void GetFileType(const std::string& file, std::string& stype);
 
private:
	std::string m_strCharset; //邮件编码  
	std::string m_strSubject; //邮件主题  
	std::string m_strContent; //邮件内容  
	std::string m_strFileName; //文件名  
	std::string m_strMessage;// 整个MIME协议字符串  
	std::string m_strUserName;//用户名  
	std::string m_strPassword;//密码  
	std::string m_strServerName;//smtp服务器  
	std::string m_strPort;//端口  
	std::string m_strSendName;//发送者姓名  
	std::string m_strSendMail;//发送者邮箱  
	std::string m_strContentType;//附件contenttype  
	std::string m_strFileContent;//附件内容  
 
	std::vector<std::string> m_vRecvMail; //收件人容器  
	std::vector<std::string> m_vAttachMent;//附件容器  
};