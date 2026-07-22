# 蓝图坐标统一换算设计

## 目标

用一个纯 Lua 坐标模块统一计算蓝图实体、地格、资源区域和清理范围的 surface 坐标，删除根据试放 ghost 猜测锚点的旧逻辑。

## 坐标模型

输入为蓝图局部位置 `L`、条目建造位置 `P`、放置方向 `D`，以及蓝图的 `snap_to_grid`、`absolute_snapping`、`position_relative_to_grid`。

绝对吸附时，先把网格大小和绝对偏移按 `D` 旋转，再逐轴计算吸附锚点：

```text
A[i] = O[i] + floor((P[i] - O[i]) / S[i]) * S[i]
surface_position = rotate(L, D) + A
```

相对吸附和无吸附时，单次脚本建造没有全局绝对网格约束，使用 `A = P`。UI 中的“网格位置”已经通过整体平移体现在蓝图实体和地格的局部坐标中，不再额外加减。

四个正交方向使用精确整数旋转；旋转 90 或 270 度时交换网格宽高。实体最终方向为 `(entity.direction + D) % 16`。

## 流水线

`apply_blueprint` 导入蓝图后创建一次 transform。静态 AABB、L3 资源与地格操作、资源标记删除全部复用该 transform。每层只调用一次 `build_blueprint`，仍把条目原始 `pos` 和 `direction` 交给 Factorio。

删除 `resolve_blueprint_content_anchor`、`infer_runtime_anchor`、试放 ghost 和锚点调整日志。正式 ghost 的真实 AABB 清理继续保留，作为碰撞箱覆盖检查，不参与坐标推断。

## 测试

纯模块覆盖无吸附、相对吸附、`390×98 / 195,1`、`392×383 / 196,196`、负局部坐标和四个正交旋转。集成测试验证每层只建造一次，并验证资源坐标与标记坐标来自同一个 transform。

## 发布

版本升级为 `2.0.6`，changelog 使用英文说明统一坐标公式和删除试放反推。
