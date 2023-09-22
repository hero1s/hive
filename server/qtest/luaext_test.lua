require("lualog")
local lcrypt = require("lcrypt")
local strlen = string.len

local object = { { a = 1 }, { a = 2 }, { a = 3 }, { a = { c = 5, 5, 9 } }, { b = 5 }, 6 }
logger.debug("{}", object)

local md5     = "Yinguohua"
local testStr = [["jdfklasjflkajslfkjalkdsjflaksjflaksdjflaksdjflaksdjlkasjflakjsdlfkasdjlkjklfdasjfl;kjadslkf;jasl;
                 gjalks;djfalkdg;jaldskjf;alkjdlk;afjl;asdkjf;laksdjgfl;sjgalkjdl;fjkas;ldfjkasl;kfj
                 jdfklasjflkajslfkjalkdsjflaksjflaksdjflaksdjflaksdjlkasjflakjsdlfkasdjlkjklfdasjfl;kjadslkf;jasl;
                 gjalks;djfalkdg;jaldskjf;alkjdlk;afjl;asdkjf;laksdjgfl;sjgalkjdl;fjkas;ldfjkasl;kfj
                 jdfklasjflkajslfkjalkdsjflaksjflaksdjflaksdjflaksdjlkasjflakjsdlfkasdjlkjklfdasjfl;kjadslkf;jasl;
                 gjalks;djfalkdg;jaldskjf;alkjdlk;afjl;asdkjf;laksdjgfl;sjgalkjdl;fjkas;ldfjkasl;kfj
                 jdfklasjflkajslfkjalkdsjflaksjflaksdjflaksdjflaksdjlkasjflakjsdlfkasdjlkjklfdasjfl;kjadslkf;jasl;
                 gjalks;djfalkdg;jaldskjf;alkjdlk;afjl;asdkjf;laksdjgfl;sjgalkjdl;fjkas;ldfjkasl;kfj
                 jdfklasjflkajslfkjalkdsjflaksjflaksdjflaksdjflaksdjlkasjflakjsdlfkasdjlkjklfdasjfl;kjadslkf;jasl;
                 gjalks;djfalkdg;jaldskjf;alkjdlk;afjl;asdkjf;laksdjgfl;sjgalkjdl;fjkas;ldfjkasl;kfj
                 jdfklasjflkajslfkjalkdsjflaksjflaksdjflaksdjflaksdjlkasjflakjsdlfkasdjlkjklfdasjfl;kjadslkf;jasl;
                 gjalks;djfalkdg;jaldskjf;alkjdlk;afjl;asdkjf;laksdjgfl;sjgalkjdl;fjkas;ldfjkasl;kfj
                 jdfklasjflkajslfkjalkdsjflaksjflaksdjflaksdjflaksdjlkasjflakjsdlfkasdjlkjklfdasjfl;kjadslkf;jasl;
                 gjalks;djfalkdg;jaldskjf;alkjdlk;afjl;asdkjf;laksdjgfl;sjgalkjdl;fjkas;ldfjkasl;kfj
                 jdfklasjflkajslfkjalkdsjflaksjflaksdjflaksdjflaksdjlkasjflakjsdlfkasdjlkjklfdasjfl;kjadslkf;jasl;
                 gjalks;djfalkdg;jaldskjf;alkjdlk;afjl;asdkjf;laksdjgfl;sjgalkjdl;fjkas;ldfjkasl;kfj
                 "]]
logger.info("test base64:{} --> {} -->> {} \n", md5, lcrypt.b64_encode(md5), lcrypt.b64_decode(lcrypt.b64_encode(md5)))
logger.info("test lz4:{} --> {} -->> {} \n", strlen(testStr), strlen(lcrypt.lz4_encode(testStr)), strlen(lcrypt.lz4_decode(lcrypt.lz4_encode(testStr))))
logger.debug("test md5,{} --> {} \n", md5, lcrypt.b64_encode(lcrypt.md5(md5)))

local teaStr = lcrypt.xxtea_encode("123123", md5)

logger.info("test xxtea:{} --> {} --> {}", md5, teaStr, lcrypt.xxtea_decode("123123", teaStr))

local mongodb = import("driver/mongo.lua")
mongodb({ db = "admin", host = "10.100.0.48", port = 27017, user = "admin", passwd = "admin123456" })

local str   = [[{
    "data":{
        "name":"gm_send_global_mail",
        "title":"111",
        "content":"111",
        "limit":1,
        "attach":[{"item_id":19001,"item_count":1}]
    }
}]]
local jstr = hive.json_decode(str)
logger.warn("json decode jstr:{}",jstr)

