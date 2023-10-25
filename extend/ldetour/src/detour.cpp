#include <stdlib.h>
#include <string.h>

#include <vector>

#include "detour.h"

static const int NAVMESHSET_MAGIC = 'M' << 24 | 'S' << 16 | 'E' << 8 | 'T'; //'MSET';
static const int NAVMESHSET_VERSION = 1;

namespace ldetour {

    // Returns a random number [0..1]
    static float frand() {
        return (float)rand() / (float)RAND_MAX;
    }

    // 把cur向前移动n, 若成功返回移动前的指针，否则返回NULL
    static void* offset_n(unsigned char*& cur, size_t& sz, size_t n) {
        if (sz < n) {
            return NULL;
        }
        unsigned char* old = cur;
        cur = cur + n;
        sz = sz - n;
        return old;
    }

    // calculate the distance square between two points on the xyz zone
    // [in]        point1    first point[(x, y, z)]
    // [in]        point2    second point[(x, y, z)]
    // [return]              distance square between two points
    float distanceSqrBetweenPoints(const float* point1, const float* point2) {
        float dx = point2[0] - point1[0];
        float dy = point2[1] - point1[1];
        float dz = point2[2] - point1[2];
        return dx*dx + dy*dy + dz*dz;
    }

    // 从dump到文件的mesh数据，还原出NavMesh的内存结构
    int nav_mesh::create(const char* buf, size_t sz) {
        unsigned char* stream = (unsigned char*)buf;
        nav_set_header* header = (nav_set_header*)offset_n(stream, sz, sizeof(nav_set_header));
        if (!header) {
            return DT_FAILURE | DT_INVALID_PARAM;
        }
        if (header->magic != NAVMESHSET_MAGIC) {
            return DT_FAILURE | DT_WRONG_MAGIC;
        }
        if (header->version != NAVMESHSET_VERSION) {
            return DT_FAILURE | DT_WRONG_VERSION;
        }

        nvmesh = dtAllocNavMesh();
        if (!nvmesh) {
            return DT_FAILURE;
        }
        dtStatus status = nvmesh->init(&header->params);
        if (!dtStatusSucceed(status)) {
            return status;
        }
        // Read tiles.
        for (int i = 0; i < header->num_tiles; ++i) {
            nav_tile_header* tile_header = (nav_tile_header*)offset_n(stream, sz, sizeof(nav_tile_header));
            if (!tile_header) {
                return DT_FAILURE | DT_INVALID_PARAM;
            }
            if (!tile_header->tile_ref || !tile_header->data_size) {
                return DT_FAILURE | DT_INVALID_PARAM;
            }
            void* src = offset_n(stream, sz, tile_header->data_size);
            if (!src) {
                return DT_FAILURE | DT_INVALID_PARAM;
            }
            unsigned char* data = (unsigned char*)dtAlloc(tile_header->data_size, DT_ALLOC_PERM);
            if (!data) {
                return DT_FAILURE;
            }
            memcpy(data, src, tile_header->data_size);
            nvmesh->addTile(data, tile_header->data_size, DT_TILE_FREE_DATA, tile_header->tile_ref, 0);
        }
        return DT_SUCCESS;
    }

    nav_mesh::~nav_mesh() {
        if (nvmesh) {
            dtFreeNavMesh(nvmesh);
            nvmesh = nullptr;
        }
    }

    int nav_mesh::get_max_tiles() {
        return nvmesh->getMaxTiles();
    }

    nav_query* nav_mesh::create_query(const int max_nodes, float scale) {
        nav_query* query = new nav_query();
        if(!dtStatusSucceed(query->create(nvmesh, max_nodes, scale))) {
            delete query;
            return nullptr;
        }
        return query;
    }

    // 多边形是否合法
    bool nav_query::poly_valid(dtPolyRef* poly_ref) {
        unsigned short flags;
        return dtStatusSucceed(mesh_ref->getPolyFlags(*poly_ref, &flags));
    }

    nav_query::~nav_query() {
        if (nvquery) {
            dtFreeNavMeshQuery(nvquery);
            nvquery = nullptr;
        }
        if (polys) {
            delete [] polys;
            polys = nullptr;
        }
        if (points) {
            delete [] points;
            points = nullptr;
        }
    }

    int32_t nav_query::pformat(float v) {
        return (int32_t)(v * qscale);
    }

