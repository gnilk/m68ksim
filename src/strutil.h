#pragma once
#include <string>
#include <vector>

namespace strutil {
    std::string to_string(int32_t value);
    std::string to_string(uint32_t value, bool hex = true);
    std::string to_string(float value);
    std::string& ltrim(std::string& str, const std::string& chars = "\t\n\v\f\r ");
    std::string& rtrim(std::string& str, const std::string& chars = "\t\n\v\f\r ");
    std::string& trim(std::string& str, const std::string& chars = "\t\n\v\f\r ");
    void split(std::vector<std::string> &strings, const char *strInput, int splitChar);
    void strip(std::string &str, int stripchar);

}
