---
name: eco-pipeline
description: 全自动计量经济学论文写作流水线。输入研究主题和数据路径，自动完成数据探索、研究问题发现、文献调研、实证分析、论文写作。
argument-hint: '"研究主题或auto" "项目目录路径"'
allowed-tools: Read, Write, Bash, WebSearch, WebFetch, Glob, Grep
---

# Eco-Pipeline: 全自动计量经济学论文流水线

## 你的任务
按顺序执行以下6个阶段，将所有状态文件统一写入项目目录，最终输出完整论文草稿。流水线必须采用“目标—执行—质检—回退—再执行”的循环逻辑，不能只线性调用各个 skill。

## 全局循环控制（必须执行）

在项目目录创建并持续更新：

```text
ECO_PIPELINE_TODO.md    全局阶段任务、目标、状态、修订轮次
ECO_PIPELINE_QA.md      每阶段质量检查、失败原因、回退动作
```

每个阶段都有明确目标、产物、通过条件和失败回退。阶段状态只能使用：

```text
pending -> running -> needs_revision -> passed -> blocked
```

执行规则：

1. 每个阶段开始前，在 `ECO_PIPELINE_TODO.md` 标记为 `running`，写清本轮目标和输入文件。
2. 阶段结束后，立即在 `ECO_PIPELINE_QA.md` 做质量检查，不得只检查文件是否存在。
3. 若阶段未达标，状态改为 `needs_revision`，回到该阶段或其依赖阶段修订，最多3轮。
4. 第3轮仍未达标时，若问题是数据或识别不可解决，状态改为 `blocked` 并向用户说明；若只是文本/格式/表格不足，继续修订直到通过，不得跳过。
5. 后续阶段发现上游问题时，必须回退到对应上游阶段。例如实证分析发现变量定义不清，回到阶段2；发现政策冲击不成立，回到阶段2.5/2.7；发现文献空白不成立，回到阶段3。
6. 完成最终汇报前，所有非跳过阶段必须为 `passed`，且 `ECO_PIPELINE_QA.md` 中无未处理 blocker。

`ECO_PIPELINE_TODO.md` 初始模板：

```markdown
# 全局流水线任务清单

| 阶段 | 目标 | 关键产物 | 通过条件 | 状态 | 修订轮次 |
|---|---|---|---|---|---:|
| 0 研究问题发现 | 生成可识别的候选主题 | ECO_IDEA.md | 候选主题具备X/Y/冲击/样本 | pending | 0 |
| 1 初始化简报 | 固化研究目标和路径 | ECO_BRIEF.md | X/Y/数据路径/状态完整 | pending | 0 |
| 2 数据探索 | 明确数据结构与变量 | ECO_DATA_PROFILE.md | ID/时间/Y/X/控制/样本缺失清楚 | pending | 0 |
| 2.5 切口关卡 | 判断研究问题是否可识别 | ECO_BRIEF.md | 切口评分>=3或用户确认调整 | pending | 0 |
| 2.7 政策背景 | 核实政策事实和制度背景 | ECO_BACKGROUND.md | 时间线/处理组/来源URL完整 | pending | 0 |
| 3 文献调研 | 建立文献、机制和识别依据 | ECO_LIT.md | 文献流/空白/机制/异质性完整 | pending | 0 |
| 3.5 引用核查 | 排除假引用 | ECO_REFS_VERIFIED.md | 无FAIL；WARN有提示 | pending | 0 |
| 4 实证分析 | 生成可解释、可复现的结果 | ECO_RESULTS.md + tables/ + analysis.do | 主结果/动态/稳健/机制/异质性齐全且有Stata复现代码 | pending | 0 |
| 4.5 贡献声明 | 明确边际贡献 | ECO_CONTRIBUTION.md | 贡献有数字、文献对照、政策含义 | pending | 0 |
| 5 论文写作 | 生成中文期刊格式论文 | ECO_PAPER_DRAFT.md + paper.pdf | 正文>=10000字且格式达标 | pending | 0 |
```

## 参数解析
- $ARGUMENTS 第一个参数：研究主题（必填）
  - 填具体主题（如"宽带基础设施对城市创新的影响"）→ 直接从阶段1开始
  - 填 `"auto"` → 先跑阶段0自动发现研究问题
