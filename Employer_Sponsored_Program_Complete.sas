/*==========================================================================================
PROGRAM:    Employer_Sponsored.sas
OBJECTIVE:  Estimate annual employer-sponsored health care expenditures by disease category
            (CCSR) for the Health Care Satellite Account (HCSA), covering years 2000-2023.

AUTHORS:    Health Care Satellite Account Team, Bureau of Economic Analysis (BEA)
CREATED:    Original version pre-dates this documentation
UPDATED:    March 21, 2026

RUN TIME:   Approximately 1 week on BEA servers

============================================================================================
OVERVIEW
============================================================================================
The HCSA redefines health care spending by disease (e.g., cost of heart conditions) rather 
than by service location (e.g., cost of a hospital visit). This program produces the 
employer-sponsored insurance portion of the HCSA.

The program has seven major processing phases:

  PHASE 1 (Steps 1-12):   Population Weights
                           Combine Census CPS populations with MEPS insurance enrollment
                           to produce CPS-adjusted private-insurance population counts by
                           age-bucket x sex x region.

  PHASE 2 (Steps 13-21):  MarketScan Sample Selection & Person Weights
                           Filter MarketScan enrollees (>=360 days enrolled, has Rx plan,
                           not capitated, constant contributor). Compute person-level 
                           weights = (CPS-adjusted private pop) / (MarketScan enrollees)
                           within age-bucket x sex x region cells.

  PHASE 3 (Steps 22-49):  SSR Rebate Infrastructure
                           Build an NDC-level crosswalk of SSR Health discount rates for
                           retail-pharmacy drugs. Physician-administered drugs (identified
                           via HCPCS codes from CMS & Palmetto) are excluded from rebates.
                           Pre-2007 rebate dollars are backcast via linear interpolation.

  PHASE 4 (Steps 50-62):  MEPS NDC-to-CCSR Crosswalk
                           Since MarketScan Rx claims lack diagnoses, this phase builds a
                           bridge from NDC codes to CCSR disease categories using MEPS
                           prescribed medicines data. Pre-2016 MEPS uses CCS codes 
                           (converted to CCSR); 2016+ uses CCSR directly.

  PHASE 5 (Steps 63-93):  MarketScan Claims Processing & Trogdon Regressions
                           The computational core. For each year x tagging cohort:
                             (a) Merge IP/OP claims with ICD-to-CCSR crosswalks
                             (b) Weight and aggregate IP/OP spending by CCSR
                             (c) Apply SSR rebates to Rx claims (post-2007)
                             (d) Run Trogdon log-linear regressions to allocate Rx 
                                 spending across diseases
                             (e) Combine IP/OP and Rx spending by CCSR

  PHASE 6 (Steps 93z-200): Tag Blending & Imputation
                           MarketScan tagging cohorts change over time. For years with only
                           one tag, impute what the preferred tag would have produced by
                           chaining year-over-year growth rates from the available tag.
                           Break years at 2004 and 2011 are handled explicitly.

  PHASE 7 (Steps 201-214): NHEA Benchmarking
                           Stack all year-CCSR estimates. Compute each CCSR's share of
                           total MarketScan spending. Apply shares to the NHEA employer-
                           sponsored health care total (private + OOP for hospitals,
                           physician/clinical, other professional, home health, and Rx).
                           Produces the final output: NHEA-controlled dollars, episodes,
                           and cost-per-case by CCSR x year.

============================================================================================
DATA SOURCES (see documentation for download instructions)
============================================================================================
  1. Census CPS        - Population estimates by age, sex, state (vintage files)
  2. MEPS               - Full-year consolidated, medical conditions, prescribed medicines,
                          and appendix files (for insurance weights & NDC-CCSR crosswalk)
  3. MarketScan         - Commercial Claims: Inpatient (CCAES), Outpatient (CCAEO),
                          Prescription (CCAED), Enrollment (CCAEA), and Tagging files
  4. SSR Health         - NDC lookup (Prod.NDCLookup) and discount rates (Prod.GTN)
  5. CCSR Crosswalks    - ICD-9/10 to CCSR (from AHRQ), CCS-to-CCSR bridge
  6. HCPCS Crosswalks   - CMS alpha-numeric HCPCS files, Palmetto NDC-HCPCS crosswalks
  7. NHEA               - Tables 7, 8, 11, 14, 16 (service-category spending),
                          Table 21 (employer-sponsored vs. direct-purchase split)
  8. RedBook            - Drug reference (bundled with MarketScan) for NDC-to-name matching

============================================================================================
ANNUAL UPDATE CHECKLIST
============================================================================================
There are 33 locations marked "UPDATE HERE" that must be modified when adding a new year.
They are grouped by phase:

  SETUP & PATHS:
    #1  %Let VENDYEAR       - Census population vintage year
    #2  %Let CENYR          - Census base year (e.g., 2020 for the 2020 Census)
    #3  %Let SHORT_YEAR     - 2-digit new HCSA estimation year
    #4  %Let BLEND_NEWYEAR  - 4-digit new HCSA estimation year
    #5  %Let BASEYR         - Benchmark year for index calculations (NIPA Table 2.4.5)
    #6  LOG path            - Where to save log files
    #7  OUTPUTS path        - Where to save output files
    #8  INPUTS path         - Where input data are stored
    #9  MKTxx libnames      - Add new MarketScan year library reference

  PHASE 1 (CPS/MEPS weights):
    #10 CPS stacking        - At each new Census, ensure each stack represents a new vintage
    #11 MEPS macro calls    - Add new %MEPS_INS_POP call for the new year
    #12 CPS sort            - Reference the latest CPS stack dataset name

  PHASE 2 (MarketScan sample & weights):
    #13-#16 TAG ranges      - Update tagging file variable names and ranges
    #17 TAG macro calls     - Add new %TAG call for the new year
    #18-#19 Stacking        - Add new year to the A and B enrollment stacks

  PHASE 3 (SSR/HCPCS):
    #20-#22 SSR imports     - Update SSR file paths (net sales, discount rates, NDCs)
    #23 RedBook stacking    - Add new year's RedBook
    #24 CMS HCPCS imports   - Add new year's HCPCS file
    #25 Palmetto imports    - Add new year's Palmetto NDC-HCPCS crosswalk
    #26-#27 MarketScan IP/OP/Rx stacking - Add new year's claims for drug-setting comparison

  PHASE 4 (MEPS NDC-CCSR):
    #28 SSR filler years    - Add new year to the filler dataset
    #29 MEPS CCSR calls     - Add new %MEPS_NDC_CCSR_XWALK call for the new year

  PHASE 5 (Claims processing):
    #30 Claims macro calls  - Add new %marketscan_claims call for the new year

  PHASE 6/7 (Blending & benchmarking):
    #31 Imputation logic    - Update tag-blending steps if tagging base changes
    #32-#33 Final stacking  - Add new year to the _201_ stack and update tag references

============================================================================================
IMPORTANT NOTES FOR NEW USERS
============================================================================================
  - Many intermediate steps are wrapped in INTENTIONALLY COMMENTED OUT blocks. These are 
    expensive operations (hours to days) that write permanent datasets to the INPUTS library.
    They only need re-running when source data change. When running the program end-to-end
    for the first time, you MUST uncomment these blocks.

  - The program uses a numbered step convention: _01_, _02_, etc. Steps within macros
    share numbers across macro calls (e.g., _63_ is created for every year). The work
    library gets very large; periodic cleanup steps (proc datasets delete) manage this.

  - The tagging file logic (Tags A through D) handles the fact that MarketScan enrollees 
    are tracked across overlapping multi-year windows. Years at the boundary of two tagging
    windows ("break years") produce two estimates that are blended in Phase 6.

  - Dataset naming convention: _NN_descriptivename[YEAR]_[TAG]
    e.g., _66_mktscn_weighted_ipop2021_A = step 66, MarketScan weighted IP/OP, year 2021,
    tag cohort A.

============================================================================================
BEGIN PROGRAM
============================================================================================*/

/*------------------------------------------------------------------------------------------
OBJECTIVE: Employer-sponsored exenditure by YEAR-CCSR

"UPDATE HERE" COUNT: 33

Run time: 1 week
--------------------------------------------------------------------------------------------*/

/*==========================================================================================
SETUP: Log routing & global macro variables
==========================================================================================*/

*Need this log command because otherwise the log window is too small to hold this code;
proc printto 
log="\\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Macros\KFF\Employer_sponsored\Logs\Employer_sponsored &SYSDATE9..log" new; 
run; 

/*------------------------------------------------------------------------------------------
GLOBAL PARAMETERS
  - VENDYEAR:        Census vintage year (the year of the population estimate file)
  - CENYR:           The Census base year (2020 = 2020 decennial Census)
  - SHORT_YEAR:      2-digit version of the newest HCSA year (used in dataset names)
  - BLEND_FIRSTYEAR: First year of the HCSA time series (always 2000)
  - BLEND_NEWYEAR:   Last/newest year of the HCSA time series
  - NUM:             Number of CCSR categories (543 as of CCSR v2023.1)
  - BASEYR:          Base year for Laspeyres/Paasche price index calculations
------------------------------------------------------------------------------------------*/
%Let VENDYEAR=2024; *<-UPDATE HERE #1, year of new vintage;
%Let CENYR=2020; *<-UPDATE HERE #2, census year at the time of running this program. For example, if running this program in y2021, then censusyear=2020;
%Let SHORT_YEAR = 23; *<-UPDATE HERE #3, with the 2 digit new year we're trying to estimate for the HCSA;
%Let BLEND_FIRSTYEAR=2000;
%Let BLEND_NEWYEAR=2023; *<-UPDATE HERE #4, with the new year we're trying to estimate for the HCSA;
%Let NUM=543; *number of CCSRs;
%Let BASEYR=2017; *<-UPDATE HERE #5, with the benchmark year in NIPA table 2.4.5;

/*------------------------------------------------------------------------------------------
LIBRARY REFERENCES
  - CPSCURR:  Census population estimate files (vintage-specific folder)
  - LOG:      Log output destination
  - OUTPUTS:  Final output datasets and Excel exports
  - INPUTS:   Pre-processed crosswalks, weights, and intermediate saved datasets
  - MEPS:     Raw MEPS data files (SAS transport format, unzipped)
  - MKTAG:    MarketScan tagging files (identify constant contributors across years)
  - MKTxx:    MarketScan claims data, one library per year or year-range
              Note: library names vary because data arrived in different batches over time.
              MKT007  = years 2000-2007
              MKT08   = 2008
              MKT910  = 2009-2010 (originally 2009-2011)
              MKT11   = 2011
              MKT12+  = one library per year from 2012 onward
------------------------------------------------------------------------------------------*/
%Let CPSCURR= \\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Census_population\Vintage&VENDYEAR.\;
Libname CPSCURR "&CPSCURR.";
%Let LOG = \\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Macros\KFF\Employer_sponsored\Logs\; *<-UPDATE HERE #6, a location to save logs;
Libname LOG	"&LOG.";
Libname OUTPUTS "\\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Macros\KFF\Employer_sponsored\Outputs\"; *<-UPDATE HERE #7, a location to save outputs;
Libname INPUTS "\\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Macros\KFF\Employer_sponsored\Inputs\"; *<-UPDATE HERE #8, a location for input data;
Libname MEPS "\\serv532a\Research2\No_Backup\HCSA\Read_in_Raw_Data\";
Libname MKTAG "\\serv532b\Research3\No_Backup\HCSA\Tagging_File";
Libname MKT007 "\\SERV532B\Research2\No_Backup\HCSA\Market_Scan\";
Libname MKT08 "\\SERV532B\Research2\No_Backup\HCSA\08updates\";	
Libname MKT910 "\\SERV532B\Research2\No_Backup\HCSA\MarketScan09_11\";
Libname MKT11 "\\SERV532B\Research2\No_Backup\HCSA\MarketScan11\"; 
Libname MKT12 "\\SERV532B\Research2\No_Backup\HCSA\MarketScan12\"; 
Libname MKT13 "\\SERV532B\Research2\No_Backup\HCSA\MarketScan13\"; 
Libname MKT14 "\\SERV532B\Research2\No_Backup\HCSA\MarketScan2014\"; 
Libname MKT15 "\\SERV532B\Research2\No_Backup\HCSA\MarketScan2015\";
Libname MKT16 "\\SERV532B\Research2\No_Backup\HCSA\MarketScan2016\"; 
Libname MKT17 "\\serv532B\Research2\No_Backup\HCSA\MarketScan2017\"; 
Libname MKT18 "\\serv532B\Research2\No_Backup\HCSA\MarketScan2018\";
Libname MKT19 "\\serv532b\Research2\No_Backup\HCSA\Marketscan2019\version_b\";
Libname MKT20 "\\serv532b\Research2\No_Backup\HCSA\Marketscan2020\";
Libname MKT21 "\\serv532b\Research2\No_Backup\HCSA\Marketscan2021\";
Libname MKT22 "\\serv532b\Research2\No_Backup\HCSA\Marketscan2022\";
Libname MKT23 "\\serv532b\Research2\No_Backup\HCSA\Marketscan2023\";
*^^UPDATE HERE #9, with new locations of marketscan data;


/*##########################################################################################
##                                                                                        ##
##   PHASE 1: POPULATION WEIGHTS                                                          ##
##   Steps 1-12                                                                           ##
##                                                                                        ##
##   PURPOSE: Construct CPS-adjusted population counts for the privately insured           ##
##   population, stratified by age-bucket x sex x region. These weights correct for        ##
##   known inconsistencies in MEPS population weights (especially around 2000 and 2010     ##
##   Census changeovers that caused discontinuous jumps in MEPS weights).                  ##
##                                                                                        ##
##   LOGIC:                                                                                ##
##     1. Import Census CPS civilian population estimates by age x sex x state             ##
##     2. Assign 12 age buckets (0, 1-17, 18-24, ..., 85+)                                ##
##     3. Aggregate population by region x sex x age-bucket                                ##
##     4. Transpose to long format (one row per region x sex x age-bucket x year)          ##
##     5. From MEPS, compute total/Medicare/private populations in matching cells           ##
##     6. Create adjustment ratio = CPS_pop / MEPS_pop                                    ##
##     7. CPS-adjusted private pop = adjustment_ratio * MEPS_private_pop                   ##
##                                                                                        ##
##   OUTPUT: INPUTS.cps_meps_pop_1999_v{VENDYEAR} with adj_cps_priv by cell               ##
##                                                                                        ##
##########################################################################################*/

/*------------------------------------------------------------------------------------------
Step 1: Import Census Population Estimates
  - Source: Census Bureau, State Population by Characteristics (SC-EST series)
  - The file contains civilian population estimates by single year of age, sex, and state
  - Variable naming: POPEST{YEAR} contains the population estimate for that year
  - The "region" variable maps states to Census regions (1=NE, 2=MW, 3=S, 4=W)
------------------------------------------------------------------------------------------*/
*1) Import Census population estimates;
proc import
	datafile="&CPSCURR.sc-est&VENDYEAR.-agesex-civ.csv"
	dbms=csv
	replace
	out=_01_cps_weights_post&CENYR._v&VENDYEAR.;
run;

/*------------------------------------------------------------------------------------------
Step 2: Assign Age Buckets
  - Maps single-year ages into 12 age groups used throughout the program
  - age=999 is a total row in the Census file and is dropped
  - These buckets match the stratification used in MEPS and MarketScan weighting

  Age Bucket Definitions:
    1  = Age 0 (infants)          7  = 55-64
    2  = 1-17                     8  = 65-69
    3  = 18-24                    9  = 70-74
    4  = 25-34                    10 = 75-79
    5  = 35-44                    11 = 80-84
    6  = 45-54                    12 = 85+
------------------------------------------------------------------------------------------*/
*2) Assign age buckets;
data _02_agebucks_v&VENDYEAR.;
	set _01_cps_weights_post&CENYR._v&VENDYEAR.;
	if age=999 then delete;
	if age=0 then age_buck=1;
	else if age>=1 and age<=17 then age_buck=2;
	else if age>=18 and age<=24 then age_buck=3;
	else if age>=25 and age<=34 then age_buck=4;
	else if age>=35 and age<=44 then age_buck=5;
	else if age>=45 and age<=54 then age_buck=6;
	else if age>=55 and age<=64 then age_buck=7;
	else if age>=65 and age<=69 then age_buck=8;
	else if age>=70 and age<=74 then age_buck=9;
	else if age>=75 and age<=79 then age_buck=10;
	else if age>=80 and age<=84 then age_buck=11;
	else age_buck=12;
run;

/*------------------------------------------------------------------------------------------
Step 3: Aggregate Population by Region x Sex x Age Bucket
  - Sums all POPEST variables (one per year) across states within each cell
  - Excludes sex=0 (total for both sexes) and state=0 (national total)
  - Output has one row per region x sex x age_buck, with columns for each year
------------------------------------------------------------------------------------------*/
*3) Sum population counts by region-sex-agebuckets;
proc means
	data=_02_agebucks_v&VENDYEAR. (where=(sex ne 0 & state ne 0)) noprint nway;
	class region sex age_buck;
	var popest:;
	output out=_03_agebuck_sums_v&VENDYEAR. (drop=_:) sum=;
run;

/*------------------------------------------------------------------------------------------
Step 4: Remove Records with Missing Classification Variables
  - Safety check: drops any rows where region, sex, or age_buck is missing
------------------------------------------------------------------------------------------*/
*4) Discard missing observations;
data _04_clean_agebuck_sums_v&VENDYEAR.;
	set _03_agebuck_sums_v&VENDYEAR.;
	if region= . then delete;
	if sex= . then delete;
	if age_buck= . then delete;
run;

proc sort
	data=_04_clean_agebuck_sums_v&VENDYEAR.;
	by region age_buck sex;
run;

/*------------------------------------------------------------------------------------------
Step 5: Transpose from Wide to Long
  - Converts from one column per year (POPEST2000, POPEST2001, ...) to one row per year
  - After transpose: _NAME_ contains the original variable name (e.g., "POPEST2021")
                     COL1 contains the population count
------------------------------------------------------------------------------------------*/
*5) Transpose to long;
proc transpose
	data= _04_clean_agebuck_sums_v&VENDYEAR.
	out= _05_transp_v&VENDYEAR.;
	by region age_buck sex;
	var popest:;
run;

/*------------------------------------------------------------------------------------------
Steps 5-6 (COMMENTED OUT): Save & Stack CPS Vintages
  - These steps save the current vintage and stack it with historical population files
  - Each Census decade has its own source file (1999, 2000-2010, 2010-2019, 2020+)
  - IMPORTANT: At every new decennial Census, the user must ensure each stack represents
    the appropriate vintage. The stacking logic may need to change.
  - Only re-run these when a new Census vintage file is obtained.
------------------------------------------------------------------------------------------*/
/*INTENTIONALLY COMMENTED OUT (below). Re-run to writeover only if necessary.
*5) Clean & save latest vintage population;
data INPUTS.cps_weights_&CENYR._&VENDYEAR.;
    set _05_transp_v&VENDYEAR.;
    year = input(substr(_name_, 7, 4), 4.);
    drop _name_ ;
    rename col1 = popestimate;
run;

*6) Stack the latest vintage alongside old population counts;
data INPUTS.cps_weights_1999_v&VENDYEAR.;
	set INPUTS.cps_weights_1999 
		INPUTS.cps_weights_2000_2010 (where=(year<2010))
		INPUTS.cps_weights_2010_2019 (rename=(popestimate=population))
		INPUTS.cps_weights_&CENYR._&VENDYEAR. (rename=(popestimate=population)); 
run;*^^UPDATE HERE #10, at every new census year, the user must ensure each new stack represents a new census year.;
^^INTENTIONALLY COMMENTED OUT^^*/

/*------------------------------------------------------------------------------------------
Step 7: Extract Insurance Populations from MEPS
  MACRO: %MEPS_INS_POP
  
  PURPOSE: For each MEPS survey year, extract three population subsets:
    (a) Total population    - all MEPS respondents (for the denominator of the CPS ratio)
    (b) Medicare population - those with mcrev=1 (Medicare coverage ever during the year)
    (c) Private population  - those with prvev=1 AND mcrev=2 (private coverage, NO Medicare)
  
  PARAMETERS:
    YEAR2 = 2-digit year suffix used in MEPS variable names (e.g., "21" for 2021)
    FY    = MEPS full-year consolidated file number (e.g., h233 for 2021)
    YEAR4 = 4-digit calendar year
  
  KEY MEPS VARIABLES:
    perwt{YY}f    = Person-level survey weight (final)
    age{YY}x      = Age at end of year
    region{YY}    = Census region (1-4)
    mcrev{YY}     = Medicare coverage ever during year (1=Yes, 2=No)
    prvev{YY}     = Private insurance coverage ever during year (1=Yes, 2=No)
  
  NOTE ON PRIVATE POPULATION: We define private as prvev=1 AND mcrev=2. This excludes 
  dual-eligible (Medicare + private supplement) individuals, since they are counted in 
  the Medicare population. This avoids double-counting.
  
  NOTE ON AGE BUCKETS: The private population subset (_07_MEPSprivweights) only keeps
  age_buck<=7 (ages 0-64) because employer-sponsored coverage is primarily for the 
  under-65 population. The total and Medicare populations keep all age buckets.
  
  FILE NUMBER REFERENCE (add new years here):
    Year  YEAR2  FY    |   Year  YEAR2  FY
    1999  99     38    |   2012  12     155
    2000  00     50    |   2013  13     163
    2001  01     60    |   2014  14     171
    2002  02     70    |   2015  15     181
    2003  03     79    |   2016  16     192
    2004  04     89    |   2017  17     201
    2005  05     97    |   2018  18     209
    2006  06     105   |   2019  19     216
    2007  07     113   |   2020  20     224
    2008  08     121   |   2021  21     233
    2009  09     129   |   2022  22     243
    2010  10     138   |   2023  23     251
    2011  11     147   |
------------------------------------------------------------------------------------------*/
*7) Separately capture total, medicare, and privately insured respondents from MEPS;
%macro MEPS_INS_POP (YEAR2=, FY=, YEAR4=);
	data _07_MEPStot_pop_&YEAR4.;
		set MEPS.h&FY. (keep=dupersid perwt&YEAR2.f sex age&YEAR2.x region&YEAR2. rename=(perwt&YEAR2.f=perwt age&YEAR2.x=age region&YEAR2.=region));
		year=&YEAR4.;
		if age =0 then age_buck=1;
		else if age>=1 and age<=17 then age_buck=2;
		else if age>=18 and age<=24 then age_buck=3;
		else if age>=25 and age<=34 then age_buck=4;
		else if age>=35 and age<=44 then age_buck=5;
		else if age>=45 and age<=54 then age_buck=6;
		else if age>=55 and age<=64 then age_buck=7;
		else if age>=65 and age<=69 then age_buck=8;
		else if age>=70 and age<=74 then age_buck=9;
		else if age>=75 and age<=79 then age_buck=10;
		else if age>=80 and age<=84 then age_buck=11;
		else if age>=85 then age_buck=12;
	run;

	data _07_MEPSmdcrweights&YEAR4.;
		set MEPS.h&FY. (keep=mcrev&YEAR2. DUPERSID PERWT&YEAR2.F sex AGE&YEAR2.X region&YEAR2. rename=(mcrev&YEAR2.=mcrev perwt&YEAR2.f=perwt age&YEAR2.x=age region&YEAR2.=region));
		year=&YEAR4.;
		if mcrev=1;
		if age =0 then age_buck=1;
		else if age>=1 and age<=17 then age_buck=2;
		else if age>=18 and age<=24 then age_buck=3;
		else if age>=25 and age<=34 then age_buck=4;
		else if age>=35 and age<=44 then age_buck=5;
		else if age>=45 and age<=54 then age_buck=6;
		else if age>=55 and age<=64 then age_buck=7;
		else if age>=65 and age<=69 then age_buck=8;
		else if age>=70 and age<=74 then age_buck=9;
		else if age>=75 and age<=79 then age_buck=10;
		else if age>=80 and age<=84 then age_buck=11;
		else if age>=85 then age_buck=12;
	run;

	data _07_MEPSprivweights&YEAR4.;
		set MEPS.h&FY. (keep=dupersid perwt&YEAR2.F sex age&YEAR2.X prvev&YEAR2. region&YEAR2. mcrev&YEAR2. rename=(perwt&YEAR2.f=perwt age&YEAR2.x=age prvev&YEAR2.=prvev region&YEAR2.=region mcrev&YEAR2.=mcrev));
		year=&YEAR4.;
		if prvev=1 and mcrev=2;
		if age =0 then age_buck=1;
		else if age>=1 and age<=17 then age_buck=2;
		else if age>=18 and age<=24 then age_buck=3;
		else if age>=25 and age<=34 then age_buck=4;
		else if age>=35 and age<=44 then age_buck=5;
		else if age>=45 and age<=54 then age_buck=6;
		else if age>=55 and age<=64 then age_buck=7;
	run;
