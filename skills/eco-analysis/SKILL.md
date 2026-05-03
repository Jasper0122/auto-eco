---
name: eco-analysis
description: 基于AER论文套路的高质量计量实证分析。自动识别识别策略，执行描述统计、基准回归、内生性处理、稳健性检验、机制分析、异质性分析，生成AER规范的结果表格和事件研究图。
argument-hint: '"研究主题" "数据路径"'
allowed-tools: Read, Write, Bash, Glob, Edit
---

# Eco-Analysis: AER级实证分析技能（自包含版）

## 你的任务
读取 ECO_DATA_PROFILE.md 和 ECO_LIT.md，按照AER顶刊标准设计并执行完整实证分析。
本技能已内嵌所有AER规范标准，无需读取外部 AER_PATTERNS.md 文件。

## 分析循环控制（必须执行）

实证分析不得一次性跑完后直接写 `ECO_RESULTS.md`。必须采用“目标—执行—诊断—修订—归档”的循环逻辑，并在项目目录输出：

```text
ECO_ANALYSIS_TODO.md    分析模块任务、目标、输入、状态、修订轮次
ECO_ANALYSIS_QA.md      每个分析模块的质量检查、失败原因、回退动作
analysis.do             可复现主要实证结果的 Stata do-file
```

模块状态只能使用：

```text
pending -> running -> needs_revision -> passed -> blocked
```

执行规则：

1. 每个分析模块运行前，在 `ECO_ANALYSIS_TODO.md` 标记为 `running`，写清目标、输入变量、输出表图。
2. 模块运行后，立即更新 `ECO_ANALYSIS_QA.md`，检查结果是否达到门槛，而不是只检查代码是否无报错。
3. 未达标模块最多修订3轮；修订时只重跑失败模块和依赖它的下游模块，不覆盖已通过的表图。
4. 若失败原因来自上游变量定义、政策时间线或识别设计，停止本技能并在 `ECO_ANALYSIS_QA.md` 写明“需回退到 eco-data-explore / eco-background / eco-lit-review”。
5. 主结果不显著或方向不符合预期时，不得自动换Y、换X、换样本或数据挖掘；只能做预先合理的诊断和稳健性，并如实记录。
6. 只有全部必需模块 `passed`，才允许生成最终 `ECO_RESULTS.md`。

`ECO_ANALYSIS_TODO.md` 模板：

```markdown
# 实证分析任务清单

| 模块 | 目标 | 输出 | 通过条件 | 状态 | 修订轮次 |
|---|---|---|---|---|---:|
| 0 状态读取与识别设计 | 明确变量、样本和识别策略 | ECO_ANALYSIS_QA.md | ID/TIME/Y/X/controls完整 | pending | 0 |
| 1 数据清洗与样本诊断 | 得到可复现分析样本 | ECO_RESULTS.md样本段 | 样本量、缺失、处理/对照分布清楚 | pending | 0 |
| 2 描述统计与平衡性 | 展示变量分布和组间可比性 | table1/table1b | 变量中文名、N、均值、标准差、p值完整 | pending | 0 |
| 3 基准回归 | 得到核心因果估计 | baseline表 | 系数、SE、t/p、固定效应、聚类层级完整 | pending | 0 |
| 4 识别有效性/动态效应 | 检查平行趋势或识别假设 | event-study图/表 | 政策前趋势、置信区间、解释完整 | pending | 0 |
| 5 稳健性检验 | 检查结论稳定性 | robustness表 | 至少3项有理论含义的稳健性 | pending | 0 |
| 6 机制检验 | 检查理论渠道 | mechanism表 | 机制变量来自文献或数据档案 | pending | 0 |
| 7 异质性分析 | 检查效应差异 | heterogeneity表 | 分组依据清楚且非事后挑选 | pending | 0 |
| 8 Stata复现代码 | 生成可复现主结果的do-file | analysis.do | 能复现描述统计、基准、稳健性和主要机制/异质性 | pending | 0 |
| 9 结果归档与一致性 | 生成可写入论文的结果档案 | ECO_RESULTS.md | 表图齐全、数字一致、局限性写明 | pending | 0 |
```

最低通过标准：

- 所有主文表格必须保存在 `tables/`，且文件名稳定。
- 必须生成 `analysis.do`，用于在 Stata 中复现主要结果；若某些 Python 专属方法无法完全等价复现，必须在 do-file 注释和 `ECO_ANALYSIS_QA.md` 中说明差异。
- 回归表必须包含系数、标准误、t值或p值、样本量、固定效应、聚类层级。
- DiD研究必须有动态效应或平行趋势诊断；无法做时必须说明原因。
- 稳健性、机制、异质性如果因数据缺失无法完成，必须在 `ECO_ANALYSIS_QA.md` 标记 `blocked`，并在 `ECO_RESULTS.md` 写“未能完成及原因”，不得伪造表格。
- `ECO_RESULTS.md` 中报告的所有数字必须能在 `tables/` 或运行日志中找到来源。

## 参数
$ARGUMENTS：第一个参数为研究主题，第二个为数据路径

---

## 前置：安装依赖

```bash
pip install pyfixest linearmodels statsmodels pandas numpy scipy openpyxl matplotlib seaborn -q
```

---

## 步骤 0：读取状态文件，判断识别策略

读取 ECO_DATA_PROFILE.md，提取：
- 个体ID变量、时间变量
- 被解释变量Y（候选）
- 核心解释变量X
- 控制变量列表
- 数据文件路径
- 是否有政策虚拟变量（treated × post → DiD）
- 是否有工具变量候选

读取 ECO_LIT.md，提取：
- 文献推荐的识别策略
- 机制变量
- 异质性分组变量

---

### 识别策略决策树（内嵌 AER_PATTERNS 第一章）

按以下优先级顺序逐条判断，命中第一个匹配项即确定策略：

```
数据结构判断
├── 有随机化分配变量 → RCT框架
│   ├── 个体随机化 → OLS + HC稳健SE
│   ├── 聚类随机化（学校/村庄/区） → OLS + 聚类SE + Wild Cluster Bootstrap（聚类数<50时必须）
│   └── 配对匹配随机化 → 控制配对FE + 聚类SE
│
├── 有政策/事件冲击 → 准实验框架（优先DiD）
│   ├── 有 treated 虚拟变量 + 时间变量 → DiD / 事件研究
│   │   ├── 两组两期 → 标准DiD（Treat×Post）
│   │   ├── 多期处理时间不同 → TWFE + 事件研究图
│   │   └── 三维变动 → Triple-DiD
│   ├── 有阈值/断点 → RD / Bunching
│   └── 地理/自然因素产生变动 → 地形工具变量、Bartik IV
│
├── 截面数据 + 有工具变量候选 → IV/2SLS
│   ├── 工具变量候选：地理特征、历史遗留、Shift-Share（Bartik）
│   └── 必须论证：相关性（F>10）+ 排他性（叙述+安慰剂）
│
└── 纯面板 + 无明显外生变动 → TWFE + 稳健性（谨慎，需额外识别手段）
```

**确定识别策略后，记录到变量中供后续步骤使用：**
- `STRATEGY` = 'DiD' / 'IV' / 'RCT' / 'TWFE'
- `HAS_DID` = True/False
- `HAS_IV` = True/False

**同时从ECO_DATA_PROFILE.md和ECO_LIT.md提取以下变量列表：**
- `OUTCOME_VARS`：多个理论驱动的结果变量列表（Table 2多列的来源）
  - 从文献推荐的Y维度出发，同一概念的不同测量方式（如：总冲突、致命冲突、武装冲突、国家暴力...）
  - 通常3-6个，不超过8个
  - **不是盲目扫描，而是理论上预期均受事件影响的Y**
- `SPILLOVER_VAR`：溢出效应虚拟变量（如：邻近处理单元的对照单元）
  - 若数据有地理/网络结构，构建"未直接处理但毗邻处理单元"的虚拟变量
  - 若无空间结构可跳过溢出分析
- `ALT_ACCOUNTS`：替代解释变量列表（同期发生的其他冲击）
  - 每个替代解释对应一个可观测变量，用于在回归中控制或交互
  - 例：其他同期政策、外部价格冲击、政治事件虚拟变量
- `HIGHER_LEVEL_TREAT_VAR`：更高地理层级的处理变量（Table 2安慰剂列）
  - 若政策在县级，则构建市级平均处理指标；若政策在市级，则用省级
  - 若数据无空间层级结构，设为 None
  - **核心逻辑**：若县级政策真的是外生的，市级处理指标对县级结果应不显著
- `PLACEBO_VARS`：结构化安慰剂变量列表（Table 2安慰剂列）
  - 放入"不可能被政策影响"的不变量，如：海拔均值、多年平均降水、历史人口密度
  - 若这类变量显著，说明存在地理混淆，识别有问题
  - 留空列表则跳过此类安慰剂列

---

## 步骤 1：安装依赖 + 数据读取 + 清洗

```python
import pandas as pd
import numpy as np
import warnings
import sys
import os
warnings.filterwarnings('ignore')
sys.stdout.reconfigure(encoding='utf-8')
os.makedirs('tables', exist_ok=True)

# 自动识别文件格式
def load_data(path):
    if path.endswith('.dta'):
        return pd.read_stata(path)
    elif path.endswith('.xlsx') or path.endswith('.xls'):
        return pd.read_excel(path)
    elif path.endswith('.csv'):
        return pd.read_csv(path)
    else:  # 尝试目录下所有文件
        for f in os.listdir(path):
            if f.endswith(('.dta', '.xlsx', '.csv')):
                return load_data(os.path.join(path, f))

df = load_data(DATA_PATH)

# 基本清洗
df = df.dropna(subset=[Y_VAR, X_VAR])  # listwise deletion

# 对数变换（如有必要，正值变量）
for v in [Y_VAR, X_VAR]:
    if df[v].min() > 0:
        df[f'ln_{v}'] = np.log(df[v])

# 缩尾处理（1%）—— 备用，稳健性检验时启用
for v in [Y_VAR, X_VAR]:
    low, high = df[v].quantile([0.01, 0.99])
    df[f'{v}_w'] = df[v].clip(low, high)

print(f"样本：{len(df)}观测，{df[ENTITY_VAR].nunique()}个个体，{df[TIME_VAR].nunique()}期")
print(f"Y均值: {df[Y_VAR].mean():.3f}，SD: {df[Y_VAR].std():.3f}")
```

