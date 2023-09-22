local xml2lua = require("xml2lua")
print("xml2lua v" .. xml2lua._VERSION .. "\n")

local log_debug = logger.debug
local log_warn  = logger.warn

local people    = {
    person = {
        { _attr = { type = "natural" }, name = "Manoel", city = "Palmas-TO" },
        { _attr = { type = "natural" }, name = "Breno", city = "Palmas-TO" },
        { _attr = { type = "legal" }, name = "University of Brasília", city = "Brasília-DF" }
    }
}

print("People Table\n")
xml2lua.printable(people)
print("\n------------------------------------------------------\n")

print("XML Representation\n")
log_debug("toXml:{}", xml2lua.toXml(people))

local xml     = [[<?xml version="1.0" encoding="gbk"?>
<req>
<sAppClass>TENCENT</sAppClass>
<sAppID>NORMAL</sAppID>
<sAppSubID>-XXXX</sAppSubID>
<sMessage>1000</sMessage>
<sSrcNo>1379449xxxx</sSrcNo>
<sVersion>2.0</sVersion>
<tel>1379449xxxx</tel>
<timestamp>1589276806</timestamp>
<signmsg>20cc336b9cccdcaa55cdc768b96459ec</signmsg>
</req>]]
local handler = require("xmlhandler.tree")
local parser  = xml2lua.parser(handler)
parser:parse(xml)

xml2lua.printable(handler.root)
log_warn("----{}", handler.root)

local param = {
    req = {
        sAppClass = "TENCENT",
        sAppID    = "NORMAL",
        sAppSubID = "XXXX",
        sMessage  = "1000",
        sSrcNo    = "tel",
        sVersion  = "2.0",
        tel       = "tel",
        timestamp = hive.now,
        signmsg   = "",
        secCheck  = {
            strNationCode = "chn",
            strClientIP   = "127.0.0.1",
            strTraceID    = hive.new_guid(),
        }
    }
}

log_warn("table to xml:{}", xml2lua.toXml(param))
