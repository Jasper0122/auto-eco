# Auto-Eco：全自动计量经济学论文写作系统

受 [ARIS](https://github.com/wanshuiyin/Auto-claude-code-research-in-sleep) 项目启发，专为计量经济学论文定制的自动化写作流水线。规范基于 AER 2020-2021 年 16 篇论文提炼，全部内嵌到各 skill 中。不需要 Stata。

---

## 这是什么

提供**研究主题**和**数据**，系统自动完成：

1. 探索数据，识别变量结构，初判识别策略
2. 自动发现数据中有趣的研究切入点（可选）
3. 搜索文献，归纳研究空白，推荐识别策略
4. 运行 Python 回归，生成标准表格 + 事件研究图
5. 按 AER 规范写出完整中文论文草稿

---

## 快速开始

### 安装

```bash
# 复制 skills 到 Claude Code 的技能目录
cp -r E:/Auto_eco/skills/* C:/Users/<你的用户名>/.claude/skills/

# 安装 Python 依赖
pip install pyfixest linearmodels statsmodels pandas numpy scipy openpyxl matplotlib seaborn csdid
```

### 运行

```
# 已知研究主题
/eco-pipeline "2015年宽带中国试点对县级制造业TFP的影响" "E:\my_project"

# 让系统自动发现研究问题
/eco-pipeline "auto" "E:\my_project"
```

也可以单独调用某个阶段（见下方各 Skill 说明）。

---

## 流水线全貌

```
/eco-pipeline "主题或auto" "项目目录"
│
├─ [阶段0] eco-idea（仅 auto 模式）
│   扫描所有 ln_ 变量两两 TWFE 回归 → 找显著且有趣的 X→Y
│   评分：识别策略可行性 + 切口具体性 + 新颖性（满分15）
│   输出：ECO_IDEA.md → 用户确认选题后继续
│
├─ [阶段1] 初始化
│   输出：ECO_BRIEF.md（研究简报，全程追踪流水线状态）
│
├─ [阶段2] eco-data-explore
│   探索变量结构、缺失率、面板平衡性
│   自动识别：DiD信号（treat/post关键词）/ IV信号（geo/dist关键词）/ 断点信号
│   推荐：FE组合 + 聚类SE层级 + WCB警告（聚类数<50时）
│   输出：ECO_DATA_PROFILE.md
│
├─ [阶段2.5] 切口关卡（硬性检查，不过不推进）
│   ✓ X 是具体命名政策/事件（非"水平/程度"型变量）
│   ✓ 有明确冲击年份
│   ✓ 处理单元是微观个体（企业/县/乡镇）
│   ✓ 有自然对照组
│   ≥3分继续 / <3分强制缩窄 / 0分停止
│
├─ [阶段3] eco-lit-review
│   6轮 WebSearch（顶刊/NBER/机制/中国情境/综述）
│   归纳3-5条文献脉络 → 推荐识别策略 → 提出H1/H2/H3
│   输出：ECO_LIT.md（含机制变量清单、异质性分组清单）
│
├─ [阶段4] eco-analysis
│   完整实证分析，见下方详细说明
│   若主系数不显著：如实报告，不自动换题（不做 specification searching）
│   输出：ECO_RESULTS.md + tables/
│
└─ [阶段5] eco-write-paper
    AER 8段引言 + 完整正文 + 结论5段
    输出：ECO_PAPER_DRAFT.md
```

---

## eco-analysis 内部结构

eco-analysis 是核心，按以下顺序执行：

### Table 1：描述统计
- 全样本 N/均值/SD/P25/P75
- DiD 时必做基线平衡检验（处理组 vs 对照组均值差 + 联合F检验）

### Table 2：基准回归（含结构化安慰剂）

6列递进规格（无FE → 控制变量 → 个体FE → 双向FE → DiD → ln(Y)），**加上安慰剂列**：

| 列 | 内容 | 预期结果 |
|----|------|---------|
| 安慰剂A | 更高地理层级处理变量（县级政策→用市级处理） | 不显著 → 无地理混淆 |
| 安慰剂B | 时间安慰剂（政策提前2期，全样本） | 不显著 → 无前期趋势 |
| 安慰剂C | 地理不变量（海拔/降水，用户指定） | 不显著 → 无空间选择 |

安慰剂直接进 Table 2，审稿人一眼可判断识别是否干净。

需在步骤0设置：
- `HIGHER_LEVEL_TREAT_VAR`：更高层级处理变量名（无则 None）
- `PLACEBO_VARS`：不变量列表（留空则跳过安慰剂C）

### Table 2b：多结果变量综合表
- 固定主规格，对所有理论驱动的 OUTCOME_VARS 逐列回归
- 展示事件影响广度；不显著的 Y 可作为安慰剂型 Y

### Table 3：识别策略

**DiD 时先检测是否为 Staggered Adoption（各单元首次处理年份是否不同）：**

- **Staggered（多队列）→ Callaway & Sant'Anna (2021) CS-DiD 为主报告**
  - Simple Aggregate ATT + Dynamic Aggregate 事件研究图
  - TWFE 事件研究保留为对比，注明负权重问题
- **单一处理时间 → 标准 TWFE 事件研究**
  - 平行趋势联合 Wald 检验（超前期应联合不显著）

IV 时：第一阶段 F（Stock-Yogo >10 / Montiel Olea-Pflueger >104.7）+ 2SLS。

### Table 4：稳健性（5项通用 + IV专项）

① Winsorize 1%　② 替换Y（对数化）　③ 放松FE　④ 无控制变量　⑤ 剔除极端X

另有：
- **Table 4b**：事件驱动宏观结果扫描（BH-FDR 多重检验校正）
- **Table 4c**：替代解释排除（Panel 格式，逐一控制竞争性解释）

### Table 4d：溢出效应分析（稳健性之后）

溢出是加分项，不是识别核心，放在稳健性通过后报告。判断：同向→扩散，反向→位移/替代，不显著→对照组干净。

### Table 5：机制分析

三步回归（X→M，M→Y，加M后β下降）+ 交互项调节法。

**写作规范（保守）**：
- 说"结果与该渠道假设一致"，不说"主要机制""必要机制"
- 传导比例自动附加免责：*此比例为 OLS 描述性分解，非 M 对总效应的严格因果贡献*

### Table 6：异质性分析（Panel 格式）
- 理论驱动分组，不机械遍历
- 行 = 异质性维度，列 = OUTCOME_VARS，末列 = 组间差异 p 值

---

## 生成文件清单

```
项目目录/
├── ECO_BRIEF.md              研究简报（流水线状态追踪）
├── ECO_IDEA.md               候选研究问题（auto模式）
├── ECO_DATA_PROFILE.md       数据档案（变量、识别策略初判）
├── ECO_LIT.md                文献档案（脉络、空白、机制/异质性变量）
├── ECO_RESULTS.md            实证结果档案（供写作阶段读取）
├── ECO_PAPER_DRAFT.md        完整论文草稿
└── tables/
    ├── table1_descriptive.csv       描述统计 + 基线平衡检验
    ├── table1b_balance.csv          基线平衡（DiD）
    ├── table2_baseline.txt          基准回归（含安慰剂列）
    ├── table2b_multi_outcomes.txt   多结果变量综合表
    ├── table3_csdid.csv             CS-DiD 估计（Staggered）
    ├── table3_event_study.txt       TWFE 事件研究
    ├── table3_iv.txt                IV 回归（IV策略）
    ├── table4_robustness.txt        稳健性检验（5项）
    ├── table4b_outcome_scan.csv     宏观结果扫描（FDR校正）
    ├── table4c_alt_accounts.csv     替代解释排除
    ├── table4d_spillovers.txt       溢出效应
    ├── table5_mechanism.txt         机制分析
    ├── table6_het_[变量名].csv      异质性分析（每维度一文件）
    └── figure1_event_study.pdf/png  事件研究图
```

---

## 各 Skill 单独调用

| Skill | 命令 | 功能 |
|-------|------|------|
| eco-pipeline | `/eco-pipeline "题目" "目录"` | 一键全流程 |
| eco-idea | `/eco-idea "数据路径"` | 自动发现研究问题 |
| eco-data-explore | `/eco-data-explore "路径"` | 数据探索 + 识别策略初判 |
| eco-lit-review | `/eco-lit-review "题目"` | 文献调研 + 假设 |
| eco-analysis | `/eco-analysis "题目" "路径"` | 完整实证分析 |
| eco-write-paper | `/eco-write-paper "题目"` | 写论文草稿 |

---

## AER 规范内嵌项

| 规范 | 位置 |
|------|------|
| 识别策略决策树（DiD/IV/RCT/TWFE） | eco-analysis、eco-data-explore |
| Staggered DiD → CS-DiD（Callaway & Sant'Anna 2021） | eco-analysis |
| DiD 四种变体方程 | eco-analysis、eco-write-paper |
| FE 组合指南 + 聚类SE指南 + WCB 警告 | eco-analysis、eco-data-explore |
| 结构化安慰剂（地理层级 + 时间 + 不变量） | eco-analysis |
| 稳健性清单（通用5项 + IV专项） | eco-analysis |
| 溢出效应分析（Table 4d，稳健性之后） | eco-analysis |
| 机制保守表达 + OLS分解免责 | eco-analysis、eco-write-paper |
| 8段引言结构 + 5段结论 | eco-write-paper |
| 数字规范（β4位、效应占均值%、Back-of-Envelope） | eco-analysis、eco-write-paper |
| AER 发表潜力评分 | eco-idea |

---

## 技术依赖

```bash
pip install pyfixest linearmodels statsmodels pandas numpy scipy openpyxl matplotlib seaborn csdid
```

| 包 | 用途 |
|----|------|
| `pyfixest` | 核心回归（Python 版 reghdfe，支持 TWFE/DiD/IV） |
| `csdid` | Callaway & Sant'Anna CS-DiD（Staggered 稳健估计） |
| `linearmodels` | IV/2SLS 回归、Hansen J 检验 |
| `statsmodels` | BH-FDR 多重检验校正 |

---

## 注意事项

1. 数据格式支持 `.csv`、`.xlsx`、`.dta`，CSV 建议 UTF-8-sig 编码
2. 论文草稿为中文，变量名可保留英文
3. **引言第3段数字必须与 ECO_RESULTS.md 一致**（人工核查，系统无法自动保证）
4. 参考文献来自网络搜索，请在 Google Scholar 验证真实性
5. 主系数不显著时系统不会自动换题——这是有意设计，避免 specification searching。可通过多结果（Table 2b）、置信区间、异质性子群分析来建立论证
6. `HIGHER_LEVEL_TREAT_VAR` 和 `PLACEBO_VARS` 需要用户根据数据结构手动指定，系统无法自动推断

---

## 设计原则

**切口要小**：不是"X影响Y"，是"某具体政策在特定时间/地点对微观单元的影响"。  
**识别要干净**：安慰剂进 Table 2，CS-DiD 处理 Staggered，溢出在稳健性后报告。  
**机制要保守**：三步法提供支持性证据，不声称因果分解。  
**结果要诚实**：不显著就如实报告，用广度和异质性建立论证，不跑到显著为止。

---

## 参考

- [ARIS](https://github.com/wanshuiyin/Auto-claude-code-research-in-sleep) — 本项目灵感来源
- 规范来源：AER 2020-2021 年 16 篇论文（DiD、IV、RCT、其他方法各4篇）
- Callaway, B. & Sant'Anna, P. H. C. (2021). Difference-in-Differences with Multiple Time Periods. *Journal of Econometrics*, 225(2), 200–230.
