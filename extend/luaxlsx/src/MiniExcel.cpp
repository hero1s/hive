#include "MiniExcel.h"

#include <stdio.h>
#include <math.h>
#include <string>
#include <vector>
#include <map>

#ifndef PATH_MAX
#define PATH_MAX 260
#endif

namespace MiniExcel {

    bool isDateTime(int id)
    {
        if ((id >= 14 && id <= 22) ||
            (id >= 27 && id <= 36) ||
            (id >= 45 && id <= 47) ||
            (id >= 50 && id <= 58) ||
            (id >= 71 && id <= 81))
        {
            return true;
        }
        return false;
    }

    bool isCustom(int id)
    {
        return id > 165;
    }

    Zip::~Zip()
    {
        mz_zip_reader_end(&zip);
    }

    bool Zip::open(const char* file)
    {
        memset(&zip, 0, sizeof(zip));
        if (!mz_zip_reader_init_file(&zip, file, 0))
        {
            return false;
        }
        return true;
    }

    unsigned char* Zip::getFileData(const char* filename, size_t& size)
    {
        int file_index = mz_zip_reader_locate_file(&zip, filename, NULL, 0);
        if (file_index < 0) return NULL;

        unsigned char* pBuffer = (unsigned char*)mz_zip_reader_extract_to_heap(&zip, file_index, &size, 0);
        if (!pBuffer) return NULL;

        return pBuffer;
    }

    bool Zip::openXML(const char* filename, tinyxml2::XMLDocument& doc)
    {
        size_t size = 0;
        unsigned char* data = getFileData(filename, size);

        if (!data) return false;

        doc.Parse((const char*)data, size);

        if (data)
            delete[] data;

        return true;
    }


    Sheet::~Sheet()
    {
        for (unsigned i = 0; i < _cells.size(); i++)
        {
            delete _cells[i];
        }
    }

    Cell* Sheet::getCell(int row, int col)
    {
        if (row < _dimension.firstRow || row > _dimension.lastRow)
            return nullptr;
        if (col < _dimension.firstCol || col > _dimension.lastCol)
            return nullptr;

        return _cells[toIndex(row, col)];
    }


    int Sheet::toIndex(int row, int col)
    {
        return (row - 1) * (_dimension.lastCol - _dimension.firstCol + 1) + (col - _dimension.firstCol);
    }

    void ExcelFile::readWorkBook(const char* filename)
    {
        tinyxml2::XMLDocument doc;

        _zip->openXML(filename, doc);

        tinyxml2::XMLElement* e;
        e = doc.FirstChildElement("workbook");
        e = e->FirstChildElement("sheets");
        e = e->FirstChildElement("sheet");

        while (e)
        {
            Sheet s;

            s._name = e->Attribute("name");
            s._rid = e->Attribute("r:id");
            s._sheetId = e->IntAttribute("sheetId");
            s._visible = (e->Attribute("state") && !strcmp(e->Attribute("state"), "hidden"));

            e = e->NextSiblingElement("sheet");

            _sheets.push_back(s);
        }
    }

    void ExcelFile::readWorkBookRels(const char* filename)
    {
        tinyxml2::XMLDocument doc;

        _zip->openXML(filename, doc);
        tinyxml2::XMLElement* e = doc.FirstChildElement("Relationships");
        e = e->FirstChildElement("Relationship");

        while (e)
        {
            const char* rid = e->Attribute("Id");

            for (Sheet& sheet : _sheets)
            {
                if (sheet._rid == rid)
                {
                    sheet._path = "xl/" + std::string(e->Attribute("Target"));

                    break;
                }
            }

            e = e->NextSiblingElement("Relationship");
        }
    }

    void ExcelFile::readSharedStrings(const char* filename)
    {
        tinyxml2::XMLDocument doc;

        if (!_zip->openXML(filename, doc)) return;

        tinyxml2::XMLElement* e;

        e = doc.FirstChildElement("sst");
        e = e->FirstChildElement("si");

        tinyxml2::XMLElement* t, * r;
        int i = 0;

        while (e)
        {
            t = e->FirstChildElement("t");
            i++;
            if (t)
            {
                const char* text = t->GetText();
                _sharedString.push_back(text ? text : "");
            }
            else
            {
                r = e->FirstChildElement("r");
                std::string value;
                while (r)
                {
                    t = r->FirstChildElement("t");
                    const char* text = t->GetText();
                    value += text ? text : "";
                    r = r->NextSiblingElement("r");
                }
                _sharedString.push_back(value);
            }
            e = e->NextSiblingElement("si");
        }
    }

