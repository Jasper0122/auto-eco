---
name: eco-idea
description: 读取数据，循环测试变量关系，自动发现统计显著且经济意义有趣的研究切入点，推荐研究问题并评估可行性。
argument-hint: '"数据路径" "研究背景（可选）"'
allowed-tools: Read, Write, Bash, WebSearch, WebFetch, Glob, Grep
---

# Eco-Idea: 研究问题发现与验证技能

## 你的任务
给定数据路径，自动循环探测变量关系，发现统计显著且有经济意义的研究切入点，输出3-5个可行研究问题并推荐最优方向。

## 参数
- $ARGUMENTS 第一个参数：数据路径（必填）
- $ARGUMENTS 第二个参数：研究背景说明（可选，例如"中国城市面板 2000-2020"）

---

## 步骤 1：AER发表潜力评估标准（内嵌）

以下标准直接内嵌，无需读取外部文件。评估每个候选研究问题时按此打分：

**识别策略可行性（0-5分）**
- 5分：有明确政策冲击可做DiD，外生性强，平行趋势可验证
- 4分：有工具变量候选（地理/历史/Bartik），排他性可论证
- 3分：面板TWFE，加时间趋势控制，有限识别
- 1-2分：截面OLS或仅有相关性，内生性无法处理

**切口具体性（0-5分）—— 顶刊发表的核心门槛**

> 顶刊不喜欢宽泛的"X影响Y"，喜欢"**某个具体事件**在**特定时间/地点**对**特定单元**产生了什么影响"。切口越小，识别越干净，越容易过审。

| 得分 | 标准 | 示例 |
|------|------|------|
| 5分 | 有具体命名的政策/事件，有明确年份，处理单元是微观个体 | "2016年缅甸矿业暂停令 → 乡镇级冲突" |
| 4分 | 有可识别的政策类别，有年份范围，处理单元是城市/县 | "2015-2017年某省宽带补贴政策 → 企业创新" |
| 3分 | 有政策背景但冲击边界模糊，或处理单元是省级 | "2010年代某类金融改革 → 经济增长" |
| 2分 | 宏观趋势变量，无明确冲击，国家/省级面板 | "金融发展水平 → GDP增长" |
| 1分 | 两个宏观总量变量的相关性 | "贸易开放度 → 经济总量" |

**切口太宽的警报信号（直接降至1-2分）：**
- X 是"水平/程度/指数"而非"事件/冲击/改革"
- 处理单元是国家或省级（N<50）
- 没有明确的政策实施年份
- 文献已有5篇以上同类宏观研究

**切口合适的信号（可得4-5分）：**
- X 有具体的政策文件/名称/编号
- 处理单元是企业/个人/乡镇/县
- 冲击有明确起始年份（甚至月份）
- 有自然对照组（未受影响的类似单元）

**新颖性判断（0-5分）**
- 因果识别新颖：现有文献多为相关性，本研究提供因果证据（+2）
- 情境新颖：现有证据来自西方国家，本研究针对中国/发展中国家（+1）
- 机制新颖：现有文献只有总效应，未检验具体传导机制（+1）
- 异质性新颖：现有研究忽略某类分组差异（+1）

**经济意义规范**
- 效应 < 5% 对照组均值：经济意义较小，需讨论
- 效应 5–20% 对照组均值：中等，AER常见范围
- 效应 > 20% 对照组均值：较大，需谨慎说明

**不推荐的X→Y关系（过度研究，直接排除）**
- GDP规模 → 人均GDP（同义反复）
- 贸易开放度 → 经济增长（文献已饱和）
- 金融发展 → 经济增长（文献已饱和）
- 人口规模 → GDP总量（规模效应，无政策含义）

**推荐的有趣X类型**
- 具体政策冲击：某项改革/补贴/禁令/许可证制度变化
- 自然灾害/外部价格冲击/企业倒闭事件
- 有空间/网络溢出效应特征的微观冲击
- 有明确实施年份和处理/对照组的政策

