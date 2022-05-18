#define LUA_LIB

#include <chrono>
#include <iostream>
#include <filesystem>
#include "lua_kit.h"

using namespace std;
using namespace std::chrono;

namespace lstdfs {

    struct file_info {
        std::string name;
        std::string type;
    };
    using file_vector = std::vector<file_info*>;
    using path_vector = std::vector<std::string>;

    std::string lstdfs_absolute(std::string path) {
        return filesystem::absolute(path).string();
    }

    std::string lstdfs_current_path() {
        return filesystem::current_path().string();
    }

    std::string lstdfs_temp_dir() {
        return filesystem::temp_directory_path().string();
    }

    luakit::variadic_results lstdfs_chdir(lua_State* L, std::string path) {
        luakit::kit_state kit_state(L);
        try {
            filesystem::current_path(path);
            return kit_state.as_return(true);
        }
        catch (filesystem::filesystem_error const& e) {
            return kit_state.as_return(false, e.what());
        }
    }

    luakit::variadic_results lstdfs_mkdir(lua_State* L, std::string path) {
        luakit::kit_state kit_state(L);
        try {
            bool res = filesystem::create_directories(path);
            return kit_state.as_return(res);
        }
        catch (filesystem::filesystem_error const& e) {
            return kit_state.as_return(false, e.what());
        }
    }

    luakit::variadic_results lstdfs_remove(lua_State* L, std::string path, bool rmall) {
        luakit::kit_state kit_state(L);
        try {
            if (rmall) {
                auto size = filesystem::remove_all(path);
                return kit_state.as_return(size > 0);
            }
            bool res = filesystem::remove(path);
            return kit_state.as_return(res);
        }
        catch (filesystem::filesystem_error const& e) {
            return kit_state.as_return(false, e.what());
        }
    }

    luakit::variadic_results lstdfs_copy(lua_State* L, std::string from, std::string to, filesystem::copy_options option) {
        luakit::kit_state kit_state(L);
        try {
            filesystem::copy(from, to, option);
            return kit_state.as_return(true);
        }
        catch (filesystem::filesystem_error const& e) {
            return kit_state.as_return(false, e.what());
        }
    }
    luakit::variadic_results lstdfs_copy_file(lua_State* L, std::string from, std::string to, filesystem::copy_options option) {
        luakit::kit_state kit_state(L);
        try {
            filesystem::copy_file(from, to, option);
            return kit_state.as_return(true);
        }
        catch (filesystem::filesystem_error const& e) {
            return kit_state.as_return(false, e.what());
        }
    }    

    luakit::variadic_results lstdfs_rename(lua_State* L, std::string pold, std::string pnew) {
        luakit::kit_state kit_state(L);
        try {
            filesystem::rename(pold, pnew);
            return kit_state.as_return(true);
        }
        catch (filesystem::filesystem_error const& e) {
            return kit_state.as_return(false, e.what());
        }
    }

    bool lstdfs_exists(std::string path) {
        return filesystem::exists(path);
    }

    std::string lstdfs_root_name(std::string path) {
        return filesystem::path(path).root_name().string();
    }

    std::string lstdfs_filename(std::string path) {
        return filesystem::path(path).filename().string();
    }

    std::string lstdfs_extension(std::string path) {
        return filesystem::path(path).extension().string();
    }

    std::string lstdfs_root_path(std::string path) {
        return filesystem::path(path).root_path().string();
    }

    std::string lstdfs_parent_path(std::string path) {
        return filesystem::path(path).parent_path().string();
    }

    std::string lstdfs_relative_path(std::string path) {
        return filesystem::path(path).relative_path().string();
    }

    std::string lstdfs_append(std::string path, std::string append_path) {
        return filesystem::path(path).append(append_path).string();
    }

    std::string lstdfs_concat(std::string path, std::string concat_path) {
        return filesystem::path(path).concat(concat_path).string();
    }

    std::string lstdfs_remove_filename(std::string path) {
        return filesystem::path(path).remove_filename().string();
    }

    std::string lstdfs_replace_filename(std::string path, std::string filename) {
        return filesystem::path(path).replace_filename(filename).string();
    }

    std::string lstdfs_replace_extension(std::string path, std::string extens) {
        return filesystem::path(path).replace_extension(extens).string();
    }

    std::string lstdfs_stem(std::string path) {
        return filesystem::path(path).stem().string();
    }

    bool lstdfs_is_directory(std::string path) {
        return filesystem::is_directory(path);
    }

    bool lstdfs_is_absolute(std::string path) {
        return filesystem::path(path).is_absolute();
    }

    luakit::variadic_results lstdfs_last_write_time(lua_State* L, std::string path) {
        luakit::kit_state kit_state(L);
        try {
            auto ftime = filesystem::last_write_time(path);
            auto sctp = time_point_cast<system_clock::duration>(ftime - filesystem::file_time_type::clock::now() + system_clock::now());
            std::time_t cftime = system_clock::to_time_t(sctp);
            return kit_state.as_return(cftime);
        }
        catch (filesystem::filesystem_error const& e) {
            return kit_state.as_return(false, e.what());
        }
    }