---

## 步骤 2：描述统计表（Table 1）

### AER规范（内嵌 AER_PATTERNS 第十章）

**Table 1 必须包含以下元素：**
- N（观测数）
- 均值（Mean）
- 标准差（SD）
- P25（第25百分位数）
- P75（第75百分位数）
- 最小值 / 最大值（可选）
- 如有处理/对照组：同时报告两组均值差及p值

**DiD情况下：必须输出基线平衡检验表（Table 1b）**
- 对照组均值 vs 处理组均值
- 差异及t检验p值
- 联合F检验（所有前定变量联合不显著，平行趋势前提）

```python
import pyfixest as pf
from scipy import stats

# ---- 全样本描述统计（AER标准：N、均值、SD、P25、P75）----
desc_vars = [Y_VAR, X_VAR] + CONTROL_VARS
desc = df[desc_vars].describe(percentiles=[.25, .75]).T[
    ['count', 'mean', 'std', '25%', '75%', 'min', 'max']
]
desc.columns = ['N', '均值', '标准差', 'P25', 'P75', '最小值', '最大值']
desc.to_csv('tables/table1_descriptive.csv', encoding='utf-8-sig')
print("Table 1 描述统计（N、均值、SD、P25、P75）：")
print(desc.round(4))

# ---- DiD：基线平衡检验（必做）----
if HAS_DID:
    baseline_df = df[df[TIME_VAR] == df[TIME_VAR].min()]  # 基线期数据
    t0_vals = baseline_df[baseline_df[TREAT_VAR] == 0][desc_vars]
    t1_vals = baseline_df[baseline_df[TREAT_VAR] == 1][desc_vars]

    t0_mean = t0_vals.mean()
    t1_mean = t1_vals.mean()
    diff = t1_mean - t0_mean

    pvals = []
    for v in desc_vars:
        try:
            pval = stats.ttest_ind(
                t0_vals[v].dropna(),
                t1_vals[v].dropna()
            ).pvalue
        except Exception:
            pval = np.nan
        pvals.append(pval)

    balance = pd.DataFrame({
        '对照组均值': t0_mean,
        '处理组均值': t1_mean,
        '差异': diff,
        'p值': pvals
    }, index=desc_vars)

    balance.to_csv('tables/table1b_balance.csv', encoding='utf-8-sig')
    print("\nTable 1b 基线平衡检验（DiD必做）：")
    print(balance.round(4))

    # 联合F检验：所有变量是否与处理状态无关
    joint_formula = f"{TREAT_VAR} ~ " + " + ".join(desc_vars)
    try:
        res_joint = pf.feols(joint_formula, data=baseline_df, vcov='HC1')
        print(f"\n联合平衡检验 F统计量 = {res_joint.f_statistic():.3f}（应不显著）")
    except Exception:
        print("联合F检验跳过（变量共线性或样本不足）")

print("Table 1 完成")
```

---

## 步骤 3：基准回归（Table 2）

### AER规范（内嵌 AER_PATTERNS 第三章固定效应指南 + 第四章SE指南）

**固定效应组合原则（至少4-6列递进）：**

| 数据类型 | 推荐FE组合 | 说明 |
|---------|-----------|------|
| 个体面板（企业/城市）| 个体FE + 年份FE | TWFE基准，主模型 |
| 个体×行业面板 | 个体FE + 行业×年FE | 控制行业时间趋势 |
| RCT + 聚类随机化 | 分配单元FE（配对/分层） | 必须控制随机化分层变量 |

**标准误聚类原则：**

| 场景 | SE类型 | 触发条件 |
|------|--------|---------|
| 无FE，截面或RCT个体随机化 | `HC1`（异方差稳健SE） | 无聚类结构时 |
| 政策在地区/个体层面变动，有面板结构 | `CRV1`（聚类稳健SE，聚类到个体/地区） | 有序列相关时 |
| 聚类数 < 50 | 在CRV1基础上加 **Wild Cluster Bootstrap（WCB）** | AER标准：聚类数<50时必须报告WCB置信区间 |
| 地理相关数据 | 地区聚类 + Conley空间相关SE（可选） | 存在空间溢出时 |

```python
import pyfixest as pf

controls_str = ' + '.join(CONTROL_VARS) if CONTROL_VARS else ''

models = []

# 列1：仅核心变量，无FE，HC1稳健SE
# 注释：无聚类结构时用HC1，展示最基础OLS
res1 = pf.feols(f'{Y_VAR} ~ {X_VAR}', data=df, vcov='HC1')
models.append(res1)

# 列2：加控制变量，无FE，HC1
# 注释：控制观测变量后的OLS，HC1处理异方差
if controls_str:
    res2 = pf.feols(f'{Y_VAR} ~ {X_VAR} + {controls_str}', data=df, vcov='HC1')
else:
    res2 = res1
models.append(res2)

# 列3：加个体FE，CRV1聚类到个体
# 注释：吸收个体时不变差异；CRV1处理个体内序列相关
res3 = pf.feols(
    f'{Y_VAR} ~ {X_VAR} + {controls_str} | {ENTITY_VAR}',
    data=df, vcov={'CRV1': ENTITY_VAR}
)
models.append(res3)

# 列4：双向FE（个体+时间）—— 主模型
# 注释：TWFE基准；CRV1聚类到个体（处理单元层级）
# 若聚类数 < 50，需补充WCB（见步骤3末尾）
res4 = pf.feols(
    f'{Y_VAR} ~ {X_VAR} + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
    data=df, vcov={'CRV1': ENTITY_VAR}
)
models.append(res4)

# 列5：DiD规格（如有treat×post）
# 注释：核心系数为DiD估计量β；聚类到处理单元层级（CRV1）
if HAS_DID:
    df['treat_post'] = df[TREAT_VAR] * df[POST_VAR]
    res5 = pf.feols(
        f'{Y_VAR} ~ treat_post + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
        data=df, vcov={'CRV1': ENTITY_VAR}
    )
    models.append(res5)

# 列6：对数Y（如适用）
# 注释：弹性解读，平减量纲差异
if f'ln_{Y_VAR}' in df.columns:
    res6 = pf.feols(
        f'ln_{Y_VAR} ~ {X_VAR} + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
        data=df, vcov={'CRV1': ENTITY_VAR}
    )
    models.append(res6)

# ---- 安慰剂列（嵌入 Table 2，审稿人一眼可判断识别是否干净）----
# 参照 JDE/AEJ 近年惯例：事件冲击类研究，安慰剂直接进 baseline table
# 安慰剂设计原则：
#   A. 更高地理层级处理安慰剂：县政策 → 用市级平均处理作为X；若市级未实施政策应不显著
#   B. 时间安慰剂：用政策实施前2期的伪处理日期，系数应不显著
#   C. 不变量安慰剂（PLACEBO_VARS）：海拔/气候/历史人口等对Y不应有效应

# 安慰剂A：更高地理层级处理变量
HIGHER_LEVEL_TREAT_VAR = locals().get('HIGHER_LEVEL_TREAT_VAR', None)
if HAS_DID and HIGHER_LEVEL_TREAT_VAR and HIGHER_LEVEL_TREAT_VAR in df.columns:
    try:
        res_plac_geo = pf.feols(
            f'{Y_VAR} ~ {HIGHER_LEVEL_TREAT_VAR} + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
            data=df, vcov={'CRV1': ENTITY_VAR}
        )
        models.append(res_plac_geo)
        pg_coef = res_plac_geo.coef().get(HIGHER_LEVEL_TREAT_VAR, float('nan'))
        pg_p    = res_plac_geo.pvalue().get(HIGHER_LEVEL_TREAT_VAR, float('nan'))
        print(f"\n安慰剂A（高层级处理 {HIGHER_LEVEL_TREAT_VAR}）：β={pg_coef:.4g}，p={pg_p:.3f}"
              f"  {'✓ 安慰剂通过' if pg_p > 0.1 else '⚠ 安慰剂显著，需检查地理混淆'}")
    except Exception as e:
        print(f"安慰剂A跳过：{e}")

# 安慰剂B：时间安慰剂（将政策日期提前2期，在全样本跑相同规格）
if HAS_DID:
    try:
        policy_year = int(df[df[TREAT_VAR] == 1][TIME_VAR].min())
        fake_policy_year = policy_year - 2
        df['fake_post'] = (df[TIME_VAR] >= fake_policy_year).astype(float)
        df['fake_did']  = df[TREAT_VAR] * df['fake_post']
        res_plac_time = pf.feols(
            f'{Y_VAR} ~ fake_did + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
            data=df, vcov={'CRV1': ENTITY_VAR}
        )
        models.append(res_plac_time)
        pt_coef = res_plac_time.coef().get('fake_did', float('nan'))
        pt_p    = res_plac_time.pvalue().get('fake_did', float('nan'))
        print(f"\n安慰剂B（时间安慰剂，伪处理年={fake_policy_year}）：β={pt_coef:.4g}，p={pt_p:.3f}"
              f"  {'✓ 安慰剂通过' if pt_p > 0.1 else '⚠ 安慰剂显著，前期趋势可疑'}")
    except Exception as e:
        print(f"安慰剂B跳过：{e}")

# 安慰剂C：不变量安慰剂（地理/气候变量，系数必须不显著）
PLACEBO_VARS = locals().get('PLACEBO_VARS', [])
for pv in PLACEBO_VARS:
    if pv in df.columns:
        try:
            res_plac_v = pf.feols(
                f'{Y_VAR} ~ {pv} + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
                data=df, vcov={'CRV1': ENTITY_VAR}
            )
            models.append(res_plac_v)
            pv_p = res_plac_v.pvalue().get(pv, float('nan'))
            print(f"\n安慰剂C（不变量 {pv}）：p={pv_p:.3f}"
                  f"  {'✓ 安慰剂通过' if pv_p > 0.1 else '⚠ 安慰剂显著，可能存在地理选择偏误'}")
        except Exception as e:
            print(f"安慰剂C ({pv}) 跳过：{e}")

# 输出比较表（含安慰剂列）
pf.etable(
    models,
    stars={'*': 0.10, '**': 0.05, '***': 0.01},
    file='tables/table2_baseline.txt'
)

# 提取主要结果（列4：双向FE主模型）
main_coef = res4.coef()[X_VAR]
main_se   = res4.se()[X_VAR]
main_pval = res4.pvalue()[X_VAR]
main_t    = main_coef / main_se
ctrl_mean = df[Y_VAR].mean()
effect_pct = main_coef / ctrl_mean * 100

# AER数字规范（第十五章）：4位有效数字 + t统计量 + 效应占均值%
print(f"\n主模型结果（TWFE，列4）：")
print(f"  β = {main_coef:.4g}（SE = {main_se:.4g}，t = {main_t:.3f}，p = {main_pval:.3f}）")
print(f"  对照组均值 = {ctrl_mean:.4g}")
print(f"  效应占对照组均值 = {effect_pct:.1f}%")

# ---- 聚类数检查：若 < 50，触发Wild Cluster Bootstrap ----
n_clusters = df[ENTITY_VAR].nunique()
if n_clusters < 50:
    print(f"\n警告：聚类数 = {n_clusters} < 50，需补充Wild Cluster Bootstrap！")
    print("AER标准：小样本聚类时CRV1可能过度拒绝，WCB提供更可靠推断。")
    # pyfixest WCB示例（bootstrap_type="11" 为AER推荐）：
    # res_wcb = pf.feols(f'{Y_VAR} ~ {X_VAR} | {ENTITY_VAR} + {TIME_VAR}',
    #                    data=df, vcov={'CRV1': ENTITY_VAR})
    # res_wcb.wildboottest(param=X_VAR, B=9999, bootstrap_type='11')
    print("请手动运行WCB并将置信区间补入Table 2注释行。")
```

