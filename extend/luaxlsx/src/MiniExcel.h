#ifndef _TINYXLSX_H_
#define _TINYXLSX_H_

#include <map>
#include <vector>
#include <string>
#include "miniz.h"
#include "tinyxml2.h"

namespace MiniExcel
{
    struct Cell
    {
        std::string value;
        std::string type;
        std::string fmtCode;
        int fmtId;
    };

    struct Range
    {
        int firstRow;
        int lastRow;
        int firstCol;
        int lastCol;
    };

    class Sheet
    {
    public:
        ~Sheet();

        bool visible() { return _visible; }
        const std::string& getName() { return _name; }
        Range& getDimension() { return _dimension; }

        Cell* getCell(int row, int col);
    private:
        friend class ExcelFile;

        int toIndex(int row, int col);

        int _sheetId;
        bool _visible;
        Range _dimension;

        std::string _rid;
        std::string _path;
        std::string _name;

        std::vector<Cell*> _cells;
    };

    class Zip
    {
    public:
        ~Zip();

        bool open(const char* file);
        bool openXML(const char* filename, tinyxml2::XMLDocument& doc);

    private:
        unsigned char* getFileData(const char* filename, size_t& size);
        mz_zip_archive zip;
    };

    class ExcelFile
    {
    public:
        ~ExcelFile();
        bool open(const char* filename);

        Sheet* getSheet(const char* name);
        std::vector<Sheet>& sheets() { return _sheets; }

    private:

        void readWorkBook(const char* filename);
        void readWorkBookRels(const char* filename);
        void readSharedStrings(const char* filename);
        void readStyles(const char* filename);
        void readSheet(Sheet& sh);
        void readCell(Cell* c, const char* t, const char* s, tinyxml2::XMLElement* v);

        void parseCell(const std::string& value, int& row, int& col);
        void parseRange(const std::string& value, Range& range);

        std::map<int, int> _formIds;
        std::map<int, std::string> _fmtCodes;
        std::vector<std::string> _sharedString;
        std::vector<Sheet> _sheets;
        Zip* _zip;
    };
}


#endif