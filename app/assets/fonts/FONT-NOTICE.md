# Bundled CJK font — source, license, SHA256

Markdown Studio 的 PDF 导出把中文字体作为**应用内置资产**打包，Windows 与
Android 使用同一份 TTF（不再依赖系统字体目录，也不使用 TTC）。

## 文件

| 文件 | 大小（字节） | SHA256 |
| --- | --- | --- |
| `noto-sans-sc-regular.ttf` | 10,595,932 | `697E00C73B6A7B7A9D35912A7D65492A113ADD0F5C6D2E965E405FF3DB6A4C0D` |
| `OFL.txt` | 4,388 | `1C05C68C34F9708415AADA51F17E1B0092D2CEA709BF4A94CD38114F9E73D7D9` |

字体名（name 表）：family `Noto Sans SC`，subfamily `Regular`，PostScript
`NotoSansSC-Regular`；版本 `Version 2.004-H2;hotconv 1.0.118;makeotfexe 2.5.65603`；
31,036 glyphs，unitsPerEm 1000，`OS/2.usWeightClass = 400`，TrueType outlines
（`glyf`/`loca`，无 CFF、无 `fvar`/`gvar`）。

## 上游来源

- 仓库：`google/fonts`（Google Fonts 官方镜像）
- 固定 commit：`2894aab31764f10f29c421bdfd2340d3b382d384`
- 路径：`ofl/notosanssc/NotoSansSC[wght].ttf`
- 原始文件大小：17,772,300 字节
- 原始文件 SHA256：`A3041811A78C361B1DE50F953C805E0244951C21C5BD412F7232EF0D899AF0DA`
- Git blob SHA1（与 GitHub Contents API 返回值一致，用于完整性核对）：
  `fb0637bafbcd804fe32152370a1225990745b4bc`
- 上游当时的可变字体实例：`wght` 100–900，默认 100（Thin）。

## 本仓库对字体做的唯一改动

`pdf` 包（3.12.0）只读取 TrueType 轮廓且不理解可变字体轴，直接用上游 VF 会把
默认实例（wght=100，Thin）嵌入 PDF。因此把上游 VF **静态实例化**到 Regular
（wght=400）并更新 name 表，除此之外未做子集化、未改字形：

```powershell
python -m fontTools.varLib.instancer <upstream>/NotoSansSC[wght].ttf `
  wght=400 --update-name-table -o noto-sans-sc-regular.ttf
# fontTools 4.58.4；输出 10,595,932 字节
```

该产物是 OFL 允许的 Modified Version，继续按 OFL 1.1 分发；family 名
`Noto Sans SC` 不含 Reserved Font Name `Source`。

## 许可

SIL Open Font License 1.1（全文见同目录 `OFL.txt`）。

```
Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'.
```

- 允许嵌入 PDF、随应用再分发、修改（修改版需同样采用 OFL 且不得使用
  Reserved Font Name `Source`）。
- 不允许单独售卖字体本身。
- 字体名 "Noto" 相关商标权不随 OFL 授予；本仓库仅按原名/原样分发内置字体，
  不对字体做品牌用途。

## 复现校验

```powershell
Get-FileHash app/assets/fonts/noto-sans-sc-regular.ttf -Algorithm SHA256
# 697E00C73B6A7B7A9D35912A7D65492A113ADD0F5C6D2E965E405FF3DB6A4C0D
```
