# Data Warehouse Project 1

## 项目概览

本项目当前已经完成了大部分数据处理、数据仓库实现和关联规则挖掘工作。  
目前的重点已经从“能不能做出来”转向“怎么把最终提交材料做得更完整、更一致、更可信”。

---

## Fixed Business Questions

以下 5 个业务问题目前作为项目主线使用，问题保持英文表述，便于后续直接写入报告。

1. Which countries and regions have the highest number and proportion of delayed or cancelled flights?
2. How does flight status change across month and quarter within the observed year?
3. Which airports handle the greatest traffic volume, and how do their flight status distributions compare?
4. How does flight status performance vary across airport, region, country, and continent hierarchies with different levels of navigation-aid availability?
5. Which combinations of time, geographic, and passenger related attributes are associated with different flight status outcomes?

---

## 目前已完成的工作

### 1. ETL 已完成

- 已使用本地 Python 完成一次性 ETL 清洗。
- 已修正 `Arrival Airport` 的 ETL 问题，将其按项目说明处理为 `Departure Airport Code` 的含义。
- 已整合 `airports.csv`、`countries.csv`、`regions.csv`、`navaids.csv`。
- 已将 `navaids.csv` 聚合为机场级属性，避免直接 join 导致 fact table 重复放大。
- 已生成 staging 数据和 warehouse-ready 数据。

### 2. PostgreSQL 数据仓库已基本完成

- 已在 PostgreSQL 中建立完整数据仓库：
  - `dim_date`
  - `dim_country`
  - `dim_region`
  - `dim_airport`
  - `dim_passenger`
  - `dim_flight_status`
  - `fact_passenger_flight`
- 已完成本地 CSV 导入。
- 已完成基于 PostgreSQL 的 cube / materialized view 多维分析层。
- 已跑通 5 个 business questions 的 SQL 查询。

### 3. Databricks 部分已完成基础实现

- 已完成数据上传与仓库落地。
- 已按项目要求完成 Databricks 版本的数据仓库实现。

### 4. Association Rule Mining 已完成

- 已使用纯 Python 实现关联规则挖掘，不依赖 Visual Studio、R 或 Weka。
- 已限制规则右侧只出现 `Flight Status`。
- 已计算并输出 `support`、`confidence`、`lift`。
- 已生成 top rules 与摘要说明文件。

### 5. Power BI 已开始

- 已完成初步查询结果导出。
- 已开始将 business query 结果导入 Power BI 做可视化。

---

## 当前还差什么

### 1. StarNet / Snowflake 图还没有正式画出来

- 这是当前最明显的缺口之一。
- 需要把概念层级画清楚，尤其是：
  - 时间层级：`Year -> Quarter -> Month`
  - 地理层级：`Continent -> Country -> Region -> Airport`
  - `navaid` 应作为机场维度属性，而不是独立 fact

### 2. Business Questions 仍可能需要微调

- 目前 5 个问题已经基本固定，但仍需要再检查一次：
  - 问题表述是否与 StarNet 完全一致
  - 问题表述是否与 cube、SQL、图表完全一致
  - 是否存在 wording 太强、容易被理解为因果推断的问题

### 3. SQL 语句需要再做一次全面检查

- 目前 SQL 基本已经能跑通，但还需要再检查：
  - 语法是否完全稳定
  - 指标计算是否正确
  - 是否存在重复统计或分母错误
  - cube 查询和普通查询之间是否一致

### 4. Power BI 图表目前比较粗糙，需要优化

- 现在图已经开始做了，但视觉效果还不够好。
- 需要继续修改：
  - 图表类型是否最合适
  - 颜色和排序是否清楚
  - 标题是否更像 business insight
  - 是否去掉 `Unknown` 等低价值类别
  - 页面布局是否适合截图进 PDF

### 5. References 目前有一部分是 AI 生成的，需要严格核对

- 这是一个明显风险点。
- 后续必须人工逐条核对：
  - 文献是否真实存在
  - 作者、年份、标题、会议/期刊是否正确
  - 引用内容是否与文献实际内容一致
- 必须特别注意 AI hallucination。

### 6. 报告整体一致性还需要最后整合

- 当前各部分已经分别做出来了，但还没有最后整合成一份完全一致的 submission package。
- 需要统一：
  - business questions
  - warehouse design
  - StarNet / Snowflake
  - cube
  - SQL
  - 可视化
  - association rules

### 7. 最终报告还没有写完

- 这是当前最终提交前最大的剩余工作。
- 报告需要系统写完以下内容：
  - project background
  - fixed business questions
  - dimensional design
  - StarNet / Snowflake
  - ETL explanation
  - PostgreSQL implementation
  - Databricks implementation
  - cube-based analysis
  - visualisations and insights
  - association rule mining
  - government recommendations
  - references

---

## 当前建议的下一步顺序

1. 先补画 StarNet / Snowflake 图。
2. 再统一检查 5 个 business questions 的 wording。
3. 全面复查 SQL 与 cube 查询结果。
4. 修改 Power BI 图表，使其适合最终截图。
5. 人工核对所有 references，删除或替换可疑引用。
6. 最后集中写报告并统一格式。

---

## 当前状态总结

从实现角度看，项目已经完成了大部分核心工作：ETL、PostgreSQL、Databricks、cube、SQL、association rule mining 都已经有了。  
现在最关键的不是再扩展功能，而是补齐设计图、检查一致性、优化图表和完成最终报告。