    int nav_query::create(dtNavMesh* mesh, const int max_nodes, float scale ) {
        mesh_ref = mesh;
        qscale = scale;
        filter = dtQueryFilter();
        nvquery = dtAllocNavMeshQuery();
        if (!nvquery) {
            return DT_FAILURE | DT_OUT_OF_MEMORY;
        }
        int status = nvquery->init(mesh_ref, max_nodes);
        if (!dtStatusSucceed(status)) {
            return status;
        }
        polys = new dtPolyRef[max_nodes];
        if (!polys) {
            return DT_FAILURE | DT_OUT_OF_MEMORY;
        }
        max_polys = max_nodes;
        points = new nav_point[max_nodes];
        if (!points) {
            return DT_FAILURE | DT_OUT_OF_MEMORY;
        }
        max_points = max_nodes;
        return DT_SUCCESS;
    }

    int nav_query::raycast(lua_State* L, int32_t sx, int32_t sy, int32_t sz, int32_t ex, int32_t ey, int32_t ez) {
        float extents[3] = { 2, 4, 2 };    // 沿着每个轴的搜索长度
        float end_pos[3] = { ex / qscale, ey / qscale, ez / qscale };
        float start_pos[3] = { sx / qscale, sy / qscale, sz / qscale };

        nav_point nearestPt;
        dtPolyRef start_ref;  // 起点所在的多边形
		filter.setExcludeFlags(0);
        filter.setIncludeFlags(0xffff);
		nvquery->findNearestPoly(start_pos, extents, &filter, &start_ref, nearestPt);
        if (!start_ref) {
            return luakit::variadic_return(L, false);
        }
        float t = 0;
        int npolys = 0;
        nav_point hit_normal, hit_point;
        nvquery->raycast(start_ref, start_pos, end_pos, &filter, &t, hit_normal, polys, &npolys, max_polys);
        if (t > 1) {
            return luakit::variadic_return(L, true);
        }
        hit_point[0] = start_pos[0] + (end_pos[0] - start_pos[0]) * t;
        hit_point[1] = start_pos[1] + (end_pos[1] - start_pos[1]) * t;
        hit_point[2] = start_pos[2] + (end_pos[2] - start_pos[2]) * t;
        return luakit::variadic_return(L, true, pformat(hit_point[0]), pformat(hit_point[1]), pformat(hit_point[2]));
    }

    int nav_query::find_path(lua_State* L, int32_t sx, int32_t sy, int32_t sz, int32_t ex, int32_t ey, int32_t ez) {
        dtPolyRef start_ref, end_ref;           // 起点/终点所在的多边形
        float half_extents[3] = { 2, 4, 2 };    // 沿着每个轴的搜索长度

        float end_pos[3] = { ex / qscale, ey / qscale, ez / qscale };
        float start_pos[3] = { sx / qscale, sy / qscale, sz / qscale };
        nvquery->findNearestPoly(start_pos, half_extents, &filter, &start_ref, 0);
        nvquery->findNearestPoly(end_pos, half_extents, &filter, &end_ref, 0);
        if (!start_ref || !end_ref) {
            return luakit::variadic_return(L, 0);
        }

        int npolys = 0;
        int path_count = 0;
        nvquery->findPath(start_ref, end_ref, start_pos, end_pos, &filter, polys, &npolys, max_polys);
        if (npolys) {
            // In case of partial path, make sure the end point is clamped to the last polygon.
            float epos[3];
            dtVcopy(epos, end_pos);
            if (polys[npolys - 1] != end_ref){
                nvquery->closestPointOnPoly(polys[npolys - 1], end_pos, epos, 0);
            }
            nvquery->findStraightPath(start_pos, epos, polys, npolys, (float*)points, nullptr, nullptr, &path_count, max_points, 0);
        }
        std::vector<int32_t> path(path_count * 3);
        for (int i = 0; i < path_count; ++i) {
            path[i * 3] = pformat(points[i][0]);
            path[i * 3 + 1] = pformat(points[i][1]);
            path[i * 3 + 2] = pformat(points[i][2]);
        }
        return luakit::variadic_return(L, path_count, std::move(path));
    }

    int nav_query::random_point(lua_State* L) {
        // filter.setAreaCost(SAMPLE_POLYAREA_GROUND, 1.0f);
        // filter.setAreaCost(SAMPLE_POLYAREA_WATER, 10.0f);
        // filter.setAreaCost(SAMPLE_POLYAREA_ROAD, 1.0f);
        // filter.setAreaCost(SAMPLE_POLYAREA_DOOR, 1.0f);
        // filter.setAreaCost(SAMPLE_POLYAREA_GRASS, 2.0f);
        // filter.setAreaCost(SAMPLE_POLYAREA_JUMP, 1.5f);
        // filter.setIncludeFlags(SAMPLE_POLYFLAGS_ALL);
        nav_point pos;
        dtPolyRef ref;
        nvquery->findRandomPoint(&filter, frand, &ref, pos);

        //luakit::kit_state state(L);
        return luakit::variadic_return(L, pformat(pos[0]), pformat(pos[1]), pformat(pos[2]));
    }