%mend;
%MEPS_INS_POP(YEAR2=99, FY=38, YEAR4=1999);
%MEPS_INS_POP(YEAR2=00, FY=50, YEAR4=2000);
%MEPS_INS_POP(YEAR2=01, FY=60, YEAR4=2001);
%MEPS_INS_POP(YEAR2=02, FY=70, YEAR4=2002);
%MEPS_INS_POP(YEAR2=03, FY=79, YEAR4=2003);
%MEPS_INS_POP(YEAR2=04, FY=89, YEAR4=2004);
%MEPS_INS_POP(YEAR2=05, FY=97, YEAR4=2005);
%MEPS_INS_POP(YEAR2=06, FY=105, YEAR4=2006);
%MEPS_INS_POP(YEAR2=07, FY=113, YEAR4=2007);
%MEPS_INS_POP(YEAR2=08, FY=121, YEAR4=2008);
%MEPS_INS_POP(YEAR2=09, FY=129, YEAR4=2009);
%MEPS_INS_POP(YEAR2=10, FY=138, YEAR4=2010);
%MEPS_INS_POP(YEAR2=11, FY=147, YEAR4=2011);
%MEPS_INS_POP(YEAR2=12, FY=155, YEAR4=2012);
%MEPS_INS_POP(YEAR2=13, FY=163, YEAR4=2013);
%MEPS_INS_POP(YEAR2=14, FY=171, YEAR4=2014);
%MEPS_INS_POP(YEAR2=15, FY=181, YEAR4=2015);
%MEPS_INS_POP(YEAR2=16, FY=192, YEAR4=2016);
%MEPS_INS_POP(YEAR2=17, FY=201, YEAR4=2017);
%MEPS_INS_POP(YEAR2=18, FY=209, YEAR4=2018);
%MEPS_INS_POP(YEAR2=19, FY=216, YEAR4=2019);
%MEPS_INS_POP(YEAR2=20, FY=224, YEAR4=2020);
%MEPS_INS_POP(YEAR2=21, FY=233, YEAR4=2021);
%MEPS_INS_POP(YEAR2=22, FY=243, YEAR4=2022);
%MEPS_INS_POP(YEAR2=23, FY=251, YEAR4=2023);
*^^UPDATE HERE #11, with the new year we're trying to estimate for the HCSA;

/*------------------------------------------------------------------------------------------
Steps 8-9: Stack & Aggregate MEPS Populations
  - Stack all year-specific MEPS datasets into three master files: total, Medicare, private
  - Then sum person weights (perwt) by year x age_buck x sex x region to get weighted 
    population counts
  - Output variables:
      wt_pop   = weighted population (sum of perwt)
      unwt_pop = unweighted count of respondents (n)
      pop_mdcr = weighted Medicare population
      pop_priv = weighted private (non-Medicare) population
------------------------------------------------------------------------------------------*/
*8) Stack MEPS' total across all years;
data _08_totweights; 
	set _07_MEPStot_pop_:; 
run; 

*8) Stack MEPS' medicare across all years;
data _08_mdcrweights; 
	set _07_MEPSmdcrweights:; 
run; 

*8) Stack MEPS' private across all years;
data _08_privweights; 
	set _07_MEPSprivweights:; 
run;

*9) Sum total person weights by year-age-sex-region;
proc means
	data=_08_totweights (where=(region>0)) noprint nway;
	var perwt;
	class year age_buck sex region;
	output out=_09_tot_pop_MEPS (drop= _:) sum=wt_pop n=unwt_pop;
run;

*9) Sum medicare person weights by year-age-sex-region;
proc means
	data=_08_mdcrweights (where=(region > 0))noprint nway;
	var perwt;
	class year age_buck sex region;
	output out=_09_mdcr_pop (drop=_:) sum=pop_mdcr;
run;

*9) Sum private person weights by year-age-sex-region;
proc means
	data=_08_privweights (where=(region > 0))noprint nway;
	var perwt;
	class year age_buck sex region;
	output out=_09_priv_pop (drop=_:) sum=pop_priv;
run;

/*------------------------------------------------------------------------------------------
Step 10: Merge CPS with MEPS to Create CPS-Adjusted Population Weights
  - Merges CPS population, MEPS total population, MEPS private, and MEPS Medicare
    by year x age_buck x sex x region
  - Computes the CPS-to-MEPS adjustment ratio and applies it to each insurance category:
      adjust_ratio   = pop_cps / pop_MEPS
      adj_cps_priv   = adjust_ratio * pop_priv    (this is the key output for weighting)
      adj_cps_mdcr   = adjust_ratio * pop_mdcr
  - This corrects for the fact that MEPS population weights have known issues around
    Census changeover years, while CPS estimates are more stable
------------------------------------------------------------------------------------------*/
*10) Merge CPS with MEPS and save to Inputs;
proc sort
	data=INPUTS.cps_weights_1999_v&VENDYEAR.; 
	by year age_buck sex region; 
run; *^^UPDATE HERE #12, with latest stack of CPS data;

/*INTENTIONALLY COMMENTED OUT (below). Re-run to writeover only if necessary.
data INPUTS.cps_meps_pop_1999_v&VENDYEAR.;
	merge INPUTS.cps_weights_1999_v&VENDYEAR. (in=x rename=(population=pop_cps)) 
		  _09_tot_pop_MEPS(rename=(wt_pop=pop_MEPS) drop=unwt_pop)
		  _09_priv_pop (in=x)
		  _09_mdcr_pop;
	by year age_buck sex region;
	if x=1;
	if pop_priv=. then pop_priv=0;
	if pop_mdcr=. then pop_mdcr=0;
	pop_meps_oth=pop_MEPS-pop_priv-pop_mdcr;
	adjust_ratio=pop_cps/pop_MEPS;
	adj_cps_mdcr=adjust_ratio*pop_mdcr;
	adj_cps_priv=adjust_ratio*pop_priv;
	adj_cps_meps_oth=adjust_ratio*pop_meps_oth;
run;
^^INTENTIONALLY COMMENTED OUT^^*/

/*------------------------------------------------------------------------------------------
Steps 11-12: Prepare Medicare Weights for Under-65 Population
  - Aggregates CPS-adjusted Medicare population for age_buck<=7 (under 65) by sex x region
  - This is used later in the Medicare HCSA (not the employer-sponsored portion), but is
    computed here for convenience since the CPS-MEPS merge is already done
  - The final_weights dataset stacks the aggregated under-65 with the already-granular 65+
------------------------------------------------------------------------------------------*/
*11) Aggregate those under age of 65;
proc means
	data=INPUTS.cps_meps_pop_1999_v&VENDYEAR. (where=(age_buck <=7)) noprint nway;
	var adj_cps_mdcr;
	class sex region year;
	output out=_11_cps_meps_1 (drop=_:) sum=adj_cps_mdcr;
run;

/*INTENTIONALLY COMMENTED OUT (below). Re-run to writeover only if necessary.
*12) stack (under 65) with (over 65);
data INPUTS.final_weights_1999_v&VENDYEAR.;
	set _11_cps_meps_1 (in=x) 
	    INPUTS.cps_meps_pop_1999_v&VENDYEAR. (where=(age_buck>=8) keep=sex region year adj_cps_mdcr age_buck);
	if x=1 then age_buck=1;
run;
^^INTENTIONALLY COMMENTED OUT^^*/


/*##########################################################################################
##                                                                                        ##
##   PHASE 2: MARKETSCAN SAMPLE SELECTION & PERSON WEIGHTS                                ##
##   Steps 13-21 (the %TAG macro)                                                         ##
##                                                                                        ##
##   PURPOSE: From MarketScan enrollment files, select the analytic sample and compute     ##
##   person-level weights that allow MarketScan (a convenience sample) to represent the    ##
##   national employer-sponsored population.                                               ##
##                                                                                        ##
##   SAMPLE RESTRICTIONS (all must be met):                                                ##
##     1. Enrolled >= 360 days in the year (babies exempt)                                 ##
##     2. Has a prescription drug plan (rx="1")                                            ##
##     3. Not in a capitated plan (plntyp not in 4,7 for any month)                       ##
##        - BEA research shows cost estimates are unreliable for capitated enrollees       ##
##     4. Is a "constant contributor" (present in the tagging file)                        ##
##        - Tagging files track enrollees across multiple years, ensuring longitudinal     ##
##          consistency. Without this, the sample composition could shift year to year.    ##
##                                                                                        ##
##   TAGGING COHORTS:                                                                      ##
##   MarketScan releases tagging files that cover overlapping year ranges. We label them   ##
##   a, b, c, d. Each year is primarily assigned to one tag, but "break years" (where      ##
##   two tags overlap) get processed twice—once per tag—so we can blend estimates later.   ##
##                                                                                        ##
##     Tag  Variable Name    Tagging File            Covers (approx.)                      ##
##     a    In_2000_2005     2014                    2000-2004                              ##
##     b    In_2003_2015     2017b_ccae              2004-2011                              ##
##     c    In_2011_2016     2019_ccae               2011-2017                              ##
##     d    In_2014_2023     2014_2023_ccae          2016-2023                              ##
##                                                                                        ##
##   Break years (processed with two tags):                                                ##
##     2004: Tags a and b                                                                  ##
##     2011: Tags b and c                                                                  ##
##     2017: Tags c and d                                                                  ##
##                                                                                        ##
##   PERSON WEIGHT FORMULA:                                                                ##
##     weight = adj_cps_priv / enrollees                                                   ##
##   where adj_cps_priv is the CPS-adjusted private population from Phase 1 and            ##
##   enrollees is the MarketScan sample count, both within the same cell                   ##
##   (age_buck x sex x region).                                                            ##
##                                                                                        ##
##   BABY HANDLING: Babies (age=0) are exempt from the 360-day enrollment requirement      ##
##   but are only kept if at least one family member (same famid) passes all filters.      ##
##   Family ID is derived as the first 9 digits of the 11-digit ENROLID.                  ##
##                                                                                        ##
##########################################################################################*/

/*------------------------------------------------------------------------------------------
MACRO: %TAG
  Processes one year x tagging cohort combination through the full sample selection and
  weighting pipeline.

  PARAMETERS:
    FYR     = MarketScan file year suffix (e.g., "002" for 2000, "232" for 2023)
              This is an internal MarketScan identifier, NOT the calendar year.
    YEAR    = 4-digit calendar year (e.g., 2000, 2023)
    LIBLET  = Library reference for MarketScan data (e.g., MKT007, MKT23)
    TAGLET  = Tagging cohort letter (a, b, c, or d)

  MARKETSCAN FILE NAMING:
    CCAEA{FYR} = Enrollment/demographics file
    Key variables from CCAEA: ENROLID, MEMDAYS, AGE, YEAR, SEX, PLNTYP1-PLNTYP12,
                              RX, REGION, EGEOLOC, HLTHPLAN, MSA

  OUTPUTS:
    _20_enr_file_w_weight_cty{FYR}_{TAGLET} = One row per enrollee with person weight

  FYR REFERENCE TABLE (for finding the right MarketScan file suffix):
    Year  FYR   Library  |  Year  FYR   Library
    2000  002   MKT007   |  2012  121   MKT12
    2001  013   MKT007   |  2013  131   MKT13
    2002  023   MKT007   |  2014  141   MKT14
    2003  033   MKT007   |  2015  151   MKT15
    2004  045   MKT007   |  2016  161   MKT16
    2005  054   MKT007   |  2017  171   MKT17
    2006  063   MKT007   |  2018  181   MKT18
    2007  072   MKT007   |  2019  192   MKT19
    2008  081   MKT08    |  2020  201   MKT20
    2009  093   MKT910   |  2021  211   MKT21
    2010  102   MKT910   |  2022  221   MKT22
    2011  111   MKT11    |  2023  232   MKT23
------------------------------------------------------------------------------------------*/
%Macro TAG(FYR=, YEAR=, LIBLET=, TAGLET=);
	/* Determine which tagging variable and file to use based on cohort letter */
	%if &TAGLET. = a %then %do;
		%let tagged = In_2000_2005;*<-UPDATE HERE #13, first tagging range;
		%let tagfilename = 2014;
	%end;

	%if &TAGLET. = b %then %do;
		%let tagged = In_2003_2015;*<-UPDATE HERE #14, second tagging range;
		%let tagfilename = 2017b_ccae;
	%end;

	%if &TAGLET. = c %then %do;
		%let tagged = In_2011_2016;*<-UPDATE HERE #15, third tagging range;
		%let tagfilename = 2019_ccae; 
	%end;

	%if &TAGLET. = d %then %do;
		%let tagged = In_2014_2023;*<-UPDATE HERE #16, fourth tagging range;
		%let tagfilename = 2014_2023_ccae;
	%end;

	/*----------------------------------------------------------------------------------
	Step 13: Merge Enrollment with Tagging File & Apply Sample Restrictions
	  - Inner join on ENROLID between enrollment file and tagging file
	  - The tagging file variable (e.g., In_2000_2005) must equal 1
	  - Capitation check: if ANY month (plntyp1-plntyp12) is "4" or "7", drop the person
	    (plan types 4 and 7 are capitated arrangements)
	  - Rx check: must have rx="1" (prescription drug coverage)
	  - Enrollment check: memdays>=360 (babies age=0 are exempt, sent to _check dataset)
	  - Baby handling: babies go to _13_check; their parents are verified in steps 14-15
	  - famid = first 9 digits of the zero-padded 11-digit ENROLID (identifies families)
	----------------------------------------------------------------------------------*/
	*13) Merge admin with tags. Drop those without drug coverage, those in a capitated plan, and those who arent continuously enrolled (except babies);
	data _13_good&FYR. 
	 	 _13_check&FYR.;
			merge &LIBLET..ccaea&FYR. (in=x keep=memdays age year enrolid sex plntyp: rx  region egeoloc hlthplan msa) 
				  MKTAG.Bea_mscan_tagging_&TAGFILENAME. (in=y where=(&TAGGED.=1) keep=enrolid &TAGGED.);
			by enrolid;
			if x+y=2;
			%macro DropPlns;
				%do i=1 %to 12;
					if plntyp&I. in ("4","7") then capplan="1";
				%end;
			%mend; %DropPlns;
			if capplan="1" then delete; *Drop capitated people;
			if rx ne "1" then delete; *Drop those without RX plans;
			if memdays<360 and age>0 then delete; *Drop noncontinuously enrolled;
			check=0;

			*If they are a baby put them in a different data file to check if their parents are in the data;
			if age=0 then check=1;
			famid=substr(put(enrolid, z11.),1,9);
			if check=0 then output _13_good&FYR.;
			else if check=1 then output _13_check&FYR.;
			drop &TAGGED.;
	run;

	/*----------------------------------------------------------------------------------
	Steps 14-15: Validate Babies
	  - Get unique family IDs from the validated adult sample
	  - Keep babies only if their family ID matches a family in the adult sample
	  - This ensures babies have at least one qualified parent/guardian in our data
	----------------------------------------------------------------------------------*/
	*14) Unique families;
	proc sort
		data=_13_good&FYR. (keep=famid) 
		nodupkey
		out=_14_goodfam&FYR.;
		by famid;
	run;

	proc sort
		data=_13_check&FYR.; 
		by famid; 
	run;

	*15) Keep babies who have a family member in our sample;
	data _15_check_good&FYR.;
		merge _13_check&FYR. (in=x) 
			  _14_goodfam&FYR. (in=y);
		by famid;
		if x+y=2;
	run;

	/*----------------------------------------------------------------------------------
	Step 16: Combine Adults & Validated Babies, Assign Age Buckets
	  - Stacks qualified adults with validated babies
	  - Assigns age buckets (same 12-bucket scheme as Phase 1)
	  - NOTE: For the employer-sponsored population, only age_buck<=7 (under 65) is used
	  - sex and region are converted from character to numeric (sex1, region1)
	  - Creates one=1 as a counter variable for aggregation in step 17
	----------------------------------------------------------------------------------*/
	*16) Stack validated adults & validated babies;
	data _16_sample&FYR. (rename=(sex1=sex region1=region)); 
		set _13_good&FYR. 
			_15_check_good&FYR.;
		*Assign age buckets;
		if age =0 then age_buck=1;
		else if age>=1 and age<=17 then age_buck=2;
		else if age>=18 and age<=24 then age_buck=3;
		else if age>=25 and age<=34 then age_buck=4;
		else if age>=35 and age<=44 then age_buck=5;
		else if age>=45 and age<=54 then age_buck=6;
		else if age>=55 and age<=64 then age_buck=7;
		sex1=sex*1;
		region1=region*1;
		drop region sex;
		one=1;
	run;

	/*----------------------------------------------------------------------------------
	Step 17: Count Enrollees per Weighting Cell
	  - Counts the number of MarketScan enrollees in each age_buck x sex x year x region cell
	  - This count becomes the denominator in the person weight formula
	----------------------------------------------------------------------------------*/
	*17) Counts of enrollees in our sample;
	proc means
		data=_16_sample&FYR. noprint nway;
		var one;
		class age_buck sex year region;
		output out=_17_countsforweights_cty&FYR. n=enrollees;
	run;

	/*----------------------------------------------------------------------------------
	Steps 18-19: Merge CPS-Adjusted Population with MarketScan Enrollee Counts
	  - Retrieves adj_cps_priv from the Phase 1 output for the matching year
	  - Only keeps age_buck<=7 (under 65, the employer-sponsored population)
	  - Computes: weight = adj_cps_priv / enrollees
	    This means each MarketScan person "represents" that many people in the national
	    employer-sponsored population within their demographic cell.
	----------------------------------------------------------------------------------*/
	*19) Merge the MEPS population counts to mktscn samples enrollee count; 
	proc sort
		data=_17_countsforweights_cty&FYR.;
		by age_buck sex year region;
	run;

	proc sort
		data=INPUTS.cps_meps_pop_1999_v&VENDYEAR.
		out=_18_cps_meps_priv_v&VENDYEAR. (keep=age_buck sex year region adj_cps_priv where=(age_buck<=7));
		by age_buck sex year region;
	run;

	data _19_MEPSPopWeights_cty&FYR.;
		merge _17_countsforweights_cty&FYR. 
			  _18_cps_meps_priv_v&VENDYEAR. (where=(year=&year) rename=(adj_cps_priv=pop));
		by age_buck sex year region;
		weight=pop/enrollees;
	run;

	/*----------------------------------------------------------------------------------
	Step 20: Attach Person Weight to Each Enrollee
	  - Merges the cell-level weight back onto each individual enrollee record
	  - Output contains: enrolid, year, age, age_buck, region, sex, weight, and plan info
	  - This is the final enrollment file used in Phase 5 for claims processing
	----------------------------------------------------------------------------------*/
	*20) Merge the weight onto each persons;
	proc sort
		data=_16_sample&FYR.;
		by age_buck sex year region;
	run;

	proc sort
		data=_19_MEPSPopWeights_cty&FYR.;
		by age_buck sex year region;
	run;

	data _20_enr_file_w_weight_cty&FYR._&TAGLET.;
		merge _16_sample&FYR.
			  _19_MEPSPopWeights_cty&FYR.;
		by age_buck sex year region;
		keep year enrolid age age_buck region sex weight egeoloc hlthplan plntyp:;
	run;
%mend; 

/*------------------------------------------------------------------------------------------
%TAG Macro Calls: One per year x tagging cohort
  - Each row below processes one year with one tagging file
  - Break years appear twice (e.g., 2004 with tags a and b; 2011 with tags b and c)
  - The primary tag for each year is listed first; the secondary (break) tag is indented
  - When adding a new year, add a new %TAG call and ensure the TAGLET matches the 
    tagging file that covers that year
------------------------------------------------------------------------------------------*/
%TAG(FYR=002, YEAR=2000, LIBLET=MKT007, TAGLET=a);
%TAG(FYR=013, YEAR=2001, LIBLET=MKT007, TAGLET=a);
%TAG(FYR=023, YEAR=2002, LIBLET=MKT007, TAGLET=a);
%TAG(FYR=033, YEAR=2003, LIBLET=MKT007, TAGLET=a);
%TAG(FYR=045, YEAR=2004, LIBLET=MKT007, TAGLET=a);
	%TAG(FYR=045, YEAR=2004, LIBLET=MKT007, TAGLET=b);
%TAG(FYR=054, YEAR=2005, LIBLET=MKT007, TAGLET=b);
%TAG(FYR=063, YEAR=2006, LIBLET=MKT007, TAGLET=b);
%TAG(FYR=072, YEAR=2007, LIBLET=MKT007, TAGLET=b);
%TAG(FYR=081, YEAR=2008, LIBLET=MKT08, TAGLET=b);
%TAG(FYR=093, YEAR=2009, LIBLET=MKT910, TAGLET=b);
%TAG(FYR=102, YEAR=2010, LIBLET=MKT910, TAGLET=b);
%TAG(FYR=111, YEAR=2011, LIBLET=MKT11, TAGLET=b);
	%TAG(FYR=111, YEAR=2011, LIBLET=MKT11, TAGLET=c);
%TAG(FYR=121, YEAR=2012, LIBLET=MKT12, TAGLET=c);
%TAG(FYR=131, YEAR=2013, LIBLET=MKT13, TAGLET=c);
%TAG(FYR=141, YEAR=2014, LIBLET=MKT14, TAGLET=c);
%TAG(FYR=151, YEAR=2015, LIBLET=MKT15, TAGLET=c);
%TAG(FYR=161, YEAR=2016, LIBLET=MKT16, TAGLET=d);
%TAG(FYR=171, YEAR=2017, LIBLET=MKT17, TAGLET=c);
	%TAG(FYR=171, YEAR=2017, LIBLET=MKT17, TAGLET=d);
%TAG(FYR=181, YEAR=2018, LIBLET=MKT18, TAGLET=d);
%TAG(FYR=192, YEAR=2019, LIBLET=MKT19, TAGLET=d);
%TAG(FYR=201, YEAR=2020, LIBLET=MKT20, TAGLET=d);
%TAG(FYR=211, YEAR=2021, LIBLET=MKT21, TAGLET=d);
%TAG(FYR=221, YEAR=2022, LIBLET=MKT22, TAGLET=d);
%TAG(FYR=232, YEAR=2023, LIBLET=MKT23, TAGLET=d);
*^^UPDATE HERE #17, with the new year we're trying to estimate for the HCSA & any updates to tag ranges;

/*------------------------------------------------------------------------------------------
Step 21 (COMMENTED OUT): Stack All Enrollment Files Across Years
  - Creates two master enrollment datasets:
    (A) The PRIMARY stack: uses the best available tag for each year
        - Years 2000-2004 use tag a, 2005-2011 use tag b, 2012-2017 use tag c, 
          2016-2023 use tag d (with 2016 switching from c to d)
    (B) The SECONDARY stack: contains only the break-year alternate tags
        - 2004 tag b, 2011 tag c, 2017 tag d
  - Both stacks are used in Phase 5 claims processing and Phase 6 blending
  - NOTE: The tag assignments in the A stack represent which tagging cohort is the
    "primary" estimate for each year. This may change when new tagging files arrive.
------------------------------------------------------------------------------------------*/
/*INTENTIONALLY COMMENTED OUT (below). Re-run to writeover only if necessary.
*21) stack all years (type_a);
data INPUTS.enr_file_w_weight_00_&SHORT_YEAR._A;
	length HLTHPLAN $8. EGEOLOC $4. ENROLID 8. AGE 8. YEAR 8. PLNTYP1 8. PLNTYP2 8. PLNTYP3 8. PLNTYP4 8. PLNTYP5 8. PLNTYP6 8. PLNTYP7 8. PLNTYP8 8. PLNTYP9 8. PLNTYP10 8. PLNTYP11 8. PLNTYP12 8.;
	set _20_enr_file_w_weight_cty002_a
		_20_enr_file_w_weight_cty013_a
		_20_enr_file_w_weight_cty023_a
		_20_enr_file_w_weight_cty033_a
		_20_enr_file_w_weight_cty045_a
		_20_enr_file_w_weight_cty054_b
		_20_enr_file_w_weight_cty063_b
		_20_enr_file_w_weight_cty072_b
		_20_enr_file_w_weight_cty081_b
		_20_enr_file_w_weight_cty093_b
		_20_enr_file_w_weight_cty102_b
		_20_enr_file_w_weight_cty111_b
		_20_enr_file_w_weight_cty121_c
		_20_enr_file_w_weight_cty131_c
		_20_enr_file_w_weight_cty141_c
		_20_enr_file_w_weight_cty151_c
		_20_enr_file_w_weight_cty161_d
		_20_enr_file_w_weight_cty171_c
		_20_enr_file_w_weight_cty181_d
		_20_enr_file_w_weight_cty192_d
		_20_enr_file_w_weight_cty201_d
		_20_enr_file_w_weight_cty211_d
		_20_enr_file_w_weight_cty221_d
		_20_enr_file_w_weight_cty232_d;
run;*^^UPDATE HERE #18, with the new year we're trying to estimate for the HCSA & any updates to tag ranges;

*21) stack all years (non type_a);
data INPUTS.enr_file_w_weight_00_&SHORT_YEAR._B;
	set _20_enr_file_w_weight_cty045_b
		_20_enr_file_w_weight_cty111_c
		_20_enr_file_w_weight_cty171_d;
run;*^^UPDATE HERE #19, with appropriate tags;
^^INTENTIONALLY COMMENTED OUT^^*/


