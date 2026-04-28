


*转换年份格式
 gen Date_stata = date(Date, "YMD") 
 format Date_stata %td   
 gen year = year(Date_stata)


*加总同年份多个观测值

* 1. 创建一个汇总变量，将每个企业每年的 Enrelcost 求和
gen total_Enrelcost = .

* 2. 按照企业代码和年份分组，并计算 Enrelcost 的总和
bysort code year (Enrelcost): replace total_Enrelcost = sum(Enrelcost)

* 3. 获取每组的总和值
bysort code year (Enrelcost): replace total_Enrelcost = total_Enrelcost[_N]

* 4. 检查结果
list code year Enrelcost total_Enrelcost if _n <= 20
