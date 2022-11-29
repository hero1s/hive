#pragma once

#include <map>
#include <vector>
#include <string>
#include <math.h>
#include "miniz.h"
#include "tinyxml2.h"
#include "lua_kit.h"

using namespace std;
using namespace tinyxml2;

namespace lxlsx
{
    bool is_date_ime(uint32_t id) {
        return (id >= 14 && id <= 22) || (id >= 27 && id <= 36) || (id >= 45 && id <= 47)
            || (id >= 50 && id <= 58) || (id >= 71 && id <= 81);
    }

    bool is_custom(uint32_t id) {
        return id > 165;
    }

    class cell
    {
    public:
        void __gc() {}
        string type = "";
        string value = "";
        string fmt_code = "";
        uint32_t fmt_id = 0;

        cell* clone() {
            cell* cl = new cell();
            cl->type = type;
            cl->value = value;
            cl->fmt_code = fmt_code;
            cl->fmt_id = fmt_id;
            return cl;
        }
    };

    class sheet
    {
    public:
        ~sheet() {
            for (auto cell : cells){ if (cell) delete cell; }
        }

        void __gc() {}
        cell* get_cell(uint32_t row, uint32_t col) {
            if (row < first_row || row > last_row || col < first_col || col > last_col)
                return nullptr;
            uint32_t index = (row - 1) * (last_col - first_col + 1) + (col - first_col);
            return cells[index];
        }

        void add_cell(uint32_t row, uint32_t col, cell* co) {
             if (row < first_row || row > last_row || col < first_col || col > last_col)
                return;
            uint32_t index = (row - 1) * (last_col - first_col + 1) + (col - first_col);
            cells[index] = co;
        }

        string rid;
        string name;
        string path;
        bool visible = true;
        uint32_t sheet_id = 0;
        uint32_t last_row = 0;
        uint32_t last_col = 0;
        uint32_t first_row = 0;
        uint32_t first_col = 0;
        vector<cell*> cells = {};
    };

    class excel_file
    {
    public:
        ~excel_file() { 
            mz_zip_reader_end(&archive);
            for (auto sh : excel_sheets) { if (sh) delete sh; }
        }

        bool open(const char* filename) {
            memset(&archive, 0, sizeof(archive));
            if (mz_zip_reader_init_file(&archive, filename, 0)) {
                read_work_book("xl/workbook.xml");
                read_shared_strings("xl/sharedStrings.xml");
                read_work_book_rels("xl/_rels/workbook.xml.rels");
                read_styles("xl/styles.xml");
                for (auto s : excel_sheets) {
                    read_sheet(s);
                }
                return true;
            }
            return false;
        }

        sheet* get_sheet(const char* name){
            for (auto sh : excel_sheets) {
                if (sh->name == name) return sh;
            }
            return nullptr;
        }

        luakit::reference sheets(lua_State* L) { 
            luakit::kit_state kit_state(L);
            return kit_state.new_reference(excel_sheets);
        }

    private:
        bool open_xml(const char* filename, XMLDocument& doc){
            uint32_t index = mz_zip_reader_locate_file(&archive, filename, nullptr, 0);
            if (index >= 0) {
                size_t size = 0;
                auto data = (const char*)mz_zip_reader_extract_to_heap(&archive, index, &size, 0);
                if (data && doc.Parse(data, size) == XML_SUCCESS) {
                    delete[] data;
                    return true;
                }
            }
            return false;
        }

        void read_sheet(sheet* sh) {
            XMLDocument doc;
            if (!open_xml(sh->path.c_str(), doc)) return;

            XMLElement* root = doc.FirstChildElement("worksheet");
            XMLElement* dim = root->FirstChildElement("dimension");
            if (dim) {
                parse_range(dim->Attribute("ref"), sh);
            }
            sh->cells.resize(sh->last_col * sh->last_row);

            XMLElement* row = root->FirstChildElement("sheetData");
            row = row->FirstChildElement("row");
            while (row) {
                uint32_t row_idx = row->IntAttribute("r");
                XMLElement* c = row->FirstChildElement("c");
                while (c) {
                    uint32_t col_idx = 0;
                    cell* cel = new cell;
                    parse_cell(c->Attribute("r"), row_idx, col_idx);
                    read_cell(cel, c->Attribute("t"), c->Attribute("s"), c->FirstChildElement("v"));
                    sh->add_cell(row_idx, col_idx, cel);
                    c = c->NextSiblingElement("c");
                }
                row = row->NextSiblingElement("row");
            }
            XMLElement* mcell = root->FirstChildElement("mergeCells");
            if (mcell) {
                mcell = mcell->FirstChildElement("mergeCell");
                while (mcell) {
                    merge_cells(sh, mcell->Attribute("ref"));
                    mcell = mcell->NextSiblingElement("mergeCell");
                }
            }
        }
        
        void read_styles(const char* filename){
            XMLDocument doc;
            if (!open_xml(filename, doc)) return;

            XMLElement* styleSheet = doc.FirstChildElement("styleSheet");
            if (styleSheet == nullptr) return;
            XMLElement* numFmts = styleSheet->FirstChildElement("numFmts");
            if (numFmts == nullptr) return;

            map<int, string> custom_date_formats;
            for (XMLElement* numFmt = numFmts->FirstChildElement(); numFmt; numFmt = numFmt->NextSiblingElement()) {
                uint32_t id = atoi(numFmt->Attribute("numFmtId"));
                string fmt = numFmt->Attribute("formatCode");
                custom_date_formats.insert(make_pair(id, fmt));
            }

            XMLElement* cellXfs = styleSheet->FirstChildElement("cellXfs");
            if (cellXfs == nullptr) return;

            uint32_t i = 0;
            for (XMLElement* cellXf = cellXfs->FirstChildElement(); cellXf; cellXf = cellXf->NextSiblingElement()) {
                const char* fi = cellXf->Attribute("numFmtId");
                if (fi) {
                    string fmt;
                    uint32_t formatId = atoi(fi);
                    map<int, string>::iterator iter = custom_date_formats.find(formatId);
                    if (iter != custom_date_formats.end()) {
                        fmt = iter->second;
                    }
                    form_ids.insert(make_pair(i, formatId));
                    fmt_codes.insert(make_pair(formatId, fmt));
                }
                ++i;
            }
        }