/*##########################################################################################
##                                                                                        ##
##   PHASE 3: SSR REBATE INFRASTRUCTURE                                                   ##
##   Steps 22-49                                                                           ##
##                                                                                        ##
##   PURPOSE: Build an NDC-level crosswalk of manufacturer rebate discount rates from      ##
##   SSR Health data, so that retail prescription drug spending can be adjusted to remove   ##
##   manufacturer rebates. Rebates are already embedded in IP/OP drug payments (the claim  ##
##   amount reflects net-of-rebate pricing), but retail Rx claims report gross prices.     ##
##                                                                                        ##
##   KEY CONCEPT - RETAIL vs. PHYSICIAN-ADMINISTERED DRUGS:                                ##
##   Some drugs (e.g., chemotherapy infusions) are administered in clinics/hospitals and    ##
##   appear in IP/OP claims. Others (e.g., statins) are picked up at retail pharmacies     ##
##   and appear in Rx claims. For the former, rebates are already reflected in the claim   ##
##   payment. For the latter, we must manually subtract rebates. To distinguish them, we   ##
##   compare each drug's claims volume between IP/OP and Rx files. Drugs with >50% of     ##
##   claims in IP/OP are flagged as physician-administered and excluded from rebate adj.   ##
##                                                                                        ##
##   REBATE FORMULA (applied to retail Rx claims in Phase 5):                              ##
##     pay_netofrebate = (1 - gross_margin) * pay * (1 - avg_discount_rate)               ##
##                     + gross_margin * pay                                                ##
##   where gross_margin = 0.035 (3.5% retail pharmacy markup per USC research)             ##
##                                                                                        ##
##   PRE-2007 HANDLING: SSR data begin in 2007. For 2001-2006, rebate dollars are          ##
##   linearly interpolated from 2007 back to 2000 (where rebates are set to $0).          ##
##   This backcasting happens in Phase 6 (the %pre2007rebateadj macro).                   ##
##                                                                                        ##
##   SUB-PHASES:                                                                           ##
##     3A (Steps 21-23): Stack RedBook drug reference files, merge with SSR NDCs           ##
##     3B (Steps 24-29): Build HCPCS crosswalk from CMS + Palmetto files                  ##
##     3C (Steps 30-32): Cross-reference SSR products with HCPCS descriptions              ##
##     3D (Steps 33-41): Compare drug volumes between IP/OP and Rx to flag                ##
##                        physician-administered drugs (COMMENTED OUT - expensive)          ##
##     3E (Steps 42-49): Clean SSR discount rates, merge with NDCs, drop flagged drugs     ##
##                                                                                        ##
##########################################################################################*/

/*------------------------------------------------------------------------------------------
SSR Data Imports (Steps 22 onward use these)
  - Sales data:    Net sales by product (not currently used in main pipeline)
  - Discount rates: Gross-to-net discount percentages by product x quarter (the key input)
  - NDC lookup:    Maps SSR product names to 11-digit NDC codes
------------------------------------------------------------------------------------------*/
*Import SSR net sales;
proc import
	datafile="\\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Macros\KFF\Employer_sponsored\Inputs\Sales.Pr.DATA_data.csv"
	out=_01_og_SSR_netsales
	dbms=csv
	replace;
	guessingrows=max;
run;*^^UPDATE HERE #20, with new ssr filepaths;

*Import SSR discount rates (total);
proc import
	datafile="\\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Macros\KFF\Employer_sponsored\Inputs\GTN.Pr.DATA_data_total.csv"
	out=_01_og_SSR_tot_discountrates
	dbms=csv
	replace;
	guessingrows=max;
run;*^^UPDATE HERE #21, with new ssr filepaths;

*Import SSR NDCs;
proc import
	datafile="\\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Macros\KFF\Employer_sponsored\Inputs\NDCUOM.PrStr.DATA_data.csv"
	out=_01_og_SSR_NDCs
	dbms=csv
	replace;
	guessingrows=max;
run;*^^UPDATE HERE #22, with new ssr filepaths;

/*------------------------------------------------------------------------------------------
Sub-Phase 3A: RedBook Drug Reference & SSR NDC Matching (Steps 21-23)
  - RedBook is a drug reference database bundled with MarketScan
  - Contains NDC numbers (ndcnum), product names (prodnme), generic names (gennme),
    and manufacturer names (manfnme)
  - We stack RedBook files from all available MarketScan years and deduplicate by NDC
  - SSR NDC codes are zero-padded to 11 digits and merged with RedBook to get 
    generic/brand name information for each SSR product
  - This enables fuzzy matching of SSR products to HCPCS descriptions in Step 32
------------------------------------------------------------------------------------------*/
*21) Stack all the redbooks together & keep only unique drugs;
data _21_stacked_REDBOOKs;
	set MKT08.redbook (keep=ndcnum prodnme gennme manfnme)
		MKT910.redbook (keep=ndcnum prodnme gennme manfnme)
		MKT12.redbook (keep=ndcnum prodnme gennme manfnme)
		MKT13.redbook (keep=ndcnum prodnme gennme manfnme)
		MKT14.redbook (keep=ndcnum prodnme gennme manfnme)
		MKT15.redbook (keep=ndcnum prodnme gennme manfnme)
		MKT16.redbook (keep=ndcnum prodnme gennme manfnme)
		MKT17.redbook (keep=ndcnum prodnme gennme manfnme)
		MKT18.redbook (keep=ndcnum prodnme gennme manfnme)
		MKT19.redbook (keep=ndcnum prodnme gennme manfnme)
		MKT20.redbook (keep=ndcnum prodnme gennme manfnme)
		MKT21.redbook (keep=ndcnum prodnme gennme manfnme)
		MKT22.redbook (keep=ndcnum prodnme gennme manfnme)
		MKT23.redbook (keep=ndcnum prodnme gennme manfnme)
		;*^^UPDATE HERE #23, with new marketscan data;
	lowcase_redbook_gennme = lowcase(gennme);*convert redbook's generic name to lowercase so it's easier to search;
	lowcase_redbook_prodnme = lowcase(prodnme);*convert redbook's product name to lowercase so it's easier to search;
	drop prodnme gennme;
run;

*Delete duplicate ndcs;
proc sort
	data=_21_stacked_REDBOOKs
	nodupkey;
	by ndcnum;
run;

/*------------------------------------------------------------------------------------------
Step 22: Standardize SSR NDC Codes to 11 Digits
  - SSR's NDC field may have fewer than 11 digits; zero-pad with PUT(ndc_11, z11.)
  - Lowercase the product name for case-insensitive matching later
  - Handle SSR product names with " / " vs "/" formatting inconsistencies
------------------------------------------------------------------------------------------*/
*22) Add leading 0's to get NDCs to 11 digits;
data _22_SSR_11dig_NDCs;
	set _01_og_SSR_NDCs;
	lowcase_ssr_product = lowcase(product);
	if find(lowcase_ssr_product, " / ", "i") then lowcase_ssr_product=tranwrd(lowcase_ssr_product," / ","/");
	ndcnum = put(ndc_11, z11.); *add leading 0s to ndc numbers;
	drop unit_of_measure product strength_form ndc_11;
run;

/*------------------------------------------------------------------------------------------
Step 23: Merge SSR NDCs with RedBook
  - Inner join gives us SSR products that also appear in RedBook
  - Drops placeholder NDCs (00000000000, 00000000001, 00000000002)
  - Result: each row has SSR product name + RedBook generic/brand names + 11-digit NDC
------------------------------------------------------------------------------------------*/
*23) Merge SSR NDCs with Redbook NDCs;
proc sort
	data=_22_SSR_11dig_NDCs;
	by ndcnum;
run;

proc sort
	data=_21_stacked_REDBOOKs;
	by ndcnum;
run;

data _23_ssr_drugs_w_redbook_ndcs;
	merge _22_SSR_11dig_NDCs (in=x)
		  _21_stacked_REDBOOKs (drop=manfnme);
	by ndcnum;
	if x=1;
	if ndcnum="00000000000" | ndcnum="00000000001" | ndcnum="00000000002" then delete;
run;

/*------------------------------------------------------------------------------------------
Sub-Phase 3B: HCPCS Crosswalk Construction (Steps 24-29)
  PURPOSE: Build a comprehensive HCPCS code reference with descriptions from two sources:
    (1) CMS Alpha-Numeric HCPCS files (procedure code descriptions)
    (2) Palmetto NDC-HCPCS crosswalks (maps NDCs to HCPCS with drug-specific descriptions)
  
  This crosswalk is used in Step 32 to determine which SSR products have HCPCS codes,
  indicating they are physician-administered drugs (and thus should NOT receive retail
  rebate adjustments).

  The CMS HCPCS files have inconsistent column naming across years, so the import macro
  handles each year's quirks with conditional logic.
------------------------------------------------------------------------------------------*/
%MACRO CMS_PALMETTO_HCPCS;
	/*--------------------------------------------------------------------------
	Import CMS HCPCS Files
	  - Each year's file has slightly different column names and layouts
	  - The macro normalizes them to: hcpcs, long_description, short_description
	  - Years 2017 & 2024 have standard column names (hcpc, long_description)
	  - Years 2018-2019 use generic names (var1, d, e)
	  - Year 2020 has a uniquely named first column
	--------------------------------------------------------------------------*/
	*Import CMS HCPCS list;
	%macro import_CMShcpcs (FILENAME=, SHEETNAME=, YEAR=, DBMS=);
		proc import
			datafile = "\\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Macros\KFF\Employer_sponsored\Inputs\&FILENAME..&DBMS."
			out=_01_og_cms_hcpcs&YEAR.
			dbms=&DBMS.
			replace;
			getnames=yes;
			sheet = "&SHEETNAME.";
		run;

		*24) Clean up the spreadsheets;
		%if &YEAR.=2017 | &YEAR.=2024 %then %do;
			data _24_clean_cms_hcpcs&YEAR.;
				set _01_og_cms_hcpcs&YEAR. (keep=hcpc long_description short_description);
				hcpcs=compress(hcpc); *remove blanks;
			run;
		%end;
		%if &YEAR.=2018 | &YEAR.=2019 %then %do;
			data _24_clean_cms_hcpcs&YEAR.;
				set _01_og_cms_hcpcs&YEAR. (keep=var1 d e);
				if d="" then delete; *discard missing observations;
				if d="LONG DESCRIPTION" then delete;
				hcpcs=compress(var1); *remove blanks;
				rename d=long_description
					   e=short_description;
			run;
		%end;
		%if &YEAR.=2020 %then %do;
			data _24_clean_cms_hcpcs&YEAR.;
				set _01_og_cms_hcpcs&YEAR. (keep=Note_regarding_coverage_and_paym d e);
				if d="" then delete;*discard missing observations;
				if d="LONG DESCRIPTION" then delete;
				hcpcs=compress(Note_regarding_coverage_and_paym); *remove blanks;
				rename d=long_description
					   e=short_description;
			run;
		%end;
	%mend;
	%import_CMShcpcs (FILENAME=HCPC17_CONTR_ANWEB, SHEETNAME=a, YEAR=2017, DBMS=xlsx);
	%import_CMShcpcs (FILENAME=HCPC2018_CONTR_ANWEB_disc, SHEETNAME=HCPCS_2018_Alpha, YEAR=2018, DBMS=xlsx);
	%import_CMShcpcs (FILENAME=HCPC2019_CONTR_ANWEB, SHEETNAME=a, YEAR=2019, DBMS=xlsx);
	%import_CMShcpcs (FILENAME=HCPC2020_ANWEB_w_disclaimer, SHEETNAME=a, YEAR=2020, DBMS=xls);
	%import_CMShcpcs (FILENAME=HCPC2024_JAN_ANWEB_v4, SHEETNAME=HCPC2024_JAN_ANWEB_v3, YEAR=2024, DBMS=xlsx);
	*^^UPDATE HERE #24, with new cms_hcpcs data;

	/*--------------------------------------------------------------------------
	Steps 25-26: Stack & Deduplicate CMS HCPCS
	  - Stack all years' cleaned HCPCS files
	  - Remove hyphens and commas from descriptions for cleaner text matching
	  - Lowercase all descriptions
	  - Some HCPCS codes appear multiple times with different descriptions (e.g., A4221)
	  - For these, concatenate descriptions with " #;# " separator so each HCPCS 
	    has one row with all descriptions combined
	--------------------------------------------------------------------------*/
	*25) Stack CMS hcpcs files together;
	data _25_stacked_cms_hcpcs;
		length hcpcs $600. short_description $30.;
		set _24_clean_cms_hcpcs: ;
		nohyphen_short_desc=compress(short_description, '-');
		nocomma_short_desc=compress(nohyphen_short_desc, ',');

		nohyphen_long_desc=compress(long_description, '-');
		nocomma_long_desc=compress(nohyphen_long_desc, ',');

		lowcase_cms_short_desc=lowcase(nocomma_short_desc);
		lowcase_cms_long_desc=lowcase(nocomma_long_desc);
		keep hcpcs lowcase:;
	run;

	*Remove duplicates;
	proc sort
		data=_25_stacked_cms_hcpcs
		nodupkey;
		by hcpcs lowcase_cms_long_desc;
	run; *NOTE: there are still duplicate HCPCS codes with different desriptions, such as A4221;

	*26) Combine descriptions if hcpcs are the same;
	proc sort
		data=_25_stacked_cms_hcpcs;
		by hcpcs;
	run;

	data _26_cms_concatenated_desc (drop=lowcase_cms_long_desc lowcase_cms_short_desc);
		set _25_stacked_cms_hcpcs;
		by hcpcs;
		length concat_lowcase_cms_long_desc $3000 concat_lowcase_cms_short_desc $500;
		retain concat_lowcase_cms_long_desc concat_lowcase_cms_short_desc;
		concat_lowcase_cms_long_desc =ifc(first.hcpcs,lowcase_cms_long_desc,catx(' #;# ',concat_lowcase_cms_long_desc,lowcase_cms_long_desc));
		concat_lowcase_cms_short_desc=ifc(first.hcpcs,lowcase_cms_short_desc,catx(' #;# ',concat_lowcase_cms_short_desc,lowcase_cms_short_desc));
		if last.hcpcs then output;
	run; *Now only a single obs of A4221;

	proc sort
		data=_26_cms_concatenated_desc
		nodupkey;
		by hcpcs;
	run;

	/*--------------------------------------------------------------------------
	Steps 27-28: Import & Clean Palmetto NDC-HCPCS Crosswalks
	  - Palmetto provides annual crosswalks mapping NDCs to HCPCS codes
	  - Same deduplication/concatenation logic as the CMS files above
	  - HCPCS descriptions from Palmetto may differ from CMS descriptions
	--------------------------------------------------------------------------*/
	*Import Palmetto HCPCS-NDC crosswalks;
	%macro import_hcpcsndc (SHEETNAME=, YEAR=, FILENAME=, DBMS=);
		proc import
			datafile = "\\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Macros\KFF\Employer_sponsored\Inputs\&FILENAME..&DBMS."
			out=_01_og_hcpcs_ndc&YEAR.
			dbms=&DBMS.
			replace;
			getnames=yes;
			sheet = "&SHEETNAME.";
		run;
	%mend;
	%import_hcpcsndc (SHEETNAME=12-05-2016 NDC-HCPCS XWalk, YEAR=2016, FILENAME=2016-12-05_xwalkfinalversion, DBMS=xls);
	%import_hcpcsndc (SHEETNAME=12-05-2017 NDC-HCPCS XWalk, YEAR=2017, FILENAME=2017-12-05XWalkFinalVersion, DBMS=xls);
	%import_hcpcsndc (SHEETNAME=12-05-2018 NDC-HCPCS XWalk, YEAR=2018, FILENAME=2018-12-05 XWalkFinalVersion, DBMS=xlsx);
	%import_hcpcsndc (SHEETNAME=12-05-2019 NDC-HCPCS XWALK, YEAR=2019, FILENAME=2019-12-05XWalk, DBMS=xlsx);
	%import_hcpcsndc (SHEETNAME=12-05-2020 NDC-HCPCS XWALK, YEAR=2020, FILENAME=2020-12-05XWalk, DBMS=xlsx);
	%import_hcpcsndc (SHEETNAME=12-05-2021 NDC-HCPCS XWALK, YEAR=2021, FILENAME=2021-12-05XWalk, DBMS=xlsx);
	%import_hcpcsndc (SHEETNAME=12-05-2022 NDC-HCPCS XWALK, YEAR=2022, FILENAME=2022-12-05XWalk, DBMS=xlsx);
	%import_hcpcsndc (SHEETNAME=12-05-2023 NDC-HCPCS XWALK, YEAR=2023, FILENAME=2023-12-05XWalk, DBMS=xlsx);
	*^^UPDATE HERE #25, with new palmetto data;

	*27) Clean up the hcpcs-ndc crosswalk and keep only the necessary variables;
	data _27_stacked_hcpcsndc;
		length hcpcs_description $250.;
		set _01_og_hcpcs_ndc: (keep=ndc hcpcs hcpcs_description ndc_label);
		nohyphen_hcpcs_desc=compress(hcpcs_description, '-');
		nocomma_hcpcs_desc=compress(nohyphen_hcpcs_desc, ',');
		lowcase_palmetto_hcpcs_desc = lowcase(nocomma_hcpcs_desc);
		lowcase_palmetto_ndc_desc = lowcase(ndc_label);
		drop hcpcs_description ndc_label nohyphen_hcpcs_desc nocomma_hcpcs_desc;
		if hcpcs="" then delete;
	run;

	*Delete duplicate values;
	proc sort
		data=_27_stacked_hcpcsndc
		nodupkey ;
		by hcpcs lowcase_palmetto_hcpcs_desc;
	run;*NOTE: there are still duplicate HCPCS codes with different desriptions, such as J0129;

	*28) Combine descriptions if hcpcs are the same;
	proc sort
		data=_27_stacked_hcpcsndc;
		by hcpcs;
	run;

	data _28_palmetto_concatenated_desc (drop=lowcase_palmetto_hcpcs_desc lowcase_palmetto_ndc_desc);
		set _27_stacked_hcpcsndc;
		by hcpcs;
		length concat_lowcase_palm_hcpcs_desc $1000 concat_lowcase_palm_ndc_desc $1000 ;
		retain concat_lowcase_palm_hcpcs_desc concat_lowcase_palm_ndc_desc;
		concat_lowcase_palm_hcpcs_desc =ifc(first.hcpcs,lowcase_palmetto_hcpcs_desc,catx(' #;# ',concat_lowcase_palm_hcpcs_desc,lowcase_palmetto_hcpcs_desc));
		concat_lowcase_palm_ndc_desc=ifc(first.hcpcs,lowcase_palmetto_ndc_desc,catx(' #;# ',concat_lowcase_palm_ndc_desc,lowcase_palmetto_ndc_desc));
		if last.hcpcs then output;
	run; *Now only a single obs of J0129;

	proc sort
		data=_28_palmetto_concatenated_desc
		nodupkey;
	by hcpcs;
	run;

	/*--------------------------------------------------------------------------
	Step 29: Merge CMS & Palmetto HCPCS References
	  - Full outer join by HCPCS code
	  - Result: one row per HCPCS with descriptions from both CMS and Palmetto
	  - This comprehensive reference is used in Step 32 for fuzzy drug matching
	--------------------------------------------------------------------------*/
	*29) Combine CMS & palmetto together;
	proc sort
		data=_26_cms_concatenated_desc;
		by hcpcs;
	run;

	proc sort
		data=_28_palmetto_concatenated_desc;
		by hcpcs;
	run;

	data _29_final_hcpcs_cms_palmetto;
		merge _26_cms_concatenated_desc
			  _28_palmetto_concatenated_desc;
		by hcpcs;
		if hcpcs="None" then delete;
	run;
%mend; %CMS_PALMETTO_HCPCS;

/*------------------------------------------------------------------------------------------
Sub-Phase 3C: Fuzzy Match SSR Products to HCPCS Codes (Steps 30-32)
  PURPOSE: Determine which SSR products have corresponding HCPCS codes, indicating
  they are typically administered in physician offices/hospitals rather than dispensed
  at retail pharmacies.
  
  APPROACH: A Cartesian (cross) join is created between all unique SSR products and all
  HCPCS codes. Then, text matching (INDEXW function) checks whether the SSR product name,
  RedBook generic name, or RedBook brand name appears within any HCPCS description.
  
  KNOWN LIMITATION: This fuzzy matching is imperfect. For example, SSR product "armour 
  thyroid" matches HCPCS G9552 "incidental thyroid nodule" because "thyroid" appears in
  both. The final deduplication keeps only one HCPCS per product for simplicity, though
  some products legitimately map to multiple HCPCS codes.
------------------------------------------------------------------------------------------*/
*30) For ssr ndc data, set missing variables to nonsense word 'asdfghj' & identify unique ssr products;
data _30_unique_ssr_products;
	set _23_ssr_drugs_w_redbook_ndcs;
	if lowcase_redbook_gennme = "" then lowcase_redbook_gennme="asdfghj";
	if lowcase_redbook_prodnme = "" then lowcase_redbook_prodnme="asdfghj";
run;

*Remove duplicates;
proc sort
	data=_30_unique_ssr_products
	nodupkey;
by lowcase:;
run;

*31) Even if it doesn't make sense, merge each row of (_30_unique_ssr_products) with each row of (_29_final_hcpcs_cms_palmetto) ;
proc sql;
	create table _31_allpossible_ssr_w_hcpcs as
	select *
	from _30_unique_ssr_products,(select * from _29_final_hcpcs_cms_palmetto)
	;
quit;

/*------------------------------------------------------------------------------------------
Step 32: Keep Only Rows Where an SSR Drug Name Appears in a HCPCS Description
  - INDEXW checks for whole-word matches across 12 combinations:
    (SSR product name, RedBook generic, RedBook brand) x 
    (CMS long desc, CMS short desc, Palmetto HCPCS desc, Palmetto NDC desc)
  - If ANY of the 12 checks finds a match (indexw >= 1), keep the row
  - After filtering, deduplicate to one HCPCS per product (for merge simplicity)
  - Result: a list of SSR products that have HCPCS codes (physician-administered drugs)
------------------------------------------------------------------------------------------*/
*32) Keep the row if hcpcs description matches a ssr molecule;
data _32_ssr_hcpcs_xwalk (keep=lowcase_ssr_product lowcase: hcpcs concat_lowcase_cms_long_desc);
	set _31_allpossible_ssr_w_hcpcs;
	indexw_1=indexw(concat_lowcase_cms_long_desc,lowcase_ssr_product);
	indexw_2=indexw(concat_lowcase_cms_long_desc,lowcase_redbook_gennme);
	indexw_3=indexw(concat_lowcase_cms_long_desc,lowcase_redbook_prodnme);

	indexw_4=indexw(concat_lowcase_cms_short_desc,lowcase_ssr_product);
	indexw_5=indexw(concat_lowcase_cms_short_desc,lowcase_redbook_gennme);
	indexw_6=indexw(concat_lowcase_cms_short_desc,lowcase_redbook_prodnme);

	indexw_7=indexw(concat_lowcase_palm_hcpcs_desc,lowcase_ssr_product);
	indexw_8=indexw(concat_lowcase_palm_hcpcs_desc,lowcase_redbook_gennme);
	indexw_9=indexw(concat_lowcase_palm_hcpcs_desc,lowcase_redbook_prodnme);

	indexw_10=indexw(concat_lowcase_palm_ndc_desc,lowcase_ssr_product);
	indexw_11=indexw(concat_lowcase_palm_ndc_desc,lowcase_redbook_gennme);
	indexw_12=indexw(concat_lowcase_palm_ndc_desc,lowcase_redbook_prodnme);

	if indexw_1>=1 | 
	   indexw_2>=1 | 
	   indexw_3>=1 | 
	   indexw_4>=1 |
	   indexw_5>=1 | 
	   indexw_6>=1 | 
	   indexw_7>=1 | 
	   indexw_8>=1 | 
	   indexw_9>=1 | 
	   indexw_10>=1 | 
	   indexw_11>=1 | 
	   indexw_12>=1 ;
run; *This mapping is not perfect. for example, ssr="armour thyroid" maps to hcspcs "G9552 incidental thyroid nodule";