- $ARGUMENTS 第二个参数：项目目录路径（必填，如 `E:\Auto_eco\ai_econometrics`）
  - 该目录下应有数据文件（或 step2/ 等子目录）
  - 所有状态文件（ECO_*.md）均写入此目录
  - 回归表格写入此目录下的 tables/ 子目录
  - Stata复现代码写入 `analysis.do`

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

## 最终交付包（必须生成）

流水线完成后，必须把分散产物整理到一个文件夹，默认命名：

```text
final_package/
```

若同名文件夹已存在，使用时间戳命名，例如：

```text
final_package_YYYYMMDD_HHMMSS/
```

交付包结构：

```text
final_package/
  paper/
    paper.pdf
    paper.tex
    ECO_PAPER_DRAFT.md
  code/
    analysis.do
    analysis.log（若已运行）
    其他复现脚本（如 Python/R 脚本，若存在）
  tables/
    table*.csv / table*.txt / table*.rtf
    figure*.pdf / figure*.png
  docs/
    ECO_BRIEF.md
    ECO_DATA_PROFILE.md
    ECO_BACKGROUND.md
    ECO_LIT.md
    ECO_REFS_VERIFIED.md
    ECO_RESULTS.md
    ECO_CONTRIBUTION.md
  qa/
    ECO_PIPELINE_TODO.md
    ECO_PIPELINE_QA.md
    ECO_ANALYSIS_TODO.md
    ECO_ANALYSIS_QA.md
    ECO_WRITING_TODO.md
    ECO_SECTION_PLAN.md
    ECO_WRITING_QA.md
    WORD_COUNT_CHECK.md（若存在）
  README.md
```

打包规则：

- `paper.pdf`、`paper.tex`、`analysis.do`、`ECO_RESULTS.md`、`ECO_PAPER_DRAFT.md` 是核心文件，缺任何一个都不得标记为完整交付包。
- `tables/` 中所有主文表图必须复制到 `final_package/tables/`，不能只复制部分表格。
- 若某个可选文件不存在，在 `final_package/README.md` 中说明，不要伪造空文件。
- `README.md` 必须写明研究主题、生成时间、主文件路径、如何编译 PDF、如何运行 Stata 代码、哪些文件需要人工复核。
- 打包完成后，在 `ECO_PIPELINE_QA.md` 记录交付包路径和核心文件检查结果。

阶段1质检：
- `ECO_BRIEF.md` 必须包含 TOPIC、PROJECT_DIR、DATA_PATH 和流水线状态。
- 若 TOPIC 为空、DATA_PATH 不存在或状态表缺失，阶段1标记为 `needs_revision` 并重写简报。

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

阶段2质检：
- `ECO_DATA_PROFILE.md` 必须报告样本量、变量列表、ID变量、时间变量、候选Y、候选X、控制变量、缺失率和识别策略初判。
- 若无法识别 ID/TIME/Y/X，必须回到 `/eco-data-explore` 重新探索，必要时让用户确认变量，而不是继续进入实证分析。
- 若样本量过小、处理组/对照组缺失、时间维度不足，标记为 `blocked` 或回到阶段0/2.5调整研究问题。

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

阶段2.5质检：
- 必须在 `ECO_PIPELINE_QA.md` 记录4项评分、扣分原因和是否调整主题。
- 若评分低于3且未形成更具体的政策/事件冲击，不得进入阶段2.7或阶段3。

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

阶段2.7质检：
- `ECO_BACKGROUND.md` 必须包含至少一个权威来源URL、政策时间线、处理组定义、对照组逻辑和潜在同期干扰。
- 若政策来源缺失或时间线不清，回到 `/eco-background` 补充；无法补充时在 `ECO_PIPELINE_QA.md` 标记 blocker，不得把政策事实写成确定表述。

> **目的**：Section 3 政策背景必须有 URL 来源支撑，不能依赖模型记忆。
> 此阶段在文献调研之前执行，确保 eco-lit-review 能引用准确的政策细节。

---

## 阶段 3：文献调研

调用 `/eco-lit-review "[TOPIC]"` 技能。

等待完成，读取 `ECO_LIT.md`，提取：
- 推荐识别策略（与阶段2初判对照，取更合理者）
- 机制变量清单（供阶段4使用）
- 异质性分组清单（供阶段4使用）

