---
name: eco-data-explore
description: 自动探索数据集，识别关键变量，生成数据档案。支持 .xlsx、.csv、.dta 格式。
argument-hint: '"数据路径"'
allowed-tools: Read, Write, Bash, Glob
---

# Eco-Data-Explore: 数据探索技能

## 你的任务
探索用户提供的数据集，识别可用变量，生成结构化的数据档案供后续分析使用。
档案中包含识别策略初判、固定效应推荐、聚类SE推荐，使后续 eco-analysis 技能可以直接使用。

## 数据路径
$ARGUMENTS 即数据路径。如果是目录，扫描其中所有数据文件。

---

## 步骤 1：扫描数据文件

用 Glob 找出路径下所有 .xlsx、.csv、.dta 文件，列出清单。

---

## 步骤 2：读取并分析每个数据文件

对每个文件运行 Python 代码：

```python
import pandas as pd
import sys
sys.stdout.reconfigure(encoding='utf-8')

# 根据文件类型读取
# .xlsx: pd.read_excel(path)
# .csv: pd.read_csv(path)
# .dta: pd.read_stata(path)

df = pd.read_[format](path)

print("=== 数据基本信息 ===")
print(f"行数: {len(df)}, 列数: {len(df.columns)}")
print(f"\n所有变量名:\n{list(df.columns)}")
print(f"\n数据类型:\n{df.dtypes}")
print(f"\n描述统计:\n{df.describe()}")
print(f"\n缺失值情况:\n{df.isnull().sum()[df.isnull().sum()>0]}")
print(f"\n前3行:\n{df.head(3).to_string()}")
```

---

## 步骤 2b：数据清洗预处理

在读取数据后，自动检测并处理以下两类常见问题，清洗结果写入数据档案。

### 2b-1：日期/年份格式检测与转换

```python
import pandas as pd
import numpy as np
import sys
sys.stdout.reconfigure(encoding='utf-8')

print("=== 日期/年份格式检测 ===")

# 检测字符串型日期列（如 "2015-03-01"、"20150301"）
str_cols = df.select_dtypes(include=['object']).columns.tolist()
date_candidates = []
for c in str_cols:
    sample = df[c].dropna().head(20).astype(str)
    # 匹配常见日期格式：YYYY-MM-DD、YYYYMMDD、YYYY/MM/DD
    looks_like_date = sample.str.match(
        r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}$|^\d{8}$'
    ).mean()
    if looks_like_date > 0.8:
        date_candidates.append(c)

if date_candidates:
    print(f"检测到疑似日期列: {date_candidates}")
    for c in date_candidates:
        try:
            df[f'{c}_parsed'] = pd.to_datetime(df[c], infer_datetime_format=True, errors='coerce')
            df[f'{c}_year']   = df[f'{c}_parsed'].dt.year
            df[f'{c}_month']  = df[f'{c}_parsed'].dt.month
            n_fail = df[f'{c}_parsed'].isna().sum()
            print(f"  {c} → 已解析，year列={c}_year，解析失败={n_fail}行")
        except Exception as e:
            print(f"  {c} 解析失败: {e}")
else:
    print("未检测到字符串日期列，跳过日期转换。")

# 检测数值型"年份"列并确认是否已为整数
num_year_cols = [c for c in df.select_dtypes(include=[np.number]).columns
                 if df[c].dropna().between(1900, 2100).mean() > 0.9
                 and df[c].nunique() < 100]
if num_year_cols:
    print(f"检测到数值年份列（无需转换）: {num_year_cols}")
```

### 2b-2：同一主体同一年份多观测检测与聚合

