# RIS 毫米波通感一体化 · 目标定位全流程

## 交付文件

- `RIS_通感一体化_定位全流程.pptx`：12 页 PowerPoint，16:9，可直接编辑文字与版式。
- `RIS_通感一体化_定位全流程.pdf`：同版 PDF 预览。
- `preview_contact_sheet.png`：12 页缩略图总览。

## 内容结构

1. 封面
2. 核心结论：两阶段参数估计
3. 坐标与输出
4. 总流程结构图
5. 粗定位：距离与速度
6. 粗定位：角度与锁定
7. RIS 四条路径几何
8. 精定位：预测—比较—修正
9. RIS 约束从哪里来
10. FAS 插在哪里
11. 误差与边界
12. 代码地图与总结

## LaTeX / TikZ 源文件

结构图由 XeLaTeX + TikZ 独立编译，源文件在：

`../latex_src/*.tex`

对应的 PDF / PNG 在：

`../figures/`

## 复现

```text
python ../make_ppt.py
```

需要：Python、python-pptx、Pillow；TikZ 图需要 XeLaTeX 与 Microsoft YaHei 字体。