### Table 2b：多结果变量综合表（顶刊核心格式）

**逻辑：固定主规格（TWFE + 控制变量），对所有理论驱动的 OUTCOME_VARS 逐列回归，放在一张表中。**

参照论文结构：一行处理变量，多列不同Y结果，直接展示事件影响的广度和分类差异。

```python
import pyfixest as pf
import pandas as pd
import numpy as np
import sys
sys.stdout.reconfigure(encoding='utf-8')

print("=== Table 2b：多结果变量综合表 ===")

# OUTCOME_VARS 从步骤0读取，由研究者根据理论预先指定
# 例：['conflict_total', 'conflict_deadly', 'conflict_battle',
#      'conflict_violent', 'state_violence', 'protest']
# 格式：理论上均预期受事件影响的Y，每个代表不同维度

outcome_models = []
outcome_labels = []
outcome_summary = []

controls_str = ' + '.join(CONTROL_VARS) if CONTROL_VARS else '1'

for y in OUTCOME_VARS:
    if y not in df.columns:
        print(f"跳过 {y}：数据中不存在"); continue

    sub_df = df.dropna(subset=[y, X_VAR])
    try:
        res = pf.feols(
            f'{y} ~ {X_VAR} + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
            data=sub_df, vcov={'CRV1': ENTITY_VAR}
        )
        coef = res.coef().get(X_VAR, np.nan)
        se   = res.se().get(X_VAR, np.nan)
        pval = res.pvalue().get(X_VAR, np.nan)
        ymean = sub_df[y].mean()
        effect_pct = coef / ymean * 100 if ymean != 0 else np.nan

        outcome_models.append(res)
        outcome_labels.append(y)
        outcome_summary.append({
            '结果变量': y,
            'β': round(coef, 4),
            'SE': round(se, 4),
            'p值': round(pval, 3),
            'Y均值': round(ymean, 4),
            '效应占均值%': round(effect_pct, 1),
            '显著': '***' if pval<0.01 else ('**' if pval<0.05 else ('*' if pval<0.1 else '')),
        })
        print(f"  {y}: β={coef:.4g}({se:.4g}), p={pval:.3f}, 效应={effect_pct:.1f}%均值")
    except Exception as e:
        print(f"  {y} 跳过: {e}")

if outcome_models:
    pf.etable(
        outcome_models,
        stars={'*': 0.10, '**': 0.05, '***': 0.01},
        file='tables/table2b_multi_outcomes.txt'
    )
    df_summary = pd.DataFrame(outcome_summary)
    df_summary.to_csv('tables/table2b_multi_outcomes.csv',
                      index=False, encoding='utf-8-sig')

    # 判断结果模式
    sig_ys = [r['结果变量'] for r in outcome_summary if r['p值'] < 0.1]
    insig_ys = [r['结果变量'] for r in outcome_summary if r['p值'] >= 0.1]
    print(f"\n显著影响的Y（p<0.1）：{sig_ys}")
    print(f"无显著影响的Y：{insig_ys}")
    if insig_ys:
        print("提示：无显著影响的Y有助于排除替代解释（如：安慰剂型Y不应显著）")

    print(f"\nTable 2b 已保存至 tables/table2b_multi_outcomes.txt")
```

---

## 步骤 4：识别策略——内生性处理（Table 3）

### 分支A：DiD + 事件研究（平行趋势检验）

#### 平行趋势检验升级规范（顶刊共识）

**错位处理（Staggered Adoption）判断：**
- 若数据中各处理单元的**首次处理年份不同**（多队列处理），TWFE 在 staggered 设计下存在"负权重"问题，估计量可能有偏
- **Callaway & Sant'Anna (2021)** 的 CS-DiD 是当前顶刊认可的稳健替代
- **操作原则**：先检测是否为 staggered；若是，CS-DiD 作为主报告，TWFE 作为对比

**依赖安装：**
```bash
pip install csdid pyfixest matplotlib -q
```