阶段3质检：
- `ECO_LIT.md` 必须包含至少3条文献流、研究空白、理论机制、识别策略依据、机制变量和异质性分组。
- 若文献与主题不匹配、只有泛泛综述或缺少可检验机制，回到 `/eco-lit-review` 重做。
- 若发现研究空白不足，必须回到阶段0/2.5调整角度，不得强行进入论文写作。

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

阶段3.5质检：
- `ECO_REFS_VERIFIED.md` 中存在 FAIL 时，必须停止或替换文献；不得把 FAIL 引用带入 `ECO_PAPER_DRAFT.md`。
- WARN 条目必须写入 `ECO_PIPELINE_QA.md` 的残余风险。

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

阶段4质检：
- 必须存在 `ECO_RESULTS.md`、`ECO_ANALYSIS_TODO.md`、`ECO_ANALYSIS_QA.md`、`analysis.do` 和 `tables/`。
- `ECO_RESULTS.md` 必须至少包含：样本说明、描述统计、基准结果、识别有效性/动态效应、稳健性、机制检验、异质性分析、局限性。
- `tables/` 必须至少包含描述统计表、基准结果表、稳健性表；DiD研究还必须包含动态效应或事件研究图。
- `analysis.do` 必须能复现主要实证结果；不得保留 `[Y_VAR]`、`[X_VAR]`、`[DATA_PATH]` 等未替换占位符。若 Stata 与 Python/R 估计器不完全等价，必须在 do-file 注释和 `ECO_ANALYSIS_QA.md` 中说明。
- 若 `ECO_ANALYSIS_QA.md` 标记任何核心项目未通过，回到 `/eco-analysis` 只修订失败的分析模块，不得重跑并覆盖已通过模块。
- 若主结果不显著或方向相反，不自动换变量；把阶段4标记为 `needs_revision`，先检查数据定义、模型设定、样本范围和识别假设。确认无误后如实保留结果，并在论文中转为“弱证据/无显著证据”的规范表述。

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

阶段4.5质检：
- `ECO_CONTRIBUTION.md` 必须把贡献和阶段4的具体结果、阶段3的文献空白、阶段2.7的政策背景对应起来。
- 若贡献没有数字或没有文献对照，回到 `/eco-contribution` 修订；若贡献依赖的主结果未通过，回到阶段4。

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

等待完成后，不要只读取 `ECO_PAPER_DRAFT.md`。Stage 5 必须把论文写作视为一个可检查、可循环的子流程，检查以下文件：

- `ECO_WRITING_TODO.md`：写作任务、章节状态、字数目标、质量门槛。
- `ECO_SECTION_PLAN.md`：每节的核心论点、证据来源、表图/文献映射、字数下限。
- `sections/01_intro.md` 至 `sections/08_conclusion_policy.md`：逐节完成的正文。
- `ECO_WRITING_QA.md`：每节质检分数、修订轮次、缺口和 residual risk。
- `ECO_PAPER_DRAFT.md`：通过质检后的整合稿。
- `paper.tex`：可编译 LaTeX 源文件。
- `paper.pdf`：如果 `tectonic`、`xelatex` 或 `latexmk` 可用，必须尝试生成。

国内/CSSCI 默认模式下，Stage 5 的质量门槛：

1. 正文中文字符数不得低于 10,000；统计时必须排除摘要、表图、公式、参考文献和附录。CSSCI/高质量实证论文推荐 12,000-18,000。
2. 每个章节必须先在 `sections/` 中单独成文，再整合进 `ECO_PAPER_DRAFT.md`。
3. 每节 `ECO_WRITING_QA.md` 评分低于 8 分时，必须回到该节修订，最多 3 轮。
4. 若正文中文字符低于 10,000，不能结束 pipeline，不能生成最终版标记；必须优先扩写低于目标字数的章节。
5. 若政策事实无权威来源，必须标注“待核查”，不得伪造政策出处或讲话原文。
6. 若参考文献少于 20 篇或中文文献少于 8 篇，不得伪造文献；输出待补充检索清单，并在最终汇报中提示。
7. 表格、系数、样本量、显著性描述必须与 `ECO_RESULTS.md` 和 `tables/` 一致。
8. 表格必须符合中文期刊格式：统一字号三线表，回归系数带 `*`、`**`、`***` 显著性星号，英文变量/模型/分组名必须有中文解释，主文表不得因单独缩放导致字体不统一。
9. 参考文献编号必须使用半角方括号 `[1]`、`[2]` 格式，不得使用中文全角括号或【】。