    void ExcelFile::readStyles(const char* filename)
    {
        tinyxml2::XMLDocument doc;
        if (!_zip->openXML(filename, doc)) return;

        tinyxml2::XMLElement* styleSheet = doc.FirstChildElement("styleSheet");
        if (styleSheet == NULL) return;

        std::map<int, std::string> customDateFormats;
        tinyxml2::XMLElement* numFmts = styleSheet->FirstChildElement("numFmts");
        if (numFmts == NULL) return;

        for (tinyxml2::XMLElement* numFmt = numFmts->FirstChildElement(); numFmt; numFmt = numFmt->NextSiblingElement())
        {
            int id = atoi(numFmt->Attribute("numFmtId"));
            std::string fmt = numFmt->Attribute("formatCode");
            customDateFormats.insert(std::make_pair(id, fmt));
        }

        tinyxml2::XMLElement* cellXfs = styleSheet->FirstChildElement("cellXfs");
        if (cellXfs == NULL) return;

        int i = 0;
        for (tinyxml2::XMLElement* cellXf = cellXfs->FirstChildElement(); cellXf; cellXf = cellXf->NextSiblingElement())
        {
            const char* fi = cellXf->Attribute("numFmtId");
            if (fi)
            {
                std::string fmt;
                int formatId = atoi(fi);
                std::map<int, std::string>::iterator iter = customDateFormats.find(formatId);
                if (iter != customDateFormats.end())
                {
                    fmt = iter->second;
                }
                _formIds.insert(std::make_pair(i, formatId));
                _fmtCodes.insert(std::make_pair(formatId, fmt));
            }
            ++i;
        }
    }

    void ExcelFile::parseCell(const std::string& value, int& row, int& col)
    {
        int index = 0;
        col = 0;

        int arr[10];

        while (index < (int)value.length())
        {
            if (isdigit(value[index])) break;
            arr[index] = value[index] - 'A' + 1;
            index++;
        }

        for (int i = 0; i < index; i++)
        {
            col += (int)(arr[i] * pow(26, index - i - 1));
        }

        row = atoi(value.c_str() + index);
    }

    void ExcelFile::parseRange(const std::string& value, Range& range)
    {
        int index = value.find_first_of(':');

        if (index != -1)
        {
            parseCell(value.substr(0, index), range.firstRow, range.firstCol);
            parseCell(value.substr(index + 1), range.lastRow, range.lastCol);
        }
        else
        {
            parseCell(value, range.firstRow, range.firstCol);
            range.lastCol = range.firstCol;
            range.lastRow = range.firstRow;
        }
    }

    void ExcelFile::readCell(Cell* c, const char* t, const char* s, tinyxml2::XMLElement* v)
    {
        c->fmtId = 0;
        c->fmtCode = "";
        if (!t && !v)
        {
            c->type = "blank";
            return;
        }
        if ((!t || !strcmp(t, "n")) && v)
        {
            if (!s)
            {
                c->type = "error";
                return;
            }
            c->value = v->GetText();
            int idx = atoi(s);
            std::map<int, int>::iterator iter = _formIds.find(idx);
            if (iter == _formIds.end())
            {
                c->type = "number";
                return;
            }
            int formatId = iter->second;
            std::map<int, std::string>::iterator iter2 = _fmtCodes.find(formatId);
            if (iter2 != _fmtCodes.end())
            {
                c->fmtCode = iter2->second;
            }
            c->fmtId = formatId;
            if (isDateTime(formatId))
            {
                c->type = "date";
            }
            else if (isCustom(formatId))
            {
                c->type = "custom";
            }
            else
            {
                c->type = "number";
            }
            return;
        }
        if (t && !strcmp(t, "s"))
        {
            c->type = "string";
            c->value = _sharedString[atoi(v->GetText())];
            return;
        }
        if (t && !strcmp(t, "inlineStr"))
        {
            c->type = "string";
            c->value = v->GetText();
            return;
        }
        if (t && !strcmp(t, "str"))
        {
            c->type = "string";
            c->value = v->GetText();
            return;
        }
        if (t && !strcmp(t, "b"))
        {
            c->type = "bool";
            c->value = v->GetText();
            return;
        }
        c->type = "error";
    }

    void ExcelFile::readSheet(Sheet& sh)
    {
        tinyxml2::XMLDocument doc;
        tinyxml2::XMLElement* root, * row, * c, * v, * d;

        _zip->openXML(sh._path.c_str(), doc);

        root = doc.FirstChildElement("worksheet");

        d = root->FirstChildElement("dimension");
        if (d)
            parseRange(d->Attribute("ref"), sh._dimension);

        row = root->FirstChildElement("sheetData");
        row = row->FirstChildElement("row");

        int vecsize = sh._dimension.lastCol * sh._dimension.lastRow;

        sh._cells.resize(vecsize);


        while (row)
        {
            int rowIdx = row->IntAttribute("r");
            c = row->FirstChildElement("c");

            while (c)
            {
                int colIdx = 0;
                parseCell(c->Attribute("r"), rowIdx, colIdx);
                int index = sh.toIndex(rowIdx, colIdx);

                v = c->FirstChildElement("v");
                const char* t = c->Attribute("t");
                const char* s = c->Attribute("s");

                Cell* cell = new Cell;
                readCell(cell, t, s, v);
                sh._cells[index] = cell;
                c = c->NextSiblingElement("c");
            }

            row = row->NextSiblingElement("row");
        }
    }

    ExcelFile::~ExcelFile()
    {
        if (_zip) delete _zip;
    }

    bool ExcelFile::open(const char* filename)
    {
        _zip = new Zip();

        if (!_zip->open(filename))
            return false;

        readWorkBook("xl/workbook.xml");
        readWorkBookRels("xl/_rels/workbook.xml.rels");
        readSharedStrings("xl/sharedStrings.xml");
        readStyles("xl/styles.xml");

        for (auto& s : _sheets)
        {
            readSheet(s);
        }

        return true;
    }


    Sheet* ExcelFile::getSheet(const char* name)
    {
        for (Sheet& sh : _sheets)
        {
            if (sh._name == name)
                return &sh;
        }

        return nullptr;
    }

}