```python
import matplotlib
import matplotlib.pyplot as plt
import numpy as np
matplotlib.rcParams['font.family'] = ['SimHei', 'DejaVu Sans']

# ---- 步骤一：检测是否为 Staggered DiD ----
# 若处理单元有不同的政策年份（多队列），则为 staggered
if HAS_DID:
    # 需要 TREAT_YEAR_VAR（每个单元首次处理年份）；若不存在则从数据构建
    # 构建方法：对每个 ENTITY_VAR，取 TREAT_VAR==1 的最早 TIME_VAR
    first_treat = (
        df[df[TREAT_VAR] == 1]
        .groupby(ENTITY_VAR)[TIME_VAR]
        .min()
        .reset_index()
        .rename(columns={TIME_VAR: 'first_treat_year'})
    )
    df = df.merge(first_treat, on=ENTITY_VAR, how='left')
    df['first_treat_year'] = df['first_treat_year'].fillna(0).astype(int)  # 0 = 从不处理

    n_cohorts = df[df['first_treat_year'] > 0]['first_treat_year'].nunique()
    is_staggered = n_cohorts > 1
    print(f"\n识别策略诊断：处理队列数 = {n_cohorts}，"
          f"{'Staggered Adoption → 使用 CS-DiD 作为主估计' if is_staggered else '单一处理期 → 标准事件研究'}")

# ---- 步骤二A：Callaway & Sant'Anna (2021) CS-DiD（Staggered 时为主报告）----
if HAS_DID and is_staggered:
    print("\n=== CS-DiD 估计（Callaway & Sant'Anna 2021，错位处理稳健）===")
    try:
        from csdid import ATTgt
        att = ATTgt(
            yname=Y_VAR,
            idname=ENTITY_VAR,
            tname=TIME_VAR,
            gname='first_treat_year',
            data=df,
            control_group='notyettreated'  # 推荐：以"尚未处理"组为对照
        )
        att.fit()

        # 汇总估计：simple aggregate（所有队列×时期的加权平均 ATT）
        agg_simple = att.aggregate('simple')
        cs_coef = agg_simple.overall_att
        cs_se   = agg_simple.overall_att_se
        cs_t    = cs_coef / cs_se if cs_se > 0 else float('nan')
        print(f"\nCS-DiD 加总 ATT（Simple Aggregate）：")
        print(f"  β_CS = {cs_coef:.4g}（SE = {cs_se:.4g}，t = {cs_t:.3f}）")
        print(f"  效应占对照组均值 = {cs_coef/ctrl_mean*100:.1f}%")

        # 动态效应（Event Study aggregate）
        agg_dynamic = att.aggregate('dynamic')
        # 绘制 CS Event Study 图
        es_df = agg_dynamic.summary()
        fig, ax = plt.subplots(figsize=(9, 5))
        ax.fill_between(es_df['e'], es_df['att'] - 1.96*es_df['att_se'],
                        es_df['att'] + 1.96*es_df['att_se'],
                        alpha=0.15, color='steelblue', label='95% CI（CS-DiD）')
        ax.plot(es_df['e'], es_df['att'], 'o-', color='steelblue',
                linewidth=2, markersize=6, label='CS-DiD 点估计')
        ax.axhline(0, color='black', linewidth=0.8)
        ax.axvline(-0.5, color='red', linewidth=1.2, linestyle='--', alpha=0.7, label='政策实施')
        ax.set_xlabel('相对于政策实施的时间（年）', fontsize=11)
        ax.set_ylabel('平均处理效应（ATT）', fontsize=11)
        ax.set_title('事件研究图：CS-DiD（Callaway & Sant\'Anna 2021）', fontsize=12)
        ax.legend(fontsize=10)
        plt.tight_layout()
        plt.savefig('tables/figure1_event_study.pdf', dpi=300, bbox_inches='tight')
        plt.savefig('tables/figure1_event_study.png', dpi=300, bbox_inches='tight')
        print("CS-DiD 事件研究图已保存")

        # 平行趋势检验：pre-trend 期 ATT 应联合不显著
        pre_es = es_df[es_df['e'] < 0]
        from scipy import stats as scipy_stats
        if len(pre_es) > 0:
            pre_t_stats = (pre_es['att'] / pre_es['att_se']).dropna()
            print(f"\nCS pre-trend 超前期系数：")
            for _, row in pre_es.iterrows():
                sig = '*' if abs(row['att']/row['att_se']) > 1.645 else ''
                print(f"  k={row['e']:+.0f}: β={row['att']:.4g}（SE={row['att_se']:.4g}）{sig}")

        agg_simple.summary().to_csv('tables/table3_csdid.csv', index=False, encoding='utf-8-sig')
        print("\n主报告：以上 CS-DiD 估计（对 staggered adoption 稳健）")

    except ImportError:
        print("csdid 未安装，降级至 TWFE 事件研究。运行：pip install csdid")
        is_staggered = False  # fallback to TWFE
    except Exception as e:
        print(f"CS-DiD 跳过（{e}），降级至 TWFE 事件研究")
        is_staggered = False

# ---- 步骤二B：TWFE 事件研究（单一处理期 or 与 CS-DiD 对比）----
if HAS_DID:
    label_twfe = "TWFE（对比参考）" if (is_staggered if 'is_staggered' in dir() else False) else "TWFE 事件研究（主报告）"
    print(f"\n=== {label_twfe} ===")

    max_lead = 4
    max_lag  = 5

    # 若 time_to_treat 未存在则从 first_treat_year 构建
    if 'time_to_treat' not in df.columns:
        if 'first_treat_year' in df.columns:
            df['time_to_treat'] = np.where(
                df['first_treat_year'] > 0,
                df[TIME_VAR] - df['first_treat_year'],
                np.nan
            )
        else:
            print("警告：time_to_treat 未设置，请手动构建 df['time_to_treat'] = df[TIME_VAR] - 政策年份")

    for k in range(-max_lead, max_lag + 1):
        if k != -1:
            vname = f'D_t{k}' if k >= 0 else f'D_tm{abs(k)}'
            df[vname] = ((df['time_to_treat'] == k) & (df[TREAT_VAR] == 1)).astype(float)

    leads       = [f'D_tm{abs(k)}' for k in range(-max_lead, -1)]
    lags        = [f'D_t{k}'      for k in range(0, max_lag + 1)]
    all_dummies = leads + lags
    ctrl_str    = controls_str if controls_str else '1'

    es_formula = (
        f"{Y_VAR} ~ {' + '.join(all_dummies)} + {ctrl_str} "
        f"| {ENTITY_VAR} + {TIME_VAR}"
    )
    res_es = pf.feols(es_formula, data=df, vcov={'CRV1': ENTITY_VAR})

    all_periods = list(range(-max_lead, max_lag + 1))
    all_coefs, all_ses = [], []
    for k in all_periods:
        if k == -1:
            all_coefs.append(0.0); all_ses.append(0.0)
        else:
            vname = f'D_t{k}' if k >= 0 else f'D_tm{abs(k)}'
            all_coefs.append(res_es.coef().get(vname, 0.0))
            all_ses.append(res_es.se().get(vname, 0.0))

    upper = [c + 1.96*s for c, s in zip(all_coefs, all_ses)]
    lower = [c - 1.96*s for c, s in zip(all_coefs, all_ses)]

    if not (is_staggered if 'is_staggered' in dir() else False):
        # 仅在非 staggered 时输出 TWFE 为主图
        fig, ax = plt.subplots(figsize=(9, 5))
        ax.fill_between(all_periods, lower, upper, alpha=0.15, color='steelblue', label='95% CI')
        ax.plot(all_periods, all_coefs, 'o-', color='steelblue',
                linewidth=2, markersize=6, label='点估计')
        ax.axhline(0, color='black', linewidth=0.8)
        ax.axvline(-0.5, color='red', linewidth=1.2, linestyle='--', alpha=0.7, label='政策实施')
        ax.set_xlabel('相对于政策实施的时间（年）', fontsize=11)
        ax.set_ylabel('处理效应估计（相对于t=-1期）', fontsize=11)
        ax.set_title('事件研究图：平行趋势检验（TWFE）', fontsize=12)
        ax.set_xticks(all_periods)
        ax.legend(fontsize=10)
        plt.tight_layout()
        plt.savefig('tables/figure1_event_study.pdf', dpi=300, bbox_inches='tight')
        plt.savefig('tables/figure1_event_study.png', dpi=300, bbox_inches='tight')
        print("TWFE 事件研究图已保存")

    print("\n平行趋势联合检验（超前期系数联合不显著 → 平行趋势成立）：")
    try:
        wald_res = res_es.wald_test(leads)
        print(wald_res)
        print("解读：若联合p值 > 0.10，平行趋势假设成立。")
    except Exception as e:
        print(f"Wald检验报错：{e}")

    pf.etable([res_es], stars={'*': 0.10, '**': 0.05, '***': 0.01},
              file='tables/table3_event_study.txt')
    if is_staggered if 'is_staggered' in dir() else False:
        print("提示：Staggered 设计下，TWFE 事件研究仅供对比，主要结论以 CS-DiD 为准")
```

---

### 分支B：IV/2SLS（若有工具变量）

#### AER规范（内嵌 AER_PATTERNS 第二章2.2 IV标准规格）

**标准IV方程：**
```
第一阶段：D_it = π·Z_it + φ'W_it + μ_i + λ_t + ν_it
第二阶段：Y_it = α·D̂_it + β'W_it + μ_i + λ_t + ε_it
```

**弱工具变量检验标准（三级）：**

| 检验标准 | 临界值 | 适用场景 |
|---------|--------|---------|
| Stock-Yogo F > 10 | F > 10（经验值） | 同方差，单IV单内生变量，基准判断 |
| Kleibergen-Paap rk Wald F > 10 | F > 10 | 聚类/异方差SE（推荐汇报） |
| Montiel Olea-Pflueger F > 104.7 | F > 104.7 | 最严格的稳健弱IV检验，AER近年趋势 |

**排他性约束论证框架（必须在正文论证）：**
1. 叙述逻辑：IV为何只通过D影响Y，不存在直接路径
2. 安慰剂检验：对不应受影响的Y'回归，应不显著
3. 平衡性检验：IV与前定特征不相关
4. 控制所有可能的直接路径变量

```python
# ---- 第一阶段回归 ----
# 注释：CRV1聚类到个体；汇报F统计量判断工具变量相关性
res_fs = pf.feols(
    f'{X_VAR} ~ {IV_VAR} + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
    data=df, vcov={'CRV1': ENTITY_VAR}
)
f_stat = res_fs.f_statistic()
print(f"第一阶段 F 统计量 = {f_stat:.2f}")
print(f"  F > 10（Stock-Yogo经验值）：{'满足' if f_stat > 10 else '不满足，工具变量可能弱'}")
print(f"  F > 104.7（Montiel Olea-Pflueger最严格标准）：{'满足' if f_stat > 104.7 else '未达最严格标准，需讨论'}")

# ---- 2SLS主回归 ----
# 注释：pyfixest语法：y ~ 1 | FE | 内生变量 ~ 工具变量
res_iv = pf.feols(
    f'{Y_VAR} ~ 1 | {ENTITY_VAR} + {TIME_VAR} | {X_VAR} ~ {IV_VAR}',
    data=df, vcov={'CRV1': ENTITY_VAR}
)

# 同时输出OLS（对照）+ 第一阶段 + 2SLS
pf.etable(
    [res4, res_fs, res_iv],
    stars={'*': 0.10, '**': 0.05, '***': 0.01},
    file='tables/table3_iv.txt'
)

iv_coef = res_iv.coef()[X_VAR]
iv_se   = res_iv.se()[X_VAR]
print(f"\n2SLS结果：β_IV = {iv_coef:.4g}（SE = {iv_se:.4g}）")
print(f"OLS vs IV系数变化：{main_coef:.4g} → {iv_coef:.4g}，"
      f"{'内生性导致OLS低估' if iv_coef > main_coef else '内生性导致OLS高估'}")
```

---

## 步骤 5：稳健性检验（Table 4）

### AER规范（内嵌 AER_PATTERNS 第五章完整稳健性清单）

**通用5项（所有策略必做）：**
1. 替换Y变量（不同测量方式）
2. 替换X变量（核心解释变量不同操作化）
3. 加强/放松FE（增减固定效应层级）
4. 缩尾处理（Winsorize 1%）
5. 替换样本范围（剔除某子群）

**DiD专项（有DiD时必加）：**
- 安慰剂检验：用政策前年份数据（应无效应）
- 替换控制组定义
- 动态效应检验

**IV专项（有IV时必加）：**
- 多IV时：Hansen J过度识别检验
- 安慰剂IV：对不应受影响Y'回归