/*
proc sort
	data=_32_ssr_hcpcs_xwalk
	nodupkey;
	by hcpcs ssr_brand_name;
run;*NOTE how, for example, hcpcs C9034 maps to multiple SSR products;
*/

proc sort
	data=_32_ssr_hcpcs_xwalk
	nodupkey;
	by hcpcs;
run; *For the sake of progress and easy merging, we'll just have 1 hcpcs. See the commented out portion above for why this is an issue;


/*------------------------------------------------------------------------------------------
Sub-Phase 3D: Compare Drug Volumes Between IP/OP and Rx Files (Steps 33-41)
  COMMENTED OUT because steps 33-40 take approximately 6 hours to run.
  Only re-run when source data change.

  PURPOSE: For each SSR product, determine whether it is predominantly dispensed at
  retail pharmacies (Rx file) or administered in clinical settings (IP/OP files).
  
  APPROACH:
    Step 33: Stack ALL MarketScan IP/OP claims across all years (keeping proc1 and pay)
    Step 34: Sum claim counts and payments by procedure code (proc1)
    Step 35: Merge the SSR-HCPCS crosswalk with MarketScan procedure-level aggregates
    Step 36: Aggregate IP/OP claims by SSR product name
    Step 37: Stack ALL MarketScan Rx claims across all years (keeping ndcnum and pay)
    Step 38: Sum Rx claims by NDC
    Step 39: Merge Rx NDC aggregates with SSR NDC lookup
    Step 40: Compare IP/OP vs Rx volumes for each SSR product
             - Calculate shares: ipop_claim_share, rx_claim_share, ipop_pay_share, rx_pay_share
             - Flag as "ipop leaning" or "rx leaning"
    Step 41: Flag drugs where IP/OP share > 50% for exclusion from rebate adjustment
             - These are saved as INPUTS.ssr_ipop_drugs_to_drop

  OUTPUT: INPUTS.ssr_ipop_drugs_to_drop (flag_to_Drop_ipopdrugs=1 for physician-admin drugs)
------------------------------------------------------------------------------------------*/
/*INTENTIONALLY COMMENTED OUT (below). _33_ - _40_ take 6~ hours to run. Only re-run this if necessary to overwrite.
*33) stack mktscn ip/op claims;
data _33_Stack_mktscn_ipop_claims&BLEND_NEWYEAR.;
	length proc1 $7. pay 8.;
	set MKT007.ccaeo002 (keep=proc1 pay)
	    MKT007.ccaes002 (keep=proc1 pay)
		MKT007.ccaeo013 (keep=proc1 pay)
		MKT007.ccaes013 (keep=proc1 pay)
		MKT007.ccaeo023 (keep=proc1 pay)
		MKT007.ccaes023 (keep=proc1 pay)
		MKT007.ccaeo033 (keep=proc1 pay)
		MKT007.ccaes033 (keep=proc1 pay)
		MKT007.ccaeo045 (keep=proc1 pay)
		MKT007.ccaes045 (keep=proc1 pay)
		MKT007.ccaeo054 (keep=proc1 pay)
		MKT007.ccaes054 (keep=proc1 pay)
		MKT007.ccaeo063 (keep=proc1 pay)
		MKT007.ccaes063 (keep=proc1 pay)
		MKT007.ccaeo072 (keep=proc1 pay)
		MKT007.ccaes072 (keep=proc1 pay)
		MKT08.ccaeo081 (keep=proc1 pay)
		MKT08.ccaes081 (keep=proc1 pay)
		MKT910.ccaeo093 (keep=proc1 pay)
		MKT910.ccaes093 (keep=proc1 pay)
		MKT910.ccaeo102 (keep=proc1 pay)
		MKT910.ccaes102 (keep=proc1 pay)
		MKT11.ccaeo111 (keep=proc1 pay)
		MKT11.ccaes111 (keep=proc1 pay)
		MKT12.ccaeo121 (keep=proc1 pay)
		MKT12.ccaes121 (keep=proc1 pay)
		MKT13.ccaeo131 (keep=proc1 pay)
		MKT13.ccaes131 (keep=proc1 pay)
		MKT14.ccaeo141 (keep=proc1 pay)
		MKT14.ccaes141 (keep=proc1 pay)
		MKT15.ccaeo151 (keep=proc1 pay)
		MKT15.ccaes151 (keep=proc1 pay)
		MKT16.ccaeo161 (keep=proc1 pay)
		MKT16.ccaes161 (keep=proc1 pay)
		MKT17.ccaeo171 (keep=proc1 pay)
		MKT17.ccaes171 (keep=proc1 pay)
		MKT18.ccaeo181 (keep=proc1 pay)
		MKT18.ccaes181 (keep=proc1 pay)
		MKT19.ccaeo192 (keep=proc1 pay)
		MKT19.ccaes192 (keep=proc1 pay)
		MKT20.ccaeo201 (keep=proc1 pay)
		MKT20.ccaes201 (keep=proc1 pay)
		MKT21.ccaeo211 (keep=proc1 pay)
		MKT21.ccaes211 (keep=proc1 pay)
		MKT22.ccaeo221 (keep=proc1 pay)
		MKT22.ccaes221 (keep=proc1 pay)
		MKT23.ccaeo232 (keep=proc1 pay)
		MKT23.ccaes232 (keep=proc1 pay);
		*^^UPDATE HERE #26 TWICE, with new marketscan data (S and O);
	claim_count=1;
	file_Type="ipop";
run;

*34) Sum claims count & pay by procedure type;
proc means
	data=_33_stack_mktscn_ipop_claims&BLEND_NEWYEAR. noprint nway;
	class proc1 file_type;
	var claim_count pay;
	output out=_34_ipop_by_proc (drop=_:) sum()=;
run;

*35) Merge SSRHCPCS with mkscnHCPCS;
proc sort
	data=_32_ssr_hcpcs_xwalk;
	by hcpcs;
run;

proc sort
	data=_34_ipop_by_proc;
	by proc1;
run;

data _35_ssr_hcpcs_w_mktscn;
	merge _32_ssr_hcpcs_xwalk (in=x rename=(hcpcs=proc1))
		  _34_ipop_by_proc (in=y);
	by proc1;
	if x+y=2;
run;

*36) Sum by drug name rather just hcpcs codes;
proc means
	data=_35_ssr_hcpcs_w_mktscn noprint nway;
	class lowcase_ssr_product;
	var claim_count pay;
	output out=_36_ipop_drugname_count (drop=_:) sum()=ipop_claim_count ipop_pay;
run;

*37) Stack all marketscan rx files & remove duplicate ndcs;
data _37_stack_mktscn_rx_allyears&BLEND_NEWYEAR.;
	length ndcnum $13. pay 8.;
	set MKT007.ccaed002 (keep=ndcnum pay)
		MKT007.ccaed013 (keep=ndcnum pay)
		MKT007.ccaed023 (keep=ndcnum pay)
		MKT007.ccaed033 (keep=ndcnum pay)
		MKT007.ccaed045 (keep=ndcnum pay)
		MKT007.ccaed054 (keep=ndcnum pay)
		MKT007.ccaed063 (keep=ndcnum pay)
		MKT007.ccaed072 (keep=ndcnum pay)
		MKT08.ccaed081 (keep=ndcnum pay)
		MKT910.ccaed093 (keep=ndcnum pay)
		MKT910.ccaed102 (keep=ndcnum pay)
		MKT11.ccaed111 (keep=ndcnum pay)
		MKT12.ccaed121 (keep=ndcnum pay)
		MKT13.ccaed131 (keep=ndcnum pay)
		MKT14.ccaed141 (keep=ndcnum pay)
		MKT15.ccaed151 (keep=ndcnum pay)
		MKT16.ccaed161 (keep=ndcnum pay)
		MKT17.ccaed171 (keep=ndcnum pay)
		MKT18.ccaed181 (keep=ndcnum pay)
		MKT19.ccaed192 (keep=ndcnum pay)
		MKT20.ccaed201 (keep=ndcnum pay)
		MKT21.ccaed211 (keep=ndcnum pay)
		MKT22.ccaed221 (keep=ndcnum pay)
		MKT23.ccaed232 (keep=ndcnum pay);
		*^^UPDATE HERE #27, with new marketscan data;
	claim_count=1;
	file_Type="rx";
run;

*38) Sum rx claims by ndc;
proc means
	data=_37_stack_mktscn_rx_allyears&BLEND_NEWYEAR. noprint nway;
	class ndcnum file_type;
	var claim_count pay;
	output out=_38_mktscn_Rx_claimcount (drop=_:) sum()=rx_claim_count rx_pay;
run;

*39) Merge claims ndcs with SSR ndcs in order to capture Retail-specific drugs;
proc sort
	data=_38_mktscn_Rx_claimcount;
	by ndcnum;
run;

proc sort
	data=_23_ssr_drugs_w_redbook_ndcs;
	by ndcnum;
run;

data _39_ssr_retails_specific_drugs;
	merge _23_ssr_drugs_w_redbook_ndcs (in=x)
		  _38_mktscn_Rx_claimcount (in=y);
	by ndcnum;
	if x+y=2;
	retail_specific=1;
run;

proc sort
	data=_39_ssr_retails_specific_drugs (keep=lowcase_ssr_product rx_:)
	nodupkey;
	by lowcase_ssr_product;
run;

*40) Merge RX with IPOP;
proc sort
	data=_36_ipop_drugname_count;
	by lowcase_ssr_product;
run;

proc sort
	data=_39_ssr_retails_specific_drugs;
	by lowcase_ssr_product;
run;

data _40_ssr_hcpcs_vs_rx_compared;
	merge _36_ipop_drugname_count
		  _39_ssr_retails_specific_drugs;
	by lowcase_ssr_product;
	all_file_claims = sum(of ipop_claim_count, rx_claim_count);
	all_file_pay=sum(of ipop_pay, rx_pay);
	ipop_claim_share = ipop_claim_count/all_file_claims;
	rx_claim_share = rx_claim_count/all_file_claims;
	ipop_pay_share = ipop_pay/all_file_pay;
	rx_pay_share = rx_pay/all_file_pay;
	if ipop_claim_share = . then ipop_claim_share=0;
	if rx_claim_share = . then rx_claim_share=0;
	if ipop_pay_share = . then ipop_pay_share=0;
	if rx_pay_share = . then rx_pay_share=0;
	if ipop_claim_share > rx_claim_share then flag_claim="ipop leaning";
	else if ipop_claim_share < rx_claim_share then flag_claim="rx leaning";
	if ipop_pay_share > rx_pay_share then flag_pay="ipop leaning";
	else if ipop_pay_share < rx_pay_share then flag_pay="rx leaning";
	if abs(ipop_claim_share - rx_claim_share) < .10 then too_close_claims=1;
	if abs(ipop_pay_share - rx_pay_share) < .10 then too_close_pay=1;
run;

*41) Flag the drugs to drop - any drug with ipop share > 50%;
data INPUTS.ssr_ipop_drugs_to_drop;
	set _40_ssr_hcpcs_vs_rx_compared;
	if ipop_claim_share >.50;
	flag_to_Drop_ipopdrugs=1;
	keep lowcase_ssr_product flag_to_Drop_ipopdrugs;
run;
^^INTENTIONALLY COMMENTED OUT^^*/

/*------------------------------------------------------------------------------------------
Sub-Phase 3E: SSR Discount Rate Processing (Steps 42-49)
  - Cleans SSR discount rate data: extracts year from quarter string, converts % to decimal
  - Averages quarterly discount rates to annual by product
  - Creates a "filler" dataset for years 2007-2023 (all zero) to serve as a scaffold
  - Merges real discount rates onto the scaffold (missing years get 0% discount)
  - When discount rate is missing, gross_margin is also set to 0 (no rebate adjustment)
  - Merges discount rates with NDC codes from Step 23
  - Drops physician-administered drugs (from INPUTS.ssr_ipop_drugs_to_drop)
  - Final output: INPUTS.ssr_ndc_xwalk_Retail_tot{BLEND_NEWYEAR}
    = one row per NDC x year with discount rate and gross margin
------------------------------------------------------------------------------------------*/
%macro SSR_discount_1 (NAME=);
	*42) Clean up SSR discount data;
	data _42_&NAME._discounts;
		set _01_og_SSR_&NAME._discountrates;
		year_char = substr(Quarter_of_Qtr_End, 1, 4);
		year = year_char * 1; *numeric format;
		discount_char = compress(ch_Product_Metric_Selection_GTN, "%",); *discarding the % symbol;
		SSR_&NAME._discount_rate = (discount_char * 1)/100; *numeric format;
		lowcase_ssr_product = lowcase(product);
		if find(lowcase_ssr_product, " / ", "i") then lowcase_ssr_product=tranwrd(lowcase_ssr_product," / ","/");
		if SSR_&NAME._discount_rate = . then delete; *discard missing discount observations;
		drop label_moving_average discount_char ch_Product_Metric_Selection_GTN year_char;
	run;

	*43) Average discount rate by product-year;
	proc means
		data=_42_&NAME._discounts noprint nway;
		class lowcase_ssr_product year;
		var SSR_&NAME._discount_rate;
		output out=_43_avg_&NAME._discountrate (Drop=_:) mean()=avgyrly_&NAME._discount_rate;
	run;
%mend; %SSR_discount_1 (NAME=tot);

/*------------------------------------------------------------------------------------------
Step 44: Create Filler/Scaffold Dataset for SSR Discount Years
  - One row per year from 2007-2023 with missing_SSR_discounts=0
  - This ensures every SSR product has a row for every year, even if no discount data exist
  - Years with no real SSR data will receive 0% discount and 0% gross margin
------------------------------------------------------------------------------------------*/
*44) Create filler discounts for missing years;
data _44_SSR_filler;
	year=2007;
	missing_SSR_discounts=0;
output;
	year=2008;
	missing_SSR_discounts=0;
output;
	year=2009;
	missing_SSR_discounts=0;
output;
	year=2010;
	missing_SSR_discounts=0;
output;
	year=2011;
	missing_SSR_discounts=0;
output;
	year=2012;
	missing_SSR_discounts=0;
output;
	year=2013;
	missing_SSR_discounts=0;
output;
	year=2014;
	missing_SSR_discounts=0;
output;
	year=2015;
	missing_SSR_discounts=0;
output;
	year=2016;
	missing_SSR_discounts=0;
output;
	year=2017;
	missing_SSR_discounts=0;
output;
	year=2018;
	missing_SSR_discounts=0;
output;
	year=2019;
	missing_SSR_discounts=0;
output;
	year=2020;
	missing_SSR_discounts=0;
output;
	year=2021;
	missing_SSR_discounts=0;
output;
	year=2022;
	missing_SSR_discounts=0;
output;
	year=2023;
	missing_SSR_discounts=0;
output;
*^^UPDATE HERE #28, with new HCSA year;
run;

*45) Unique product names;
proc sort
	data=_23_ssr_drugs_w_redbook_ndcs
	nodupkey
	out=_45_all_ssr_brand_names (keep=lowcase_ssr_product);
	by lowcase_ssr_product;
run;

/*------------------------------------------------------------------------------------------
Step 46: Cartesian Join of SSR Products x Years
  - Every unique SSR product gets a row for every year in the filler dataset
  - This scaffold is then merged with actual discount rate data in step 47
------------------------------------------------------------------------------------------*/
*46) Attach product names to all possible years of discount data;
proc sql;
	create table _46_allpossble_ssr_prods_w_years as
	select
	*
	from _45_all_ssr_brand_names, _44_ssr_filler;
quit;

%macro SSR_discount_2 (NAME=);
	/*----------------------------------------------------------------------
	Step 47: Merge Real Discount Rates onto the Product x Year Scaffold
	  - Where real data exist, use the actual average yearly discount rate
	  - Where data are missing, set discount rate = 0 and gross_margin = 0
	    (meaning no rebate adjustment will be applied for that product-year)
	  - gross_margin is set to 0.035 (3.5%) for products with real discount data
	----------------------------------------------------------------------*/
	*47) Merge filler years to existing real data;
	proc sort
		data=_46_allpossble_ssr_prods_w_years;
		by lowcase_ssr_product year;
	run;

	proc sort
		data=_43_avg_&NAME._discountrate;
		by lowcase_ssr_product year;
	run;

	data _47_ssr_&NAME.discount_allyears;
		merge _43_avg_&NAME._discountrate
			  _46_allpossble_ssr_prods_w_years;
		by lowcase_ssr_product year;
		gross_margin = 0.035;
		if avgyrly_&NAME._discount_rate=. then do;
			avgyrly_&NAME._discount_rate=0;
			gross_margin=0;
		end;
		drop missing: ;
	run; *For example, 8-mop 2008 will get a discount rate of 0;

	/*----------------------------------------------------------------------
	Step 48: Merge Discount Rates with NDC Codes
	  - Joins the product-year discount rates with the SSR-NDC lookup from Step 23
	  - Result: one row per NDC x year with the applicable discount rate
	----------------------------------------------------------------------*/
	*48) merge these with stages1-4 NDCs;
	proc sql noprint;
		create table _48_SSR_&NAME._discounts_w_ndcs as
		select a.*, b.* from _47_ssr_&NAME.discount_allyears a
		join _23_ssr_drugs_w_redbook_ndcs b
		on a.lowcase_ssr_product = b.lowcase_ssr_product;
	quit;

	/*----------------------------------------------------------------------
	Step 49: Drop Physician-Administered Drugs from the NDC Crosswalk
	  - Merges with the flag file from Step 41
	  - Drugs where flag_to_Drop_ipopdrugs=1 are deleted
	  - Remaining drugs are retail-pharmacy drugs eligible for rebate adjustment
	  - SSR_flag=1 marks these NDCs as having SSR discount data
	  - Saved as INPUTS.ssr_ndc_xwalk_Retail_{NAME}{BLEND_NEWYEAR}
	----------------------------------------------------------------------*/
	*49) Drop physician admin drugs from the ndcxwalk;
	proc sort
		data=_48_SSR_&NAME._discounts_w_ndcs;
		by lowcase_ssr_product;
	run;

	proc sort
		data=INPUTS.ssr_ipop_drugs_to_drop;
		by lowcase_ssr_product;
	run;

	/*INTENTIONALLY COMMENTED OUT (below). Re-run to writeover only if necessary.
	data INPUTS.ssr_ndc_xwalk_Retail_&NAME.&BLEND_NEWYEAR.;
		length lowcase_ssr_product $50.;
		merge _48_SSR_&NAME._discounts_w_ndcs
			  INPUTS.ssr_ipop_drugs_to_drop;
		by lowcase_ssr_product;
		if flag_to_Drop_ipopdrugs=1 then delete;
		drop flag_to_drop_ipopdrugs;
		if year>&BLEND_NEWYEAR. then delete;
		SSR_flag=1;
	run;

	proc sort
		data=INPUTS.ssr_ndc_xwalk_Retail_&NAME.&BLEND_NEWYEAR.;
		by lowcase_ssr_product year;
	run;
	^^INTENTIONALLY COMMENTED OUT^^*/
%mend; %SSR_discount_2 (NAME=tot);


/*##########################################################################################
##                                                                                        ##
##   PHASE 4: MEPS NDC-TO-CCSR CROSSWALK                                                 ##
##   Steps 50-62                                                                           ##
##                                                                                        ##
##   PURPOSE: MarketScan prescription drug claims do not include diagnosis codes. To       ##
##   allocate Rx spending to diseases, we need to know which diseases each drug treats.    ##
##   MEPS prescribed medicines files contain both NDC codes and associated diagnoses,      ##
##   allowing us to build an NDC -> CCSR crosswalk.                                       ##
##                                                                                        ##
##   TWO ERAS OF MEPS DIAGNOSIS CODING:                                                   ##
##     Pre-2016 (macro %MEPS_NDC_CCS_XWALK):                                              ##
##       MEPS provides CCS codes (rxccc1x, rxccc2x, rxccc3x) on Rx claims.               ##
##       These are converted to CCSR via INPUTS.Ccs_ccsr_xwalk2.                          ##
##       For pre-2004 data, mental health CCS codes are manually remapped because          ##
##       the CCS mental health coding scheme changed between 2003 and 2004.                ##
##                                                                                        ##
##     2016+ (macro %MEPS_NDC_CCSR_XWALK):                                                ##
##       MEPS provides CCSR codes directly (ccsr1x, ccsr2x, ccsr3x) through the           ##
##       medical conditions file linked to the appendix file.                              ##
##       This requires a many-to-many merge: medical conditions -> appendix -> Rx claims.  ##
##                                                                                        ##
##   RESULT: A deduplicated NDC x CCSR crosswalk spanning 1999-2023, where each NDC       ##
##   maps to one or more CCSR codes. This is then converted to a wide binary dummy         ##
##   matrix (543 columns) for use in the Trogdon regressions in Phase 5.                  ##
##                                                                                        ##
##   CCSR CLEANING: MEPS uses "000" suffix CCSRs (e.g., BLD000, CIR000) as catchall      ##
##   categories. We reassign these to legitimate CCSR codes per the mapping in Step 59.    ##
##   Dental CCSRs (DEN*) are deleted throughout.                                           ##
##                                                                                        ##
##########################################################################################*/

/*------------------------------------------------------------------------------------------
MACRO: %MEPS_NDC_CCS_XWALK (for pre-2016 years)
  Uses CCS codes from MEPS Rx files, converts to CCSR.
  
  PARAMETERS:
    FILE = MEPS prescribed medicines file number (e.g., h33a for 1999)
    YR   = 2-digit year suffix
    FY   = MEPS full-year consolidated file number
  
  STEPS:
    50: Merge MEPS Rx file with full-year file; keep only private (prvev=1, mcrev=2)
    51: Split wide-format CCS (ccs1, ccs2, ccs3) into separate datasets
    57a: Stack into long format (one row per NDC x CCS)
         - Pre-2004: remap mental health CCS codes to post-2004 equivalents
    58a: Convert CCS to CCSR using the CCS-CCSR crosswalk
  
  MENTAL HEALTH CCS REMAPPING (pre-2004 only):
    Old CCS -> New CCS:  65->654, 66->660, 67->661, 68->653, 69->657,
    70->655, 71->659, 72->651 (anxiety), 73->652, 74->670 (misc), 75->663
------------------------------------------------------------------------------------------*/
%macro MEPS_NDC_CCS_XWALK (FILE=, YR=, FY=);
	*50) Merge MEPS rx with MEPS fy;
	proc sort
		data=MEPS.h&FILE.a;
		by dupersid;
	run;

	proc sort
		data=MEPS.h&FY.;
		by dupersid;
	run;

	data _50_MEPS_rx_fy&YR.;
		merge MEPS.h&FILE.a(keep=dupersid rxndc rxccc: in=a) 
			  MEPS.h&FY.(keep=DUPERSID age&YR.x mcrev&YR. prvev&YR. in=b);
		by dupersid;
		ccs1=rxccc1x*1;
		ccs2=rxccc2x*1;
		ccs3=rxccc3x*1;
		if a=1 & prvev&YR.=1 & mcrev&YR.=2 & rxndc>="0" & (ccs1>=0 | ccs2>=0 | ccs3>=0);*selecting just private pop;
		if ccs1<0 then ccs1=0;
		if ccs2<0 then ccs2=0;	
		if ccs3<0 then ccs3=0;
		keep rxndc ccs1 ccs2 ccs3;
	run;

	*51) Separate Wide-Format CCS to different datasets;
	data _51_MEPS_rx_fy&YR._1 
		 _51_MEPS_rx_fy&YR._2 
		 _51_MEPS_rx_fy&YR._3;
			set _50_MEPS_rx_fy&YR.;
			if ccs1 ne 0 then output _51_MEPS_rx_fy&YR._1;
			if ccs2 ne 0 then output _51_MEPS_rx_fy&YR._2;
			if ccs3 ne 0 then output _51_MEPS_rx_fy&YR._3;
	run;

	*57a) Stack the CCS together in Long-Format;
	%if &YR.=99 | &YR.<=03 %then %do;
		data _57_stacked_MEPS_rx_ndc&YR.;*map pre2004 Mental health to post-2004 MH*;
			set _51_MEPS_rx_fy&YR._1(keep=rxndc ccs1 rename=(ccs1=ccs)) 
				_51_MEPS_rx_fy&YR._2(keep=rxndc ccs2 rename=(ccs2=ccs)) 
				_51_MEPS_rx_fy&YR._3(keep=rxndc ccs3 rename=(ccs3=ccs));
			if ccs=65 then ccs=654;
			if ccs=66 then ccs=660;
			if ccs=67 then ccs=661;
			if ccs=68 then ccs=653;
			if ccs=69 then ccs=657;
			if ccs=70 then ccs=655;
			if ccs=71 then ccs=659;
			if ccs=72 then ccs=651; *anxiety;
			if ccs=73 then ccs=652;
			if ccs=74 then ccs=670; *misc;
			if ccs=75 then ccs=663;
		run;
	%end;
	%else %do;
		data _57_stacked_MEPS_rx_ndc&YR.;
			set _51_MEPS_rx_fy&YR._1(keep=rxndc ccs1 rename=(ccs1=ccs)) 
				_51_MEPS_rx_fy&YR._2(keep=rxndc ccs2 rename=(ccs2=ccs)) 
				_51_MEPS_rx_fy&YR._3(keep=rxndc ccs3 rename=(ccs3=ccs));
		run;
	%end;

	*58a) Convert CCS to CCSR;
	proc sort
		data=_57_stacked_MEPS_rx_ndc&YR.;
		by CCS;
	run;

	proc sort
		data=INPUTS.Ccs_ccsr_xwalk2;
		by Beta_Version_CCS_Category;
	run; *Take note of the source variable in this dataset;

	data _58_MEPS_CCS_to_CCSR&YR.;
		merge _57_stacked_MEPS_rx_ndc&YR. (in=x)
			  INPUTS.Ccs_ccsr_xwalk2 (in=y keep=Beta_Version_CCS_Category ccsr_category rename=(Beta_Version_CCS_Category=ccs));
		by ccs;
		if x+y=2;
	run;