---

## 步骤 2：数据加载与变量清单

用Python（Bash工具）执行：

```python
import pandas as pd
import numpy as np

DATA_PATH = "$ARGUMENTS的第一个参数"

# 尝试多种编码
for enc in ['utf-8-sig', 'utf-8', 'gbk', 'gb18030']:
    try:
        df = pd.read_csv(DATA_PATH, encoding=enc)
        print(f"Loaded with {enc}: {df.shape}")
        break
    except:
        continue

# 打印列名
print("\n=== 所有列名 ===")
for i, c in enumerate(df.columns):
    print(f"{i:3d}. {c}")

# 找ID列和时间列
id_cols = [c for c in df.columns if any(k in c.lower() for k in ['city','id','code','区','市'])]
time_cols = [c for c in df.columns if any(k in c.lower() for k in ['year','年','time'])]
print(f"\nID候选: {id_cols}")
print(f"时间候选: {time_cols}")

# 数值列统计
num_cols = df.select_dtypes(include=[np.number]).columns.tolist()
print(f"\n数值列数量: {len(num_cols)}")
print("\n=== 数值列缺失率 ===")
missing = df[num_cols].isnull().mean().sort_values(ascending=False)
print(missing[missing < 0.8].to_string())

# 对数变换列（ln_开头）
ln_cols = [c for c in df.columns if c.startswith('ln_')]
print(f"\n已有对数列: {ln_cols}")

# 基本统计
if ln_cols:
    print("\n=== 对数列统计 ===")
    print(df[ln_cols].describe().round(3).to_string())
```

记录：
- 数据维度（N, T, 城市/地区数量）
- 所有数值变量名单
- 缺失率超过50%的变量（后续跳过）

---

## 步骤 3：循环探测变量关系（核心步骤）

**目标**：用Panel TWFE跑所有有意义的X→Y组合，找出：
1. 系数显著（p<0.05）
2. 系数方向符合经济逻辑
3. 样本量足够（>500观测）

```python
import pandas as pd
import numpy as np
import pyfixest as pf
import warnings
warnings.filterwarnings('ignore')

# 重新加载数据（使用上步确认的编码）
df = pd.read_csv(DATA_PATH, encoding='utf-8-sig')

# 确认ID和时间列（根据步骤2输出手动填入）
id_col = "cityid"   # 替换为实际列名
time_col = "year"   # 替换为实际列名

# 确保面板变量正确
df[id_col] = df[id_col].astype(str)
df[time_col] = pd.to_numeric(df[time_col], errors='coerce')
df = df.dropna(subset=[id_col, time_col])

# 候选变量（ln_开头且缺失率<50%）
ln_cols = [c for c in df.columns if c.startswith('ln_') and df[c].isnull().mean() < 0.5]
print(f"候选变量: {ln_cols}")

# 循环测试所有X→Y组合
results = []
total = len(ln_cols) * (len(ln_cols) - 1)
done = 0

for y_var in ln_cols:
    for x_var in ln_cols:
        if x_var == y_var:
            continue

        # 准备数据：去掉缺失值
        cols_needed = [id_col, time_col, y_var, x_var]
        df_sub = df[cols_needed].dropna()

        if len(df_sub) < 300 or df_sub[id_col].nunique() < 20:
            done += 1
            continue

        try:
            # Panel TWFE
            m = pf.feols(
                f'{y_var} ~ {x_var} | {id_col} + {time_col}',
                df_sub,
                vcov={'CRV1': id_col}
            )
            coef = m.coef()[x_var]
            se = m.se()[x_var]
            t_stat = coef / se
            pval = 2 * (1 - abs(t_stat) / (abs(t_stat) + df_sub[id_col].nunique()))

            # 简单显著性判断
            sig = abs(t_stat) > 2.0

            results.append({
                'Y': y_var,
                'X': x_var,
                'coef': round(coef, 4),
                'se': round(se, 4),
                't_stat': round(t_stat, 2),
                'sig': sig,
                'n_obs': len(df_sub),
                'n_cities': df_sub[id_col].nunique()
            })
        except Exception as e:
            pass

        done += 1
        if done % 20 == 0:
            print(f"进度: {done}/{total}")

# 转换为DataFrame
res_df = pd.DataFrame(results)
print(f"\n总共测试: {len(res_df)} 个组合")
print(f"显著的: {res_df['sig'].sum()} 个")

# 只看显著结果，按|t|排序
sig_df = res_df[res_df['sig']].sort_values('t_stat', key=abs, ascending=False)
print("\n=== 显著结果（按|t-stat|排序）===")
print(sig_df.head(30).to_string())

# 保存完整结果
res_df.to_csv(r'ECO_IDEA_SCAN.csv', index=False, encoding='utf-8-sig')
sig_df.to_csv(r'ECO_IDEA_SIGNIFICANT.csv', index=False, encoding='utf-8-sig')
print("\n已保存到 ECO_IDEA_SCAN.csv 和 ECO_IDEA_SIGNIFICANT.csv")
```