```python
import pandas as pd
import numpy as np
import sys
sys.stdout.reconfigure(encoding='utf-8')

print("\n=== 同主体同年份多观测检测 ===")

# 识别个体ID候选列和时间列
numeric_cols = df.select_dtypes(include=[np.number]).columns.tolist()
time_cols = [c for c in numeric_cols
             if df[c].dropna().between(1900, 2100).mean() > 0.9
             and df[c].nunique() < 100]

id_candidates = [c for c in df.columns
                 if c not in time_cols
                 and df[c].nunique() > 5
                 and df[c].nunique() < len(df) * 0.9]

if time_cols and id_candidates:
    col_time = time_cols[0]
    col_id   = id_candidates[0]
    dup_check = df.groupby([col_id, col_time]).size()
    max_dup   = dup_check.max()
    dup_ratio = (dup_check > 1).mean()

    print(f"个体列={col_id}，时间列={col_time}")
    print(f"每个(个体,年份)组合最大观测数: {max_dup}")
    print(f"存在多观测的(个体,年份)组合比例: {dup_ratio:.1%}")

    if max_dup > 1:
        print(f"\n⚠ 存在同主体同年份多条观测，建议聚合！")
        # 对数值列自动按 sum / mean 聚合（供参考，不自动覆盖原数据）
        num_vars = df.select_dtypes(include=[np.number]).columns.tolist()
        agg_dict = {v: 'sum' for v in num_vars if v not in [col_id, col_time]}
        df_agg = df.groupby([col_id, col_time], as_index=False).agg(agg_dict)
        print(f"  聚合后行数: {len(df_agg)}（原始: {len(df)}）")
        print(f"  聚合方式: 数值列 sum（流量变量适用），如有存量变量请手动改为 mean）")
        print(f"  聚合结果存于 df_agg，请确认后手动替换 df = df_agg")
        # 输出聚合前后对比示例（取前5行）
        example_id = dup_check[dup_check > 1].index[0]
        print(f"\n  示例（{col_id}={example_id[0]}, {col_time}={example_id[1]}）：")
        print(df[(df[col_id]==example_id[0]) & (df[col_time]==example_id[1])].to_string())
    else:
        print("每个(个体,年份)组合仅有1条观测，无需聚合。")
else:
    print("未能自动识别个体ID列或时间列，跳过多观测检测。")
```

将清洗结果记录到数据档案的「数据质量注意事项」部分，格式：
- 日期转换：是/否，转换字段名
- 多观测聚合：是/否，最大重复数，建议聚合方式

---

## 步骤 3：识别关键变量类型

根据变量名和数据内容，分类识别：

**面板结构变量**（必须找到）：
- 个体ID变量（城市代码、企业ID、地区代码等）
- 时间变量（年份、季度等）

**候选被解释变量 Y**（结果变量）：
- 经济产出类：GDP、收入、就业、工资
- 创新类：专利、研发支出
- 金融类：股价、融资
- 其他核心结果指标

**候选核心解释变量 X**（处理变量/政策变量）：
- 政策虚拟变量（DID）
- 基础设施、制度、政策相关
- 连续处理变量

**候选控制变量 Z**：
- 经济规模（GDP、人口）
- 资本、劳动、技术
- 地区特征

---

## 步骤 3b：识别策略初判（基于AER_PATTERNS第一章决策树）

在完成变量类型识别后，运行以下 Python 代码，对数据结构做自动识别策略初判：