        void read_work_book(const char* filename) {
            XMLDocument doc;
            if (!open_xml(filename, doc)) return;
            XMLElement* e = doc.FirstChildElement("workbook");
            e = e->FirstChildElement("sheets");
            e = e->FirstChildElement("sheet");
            while (e) {
                sheet* s = new sheet();
                s->rid = e->Attribute("r:id");
                s->name = e->Attribute("name");
                s->sheet_id = e->IntAttribute("sheetId");
                s->visible = (e->Attribute("state") && !strcmp(e->Attribute("state"), "hidden"));
                e = e->NextSiblingElement("sheet");
                excel_sheets.push_back(s);
            }
        }

        void read_shared_strings(const char* filename) {
            XMLDocument doc;
            if (!open_xml(filename, doc)) return;
            XMLElement* e = doc.FirstChildElement("sst");
            e = e->FirstChildElement("si");
            while (e) {
                XMLElement* t = e->FirstChildElement("t");
                if (t) {
                    const char* text = t->GetText();
                    shared_string.push_back(text ? text : "");
                    e = e->NextSiblingElement("si");
                    continue;
                }
                string value;
                XMLElement* r = e->FirstChildElement("r");
                while (r) {
                    t = r->FirstChildElement("t");
                    const char* text = t->GetText();
                    if (text) value.append(text);
                    r = r->NextSiblingElement("r");
                }
                shared_string.push_back(value);
                e = e->NextSiblingElement("si");
            }
        }

        void read_work_book_rels(const char* filename){
            XMLDocument doc;
            if (!open_xml(filename, doc)) return;
            XMLElement* e = doc.FirstChildElement("Relationships");
            e = e->FirstChildElement("Relationship");
            while (e) {
                const char* rid = e->Attribute("Id");
                for (auto sheet : excel_sheets) {
                    if (sheet->rid == rid) {
                        sheet->path = "xl/" + std::string(e->Attribute("Target"));
                        break;
                    }
                }
                e = e->NextSiblingElement("Relationship");
            }
        }

        void read_cell(cell* c, const char* t, const char* s, XMLElement* v){
            if (!v || !v->GetText()) {
                c->type = "blank";
                return;
            }
            c->type = "error";
            c->value = v->GetText();
            if (!t || !strcmp(t, "n")) {
                c->type = "number";
                if (s) {
                    uint32_t idx = atoi(s);
                    auto it = form_ids.find(idx);
                    if (it == form_ids.end()) return;
                    uint32_t format_id = it->second;
                    auto it2 = fmt_codes.find(format_id);
                    if (it2 == fmt_codes.end()) return;
                    c->fmt_id = format_id;
                    c->fmt_code = it2->second;
                    if (is_date_ime(format_id)) {
                        c->type = "date";
                    } else if (is_custom(format_id)) {
                        c->type = "custom";
                    }
                    return;
                }
            }
            if (!t) return;
            if (!strcmp(t, "s")) {
                c->type = "string";
                c->value = shared_string[atoi(v->GetText())];
            } else if (!strcmp(t, "inlineStr")) {
                c->type = "string";
            } else if (!strcmp(t, "str")) {
                c->type = "string";
            } else if (!strcmp(t, "b")) {
                c->type = "bool";
            }
        }

        void parse_cell(const string& value, uint32_t& row, uint32_t& col) {
            col = 0;
            uint32_t arr[10];
            uint32_t index = 0;
            while (index < value.length()) {
                if (isdigit(value[index])) break;
                arr[index] = value[index] - 'A' + 1;
                index++;
            }
            for (uint32_t i = 0; i < index; i++) {
                col += (arr[i] * pow(26, index - i - 1));
            }
            row = atol(value.c_str() + index);
        }

        void merge_cells(sheet* sh, const string& value) {
            size_t index = value.find_first_of(':');
            if (index != string::npos) {
                uint32_t first_row = 0, first_col = 0, last_row = 0, last_col = 0;
                parse_cell(value.substr(0, index), first_row, first_col);
                parse_cell(value.substr(index + 1), last_row, last_col);
                cell* valc = sh->get_cell(first_row, first_col);
                if (valc) {
                    for (uint32_t i = first_row;  i <= last_row; ++i) {
                        for (uint32_t j = first_col; j <= last_col; ++j) {
                            if (i != first_row || j != first_col) {
                                sh->add_cell(i, j, valc->clone());
                            }
                        }
                    }
                }
            }
        }

        void parse_range(const string& value, sheet* sh) {
            size_t index = value.find_first_of(':');
            if (index != string::npos) {
                parse_cell(value.substr(0, index), sh->first_row, sh->first_col);
                parse_cell(value.substr(index + 1), sh->last_row, sh->last_col);
            } else {
                parse_cell(value, sh->first_row, sh->first_col);
                sh->last_col = sh->first_col;
                sh->last_row = sh->first_row;
            }
        }

        mz_zip_archive archive;
        vector<sheet*> excel_sheets;
        vector<string> shared_string;
        map<uint32_t, uint32_t> form_ids;
        map<uint32_t, string> fmt_codes;
    };
}