将 ECO_IDEA_SCAN.csv 和 ECO_IDEA_SIGNIFICANT.csv 保存到**数据所在目录**。

---

## 步骤 4：新颖性筛选

读取 ECO_IDEA_SIGNIFICANT.csv 后，对显著结果进行筛选：

**排除以下"无聊"关系**（这些已有大量文献）：
- GDP → GDP类变量（同义反复）
- 规模变量 → 规模变量（人口 → GDP）
- 金融发展 → 经济增长（过度研究）
- 贸易开放 → GDP（过度研究）

**保留以下"有趣"关系**：
- 非传统X（文化/制度/信息/健康/自然地理）→ 经济产出
- 创新产出（专利）作为Y，非显然X
- 空间/网络溢出效应相关
- 有异质性分析潜力（城乡/东西部/高低收入）
- 数据中有时间趋势断点（可能对应政策冲击）

用WebSearch搜索每个候选X→Y关系是否已有中文顶刊论文：
`"[X变量含义]" "[Y变量含义]" 因果识别 site:cnki.net OR site:ssrn.com`

---

## 步骤 5：识别策略 + 切口具体性综合评估

对筛选后的3-5个候选关系，逐一完成以下评估表：

```
候选关系：[X变量含义] → [Y变量含义]

─────────────────────────────────────────
【A】切口具体性评分（0-5分）
─────────────────────────────────────────
□ X 是具体命名的政策/事件（非水平变量）？     +2分
□ 有明确的冲击年份（具体到年甚至季度）？       +1分
□ 处理单元是微观个体（企业/乡镇/个人/县）？   +1分
□ 有自然对照组（未受影响的类似单元）？         +1分

切口具体性得分：___/5
⚠ 得分 < 3 → 该话题太宽泛，顶刊不接受，建议搜索是否有更具体的政策冲击

─────────────────────────────────────────
【B】切口具体化操作（若得分<3，必做）
─────────────────────────────────────────
用 WebSearch 搜索：
  "[X变量含义]" "[数据时间范围内某年份]" 政策改革 中国
  "[X variable]" specific policy reform "[country/region]" site:nber.org

目标：找到一个**有具体名称和年份**的政策事件，将宽泛的X转化为具体冲击
例：
  "金融发展" → 某市2014年设立的特定金融改革试验区
  "宽带普及" → 2015年宽带中国战略中某批次城市入选
  "企业融资" → 某行业2016年特定银行分支机构关闭事件

若找不到具体事件 → 该候选降级，不推荐作为主研究问题

─────────────────────────────────────────
【C】识别策略可行性
─────────────────────────────────────────
□ 内生性来源：
  □ 遗漏变量（哪些变量同时影响X和Y？）
  □ 反向因果（Y是否反过来影响X？）

□ 识别方案：
  □ 有政策冲击可做DiD？（处理组=受政策影响，对照组=未受影响）
  □ 有工具变量候选？（地理特征/历史遗留/Bartik）
  □ 数据中的跳变年份对应已确认的政策冲击？

─────────────────────────────────────────
【综合评分】
─────────────────────────────────────────
切口具体性：___/5
识别可行性：___/5
新颖性：    ___/5
总分：      ___/15

★★★★★ ≥ 12分：强烈推荐，直接进入 eco-lit-review
★★★★  10-11分：推荐，但需进一步确认切口
★★★   8-9分：一般，建议缩窄角度后再推进
★★以下 <8分：不推荐，切口太宽或识别不可行
```