%mend;
%MEPS_NDC_CCS_XWALK (FILE=33, FY=38, YR=99);
%MEPS_NDC_CCS_XWALK (FILE=51, FY=50, YR=00);
%MEPS_NDC_CCS_XWALK (FILE=59, FY=60, YR=01);
%MEPS_NDC_CCS_XWALK (FILE=67, FY=70, YR=02);
%MEPS_NDC_CCS_XWALK (FILE=77, FY=79, YR=03);
%MEPS_NDC_CCS_XWALK (FILE=85, FY=89, YR=04);
%MEPS_NDC_CCS_XWALK (FILE=94, FY=97, YR=05);
%MEPS_NDC_CCS_XWALK (FILE=102, FY=105, YR=06);
%MEPS_NDC_CCS_XWALK (FILE=110, FY=113, YR=07);
%MEPS_NDC_CCS_XWALK (FILE=118, FY=121, YR=08);
%MEPS_NDC_CCS_XWALK (FILE=126, FY=129, YR=09);
%MEPS_NDC_CCS_XWALK (FILE=135, FY=138, YR=10);
%MEPS_NDC_CCS_XWALK (FILE=144, FY=147, YR=11);
%MEPS_NDC_CCS_XWALK (FILE=152, FY=155, YR=12);
%MEPS_NDC_CCS_XWALK (FILE=160, FY=163, YR=13);
%MEPS_NDC_CCS_XWALK (FILE=168, FY=171, YR=14);
%MEPS_NDC_CCS_XWALK (FILE=178, FY=181, YR=15);

/*------------------------------------------------------------------------------------------
MACRO: %MEPS_NDC_CCSR_XWALK (for 2016+ years)
  Uses CCSR codes directly from MEPS medical conditions file.
  
  PARAMETERS:
    FILE = MEPS prescribed medicines / appendix file number
    YR   = 2-digit year suffix
    FY   = MEPS full-year consolidated file number
    MC   = MEPS medical conditions file number
  
  STEPS:
    54: Merge MEPS medical conditions (has CCSR codes) with appendix (links conditions
        to events via CONDIDX -> EVNTIDX)
    55: Many-to-many merge between appendix-linked conditions and Rx claims via 
        EVNTIDX = LINKIDX. This maps each Rx claim to associated CCSR diagnoses.
    56: Merge with full-year to keep only private population (prvev=1, mcrev=2)
    57b: Split wide CCSR (ccsr1x, ccsr2x, ccsr3x) into separate datasets
    58b: Stack into long format (one row per NDC x CCSR)
------------------------------------------------------------------------------------------*/
%macro MEPS_NDC_CCSR_XWALK (FILE=, YR=, FY=, MC=);
	*54) Merge MEPS_MC with MEPS_appendix;
	proc sort
		data=MEPS.h&MC.;
		by condidx;
	run;

	proc sort
		data=MEPS.h&FILE.if1;
		by condidx;
	run;

	data _54_MEPS_medcond_appendix&YR.;
		merge MEPS.h&MC. (in=x keep=condidx CCSR:)
			  MEPS.h&FILE.if1 (in=y drop=panel eventype);
		by condidx;
		if x+y=2;
	run;

	proc sort
		data=MEPS.h&FILE.a;
		by linkidx;
	run;

	proc sort
		data=_54_MEPS_medcond_appendix&YR.;
		by evntidx;
	run;

	*55) Many-to-many merge between Medical conditions, appendix, and prescriber files;
	proc sql noprint;
		create table _55_meps_medcond_appndx_rx&YR. as
		select a.dupersid, a.ccsr1x, a.ccsr2x, a.ccsr3x, a.evntidx, b.linkidx, b.rxrecidx, b.rxndc, b.rxname from _54_MEPS_medcond_appendix&YR. a
		join MEPS.h&FILE.a b
		on a.evntidx = b.linkidx;
	quit;

	*56) Merge with the full year and keep only private patients;
	proc sort
		data=_55_meps_medcond_appndx_rx&YR.;
		by dupersid;
	run;

	proc sort
		data=MEPS.h&FY.;
		by dupersid;
	run;

	data _56_medcond_appndx_rx_fy&YR.;
		merge _55_meps_medcond_appndx_rx&YR. (keep=dupersid rxndc ccsr: in=a) 
			  MEPS.h&FY.(keep=DUPERSID mcrev&YR. prvev&YR.);
		by dupersid;
		if a=1 & prvev&YR.=1 & mcrev&YR.=2 & rxndc>="0";*selecting just priv pop;
		keep rxndc ccsr:;
	run;

	*57b) Separate Wide-Format CCSR to different datasets;
	data _57_MEPS_rx_fy&YR._1 
		 _57_MEPS_rx_fy&YR._2 
		 _57_MEPS_rx_fy&YR._3;
			set _56_medcond_appndx_rx_fy&YR.;
			if ccsr1x ne "-1" then output _57_MEPS_rx_fy&YR._1;
			if ccsr2x ne "-1" then output _57_MEPS_rx_fy&YR._2;
			if ccsr3x ne "-1" then output _57_MEPS_rx_fy&YR._3;
	run;

	*58b) Stack the CCSR together in Long-Format;
	data _58_stacked_MEPS_rx_ndc&YR.;
		set _57_MEPS_rx_fy&YR._1(keep=rxndc ccsr1x rename=(ccsr1x=ccsr)) 
			_57_MEPS_rx_fy&YR._2(keep=rxndc ccsr2x rename=(ccsr2x=ccsr)) 
			_57_MEPS_rx_fy&YR._3(keep=rxndc ccsr3x rename=(ccsr3x=ccsr));
	run;
%mend;
%MEPS_NDC_CCSR_XWALK (FILE=188, YR=16, FY=192, MC=190);
%MEPS_NDC_CCSR_XWALK (FILE=197, YR=17, FY=201, MC=199);
%MEPS_NDC_CCSR_XWALK (FILE=206, YR=18, FY=209, MC=207);
%MEPS_NDC_CCSR_XWALK (FILE=213, YR=19, FY=216, MC=214);
%MEPS_NDC_CCSR_XWALK (FILE=220, YR=20, FY=224, MC=222);
%MEPS_NDC_CCSR_XWALK (FILE=229, YR=21, FY=233, MC=231);
%MEPS_NDC_CCSR_XWALK (FILE=239, YR=22, FY=243, MC=241);
%MEPS_NDC_CCSR_XWALK (FILE=248, YR=23, FY=251, MC=249);
*^^UPDATE HERE #29, with the new year we're trying to estimate for the HCSA;

/*------------------------------------------------------------------------------------------
Step 59 (COMMENTED OUT): Stack Pre-2016 and 2016+ NDC-CCSR Crosswalks
  - Combines CCS-to-CCSR converted data (_58_meps_ccs_to_ccsr:) with direct CCSR data 
    (_58_stacked_meps_rx_ndc:)
  - Drops invalid NDC "99999999996" per CMS guidance
  - Reassigns MEPS "000" catchall CCSRs to legitimate codes:
    e.g., BLD000 -> BLD010, CIR000 -> CIR032, etc.
    These catchalls are MEPS-internal codes that don't correspond to real CCSR categories.
------------------------------------------------------------------------------------------*/
/*INTENTIONALLY COMMENTED OUT (below). Re-run to writeover only if necessary.
*59) Stack 2000-15 with 2016-present. Eliminate duplicates;
data INPUTS.meps_ndc_ccsr99_&SHORT_YEAR. ;
	set _58_meps_ccs_to_ccsr: (drop=ccs rename=(ccsr_category=ccsr))
		_58_stacked_meps_rx_ndc:;
	if rxndc="99999999996" then delete;*CMS drops it (https://www.resdac.org/cms-data/variables/product-service-id);
	*LASANTHI: 000 is not a valid CCSR, it's a catchall MEPS created for themselves. I'm choosing to assing it to legit CCSRs;
	if CCSR = "BLD000" then CCSR = "BLD010";
	if CCSR = "CIR000" then CCSR = "CIR032";
	if CCSR = "DIG000" then CCSR = "DIG019";
	if CCSR = "EAR000" then CCSR = "EAR006";
	if CCSR = "END000" then CCSR = "END016";
	if CCSR = "EXT000" then CCSR = "EXT018";
	if CCSR = "EYE000" then CCSR = "EYE012";
	if CCSR = "FAC000" then CCSR = "FAC025";
	if CCSR = "GEN000" then CCSR = "GEN025";
	if CCSR = "INF000" then CCSR = "INF011";
	if CCSR = "INJ000" then CCSR = "INJ064";
	if CCSR = "MAL000" then CCSR = "MAL010";
	if CCSR = "MBD000" then CCSR = "MBD025";
	if CCSR = "MUS000" then CCSR = "MUS028";
	if CCSR = "NEO000" then CCSR = "NEO074";
	if CCSR = "NVS000" then CCSR = "NVS020";
	if CCSR = "PNL000" then CCSR = "PNL013";
	if CCSR = "PRG000" then CCSR = "PRG028";
	if CCSR = "RSP000" then CCSR = "RSP016";
	if CCSR = "SKN000" then CCSR = "SKN007";
	if CCSR = "SYM000" then CCSR = "SYM016";
	run;
^^INTENTIONALLY COMMENTED OUT^^*/

proc sort
	data=INPUTS.meps_ndc_ccsr99_&SHORT_YEAR.
	nodupkeys;
	by rxndc ccsr;
run;

/*------------------------------------------------------------------------------------------
Steps 60-62: Create NDC Dummy Matrix for Trogdon Regressions
  
  Step 60: Merge the NDC-CCSR crosswalk with CCSR label file to get numeric CCSR IDs
    - ccsrnum is a sequential integer (1-543) assigned to each CCSR category
    - This numeric ID ("trog_id") is used as the column index in the dummy matrix
    - Dental CCSRs (DEN*) and invalid CCSRs ("-") are dropped
  
  Step 61: Transpose to wide format
    - Each NDC gets columns trog_id1, trog_id2, ..., trog_idN listing its associated 
      CCSR numeric IDs
  
  Step 62: Convert to binary dummy variables
    - Creates 543 columns: trogndcdummy1 through trogndcdummy543
    - For each NDC, trogndcdummy{j}=1 if the NDC is associated with CCSR number j
    - This matrix is merged with MarketScan Rx claims in Phase 5 to identify which
      diseases each patient's prescriptions could plausibly treat
------------------------------------------------------------------------------------------*/
*60) Merge unique trog identifiers to CCSR categories;
proc sort
	data=INPUTS.meps_ndc_ccsr99_&SHORT_YEAR.;
	by ccsr;
run;

proc sort
	data=INPUTS.ccsr_label_v20231;
	by ccsr;
run;

data _60_ndc_ccsr_w_trog_ids;
	merge INPUTS.meps_ndc_ccsr99_&SHORT_YEAR. (in=x)
		  INPUTS.ccsr_label_v20231 (keep=ccsr ccsrnum rename=(ccsrnum=ccsr_trog_id));
	by ccsr;
	if x=1;
	if ccsr=: "DEN" then delete; *Delete dental conditions;
	if ccsr=: "-" then delete;
run;

*61) Transpose to wide;
proc sort
	data=_60_ndc_ccsr_w_trog_ids;
	by rxndc ccsr_trog_id;
run;

proc transpose
	data=_60_ndc_ccsr_w_trog_ids
	out=_61_ccsr_ndc_wide (drop=_name_) 
	prefix=trog_id; 
	by RXNDC;
	var ccsr_trog_id;
run;

*62) Create dummy so that column number corresponds to trog_id number. For example, when the trog_id=167 then there's a corresponding variable called 'trogdummy167=1';
data _62_ndcdum;
	set _61_ccsr_ndc_wide;
	array c(*) trog_id:;
	array dum(1:543) trogndcdummy1-trogndcdummy543;
	do j=1 to 145;
		 dum(j)=0;
	end;
	do i=1 to dim(c);
		do j=1 to 543;
			if c(i)=j then dum(j)=1;
		end;
	end;
	drop i j  trog_id:;
run;

proc sort
	data=_62_ndcdum(rename=(rxndc=ndcnum));
	by ndcnum;
run;


/*##########################################################################################
##                                                                                        ##
##   PHASE 5: MARKETSCAN CLAIMS PROCESSING & TROGDON REGRESSIONS                         ##
##   Steps 63-93 (the %marketscan_claims macro)                                           ##
##                                                                                        ##
##   PURPOSE: This is the computational core of the program. For each year x tag cohort,  ##
##   it processes all MarketScan inpatient, outpatient, and prescription drug claims to    ##
##   produce disease-level (CCSR) spending estimates.                                      ##
##                                                                                        ##
##   PROCESSING PIPELINE (per year x tag):                                                ##
##                                                                                        ##
##   A. INPATIENT/OUTPATIENT CLAIMS (Steps 63-70):                                        ##
##      63-64: Merge IP/OP claims with ICD-to-CCSR crosswalks                             ##
##             - Pre-2015: ICD-9 only                                                      ##
##             - 2015+: Dual ICD-9/ICD-10 (separated by dxver variable)                   ##
##      65: Stack IP + OP claims together                                                  ##
##      66: Merge with person weights from Phase 2                                         ##
##          weighted_pay = weight * pay (grosses up to national level)                     ##
##      67: Assign Trogdon numeric IDs to each claim's CCSR                               ##
##      68: Deduplicate to unique patient x CCSR combinations                              ##
##      69-70: Create patient-level CCSR dummy matrix (trogccsrdummy1-543)                ##
##                                                                                        ##
##   B. PRESCRIPTION DRUG CLAIMS (Steps 71-77):                                           ##
##      71: Apply SSR rebates to Rx claims                                                 ##
##          - Pre-2007: No rebate adjustment (pay_netofrebate = pay)                       ##
##          - 2007+: pay_netofrebate = (1-GM)*pay*(1-discount) + GM*pay                    ##
##            where GM = gross_margin (0.035)                                              ##
##      72: Merge Rx claims with person weights                                            ##
##      73: Sum each patient's annual Rx expenditure                                       ##
##      74-76: Create "intersection dummies" — for each patient's Rx claims, determine    ##
##             which CCSRs appear in BOTH their IP/OP diagnoses AND their NDC's            ##
##             MEPS-derived CCSR associations. Only the intersection is used in the         ##
##             regression, ensuring drugs are only attributed to diseases the patient       ##
##             actually has.                                                                ##
##      77: Merge total Rx dollars with intersection dummies and take log(pay+1)           ##
##                                                                                        ##
##   C. TROGDON REGRESSION (Steps 78-86):                                                  ##
##      The "Trogdon method" regresses log(total Rx spending) on disease indicator          ##
##      variables. The regression is:                                                       ##
##        log(pay + 1) = intercept + Σ β_j * CCSR_dummy_j + ε                             ##
##      where CCSR_dummy_j = 1 if the patient has disease j (intersection of IP/OP         ##
##      diagnosis and NDC-CCSR association).                                                ##
##                                                                                        ##
##      The coefficients are used to allocate each patient's Rx spending:                  ##
##        1. Exponentiate coefficients: exp(β_j) * dummy_j                                ##
##        2. Compute disease shares: S_j = exp(β_j)*dummy_j / Σ exp(β_k)*dummy_k          ##
##        3. Compute disease-attributable spending plus intercept:                          ##
##           ETGdisease = exp(intercept + Σ β_j*dummy_j) * exp(ε) - exp(intercept)*exp(ε) ##
##           doll_int = exp(intercept) * exp(ε) - 1                                        ##
##        4. Force intercept to diseases: dolld_j = (ETGdisease + doll_int) * S_j          ##
##           This distributes ALL spending (including the intercept) across diseases        ##
##      78: Run weighted PROC REG                                                          ##
##      79-80: Extract and merge coefficients back to patient data                         ##
##      81: Compute disease-level dollar allocations per patient                           ##
##      82: Sum weighted disease dollars across all patients                               ##
##      83-86: Transpose to long format and clean up                                       ##
##                                                                                        ##
##   D. COMBINE IP/OP + Rx (Steps 87-93):                                                  ##
##      87: Merge CCSR labels onto Rx regression results                                   ##
##      88: Sum IP/OP weighted payments by CCSR                                            ##
##      89-92: Count weighted patients by CCSR from the IP/OP dummy matrix                 ##
##      93: Merge IP/OP spending + Rx spending + patient counts per CCSR                   ##
##          dollars{YEAR}_{TAG} = ipop_pay + rx_dollars_netrebate                          ##
##                                                                                        ##
##   SPECIAL CASE - YEAR 2007:                                                             ##
##      For 2007 only, the regression is run TWICE: once on log(pay_netofrebate+1) and     ##
##      once on log(pay+1). The original-pay version is needed for the pre-2007 rebate     ##
##      backcasting in Phase 6 (the difference between the two = 2007 rebate dollars).     ##
##                                                                                        ##
##   MEMORY MANAGEMENT: After processing each year, intermediate datasets (_63_ through    ##
##      _81_) are deleted to keep the work library manageable.                             ##
##                                                                                        ##
##########################################################################################*/