```python
import pandas as pd
import numpy as np
import sys
sys.stdout.reconfigure(encoding='utf-8')

# ── 假设 df 已加载，col_id / col_time 已由步骤3确认 ──

print("=" * 60)
print("【识别策略初判】基于 AER_PATTERNS 第一章决策树")
print("=" * 60)

# ── 检测1：是否存在 treated / treatment 虚拟变量 ──
treat_keywords = ['treat', 'treated', 'treatment', 'post', 'policy',
                  'did', 'dummy', 'reform', 'pilot', 'program']
found_treat_vars = [c for c in df.columns
                    if any(k in c.lower() for k in treat_keywords)]

if found_treat_vars:
    print(f"\n[DiD信号] 检测到疑似处理/政策虚拟变量: {found_treat_vars}")
    # 判断是否为0/1变量
    binary_vars = [c for c in found_treat_vars
                   if df[c].dropna().isin([0, 1]).all()]
    if binary_vars:
        print(f"  → 其中为0/1二值变量: {binary_vars}")
        print("  → 建议策略: DiD / TWFE（双重差分）")
    else:
        print("  → 含非二值处理变量，可能适合连续处理强度DiD")
else:
    print("\n[DiD信号] 未检测到明显的处理/政策虚拟变量")

# ── 检测2：时间变量年份均值跳变（疑似政策断点）──
# 需要已识别时间变量 col_time 和至少一个 Y 变量 col_y
# 此处用描述统计中均值最大/最小的数值列作为代理Y
numeric_cols = df.select_dtypes(include=[np.number]).columns.tolist()

# 识别时间变量（取值范围看起来像年份：1900-2100）
time_candidates = [c for c in numeric_cols
                   if df[c].dropna().between(1900, 2100).mean() > 0.9
                   and df[c].nunique() < 100]

if time_candidates:
    col_time_detected = time_candidates[0]
    years = sorted(df[col_time_detected].dropna().unique())
    print(f"\n[RD/断点信号] 检测到时间变量: {col_time_detected}，年份范围: {int(min(years))}~{int(max(years))}")

    if len(years) >= 4:
        # 对所有数值Y变量计算年均值，检测最大跳变点
        y_candidates = [c for c in numeric_cols if c != col_time_detected]
        jump_results = []
        for yc in y_candidates[:10]:   # 最多检测10个变量，避免输出过多
            try:
                yearly_mean = df.groupby(col_time_detected)[yc].mean().dropna()
                if len(yearly_mean) < 3:
                    continue
                diffs = yearly_mean.diff().abs()
                max_jump_year = diffs.idxmax()
                max_jump_val = diffs.max()
                mean_diff = diffs.mean()
                if mean_diff > 0 and max_jump_val > 2 * mean_diff:
                    jump_results.append((yc, int(max_jump_year), max_jump_val, mean_diff))
            except Exception:
                continue

        if jump_results:
            print("  → 检测到年份均值存在明显跳变（跳变幅度 > 2倍平均波动）：")
            for yc, yr, jv, mv in jump_results:
                print(f"     变量={yc}，疑似断点年份={yr}，跳变幅度={jv:.4f}（平均波动={mv:.4f}）")
            breakpoint_years = list(set([r[1] for r in jump_results]))
            print(f"  → 疑似政策断点年份: {breakpoint_years}")
            print("  → 建议策略: RD（断点回归）或 DiD（以断点年份为Post分界）")
        else:
            print("  → 未检测到显著均值跳变，暂无明显政策断点信号")
else:
    print("\n[RD/断点信号] 未检测到年份格式时间变量，跳过断点检测")

# ── 检测3：疑似工具变量（地理/历史/距离变量）──
iv_keywords = ['geo', 'dist', 'distance', 'elev', 'elevation', 'slope',
               'terrain', 'rainfall', 'rain', 'rugged', 'coast', 'river',
               'hist', 'history', 'historical', 'bartik', 'shift',
               'lat', 'lon', 'longitude', 'latitude', 'altitude',
               'port', 'road', 'railway', 'colonial', 'heritage']
found_iv_vars = [c for c in df.columns
                 if any(k in c.lower() for k in iv_keywords)]

if found_iv_vars:
    print(f"\n[IV信号] 检测到疑似工具变量候选（地理/历史/距离类变量）: {found_iv_vars}")
    print("  → 建议策略: IV/2SLS（需论证相关性 F>10 及排他性）")
else:
    print("\n[IV信号] 未检测到明显工具变量候选变量")

# ── 决策树汇总输出 ──
print("\n" + "=" * 60)
print("【识别策略决策树汇总】（基于 AER_PATTERNS 第一章）")
print("""
数据结构判断
├── 有随机化分配 → RCT框架
│   ├── 个体随机化 → OLS + HC稳健SE
│   ├── 聚类随机化（学校/村庄/区） → OLS + 聚类SE + Wild Cluster Bootstrap
│   └── 配对匹配随机化 → 控制配对FE + 聚类SE
│
├── 有政策/事件冲击 → 准实验框架
│   ├── 处理时间不同 + 面板 → DiD / 事件研究
│   │   ├── 两组两期 → 标准DiD
│   │   ├── 多期 → TWFE + 事件研究图
│   │   └── 多维变动 → 三重差分（Triple-DiD）
│   ├── 阈值/断点 → RD / Bunching
│   └── 地理/自然因素产生的变动 → 地形工具变量、Bartik IV
│
├── 截面数据 + 内生变量 → IV/2SLS
│   ├── 工具变量候选：地理特征、历史遗留、Shift-Share（Bartik）
│   └── 必须论证：相关性（F>10）+ 排他性（叙述+安慰剂）
│
└── 纯面板 + 无明显外生变动 → 谨慎，需额外识别手段
""")
print("=" * 60)
```

