#pragma once

#include <map>
#include <vector>
#include <string>
#include <string.h>

#include "fmt/core.h"
#include "lua_kit.h"

#ifdef _MSC_VER
#define strcasecmp _stricmp
#endif

using namespace std;

namespace lhttp {

    const string CRLF = "\r\n";
    const string CRLF2 = "\r\n\r\n";
    const string RESPONSE = "HTTP/1.1 {}\r\nDate: {}\r\n{}\r\n{}";

    #define SC_UNKNOWN 0
    #define SC_OK 200
    #define SC_NOCONTENT 204
    #define SC_PARTIAL 206
    #define SC_OBJMOVED 302
    #define SC_BADREQUEST 400
    #define SC_FORBIDDEN 403
    #define SC_NOTFOUND 404
    #define SC_BADMETHOD 405
    #define SC_SERVERERROR 500
    #define SC_SERVERBUSY 503

    class http_request
    {
    public:
        http_request() {}

        string get_header(const string key) {
            auto it = headers.find(key); 
            if (it != headers.end()) {
                return it->second;
            }
            return "";
        }

        string get_param(const string key) {
            auto it = params.find(key);
            if (it != params.end()) {
                return it->second;
            }
            return "";
        }

        luakit::reference get_params(lua_State* L) {
            luakit::kit_state kit_state(L);
            return kit_state.new_reference(params);
        }

        luakit::reference get_headers(lua_State* L) {
            luakit::kit_state kit_state(L);
            return kit_state.new_reference(headers);
        }

        bool parse(const string buf) {
            size_t size = buf.size();
            if (size == 0) return false;
            size_t pos = buf.find(CRLF2);
            if (pos == string::npos) return false;
            string header = buf.substr(0, pos);
            size_t offset = pos + CRLF2.length();
            vector<string> lines;
            split(header, CRLF, lines);
            size_t count = lines.size();
            if (count == 0) return false;
            vector<string> parts;
            split(lines[0], " ", parts);
            if (parts.size() < 3) return false;
            method = parts[0];
            version = parts[2];
            parse_url(parts[1]);
            for (size_t i = 1; i < count; ++i) {
                parse_header(lines[i]);
            }
            if (size >= offset) {
                parse_content(buf.substr(offset));
            }
            return body.size() == content_size;
        }

    private:
        void split(const string& str, const string& delim, vector<string>& res) {
            size_t cur = 0;
            size_t step = delim.size();
            size_t pos = str.find(delim);
            while (pos != string::npos) {
                res.push_back(str.substr(cur, pos - cur));
                cur = pos + step;
                pos = str.find(delim, cur);
            }
            if (str.size() > cur) {
                res.push_back(str.substr(cur));
            }
        }

        void parse_url(const string& str) {
            params.clear();
            size_t pos = str.find("?");
            if (pos != string::npos) {
                url = str.substr(0, pos);
                string args = str.substr(pos + 1);
                vector<string> parts;
                split(args, "&", parts);
                for (const string& part : parts) {
                    size_t pos = part.find("=");
                    if (pos != string::npos) {
                        params.insert(make_pair(part.substr(0, pos), part.substr(pos + 1)));
                    }
                }
            } else {
                url = str;
            }
            if (url.size() > 1 && url.back() == '/') {
                url.pop_back();
            }
        }

        void parse_header(const string& str) {
            size_t pos = str.find(":");
            if (pos != string::npos) {
                string key = str.substr(0, pos);
                string value = str.substr(pos + 2);
                value.erase(0, value.find_first_not_of(" "));
                headers.insert(make_pair(key, value));
                if (!strcasecmp(key.c_str(), "Content-Length")) {
                    content_size = atoi(value.c_str());
                }
                else if (!strcasecmp(key.c_str(), "Transfer-Encoding") && !strcasecmp(value.c_str(), "chunked")) {
                    chunked = true;
                }
            }
        }

        void parse_content(const string& str) {
            if (!chunked) {
                body = str;
                return;
            }
            vector<string> lines;
            split(str, CRLF, lines);
            for (size_t i = 0; i < lines.size(); i++) {
                if (i % 2 != 0) {
                    body.append(lines[i]);
                }
            }
            content_size = body.size();
        }

    public:
        bool chunked = false;
        size_t content_size = 0;
        map<string, string> params;
        map<string, string> headers;
        string url, body, method, version;
    };

    class http_response
    {
    public:
        http_response() {}

        void set_header(const string key, const string value) {
            headers.insert(make_pair(key, value));
        }

        string serialize() {
            set_header("Content-Length", fmt::format("{}", content.size()));
            return fmt::format(RESPONSE, format_status(), format_date(), format_header(), content);
        }

    private:
        string format_date() {
            char date[32];
            time_t rawtime;
            time(&rawtime);
            struct tm* timeinfo;
            timeinfo = gmtime(&rawtime);
            strftime(date, 32, "%a, %d %b %Y %T GMT", timeinfo);
            return date;
        }

        string format_header() {
            string str;
            for (auto it : headers) {
                str = fmt::format("{}{}: {}\r\n", str, it.first, it.second);
            }
            return str;
        }

        string format_status() {
            switch (status) {
            case SC_OK:         return "200 OK";
            case SC_NOCONTENT:  return "204 No Content";
            case SC_PARTIAL:    return "206 Partial Content";
            case SC_BADREQUEST: return "400 Bad Request";
            case SC_OBJMOVED:   return "302 Moved Temporarily";
            case SC_NOTFOUND:   return "404 Not Found";
            case SC_BADMETHOD:  return "405 Method Not Allowed";
            default: return "500 Internal Server Error";
            }
        }

    public:
        string content;
        size_t status = 200;
        map<string, string> headers;
    };
}
