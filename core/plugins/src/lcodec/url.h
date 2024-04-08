#pragma once
#include <string>

namespace lcodec {

    inline unsigned char tohex(unsigned char x) { 
        return  x > 9 ? x + 55 : x + 48; 
    }
    
    inline unsigned char fromhex(unsigned char x) { 
        if (x >= 'A' && x <= 'Z') return x - 'A' + 10;
        else if (x >= 'a' && x <= 'z') return x - 'a' + 10;
        else if (x >= '0' && x <= '9') return x - '0';
        else return x;
    }
    
    static std::string url_encode(std::string str) {
        std::string temp = "";
        size_t length = str.length();
        for (size_t i = 0; i < length; i++) {
            if (isalnum((unsigned char)str[i]) || (str[i] == '-') || (str[i] == '_') || (str[i] == '.') || (str[i] == '~'))
                temp += str[i];
            else if (str[i] == ' ')
                temp += "+";
            else {
                temp += '%';
                temp += tohex((unsigned char)str[i] >> 4);
                temp += tohex((unsigned char)str[i] % 16);
            }
        }
        return temp;
    }
    
    static std::string url_decode(std::string str) {
        std::string temp = "";
        size_t length = str.length();
        for (size_t i = 0; i < length; i++)
        {
            if (str[i] == '+') temp += ' ';
            else if (str[i] == '%'){
                unsigned char high = fromhex((unsigned char)str[++i]);
                unsigned char low = fromhex((unsigned char)str[++i]);
                temp += high * 16 + low;
            }
            else temp += str[i];
        }
        return temp;
    }
}
