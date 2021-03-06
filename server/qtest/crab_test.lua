local crab  = require "lcrab"

local t     = { "意外",
                "有点",
                "有点心动",
                "我一直",
                "一个人",
                "一种",
                "一种麦子",
                "一",
                "可以有足够的时间",
                "无论",
                "生死",
                "还是",
                "离别",
                "一次",
                "真的足够了",
                "从不",
                "盲目",
                "期待" }

local words = {}
for _,line in ipairs(t) do
    local t = {}
    assert(crab.toutf32(line, t), "non utf8 words detected:" .. line)
    table.insert(words, t)
end

crab.open(words)

local input = [["那些意外，似乎来的早了些，也只能听从心的指引，去做到最好。
无论生死，还是离别，一次，真的足够了。
如果我不能带给你平静的喜乐，请你一定要远离我，
若你还爱我，舍不得，请珍惜我，给我安宁与平静的欢喜。
单薄的衣衫，翩跹在春风里，似乎有点瑟瑟。
凝眸花草，我彻底的寂寞着，有点心酸，有点心动，依然还有回眸的幸福。
床头的旧照片，还是我从电脑上临摹的，你温暖的眼神依旧，仿佛注视着我。
我爱极了瞳孔里的深邃，无眠的夜晚，我常常悄悄的与那个你对着话，也不知道聊着什么。
抚摸着那个轮廓，很近，又很远，依然不能阻止那些温暖，仿佛就在身边，在心底升腾着笑意。
心有所定，只是专注着，在人群中静静独立着，保持着一种完整的姿态，等待着。
从不是盲目的期待，也不是纠缠，我知道，我一直遇见着那颗心，那颗总能让我温暖的心。
或许，太过执着，总有些患得患失，心底寂静无声依赖着。
现世依旧安稳着，静静相守，一个人愿意跟另一个人一起老去，是一种最美的承诺。
我庆幸着，我没有一个人相思着，我爱着的人，如此爱着我。
这些寂寞，似乎是些折磨，又似乎是幸福，我可以有足够的时间，慢慢的想，慢慢的等。
相爱，是一场真心的对奕，从不怕辜负，我只怕我不能带给你快乐，若我不能，你一定要离开。
我的内心，那么的希望，你能找寻到自己的快乐。
梨花似雪的心情，遥望着，这个世界上，即使再阴暗的角落，也会有爱情的微光照耀。
我们终其一生寻找的，或许就是灵魂的安放地，不找到是无法罢休的。
或许，只是一种形式的亲近，亦或是一种心的贴近，有心，用心，安心，足够了。
人的一生，何其漫长，纵然遇到再多的人，那个对的只有你。
无论遇到谁，我已然没有爱的能力了，一次足够了，他们都不是你。
无论是否适合，我知道，自己的内心如此固执的深爱着。
凡此世间种种，或者都是因果循环。"]]

local texts = {}
assert(crab.toutf32(input, texts), "non utf8 words detected:", texts)
crab.filter(texts)
local output = crab.toutf8(texts)

logger.debug(output)