根据以上检测结果，在数据档案中填写"识别策略初步建议"：
- 若检测到处理虚拟变量 → 主推 DiD / TWFE
- 若检测到均值跳变年份 → 标注疑似政策断点，记录年份
- 若检测到地理/历史变量 → 标注 IV/2SLS 备选策略

---

## 步骤 3c：固定效应组合建议（基于AER_PATTERNS第三章）

根据步骤3识别的数据结构，运行以下代码并结合判断输出推荐的FE组合：

```python
import pandas as pd
import numpy as np
import sys
sys.stdout.reconfigure(encoding='utf-8')

# ── 假设 df 已加载，col_id / col_time / industry_col 已识别 ──

print("=" * 60)
print("【固定效应组合建议】基于 AER_PATTERNS 第三章指南")
print("=" * 60)

# 判断面板维度
numeric_cols = df.select_dtypes(include=[np.number]).columns.tolist()
time_candidates = [c for c in numeric_cols
                   if df[c].dropna().between(1900, 2100).mean() > 0.9
                   and df[c].nunique() < 100]
has_time = len(time_candidates) > 0

# 识别个体ID变量（唯一值数量多，非时间型）
id_candidates = [c for c in df.columns
                 if df[c].nunique() > 5 and c not in time_candidates
                 and df[c].nunique() < len(df) * 0.9]

# 识别行业变量
industry_keywords = ['ind', 'industry', 'sector', 'sic', 'naics', 'isic', 'nace']
industry_candidates = [c for c in df.columns
                       if any(k in c.lower() for k in industry_keywords)]

print(f"\n数据结构检测：")
print(f"  时间变量候选: {time_candidates if time_candidates else '未检测到'}")
print(f"  个体ID候选: {id_candidates[:5] if id_candidates else '未检测到'}")
print(f"  行业变量候选: {industry_candidates if industry_candidates else '未检测到'}")

print("\n【推荐FE组合】（参照AER_PATTERNS第三章标准）")
print("""
| 数据类型               | 推荐FE组合                                          | 说明                          |
|----------------------|---------------------------------------------------|-------------------------------|
| 个体面板（企业/城市）   | 个体FE + 年份FE                                    | 双向固定效应（TWFE）基准        |
| 个体×行业面板          | 个体FE + 行业×年FE                                 | 控制行业时间趋势                |
| 发明人/专利数据         | 个体FE + 企业FE + 城市×领域FE + 领域×年FE + 城市×年FE | 极精细，吸收多维混淆           |
| RCT + 聚类随机化       | 分配单元FE（配对/分层）                              | 必须控制随机化分层变量          |
| 跨国截面               | 国家/地区FE                                         | 吸收时不变国家效应              |
""")

# 根据检测结果给出具体建议
if has_time and id_candidates:
    col_time = time_candidates[0]
    col_id = id_candidates[0]
    if industry_candidates:
        col_ind = industry_candidates[0]
        print(f"  → 当前数据检测结果：含个体({col_id}) + 时间({col_time}) + 行业({col_ind})")
        print(f"  → 推荐FE: {col_id} FE + {col_ind}×{col_time} FE（控制行业时间趋势）")
        print(f"  → pyfixest 公式示例: feols('y ~ x | {col_id} + {col_ind}^{col_time}', ...)")
    else:
        print(f"  → 当前数据检测结果：含个体({col_id}) + 时间({col_time})")
        print(f"  → 推荐FE: {col_id} FE + {col_time} FE（双向固定效应 TWFE）")
        print(f"  → pyfixest 公式示例: feols('y ~ x | {col_id} + {col_time}', ...)")
elif has_time and not id_candidates:
    print("  → 仅检测到时间变量，无明确个体ID → 可能为截面数据")
    print("  → 推荐FE: 地区/行业FE（若有）")
else:
    print("  → 未检测到面板结构，建议人工确认ID变量和时间变量")

print("\n原则：FE从少到多逐列添加，展示系数稳健性（AER规范：至少4-6列递进规格）")
print("=" * 60)
```