---

## 步骤 6：数据中寻找"断点"和"政策冲击"

```python
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

df = pd.read_csv(DATA_PATH, encoding='utf-8-sig')

# 按时间计算各变量均值，寻找跳变点
time_col = "year"
ln_cols = [c for c in df.columns if c.startswith('ln_')]

annual_means = df.groupby(time_col)[ln_cols].mean()

# 计算年度变化率
annual_changes = annual_means.diff()

# 找到变化最大的年份（每个变量）
print("=== 各变量历史最大年度跳变 ===")
for col in ln_cols:
    if col in annual_changes.columns:
        max_change_year = annual_changes[col].abs().idxmax()
        max_change = annual_changes[col].abs().max()
        if max_change > 0.05:  # 只显示变化大于5%的
            print(f"{col}: 最大跳变年份={max_change_year}, 变化幅度={max_change:.3f}")

# 输出各变量时间序列（用于人工判断是否有政策断点）
print("\n=== 年度均值时间序列（ln_变量）===")
print(annual_means.round(3).to_string())
```

**重点**：找到跳变年份后，用WebSearch搜索该年份是否有对应政策冲击：
`"[跳变年份]" "[X变量含义]" 政策 中国`
`"[跳变年份]" China "[X variable meaning]" policy reform`

如果找到政策冲击，这是**最强的DiD识别机会**。

---

## 步骤 7：生成 ECO_IDEA.md

写入数据所在目录的 `ECO_IDEA.md`，内容：

```markdown
# 研究问题候选档案

## 数据概况
- 数据路径：
- 样本规模：
- 时间范围：
- 变量数量：

## 扫描结果摘要
- 测试组合总数：
- 显著组合数量：
- 筛选后候选数：

## 候选研究问题

### 候选1（推荐★★★★★）
**研究问题**：[具体事件名称] 如何影响 [Y]？
**一句话切口**：[年份] + [具体政策/事件名] + [处理单元类型] + [Y结果]
  示例："2016年缅甸矿业暂停令导致乡镇级武装冲突下降69%"
**切口具体性**：___/5（≥4方可推荐）
**统计基础**：TWFE系数 = X.XXXX（SE = X.XXXX，N = XXXX）
**具体政策冲击**：[政策名称 + 颁布年份 + 覆盖范围 + 处理组定义]
**对照组**：[未受该政策影响的类似单元，说明可比性]
**识别策略**：[DiD/IV/RD]
**新颖性**：[为什么这个关系有研究价值，现有文献空白]
**文献对标**：[类似识别策略的AER论文]
**下一步**：运行 `/eco-lit-review "[研究问题]"` 进一步验证

### 候选2（推荐★★★★）
...

### 候选3（推荐★★★）
...

## 数据中的"政策断点"清单
| 变量 | 跳变年份 | 变化幅度 | 可能的政策冲击 |
|------|----------|----------|----------------|

## 不推荐的关系（及原因）
- [X]→[Y]：原因（过度研究/无识别策略/方向不合逻辑）

## 推荐的下一步
1. 对候选1运行：`/eco-lit-review "[候选1问题]"`
2. 确认文献空白后运行：`/eco-analysis "[候选1问题]" "[数据路径]"`
```

完成后输出："研究扫描完成！测试了[N]个变量组合，发现[N]个有趣候选问题。推荐：[候选1]。档案保存至 ECO_IDEA.md"