```python
robust_models  = []
robust_labels  = []

# ---- 通用1：缩尾（Winsorize 1%）----
df_w = df.copy()
for v in [Y_VAR, X_VAR]:
    p1, p99 = df[v].quantile([0.01, 0.99])
    df_w[v] = df[v].clip(p1, p99)
res_r1 = pf.feols(
    f'{Y_VAR} ~ {X_VAR} + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
    data=df_w, vcov={'CRV1': ENTITY_VAR}
)
robust_models.append(res_r1); robust_labels.append('Winsorize 1%')

# ---- 通用2：替换Y（对数化）----
if f'ln_{Y_VAR}' in df.columns:
    res_r2 = pf.feols(
        f'ln_{Y_VAR} ~ {X_VAR} + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
        data=df, vcov={'CRV1': ENTITY_VAR}
    )
    robust_models.append(res_r2); robust_labels.append('替换Y：ln(Y)')

# ---- 通用3：放松FE（只加个体FE，去掉时间FE）----
res_r3 = pf.feols(
    f'{Y_VAR} ~ {X_VAR} + {controls_str} | {ENTITY_VAR}',
    data=df, vcov={'CRV1': ENTITY_VAR}
)
robust_models.append(res_r3); robust_labels.append('仅个体FE（放松FE）')

# ---- 通用4：无控制变量（加强FE，去掉控制变量）----
res_r4 = pf.feols(
    f'{Y_VAR} ~ {X_VAR} | {ENTITY_VAR} + {TIME_VAR}',
    data=df, vcov={'CRV1': ENTITY_VAR}
)
robust_models.append(res_r4); robust_labels.append('无控制变量')

# ---- 通用5：剔除极端个体（替换样本，排除X前后5%）----
p5, p95 = df[X_VAR].quantile([0.05, 0.95])
df_trim = df[(df[X_VAR] >= p5) & (df[X_VAR] <= p95)]
res_r5 = pf.feols(
    f'{Y_VAR} ~ {X_VAR} + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
    data=df_trim, vcov={'CRV1': ENTITY_VAR}
)
robust_models.append(res_r5); robust_labels.append('剔除极端X（5%-95%）')

# ---- DiD专项：安慰剂检验（用政策实施前数据，应无效应）----
if HAS_DID:
    pre_period_df = df[df[TIME_VAR] < df[df[TREAT_VAR]==1][TIME_VAR].min()]
    if len(pre_period_df) > 50:
        # 随机分配伪处理期，检验系数应不显著
        np.random.seed(42)
        pre_period_df = pre_period_df.copy()
        mid_time = pre_period_df[TIME_VAR].median()
        pre_period_df['fake_post'] = (pre_period_df[TIME_VAR] > mid_time).astype(float)
        pre_period_df['fake_did'] = pre_period_df[TREAT_VAR] * pre_period_df['fake_post']
        try:
            res_placebo = pf.feols(
                f'{Y_VAR} ~ fake_did + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
                data=pre_period_df, vcov={'CRV1': ENTITY_VAR}
            )
            robust_models.append(res_placebo); robust_labels.append('DiD安慰剂（伪处理期）')
        except Exception as e:
            print(f"DiD安慰剂检验跳过：{e}")

# ---- IV专项：Hansen J过度识别检验（多IV时）----
if HAS_IV and IV_LIST and len(IV_LIST) > 1:
    print("\nIV专项：Hansen J过度识别检验")
    iv_str = ' + '.join(IV_LIST)
    try:
        res_iv_multi = pf.feols(
            f'{Y_VAR} ~ 1 | {ENTITY_VAR} + {TIME_VAR} | {X_VAR} ~ {iv_str}',
            data=df, vcov={'CRV1': ENTITY_VAR}
        )
        # Hansen J检验需要 linearmodels 或手动计算
        print("Hansen J检验：使用linearmodels.iv.IV2SLS获取overid统计量")
        from linearmodels.iv import IV2SLS
        iv_lm = IV2SLS.from_formula(
            f'{Y_VAR} ~ 1 + {controls_str} + [{X_VAR} ~ {iv_str}]',
            data=df
        ).fit(cov_type='robust')
        print(iv_lm.wooldridge_overid)
    except Exception as e:
        print(f"Hansen J跳过：{e}")

# ---- 输出稳健性汇总表 ----
pf.etable(
    robust_models,
    stars={'*': 0.10, '**': 0.05, '***': 0.01},
    file='tables/table4_robustness.txt'
)
print(f"\n稳健性检验完成，共 {len(robust_models)} 项：{robust_labels}")
```

---

### 补充：事件驱动宏观结果扫描（Table 4b）

**逻辑：识别策略来自外生事件/政策冲击（X 已确定），扫描宏观数据库中所有候选结果变量 Y，找出哪些 Y 被这个事件显著影响。**

```
固定外生事件 X（政策冲击、改革、自然实验）
        ↓
遍历宏观数据库中所有候选 Y 变量
        ↓
对每个 Y 跑相同规格的基准回归
        ↓
FDR 校正多重检验 → 输出所有结果 + 显著 Y 列表
```

> **使用前提：X 的外生性已在步骤3（识别策略）中论证。本步骤回答的是"这个事件影响了哪些宏观变量"，而非调整规格让某个假设显著。**

```python
import pandas as pd
import numpy as np
import pyfixest as pf
from statsmodels.stats.multitest import multipletests
import sys
sys.stdout.reconfigure(encoding='utf-8')

print("=== 事件驱动宏观结果扫描 ===")
print(f"固定事件变量 X = {X_VAR}，扫描所有候选结果变量 Y\n")

# ---- 参数设置 ----
# 候选 Y 变量：从数据中自动识别所有数值列，排除 X、ID、时间、控制变量
exclude_vars = set([X_VAR, ENTITY_VAR, TIME_VAR] + CONTROL_VARS)
if HAS_DID:
    exclude_vars.update([TREAT_VAR, POST_VAR, 'treat_post'])

candidate_ys = [
    c for c in df.select_dtypes(include=[np.number]).columns
    if c not in exclude_vars
    and not c.startswith('ln_')      # 排除已生成的对数变换列
    and not c.endswith('_w')         # 排除缩尾列
    and df[c].notna().sum() > len(df) * 0.5   # 至少50%非缺失
]

print(f"候选结果变量 Y：共 {len(candidate_ys)} 个")
print(f"  {candidate_ys}\n")

controls_str = ' + '.join(CONTROL_VARS) if CONTROL_VARS else '1'
scan_results = []

# ---- 对每个候选 Y 跑相同规格的基准回归 ----
for y in candidate_ys:
    try:
        formula = (
            f'{y} ~ {X_VAR} + {controls_str} '
            f'| {ENTITY_VAR} + {TIME_VAR}'
        )
        res = pf.feols(formula, data=df.dropna(subset=[y, X_VAR]),
                       vcov={'CRV1': ENTITY_VAR})
        coef = res.coef().get(X_VAR, np.nan)
        se   = res.se().get(X_VAR, np.nan)
        pval = res.pvalue().get(X_VAR, np.nan)
        nobs = int(res.nobs)
        scan_results.append({
            '结果变量Y': y,
            'β': round(coef, 4),
            'SE': round(se, 4),
            't值': round(coef / se, 3) if se and se > 0 else np.nan,
            'p值_原始': round(pval, 4),
            'N': nobs,
        })
    except Exception as e:
        scan_results.append({
            '结果变量Y': y, 'β': np.nan, 'SE': np.nan,
            't值': np.nan, 'p值_原始': np.nan, 'N': np.nan,
        })

df_scan = pd.DataFrame(scan_results)

# ---- FDR 多重检验校正（Benjamini-Hochberg）----
# 原因：扫描多个 Y 时，期望有 N×0.05 个变量碰巧显著；
# BH-FDR 校正控制"错误发现率"，比 Bonferroni 更不保守，AER 推荐。
valid_mask = df_scan['p值_原始'].notna()
if valid_mask.sum() > 0:
    reject, pvals_fdr, _, _ = multipletests(
        df_scan.loc[valid_mask, 'p值_原始'],
        alpha=0.1, method='fdr_bh'
    )
    df_scan.loc[valid_mask, 'p值_FDR校正'] = pvals_fdr.round(4)
    df_scan.loc[valid_mask, 'FDR显著(q<0.1)'] = reject

df_scan['显著星号'] = df_scan['p值_原始'].apply(
    lambda p: '***' if p < 0.01 else ('**' if p < 0.05 else ('*' if p < 0.1 else ''))
    if pd.notna(p) else ''
)

# ---- 输出汇总 ----
df_scan_sorted = df_scan.sort_values('p值_原始')
print(f"扫描完成，共 {len(df_scan)} 个结果变量\n")

# 原始 p<0.1 显著的变量
sig_raw = df_scan[df_scan['p值_原始'] < 0.1]['结果变量Y'].tolist()
print(f"原始显著（p<0.1）的 Y 变量（{len(sig_raw)} 个）：{sig_raw}")

# FDR 校正后仍显著的变量（更可靠）
if 'FDR显著(q<0.1)' in df_scan.columns:
    sig_fdr = df_scan[df_scan['FDR显著(q<0.1)'] == True]['结果变量Y'].tolist()
    print(f"FDR校正后显著（q<0.1）的 Y 变量（{len(sig_fdr)} 个）：{sig_fdr}")
    print(f"\n解读：FDR校正后显著的变量是真实受事件影响的概率更高，"
          f"建议以此为基础展开机制分析。")

print(f"\n期望虚假显著数量（如无真实效应）：{len(df_scan) * 0.05:.1f} 个")

# ---- 完整结果表 ----
print(f"\n完整扫描结果（按原始p值排序）：")
print(df_scan_sorted[['结果变量Y','β','SE','t值','p值_原始','p值_FDR校正','显著星号','N']
                      ].to_string(index=False))

df_scan_sorted.to_csv('tables/table4b_outcome_scan.csv',
                      index=False, encoding='utf-8-sig')
print("\n完整结果已保存至 tables/table4b_outcome_scan.csv")

# ---- AER 写作提示 ----
if 'FDR显著(q<0.1)' in df_scan.columns:
    print(f"""
[论文写作提示]
"我们对宏观数据库中 {len(df_scan)} 个候选结果变量逐一进行回归分析，
采用 Benjamini-Hochberg FDR 校正控制多重检验问题。
经FDR校正后，以下变量在 q<0.1 水平显著受到事件影响：{sig_fdr}。
完整扫描结果见 Online Appendix Table A1。"
""")
```

---

### 替代解释排除（Table 4c）

**逻辑：明确列举所有合理的竞争性解释，用数据逐一否定，证明效应确实来自本研究的事件X，而非同期其他因素。**

参照论文 Table 6 结构：每个 Panel 对应一个替代解释，在主回归中同时控制，若主系数不变则排除该解释。