可用如下 PowerShell 检查全文长度：

```powershell
$text = Get-Content .\ECO_PAPER_DRAFT.md -Raw
$body = ($text -replace '(?s)##?\s*参考文献.*$','')
$body = ($body -replace '(?s)```.*?```','')
$body = ($body -replace '(?s)\|.*?\|','')
$chars = ([regex]::Matches($body, '[\u4e00-\u9fff]')).Count
if ($chars -lt 10000) { throw "Paper body too short: $chars Chinese chars" }
```

如果上述检查失败，回到 `/eco-write-paper "[TOPIC]"`，明确要求“只修订未达标章节并重新整合”，不得从头丢弃已有合格章节。

---

## 全局最终总检（必须通过）

在输出完成汇报前，读取 `ECO_PIPELINE_TODO.md` 和 `ECO_PIPELINE_QA.md`，逐项确认：

1. 所有已执行阶段状态均为 `passed`；被跳过阶段必须写明跳过理由。
2. 不存在未处理的 `blocked` 或 `needs_revision`。
3. 上游产物完整：`ECO_BRIEF.md`、`ECO_DATA_PROFILE.md`、`ECO_BACKGROUND.md`、`ECO_LIT.md`、`ECO_REFS_VERIFIED.md`、`ECO_RESULTS.md`、`ECO_CONTRIBUTION.md`。
4. 分析产物完整：`ECO_ANALYSIS_TODO.md`、`ECO_ANALYSIS_QA.md`、`ECO_RESULTS.md`、`analysis.do`、`tables/`，且核心分析模块通过。
5. 写作产物完整：`ECO_WRITING_TODO.md`、`ECO_SECTION_PLAN.md`、`sections/`、`ECO_WRITING_QA.md`、`ECO_PAPER_DRAFT.md`、`paper.tex`，有编译器时必须有 `paper.pdf`。
6. 正文字数、表格格式、参考文献格式满足 Stage 5 门槛。
7. 最终交付包 `final_package/` 或带时间戳的 `final_package_*/` 已生成，且包含 `paper/paper.pdf`、`paper/paper.tex`、`code/analysis.do`、`tables/`、`docs/ECO_RESULTS.md`、`qa/` 和 `README.md`。

若任何一项失败，不得输出“完成”；必须回到失败阶段继续循环，并在 `ECO_PIPELINE_QA.md` 记录本轮回退动作。

---

## 完成汇报

输出以下总结：

```
=== Eco-Pipeline 完成 ===

项目目录：[PROJECT_DIR]
最终交付包：[PROJECT_DIR]/final_package

已生成文件：
└── final_package/
    ├── paper/                  PDF、LaTeX和Markdown论文稿
    ├── code/                   Stata复现代码和运行日志
    ├── tables/                 主文表格和图形
    ├── docs/                   数据、文献、政策、结果和贡献档案
    ├── qa/                     全流程、分析和写作质检记录
    └── README.md               交付包说明

项目根目录保留：
├── ECO_BRIEF.md              研究简报
├── ECO_DATA_PROFILE.md       数据档案（含识别策略初判）
├── ECO_BACKGROUND.md         政策制度背景（含来源URL）
├── ECO_LIT.md                文献综述档案
├── ECO_REFS_VERIFIED.md      引用核查报告
├── ECO_CONTRIBUTION.md       贡献声明
├── ECO_RESULTS.md            实证结果档案
├── analysis.do               Stata复现代码
├── ECO_WRITING_TODO.md       写作任务清单与质量门槛
├── ECO_SECTION_PLAN.md       分节写作计划
├── sections/                 分节正文草稿
├── ECO_WRITING_QA.md         分节质检与修订记录
├── ECO_PAPER_DRAFT.md        论文草稿
├── paper.tex                 LaTeX源文件
├── paper.pdf                 PDF稿件（若编译器可用）
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
3. analysis.do 是否能在本机 Stata 中复现主表结果
4. ECO_REFS_VERIFIED.md 中 WARN 条目（建议Google Scholar确认）
5. ECO_BACKGROUND.md 中"[未核实，来自模型记忆]"标注（建议检索原始文件）
```
