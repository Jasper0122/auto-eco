---
name: eco-pipeline
description: 全自动计量经济学论文写作流水线。输入研究主题和数据路径，自动完成数据探索、研究问题发现、文献调研、实证分析、论文写作。
argument-hint: '"研究主题或auto" "项目目录路径"'
allowed-tools: Read, Write, Bash, WebSearch, WebFetch, Glob, Grep
---

# Eco-Pipeline: 全自动计量经济学论文流水线

## 你的任务
按顺序执行以下6个阶段，将所有状态文件统一写入项目目录，最终输出完整论文草稿。

## 参数解析
- $ARGUMENTS 第一个参数：研究主题（必填）
  - 填具体主题（如"宽带基础设施对城市创新的影响"）→ 直接从阶段1开始
  - 填 `"auto"` → 先跑阶段0自动发现研究问题
- $ARGUMENTS 第二个参数：项目目录路径（必填，如 `E:\Auto_eco\ai_econometrics`）
  - 该目录下应有数据文件（或 step2/ 等子目录）
  - 所有状态文件（ECO_*.md）均写入此目录
  - 回归表格写入此目录下的 tables/ 子目录

**执行前**：用 Bash 切换工作目录到项目目录：
```bash
cd "项目目录路径"
```
后续所有文件读写使用相对路径。

---

## 阶段 0：研究问题发现（仅当 TOPIC="auto" 时执行）

调用 `/eco-idea "数据文件路径"` 技能，自动扫描数据中的有趣变量关系。

等待完成，读取项目目录下的 `ECO_IDEA.md`，从中选取**推荐星级最高**的候选问题。

**向用户确认**选定的研究主题后，将其存为 TOPIC，进入阶段1。

如果 TOPIC 已明确，跳过此阶段。

---

## 阶段 1：初始化研究简报

在项目目录创建 `ECO_BRIEF.md`：

```markdown
# 研究简报

## 基本信息
- 研究主题：[TOPIC]
- 项目目录：[PROJECT_DIR]
- 数据路径：[DATA_PATH]
- 流水线启动时间：[时间]

## 核心因果问题
- X（核心解释变量）：[待数据探索后填入]
- Y（被解释变量）：[待数据探索后填入]
- 内生性来源：[待文献调研后填入]

## 流水线状态
- [x] 阶段1：初始化 ✓
- [ ] 阶段2：数据探索
- [ ] 阶段3：文献调研
- [ ] 阶段4：实证分析
- [ ] 阶段5：论文写作
```

---

## 阶段 2：数据探索

调用 `/eco-data-explore "[DATA_PATH]"` 技能。

等待完成，读取 `ECO_DATA_PROFILE.md`，提取：
- 个体ID变量名、时间变量名
- 候选Y变量（被解释变量）
- 候选X变量（核心解释变量）
- 控制变量列表
- 识别策略初判（DiD/IV/TWFE）
- 推荐FE组合和聚类层级
- 是否需要Wild Cluster Bootstrap（聚类数<50）

更新 ECO_BRIEF.md 中的 X、Y、内生性来源字段。

---

## 阶段 2.5：切口具体性关卡（必过，否则不推进）

在进入文献调研之前，对研究主题做切口评估。

**评估以下4个问题（每项1分，满分4分）：**

1. X 是**具体命名的政策/事件**，而非水平型变量（如"金融发展程度"）？
2. 有**明确的冲击年份**（能说出"XX年XX政策"）？
3. 处理单元是**微观个体**（企业/县/乡镇/个人），而非省级或国家级？
4. 有**自然对照组**（能定义哪些单元没有受到该政策影响）？

**判断规则：**

- **≥ 3分** → 切口合格，继续阶段3
- **1-2分** → 切口太宽，执行以下操作后再继续：
  1. 告知用户：当前话题切口过宽（举例说明哪项不满足）
  2. 搜索数据时间范围内是否有更具体的政策冲击：
     `"[研究主题关键词]" "[数据起止年份]" 具体政策 改革 试点`
  3. 将宽泛话题缩窄为**一个具体事件**后重新描述研究问题
  4. 用新的具体话题更新 ECO_BRIEF.md 并重新评估
- **0分** → 停止流水线，要求用户重新定义研究切入点

**切口改造示例：**
```
原始（宽）：金融发展如何影响企业创新？
改造后（窄）：2014年某市设立的金融改革试验区如何影响区内企业专利申请？

原始（宽）：基础设施投资对经济增长的影响
改造后（窄）：2015年宽带中国战略第二批试点城市获批对当地制造业企业TFP的影响
```

---

## 阶段 2.7：政策制度背景研究

调用 `/eco-background "[TOPIC]" "[PROJECT_DIR]"` 技能，搜集政策原始资料。

等待完成，读取 `ECO_BACKGROUND.md`，确认：
- 政策实施时间线（关键节点和批次）
- 处理组构成（哪些单元入选，为什么入选是外生的）
- 同期干扰政策（若有，记录以备稳健性检验）

> **目的**：Section 3 政策背景必须有 URL 来源支撑，不能依赖模型记忆。
> 此阶段在文献调研之前执行，确保 eco-lit-review 能引用准确的政策细节。

---

## 阶段 3：文献调研

调用 `/eco-lit-review "[TOPIC]"` 技能。