```python
import pyfixest as pf
import numpy as np
import sys
sys.stdout.reconfigure(encoding='utf-8')

# ALT_ACCOUNTS 从步骤0读取，格式：
# [
#   {'label': '替代解释1名称', 'var': '对应变量名', 'interact_with_post': True/False},
#   {'label': '替代解释2名称', 'var': '对应变量名', 'interact_with_post': False},
# ]
# interact_with_post=True：用 var×Post 交互项控制（同期政策/事件）
# interact_with_post=False：直接加入变量控制

if not ALT_ACCOUNTS:
    print("未设置 ALT_ACCOUNTS，跳过替代解释排除。")
    print("提示：建议从文献中整理3-5个主要竞争性解释，对应可观测变量。")
else:
    print("=== Table 4c：替代解释排除 ===")
    controls_str = ' + '.join(CONTROL_VARS) if CONTROL_VARS else '1'
    alt_results = []

    for alt in ALT_ACCOUNTS:
        alt_var   = alt['var']
        alt_label = alt['label']
        use_interact = alt.get('interact_with_post', False)

        if alt_var not in df.columns:
            print(f"跳过 {alt_label}（{alt_var} 不在数据中）"); continue

        try:
            if use_interact and POST_VAR in df.columns:
                # 交互项形式：alt_var × Post（控制该变量在政策前后的差异效应）
                interact_name = f'alt_{alt_var}_post'
                df[interact_name] = df[alt_var] * df[POST_VAR]
                formula = (
                    f'{Y_VAR} ~ {X_VAR} + {alt_var} + {interact_name} + {controls_str} '
                    f'| {ENTITY_VAR} + {TIME_VAR}'
                )
            else:
                # 直接控制
                formula = (
                    f'{Y_VAR} ~ {X_VAR} + {alt_var} + {controls_str} '
                    f'| {ENTITY_VAR} + {TIME_VAR}'
                )

            res_alt = pf.feols(formula, data=df, vcov={'CRV1': ENTITY_VAR})
            main_coef_alt = res_alt.coef().get(X_VAR, np.nan)
            main_se_alt   = res_alt.se().get(X_VAR, np.nan)
            main_p_alt    = res_alt.pvalue().get(X_VAR, np.nan)

            alt_coef = res_alt.coef().get(alt_var, np.nan)
            alt_p    = res_alt.pvalue().get(alt_var, np.nan)

            alt_results.append({
                'Panel': alt_label,
                '主系数β（控制替代解释后）': round(main_coef_alt, 4),
                '主系数SE': round(main_se_alt, 4),
                '主系数p值': round(main_p_alt, 3),
                '替代解释变量系数': round(alt_coef, 4),
                '替代解释变量p值': round(alt_p, 3),
                '主系数是否稳健': '是' if main_p_alt < 0.1 else '否（请检查）',
            })

            print(f"\nPanel：{alt_label}")
            print(f"  控制 {alt_var} 后，主系数 β = {main_coef_alt:.4g}（p={main_p_alt:.3f}）"
                  f"  → {'主系数稳健，排除该替代解释' if main_p_alt < 0.1 else '主系数不显著，需讨论'}")
            print(f"  替代解释变量本身：β = {alt_coef:.4g}（p={alt_p:.3f}）")

        except Exception as e:
            print(f"  {alt_label} 跳过: {e}")

    if alt_results:
        import pandas as pd
        df_alt = pd.DataFrame(alt_results)
        df_alt.to_csv('tables/table4c_alt_accounts.csv',
                      index=False, encoding='utf-8-sig')
        print(f"\nTable 4c 替代解释排除表已保存至 tables/table4c_alt_accounts.csv")
        print("\n[论文写作提示]")
        print("在稳健性部分按Panel格式呈现：")
        print("  Panel A：[替代解释1] — 控制后主系数β=XX，仍显著，排除")
        print("  Panel B：[替代解释2] — 控制后主系数β=XX，仍显著，排除")
```

---

## 步骤 5.5：溢出效应分析（Table 4d）

**位置说明**：溢出效应是加分项，不是识别核心。阅读逻辑上应在 baseline 站稳、识别通过、稳健性完成之后再讲。放在稳健性之后，审稿人已认可基本识别，此时溢出才是有意义的拓展检验。

**逻辑：处理单元之外，毗邻/网络关联单元是否也受到影响？**
- 溢出方向与直接效应一致 → 扩散效应（政策效应具有整体性）
- 溢出方向与直接效应相反 → 替代/位移效应（效应从处理区转移至邻区，对照组不干净）
- 溢出不显著 → 可排除效应转移的替代解释，强化识别

```python
import pyfixest as pf
import numpy as np
import sys
sys.stdout.reconfigure(encoding='utf-8')

# SPILLOVER_VAR：在步骤0中定义，标识"未直接处理但毗邻/关联处理单元"的虚拟变量
# 例：邻近矿区但本身无矿许可证的乡镇 = 1；若无空间结构设为 None

SPILLOVER_VAR = locals().get('SPILLOVER_VAR', None)

if SPILLOVER_VAR is None:
    print("未设置 SPILLOVER_VAR，跳过溢出效应分析。")
    print("提示：若数据有空间/网络结构，建议构建毗邻单元虚拟变量再运行本步骤。")
else:
    print("=== Table 4d：溢出效应分析 ===")
    spillover_models = []
    controls_str_spill = ' + '.join(CONTROL_VARS) if CONTROL_VARS else '1'

    for y in ([Y_VAR] + (OUTCOME_VARS[:4] if 'OUTCOME_VARS' in dir() else [])):
        if y not in df.columns: continue
        try:
            res_spill = pf.feols(
                f'{y} ~ {X_VAR} + {SPILLOVER_VAR} + {controls_str_spill} '
                f'| {ENTITY_VAR} + {TIME_VAR}',
                data=df, vcov={'CRV1': ENTITY_VAR}
            )
            direct_coef    = res_spill.coef().get(X_VAR, np.nan)
            spillover_coef = res_spill.coef().get(SPILLOVER_VAR, np.nan)
            spillover_p    = res_spill.pvalue().get(SPILLOVER_VAR, np.nan)
            spillover_models.append(res_spill)

            print(f"\n{y}:")
            print(f"  直接效应（X_VAR）: β = {direct_coef:.4g}")
            print(f"  溢出效应（{SPILLOVER_VAR}）: β = {spillover_coef:.4g}（p={spillover_p:.3f}）")
            if not np.isnan(spillover_p):
                if spillover_p < 0.1:
                    same_dir = (direct_coef * spillover_coef > 0)
                    print(f"  → 溢出显著，{'扩散效应' if same_dir else '替代/位移效应（需讨论对照组纯净性）'}")
                else:
                    print(f"  → 溢出不显著，可排除效应转移，对照组干净")
        except Exception as e:
            print(f"  {y} 跳过: {e}")

    if spillover_models:
        pf.etable(
            spillover_models,
            stars={'*': 0.10, '**': 0.05, '***': 0.01},
            file='tables/table4d_spillovers.txt'
        )
        print("\nTable 4d 溢出效应表已保存至 tables/table4d_spillovers.txt")
```

---

## 步骤 6：机制分析（Table 5）

### AER规范（内嵌 AER_PATTERNS 第六章四种机制方法）

**本步骤实现方式1（渠道变量法）+ 方式2（异质性调节法）：**

