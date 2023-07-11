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
log_debug("toXml:%s", xml2lua.toXml(people))

local xml     = [[<?xml version="1.0" encoding="gbk"?>
<req>
    <sAppClass>TENCENT</sAppClass>
    <sAppID>NORMAL</sAppID>
    <sAppSubID>-TEST</sAppSubID>
    <sAppSubIDExt>10</sAppSubIDExt>
    <sMessage>HelloWorld</sMessage>
    <sSession>123456</sSession>
    <sSrcNo>13560405750</sSrcNo>
    <sVersion>2.0</sVersion>
    <tel>13560405750</tel>
    <accountType>1</accountType>
    <timestamp>1449039957</timestamp>
    <signmsg>99cbf6345faa750f0082f2031645cf1b</signmsg>
    <sSignType>MD5</sSignType>
    <secCheck>
        <strNationCode>chn</strNationCode>
        <iAccountType>1</iAccountType>
        <strAccountAppid>appid</strAccountAppid>
        <strAccount>1234567</strAccount>
        <strClientIP>111.111.111.111</strClientIP>
        <iDeviceType>1</iDeviceType>
        <strDevice>imei123456</strDevice>
        <strDeviceName>HUAWEI</strDeviceName>
        <strReferer>https://www.qq.com</strReferer>
        <strUA>111</strUA>
        <strTraceID>2012031902923094382391</strTraceID>
    </secCheck>
</req>]]
local handler = require("xmlhandler.tree")
local parser  = xml2lua.parser(handler)
parser:parse(xml)

xml2lua.printable(handler.root)
log_warn("----%s", handler.root)