%macro marketscan_claims (YEAR=, TAG=, LIB=, YR=);
	/*==================================================================================
	  PART A: INPATIENT/OUTPATIENT CLAIMS PROCESSING
	==================================================================================*/

	%if &TAG.=A %then %do;
		/*----------------------------------------------------------------------
		Steps 63-64: Merge MarketScan Claims with ICD-to-CCSR Crosswalks
		  
		  PRE-2015 (ICD-9 only):
		    - All claims use ICD-9 codes in dx1
		    - Merged with INPUTS.icd9ccsrip_format (inpatient) and 
		      INPUTS.icd9ccsrop_format (outpatient)
		    - dx1 is the PRIMARY diagnosis on the claim; we do not use 
		      secondary diagnoses because BEA research shows the additional 
		      complexity makes little difference in aggregate results
		  
		  2015+ (Dual ICD-9/ICD-10):
		    - The dxver variable indicates the coding system:
		      dxver="9" -> ICD-9, dxver="0" -> ICD-10
		    - Each coding system is merged with its respective crosswalk
		    - ICD-9 and ICD-10 results are then stacked together
		    - Note: 2015 was a transition year; claims could be either system
		----------------------------------------------------------------------*/
		%if &YEAR. < 2015 %then %do;
			*63) Merge marketscan inpatient (icd9) claims with CCSR;
			proc sort
				data=&LIB..CCAES&YR.;
				by dx1;
			run;

			proc sort
				data=INPUTS.icd9ccsrip_format;
				by start;
			run;

			data _63_mktscn_ip_w_ccsr&YEAR.;
				merge &LIB..CCAES&YR. (keep=enrolid dx1 pay in=x)
					  INPUTS.icd9ccsrip_format (keep=start ccsr rename=(start=dx1));
				by dx1;
				if x=1;
			run;

			*64) Merge marketscan outpatient (icd9) claims with CCSR;
			proc sort
				data=&LIB..CCAEO&YR.;
				by dx1;
			run;

			proc sort
				data=INPUTS.icd9ccsrop_format;
				by start;
			run;

			data _64_mktscn_op_w_ccsr&YEAR.;
				merge &LIB..CCAEO&YR. (keep=enrolid dx1 pay in=x)
					  INPUTS.icd9ccsrop_format (keep=start ccsr rename=(start=dx1));
				by dx1;
				if x=1;
			run;
		%end;

		%if &YEAR.>=2015 %then %do;
			*63a) Merge marketscan inpatient (icd9) claims with CCSR;
			proc sort
				data=&LIB..CCAES&YR.;
				by dx1;
			run;

			proc sort
				data=INPUTS.icd9ccsrip_format;
				by start;
			run;

			data _63a_mktscn_ip_icd9_w_ccsr&YEAR.;
				merge &LIB..CCAES&YR. (keep=enrolid dx1 dxver pay in=x where=(dxver="9"))
					  INPUTS.icd9ccsrip_format (keep=start ccsr rename=(start=dx1));
				by dx1;
				if x=1;
				drop dxver;
			run;

			*63b) Merge marketscan inpatient (icd10) claims with CCSR;
			proc sort
				data=INPUTS.ccsrip_format;
				by start;
			run;

			data _63b_mktscn_ip_icd10_w_ccsr&YEAR.;
				merge &LIB..CCAES&YR. (keep=enrolid dx1 dxver pay in=x where=(dxver="0"))
					  INPUTS.ccsrip_format (keep=start ccsr rename=(start=dx1));
				by dx1;
				if x=1;
				drop dxver;
			run;

			*63) Stack inpatient icd9 & icd10 together;
			data _63_mktscn_ip_w_ccsr&YEAR.;
				set _63a_mktscn_ip_icd9_w_ccsr&YEAR.
					_63b_mktscn_ip_icd10_w_ccsr&YEAR.;
			run;

			*64a) Merge marketscan outpatient (icd9) claims with CCSR;
			proc sort
				data=&LIB..CCAEO&YR.;
				by dx1;
			run;

			proc sort
				data=INPUTS.icd9ccsrop_format;
				by start;
			run;

			data _64a_mktscn_op_icd9_w_ccsr&YEAR.;
				merge &LIB..CCAEO&YR. (keep=enrolid dx1 dxver pay in=x where=(dxver="9"))
					  INPUTS.icd9ccsrop_format (keep=start ccsr rename=(start=dx1));
				by dx1;
				if x=1;
				drop dxver;
			run;

			*64b) Merge marketscan outpatient (icd10) claims with CCSR;
			proc sort
				data=INPUTS.ccsrop_format;
				by start;
			run;

			data _64b_mktscn_op_icd10_w_ccsr&YEAR.;
				merge &LIB..CCAEO&YR. (keep=enrolid dx1 dxver pay in=x where=(dxver="0"))
					  INPUTS.ccsrop_format (keep=start ccsr rename=(start=dx1));
				by dx1;
				if x=1;
				drop dxver;
			run;

			*63) Stack outpatient icd9 & icd10 together;
			data _64_mktscn_op_w_ccsr&YEAR.;
				set _64a_mktscn_op_icd9_w_ccsr&YEAR.
					_64b_mktscn_op_icd10_w_ccsr&YEAR.;
			run;
		%end;

		*65) Stack ip + op;
		data _65_mktscn_ipop&YEAR.;
			set _63_mktscn_ip_w_ccsr&YEAR.
				_64_mktscn_op_w_ccsr&YEAR.;
		run;
	%end;

	/*==================================================================================
	  Steps 66-70: Apply Weights & Build Patient-Level CCSR Dummy Matrix for IP/OP
	==================================================================================*/

	/*----------------------------------------------------------------------
	Step 66: Merge Claims with Person Weights
	  - Inner join between IP/OP claims and enrollment file (with weights)
	  - Only keeps patients present in both files AND with positive weight
	  - weighted_pay = weight * pay: scales the claim to national level
	----------------------------------------------------------------------*/
	*66) Merge with patient weights;
	proc sort
		data=_65_mktscn_ipop&YEAR.;
		by enrolid;
	run;

	proc sort
		data=INPUTS.Enr_file_w_weight_00_&SHORT_YEAR._&TAG.;
		by enrolid;
	run;

	data _66_mktscn_weighted_ipop&YEAR._&TAG.;
		merge _65_mktscn_ipop&YEAR. (in=x)
			  INPUTS.Enr_file_w_weight_00_&SHORT_YEAR._&TAG. (keep=enrolid year weight in=y where=(year=&YEAR.));
		by enrolid;
		if enrolid ne .; *Drop missing patients;
		if x+y=2;
		if weight>0;
		weighted_pay = weight*pay;
	run;

	/*----------------------------------------------------------------------
	Steps 67-70: Build Patient-Level CCSR Dummy Matrix
	  67: Assign Trogdon numeric IDs to each claim's CCSR
	  68: Deduplicate to unique enrolid x CCSR (so each patient has each 
	      disease listed only once)
	  69: Transpose to wide (one row per patient, columns for each CCSR ID)
	  70: Convert to binary dummies (trogccsrdummy1-543)
	      trogccsrdummy{j} = 1 if the patient has any IP/OP claim for CCSR j
	----------------------------------------------------------------------*/
	*67) Assign trog id;
	proc sort
		data=_66_mktscn_weighted_ipop&YEAR._&TAG.;
		by ccsr;
	run;

	proc sort
	data=INPUTS.ccsr_label_v20231;
	by ccsr;
	run;

	data _67_inout_w_trog_id&YEAR._&TAG.;
		merge _66_mktscn_weighted_ipop&YEAR._&TAG. (in=x keep=enrolid ccsr weight)
			  INPUTS.ccsr_label_v20231 (keep=ccsr ccsrnum rename=(ccsrnum=ccsr_trog_id));
		by ccsr;
		if x=1;
		if ccsr=: "DEN" | ccsr=: "-" | ccsr=: "" then delete; *Delete dental conditions;
		count=1;
	run;

	*68) Unique CCSR for each patient;
	proc sort
		data=_67_inout_w_trog_id&YEAR._&TAG. 
		nodupkeys 
		out=_68_inout_pat_ccsr&YEAR._&TAG. (keep=enrolid ccsr ccsr_trog_id weight count);
		by enrolid ccsr; 
	run;

	*69) Transpose to wide;
	proc transpose
		data=_68_inout_pat_ccsr&YEAR._&TAG. 
		out=_69_inout_wide&YEAR._&TAG. prefix=trog_id; 
		by enrolid weight count;
		var ccsr_trog_id;
	run;

	*70) Create patient ip_op ccsr dummy;
	data _70_inout_w_dum&YEAR._&TAG.;
		set _69_inout_wide&YEAR._&TAG. (drop=_name_);
		array c(*) trog_id:;
		array dum(1:543) trogccsrdummy1-trogccsrdummy543;
		do j=1 to 543;
			 dum(j)=0;
		end;
		do i=1 to dim(c);
			do j=1 to 543;
				if c(i)=j then dum(j)=1;
			end;
		end;
		drop i j trog_id:;
	run;

	/*==================================================================================
	  PART B: PRESCRIPTION DRUG CLAIMS PROCESSING
	==================================================================================*/

	%if &TAG.=A %then %do;
		/*----------------------------------------------------------------------
		Step 71: Apply Rebates to Prescription Drug Claims
		  
		  PRE-2007: No SSR data available, so pay_netofrebate = pay
		  
		  2007+: Merge Rx claims with SSR NDC crosswalk (from Phase 3)
		    For drugs with SSR data (SSR_Flag=1):
		      pay_netofrebate = (1 - gross_margin) * pay * (1 - discount_rate)
		                      + gross_margin * pay
		    For drugs without SSR data:
		      pay_netofrebate = pay (no adjustment)
		    
		    Intuition: The non-pharmacy portion (1-GM) of the price gets the full
		    rebate discount. The pharmacy markup portion (GM=3.5%) is retained.
		----------------------------------------------------------------------*/
		*71) Apply rebates to drugs;
		%if &YEAR.<=2006 %then %do;
			data _71_mktscn_rx&YEAR.;
				set &LIB..CCAED&YR.;
				pay_netofrebate=pay;
				drugfile="d";
			run;
		%end;
		%else %if &YEAR.>=2007 %then %do;
			proc sort
				data=&LIB..CCAED&YR.;
				by ndcnum;
			run;

			proc sort
				data=INPUTS.Ssr_ndc_xwalk_retail_tot&BLEND_NEWYEAR.;
				by ndcnum;
			run;

			data _71_mktscn_rx&YEAR.;
				merge &LIB..CCAED&YR. (in=x)
					  INPUTS.Ssr_ndc_xwalk_retail_tot&BLEND_NEWYEAR. (DROP=lowcase_redbook: where=(year=&YEAR.));
				by ndcnum;
				if x=1;
				if SSR_Flag = 1 then do;
					pay_netofrebate= (1-gross_margin)*pay *(1- avgyrly_tot_discount_rate) + gross_margin * pay; *Rebate adjustment;
				end;
				else do;
					pay_netofrebate=pay;
				end;
				drugfile="d";
			run;
		%end;
	%end;

	/*----------------------------------------------------------------------
	Steps 72-73: Weight Rx Claims & Sum Patient Annual Expenditure
	  72: Merge Rx claims with person weights (same logic as step 66)
	  73: Sum pay and pay_netofrebate by patient to get annual Rx totals
	----------------------------------------------------------------------*/
	*72) Merge rx with person weights;
	proc sort
		data=_71_mktscn_rx&YEAR.;
		by enrolid;
	run;

	proc sort
		data=INPUTS.Enr_file_w_weight_00_&SHORT_YEAR._&TAG.;
		by enrolid;
	run;

	data _72_mktscn_weighted_rx&YEAR._&TAG.;
		merge _71_mktscn_rx&YEAR. (in=x keep=enrolid NDCnum pay:)
			  INPUTS.Enr_file_w_weight_00_&SHORT_YEAR._&TAG. (keep=enrolid year weight in=y where=(year=&YEAR.));
		by enrolid;
		if enrolid ne .;
		if x+y=2;
		if weight>0;
	run;

	proc sort
		data=_72_mktscn_weighted_rx&YEAR._&TAG.; 
		by enrolid;
	run;

	*73) Each patients annual rx expenditure;
	proc means
		data=_72_mktscn_weighted_rx&YEAR._&TAG. noprint;
		by enrolid;
		var pay pay_netofrebate;
		output out=_73_iddrugpay_mkt&YEAR._&TAG. (drop=_:) sum()=;
	run;

	/*----------------------------------------------------------------------
	Steps 74-76: Create Intersection Dummies
	  PURPOSE: For each patient's Rx claims, determine which diseases could
	  plausibly explain their prescriptions by intersecting:
	    (a) The patient's IP/OP-diagnosed CCSRs (from step 70)
	    (b) The NDC's MEPS-derived CCSR associations (from step 62)
	  
	  Only diseases in the intersection are used in the Trogdon regression.
	  This prevents attributing a drug to a disease the patient doesn't have.
	  
	  74: Merge each Rx claim's NDC-level CCSR dummies with the patient's 
	      IP/OP CCSR dummies
	  75: Compute intersection: intersectdummy{j} = 1 if BOTH 
	      trogccsrdummy{j}=1 AND trogndcdummy{j}=1
	  76: Aggregate intersection dummies by patient (since a patient may have
	      multiple Rx claims with different NDCs)
	----------------------------------------------------------------------*/
	*74) Merge ipop_ccsrdum to drug claims;
	data _74_ipop_rx_ccsr&YEAR._&TAG.; 
		merge _72_mktscn_weighted_rx&YEAR._&TAG.(in=a drop=pay) 
			  _70_inout_w_dum&YEAR._&TAG.(in=b);
		by enrolid;
		if a+b=2;
	run;

	*75) Merge meps_ndc dummies to each claims;
	proc sort
		data=_74_ipop_rx_ccsr&YEAR._&TAG.;
		by ndcnum;
	run;

	data _75_ipop_rx_ndc_ccsr&YEAR._&TAG.;
		merge _74_ipop_rx_ccsr&YEAR._&TAG.(in=a) 
			  _62_ndcdum(in=b);
		by ndcnum;
		if a+b=2;
		*Intersection of ccsdummy and ndcdummy;
		array cal(3,1:543) trogccsrdummy1-trogccsrdummy543 trogndcdummy1-trogndcdummy543 intersectdummy1-intersectdummy543;
		array cd (*) 3. intersectdummy1-intersectdummy543;
		do j=1 to 543;
			 cal(3,j)=0;
		end;
		do i=1 to 543;
			if cal(1,i)+cal(2,i)=2 then cal(3,i)=1;
		end;
		keep enrolid weight intersectdummy:;
	run;

	*76) Aggregate intersecting ccsrdummy by id;
	proc sort
		data=_75_ipop_rx_ndc_ccsr&YEAR._&TAG.;
		by enrolid;
	run;

	proc means
		data=_75_ipop_rx_ndc_ccsr&YEAR._&TAG. noprint nway;
		by enrolid;
		id weight;
		var intersectdummy:;
		output out=_76_agg_id_ccsr&YEAR._&TAG. sum=;
	run;

	/*----------------------------------------------------------------------
	Step 77: Prepare Regression Dataset
	  - Merges aggregated intersection dummies with patient's total Rx pay
	  - Converts intersection dummies to binary (>0 becomes 1)
	  - Takes log(pay + 1) as the dependent variable
	    The +1 prevents log(0) for patients with zero spending
	  - Both log(pay_netofrebate+1) and log(pay+1) are computed
	    (pay is the original gross amount; pay_netofrebate has rebates removed)
	----------------------------------------------------------------------*/
	*77) Attach total drug dollars for each patient;
	data _77_rx_pay_w_ccsr&YEAR._&TAG.;
		merge _76_agg_id_ccsr&YEAR._&TAG.(in=a) 
			  _73_iddrugpay_mkt&YEAR._&TAG.(in=b keep=enrolid pay:);
		by enrolid;
		if a+b=2;
		array orig(2, 1:543) intersectdummy1-intersectdummy543 ccsrdummy1-ccsrdummy543;
			do i=1 to 543;
				orig(2,i)=0;
				if orig(1,i)>0 then orig(2,i)=1;
			end;
		*Normalize by taking the log of the dollars and adding 1 this data is unweighted;
		logdollars_paynetofrebate = log(pay_netofrebate +1);
		logdollars_pay = log(pay+1);
		drop i _: intersectdummy: ;
	run;

	/*==================================================================================
	  PART C: TROGDON REGRESSION
	  
	  References: Trogdon, Finkelstein, Nwaise (2008). "The Economic Burden of Chronic 
	  Cardiovascular Disease for Major Insurers." Health Promotion Practice.
	  
	  The method regresses each patient's total Rx spending on binary indicators for
	  whether the patient has each disease. The model is estimated in logs (to handle
	  right-skewed spending distributions) and weighted by person weights. The intercept
	  is then "forced" back into disease categories proportionally, so that ALL Rx 
	  spending is attributed to diseases (nothing remains in the intercept).
	==================================================================================*/

	/*----------------------------------------------------------------------
	Step 78: Run Weighted Log-Linear Regression
	  - Dependent variable: log(pay_netofrebate + 1)
	  - Independent variables: ccsrdummy1 through ccsrdummy543
	  - Weight: person weight from Phase 2
	  - Outputs:
	    _78a_coefs: regression coefficients (one row, 543 columns)
	    _78b_pats_pred: patient-level predicted values (phat) and residuals (res)
	----------------------------------------------------------------------*/
	*78) Residuals(res), standard errors(outseb), predicted(phat), coefficients(coefs), input(patients_pred);
	proc reg
		data=_77_rx_pay_w_ccsr&YEAR._&TAG. 
		outest=_78a_coefs_netrebate&YEAR._&TAG. noprint;
		model logdollars_paynetofrebate =ccsrdummy1-ccsrdummy543 / outseb;
		weight weight;
		output out=_78b_pats_pred_netrebate&YEAR._&TAG. p=phat r=res;
	run;
	quit;

	/*----------------------------------------------------------------------
	Step 79: Extract Coefficients
	  - The first observation of the outest dataset contains the coefficients
	  - Rename ccsrdummy{j} to trog_est{j} for clarity in subsequent calculations
	----------------------------------------------------------------------*/
	*79) The first obs of data should be the coefficients;
	data _79_coefsobs1_netrebate&YEAR._&TAG.;
		set _78a_coefs_netrebate&YEAR._&TAG. (drop=_model_ _type_ _depvar_ obs=1);
		%macro rename;
			%do j=1 %to 543; 
				rename ccsrdummy&J. = trog_est&J.;
			%end; 
		%mend; %rename; 
		drop logdollars_paynetofrebate;
	run;

	/*----------------------------------------------------------------------
	Step 80: Merge Coefficients with Patient-Level Data
	  - Cartesian join: every patient gets the same set of coefficients
	  - After this, each patient row has: their dummies, their residual, 
	    predicted value, AND the coefficient for every disease
	----------------------------------------------------------------------*/
	*80) Merge coeffients with original data;
	proc sql;
		create table _80_pat_coefs_netrebate&YEAR._&TAG. as
		select
			a.*,
			b.*
		from
			_78b_pats_pred_netrebate&YEAR._&TAG. as a,
			_79_coefsobs1_netrebate&YEAR._&TAG. as b
		;
	quit;

	/*----------------------------------------------------------------------
	Step 81: Allocate Rx Spending to Diseases (Trogdon Method)
	  
	  Arrays used (6 layers x 543 diseases):
	    Row 1: ccsrdummy     - binary indicator (patient has disease j)
	    Row 2: trog_est      - regression coefficient for disease j
	    Row 3: trog_exp_est  - exp(β_j) * dummy_j 
	    Row 4: trog_SK       - disease j's share of total exp(β) sum
	    Row 5: dis           - dummy_j * β_j (contribution to linear predictor)
	    Row 6: rebatedolld   - allocated dollar amount for disease j
	  
	  ALLOCATION LOGIC:
	    1. trog_exp_est_j = exp(β_j) * dummy_j
	       - Exponentiated coefficient, zeroed out for diseases patient doesn't have
	    2. trog_SK_j = trog_exp_est_j / sum(trog_exp_est)
	       - Share of each disease in the patient's exponentiated total
	    3. ETGdisease = [exp(intercept + Σ dis_j) * exp(residual)] - [exp(intercept) * exp(residual)]
	       - Total disease-attributable spending (the predicted part minus intercept part)
	    4. doll_int_rebate = exp(intercept) * exp(residual) - 1
	       - Spending attributable to the intercept
	    5. rebatedolld_j = (ETGdisease + doll_int_rebate) * trog_SK_j
	       - FORCES the intercept into disease categories, so all spending is allocated
	    
	    CHECK: sum(rebatedolld:) should equal the patient's actual pay_netofrebate
	----------------------------------------------------------------------*/
	*81) Assign dollars+intercept to diseases;
	data _81_pat_with_est_netrebate&YEAR._&TAG.;
		set _80_pat_coefs_netrebate&YEAR._&TAG.;
		array trog(6, 1:543) ccsrdummy1-ccsrdummy543 trog_est1-trog_est543 trog_exp_est1-trog_exp_est543 trog_SK1-trog_SK543 dis1-dis543 rebatedolld1-rebatedolld543;

		*trog_exp_est - exponentiate the coefficient and then set to 0 if the person does not have the disease;
		do j=1 to 543;
		trog(3,j)=exp(trog(2,j))*trog(1,j);
		end;
		trog_exp_est_sum=sum(of trog_exp_est:);*calculate a share for each disease a person has (see eqn 1 of Trogdon);

		*trog_sk;
		do j=1 to 543;
		trog(4,j)=trog(3,j)/trog_exp_est_sum;
			if trog(4,j) = . then trog(4,j)= 0;

		*dis;
		trog(5,j)=trog(1,j)*trog(2,j);*Amount of spending attributable to diseases versus the intercept;
		end;

		ETGdisease=((exp(sum(intercept, sum(of dis:))) * exp(res))-exp(intercept)*exp(res));
		doll_int_rebate=(exp(intercept)*exp(res))-1;*Amount of spending given to the intercept;

		*dolld = multiply share of the spending for each disease by the amount of spending all diseases to get the amount of spending for each disease;
		do j=1 to 543;
		trog(6,j) = ((ETGdisease+doll_int_rebate)*trog(4,j));*forcing intercept to disease;
		end;

		*Check Trogdon predicted spending=actual spending;
		pred=sum(of rebatedolld:);
		one=-1;
		drop j;
	run;

	/*----------------------------------------------------------------------
	Steps 82-86: Aggregate & Clean Regression Results
	  82: Sum disease dollars across all patients (weighted)
	  83: Transpose from wide to long
	  86: Extract CCSR numeric ID from variable name, drop intercept row
	----------------------------------------------------------------------*/
	*82) Sum dollars for each disease;
	proc means
		data=_81_pat_with_est_netrebate&YEAR._&TAG. noprint nway ;
		var one rebatedolld1-rebatedolld543 doll_int_rebate;
		weight weight;
		output out=_82_cross_class_netrebate&YEAR._&TAG.  sum=one ccsrdummy1-ccsrdummy543 intercept;
	run;

	*83) Transpose to long-format; 
	proc transpose
		data=_82_cross_class_netrebate&YEAR._&TAG. (keep=one intercept ccsrdummy:) 
		out=_83_cross_netrebate_long&YEAR._&TAG.;
	run;

	proc sort
		data=_83_cross_netrebate_long&YEAR._&TAG.; 
		by _name_; 
	run;

	*86) Clean up;
	data _86_rx_expend&YEAR._&TAG.;
		set _83_cross_netrebate_long&YEAR._&TAG. (rename=(col1=rx_dollars_netrebate));
		year=&YEAR.;
		if _NAME_="intercept" | _NAME_="one" then delete;
		ccsrdum=substr(_NAME_,10,3)*1;
		drop _NAME_;
	run;

	/*----------------------------------------------------------------------
	Step 87: Merge CCSR Labels to Regression Results
	----------------------------------------------------------------------*/
	*87) Merge CCSR to the dummies;
	proc sort
		data=INPUTS.ccsr_label_v20231;
		by ccsrnum;
	run;

	proc sort
		data=_86_rx_expend&YEAR._&TAG.;
		by ccsrdum;
	run;

	%if &YEAR. ne 2007 %then %do;
		data _87_rx_mktscn_reg_fin&YEAR._&TAG.;
			merge _86_rx_expend&YEAR._&TAG. (in=x)
				  INPUTS.ccsr_label_v20231 (rename=(ccsrnum=ccsrdum));
			by ccsrdum;
			if x=1;
			if ccsr=: "DEN" then delete;
		run;
	%end;

	/*----------------------------------------------------------------------
	SPECIAL CASE: Year 2007 - Run Regression on Original (Unrebated) Pay Too
	  For pre-2007 rebate backcasting (Phase 6), we need the difference between
	  original pay and rebated pay in 2007. So we run the Trogdon regression a 
	  second time using log(pay+1) as the dependent variable.
	  The 2007 _87_ dataset then contains both rx_dollars_netrebate and rx_dollars_ogpay.
	----------------------------------------------------------------------*/
	*For 2007 only, need the original (unrebated) pay version;
	%if &YEAR.=2007 %then %do;
		proc reg
			data=_77_rx_pay_w_ccsr&YEAR._&TAG. 
			outest=_78a_coefs_ogpay&year._&TAG. noprint;
			model logdollars_pay =ccsrdummy1-ccsrdummy543 / outseb;
			weight weight;
			output out=_78b_pats_pred_ogpay&YEAR._&TAG. p=phat r=res;
		run;
		quit;

		data _79_coefsobs1_ogpay&YEAR._&TAG.;
			set _78a_coefs_ogpay&YEAR._&TAG. (drop=_model_ _type_ _depvar_ obs=1);
			%macro rename;
				%do j=1 %to 543; 
					rename ccsrdummy&J. = trog_est&J.;
				%end; 
			%mend; %rename; 
			drop logdollars_pay;
		run;

		proc sql;
			create table _80_pat_coefs_ogpay&YEAR._&TAG. as
			select
				a.*,
				b.*
			from
				_78b_pats_pred_ogpay&YEAR._&TAG. as a,
				_79_coefsobs1_ogpay&YEAR._&TAG. as b
			;
		quit;

		data _81_pat_with_est_ogpay&YEAR._&TAG.;
			set _80_pat_coefs_ogpay&YEAR._&TAG.;
			array trog(6, 1:543) ccsrdummy1-ccsrdummy543 trog_est1-trog_est543 trog_exp_est1-trog_exp_est543 trog_SK1-trog_SK543 dis1-dis543 dolld1-dolld543;

			*trog_exp_est - exponentiate the coefficient and then set to 0 if the person does not have the disease;
			do j=1 to 543;
			trog(3,j)=exp(trog(2,j))*trog(1,j);
			end;
			trog_exp_est_sum=sum(of trog_exp_est:);*Calculate a share for each disease a person has (see eqn 1 of Trogdon);

			*trog_sk;
			do j=1 to 543;
			trog(4,j)=trog(3,j)/trog_exp_est_sum;
				if trog(4,j) = . then trog(4,j)= 0;

			*dis;
			trog(5,j)=trog(1,j)*trog(2,j);*Amount of spending attributable to diseases versus the intercept;
			end;

			ETGdisease=((exp(sum(intercept, sum(of dis:))) * exp(res))-exp(intercept)*exp(res));
			doll_int=(exp(intercept)*exp(res))-1;*Amount of spending given to the intercept;

			*dolld = multiply share of the spending for each disease by the amount of spending all diseases to get the amount of spending for each disease;
			do j=1 to 543;
			trog(6,j) = ((ETGdisease+doll_int)*trog(4,j));*forcing intercept to disease;
			end;

			*Check Trogdon predicted spending=actual spending;
			pred=sum(of dolld:);
			one=-1;
			drop j;
		run;

		proc means
			data=_81_pat_with_est_ogpay&YEAR._&TAG. noprint nway ;
			var one dolld1-dolld543 doll_int;
			weight weight;
			output out=_82_cross_class_ogpay&YEAR._&TAG.  sum=one ccsrdummy1-ccsrdummy543 intercept;
		run;

		proc transpose
			data=_82_cross_class_ogpay&YEAR._&TAG. (keep=one intercept ccsrdummy:) 
			out=_83_cross_ogpay_long&YEAR._&TAG.;
		run;

		proc sort
			data=_83_cross_ogpay_long&YEAR._&TAG.; 
			by _name_; 
		run;

		data _86_rx_expend_ogpay&YEAR._&TAG.;
			set _83_cross_ogpay_long&YEAR._&TAG. (rename=(col1=rx_dollars_ogpay));
			year=&YEAR.;
			if _NAME_="intercept" | _NAME_="one" then delete;
			ccsrdum=substr(_NAME_,10,3)*1;
			drop _NAME_;
		run;

		proc sort
			data=_86_rx_expend_ogpay&YEAR._&TAG.;
			by ccsrdum;
		run;

		data _87_rx_mktscn_reg_fin&YEAR._&TAG.;
			merge _86_rx_expend&YEAR._&TAG. (in=x)
		 		  _86_rx_expend_ogpay&YEAR._&TAG.
				  INPUTS.ccsr_label_v20231 (rename=(ccsrnum=ccsrdum));
			by ccsrdum;
			if x=1;
			if ccsr=: "DEN" then delete;
		run;
	%end;

	/*==================================================================================
	  PART D: COMBINE IP/OP + Rx SPENDING BY CCSR
	==================================================================================*/

	/*----------------------------------------------------------------------
	Steps 88-92: Aggregate IP/OP Spending and Patient Counts by CCSR
	  88: Sum weighted IP/OP payments by CCSR
	  89-90: Sum the trogccsrdummy matrix (weighted) to get patient counts per CCSR
	  91-92: Clean and merge with CCSR labels
	----------------------------------------------------------------------*/
	*88) Sum ip_op pay by ccsr;
	proc means
		data=_66_mktscn_weighted_ipop&YEAR._&TAG. noprint nway;
		class ccsr;
		var weighted_pay;
		id year;
		output out=_88_mkt_ipop_ccsr_sum&YEAR._&TAG. (drop=_:) sum()=ipop_pay;
	run;

	*89) Sum ip_op patients by ccsr;
	proc means
		data=_70_inout_w_dum&YEAR._&TAG. noprint nway ; 
		var trogccsrdummy1-trogccsrdummy543;
		weight weight;
		output out= _89_ipop_patcounts&YEAR._&TAG. sum=; 
	run;

	*90) Transpose patient counts to long-format;
	proc transpose
		data=_89_ipop_patcounts&YEAR._&TAG. (keep=trogccsrdummy:) 
		out=_90_ipop_patcounts_long&YEAR._&TAG.; 
	run;

	*91) Clean ipop pats;
	data _91_clean_ipop_pats&YEAR._&TAG.;
		set _90_ipop_patcounts_long&YEAR._&TAG.;
		if _NAME_="intercept" | _NAME_="one" then delete;
		ccsrdum=substr(_NAME_,14,3)*1;
		drop _NAME_;
	run;

	*92) Merge CCSR to the dummies;
	proc sort
		data=INPUTS.ccsr_label_v20231;
		by ccsrnum;
	run;

	proc sort
		data=_91_clean_ipop_pats&YEAR._&TAG.;
		by ccsrdum;
	run;

	data _92_ipop_pats&YEAR._&TAG.;
		merge _91_clean_ipop_pats&YEAR._&TAG. (in=x rename=(col1=patients_&YEAR._&tag.))
			  INPUTS.ccsr_label_v20231 (rename=(ccsrnum=ccsrdum) drop=ccsr_label ccsr_chpt:);
		by ccsrdum;
		if x=1;
		year=&YEAR.;
		if ccsr=: "DEN" then delete;
	run;

	/*----------------------------------------------------------------------
	Step 93: Final Merge - IP/OP Spending + Rx Spending + Patient Counts
	  - Combines all three components by year x CCSR
	  - dollars{YEAR}_{TAG} = ipop_pay + rx_dollars_netrebate
	    This is the total disease-level spending for this year x tag combination
	----------------------------------------------------------------------*/
	*93) Merge ip_op with rx;
	proc sort
		data=_88_mkt_ipop_ccsr_sum&YEAR._&TAG.;
		by year ccsr;
	run;

	proc sort
		data=_87_rx_mktscn_reg_fin&YEAR._&TAG.;
		by year ccsr;
	run;

	proc sort
		data=_92_ipop_pats&YEAR._&TAG.;
		by year ccsr;
	run;

	data _93_mktscn_ccsr&YEAR._&TAG.;
		merge _88_mkt_ipop_ccsr_sum&YEAR._&TAG.
			  _87_rx_mktscn_reg_fin&YEAR._&TAG. (drop=ccsrdum)
			  _92_ipop_pats&YEAR._&TAG.;
		by year ccsr;
		dollars&YEAR._&TAG. = sum(ipop_pay,rx_dollars_netrebate);
	run;

	*Cleaning up work space;
	proc datasets lib=work memtype=data nolist;
		delete _63:
			   _64:
			   _74_:
			   _75_:
			   _80_:
			   _81_:;
	quit;