    int nav_query::around_point(lua_State* L, int32_t x, int32_t y, int32_t z, int32_t radius) {
        float radius_f = radius / qscale;
        const float radius_max = 40;
        if (radius_f > radius_max) {
            radius_f = radius_max;
        }
        float half_extents[3] = { 2, 4, 2 };    // 沿着每个轴的搜索长度
        dtPolyRef start_ref;
        dtPolyRef random_ref;
        nav_point random_pos;
        float pos[3] = { x / qscale, y / qscale, z / qscale };
        nvquery->findNearestPoly(pos, half_extents, &filter, &start_ref, 0);
        if (!start_ref) {
            return luakit::variadic_return(L, false);
        }
        int try_count = 3; // 最多尝试3次
        float radius_sqr = radius_f * radius_f; // 距离的平方
        while (try_count-- > 0) {
            bool found = nvquery->findRandomPointAroundCircle(start_ref, pos, radius_f, &filter, frand, &random_ref, random_pos) == DT_SUCCESS;
            if (found && poly_valid(&random_ref) && distanceSqrBetweenPoints(pos, random_pos) <= radius_sqr) {
                // 随机点可寻路，返回
                break;
            }
        }
        if (try_count < 0) {
            // 重试次数用完了，但是未找到
            return luakit::variadic_return(L, false);
        }
        return luakit::variadic_return(L, pformat(random_pos[0]), pformat(random_pos[1]), pformat(random_pos[2]));
    }

    bool nav_query::point_valid(lua_State* L, int32_t x, int32_t y, int32_t z) {
        dtPolyRef ref;           // 起点/终点所在的多边形
        float half_extents[3] = { 2, 4, 2 };    // 沿着每个轴的搜索长度

        float pos[3] = { x / qscale, y / qscale, z / qscale };
        nvquery->findNearestPoly(pos, half_extents, &filter, &ref, 0);
        if (!ref) {
            return false;
        }
        return true;
    }

    int nav_query::find_valid_point(lua_State* L, int32_t sx, int32_t sy, int32_t sz, int32_t ex, int32_t ey, int32_t ez, bool is_along_surface)
    {
        //查找开始位置所在的poly
        dtPolyRef start_ref;           // 起点/合法终点所在的多边形
        float half_extents[3] = { 2, 4, 2 };    // 沿着每个轴的搜索长度
        float start_pos[3] = { sx / qscale, sy / qscale, sz / qscale };
        dtStatus status = nvquery->findNearestPoly(start_pos, half_extents, &filter, &start_ref, 0);
        if (status != DT_SUCCESS || !start_ref) {
            return luakit::variadic_return(L, false);
        }

        //查找可到达的结束位置
        int npolys = 0;
        nav_point pos;
        float end_pos[3] = { ex / qscale, ey / qscale, ez / qscale };
        if (is_along_surface)
        {
            // 贴地移动可以到达的位置
            status = nvquery->moveAlongSurface(start_ref, start_pos, end_pos, &filter, pos, polys, &npolys, max_polys);
        }
        else
        {
            // 射线可以到达的位置
            float t = 0;
            nav_point hit_normal;
            status = nvquery->raycast(start_ref, start_pos, end_pos, &filter, &t, hit_normal, polys, &npolys, 64);
            pos[0] = end_pos[0];
            pos[1] = end_pos[1];
            pos[2] = end_pos[2];
            if (t < 1)
            {
                pos[0] = start_pos[0] + (end_pos[0] - start_pos[0]) * t;
                pos[1] = start_pos[1] + (end_pos[1] - start_pos[1]) * t;
                pos[2] = start_pos[2] + (end_pos[2] - start_pos[2]) * t;
            }
        }
        if (status != DT_SUCCESS || npolys <= 0)
        {
            return luakit::variadic_return(L, false);
        }

        //查找结束位置的高度
        float height = pos[1];
        dtPolyRef lastPolyRef = polys[npolys - 1];
        status = nvquery->getPolyHeight(lastPolyRef, pos, &height);
        if (status != DT_SUCCESS)
        {
            return luakit::variadic_return(L, false);
        }
        pos[1] = height;
        return luakit::variadic_return(L, true, pformat(pos[0]), pformat(pos[1]), pformat(pos[2]));
    }
}