**方式1：渠道变量法（三步回归）**
```
步骤①：Y_it = α + β·X + FE + ε        （主回归，建立基准β）
步骤②：M_it = α + γ·X + FE + ε        （X对中间变量M的效应）
步骤③：Y_it = α + β'·X + δ·M + FE + ε （加入M后，若β'<β，M是传导渠道）
```
- β' < β 说明结果**与M作为渠道的假设一致**（不等同于严格因果分解）
- 传导比例 = (β - β') / β × 100%
- **写作规范（保守表达）**：说"结果与该渠道一致"或"提供了支持性证据"；不说"主要机制""必要机制"；传导比例须加免责：**"以上比例基于OLS分解，不等同于M的严格因果贡献"**

**方式2：异质性调节法（交互项）**
```
Y_it = α + β·X + τ·(X × Mech_i) + FE + ε
```
- τ的符号和显著性检验机制预测
- Mech_i为机制代理变量（如：文化强度、国家能力、教育水平）

```python
mech_models = []
mech_labels = []

for mech_var in MECHANISM_VARS:
    if mech_var not in df.columns:
        print(f"跳过机制变量 {mech_var}：数据中不存在"); continue

    # ---- 方式1：渠道变量法（三步）----

    # 步骤①：主回归（基准β，已在步骤3完成，这里复用 main_coef）

    # 步骤②：X → M（X对中间变量的效应）
    res_m_step2 = pf.feols(
        f'{mech_var} ~ {X_VAR} + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
        data=df, vcov={'CRV1': ENTITY_VAR}
    )
    gamma = res_m_step2.coef().get(X_VAR, np.nan)
    gamma_p = res_m_step2.pvalue().get(X_VAR, np.nan)
    mech_models.append(res_m_step2)
    mech_labels.append(f'步骤②：X→{mech_var}')

    # 步骤③：X + M → Y（加入M后X系数应下降）
    res_m_step3 = pf.feols(
        f'{Y_VAR} ~ {X_VAR} + {mech_var} + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
        data=df, vcov={'CRV1': ENTITY_VAR}
    )
    beta_prime = res_m_step3.coef().get(X_VAR, np.nan)
    mech_models.append(res_m_step3)
    mech_labels.append(f'步骤③：X+{mech_var}→Y')

    # 计算传导比例（保守解读）
    if not np.isnan(main_coef) and main_coef != 0 and not np.isnan(beta_prime):
        mediation_pct = (main_coef - beta_prime) / main_coef * 100
        print(f"\n机制渠道：{mech_var}")
        print(f"  步骤②：X对M的效应 γ = {gamma:.4g}（p = {gamma_p:.3f}）")
        print(f"  步骤③：加入M后，X系数从 β={main_coef:.4g} 降至 β'={beta_prime:.4g}（下降 {mediation_pct:.1f}%）")
        print(f"  → 结果与 [{mech_var}] 渠道假设一致（提供支持性证据）")
        print(f"  ⚠ 注：{mediation_pct:.1f}% 为OLS描述性分解，不等同于 {mech_var} 的严格因果贡献，写作时须加免责说明")
        if mediation_pct < 0:
            print("  注意：系数上升（抑制效应），可能存在多重共线性或复杂路径，需单独讨论。")

    # ---- 方式2：异质性调节法（交互项）----
    # 构造交互项：X × Mech_i
    interact_name = f'{X_VAR}_x_{mech_var}'
    df[interact_name] = df[X_VAR] * df[mech_var]

    res_interact = pf.feols(
        f'{Y_VAR} ~ {X_VAR} + {mech_var} + {interact_name} + {controls_str} '
        f'| {ENTITY_VAR} + {TIME_VAR}',
        data=df, vcov={'CRV1': ENTITY_VAR}
    )
    tau = res_interact.coef().get(interact_name, np.nan)
    tau_p = res_interact.pvalue().get(interact_name, np.nan)
    mech_models.append(res_interact)
    mech_labels.append(f'方式2：X×{mech_var}交互')

    print(f"  方式2交互项：τ(X×{mech_var}) = {tau:.4g}（p = {tau_p:.3f}）"
          f"  → {'结果与机制预测方向一致' if tau_p < 0.1 else '交互项不显著，机制证据不足'}")

if mech_models:
    pf.etable(
        mech_models,
        stars={'*': 0.10, '**': 0.05, '***': 0.01},
        file='tables/table5_mechanism.txt'
    )
    print("\n机制分析完成（渠道变量法 + 交互项调节法）")
```

---

## 步骤 7：异质性分析（Table 6）

### AER规范（内嵌 AER_PATTERNS 第七章框架）

**核心原则：理论驱动，而非机械遍历**

| 维度类型 | 常见分组 | 理论依据 |
|---------|---------|---------|
| 个体特征 | 性别、种族、年龄、教育 | 差异化边际效用 |
| 处理强度 | 高/低剂量、完全/部分处理 | 剂量-反应关系 |
| 地理/制度 | 东中西部、高低行政能力、城乡 | 互补性/替代性 |
| 时间 | 前/后期效应、队列差异 | 动态效应 |
| 理论调节变量 | 由机制预测哪组效应更强 | 机制检验 |

**报告格式（顶刊Panel标准）：**
- 行 = 处理变量 × 子组（每个异质性维度占一个 Panel）
- 列 = 不同结果变量 Y（复用 OUTCOME_VARS，最多5列）
- 每个 Panel 末尾报告组间差异的 p 值（差异显著性）

**参照论文 Table 4 格式：Panel A（Y1）、Panel B（Y2）...× 子组列（高/低/是/否）**

```python
import pyfixest as pf
import numpy as np
import pandas as pd
import sys
sys.stdout.reconfigure(encoding='utf-8')

print("=== Table 6：异质性分析（Panel格式）===")
controls_str = ' + '.join(CONTROL_VARS) if CONTROL_VARS else '1'

# 每个异质性变量构建一个 Panel
for het_var in HETEROGENEITY_VARS:
    if het_var not in df.columns:
        print(f"跳过异质性变量 {het_var}：不在数据中"); continue

    print(f"\n{'='*60}")
    print(f"Panel：{het_var}（理论预测：哪组效应更强？）")

    # 判断变量类型：0/1虚拟变量 or 连续变量（取中位数分组）
    unique_vals = df[het_var].dropna().unique()
    if set(unique_vals).issubset({0, 1, 0.0, 1.0}):
        groups = [(f'{het_var}=0', df[het_var] == 0),
                  (f'{het_var}=1', df[het_var] == 1)]
    else:
        median_val = df[het_var].median()
        groups = [(f'{het_var}_低（≤中位数）', df[het_var] <= median_val),
                  (f'{het_var}_高（>中位数）', df[het_var] > median_val)]

    panel_rows = []

    # 对每个 Y 结果变量跑分组回归（Panel的列）
    for y in ([Y_VAR] + OUTCOME_VARS[:4]):
        if y not in df.columns: continue

        row = {'结果变量Y': y}
        coefs = []

        for grp_label, grp_mask in groups:
            sub_df = df[grp_mask].dropna(subset=[y, X_VAR])
            if len(sub_df) < 30:
                row[grp_label] = 'N<30'
                coefs.append(np.nan)
                continue
            try:
                res_g = pf.feols(
                    f'{y} ~ {X_VAR} + {controls_str} | {ENTITY_VAR} + {TIME_VAR}',
                    data=sub_df, vcov={'CRV1': ENTITY_VAR}
                )
                c  = res_g.coef().get(X_VAR, np.nan)
                se = res_g.se().get(X_VAR, np.nan)
                p  = res_g.pvalue().get(X_VAR, np.nan)
                star = '***' if p<0.01 else ('**' if p<0.05 else ('*' if p<0.1 else ''))
                row[grp_label] = f'{c:.4g}{star}\n({se:.4g})'
                coefs.append(c)
            except:
                row[grp_label] = 'error'
                coefs.append(np.nan)

        # 组间差异p值（全样本交互项规格）
        try:
            high_dummy    = f'_het_high_{het_var}'
            interact_name = f'_het_interact_{het_var}'
            df[high_dummy]    = groups[1][1].astype(float)
            df[interact_name] = df[X_VAR] * df[high_dummy]
            res_int = pf.feols(
                f'{y} ~ {X_VAR} + {high_dummy} + {interact_name} + {controls_str} '
                f'| {ENTITY_VAR} + {TIME_VAR}',
                data=df.dropna(subset=[y, X_VAR]),
                vcov={'CRV1': ENTITY_VAR}
            )
            diff_p = res_int.pvalue().get(interact_name, np.nan)
            row['差异p值'] = round(diff_p, 3) if pd.notna(diff_p) else 'N/A'
        except:
            row['差异p值'] = 'N/A'

        panel_rows.append(row)

    # 输出当前 Panel
    df_panel = pd.DataFrame(panel_rows)
    print(df_panel.to_string(index=False))

    # 存储
    df_panel.to_csv(
        f'tables/table6_het_{het_var}.csv',
        index=False, encoding='utf-8-sig'
    )

print("\n异质性分析完成（Panel × 多结果变量格式，含组间差异p值）")
print("已保存至 tables/table6_het_[变量名].csv")
print("\n[论文写作提示]")
print("每个Panel对应一个异质性维度，列为不同Y结果变量。")
print("Panel末行的'差异p值'用于判断组间差异是否统计显著。")
print("仅报告理论上有明确方向预测的Panel，避免机械遍历。")
```

---

## 步骤 8：生成ECO_RESULTS.md（结果档案）

### AER数字规范（内嵌 AER_PATTERNS 第十五章）

**ECO_RESULTS.md 必须包含以下数字元素：**
- β（4位有效数字）
- SE（标准误）
- t统计量
- 效应占对照组均值的百分比（β ÷ 对照组均值 × 100%）
- Back-of-Envelope换算（将系数换算为更直观的经济量级）

**量级参考标准（AER惯例）：**
- 效应 < 5% 均值：经济意义较小，需讨论
- 效应 5-20% 均值：经济意义中等，AER常见
- 效应 > 20% 均值：经济意义较大，需谨慎

```python
# ---- 自动生成 ECO_RESULTS.md ----

# 汇总关键数字（AER第十五章规范：4位有效数字）
main_t    = main_coef / main_se
effect_pct = main_coef / ctrl_mean * 100

# Back-of-Envelope：换算为直观量级
# 例：效应 × 样本个体数 = 总量影响；效应 × 工资率 = 货币换算
boe_example = f"{main_coef:.4g} × [N个体] = 总计影响 [换算单位]（请根据具体变量填写）"

results_md = f"""# ECO_RESULTS.md —— 实证结果档案

## 研究主题
{TOPIC}

## 识别策略
{STRATEGY} — [外生变动来源简述，请填写]

## 样本描述
- 最终样本：{len(df)} 个观测，{df[ENTITY_VAR].nunique()} 个个体，{df[TIME_VAR].nunique()} 期
- Y变量：{Y_VAR}（均值 = {df[Y_VAR].mean():.4g}，SD = {df[Y_VAR].std():.4g}）
- 核心X变量：{X_VAR}

---

## 主要结论

### 基准回归（Table 2，双向FE主模型）
- **核心系数：β = {main_coef:.4g}（SE = {main_se:.4g}，t = {main_t:.3f}，p = {main_pval:.3f}）**
- 对照组均值：{ctrl_mean:.4g}
- 效应量：**{effect_pct:.1f}%**（相对于对照组均值）
- 经济量级判断：{'< 5%，经济意义较小' if abs(effect_pct) < 5 else ('5-20%，经济意义中等' if abs(effect_pct) <= 20 else '> 20%，经济意义较大')}
- Back-of-Envelope：{boe_example}
- 解读：{X_VAR} 增加1单位，{Y_VAR} {'增加' if main_coef > 0 else '减少'} {abs(main_coef):.4g}（{abs(effect_pct):.1f}% 对照组均值）

### 内生性处理（Table 3）
- 识别策略：{STRATEGY}
- [DiD：事件研究图显示，处理前超前期系数联合不显著，平行趋势假设成立。请填写联合检验p值。]
- [IV：第一阶段 F = [填写]，满足相关性条件；排他性论证：[填写]。]
- 控制内生性后，效应 [增大/减小/不变，请填写]

### 稳健性（Table 4）
- 共执行 {len(robust_models)} 项稳健性检验
- 核心系数范围：[请填写最小值～最大值]
- 结论：[稳健/有一定变化，请填写]

### 机制分析（Table 5）
"""

for mech_var in MECHANISM_VARS:
    if mech_var in df.columns:
        results_md += f"- 渠道变量 {mech_var}：加入M后β下降约[填写]%，结果与该渠道假设一致（支持性证据；注：此比例为OLS描述性分解，非严格因果估计）\n"

results_md += f"""
### 异质性分析（Table 6）
"""
for het_var in HETEROGENEITY_VARS:
    if het_var in df.columns:
        results_md += f"- {het_var} 高组效应 vs 低组效应：[填写具体数值和差异显著性]\n"

results_md += f"""
---

## 关键系数汇总（AER第十五章规范：4位有效数字 + t统计量 + 效应%）

| 模型 | β（4位有效数字） | SE | t统计量 | p值 | 效应/均值% |
|------|----------------|-----|--------|-----|-----------|
| 主模型（TWFE，双向FE） | {main_coef:.4g} | {main_se:.4g} | {main_t:.3f} | {main_pval:.3f} | {effect_pct:.1f}% |
| 稳健性（均值） | [填写] | [填写] | [填写] | [填写] | [填写] |
| 机制渠道1 | [填写] | [填写] | [填写] | [填写] | — |
| 异质性-高组 | [填写] | [填写] | [填写] | [填写] | [填写] |
| 异质性-低组 | [填写] | [填写] | [填写] | [填写] | [填写] |

---

## 表格文件清单

| 文件 | 内容 |
|------|------|
| tables/table1_descriptive.csv | 描述统计（N、均值、SD、P25、P75） |
| tables/table1b_balance.csv | 基线平衡检验（DiD适用） |
| tables/table2_baseline.txt | 基准回归（6列递进规格） |
| tables/table3_event_study.txt | 事件研究回归（DiD适用） |
| tables/table3_iv.txt | IV回归：OLS、第一阶段、2SLS（IV适用） |
| tables/table4_robustness.txt | 稳健性检验 |
| tables/table5_mechanism.txt | 机制分析（渠道变量法 + 交互项） |
| tables/table6_heterogeneity.txt | 异质性分析（分组回归 + 交互项） |
| tables/figure1_event_study.pdf | 事件研究图（DiD适用） |
| tables/figure1_event_study.png | 事件研究图（PNG备份） |

---

*由 eco-analysis 技能自动生成 | 日期：{pd.Timestamp.now().strftime('%Y-%m-%d')} | 规范来源：AER 2020-2021论文套路库*
"""

with open('ECO_RESULTS.md', 'w', encoding='utf-8') as f:
    f.write(results_md)

print("ECO_RESULTS.md 已生成")
print(f"\n实证分析完成！")
print(f"生成 {len(robust_models)+4} 张回归表 + 1张事件研究图。")
print(f"主要结论：{X_VAR} 对 {Y_VAR} 的效应 β = {main_coef:.4g}"
      f"（SE = {main_se:.4g}，p = {main_pval:.3f}），"
      f"占对照组均值 {effect_pct:.1f}%。")
print("结果已保存至 ECO_RESULTS.md 和 tables/ 目录。")
```

---

## 步骤 9：生成 Stata 复现代码（analysis.do）

无论主要分析是在 Python、R 还是 Stata 中完成，最终都必须输出 `analysis.do`。该 do-file 的目标是复现主要实证表格，而不是只作为占位文件。

`analysis.do` 必须包含：

1. 文件头：项目名称、生成日期、数据路径、软件版本建议、运行说明。
2. 环境设置：`clear all`、`set more off`、工作目录、日志文件。
3. 依赖安装提示：`reghdfe`、`estout`、`csdid`、`event_plot`、`winsor2` 等按需 `cap which` 检查；不得静默假设用户已安装。
4. 数据读取：根据原始数据格式写 `import delimited`、`import excel` 或 `use`；如果原始格式非 Stata，说明转换方式。
5. 变量定义：Y、X、处理变量、时间变量、个体ID、控制变量、机制变量、异质性变量。
6. 样本清洗：缺失处理、缩尾、对数变换、样本限制，必须与主分析一致。
7. 描述统计和平衡性检验，对应 `table1_descriptive` 和 `table1b_balance`。
8. 基准回归：固定效应、聚类层级和控制变量必须与 `ECO_RESULTS.md` 一致。
9. 动态效应或平行趋势：DiD 研究必须给出事件时间构造和估计命令；如 Python 使用的 CS-DiD 与 Stata 命令不完全一致，在注释中说明。
10. 稳健性、机制和异质性：至少覆盖主文使用的核心表格。
11. 输出：使用 `esttab/estout` 或 `putexcel/export delimited` 导出到 `tables/`。
12. 交付包同步：由 pipeline 调用时，必须复制到 `final_package/code/analysis.do`；若有 `analysis.log`，也复制到 `final_package/code/analysis.log`。

推荐 do-file 骨架：

```stata
****************************************************
* analysis.do
* Purpose: Reproduce main empirical results
* Generated by eco-analysis
****************************************************

clear all
set more off
version 17

global project_dir "[PROJECT_DIR]"
cd "$project_dir"
capture log close
log using "analysis.log", replace text

* ---- Dependencies ----
cap which reghdfe
if _rc ssc install reghdfe, replace
cap which esttab
if _rc ssc install estout, replace
cap which winsor2
if _rc ssc install winsor2, replace

* ---- Data ----
* Replace this block according to the actual input format.
* CSV:    import delimited "[DATA_PATH]", clear encoding(UTF-8)
* Excel:  import excel "[DATA_PATH]", firstrow clear
* Stata:  use "[DATA_PATH]", clear

* ---- Variable globals ----
global y     "[Y_VAR]"
global x     "[X_VAR]"
global id    "[ENTITY_VAR]"
global time  "[TIME_VAR]"
global ctrls "[CONTROL_VARS]"

* ---- Sample construction ----
drop if missing($y, $x, $id, $time)
xtset $id $time

* ---- Table 1: Descriptive statistics ----
estpost summarize $y $x $ctrls
esttab using "tables/table1_descriptive_stata.rtf", replace cells("count mean sd p25 p75 min max")

* ---- Baseline regression ----
eststo clear
reghdfe $y $x $ctrls, absorb($id $time) vce(cluster $id)
eststo m1
esttab m1 using "tables/table_baseline_stata.rtf", replace se star(* 0.10 ** 0.05 *** 0.01)

* ---- Robustness / mechanism / heterogeneity ----
* Add project-specific models here; keep fixed effects and clustering consistent.

log close
****************************************************
```

质检要求：

- `analysis.do` 中不得保留未替换的 `[Y_VAR]`、`[X_VAR]`、`[DATA_PATH]` 等占位符；如果确实无法确定，必须在 `ECO_ANALYSIS_QA.md` 标记为 `needs_revision`。
- 若 Stata 没有完全等价命令复现 Python 估计器，`analysis.do` 必须提供最接近的可复现版本，并在注释中写明差异。
- 若项目中存在 `final_package/`，必须同步维护 `final_package/code/analysis.do`，并确保它和项目根目录的 `analysis.do` 内容一致。
- `ECO_RESULTS.md` 的“表格文件清单”必须列出 `analysis.do` 和 `analysis.log`（若已运行）。

---

## 最终分析质检（生成 ECO_RESULTS.md 前必须执行）

在写出最终 `ECO_RESULTS.md` 前，必须完成以下检查并写入 `ECO_ANALYSIS_QA.md`：

```markdown
# 实证分析质量检查

| 模块 | 检查项 | 结果 | 失败时回退 |
|---|---|---|---|
| 状态读取 | ID/TIME/Y/X/controls 是否完整 | pass/fail | 回到数据探索 |
| 样本诊断 | 样本量、时间跨度、处理组/对照组是否足够 | pass/fail | 回到数据探索或切口关卡 |
| 描述统计 | table1 是否含N、均值、标准差、分位数 | pass/fail | 重跑描述统计 |
| 平衡性 | DiD是否输出table1b或说明无法做 | pass/fail | 重跑平衡性/回到数据定义 |
| 基准回归 | 系数、SE、t/p、FE、聚类层级是否完整 | pass/fail | 重跑基准模型 |
| 动态效应 | 是否检查平行趋势/事件研究 | pass/fail | 重跑事件研究 |
| 稳健性 | 是否至少3项且有理论含义 | pass/fail | 补充稳健性 |
| 机制 | 机制变量是否来自文献/数据 | pass/fail | 回到文献或机制模型 |
| 异质性 | 分组是否事前定义且可解释 | pass/fail | 回到文献或分组定义 |
| Stata复现 | analysis.do 是否存在且无未替换占位符 | pass/fail | 重新生成 do-file |
| 数字一致性 | ECO_RESULTS与tables数字是否一致 | pass/fail | 修正结果档案 |
```

通过条件：

- 不允许存在 `fail` 的核心模块：状态读取、样本诊断、基准回归、数字一致性。
- DiD/政策评估类研究不允许跳过动态效应；确实无法做时必须在 `blocked` 中说明数据原因。
- 稳健性、机制、异质性如果无法完成，必须写明“数据不支持/变量缺失/理论不适用”，不得生成空表或虚构结果。
- 最终输出必须包括 `ECO_ANALYSIS_TODO.md`、`ECO_ANALYSIS_QA.md`、`ECO_RESULTS.md`、`analysis.do` 和 `tables/`。

---

## 附录：AER规范速查表（本技能内嵌标准汇总）

### 固定效应（第三章）
| 数据类型 | 推荐FE | 代码示例 |
|---------|--------|---------|
| 个体面板 | 个体FE + 年份FE | `\| entity + year` |
| 个体×行业面板 | 个体FE + 行业×年FE | `\| entity + industry_year` |
| RCT聚类随机化 | 分配单元FE | `\| strata` |

### 标准误（第四章）
| 场景 | SE类型 | pyfixest代码 |
|------|--------|------------|
| 截面/RCT个体随机化 | HC1 | `vcov='HC1'` |
| 面板/地区政策 | CRV1（聚类到个体/地区） | `vcov={'CRV1': 'entity'}` |
| 聚类数 < 50 | CRV1 + Wild Cluster Bootstrap | 见步骤3注释 |

### 弱工具变量（第二章2.2）
| 标准 | 临界值 | 严格程度 |
|------|--------|--------|
| Stock-Yogo经验值 | F > 10 | 基础 |
| Kleibergen-Paap | F > 10 | 推荐（聚类SE下） |
| Montiel Olea-Pflueger | F > 104.7 | 最严格（AER近年趋势） |

### 机制分析（第六章）
| 方式 | 核心逻辑 | 必须输出 |
|------|---------|---------|
| 渠道变量法 | X→M→Y三步回归 | "通过M传导了X%的总效应" |
| 异质性调节法 | X×Mech交互项 | 交互项τ的符号和显著性 |

### AER数字规范（第十五章）
- β：4位有效数字
- 必须报告：SE、t统计量、效应占对照组均值%
- 必须做Back-of-Envelope换算
- 效应量判断：< 5% 偏小 / 5-20% 中等 / > 20% 较大