    std::string get_file_type(const filesystem::path& path) {
        filesystem::file_status s = filesystem::status(path);
        switch (s.type()) {
        case filesystem::file_type::none: return "none";
        case filesystem::file_type::not_found: return "not_found";
        case filesystem::file_type::regular: return "regular";
        case filesystem::file_type::directory: return "directory";
        case filesystem::file_type::symlink: return "symlink";
        case filesystem::file_type::block: return "block";
        case filesystem::file_type::character: return "character";
        case filesystem::file_type::fifo: return "fifo";
        case filesystem::file_type::socket: return "socket";
        case filesystem::file_type::unknown: return "unknown";
        default: return "implementation-defined";
        }
    }

    std::string lstdfs_filetype(std::string path) {
        return get_file_type(filesystem::path(path));
    }

    luakit::variadic_results lstdfs_dir(lua_State* L, std::string path, bool recursive) {
        luakit::kit_state kit_state(L);
        try {
            file_vector files;
            if (recursive) {
                for (auto entry : filesystem::recursive_directory_iterator(path)) {
                    files.push_back(new file_info({ entry.path().string(), get_file_type(entry.path()) }));
                }
                return kit_state.as_return(files);
            }
            for (auto entry : filesystem::directory_iterator(path)) {
                files.push_back(new file_info({ entry.path().string(), get_file_type(entry.path()) }));
            }
            return kit_state.as_return(files);
        }
        catch (filesystem::filesystem_error const& e) {
            return kit_state.as_return(false, e.what());
        }
    }

    path_vector lstdfs_split(std::string cpath) {
        path_vector values;
        filesystem::path path = filesystem::path(cpath);
        for (auto it = path.begin(); it != path.end(); ++it) {
            values.push_back((*it).string());
        }
        return values;
    }

    luakit::lua_table open_lstdfs(lua_State* L) {
        luakit::kit_state kit_state(L);
        kit_state.new_class<file_info>("name", &file_info::name, "type", &file_info::type);
        auto lstdfs = kit_state.new_table();
        lstdfs.new_enum("copy_options",
            "none", filesystem::copy_options::none,
            "recursive", filesystem::copy_options::recursive,
            "recursive", filesystem::copy_options::recursive,
            "copy_symlinks", filesystem::copy_options::copy_symlinks,
            "copy_symlinks", filesystem::copy_options::copy_symlinks,
            "skip_symlinks", filesystem::copy_options::skip_symlinks,
            "create_symlinks", filesystem::copy_options::create_symlinks,
            "directories_only", filesystem::copy_options::directories_only,
            "create_hard_links", filesystem::copy_options::create_hard_links,
            "overwrite_existing", filesystem::copy_options::overwrite_existing
        );
        lstdfs.set_function("dir", lstdfs_dir);
        lstdfs.set_function("stem", lstdfs_stem);
        lstdfs.set_function("copy", lstdfs_copy);
        lstdfs.set_function("mkdir", lstdfs_mkdir);
        lstdfs.set_function("chdir", lstdfs_chdir);
        lstdfs.set_function("split", lstdfs_split);
        lstdfs.set_function("rename", lstdfs_rename);
        lstdfs.set_function("exists", lstdfs_exists);
        lstdfs.set_function("remove", lstdfs_remove);
        lstdfs.set_function("append", lstdfs_append);
        lstdfs.set_function("concat", lstdfs_concat);
        lstdfs.set_function("temp_dir", lstdfs_temp_dir);
        lstdfs.set_function("absolute", lstdfs_absolute);
        lstdfs.set_function("filetype", lstdfs_filetype);
        lstdfs.set_function("filename", lstdfs_filename);
        lstdfs.set_function("copy_file", lstdfs_copy_file);
        lstdfs.set_function("extension", lstdfs_extension);
        lstdfs.set_function("root_name", lstdfs_root_name);
        lstdfs.set_function("root_path", lstdfs_root_path);
        lstdfs.set_function("is_absolute", lstdfs_is_absolute);
        lstdfs.set_function("parent_path", lstdfs_parent_path);
        lstdfs.set_function("is_directory", lstdfs_is_directory);
        lstdfs.set_function("current_path", lstdfs_current_path);
        lstdfs.set_function("relative_path", lstdfs_relative_path);
        lstdfs.set_function("last_write_time", lstdfs_last_write_time);
        lstdfs.set_function("remove_filename", lstdfs_remove_filename);
        lstdfs.set_function("replace_filename", lstdfs_replace_filename);
        lstdfs.set_function("replace_extension", lstdfs_replace_extension);
        return lstdfs;
    }
}

extern "C" {
    LUALIB_API int luaopen_lstdfs(lua_State* L) {
        auto lstdfs = lstdfs::open_lstdfs(L);
        return lstdfs.push_stack();
    }
}