%mend;

/*------------------------------------------------------------------------------------------
%marketscan_claims Macro Calls: One per year x tag
  - TAG=A is the primary estimate; TAG=B is the break-year alternate
  - Years 2004, 2011, 2017 each have two calls (A and B)
  - NOTE: TAG=A runs the full pipeline including IP/OP claims processing (Steps 63-65)
    and Rx rebate application (Step 71). TAG=B skips these since they were already 
    created by the TAG=A call for the same year.
------------------------------------------------------------------------------------------*/
%marketscan_claims (YEAR=2000, TAG=A, LIB=MKT007, YR=002);
%marketscan_claims (YEAR=2001, TAG=A, LIB=MKT007, YR=013);
%marketscan_claims (YEAR=2002, TAG=A, LIB=MKT007, YR=023);
%marketscan_claims (YEAR=2003, TAG=A, LIB=MKT007, YR=033);
%marketscan_claims (YEAR=2004, TAG=A, LIB=MKT007, YR=045);
%marketscan_claims (YEAR=2004, TAG=B, LIB=MKT007, YR=045);
%marketscan_claims (YEAR=2005, TAG=A, LIB=MKT007, YR=054);
%marketscan_claims (YEAR=2006, TAG=A, LIB=MKT007, YR=063);
%marketscan_claims (YEAR=2007, TAG=A, LIB=MKT007, YR=072);
%marketscan_claims (YEAR=2008, TAG=A, LIB=MKT08, YR=081);
%marketscan_claims (YEAR=2009, TAG=A, LIB=MKT910, YR=093);
%marketscan_claims (YEAR=2010, TAG=A, LIB=MKT910, YR=102);
%marketscan_claims (YEAR=2011, TAG=A, LIB=MKT11, YR=111);
%marketscan_claims (YEAR=2011, TAG=B, LIB=MKT11, YR=111);
%marketscan_claims (YEAR=2012, TAG=A, LIB=MKT12, YR=121);
%marketscan_claims (YEAR=2013, TAG=A, LIB=MKT13, YR=131);
%marketscan_claims (YEAR=2014, TAG=A, LIB=MKT14, YR=141);
%marketscan_claims (YEAR=2015, TAG=A, LIB=MKT15, YR=151);
%marketscan_claims (YEAR=2016, TAG=A, LIB=MKT16, YR=161);
%marketscan_claims (YEAR=2017, TAG=A, LIB=MKT17, YR=171);
%marketscan_claims (YEAR=2017, TAG=B, LIB=MKT17, YR=171);
%marketscan_claims (YEAR=2018, TAG=A, LIB=MKT18, YR=181);
%marketscan_claims (YEAR=2019, TAG=A, LIB=MKT19, YR=192);
%marketscan_claims (YEAR=2020, TAG=A, LIB=MKT20, YR=201);
%marketscan_claims (YEAR=2021, TAG=A, LIB=MKT21, YR=211);
%marketscan_claims (YEAR=2022, TAG=A, LIB=MKT22, YR=221);
%marketscan_claims (YEAR=2023, TAG=A, LIB=MKT23, YR=232);
*^^UPDATE HERE #30, with the new year we're trying to estimate for the HCSA;


/*##########################################################################################
##                                                                                        ##
##   PHASE 6: PRE-2007 REBATE BACKCASTING & TAG BLENDING/IMPUTATION                      ##
##   Steps 93z - 200                                                                       ##
##                                                                                        ##
##   This phase has two sub-objectives:                                                    ##
##                                                                                        ##
##   6A. REBATE BACKCASTING (Steps 94-99, %pre2007rebateadj macro):                       ##
##       SSR data begin in 2007. For years 2001-2006, we backcast rebate dollars using     ##
##       linear interpolation. For each CCSR:                                              ##
##         - rebate_dollars_2007 = rx_dollars_ogpay - rx_dollars_netrebate (from Phase 5)  ##
##         - rebate_dollars_2000 = 0 (assumed)                                             ##
##         - rebate_dollars_2001 to 2006 = linearly interpolated                           ##
##       These predicted rebates are subtracted from total dollars for 2001-2006.          ##
##       Year 2000 receives no rebate adjustment.                                          ##
##                                                                                        ##
##   6B. TAG BLENDING (Steps 200+):                                                        ##
##       Because tagging cohorts change, years before the "preferred" tag's start must     ##
##       be imputed. The logic chains growth rates backward from the preferred tag:        ##
##                                                                                        ##
##         dollars_B_year = dollars_B_(year+1) * [dollars_A_year / dollars_A_(year+1)]     ##
##                                                                                        ##
##       This says: "what would tag B have looked like in this year?" = "tag B's value     ##
##       in the next year" * "the year-over-year growth rate observed in tag A."           ##
##                                                                                        ##
##       The blending proceeds backward from the newest tag boundary:                      ##
##         - 2017_B -> 2016_CD -> 2015_CD -> ... -> 2012_CD -> 2011_CD                    ##
##         - At break year 2011, switch from tag C to tag B for the next segment           ##
##         - 2011_CD -> 2010_BC -> 2009_BC -> ... -> 2007_BC                               ##
##         - At break year 2004, switch from tag B to tag A for the final segment          ##
##         - 2004_BC -> 2003_AB -> 2002_AB -> 2001_AB -> 2000_AB                           ##
##                                                                                        ##
##       The suffix convention (e.g., "AB", "BC", "CD") indicates which tags               ##
##       were blended to produce that year's estimate.                                     ##
##                                                                                        ##
##########################################################################################*/

/*------------------------------------------------------------------------------------------
SUB-PHASE 6A: PRE-2007 REBATE BACKCASTING
  MACRO: %pre2007rebateadj
  
  For each of the 543 CCSRs:
    Step 94: Stack years 2000-2007 from the TAG=A estimates
    Step 95: Calculate 2007 rebate dollars as (og_pay - net_of_rebate pay)
             Set 2000 rebate = 0, 2001-2006 rebate = missing (to be predicted)
    Step 96: Assign chronological period numbers (1-8) for regression
    Step 97: Run linear regression: rebate_dollars = f(period)
             The two known points (2000=0, 2007=actual) anchor the line
    Step 98: Merge predicted rebate dollars with original data
    
  After looping through all 543 CCSRs:
    Step 93z: Subtract predicted rebate dollars from total dollars for 2001-2006
              Only adjusts years where rx_dollars_netrebate > 0 (has Rx spending)
    Step 99: Extract 2004 rebates from tag A and apply to 2004 tag B
------------------------------------------------------------------------------------------*/
%macro pre2007rebateadj;
	*94) Stack years that need adjustment (2000-06), and the first year with rebate data (2007);
	data _94_expend2000_2007;
		set _93_mktscn_ccsr2000_A
			_93_mktscn_ccsr2001_A
			_93_mktscn_ccsr2002_A
			_93_mktscn_ccsr2003_A
			_93_mktscn_ccsr2004_A
			_93_mktscn_ccsr2005_A
			_93_mktscn_ccsr2006_A
			_93_mktscn_ccsr2007_A;
		run;
	
	%do ccsr=1 %to &NUM.;
		*95) For each CCSR, calculate rebate dollars for 2007 as the difference between pay & paynetofrebate; 
		data _95_clean_expend&CCSR.;
			set _94_expend2000_2007;
			if ccsrdum=&CCSR.;
			rebate_dollars = rx_dollars_ogpay - rx_dollars_netrebate;
			if year=2000 then rebate_dollars=0;
			if 2001<=year<=2006 then rebate_dollars=.;
		run;

		*96) Sort by year and assign a chronological order dummy;
		proc sort
			data=_95_clean_expend&CCSR.;
			by year;
		run;

		data _96_prep_reg_&CCSR.;
			set _95_clean_expend&CCSR.;
			period=_n_;
		run;

		*97) Linearly predict dollars for 2000-06 based on 2007 rebate dollars;
		proc reg
			data=_96_prep_reg_&CCSR. noprint;
			model rebate_dollars= period;
			output out=_97_linear_reg_output&CCSR. predicted=predicted_rebate_dollars;
			run;
		quit;

		*98) Merge the rebate dollars for 2000-06 with the original data;
		data _98_final_rebateadj_&CCSR.;
			merge _95_clean_expend&CCSR.
				  _97_linear_reg_output&CCSR. (in=x keep=ccsrdum predicted_rebate_dollars);
			by ccsrdum;
			if x=1;
		run;
	%end;

	/*----------------------------------------------------------------------
	Step 93z: Apply Backcasted Rebates to 2001-2006 Total Dollars
	  - Subtracts predicted_rebate_dollars from dollars{YEAR}_A for each year
	  - Only adjusts where rx_dollars_netrebate > 0 (i.e., the CCSR has Rx spending)
	  - Output: _93z_mktscn_ccsr{YEAR}_a datasets for 2001-2006
	----------------------------------------------------------------------*/
	*93z) Stack all the CCSRs together & remove rebate dollars from total dollars in order to get totaldollarsnetofrebate;
	data _93z_mktscn_ccsr2001_a (keep=CCSR YEAR ipop_pay rx_dollars_netrebate ccsr_label ccsr_chpt ccsr_chpt_label patients_2001_a dollars2001_a)
	     _93z_mktscn_ccsr2002_a (keep=CCSR YEAR ipop_pay rx_dollars_netrebate ccsr_label ccsr_chpt ccsr_chpt_label patients_2002_a dollars2002_a)
		 _93z_mktscn_ccsr2003_a (keep=CCSR YEAR ipop_pay rx_dollars_netrebate ccsr_label ccsr_chpt ccsr_chpt_label patients_2003_a dollars2003_a)
		 _93z_mktscn_ccsr2004_a (keep=CCSR YEAR ipop_pay rx_dollars_netrebate ccsr_label ccsr_chpt ccsr_chpt_label patients_2004_a dollars2004_a)
		 _93z_mktscn_ccsr2005_a (keep=CCSR YEAR ipop_pay rx_dollars_netrebate ccsr_label ccsr_chpt ccsr_chpt_label patients_2005_a dollars2005_a)
		 _93z_mktscn_ccsr2006_a (keep=CCSR YEAR ipop_pay rx_dollars_netrebate ccsr_label ccsr_chpt ccsr_chpt_label patients_2006_a dollars2006_a);
			set _98_final_rebateadj_:;
			if year=2001 then do;
				if rx_dollars_netrebate > 0 then dollars2001_A = (dollars2001_A-predicted_rebate_dollars);
				output _93z_mktscn_ccsr2001_a;
			end;
			if year=2002 then do;
				if rx_dollars_netrebate > 0 then dollars2002_A = (dollars2002_A-predicted_rebate_dollars);
				output _93z_mktscn_ccsr2002_a;
			end;
			if year=2003 then do;
				if rx_dollars_netrebate > 0 then dollars2003_A = (dollars2003_A-predicted_rebate_dollars);
				output _93z_mktscn_ccsr2003_a;
			end;
			if year=2004 then do;
				if rx_dollars_netrebate > 0 then dollars2004_A = (dollars2004_A-predicted_rebate_dollars);
				output _93z_mktscn_ccsr2004_a;
			end;
			if year=2005 then do;
				if rx_dollars_netrebate > 0 then dollars2005_A = (dollars2005_A-predicted_rebate_dollars);
				output _93z_mktscn_ccsr2005_a;
			end;
			if year=2006 then do;
				if rx_dollars_netrebate > 0 then dollars2006_A = (dollars2006_A-predicted_rebate_dollars);
				output _93z_mktscn_ccsr2006_a;
			end;
	run;

	/*----------------------------------------------------------------------
	Step 99: Apply 2004 Tag-A Rebates to 2004 Tag-B
	  - The backcasting only ran on tag A data
	  - For the 2004 break year, apply tag A's predicted rebates to tag B's dollars
	----------------------------------------------------------------------*/
	*99) Isolate rebate dollars from 2004_A;
	data _99_rebates_y2004_A;
		set _97_linear_reg_output:;
		if year=2004;
		keep year ccsrdum predicted:;
	run;

	*93z) Apply 2004_A rebates to 2004_B;
	proc sort
		data=_99_rebates_y2004_A;
		by ccsrdum;
	run;

	proc sort
		data=_93_mktscn_ccsr2004_b;
		by ccsrdum;
	run;

	data _93z_mktscn_ccsr2004_b;
		merge _93_mktscn_ccsr2004_b
			  _99_rebates_y2004_A;
		by ccsrdum;
		if rx_dollars_netrebate > 0 then dollars2004_B = dollars2004_B - predicted_rebate_Dollars;
		if dollars2004_B = . then dollars2004_B = ipop_pay;
		drop predicted:;
	run;

	*Cleaning up work space;
	proc datasets lib=work memtype=data nolist;
	delete _95_:
		   _96_:
		   _97_:
		   _98_:;
	quit;
%mend; %pre2007rebateadj; *Year=2000 doesnt need rebate adj;

/*------------------------------------------------------------------------------------------
SUB-PHASE 6B: TAG BLENDING / IMPUTATION
  Steps labeled _200_

  The blending starts at the newest tag boundary (2017, where tags C and D overlap) and
  works backward. At each step, the preferred-tag estimate for year Y is imputed as:

    dollars_preferred_Y = dollars_preferred_(Y+1) * [dollars_available_Y / dollars_available_(Y+1)]

  Where "available" is the tag that was actually run for that year.

  SEGMENT 1: Tag D boundary (2017) backward through tag C territory to 2011
    - Anchor: 2017_B (tag D processed as "B" in the macro)
    - Growth rates from: tag A (the primary tag for 2012-2017)
    - Break at 2011: tag C was processed as "B", so switch source

  SEGMENT 2: Tag C boundary (2011) backward through tag B territory to 2004
    - Anchor: 2011_CD imputed estimate
    - Growth rates from: tag A (primary for 2005-2011)
    - Break at 2004: tag B was processed as "B", so switch source

  SEGMENT 3: Tag B boundary (2004) backward through tag A territory to 2000
    - Anchor: 2004_BC imputed estimate
    - Growth rates from: tag A (primary for 2000-2004)
------------------------------------------------------------------------------------------*/

*UPDATE HERE #31 (BELOW) for new tagging base;

/*--- Segment 1: Impute 2016 through 2011 using tag D anchor ---*/

*200) Impute For 2016;
proc sort
	data=_93_mktscn_ccsr2017_B; 
	by CCSR; 
run;

proc sort
	data=_93_mktscn_ccsr2016_A; 
	by CCSR; 
run;

proc sort
	data=_93_mktscn_ccsr2017_A; 
	by CCSR; 
run;

data _200_expend_patients2016_CD;
	merge _93_mktscn_ccsr2017_B (drop= year) 
		  _93_mktscn_ccsr2016_A
		  _93_mktscn_ccsr2017_A (drop= year);
	by CCSR;
	dollarsAB_2016=dollars2017_B*(Dollars2016_A/dollars2017_A);
	patientsAB_2016=patients_2017_B*(patients_2016_A/patients_2017_A);
	dollars=dollarsAB_2016;
	patients=patientsAB_2016;
run;

*200) Impute For 2015;
proc sort
	data=_93_mktscn_ccsr2016_A; 
	by CCSR; 
run;

proc sort
	data=_93_mktscn_ccsr2015_A; 
	by CCSR; 
run;

proc sort
	data=_200_expend_patients2016_CD; 
	by CCSR; 
run;

data _200_expend_patients2015_CD;
	merge _93_mktscn_ccsr2016_A (drop=year)
		  _93_mktscn_ccsr2015_A
		  _200_expend_patients2016_CD (keep=ccsr dollarsAB_2016 patientsAB_2016);
	by CCSR;
	dollarsAB_2015=dollarsAB_2016*(Dollars2015_A/dollars2016_A);
	patientsAB_2015=patientsAB_2016*(patients_2015_A/patients_2016_A);
	dollars=dollarsAB_2015;
	patients=patientsAB_2015;
run;

*200) Impute For 2014;
proc sort data=_93_mktscn_ccsr2015_A; by CCSR; run;
proc sort data=_93_mktscn_ccsr2014_A; by CCSR; run;
proc sort data=_200_expend_patients2015_CD; by CCSR; run;

data _200_expend_patients2014_CD;
	merge _93_mktscn_ccsr2015_A (drop=year)
		  _93_mktscn_ccsr2014_A
		  _200_expend_patients2015_CD (keep=CCSR dollarsAB_2015 patientsAB_2015);
	by CCSR;
	dollarsAB_2014=dollarsAB_2015*(Dollars2014_A/dollars2015_A);
	patientsAB_2014=patientsAB_2015*(patients_2014_A/patients_2015_A);
	dollars=dollarsAB_2014;
	patients=patientsAB_2014;
run;

*200) Impute For 2013;
proc sort data=_93_mktscn_ccsr2014_A; by CCSR; run;
proc sort data=_93_mktscn_ccsr2013_A; by CCSR; run;
proc sort data=_200_expend_patients2014_CD; by CCSR; run;

data _200_expend_patients2013_CD;
	merge _93_mktscn_ccsr2014_A (drop=year)
		  _93_mktscn_ccsr2013_A
		  _200_expend_patients2014_CD (keep=CCSR dollarsAB_2014 patientsAB_2014);
	by CCSR;
	dollarsAB_2013=dollarsAB_2014*(Dollars2013_A/dollars2014_A);
	patientsAB_2013=patientsAB_2014*(patients_2013_A/patients_2014_A);
	dollars=dollarsAB_2013;
	patients=patientsAB_2013;
run;

*200) Impute For 2012;
proc sort data=_93_mktscn_ccsr2013_A; by CCSR; run;
proc sort data=_93_mktscn_ccsr2012_A; by CCSR; run;
proc sort data=_200_expend_patients2013_CD; by CCSR; run;

data _200_expend_patients2012_CD;
	merge _93_mktscn_ccsr2013_A (drop=year)
		  _93_mktscn_ccsr2012_A
		  _200_expend_patients2013_CD (keep=CCSR dollarsAB_2013 patientsAB_2013);
	by CCSR;
	dollarsAB_2012=dollarsAB_2013*(Dollars2012_A/dollars2013_A);
	patientsAB_2012=patientsAB_2013*(patients_2012_A/patients_2013_A);
	dollars=dollarsAB_2012;
	patients=patientsAB_2012;
run;

/*--- Break year 2011: Tag C was run as "B"; switch growth rate source ---*/
*200) Impute For 2011;
*There is a 2011 break year so we use 2011_B and the output will then be mapped to a different 2011_1 dataset;
proc sort data=_93_mktscn_ccsr2012_A; by CCSR; run;
proc sort data=_93_mktscn_ccsr2011_B; by CCSR; run;
proc sort data=_200_expend_patients2012_CD; by CCSR; run;

data _200_expend_patients2011_CD;
	merge _93_mktscn_ccsr2012_A (drop=year)
		  _93_mktscn_ccsr2011_B
		  _200_expend_patients2012_CD (keep=CCSR dollarsAB_2012 patientsAB_2012);
	by CCSR;
	dollarsAB_2011=dollarsAB_2012*(Dollars2011_B/dollars2012_A);
	patientsAB_2011=patientsAB_2012*(patients_2011_B/patients_2012_A);
	dollars=dollarsAB_2011;
	patients=patientsAB_2011;
run;

/*--- Segment 2: Impute 2010 through 2007 using tag C/D blended anchor ---*/
*There is a break year here so we use 2011_1 instead of the one used in preceding step;
*200) Impute For 2010;
proc sort data=_200_expend_patients2011_CD; by CCSR; run;
proc sort data=_93_mktscn_ccsr2010_A; by CCSR; run;
proc sort data=_93_mktscn_ccsr2011_A; by CCSR; run;

data _200_expend_patients2010_BC;
	merge _200_expend_patients2011_CD (keep = CCSR dollars patients rename=(dollars=dollars_2011_C patients=patients_2011_C)) 
		  _93_mktscn_ccsr2010_A
		  _93_mktscn_ccsr2011_A (drop=year);
	by CCSR;
	dollarsAB_2010=dollars_2011_C*(Dollars2010_A/dollars2011_A);
	patientsAB_2010=patients_2011_C*(patients_2010_A/patients_2011_A);
	dollars=dollarsAB_2010;
	patients=patientsAB_2010;
run;

*200) Impute For 2009;
proc sort data=_93_mktscn_ccsr2010_A; by CCSR; run;
proc sort data=_93_mktscn_ccsr2009_A; by CCSR; run;
proc sort data=_200_expend_patients2010_BC; by CCSR; run;

data _200_expend_patients2009_BC;
	merge _93_mktscn_ccsr2010_A (drop=year)
		  _93_mktscn_ccsr2009_A
		  _200_expend_patients2010_BC (keep=CCSR dollarsAB_2010 patientsAB_2010);
	by CCSR;
	dollarsAB_2009=dollarsAB_2010*(Dollars2009_A/dollars2010_A);
	patientsAB_2009=patientsAB_2010*(patients_2009_A/patients_2010_A);
	dollars=dollarsAB_2009;
	patients=patientsAB_2009;
run;

*200) Impute For 2008;
proc sort data=_93_mktscn_ccsr2009_A; by CCSR; run;
proc sort data=_93_mktscn_ccsr2008_A; by CCSR; run;
proc sort data=_200_expend_patients2009_BC; by CCSR; run;

data _200_expend_patients2008_BC;
	merge _93_mktscn_ccsr2009_A (drop=year)
		  _93_mktscn_ccsr2008_A
		  _200_expend_patients2009_BC (keep=CCSR dollarsAB_2009 patientsAB_2009);
	by CCSR;
	dollarsAB_2008=dollarsAB_2009*(Dollars2008_A/dollars2009_A);
	patientsAB_2008=patientsAB_2009*(patients_2008_A/patients_2009_A);
	dollars=dollarsAB_2008;
	patients=patientsAB_2008;
run;

*200) Impute For 2007;
proc sort data=_93_mktscn_ccsr2008_A; by CCSR; run;
proc sort data=_93_mktscn_ccsr2007_A; by CCSR; run;
proc sort data=_200_expend_patients2008_BC; by CCSR; run;

data _200_expend_patients2007_BC;
	merge _93_mktscn_ccsr2008_A (drop=year)
		  _93_mktscn_ccsr2007_A
		  _200_expend_patients2008_BC (keep=CCSR dollarsAB_2008 patientsAB_2008);
	by CCSR;
	dollarsAB_2007=dollarsAB_2008*(Dollars2007_A/dollars2008_A);
	patientsAB_2007=patientsAB_2008*(patients_2007_A/patients_2008_A);
	dollars=dollarsAB_2007;
	patients=patientsAB_2007;
run;

/*--- Now using rebate-adjusted (_93z_) datasets for 2006 and earlier ---*/

*200) Impute For 2006;
proc sort data=_93_mktscn_ccsr2007_A; by CCSR; run;
proc sort data=_93z_mktscn_ccsr2006_A; by CCSR; run;
proc sort data=_200_expend_patients2007_BC; by CCSR; run;

data _200_expend_patients2006_BC;
	merge _93_mktscn_ccsr2007_A (drop=year)
		  _93z_mktscn_ccsr2006_A
		  _200_expend_patients2007_BC (keep=CCSR dollarsAB_2007 patientsAB_2007);
	by CCSR;
	dollarsAB_2006=dollarsAB_2007*(Dollars2006_A/dollars2007_A);
	patientsAB_2006=patientsAB_2007*(patients_2006_A/patients_2007_A);
	dollars=dollarsAB_2006;
	patients=patientsAB_2006;