等待完成，读取 `ECO_LIT.md`，提取：
- 推荐识别策略（与阶段2初判对照，取更合理者）
- 机制变量清单（供阶段4使用）
- 异质性分组清单（供阶段4使用）

**关键检查**：若文献调研发现该问题已有大量AER级因果识别文献，研究空白不足，
向用户说明原因，建议调整主题或缩窄角度（异质性/机制/特定情境）。

---

## 阶段 3.5：引用核查

调用 `/eco-ref-verify "[PROJECT_DIR]"` 技能，逐条核查 ECO_LIT.md 中的引用。

等待完成，读取 `ECO_REFS_VERIFIED.md`：
- 若有 ❌ FAIL 条目：**暂停流水线**，告知用户具体的假引用列表，
  请用户决定是手动替换还是继续（FAIL 引用若保留会在审稿环节暴露）
- 若有 ⚠ WARN 条目：记录并继续，在完成汇报中提示人工核查
- 若全部 ✅ PASS：直接进入阶段4

---

## 阶段 4：实证分析

调用 `/eco-analysis "[TOPIC]" "[DATA_PATH]"` 技能。

执行前确认以下变量已从 ECO_DATA_PROFILE.md 和 ECO_LIT.md 中获取：
- ENTITY_VAR（个体ID）
- TIME_VAR（时间变量）
- Y_VAR（被解释变量）
- X_VAR（核心解释变量）
- CONTROL_VARS（控制变量列表）
- MECHANISM_VARS（机制变量，来自ECO_LIT.md）
- HETEROGENEITY_VARS（异质性分组变量，来自ECO_LIT.md）
- 识别策略（DiD/IV/TWFE）

等待完成，读取 `ECO_RESULTS.md`。

**关键检查**：若主模型（双向FE）中核心系数 |t| < 1.65 或方向与理论相反：
- **不要自动换题或换变量**——这是 specification searching，会损害学术规范
- 向用户如实报告结果，并说明可能原因（识别不够干净、样本限制、效应本身弱）
- 建议用以下方式建立论证：多结果变量（Table 2b 展示效应广度）、置信区间（区分"效应小"与"无效应"）、异质性分析（在理论预期强的子群中效应是否显著）
- 若用户明确判断研究问题需要调整，再切换至备选问题，但须由用户主动确认

---

## 阶段 4.5：贡献声明打磨

调用 `/eco-contribution "[PROJECT_DIR]"` 技能。

等待完成，读取 `ECO_CONTRIBUTION.md`，确认：
- 3条贡献点是否有具体数字支撑
- 是否点名了被超越的已有文献
- 是否发现本文与近期顶刊文献高度重合（若有，向用户说明）

> 贡献声明草稿将被 eco-write-paper 在引言阶段直接引用。

---

## 阶段 5：论文写作

调用 `/eco-write-paper "[TOPIC]"` 技能。

执行前确认项目目录下存在：
- ECO_BRIEF.md ✓
- ECO_DATA_PROFILE.md ✓
- ECO_BACKGROUND.md ✓（政策背景）
- ECO_LIT.md ✓
- ECO_REFS_VERIFIED.md ✓（引用核查）
- ECO_CONTRIBUTION.md ✓（贡献声明）
- ECO_RESULTS.md ✓
- tables/ 目录（含table1~6和figure1）✓

等待完成，读取 `ECO_PAPER_DRAFT.md`。

---

## 完成汇报

输出以下总结：

```
=== Eco-Pipeline 完成 ===

项目目录：[PROJECT_DIR]

已生成文件：
├── ECO_BRIEF.md              研究简报
├── ECO_DATA_PROFILE.md       数据档案（含识别策略初判）
├── ECO_BACKGROUND.md         政策制度背景（含来源URL）
├── ECO_LIT.md                文献综述档案
├── ECO_REFS_VERIFIED.md      引用核查报告
├── ECO_CONTRIBUTION.md       贡献声明
├── ECO_RESULTS.md            实证结果档案
├── ECO_PAPER_DRAFT.md        论文草稿
└── tables/
    ├── table1_descriptive.csv    描述统计
    ├── table2_baseline.txt       基准回归（含安慰剂列）
    ├── table3_csdid.csv          CS-DiD 估计（Staggered）
    ├── table3_event_study.txt    TWFE 事件研究
    ├── table4_robustness.txt     稳健性检验
    ├── table4d_spillovers.txt    溢出效应
    ├── table5_mechanism.txt      机制分析
    ├── table6_het_*.csv          异质性分析
    └── figure1_event_study.pdf   事件研究图

核心结果：
- 研究主题：[TOPIC]
- 识别策略：[DiD/IV/TWFE]
- 主系数：β = [X]（SE = [X]，t = [X]）
- 效应量：占样本均值 [X]%
- 稳健性：经[N]项检验，结论[稳健/有保留]

请重点人工核查：
1. ECO_PAPER_DRAFT.md 引言第3段数字是否与ECO_RESULTS一致
2. tables/ 中的系数是否与论文文字描述匹配
3. ECO_REFS_VERIFIED.md 中 WARN 条目（建议Google Scholar确认）
4. ECO_BACKGROUND.md 中"[未核实，来自模型记忆]"标注（建议检索原始文件）
```
