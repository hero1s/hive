#pragma once

namespace lbuffer {
#ifdef WIN32
    #include <stdio.h>
    #include <windows.h>
    uint8_t* attach_shm(size_t shm_id, size_t size, size_t* shm_handle) {
        char name_buff[128];
        snprintf(name_buff, sizeof(name_buff), "shm_%zu", shm_id);
        HANDLE fileMapping = OpenFileMapping(FILE_MAP_ALL_ACCESS, FALSE, name_buff);
        if (!fileMapping) {
            fileMapping = CreateFileMapping(INVALID_HANDLE_VALUE, 0, PAGE_READWRITE, 0, size, name_buff);
            if (!fileMapping) {
                return NULL;
            }
        }
        uint8_t* shm_buff = (uint8_t*)MapViewOfFile(fileMapping, FILE_MAP_ALL_ACCESS, 0, 0, 0);
        *shm_handle = (size_t)fileMapping;
        return shm_buff;
    }

    void detach_shm(uint8_t* shm_buff, size_t shm_handle) {
        UnmapViewOfFile(shm_buff);
        HANDLE fileMapping = (HANDLE)shm_handle;
        if (fileMapping) {
            CloseHandle(fileMapping);
        }
    }

    void delete_shm(size_t shm_handle) {
    }

#else
    #include <sys/ipc.h>
    #include <sys/shm.h>

    uint8_t* attach_shm(size_t shm_id, size_t size, size_t* shm_handle) {
        int handle = shmget(shm_id, 0, 0);
        if (handle < 0) {
            handle = shmget(shm_id, size, 0666 | IPC_CREAT);
            if (handle < 0) {
                return NULL;
            }
        }
        uint8_t* shm_buff = (uint8_t*)shmat(handle, 0, 0);
        if (shm_buff == (uint8_t*)-1) {
            return NULL;
        }
        *shm_handle = handle;
        return shm_buff;
    }

    void detach_shm(uint8_t* shm_buff, size_t shm_handle) {
        shmdt(shm_buff);
    }

    void delete_shm(size_t shm_handle) {
        if (shm_handle > 0) {
            shmctl(shm_handle, IPC_RMID, NULL);
        }
    }
#endif
}

