# Lua 行为树

## 支持节点类型

* Failed：总是返回FAIL
* Invert：反转执行结果
* Succeed: 总是返回成功
* Random：随机选择子节点执行
* Repeat：重复执行子节点，需要注意的是每次重复会跳帧
* Select：顺序执行，遇到成功返回
* Sequence：顺序执行，遇到失败返回
* WSelect：顺序执行，遇到成功返回，子节点按权重先排序
* WSequence：顺序执行，遇到失败返回，子节点按权重先排序
* Condition：条件节点，根据条件执行子节点
* Parallel：并行节点，根据设置的成功和失败条件返回

## 实现原理
* 节点状态
```
luabt = {
    -- Node Status
    WAITING     = 0,    --等待，中间状态，展开子节点返回
    SUCCESS     = 1,    --成功
    FAIL        = 2,    --失败
    RUNNING     = 3,    --运行
}
```
* 每次tick从root节点一次展开执行，遇到FAIL或者全部SUCCESS则reset
* 遇到RUNNING，本次tick结束，下一次从RUNNING继续执行
* 支持中断机制，中断达成后，回到中断节点继续执行

## 扩展节点

* 修饰节点Succeed, Failed, Invert：子节点从框架节点继承，同时实现on_execute接口
```
function SucceedNode:on_execute(tree)
    return SUCCESS
end
```
* 条件节点Condition：子节点从框架节点继承，同时实现on_check接口
```
function ConditionNode:on_check(tree)
    return true
end
```
* 循环节点Repeat：子节点从框架节点继承，同时实现on_check接口控制循环
```
function RepeatNode:on_check(tree)
    return true
end
```
* 普通节点Node：子节点从框架Node节点继承，同时实现run接口
```
function Flee:run(tree)
    tree.robot.hp = tree.robot.hp + 2
    print(tree.robot.hp, "Flee.....")
    return SUCCESS
end
```
* 中断节点：任意节点可以成为中断节点，只需要实现on_interrupt接口
```
function BtNode:on_interrupt(tree)
    return true
end
```
* 组合节点：直接使用系统提供的组合节点