---

## 步骤 3d：聚类标准误建议（基于AER_PATTERNS第四章）

根据数据结构自动检测推荐聚类层级，并判断是否需要 Wild Cluster Bootstrap：

```python
import pandas as pd
import numpy as np
import sys
sys.stdout.reconfigure(encoding='utf-8')

# ── 假设 df 已加载，cluster_col 由步骤3识别的处理单元层级 ──

print("=" * 60)
print("【聚类标准误建议】基于 AER_PATTERNS 第四章指南")
print("=" * 60)

print("""
【标准误聚类指南】（AER_PATTERNS 第四章）

| 场景                        | 聚类层级                     | 注意事项                              |
|-----------------------------|------------------------------|---------------------------------------|
| 政策在地区/州层面变动         | 地区/州                      |                                       |
| RCT个体随机化                | 无需聚类，用HC稳健SE           |                                       |
| RCT聚类随机化（村庄/学校）   | 随机化单元（村庄/学校）        | 聚类数<50时加 Wild Cluster Bootstrap   |
| 个体面板                     | 个体（个体序列相关）           |                                       |
| 地理相关数据                 | 地区 + Conley空间相关SE（可选）|                                       |

Wild Cluster Bootstrap（WCB）触发条件：
  - 聚类数 < 50（Baranov: 40个UC，Lowe: ~30个联赛）
  - AER标准：报告WCB置信区间作为补充
""")

# 检测潜在聚类变量及其唯一值数量
numeric_cols = df.select_dtypes(include=[np.number]).columns.tolist()
time_candidates = [c for c in numeric_cols
                   if df[c].dropna().between(1900, 2100).mean() > 0.9
                   and df[c].nunique() < 100]

# 排除时间变量和Y变量，找ID类变量
cluster_candidates = [c for c in df.columns
                      if c not in time_candidates
                      and df[c].nunique() >= 2
                      and df[c].nunique() <= 500]

print("\n【当前数据聚类单元检测】")
wcb_needed = False
recommended_cluster = None

for cc in cluster_candidates[:8]:
    n_clusters = df[cc].nunique()
    wcb_flag = " ★ 聚类数<50，需要 Wild Cluster Bootstrap！" if n_clusters < 50 else ""
    print(f"  变量={cc}，唯一值数量（潜在聚类数）={n_clusters}{wcb_flag}")
    if n_clusters < 50 and recommended_cluster is None:
        recommended_cluster = cc
        wcb_needed = True

# 输出推荐
print("\n【聚类SE推荐结论】")
if recommended_cluster:
    print(f"  → 若以 {recommended_cluster} 为聚类层级，聚类数={df[recommended_cluster].nunique()} < 50")
    print("  → 必须使用 Wild Cluster Bootstrap（WCB），不可仅报告常规聚类SE")
    print("  → pyfixest WCB 示例:")
    print("""     res = pf.feols('y ~ x | entity + year',
                data=df, vcov={'CRV1': 'cluster_var'})
     # 若聚类数<50，补充 bootstrap_type='11' 的WCB结果""")
else:
    # 找最合理的聚类变量（个体ID层面）
    id_candidates = [c for c in cluster_candidates if df[c].nunique() >= 50]
    if id_candidates:
        recommended_cluster = id_candidates[0]
        print(f"  → 推荐聚类变量: {recommended_cluster}（唯一值={df[recommended_cluster].nunique()}，≥50无需WCB）")
        print(f"  → pyfixest 示例: vcov={{'CRV1': '{recommended_cluster}'}}")
    else:
        print("  → 未能自动确定最优聚类层级，建议人工按照处理单元层级手动指定")

print("\n[WCB需要]: " + ("是" if wcb_needed else "否"))
print("=" * 60)
```

