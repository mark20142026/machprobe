#pragma once
#include <cstdint>
#include <filesystem>
#include <map>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <variant>
#include <vector>

namespace mp {
struct Unsupported : std::runtime_error { using std::runtime_error::runtime_error; };
// A small output-only JSON value; the parser and CLI share the same report tree.
struct Json {
    using Array = std::vector<Json>;
    using Object = std::map<std::string, Json>;
    std::variant<std::nullptr_t, bool, int64_t, uint64_t, std::string, Array, Object> value;
    Json() : value(nullptr) {}
    Json(bool v) : value(v) {}
    template<class T, std::enable_if_t<std::is_integral_v<T> && !std::is_same_v<T,bool>,int> = 0>
    Json(T v) { if constexpr(std::is_signed_v<T>) value = int64_t(v); else value = uint64_t(v); }
    Json(const char* v) : value(std::string(v)) {}
    Json(std::string v) : value(std::move(v)) {}
    Json(Array v) : value(std::move(v)) {}
    Json(Object v) : value(std::move(v)) {}
    static Json object() { return Object{}; }
    static Json array() { return Array{}; }
    Json& operator[](const std::string& key) { return std::get<Object>(value)[key]; }
    const Json& at(const std::string& key) const { return std::get<Object>(value).at(key); }
    void push(Json v) { std::get<Array>(value).push_back(std::move(v)); }
    std::string dump(unsigned indent = 0) const;
};
struct Dependency { std::string name, kind; };
struct Image {
    Json report = Json::object();
    std::vector<Dependency> dependencies;
    std::vector<std::string> rpaths;
    uint32_t cpu = 0, subtype = 0;
};
Image inspect(const std::filesystem::path&, const std::string& arch = "arm64");
Json dependencies(const std::filesystem::path&, const std::string& arch, unsigned maxDepth);
std::string describe(const Json&);
std::string version(uint32_t);
}
