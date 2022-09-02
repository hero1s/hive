local lxlsx = require "luaxlsx"

local x = lxlsx.open('test.xlsx')

local sheets = x.sheets()

print(type(sheets), #sheets)

for i, sheet1 in ipairs(sheets) do

    local f = io.open(sheet1.name .. '.txt', 'w')
    print(sheet1.name())

    for r = sheet1.first_row, sheet1.last_row do
        local row_table = {}
        for c = sheet1.first_col, sheet1.lastC_cl do
                local cell = sheet1.get_cell(r, c)
                local str = "."
                if cell then
                    print(cell.type, cell.value, cell.fmt_id, cell.fmt_code)
                    str = cell.value
                end

                table.insert(row_table, string.format("%30s", str))
        end
        f:write(table.concat(row_table, '|') .. '\n')
    end

    f:close()
end