run;

*200) Impute For 2005;
proc sort data=_93z_mktscn_ccsr2006_A; by CCSR; run;
proc sort data=_93z_mktscn_ccsr2005_A; by CCSR; run;
proc sort data=_200_expend_patients2006_BC; by CCSR; run;

data _200_expend_patients2005_BC;
	merge _93z_mktscn_ccsr2006_A (drop=year)
		  _93z_mktscn_ccsr2005_A
		  _200_expend_patients2006_BC (keep=CCSR dollarsAB_2006 patientsAB_2006);
	by CCSR;
	dollarsAB_2005=dollarsAB_2006*(Dollars2005_A/dollars2006_A);
	patientsAB_2005=patientsAB_2006*(patients_2005_A/patients_2006_A);
	dollars=dollarsAB_2005;
	patients=patientsAB_2005;
run;

/*--- Break year 2004: Tag B was processed; switch growth rate source ---*/
*200) Impute For 2004;
*There is a 2004 break year so we use 2004_B and the output will then be mapped to a different 2004_A dataset;
proc sort data=_93z_mktscn_ccsr2005_A; by CCSR; run;
proc sort data=_93z_mktscn_ccsr2004_b; by CCSR; run;
proc sort data=_200_expend_patients2005_BC; by CCSR; run;

data _200_expend_patients2004_BC;
	merge _93z_mktscn_ccsr2005_A (drop=year)
		  _93z_mktscn_ccsr2004_b
		  _200_expend_patients2005_BC (keep=CCSR dollarsAB_2005 patientsAB_2005);
	by CCSR;
	dollarsAB_2004=dollarsAB_2005*(Dollars2004_B/dollars2005_A);
	patientsAB_2004=patientsAB_2005*(patients_2004_B/patients_2005_A);
	dollars=dollarsAB_2004;
	patients=patientsAB_2004;
run;

/*--- Segment 3: Impute 2003 through 2000 using tag B/C blended anchor ---*/
*There is a break year here so we use 2004_1 instead of the one used in preceding step;
*200) Impute For 2003;
proc sort data=_200_expend_patients2004_BC; by CCSR; run;
proc sort data=_93z_mktscn_ccsr2003_A; by CCSR; run;
proc sort data=_93z_mktscn_ccsr2004_A; by CCSR; run;

data _200_expend_patients2003_AB;
	merge _200_expend_patients2004_BC (keep = CCSR dollars patients rename=(dollars=dollars2004_C patients=patients_2004_C) drop= year) 
		  _93z_mktscn_ccsr2003_A
		  _93z_mktscn_ccsr2004_A (drop= year);
	by CCSR;
	dollarsAB_2003=dollars2004_C*(Dollars2003_A/dollars2004_A);
	patientsAB_2003=patients_2004_C*(patients_2003_A/patients_2004_A);
	dollars=dollarsAB_2003;
	patients=patientsAB_2003;
run;

*200) Impute For 2002;
proc sort data=_93z_mktscn_ccsr2003_A; by CCSR; run;
proc sort data=_93z_mktscn_ccsr2002_A; by CCSR; run;
proc sort data=_200_expend_patients2003_AB; by CCSR; run;

data _200_expend_patients2002_AB;
	merge _93z_mktscn_ccsr2003_A (drop=year) 
		  _93z_mktscn_ccsr2002_A
		  _200_expend_patients2003_AB (keep=CCSR dollarsAB_2003 patientsAB_2003);
	by CCSR;
	dollarsAB_2002=dollarsAB_2003*(Dollars2002_A/dollars2003_A);
	patientsAB_2002=patientsAB_2003*(patients_2002_A/patients_2003_A);
	dollars=dollarsAB_2002;
	patients=patientsAB_2002;
run;

*200) Impute For 2001;
proc sort data=_93z_mktscn_ccsr2002_A; by CCSR; run;
proc sort data=_93z_mktscn_ccsr2001_A; by CCSR; run;
proc sort data=_200_expend_patients2002_AB; by CCSR; run;

data _200_expend_patients2001_AB;
	merge _93z_mktscn_ccsr2002_A (drop= year)
	   	  _93z_mktscn_ccsr2001_A
		  _200_expend_patients2002_AB (keep=CCSR dollarsAB_2002 patientsAB_2002);
	by CCSR;
	dollarsAB_2001=dollarsAB_2002*(Dollars2001_A/dollars2002_A);
	patientsAB_2001=patientsAB_2002*(patients_2001_A/patients_2002_A);
	dollars=dollarsAB_2001;
	patients=patientsAB_2001;
run;

*200) Impute For 2000;
proc sort data=_93z_mktscn_ccsr2001_A; by CCSR; run;
proc sort data=_93_mktscn_ccsr2000_A; by CCSR; run;
proc sort data=_200_expend_patients2001_AB; by CCSR; run;

data _200_expend_patients2000_AB;
	merge _93z_mktscn_ccsr2001_A (drop= year)
		  _93_mktscn_ccsr2000_A
		  _200_expend_patients2001_AB (keep=CCSR dollarsAB_2001 patientsAB_2001);
	by CCSR;
	dollarsAB_2000=dollarsAB_2001*(Dollars2000_A/dollars2001_A);
	patientsAB_2000=patientsAB_2001*(patients_2000_A/patients_2001_A);
	dollars=dollarsAB_2000;
	patients=patientsAB_2000;
run;


/*##########################################################################################
##                                                                                        ##
##   PHASE 7: NHEA BENCHMARKING                                                           ##
##   Steps 201-214                                                                         ##
##                                                                                        ##
##   PURPOSE: Scale the MarketScan disease-level spending estimates to match official      ##
##   NHEA totals for the employer-sponsored population. This ensures our disease           ##
##   breakdown is consistent with national health expenditure aggregates.                  ##
##                                                                                        ##
##   LOGIC:                                                                                ##
##     1. Stack all blended year-CCSR estimates into one dataset                           ##
##     2. Compute each CCSR's share of total MarketScan spending per year                  ##
##     3. Import NHEA Tables 7,8,11,14,16 for private+OOP spending by service category    ##
##     4. Import NHEA Table 21 for employer-sponsored vs. direct-purchase split            ##
##     5. Compute NHEA employer-sponsored total health spending                            ##
##     6. Apply CCSR shares to NHEA total: NHEA_dollars = share * nhea_health_emp * 1B     ##
##     7. Compute episodes and cost-per-case                                               ##
##                                                                                        ##
##   KEY FORMULAS:                                                                         ##
##     nhea_health = sum(private_hosp + OOP_hosp + private_physclin + OOP_physclin +       ##
##                       private_othprof + OOP_othprof + private_homehlth + OOP_homehlth + ##
##                       private_rx + OOP_rx)                                              ##
##     emp_share = private_emp / (private_emp + private_oth)                                ##
##     nhea_health_emp = nhea_health * emp_share                                           ##
##     NHEA_dollars = CCSR_share * nhea_health_emp * 1,000,000,000                         ##
##     number_of_episodes = patients * (NHEA_dollars / uncontrolled_dollars)                ##
##     cost_per_case = NHEA_dollars / number_of_episodes                                   ##
##                                                                                        ##
##########################################################################################*/

/*------------------------------------------------------------------------------------------
Step 201: Stack All Blended Year-CCSR Estimates
  - Combines imputed ("_200_") years with directly-estimated ("_93_") years
  - For years covered by imputation: uses the blended estimate
  - For recent years (2016+): uses direct estimates from the preferred tag
  - NOTE: 2016 uses tag A directly (not imputed), 2017 uses tag B (=tag D)
  - Keeps only: ccsr, ccsr_label, ccsr_chpt, ccsr_chpt_label, year, dollars, patients
------------------------------------------------------------------------------------------*/
*201) Stack all marketscan years;
data _201_forindex_patients_mktscn;
	set _200_Expend_patients2000_AB
		_200_Expend_patients2001_AB
		_200_Expend_patients2002_AB
		_200_Expend_patients2003_AB
		_200_Expend_patients2004_BC
		_200_Expend_patients2005_BC
		_200_Expend_patients2006_BC
		_200_Expend_patients2007_BC
		_200_Expend_patients2008_BC
		_200_Expend_patients2009_BC
		_200_Expend_patients2010_BC
		_200_Expend_patients2011_CD
		_200_Expend_patients2012_CD
		_200_Expend_patients2013_CD
		_200_Expend_patients2014_CD
		_200_Expend_patients2015_CD
		_93_mktscn_ccsr2016_a (rename=(dollars2016_a = dollars patients_2016_a = patients))
		_93_mktscn_ccsr2017_B (rename=(dollars2017_b = dollars patients_2017_b = patients))
		_93_mktscn_ccsr2018_a (rename=(dollars2018_a = dollars patients_2018_a = patients))
		_93_mktscn_ccsr2019_a (rename=(dollars2019_a = dollars patients_2019_a = patients))
		_93_mktscn_ccsr2020_a (rename=(dollars2020_a = dollars patients_2020_a = patients))
		_93_mktscn_ccsr2021_a (rename=(dollars2021_a = dollars patients_2021_a = patients))
		_93_mktscn_ccsr2022_a (rename=(dollars2022_a = dollars patients_2022_a = patients))
		_93_mktscn_ccsr2023_a (rename=(dollars2023_a = dollars patients_2023_a = patients))
		;
		*^^UPDATE HERE #32, with the newest year we're trying to estimate for the HCSA;
		*^^UPDATE HERE #33, with updated tag years;
	keep ccsr: year dollars patients;
run;

/*------------------------------------------------------------------------------------------
Steps 202-203: Compute MCE (Medical Care Expenditure) Price Indexes
  - Creates base weights from the BASEYR (2017) for Laspeyres/Paasche index computation
  - MCE = (cost_per_case_year / cost_per_case_base) for each CCSR
  - Paasche = 1/MCE
  - These indexes are not used in the final output but provide analytical context
------------------------------------------------------------------------------------------*/
*202) Create base weights for the indexes;
data _202_weight;
	set _201_forindex_patients_mktscn (where=(year=&BASEYR.));
	lag_dollars=dollars;
	lag_patients=patients;
	keep ccsr lag:;
run;

*203) Calculate the MCE;
proc sort data=_202_weight; by ccsr; run;
proc sort data=_201_forindex_patients_mktscn; by ccsr; run;

data _203_compare_allquarters ;
	merge _201_forindex_patients_mktscn (in=x) 
		  _202_weight; 
	by ccsr;
	if x=1;
	MCE_incld_clms=(dollars/patients)/(lag_dollars/lag_patients);
	Paas_incld_Clms=1/((dollars/patients)/(lag_dollars/lag_patients));
run; 

/*------------------------------------------------------------------------------------------
Step 204: Calculate Total Annual MarketScan Spending
  - Sums all CCSR-level dollars by year to get the annual total
  - This total is the denominator for computing each CCSR's share
------------------------------------------------------------------------------------------*/
*204) Calculate annual pay;
proc means
	data=_203_compare_allquarters noprint nway;
	var dollars;
	class year;
	output out=_204_agg_expend_byyear (drop=_:) sum=paytotal_year;
run;

proc sort data=_203_compare_allquarters; by year ccsr; run;

/*------------------------------------------------------------------------------------------
Step 209: Compute Each CCSR's Share of Total Annual Spending
  - share = dollars / paytotal_year for each CCSR x year
  - These shares are applied to NHEA totals in step 214
------------------------------------------------------------------------------------------*/
*209) Merge marketscan ccsr data with marketscan annual data;
data _209_compare_allquarters;
	merge _203_compare_allquarters (keep=year ccsr: dollars patients) 
		  _204_agg_expend_byyear (in=x);
	by year;
	if x=1;
	share=dollars/paytotal_year;
run;

/*------------------------------------------------------------------------------------------
NHEA Tables Import & Processing
  MACRO: %NHEA_tables
  
  PARAMETERS:
    NUM       = NHEA table number (07, 08, 11, 14, 16, or 21)
    NAME      = Column name prefix in the Excel file (varies by table)
    SHORTNAME = Short label used in variable naming (hosp, physclin, etc.)
  
  For Tables 7/8/11/14/16 (service-category spending):
    - Extracts private insurance OOP and private insurance expenditure columns
    - Sums them: private_{service}_exp_w_oop = OOP + expenditure
    - Keeps only years >= 2000

  For Table 21 (insurance enrollment/spending):
    - Extracts "Employer Sponsored Private Health Insurance" and "Direct Purchase" rows
    - Transposes from wide to long
    - Used to compute the employer-sponsored share of total private spending
    
  NOTE: The NHEA Table 21 import has hardcoded column letter-to-year mappings
  (o=2000, p=2001, ..., al=2023). When adding a new year, add the next column letter.

  KNOWN ISSUE: The macro calls below have the SHORTNAME for tables 7 and 8 swapped
  (Table 7 = Hospital Care gets SHORTNAME=physclin; Table 8 = Physician/Clinical gets 
  SHORTNAME=hosp). This is a historical naming error that does NOT affect results because
  the variables are all summed together in step 213 regardless of their names.
------------------------------------------------------------------------------------------*/
%macro NHEA_tables (NUM=, NAME=, SHORTNAME=);
	*Import NHEA (table NUM);
	proc import
		datafile="\\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Macros\KFF\Employer_sponsored\Inputs\Table &NUM.*.xlsx"
		out=_01_og_NHEA_table&NUM.
		dbms=xlsx
		replace;
	run;

	%if &NUM. ne 21 %then %do;
		*210) Clean NHEA table NUM;
		data _210_clean_nhea&NUM.;
			set _01_og_NHEA_table&NUM. (keep=Table: c e rename=(&NAME.=year_char c=priv_&SHORTNAME._oop_char e=private_&SHORTNAME._exp_char));
			if _n_<=32;
			if year_char>=2000;
			year=year_char*1; *Converting from character to numeric;
			private_&SHORTNAME._oop = priv_&SHORTNAME._oop_char*1; *Converting from character to numeric;
			private_&SHORTNAME._expenditure = private_&SHORTNAME._exp_char*1; *Converting from character to numeric;
			private_&SHORTNAME._exp_w_oop = sum(private_&SHORTNAME._oop,private_&SHORTNAME._expenditure);
			keep year private_&SHORTNAME._exp_w_oop;
		run;
	%end;
	%if &NUM. = 21 %then %do;
		*210) Clean NHEA table NUM;
		data _210_clean_nheaNUM.;
			set _01_og_NHEA_tableNUM. (keep=var1 o	p	q	r	s	t	u	v	w	x	y	z	aa	ab	ac	ad	ae	af	ag	ah	ai	aj	ak	al rename=(o	=	_2000
																																						p	=	_2001
																																						q	=	_2002
																																						r	=	_2003
																																						s	=	_2004
																																						t	=	_2005
																																						u	=	_2006
																																						v	=	_2007
																																						w	=	_2008
																																						x	=	_2009
																																						y	=	_2010
																																						z	=	_2011
																																						aa	=	_2012
																																						ab	=	_2013
																																						ac	=	_2014
																																						ad	=	_2015
																																						ae	=	_2016
																																						af	=	_2017
																																						ag	=	_2018
																																						ah	=	_2019
																																						ai	=	_2020
																																						aj	=	_2021
																																						ak	=	_2022
																																						al	=	_2023));
			if _n_<=10;
			if var1= "   Employer Sponsored Private Health Insurance" | var1= "   Direct Purchase";
		run;

		proc sort
			data=_210_clean_nhea&NUM.;
			by var1;
		run;

		*211) Transpose the employer-sponsored row to long;
		proc transpose
			data=_210_clean_nhea&NUM. (where=(var1="   Employer Sponsored Private Health Insurance"))
			out=_211_long_nhea&NUM._emp;
			by var1;
			var _:;
		run;

		*211) Transpose the direct-purchase row to long;
		proc transpose
			data=_210_clean_nhea&NUM. (where=(var1="   Direct Purchase"))
			out=_211_long_nhea&NUM._oth;
			by var1;
			var _:;
		run;

		*212) Clean the long version (employee sponsored);
		data _212_clean_long_nhea&NUM._emp;
			set _211_long_nhea&NUM._emp (keep=_name_ col1);
			private_emp = col1*1; *numeric;
			year=substr(_name_, 2,4)*1; *numeric;
			drop _name_ col1;
		run;

		*212) Clean the long version (directpurchase);
		data _212_clean_long_nhea&NUM._oth;
			set _211_long_nhea&NUM._oth (keep=_name_ col1);
			private_oth = col1*1; *numeric;
			year=substr(_name_, 2,4)*1; *numeric;
			drop _name_ col1;
		run;
	%end;

%mend;
%NHEA_tables (NUM=07, NAME=Table_7___Hospital_Care_Expendit, SHORTNAME=physclin);
%NHEA_tables (NUM=08, NAME=Table_8___Physician_and_Clinical, SHORTNAME=hosp);
%NHEA_tables (NUM=11, NAME=Table_11___Other_Professional_Se, SHORTNAME=othprof);
%NHEA_tables (NUM=14, NAME=Table_14___Home_Health_Care_Serv, SHORTNAME=homehlth);
%NHEA_tables (NUM=16, NAME=Table__16__Retail_Prescription_D, SHORTNAME=rx);
%NHEA_tables (NUM=21);

/*------------------------------------------------------------------------------------------
Step 213: Merge All NHEA Tables & Compute Employer-Sponsored Health Total
  - Merges service-category spending (tables 7,8,11,14,16) with insurance split (table 21)
  - nhea_health = sum of all private + OOP spending across service categories
  - emp_share = employer-sponsored / (employer-sponsored + direct purchase)
  - nhea_health_emp = nhea_health * emp_share (in billions)
------------------------------------------------------------------------------------------*/
*213) Merge NHEA tabls together and sum the components to achieve totalhealthdollars;
data _213_all_nhea_Tables;
	merge _210_clean_nhea7
	      _210_clean_nhea8
		  _210_clean_nhea11
		  _210_clean_nhea14
		  _210_clean_nhea16
		  _212_clean_long_nhea21_emp
		  _212_clean_long_nhea21_oth;
	by year;
	if year<=&BLEND_NEWYEAR.;
	nhea_health = sum(private_hosp_exp_w_oop, private_physclin_exp_w_oop, private_othprof_exp_w_oop, private_homehlth_exp_w_oop, private_rx_exp_w_oop);
	private_total = sum(private_emp, private_oth);
	emp_share = private_emp/private_total;
	nhea_health_emp = nhea_health*emp_share;
	keep year nhea_health_emp;
run;

/*------------------------------------------------------------------------------------------
Step 214: Apply NHEA Benchmarking to Disease-Level Estimates
  - For each CCSR x year:
    NHEA_ALL = share * nhea_health_emp (in billions)
    NHEA_dollars = NHEA_ALL * 1,000,000,000 (convert to actual dollars)
    number_of_episodes = patients * (NHEA_dollars / uncontrolled_mktscn_dollars)
      - Scales patient counts proportionally to the NHEA adjustment
    cost_per_case = NHEA_dollars / number_of_episodes
  
  FINAL OUTPUT VARIABLES:
    year                        - Calendar year (2000-2023)
    ccsr                        - CCSR category code (e.g., "CIR007")
    ccsr_label                  - CCSR category description
    ccsr_chpt                   - CCSR chapter code
    ccsr_chpt_label             - CCSR chapter description
    nhea_dollars                - NHEA-benchmarked spending in dollars
    number_of_episodes          - NHEA-scaled patient count
    cost_per_case               - NHEA-benchmarked cost per episode
    uncontrolled_mktscn_dollars - Original MarketScan spending (pre-benchmarking)
    patients                    - Original MarketScan weighted patient count
------------------------------------------------------------------------------------------*/
*214) Weight disease spending up to NHEA totals;
data _214_Spending_on_ccc_mce;
	merge _209_compare_allquarters (in=x) 
		  _213_all_nhea_Tables;
	by year;
	if x=1;
	NHEA_ALL=share*nhea_health_emp;
	NHEA_dollars = NHEA_all*1000000000;
	number_of_episodes = patients * (NHEA_dollars/dollars);
	cost_per_case = NHEA_dollars/number_of_episodes;
	keep year ccsr ccsr_label ccsr_chpt ccsr_chpt_label nhea_dollars number_of_episodes cost_per_case dollars patients;
	rename dollars=uncontrolled_mktscn_dollars;
run;

/*------------------------------------------------------------------------------------------
FINAL EXPORT (COMMENTED OUT)
  - Exports the _214_ dataset to Excel for distribution
  - File naming convention includes the date: employer_sponsored_ccsr_output00_23_{DATE}.xlsx
------------------------------------------------------------------------------------------*/
/*INTENTIONALLY COMMENTED OUT (below). Only re-run if necessary to overwrite.
proc export
	data=_214_Spending_on_ccc_mce
	outfile="\\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Macros\KFF\Employer_sponsored\Outputs\employer_sponsored_ccsr_output00_23_&sysdate9..xlsx"
	dbms=xlsx
	replace;
run;
^^INTENTIONALLY COMMENTED OUT^^*/

*Save log;
proc printto; run;


/*==========================================================================================
APPENDIX: VALIDATION CHECKS (COMMENTED OUT)
  The following code compares the current estimates against a prior version ("1.5")
  produced by a different methodology. It generates PDF graphs of:
    - Uncontrolled MarketScan dollars (current vs. 1.5) by CCSR over time
    - Patient counts (current vs. 1.5) by CCSR over time
  Also identifies the 107 CCSRs with zero or missing spending.
  
  These checks are for internal QA only and do not affect the output.
==========================================================================================*/
/*INTENTIONALLY COMMENTED OUT (below). some backofenvelope checks

Libname onepfive "\\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Nominal_Spending\Integrated_Index\update2021\for_indexes"; *indxint from hcsa1.5;

*capture just the marketscan portion of peter's 1.5 version;
data _del01;
set ONEPFIVE.forindex_totals_adj_ntag;
keep year ccsr_cat dollars_rebate_mktscn patients_mktscn;
run;

*merge peter's 1.5 marketscan with ccsr labels;
proc sort
	data=INPUTS.ccsr_label_v20231
	out=_del02 (rename=(ccsrnum=ccsr_cat)); 
	by ccsrnum; 
run;

proc sort
	data=_del01; 
	by ccsr_cat; 
run;

data _del03;
	merge _del01(in=x) 
		  _del02;
	by ccsr_cat;
	if x=1;
run;

*merge peter's 1.5mktscn with kffmktscn;
proc sort
	data=_del03;
	by ccsr year;
run;

proc sort
	data=_214_spending_on_ccc_mce;
	by ccsr year;
run;

data _del04;
	merge _214_spending_on_ccc_mce (rename=(uncontrolled_mktscn_dollars=kff_uncontrolled_mktscn_dollars patients=kff_patients))
		  _del03 (keep=ccsr year dollars_rebate_mktscn patients_mktscn rename=(dollars_rebate_mktscn=_1p5_uncontrolled_mktscn_doll patients_mktscn=_1p5_patients));
	by ccsr year;
run;

data _del04b;
	set _del04;
	format kff_uncontrolled_mktscn_dollars comma16. _1p5_uncontrolled_mktscn_doll comma16.;
run;

*graph;
proc sort
	data=_del04b;
	by ccsr_label ccsr;
run;

GOPTIONS RESET=ALL;
ods pdf file="\\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Macros\KFF\Employer_sponsored\Outputs\graphs\kff_vs_1p5_mktscndollars.pdf"
startpage=never ;
proc sgplot data=_del04b;
series x = year y=kff_uncontrolled_mktscn_dollars/lineattrs=(pattern=solid color=blue);
series x = year y=_1p5_uncontrolled_mktscn_doll/lineattrs=(pattern=solid color=red);
by ccsr_label ccsr;
xaxis values=(2000 to 2023 by 1);
yaxis label="uncontrolled_dollars";
run;
ods pdf close;

GOPTIONS RESET=ALL;
ods pdf file="\\serv532a\Research2\HCSA\MEPS_PROCESSING\HCSA\Macros\KFF\Employer_sponsored\Outputs\graphs\kff_vs_1p5_mktscnpatients.pdf"
startpage=never ;
proc sgplot data=_del04b;
series x = year y=kff_patients/lineattrs=(pattern=solid color=blue);
series x = year y=_1p5_patients/lineattrs=(pattern=solid color=red);
by ccsr_label ccsr;
xaxis values=(2000 to 2023 by 1);
yaxis label="patients";
run;
ods pdf close;

proc sort data=_214_spending_on_ccc_mce
		  nodupkey
		  out=_del05_107missingccsr (where=(uncontrolled_mktscn_dollars=. | uncontrolled_mktscn_dollars=0) keep=ccsr ccsr_label uncontrolled_mktscn_dollars);
by ccsr;
run; *107 missing ccsrs;
^^INTENTIONALLY COMMENTED OUT^^*/
