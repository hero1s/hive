
#include <chrono>
#include <iostream>
#include <filesystem>
#include "lua_kit.h"

using namespace std;
using namespace luakit;
using namespace std::chrono;
using namespace std::filesystem;
using fspath = std::filesystem::path;

namespace lstdfs {

    struct file_info {
        string name;
        string type;
    };
    using path_vector = vector<string>;
    using file_vector = vector<file_info*>;

    string lstdfs_absolute(string_view path) {
        return absolute(path).string();
    }

    string lstdfs_current_path() {
        return current_path().string();
    }

    string lstdfs_temp_dir() {
        return temp_directory_path().string();
    }

    int lstdfs_chdir(lua_State* L, string_view path) {
        try {
            current_path(path);
            return variadic_return(L, true);
        }
        catch (filesystem_error const& e) {
            return variadic_return(L, false, e.what());
        }
    }

    int lstdfs_mkdir(lua_State* L, string_view path) {
        try {
            bool res = create_directories(path);
            return variadic_return(L, res);
        }
        catch (filesystem_error const& e) {
            return variadic_return(L, false, e.what());
        }
    }

    int lstdfs_remove(lua_State* L, string_view path, bool rmall) {
        try {
            if (rmall) {
                auto size = remove_all(path);
                return variadic_return(L, size > 0);
            }
            bool res = remove(path);
            return variadic_return(L, res);
        }
        catch (filesystem_error const& e) {
            return variadic_return(L, false, e.what());
        }
    }

    int lstdfs_copy(lua_State* L, string_view from, string_view to, copy_options option) {
        try {
            filesystem::copy(from, to, option);
            return variadic_return(L, true);
        }
        catch (filesystem_error const& e) {
            return variadic_return(L, false, e.what());
        }
    }
    int lstdfs_copy_file(lua_State* L, string_view from, string_view to, copy_options option) {
        try {
            copy_file(from, to, option);
            return variadic_return(L, true);
        }
        catch (filesystem_error const& e) {
            return variadic_return(L, false, e.what());
        }
    }

    int lstdfs_rename(lua_State* L, string_view pold, string_view pnew) {
        try {
            rename(pold, pnew);
            return variadic_return(L, true);
        }
        catch (filesystem_error const& e) {
            return variadic_return(L, false, e.what());
        }
    }

    bool lstdfs_exists(string_view path) {
        return exists(path);
    }

    string lstdfs_root_name(string_view path) {
        return fspath(path).root_name().string();
    }

    string lstdfs_filename(string_view path) {
        return fspath(path).filename().string();
    }

    string lstdfs_extension(string_view path) {
        return fspath(path).extension().string();
    }

    string lstdfs_root_path(string_view path) {
        return fspath(path).root_path().string();
    }

    string lstdfs_parent_path(string_view path) {
        return fspath(path).parent_path().string();
    }

    string lstdfs_relative_path(string_view path) {
        return fspath(path).relative_path().string();
    }

    string lstdfs_append(string_view path, string_view append_path) {
        return fspath(path).append(append_path).string();
    }

    string lstdfs_concat(string_view path, string_view concat_path) {
        return fspath(path).concat(concat_path).string();
    }

    string lstdfs_remove_filename(string_view path) {
        return fspath(path).remove_filename().string();
    }

    string lstdfs_replace_filename(string_view path, string_view filename) {
        return fspath(path).replace_filename(filename).string();
    }

    string lstdfs_replace_extension(string_view path, string_view extens) {
        return fspath(path).replace_extension(extens).string();
    }

    string lstdfs_make_preferred(string_view path) {
        return fspath(path).make_preferred().string();
    }

    string lstdfs_stem(string_view path) {
        return fspath(path).stem().string();
    }

    bool lstdfs_is_directory(string_view path) {
        return is_directory(path);
    }

    bool lstdfs_is_absolute(string_view path) {
        return fspath(path).is_absolute();
    }

    int lstdfs_last_write_time(lua_State* L, string_view path) {
        try {
            auto ftime = last_write_time(path);
            auto sctp = time_point_cast<system_clock::duration>(ftime - file_time_type::clock::now() + system_clock::now());
            time_t cftime = system_clock::to_time_t(sctp);
            return variadic_return(L, cftime);
        }
        catch (filesystem_error const& e) {
            return variadic_return(L, 0, e.what());
        }
    }

    string get_file_type(fspath path) {
        file_status s = status(path);
        switch (s.type()) {
        case file_type::none: return "none";
        case file_type::not_found: return "not_found";
        case file_type::regular: return "regular";
        case file_type::directory: return "directory";
        case file_type::symlink: return "symlink";
        case file_type::block: return "block";
        case file_type::character: return "character";
        case file_type::fifo: return "fifo";
        case file_type::socket: return "socket";
        case file_type::unknown: return "unknown";
        default: return "implementation-defined";
        }
    }

    string lstdfs_filetype(string_view path) {
        return get_file_type(path);
    }

    int lstdfs_dir(lua_State* L, string_view path, bool recursive) {
        try {
            file_vector files;
            if (recursive) {
                for (auto entry : recursive_directory_iterator(path)) {
                    files.push_back(new file_info({ entry.path().string(), get_file_type(entry.path())}));
                }
                return variadic_return(L, files);
            }
            for (auto entry : directory_iterator(path)) {
                files.push_back(new file_info({ entry.path().string(), get_file_type(entry.path()) }));
            }
            return variadic_return(L, files);
        }
        catch (filesystem_error const& e) {
            return variadic_return(L, nullptr, e.what());
        }
    }

    path_vector lstdfs_split(string_view cpath) {
        path_vector values;
        fspath path = fspath(cpath);
        for (auto it = path.begin(); it != path.end(); ++it) {
            values.push_back((*it).string());
        }
        return values;
    }

    lua_table open_lstdfs(lua_State* L) {
        kit_state kit_state(L);
        kit_state.new_class<file_info>("name", &file_info::name, "type", &file_info::type);
        auto lstdfs = kit_state.new_table();
        lstdfs.new_enum("copy_options",
            "none", copy_options::none,
            "recursive", copy_options::recursive,
            "recursive", copy_options::recursive,
            "copy_symlinks", copy_options::copy_symlinks,
            "copy_symlinks", copy_options::copy_symlinks,
            "skip_symlinks", copy_options::skip_symlinks,
            "create_symlinks", copy_options::create_symlinks,
            "directories_only", copy_options::directories_only,
            "create_hard_links", copy_options::create_hard_links,
            "overwrite_existing", copy_options::overwrite_existing
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
        lstdfs.set_function("make_preferred", lstdfs_make_preferred);
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
