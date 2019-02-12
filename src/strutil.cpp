/*-------------------------------------------------------------------------
 File    : strutil.cpp
 Author  : FKling
 Version : -
 Orginal : 2018-10-18
 Descr   : Set of small string utility functions

 Part of testrunner
 BSD3 License!
 
 Modified: $Date: $ by $Author: $
 ---------------------------------------------------------------------------
 TODO: [ -:Not done, +:In progress, !:Completed]
 <pre>

 </pre>
 
 
 \History
 - 2018.10.18, FKling, Implementation
 
 ---------------------------------------------------------------------------*/

#include <stdio.h>
#include <string>
#include <vector>

#include "strutil.h"

namespace strutil {

std::string to_string(int32_t value) {
    char buffer[32];
    snprintf(buffer,32,"%d",value);
    return std::string(buffer);
}

std::string to_string(uint32_t value, bool hex /*= true*/) {
    char buffer[32];
    if (!hex) {
        snprintf(buffer,32,"%lu",value);
    } else {
        snprintf(buffer,32,"$%.8x",value);        
    }
    return std::string(buffer);
}


std::string to_string(float value) {
    char buffer[32];
    snprintf(buffer,32,"%f",value);
    return std::string(buffer);
}


std::string& ltrim(std::string& str, const std::string& chars /* = "\t\n\v\f\r " */) {
    str.erase(0, str.find_first_not_of(chars));
    return str;
}
 
std::string& rtrim(std::string& str, const std::string& chars /* = "\t\n\v\f\r " */) {
    str.erase(str.find_last_not_of(chars) + 1);
    return str;
}
 
std::string& trim(std::string& str, const std::string& chars /* = "\t\n\v\f\r " */) {
    return ltrim(rtrim(str, chars), chars);
}
// everything else is inline
static std::string whiteSpaces( " \f\n\r\t\v" );

void split(std::vector<std::string> &strings, const char *strInput, int splitChar) {
    std::string input(strInput);
    size_t iPos = 0;
    while(iPos != -1) {
        size_t iStart = iPos;
        iPos = input.find(splitChar,iPos);
        if (iPos != -1) {
            std::string str = input.substr(iStart, iPos-iStart);
            trim(str);
            // 2018-11-29, Gnilk: Push back even if length is 0
            strings.push_back(str);
            iPos++;
        } else {
            std::string str = input.substr(iStart, input.length()-iStart);
            trim(str);
            if (str.length() > 0) {
                strings.push_back(str);
            }
        }
    }
}      

void strip(std::string &str, int stripchar) {
// NOTE: if depending on algorithm, this can be written as: 
//    while(from.erase(std::find(from.begin(), from.end(), '\"')) != from.end());
    auto it = str.begin();
    while(it != str.end()) {
        if (*it == stripchar) {
            it = str.erase(it);
        } else {
            it++;
        }   
    }
}

}
