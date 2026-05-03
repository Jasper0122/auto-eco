****************************************************
* analysis.do
* Purpose: Reproduce main empirical results for Auto-Eco demo
****************************************************

clear all
set more off
version 17

global project_dir "C:\Users\zongr\Documents\auto-eco\demo_eco"
cd "$project_dir"
capture log close
log using "analysis.log", replace text

cap which reghdfe
if _rc ssc install reghdfe, replace
cap which esttab
if _rc ssc install estout, replace
cap which winsor2
if _rc ssc install winsor2, replace

import delimited "broadband_china.csv", clear encoding(UTF-8)

global y "ln_tfp"
global x "did"
global id "county_id"
global time "year"
global ctrls "ln_gdp ln_population ln_fiscal gov_ratio urban_ratio"

drop if missing($y, $x, $id, $time)
xtset $id $time

estpost summarize ln_tfp ln_patent ln_export did $ctrls
esttab using "tables/table1_descriptive_stata.rtf", replace cells("count mean sd p25 p75 min max")

eststo clear
reghdfe $y $x $ctrls, absorb($id $time) vce(cluster $id)
eststo baseline
esttab baseline using "tables/table2_baseline_stata.rtf", replace se star(* 0.10 ** 0.05 *** 0.01)

gen event_time = year - first_treat_year
forvalues k = -4/4 {
    if `k' != -1 {
        local nm = cond(`k' < 0, "event_m" + string(abs(`k')), "event_" + string(`k'))
        gen `nm' = (event_time == `k' & treated == 1)
    }
}
reghdfe ln_tfp event_m4 event_m3 event_m2 event_0 event_1 event_2 event_3 event_4 $ctrls, absorb($id $time) vce(cluster $id)
eststo event
esttab event using "tables/table3_event_study_stata.rtf", replace se star(* 0.10 ** 0.05 *** 0.01)

winsor2 ln_tfp, cuts(1 99) suffix(_w)
reghdfe ln_tfp_w did $ctrls, absorb($id $time) vce(cluster $id)
eststo robust_w
reghdfe ln_tfp did $ctrls if event_time != 0, absorb($id $time) vce(cluster $id)
eststo robust_drop
esttab robust_w robust_drop using "tables/table4_robustness_stata.rtf", replace se star(* 0.10 ** 0.05 *** 0.01)

reghdfe ln_patent did $ctrls, absorb($id $time) vce(cluster $id)
eststo mech1
reghdfe ln_tfp did ln_patent $ctrls, absorb($id $time) vce(cluster $id)
eststo mech2
esttab mech1 mech2 using "tables/table5_mechanism_stata.rtf", replace se star(* 0.10 ** 0.05 *** 0.01)

log close
****************************************************
