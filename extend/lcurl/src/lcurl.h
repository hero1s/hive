#pragma once

#include <string.h>
#include <curl/curl.h>
#include "lua_kit.h"
#ifdef WIN32
#include<winsock2.h>
#pragma comment(lib,"ws2_32.lib")
#endif // WIN32



using namespace std;

namespace lcurl {

	static size_t write_callback(char* buffer, size_t block_size, size_t count, void* arg);

	class curl_request
	{
	public:
		curl_request(CURLM* cm, CURL* c) : curlm(cm), curl(c) {}
		~curl_request() {
			if (curl) {
				curl_multi_remove_handle(curlm, curl);
				curl_easy_cleanup(curl);
				curl = nullptr;
			}
			if (header) {
				curl_slist_free_all(header);
				header = nullptr;
			}
			curlm = nullptr;
		}

		void create(const string& url, size_t timeout_ms) {
			curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
			curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1);
			curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void*)this);
			curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, error);
			curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, timeout_ms);
			curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, timeout_ms);
			curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
			curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, false);
			curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, false);
			curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
		}

		bool call_get(const char* data) {
			return request(data);
		}

		bool call_post(const char* data) {
			curl_easy_setopt(curl, CURLOPT_POST, 1L);
			return request(data, true);
		}

		bool call_put(const char* data) {
			curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "PUT");
			return request(data, true);
		}

		bool call_del(const char* data) {
			curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "DELETE");
			return request(data);
		}

		void set_header(string value) {
			header = curl_slist_append(header, value.c_str());
		}

		void enable_ssl(const char* ca_path) {
			curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 2L);
			curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
			curl_easy_setopt(curl, CURLOPT_CAINFO, ca_path);
		}

		int get_respond(lua_State* L) {
			long code = 0;
			curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &code);
			return luakit::variadic_return(L, content, code, error);
		}

	private:
		bool request(const char* data, bool body_field = false) {
			if (header) {
				curl_easy_setopt(curl, CURLOPT_HTTPHEADER, header);
			}
			int len = data ? strlen(data) : 0;
			if (body_field || len > 0) {
				curl_easy_setopt(curl, CURLOPT_POSTFIELDS, data);
				curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, len);
			}
			if (curl_multi_add_handle(curlm, curl) == CURLM_OK) {
				return true;
			}
			return false;
		}

	public:
		string content;

	private:
		CURLM* curlm = nullptr;
		CURL* curl = nullptr;
		curl_slist* header = nullptr;
		char error[CURL_ERROR_SIZE] = {};
	};

	class curlm_mgr
	{
	public:
		curlm_mgr(CURLM* cm, CURL* ce) : curlm(cm), curle(ce) {}

		void destory() {
			if (curle) {
				curl_easy_cleanup(curle);
				curle = nullptr;
			}
			if (curlm) {
				curl_multi_cleanup(curlm);
				curlm = nullptr;
			}
			curl_global_cleanup();
		}

		int create_request(lua_State* L, string url, size_t timeout_ms) {
			CURL* curl = curl_easy_init();
			if (!curl) {
				return 0;
			}
			curl_request* request = new curl_request(curlm, curl);
			request->create(url, timeout_ms);
			return luakit::variadic_return(L, request, curl);
		}
		bool curl_select()
		{
			struct timeval timeout;
			fd_set fdread;
			fd_set fdwrite;
			fd_set fdexcep;
			int maxfd = -1;
			FD_ZERO(&fdread);
			FD_ZERO(&fdwrite);
			FD_ZERO(&fdexcep);
			timeout.tv_sec = 0;
			timeout.tv_usec = 0;
			curl_multi_fdset(curlm, &fdread, &fdwrite, &fdexcep, &maxfd);
			if (-1 == maxfd)return -1;
			return select(maxfd + 1, &fdread, &fdwrite, &fdexcep, &timeout) > 0;
		}
		int update(lua_State* L) {
			//if (!curl_select())return 1;
			int running_handles;
			CURLMcode result = curl_multi_perform(curlm, &running_handles);
			if (result != CURLM_OK && result != CURLM_CALL_MULTI_PERFORM) {
				lua_pushboolean(L, false);
				lua_pushstring(L, "curl_multi_perform failed");
				return 2;
			}
			int msgs_in_queue;
			CURLMsg* curlmsg = nullptr;
			luakit::kit_state kit_state(L);
			while ((curlmsg = curl_multi_info_read(curlm, &msgs_in_queue)) != nullptr) {
				if (curlmsg->msg == CURLMSG_DONE) {
					kit_state.object_call(this, "on_respond", nullptr, tie(), curlmsg->easy_handle, curlmsg->data.result);
					curl_multi_remove_handle(curlm, curlmsg->easy_handle);
				}
			}
			lua_pushboolean(L, true);
			return 1;
		}

	private:
		CURLM* curlm = nullptr;
		CURL* curle = nullptr;
	};

	static size_t write_callback(char* buffer, size_t block_size, size_t count, void* arg) {
		size_t length = block_size * count;
		curl_request* request = (curl_request*)arg;
		if (request) {
			request->content.append(buffer, length);
		}
		return length;
	}

}