---

## 步骤 4：生成数据档案

将以上所有分析写入 `ECO_DATA_PROFILE.md`，格式如下：

```markdown
# 数据档案

## 数据集概览
- 文件列表：...
- 总观测数：...
- 时间跨度：...
- 覆盖范围：...

## 面板结构
- 个体ID变量：...
- 时间变量：...
- 面板类型：平衡/非平衡

## 候选变量
### 被解释变量（Y）
| 变量名 | 含义 | 类型 | 缺失率 |
|--------|------|------|--------|

### 核心解释变量（X）
| 变量名 | 含义 | 类型 | 缺失率 |
|--------|------|------|--------|

### 控制变量（Z）
| 变量名 | 含义 | 类型 | 缺失率 |
|--------|------|------|--------|

## 描述统计表
（完整描述统计）

## 数据质量注意事项
- 缺失值问题
- 异常值
- 需要处理的编码问题

## 识别策略初判

> 本节由步骤3b/3c/3d自动生成，供后续 eco-analysis 直接使用。

### 推荐识别策略
| 策略 | 推荐理由 |
|------|---------|
| DiD / TWFE | （若检测到处理虚拟变量，注明变量名） |
| IV / 2SLS  | （若检测到地理/历史类工具变量候选，注明变量名） |
| RD         | （若检测到年份均值跳变，注明疑似断点年份） |

**综合推荐策略：** （填写最终建议，如"主推TWFE，备选IV"）

**推荐理由：** （简述检测到的信号）

### 推荐固定效应组合
| 回归规格 | FE组合 | pyfixest公式示意 |
|---------|--------|----------------|
| 基准（列1-2） | 个体FE | `feols('y ~ x \| entity', ...)` |
| 标准TWFE（列3-4） | 个体FE + 年份FE | `feols('y ~ x \| entity + year', ...)` |
| 严格规格（列5-6） | 个体FE + 行业×年FE | `feols('y ~ x \| entity + ind^year', ...)` |

（根据步骤3c检测结果填写实际变量名）

### 推荐聚类层级
- **聚类变量：** （填写步骤3d推荐的聚类变量名）
- **聚类数量：** （填写唯一值数量）
- **Wild Cluster Bootstrap是否需要：** 是 / 否
  - 若是：聚类数 < 50，必须在常规聚类SE之外额外报告WCB置信区间

### 潜在政策断点年份
- **疑似断点年份：** （填写步骤3b检测到的跳变年份，或"未检测到"）
- **对应变量：** （填写发生跳变的变量名）
- **建议：** （如"可以 XXXX 年为 Post=1 分界线构造 DiD"）
```

完成后输出："数据探索完成，档案已保存至 ECO_DATA_PROFILE.md"
