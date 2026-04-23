#===========================================================================================
# PROGRAM:    Employer_Sponsored.R
# OBJECTIVE:  Estimate annual employer-sponsored health care expenditures by disease
#             category (CCSR) for the Health Care Satellite Account (HCSA), 2000-2023.
#
# R TRANSLATION of: Employer_Sponsored.sas
#
# AUTHORS:    Health Care Satellite Account Team, Bureau of Economic Analysis (BEA)
# CREATED:    R version April 2026
#
# DEPENDENCIES:
#   tidyverse   - Core data wrangling (dplyr, tidyr, purrr, stringr, readr)
#   haven       - Read SAS .sas7bdat files
#   readxl      - Read Excel .xlsx/.xls files
#   openxlsx    - Write Excel output
#
# SEE ALSO: Employer_Sponsored_Documented.sas for full methodological documentation.
#===========================================================================================

library(tidyverse)
library(haven)
library(readxl)
library(openxlsx)

# ---- Start log ----
log_file <- file.path(
  "//serv532a/Research2/HCSA/MEPS_PROCESSING/HCSA/Macros/KFF/Employer_sponsored/Logs",
  paste0("Employer_sponsored_R_", format(Sys.Date(), "%d%b%Y"), ".log")
)
sink(log_file, split = TRUE)
cat("Employer_Sponsored.R started at", format(Sys.time()), "\n")

#===========================================================================================
# GLOBAL PARAMETERS
#===========================================================================================
VENDYEAR       <- 2024   # <- UPDATE HERE #1
CENYR          <- 2020   # <- UPDATE HERE #2
SHORT_YEAR     <- "23"   # <- UPDATE HERE #3
BLEND_FIRSTYEAR <- 2000
BLEND_NEWYEAR  <- 2023   # <- UPDATE HERE #4
NUM            <- 543
BASEYR         <- 2017   # <- UPDATE HERE #5

TEST_MODE  <- TRUE
TEST_NROWS <- 10000

#===========================================================================================
# DIRECTORY PATHS
#===========================================================================================
dir_cpscurr <- paste0("//serv532a/Research2/HCSA/MEPS_PROCESSING/HCSA/Census_population/Vintage", VENDYEAR, "/")
dir_log     <- "//serv532a/Research2/HCSA/MEPS_PROCESSING/HCSA/Macros/KFF/Employer_sponsored/Logs/"      # <- UPDATE HERE #6
dir_outputs <- "//serv532a/Research2/HCSA/MEPS_PROCESSING/HCSA/Macros/KFF/Employer_sponsored/Outputs/"    # <- UPDATE HERE #7
dir_inputs  <- "//serv532a/Research2/HCSA/MEPS_PROCESSING/HCSA/Macros/KFF/Employer_sponsored/Inputs/"     # <- UPDATE HERE #8
dir_meps    <- "//serv532a/Research2/No_Backup/HCSA/Read_in_Raw_Data/"
dir_mktag   <- "//serv532b/Research3/No_Backup/HCSA/Tagging_File/"
dir_mkt <- list(
  MKT007 = "//SERV532B/Research2/No_Backup/HCSA/Market_Scan/",
  MKT08  = "//SERV532B/Research2/No_Backup/HCSA/08updates/",
  MKT910 = "//SERV532B/Research2/No_Backup/HCSA/MarketScan09_11/",
  MKT11  = "//SERV532B/Research2/No_Backup/HCSA/MarketScan11/",
  MKT12  = "//SERV532B/Research2/No_Backup/HCSA/MarketScan12/",
  MKT13  = "//SERV532B/Research2/No_Backup/HCSA/MarketScan13/",
  MKT14  = "//SERV532B/Research2/No_Backup/HCSA/MarketScan2014/",
  MKT15  = "//SERV532B/Research2/No_Backup/HCSA/MarketScan2015/",
  MKT16  = "//SERV532B/Research2/No_Backup/HCSA/MarketScan2016/",
  MKT17  = "//serv532B/Research2/No_Backup/HCSA/MarketScan2017/",
  MKT18  = "//serv532B/Research2/No_Backup/HCSA/MarketScan2018/",
  MKT19  = "//serv532b/Research2/No_Backup/HCSA/Marketscan2019/version_b/",
  MKT20  = "//serv532b/Research2/No_Backup/HCSA/Marketscan2020/",
  MKT21  = "//serv532b/Research2/No_Backup/HCSA/Marketscan2021/",
  MKT22  = "//serv532b/Research2/No_Backup/HCSA/Marketscan2022/",
  MKT23  = "//serv532b/Research2/No_Backup/HCSA/Marketscan2023/"
) # <- UPDATE HERE #9

#===========================================================================================
# HELPER FUNCTIONS
#===========================================================================================

# Standardize column names: lowercase, replace spaces/slashes/special chars with underscores
clean_colnames <- function(nms) {
  nms |> tolower() |> str_replace_all("[^a-z0-9]+", "_") |> str_remove("^_|_$")
}

read_sas_file <- function(dir, filename) {
  path <- file.path(dir, paste0(filename, ".sas7bdat"))
  df <- if (TEST_MODE) haven::read_sas(path, n_max = TEST_NROWS) else haven::read_sas(path)
  df <- as_tibble(df); names(df) <- clean_colnames(names(df)); df
}
read_csv_file <- function(path, ...) {
  df <- if (TEST_MODE) readr::read_csv(path, n_max = TEST_NROWS, show_col_types = FALSE, ...)
  else readr::read_csv(path, show_col_types = FALSE, ...)
  names(df) <- clean_colnames(names(df)); df
}
read_excel_file <- function(path, ...) {
  df <- if (TEST_MODE) readxl::read_excel(path, n_max = TEST_NROWS, ...)
  else readxl::read_excel(path, ...)
  df <- as_tibble(df); names(df) <- clean_colnames(names(df)); df
}
save_input <- function(df, name) saveRDS(df, file.path(dir_inputs, paste0(name, ".rds")))
load_input <- function(name) {
  rds_path <- file.path(dir_inputs, paste0(name, ".rds"))
  sas_path <- file.path(dir_inputs, paste0(name, ".sas7bdat"))
  if (file.exists(rds_path)) {
    df <- readRDS(rds_path)
    if (is.data.frame(df)) { names(df) <- clean_colnames(names(df)); df <- as_tibble(df) }
    df
  } else if (file.exists(sas_path)) {
    cat("  [load_input] No .rds for '", name, "', reading .sas7bdat\n", sep = "")
    df <- as_tibble(haven::read_sas(sas_path)); names(df) <- clean_colnames(names(df)); df
  } else stop("Cannot find '", name, "' in ", dir_inputs)
}

assign_age_bucket <- function(age) {
  case_when(
    age == 0 ~ 1L, age >= 1 & age <= 17 ~ 2L, age >= 18 & age <= 24 ~ 3L,
    age >= 25 & age <= 34 ~ 4L, age >= 35 & age <= 44 ~ 5L, age >= 45 & age <= 54 ~ 6L,
    age >= 55 & age <= 64 ~ 7L, age >= 65 & age <= 69 ~ 8L, age >= 70 & age <= 74 ~ 9L,
    age >= 75 & age <= 79 ~ 10L, age >= 80 & age <= 84 ~ 11L, age >= 85 ~ 12L,
    .default = NA_integer_
  )
}

if (TEST_MODE) cat("\n=== TEST MODE: reading only", TEST_NROWS, "rows per file ===\n\n")

###########################################################################################
##   PHASE 1: POPULATION WEIGHTS (Steps 1-12)                                           ##
###########################################################################################

cat("Step 1: Importing CPS population estimates...\n")
`_01_cps_weights` <- read_csv_file(
  file.path(dir_cpscurr, paste0("sc-est", VENDYEAR, "-agesex-civ.csv"))
)

cat("Step 2: Assigning age buckets...\n")
`_02_agebucks` <- `_01_cps_weights` |>
  filter(age != 999) |>
  mutate(age_buck = assign_age_bucket(age))

cat("Step 3: Aggregating population...\n")
popest_cols <- grep("^popest", names(`_02_agebucks`), value = TRUE, ignore.case = TRUE)
`_03_agebuck_sums` <- `_02_agebucks` |>
  filter(sex != 0, state != 0) |>
  group_by(region, sex, age_buck) |>
  summarize(across(all_of(popest_cols), \(x) sum(x, na.rm = TRUE)), .groups = "drop")

cat("Step 4-5: Cleaning and transposing...\n")
`_05_transp` <- `_03_agebuck_sums` |>
  filter(!is.na(region), !is.na(sex), !is.na(age_buck)) |>
  pivot_longer(cols = all_of(popest_cols), names_to = "popest_var", values_to = "popestimate") |>
  mutate(year = as.integer(str_extract(popest_var, "\\d{4}"))) |>
  select(-popest_var)

# Steps 5-6 COMMENTED OUT: Save & stack CPS vintages <- UPDATE HERE #10

cat("Step 7: Extracting MEPS insurance populations...\n")
meps_ins_pop <- function(year2, fy, year4) {
  fy_dt <- read_sas_file(dir_meps, paste0("h", fy))
  v <- list(perwt = paste0("perwt", year2, "f"), age = paste0("age", year2, "x"),
            region = paste0("region", year2), mcrev = paste0("mcrev", year2),
            prvev = paste0("prvev", year2))
  
  base <- fy_dt |>
    select(dupersid, sex, perwt = all_of(v$perwt), age = all_of(v$age),
           region = all_of(v$region), mcrev = all_of(v$mcrev), prvev = all_of(v$prvev)) |>
    mutate(year = year4, age_buck = assign_age_bucket(age))
  
  list(
    tot  = base |> select(dupersid, perwt, sex, age, region, year, age_buck),
    mdcr = base |> filter(mcrev == 1) |> select(dupersid, perwt, sex, age, region, year, age_buck),
    priv = base |> filter(prvev == 1, mcrev == 2, age_buck <= 7) |>
      select(dupersid, perwt, sex, age, region, year, age_buck)
  )
}

meps_years <- list(
  list("99",38,1999), list("00",50,2000), list("01",60,2001), list("02",70,2002),
  list("03",79,2003), list("04",89,2004), list("05",97,2005), list("06",105,2006),
  list("07",113,2007), list("08",121,2008), list("09",129,2009), list("10",138,2010),
  list("11",147,2011), list("12",155,2012), list("13",163,2013), list("14",171,2014),
  list("15",181,2015), list("16",192,2016), list("17",201,2017), list("18",209,2018),
  list("19",216,2019), list("20",224,2020), list("21",233,2021), list("22",243,2022),
  list("23",251,2023)
) # <- UPDATE HERE #11

meps_results <- map(meps_years, \(x) {
  cat("  MEPS year", x[[3]], "\n"); meps_ins_pop(x[[1]], x[[2]], x[[3]])
})

cat("Step 8-9: Stacking and aggregating MEPS...\n")
`_08_totweights`  <- bind_rows(map(meps_results, "tot"))
`_08_mdcrweights` <- bind_rows(map(meps_results, "mdcr"))
`_08_privweights` <- bind_rows(map(meps_results, "priv"))
rm(meps_results); gc()

`_09_tot_pop_MEPS` <- `_08_totweights` |> filter(region > 0) |>
  group_by(year, age_buck, sex, region) |>
  summarize(wt_pop = sum(perwt, na.rm = TRUE), unwt_pop = n(), .groups = "drop")
`_09_mdcr_pop` <- `_08_mdcrweights` |> filter(region > 0) |>
  group_by(year, age_buck, sex, region) |> summarize(pop_mdcr = sum(perwt, na.rm = TRUE), .groups = "drop")
`_09_priv_pop` <- `_08_privweights` |> filter(region > 0) |>
  group_by(year, age_buck, sex, region) |> summarize(pop_priv = sum(perwt, na.rm = TRUE), .groups = "drop")

cat("Step 10: Loading CPS-adjusted weights...\n") # <- UPDATE HERE #12
cps_meps <- load_input(paste0("cps_meps_pop_1999_v", VENDYEAR))
# COMMENTED OUT: Regenerate CPS-MEPS merge (see SAS documentation)

cat("Steps 11-12: Under-65 Medicare weights...\n")
`_11_cps_meps_1` <- cps_meps |> filter(age_buck <= 7) |>
  group_by(sex, region, year) |>
  summarize(adj_cps_mdcr = sum(adj_cps_mdcr, na.rm = TRUE), .groups = "drop")


###########################################################################################
##   PHASE 2: MARKETSCAN SAMPLE SELECTION & PERSON WEIGHTS (Steps 13-21)                ##
###########################################################################################
cat("Phase 2: MarketScan sample selection & weighting...\n")

tag_config <- list(
  a = list(tagged = "in_2000_2005", tagfilename = "2014"),         # <- UPDATE HERE #13
  b = list(tagged = "in_2003_2015", tagfilename = "2017b_ccae"),   # <- UPDATE HERE #14
  c = list(tagged = "in_2011_2016", tagfilename = "2019_ccae"),    # <- UPDATE HERE #15
  d = list(tagged = "in_2014_2023", tagfilename = "2014_2023_ccae") # <- UPDATE HERE #16
)

tag_process <- function(fyr, year_val, liblet, taglet) {
  cat("  TAG: year=", year_val, "tag=", taglet, "\n")
  tc <- tag_config[[taglet]]
  lib_dir <- dir_mkt[[liblet]]
  
  # Step 13: Read enrollment & tagging, merge, apply restrictions
  enr <- read_sas_file(lib_dir, paste0("ccaea", fyr))
  tag_file <- read_sas_file(dir_mktag, paste0("Bea_mscan_tagging_", tc$tagfilename))
  
  plntyp_cols <- paste0("plntyp", 1:12)
  plntyp_cols <- intersect(plntyp_cols, names(enr))
  
  merged <- inner_join(enr, tag_file |> filter(.data[[tc$tagged]] == 1) |> select(enrolid),
                       by = "enrolid")
  
  # Drop capitated plans
  if (length(plntyp_cols) > 0) {
    merged <- merged |>
      mutate(.capplan = reduce(across(all_of(plntyp_cols),
                                      \(x) x %in% c("4", "7", 4, 7)), `|`)) |>
      filter(!.capplan | is.na(.capplan)) |>
      select(-.capplan)
  }
  
  # Apply remaining restrictions
  merged <- merged |>
    filter(rx == "1" | rx == 1) |>
    filter(memdays >= 360 | age == 0) |>
    mutate(famid = str_sub(sprintf("%011.0f", enrolid), 1, 9))
  
  # Steps 14-15: Validate babies
  adults <- merged |> filter(age > 0)
  babies <- merged |> filter(age == 0) |> filter(famid %in% adults$famid)
  
  # Step 16: Combine and assign age buckets
  sample_dt <- bind_rows(adults, babies) |>
    mutate(age_buck = assign_age_bucket(age),
           sex = as.integer(sex), region = as.integer(region)) |>
    filter(age_buck <= 7)
  
  # Step 17: Count enrollees per cell
  enrollee_counts <- sample_dt |>
    group_by(age_buck, sex, year = as.integer(year), region) |>
    summarize(enrollees = n(), .groups = "drop")
  
  # Steps 18-19: Merge with CPS-adjusted private population
  cps_priv_yr <- cps_meps |>
    filter(age_buck <= 7, year == year_val) |>
    select(age_buck, sex, year, region, pop = adj_cps_priv)
  
  weights_dt <- enrollee_counts |>
    left_join(cps_priv_yr, by = c("age_buck", "sex", "year", "region")) |>
    mutate(weight = pop / enrollees)
  
  # Step 20: Attach weight to each enrollee
  sample_dt |>
    mutate(year = as.integer(year)) |>
    left_join(weights_dt |> select(age_buck, sex, year, region, weight),
              by = c("age_buck", "sex", "year", "region")) |>
    select(any_of(c("year", "enrolid", "age", "age_buck", "region", "sex", "weight",
                    "egeoloc", "hlthplan", plntyp_cols)))
}

# TAG macro calls  <- UPDATE HERE #17
tag_calls <- tribble(
  ~fyr,  ~year, ~liblet,  ~taglet,
  "002", 2000,  "MKT007", "a", "013", 2001, "MKT007", "a", "023", 2002, "MKT007", "a",
  "033", 2003,  "MKT007", "a", "045", 2004, "MKT007", "a", "045", 2004, "MKT007", "b",
  "054", 2005,  "MKT007", "b", "063", 2006, "MKT007", "b", "072", 2007, "MKT007", "b",
  "081", 2008,  "MKT08",  "b", "093", 2009, "MKT910", "b", "102", 2010, "MKT910", "b",
  "111", 2011,  "MKT11",  "b", "111", 2011, "MKT11",  "c", "121", 2012, "MKT12",  "c",
  "131", 2013,  "MKT13",  "c", "141", 2014, "MKT14",  "c", "151", 2015, "MKT15",  "c",
  "161", 2016,  "MKT16",  "d", "171", 2017, "MKT17",  "c", "171", 2017, "MKT17",  "d",
  "181", 2018,  "MKT18",  "d", "192", 2019, "MKT19",  "d", "201", 2020, "MKT20",  "d",
  "211", 2021,  "MKT21",  "d", "221", 2022, "MKT22",  "d", "232", 2023, "MKT23",  "d"
)

enr_weights <- list()
for (i in seq_len(nrow(tag_calls))) {
  tc <- tag_calls[i, ]
  key <- paste0(tc$year, "_", tc$taglet)
  enr_weights[[key]] <- tag_process(tc$fyr, tc$year, tc$liblet, tc$taglet)
}

# Step 21 COMMENTED OUT: Stack enrollment files  <- UPDATE HERE #18-19
enr_A <- load_input(paste0("enr_file_w_weight_00_", SHORT_YEAR, "_A"))
enr_B <- load_input(paste0("enr_file_w_weight_00_", SHORT_YEAR, "_B"))


###########################################################################################
##   PHASE 3: SSR REBATE INFRASTRUCTURE (Steps 22-49)                                   ##
###########################################################################################
cat("Phase 3: SSR rebate infrastructure...\n")

`_01_og_SSR_netsales`        <- read_csv_file(file.path(dir_inputs, "Sales.Pr.DATA_data.csv"))             # <- UPDATE HERE #20
`_01_og_SSR_tot_discountrates` <- read_csv_file(file.path(dir_inputs, "GTN.Pr.DATA_data_total.csv"))       # <- UPDATE HERE #21
`_01_og_SSR_NDCs`            <- read_csv_file(file.path(dir_inputs, "NDCUOM.PrStr.DATA_data.csv"))         # <- UPDATE HERE #22

# Step 21: Stack RedBook files  <- UPDATE HERE #23
cat("Step 21: Stacking RedBook files...\n")
redbook_libs <- c("MKT08","MKT910","MKT12","MKT13","MKT14","MKT15","MKT16",
                  "MKT17","MKT18","MKT19","MKT20","MKT21","MKT22","MKT23")
`_21_stacked_REDBOOKs` <- map_dfr(redbook_libs, \(lib) {
  read_sas_file(dir_mkt[[lib]], "redbook") |> select(ndcnum, prodnme, gennme)
}) |>
  mutate(lowcase_redbook_gennme = tolower(gennme), lowcase_redbook_prodnme = tolower(prodnme)) |>
  select(-prodnme, -gennme) |>
  distinct(ndcnum, .keep_all = TRUE)

# Step 22-23: SSR NDC standardization & merge with RedBook
cat("Steps 22-23: SSR NDC processing...\n")
`_22_SSR_11dig_NDCs` <- `_01_og_SSR_NDCs` |>
  mutate(lowcase_ssr_product = str_replace_all(tolower(product), " / ", "/"),
         ndcnum = str_pad(ndc_11, width = 11, side = "left", pad = "0")) |>
  select(ndcnum, lowcase_ssr_product)

`_23_ssr_drugs_w_redbook_ndcs` <- `_22_SSR_11dig_NDCs` |>
  left_join(`_21_stacked_REDBOOKs`, by = "ndcnum") |>
  filter(!ndcnum %in% c("00000000000", "00000000001", "00000000002"))

# Steps 24-29: HCPCS crosswalk  <- UPDATE HERE #24, #25
cat("Steps 24-29: Building HCPCS crosswalk...\n")
import_cms_hcpcs <- function(filename, sheetname, year) {
  dt <- read_excel_file(file.path(dir_inputs, filename), sheet = sheetname)
  if (year %in% c(2017, 2024)) {
    dt <- dt |> transmute(hcpcs = trimws(hcpc), long_description, short_description)
  } else {
    nms <- names(dt)
    dt <- dt |> select(var1 = 1, long_description = 3, short_description = 4) |>
      filter(!is.na(long_description), long_description != "", long_description != "LONG DESCRIPTION") |>
      mutate(hcpcs = trimws(var1)) |> select(-var1)
  }
  dt |> mutate(lowcase_cms_long_desc = tolower(str_remove_all(long_description, "[,-]")),
               lowcase_cms_short_desc = tolower(str_remove_all(short_description, "[,-]"))) |>
    select(hcpcs, lowcase_cms_long_desc, lowcase_cms_short_desc)
}

`_26_cms_concatenated_desc` <- bind_rows(
  import_cms_hcpcs("HCPC17_CONTR_ANWEB.xlsx", "A", 2017),
  import_cms_hcpcs("HCPC2018_CONTR_ANWEB_disc.xlsx", "HCPCS_2018_Alpha", 2018),
  import_cms_hcpcs("HCPC2019_CONTR_ANWEB.xlsx", "A", 2019),
  import_cms_hcpcs("HCPC2020_ANWEB_w_disclaimer.xls", "A", 2020),
  import_cms_hcpcs("HCPC2024_JAN_ANWEB_v4.xlsx", "HCPC2024_JAN_ANWEB_v3", 2024)
) |>
  distinct(hcpcs, lowcase_cms_long_desc, .keep_all = TRUE) |>
  group_by(hcpcs) |>
  summarize(concat_lowcase_cms_long_desc  = paste(lowcase_cms_long_desc, collapse = " #;# "),
            concat_lowcase_cms_short_desc = paste(lowcase_cms_short_desc, collapse = " #;# "),
            .groups = "drop")

palmetto_years <- list(
  list("12-05-2016 NDC-HCPCS XWalk","2016-12-05_xwalkfinalversion.xls"),
  list("12-05-2017 NDC-HCPCS XWalk","2017-12-05XWalkFinalVersion.xls"),
  list("12-05-2018 NDC-HCPCS XWalk","2018-12-05 XWalkFinalVersion.xlsx"),
  list("12-05-2019 NDC-HCPCS XWALK","2019-12-05XWalk.xlsx"),
  list("12-05-2020 NDC-HCPCS XWALK","2020-12-05XWalk.xlsx"),
  list("12-05-2021 NDC-HCPCS XWALK","2021-12-05XWalk.xlsx"),
  list("12-05-2022 NDC-HCPCS XWALK","2022-12-05XWalk.xlsx"),
  list("12-05-2023 NDC-HCPCS XWALK","2023-12-05XWalk.xlsx")
)
`_28_palmetto_concatenated_desc` <- map_dfr(palmetto_years, \(x) {
  read_excel_file(file.path(dir_inputs, x[[2]]), sheet = x[[1]]) |>
    filter(!is.na(hcpcs), hcpcs != "") |>
    transmute(hcpcs, lowcase_palmetto_hcpcs_desc = tolower(str_remove_all(hcpcs_description, "[,-]")),
              lowcase_palmetto_ndc_desc = tolower(ndc_label))
}) |>
  distinct(hcpcs, lowcase_palmetto_hcpcs_desc, .keep_all = TRUE) |>
  group_by(hcpcs) |>
  summarize(concat_lowcase_palm_hcpcs_desc = paste(lowcase_palmetto_hcpcs_desc, collapse = " #;# "),
            concat_lowcase_palm_ndc_desc   = paste(lowcase_palmetto_ndc_desc, collapse = " #;# "),
            .groups = "drop")

`_29_final_hcpcs_cms_palmetto` <- full_join(`_26_cms_concatenated_desc`,
                                            `_28_palmetto_concatenated_desc`, by = "hcpcs") |>
  filter(hcpcs != "None")

# Steps 30-32: Fuzzy match SSR to HCPCS
cat("Steps 30-32: Fuzzy matching SSR to HCPCS...\n")
ssr_prods <- `_23_ssr_drugs_w_redbook_ndcs` |>
  mutate(across(c(lowcase_redbook_gennme, lowcase_redbook_prodnme),
                \(x) if_else(is.na(x) | x == "", "asdfghj", x))) |>
  distinct(lowcase_ssr_product, lowcase_redbook_gennme, lowcase_redbook_prodnme)

word_match <- function(text, pattern) {
  if (is.na(pattern) || pattern == "" || pattern == "asdfghj") return(FALSE)
  str_detect(text, paste0("\\b", pattern, "\\b"))
}

hcpcs_ref <- `_29_final_hcpcs_cms_palmetto`
match_results <- map_dfr(seq_len(nrow(ssr_prods)), \(i) {
  prod <- ssr_prods[i, ]
  matched <- hcpcs_ref |>
    filter(
      map_lgl(concat_lowcase_cms_long_desc, word_match, pattern = prod$lowcase_ssr_product) |
        map_lgl(concat_lowcase_cms_long_desc, word_match, pattern = prod$lowcase_redbook_gennme) |
        map_lgl(concat_lowcase_cms_long_desc, word_match, pattern = prod$lowcase_redbook_prodnme) |
        map_lgl(coalesce(concat_lowcase_cms_short_desc, ""), word_match, pattern = prod$lowcase_ssr_product) |
        map_lgl(coalesce(concat_lowcase_palm_hcpcs_desc, ""), word_match, pattern = prod$lowcase_ssr_product) |
        map_lgl(coalesce(concat_lowcase_palm_ndc_desc, ""), word_match, pattern = prod$lowcase_ssr_product)
    )
  if (nrow(matched) > 0) matched |> mutate(lowcase_ssr_product = prod$lowcase_ssr_product) |> select(lowcase_ssr_product, hcpcs)
})
`_32_ssr_hcpcs_xwalk` <- match_results |> distinct(hcpcs, .keep_all = TRUE)

# Steps 33-41 COMMENTED OUT: load pre-saved
ssr_ipop_drugs_to_drop <- load_input("ssr_ipop_drugs_to_drop")

# Steps 42-49: SSR discount rate processing
cat("Steps 42-49: SSR discount rates...\n")
disc_raw <- `_01_og_SSR_tot_discountrates`
qtr_col  <- names(disc_raw)[str_detect(names(disc_raw), regex("quarter|qtr", ignore_case = TRUE))][1]
gtn_col  <- names(disc_raw)[str_detect(names(disc_raw), regex("gtn|product_metric", ignore_case = TRUE))][1]
prod_col <- names(disc_raw)[str_detect(names(disc_raw), regex("^product$", ignore_case = TRUE))][1]

`_43_avg_tot_discountrate` <- disc_raw |>
  transmute(year = as.integer(str_sub(.data[[qtr_col]], 1, 4)),
            ssr_tot_discount_rate = as.numeric(str_remove(.data[[gtn_col]], "%")) / 100,
            lowcase_ssr_product = str_replace_all(tolower(.data[[prod_col]]), " / ", "/")) |>
  filter(!is.na(ssr_tot_discount_rate)) |>
  group_by(lowcase_ssr_product, year) |>
  summarize(avgyrly_tot_discount_rate = mean(ssr_tot_discount_rate, na.rm = TRUE), .groups = "drop")

# Steps 44-49: Scaffold, merge, drop physician-administered drugs  <- UPDATE HERE #28
all_ssr_names <- `_23_ssr_drugs_w_redbook_ndcs` |> distinct(lowcase_ssr_product)
`_47_ssr_totdiscount_allyears` <- crossing(lowcase_ssr_product = all_ssr_names$lowcase_ssr_product,
                                           year = 2007:2023) |>
  left_join(`_43_avg_tot_discountrate`, by = c("lowcase_ssr_product", "year")) |>
  mutate(gross_margin = if_else(is.na(avgyrly_tot_discount_rate), 0, 0.035),
         avgyrly_tot_discount_rate = replace_na(avgyrly_tot_discount_rate, 0))

# Load pre-saved retail NDC crosswalk
ssr_ndc_xwalk_retail <- load_input(paste0("ssr_ndc_xwalk_Retail_tot", BLEND_NEWYEAR))


###########################################################################################
##   PHASE 4: MEPS NDC-TO-CCSR CROSSWALK (Steps 50-62)                                 ##
###########################################################################################
cat("Phase 4: Building MEPS NDC-CCSR crosswalk...\n")

meps_ndc_ccs_xwalk <- function(file_num, yr, fy_num) {
  cat("  MEPS CCS xwalk: yr =", yr, "\n")
  rx <- read_sas_file(dir_meps, paste0("h", file_num, "a"))
  fy <- read_sas_file(dir_meps, paste0("h", fy_num))
  v_mcrev <- paste0("mcrev", yr); v_prvev <- paste0("prvev", yr)
  
  rx_fy <- inner_join(
    rx |> select(dupersid, rxndc, rxccc1x, rxccc2x, rxccc3x),
    fy |> select(dupersid, all_of(c(v_prvev, v_mcrev))), by = "dupersid"
  ) |>
    filter(.data[[v_prvev]] == 1, .data[[v_mcrev]] == 2, rxndc >= "0") |>
    mutate(ccs1 = as.integer(rxccc1x), ccs2 = as.integer(rxccc2x), ccs3 = as.integer(rxccc3x)) |>
    filter(ccs1 >= 0 | ccs2 >= 0 | ccs3 >= 0) |>
    mutate(across(c(ccs1, ccs2, ccs3), \(x) if_else(x < 0, 0L, x)))
  
  stacked <- bind_rows(
    rx_fy |> filter(ccs1 != 0) |> transmute(rxndc, ccs = ccs1),
    rx_fy |> filter(ccs2 != 0) |> transmute(rxndc, ccs = ccs2),
    rx_fy |> filter(ccs3 != 0) |> transmute(rxndc, ccs = ccs3)
  )
  # Pre-2004 mental health remapping
  yr_int <- as.integer(ifelse(yr == "99", "99", yr))
  if (yr == "99" || yr_int <= 3) {
    remap <- c(`65`=654L,`66`=660L,`67`=661L,`68`=653L,`69`=657L,
               `70`=655L,`71`=659L,`72`=651L,`73`=652L,`74`=670L,`75`=663L)
    stacked <- stacked |> mutate(ccs = if_else(as.character(ccs) %in% names(remap),
                                               remap[as.character(ccs)], ccs))
  }
  ccs_ccsr_xwalk <- load_input("Ccs_ccsr_xwalk2") |>
    select(ccs = beta_version_ccs_category, ccsr = ccsr_category)
  inner_join(stacked, ccs_ccsr_xwalk, by = "ccs") |> select(-ccs)
}

meps_ndc_ccsr_xwalk <- function(file_num, yr, fy_num, mc_num) {
  cat("  MEPS CCSR xwalk: yr =", yr, "\n")
  v_mcrev <- paste0("mcrev", yr); v_prvev <- paste0("prvev", yr)
  
  mc   <- read_sas_file(dir_meps, paste0("h", mc_num))
  appx <- read_sas_file(dir_meps, paste0("h", file_num, "if1"))
  rx   <- read_sas_file(dir_meps, paste0("h", file_num, "a"))
  fy   <- read_sas_file(dir_meps, paste0("h", fy_num))
  
  mc_appx <- inner_join(mc |> select(dupersid, condidx, ccsr1x, ccsr2x, ccsr3x),
                        appx |> select(-any_of(c("panel", "eventype"))),
                        by = c("dupersid", "condidx"))
  mc_appx_rx <- inner_join(mc_appx |> select(dupersid, ccsr1x, ccsr2x, ccsr3x, evntidx),
                           rx |> select(linkidx, rxndc),
                           by = c("evntidx" = "linkidx"), relationship = "many-to-many")
  mc_appx_rx_fy <- inner_join(
    mc_appx_rx |> select(dupersid, rxndc, ccsr1x, ccsr2x, ccsr3x),
    fy |> select(dupersid, all_of(c(v_prvev, v_mcrev))), by = "dupersid"
  ) |> filter(.data[[v_prvev]] == 1, .data[[v_mcrev]] == 2, rxndc >= "0")
  
  bind_rows(
    mc_appx_rx_fy |> filter(ccsr1x != "-1") |> transmute(rxndc, ccsr = ccsr1x),
    mc_appx_rx_fy |> filter(ccsr2x != "-1") |> transmute(rxndc, ccsr = ccsr2x),
    mc_appx_rx_fy |> filter(ccsr3x != "-1") |> transmute(rxndc, ccsr = ccsr3x)
  )
}

# Execute for all years
pre2016 <- list(c(33,"99",38),c(51,"00",50),c(59,"01",60),c(67,"02",70),c(77,"03",79),
                c(85,"04",89),c(94,"05",97),c(102,"06",105),c(110,"07",113),c(118,"08",121),
                c(126,"09",129),c(135,"10",138),c(144,"11",147),c(152,"12",155),c(160,"13",163),
                c(168,"14",171),c(178,"15",181))
pre2016_results <- map(pre2016, \(x) meps_ndc_ccs_xwalk(x[1], x[2], x[3]))

post2016 <- list(c(188,"16",192,190),c(197,"17",201,199),c(206,"18",209,207), # <- UPDATE HERE #29
                 c(213,"19",216,214),c(220,"20",224,222),c(229,"21",233,231),c(239,"22",243,241),c(248,"23",251,249))
post2016_results <- map(post2016, \(x) meps_ndc_ccsr_xwalk(x[1], x[2], x[3], x[4]))

# Step 59 COMMENTED OUT: Stack & clean (load pre-saved)
meps_ndc_ccsr <- load_input(paste0("meps_ndc_ccsr99_", SHORT_YEAR)) |> distinct(rxndc, ccsr)
rm(pre2016_results, post2016_results); gc()

# Steps 60-62: Create NDC dummy matrix
cat("Steps 60-62: Creating NDC dummy matrix...\n")
ccsr_labels <- load_input("ccsr_label_v20231")

`_60_ndc_ccsr_w_trog_ids` <- meps_ndc_ccsr |>
  inner_join(ccsr_labels |> select(ccsr, ccsr_trog_id = ccsrnum), by = "ccsr") |>
  filter(!str_starts(ccsr, "DEN"), !str_starts(ccsr, "-"))

# Build dummy matrix efficiently
ndc_trog <- `_60_ndc_ccsr_w_trog_ids` |>
  group_by(ndcnum = rxndc) |>
  summarize(trog_ids = list(unique(ccsr_trog_id)), .groups = "drop")

ndc_dummy_mat <- matrix(0L, nrow = nrow(ndc_trog), ncol = NUM)
colnames(ndc_dummy_mat) <- paste0("trogndcdummy", 1:NUM)
for (i in seq_len(nrow(ndc_trog))) {
  ids <- ndc_trog$trog_ids[[i]]
  ids <- ids[!is.na(ids) & ids >= 1 & ids <= NUM]
  if (length(ids) > 0) ndc_dummy_mat[i, ids] <- 1L
}
`_62_ndcdum` <- bind_cols(ndc_trog |> select(ndcnum), as_tibble(ndc_dummy_mat))
rm(ndc_dummy_mat, ndc_trog); gc()


###########################################################################################
##   PHASE 5: MARKETSCAN CLAIMS PROCESSING & TROGDON REGRESSIONS (Steps 63-93)         ##
###########################################################################################
cat("Phase 5: Claims processing & Trogdon regressions...\n")

icd9ccsrip <- load_input("icd9ccsrip_format")
icd9ccsrop <- load_input("icd9ccsrop_format")
ccsrip     <- load_input("ccsrip_format")
ccsrop     <- load_input("ccsrop_format")

marketscan_claims <- function(year_val, tag, lib, yr) {
  cat("  Claims: year=", year_val, " tag=", tag, "\n")
  lib_dir <- dir_mkt[[lib]]
  
  # ==== PART A: IP/OP CLAIMS ====
  if (tag == "A") {
    ip <- read_sas_file(lib_dir, paste0("ccaes", yr))
    op <- read_sas_file(lib_dir, paste0("ccaeo", yr))
    
    merge_icd <- function(claims, xwalk) {
      inner_join(claims |> select(enrolid, dx1, pay), xwalk |> transmute(dx1 = start, ccsr), by = "dx1")
    }
    if (year_val < 2015) {
      ip_ccsr <- merge_icd(ip, icd9ccsrip); op_ccsr <- merge_icd(op, icd9ccsrop)
    } else {
      ip_ccsr <- bind_rows(merge_icd(ip |> filter(dxver == "9"), icd9ccsrip),
                           merge_icd(ip |> filter(dxver == "0"), ccsrip))
      op_ccsr <- bind_rows(merge_icd(op |> filter(dxver == "9"), icd9ccsrop),
                           merge_icd(op |> filter(dxver == "0"), ccsrop))
    }
    `_65_ipop` <<- bind_rows(ip_ccsr, op_ccsr)
    rm(ip, op); gc()
  }
  
  # Step 66: Merge with person weights
  enr_file <- if (tag == "A") enr_A else enr_B
  enr_yr <- enr_file |> filter(year == year_val) |> select(enrolid, year, weight)
  
  `_66_weighted_ipop` <- inner_join(`_65_ipop`, enr_yr, by = "enrolid") |>
    filter(!is.na(enrolid), weight > 0) |>
    mutate(weighted_pay = weight * pay)
  
  # Steps 67-70: Patient CCSR dummy matrix
  `_67_ipop_trog` <- `_66_weighted_ipop` |>
    select(enrolid, ccsr, weight) |>
    inner_join(ccsr_labels |> select(ccsr, ccsr_trog_id = ccsrnum), by = "ccsr") |>
    filter(!str_starts(ccsr, "DEN"), ccsr != "", !str_starts(ccsr, "-"))
  
  `_68_pat_ccsr` <- `_67_ipop_trog` |> distinct(enrolid, ccsr, .keep_all = TRUE)
  pat_ids <- `_68_pat_ccsr` |> distinct(enrolid, weight)
  pat_trog_list <- `_68_pat_ccsr` |> group_by(enrolid) |>
    summarize(trog_ids = list(ccsr_trog_id), .groups = "drop")
  
  ccsr_mat <- matrix(0L, nrow = nrow(pat_trog_list), ncol = NUM)
  for (i in seq_len(nrow(pat_trog_list))) {
    ids <- pat_trog_list$trog_ids[[i]]
    ids <- ids[!is.na(ids) & ids >= 1 & ids <= NUM]
    if (length(ids) > 0) ccsr_mat[i, ids] <- 1L
  }
  colnames(ccsr_mat) <- paste0("trogccsrdummy", 1:NUM)
  `_70_inout_w_dum` <- bind_cols(
    pat_trog_list |> select(enrolid),
    pat_trog_list |> select(enrolid) |> inner_join(pat_ids, by = "enrolid") |> select(weight),
    as_tibble(ccsr_mat)
  )
  rm(ccsr_mat); gc()
  
  # ==== PART B: PRESCRIPTION DRUG CLAIMS ====
  if (tag == "A") {
    rx_raw <- read_sas_file(lib_dir, paste0("ccaed", yr))
    if (year_val <= 2006) {
      rx_raw <- rx_raw |> mutate(pay_netofrebate = pay)
    } else {
      rx_ssr <- ssr_ndc_xwalk_retail |> filter(year == year_val) |>
        select(ndcnum, avgyrly_tot_discount_rate, gross_margin, ssr_flag)
      rx_raw <- rx_raw |>
        left_join(rx_ssr, by = "ndcnum") |>
        mutate(pay_netofrebate = if_else(
          ssr_flag == 1 & !is.na(ssr_flag),
          (1 - gross_margin) * pay * (1 - avgyrly_tot_discount_rate) + gross_margin * pay,
          pay
        ))
    }
    `_71_rx` <<- rx_raw |> select(enrolid, ndcnum, pay, pay_netofrebate)
    rm(rx_raw); gc()
  }
  
  # Step 72-73: Weight Rx, sum annual
  `_72_weighted_rx` <- inner_join(`_71_rx`, enr_yr, by = "enrolid") |> filter(!is.na(enrolid), weight > 0)
  `_73_iddrugpay` <- `_72_weighted_rx` |> group_by(enrolid) |>
    summarize(pay = sum(pay, na.rm = TRUE), pay_netofrebate = sum(pay_netofrebate, na.rm = TRUE), .groups = "drop")
  
  # Steps 74-76: Intersection dummies
  rx_ndc_unique <- `_72_weighted_rx` |> distinct(enrolid, ndcnum)
  ndc_dummy_cols <- paste0("trogndcdummy", 1:NUM)
  ccsr_dummy_cols <- paste0("trogccsrdummy", 1:NUM)
  intersect_cols <- paste0("ccsrdummy", 1:NUM)
  
  ndc_agg <- inner_join(rx_ndc_unique, `_62_ndcdum`, by = "ndcnum") |>
    group_by(enrolid) |>
    summarize(across(all_of(ndc_dummy_cols), \(x) as.integer(any(x > 0))), .groups = "drop")
  
  intersect_dt <- inner_join(ndc_agg, `_70_inout_w_dum` |> select(enrolid, all_of(ccsr_dummy_cols)),
                             by = "enrolid")
  # Compute intersection: both ndc and ccsr dummy = 1
  for (j in 1:NUM) {
    intersect_dt[[intersect_cols[j]]] <- as.integer(
      intersect_dt[[ndc_dummy_cols[j]]] > 0 & intersect_dt[[ccsr_dummy_cols[j]]] > 0
    )
  }
  intersect_dt <- intersect_dt |> select(enrolid, all_of(intersect_cols))
  
  # Step 77: Regression dataset
  `_77_reg_data` <- intersect_dt |>
    inner_join(`_73_iddrugpay`, by = "enrolid") |>
    inner_join(`_70_inout_w_dum` |> select(enrolid, weight), by = "enrolid") |>
    mutate(logdollars_paynetofrebate = log(pay_netofrebate + 1),
           logdollars_pay = log(pay + 1))
  rm(intersect_dt, ndc_agg); gc()
  
  # ==== PART C: TROGDON REGRESSION ====
  run_trogdon <- function(df, depvar) {
    formula_str <- paste0(depvar, " ~ ", paste(intersect_cols, collapse = " + "))
    fit <- lm(as.formula(formula_str), data = df, weights = df$weight)
    
    coefs <- coef(fit)
    resid_vec <- residuals(fit)
    intercept <- coefs["(Intercept)"]
    beta <- coefs[intersect_cols]; beta[is.na(beta)] <- 0
    
    dummy_mat <- as.matrix(df |> select(all_of(intersect_cols)))
    beta_vec <- as.numeric(beta)
    
    exp_beta_dummy <- sweep(dummy_mat, 2, exp(beta_vec), `*`)
    exp_sum <- rowSums(exp_beta_dummy)
    exp_sum[exp_sum == 0] <- NA_real_
    sk <- exp_beta_dummy / exp_sum; sk[is.na(sk)] <- 0
    
    dis_mat <- sweep(dummy_mat, 2, beta_vec, `*`)
    dis_sum <- rowSums(dis_mat)
    
    etg_disease <- (exp(intercept + dis_sum) * exp(resid_vec)) - (exp(intercept) * exp(resid_vec))
    doll_int <- exp(intercept) * exp(resid_vec) - 1
    dolld_mat <- sweep(sk, 1, etg_disease + doll_int, `*`)
    
    tibble(ccsrdum = 1:NUM, dollars = colSums(dolld_mat * df$weight, na.rm = TRUE))
  }
  
  rx_netrebate <- run_trogdon(`_77_reg_data`, "logdollars_paynetofrebate") |>
    rename(rx_dollars_netrebate = dollars)
  rx_ogpay <- if (year_val == 2007 & tag == "A") {
    run_trogdon(`_77_reg_data`, "logdollars_pay") |> rename(rx_dollars_ogpay = dollars)
  } else NULL
  rm(`_77_reg_data`); gc()
  
  # Step 87: CCSR labels
  rx_final <- rx_netrebate |>
    left_join(ccsr_labels |> select(ccsrdum = ccsrnum, ccsr, ccsr_label, ccsr_chpt, ccsr_chpt_label),
              by = "ccsrdum") |>
    filter(!str_starts(ccsr, "DEN") | is.na(ccsr)) |>
    mutate(year = year_val)
  if (!is.null(rx_ogpay)) rx_final <- left_join(rx_final, rx_ogpay, by = "ccsrdum")
  
  # ==== PART D: COMBINE ====
  `_88_ipop_sum` <- `_66_weighted_ipop` |>
    group_by(ccsr) |> summarize(ipop_pay = sum(weighted_pay, na.rm = TRUE), .groups = "drop") |>
    mutate(year = year_val)
  
  wt_vec <- `_70_inout_w_dum`$weight
  ccsr_dum_mat <- as.matrix(`_70_inout_w_dum` |> select(all_of(ccsr_dummy_cols)))
  weighted_patients <- colSums(sweep(ccsr_dum_mat, 1, wt_vec, `*`), na.rm = TRUE)
  `_92_ipop_pats` <- tibble(ccsrdum = 1:NUM, patients = as.numeric(weighted_patients), year = year_val) |>
    left_join(ccsr_labels |> select(ccsrdum = ccsrnum, ccsr), by = "ccsrdum") |>
    filter(!str_starts(ccsr, "DEN") | is.na(ccsr))
  
  result <- `_88_ipop_sum` |>
    full_join(rx_final |> select(year, ccsr, rx_dollars_netrebate, ccsr_label, ccsr_chpt,
                                 ccsr_chpt_label, ccsrdum, any_of("rx_dollars_ogpay")),
              by = c("year", "ccsr")) |>
    full_join(`_92_ipop_pats` |> select(year, ccsr, patients), by = c("year", "ccsr")) |>
    mutate(dollars = replace_na(ipop_pay, 0) + replace_na(rx_dollars_netrebate, 0))
  
  rm(`_66_weighted_ipop`, `_70_inout_w_dum`, `_72_weighted_rx`); gc()
  result
}

# Execute  <- UPDATE HERE #30
claims_calls <- tribble(
  ~year, ~tag, ~lib,     ~yr,
  2000,  "A",  "MKT007", "002", 2001, "A", "MKT007", "013", 2002, "A", "MKT007", "023",
  2003,  "A",  "MKT007", "033", 2004, "A", "MKT007", "045", 2004, "B", "MKT007", "045",
  2005,  "A",  "MKT007", "054", 2006, "A", "MKT007", "063", 2007, "A", "MKT007", "072",
  2008,  "A",  "MKT08",  "081", 2009, "A", "MKT910", "093", 2010, "A", "MKT910", "102",
  2011,  "A",  "MKT11",  "111", 2011, "B", "MKT11",  "111", 2012, "A", "MKT12",  "121",
  2013,  "A",  "MKT13",  "131", 2014, "A", "MKT14",  "141", 2015, "A", "MKT15",  "151",
  2016,  "A",  "MKT16",  "161", 2017, "A", "MKT17",  "171", 2017, "B", "MKT17",  "171",
  2018,  "A",  "MKT18",  "181", 2019, "A", "MKT19",  "192", 2020, "A", "MKT20",  "201",
  2021,  "A",  "MKT21",  "211", 2022, "A", "MKT22",  "221", 2023, "A", "MKT23",  "232"
)

mktscn_ccsr <- list()
for (i in seq_len(nrow(claims_calls))) {
  cc <- claims_calls[i, ]
  key <- paste0(cc$year, "_", cc$tag)
  mktscn_ccsr[[key]] <- marketscan_claims(cc$year, cc$tag, cc$lib, cc$yr)
}


###########################################################################################
##   PHASE 6: PRE-2007 REBATE BACKCASTING & TAG BLENDING (Steps 93z-200)               ##
###########################################################################################
cat("Phase 6: Rebate backcasting & tag blending...\n")

# ---- Sub-Phase 6A: Pre-2007 rebate backcasting ----
cat("  Steps 94-99: Rebate backcasting...\n")
expend_2000_2007 <- bind_rows(map(2000:2007, \(y) mktscn_ccsr[[paste0(y, "_A")]]))

backcasted_all <- map_dfr(1:NUM, \(cnum) {
  dt_ccsr <- expend_2000_2007 |> filter(ccsrdum == cnum)
  if (nrow(dt_ccsr) == 0) return(tibble())
  dt_ccsr <- dt_ccsr |>
    mutate(rebate_dollars = case_when(
      year == 2007 & !is.na(rx_dollars_ogpay) ~ rx_dollars_ogpay - rx_dollars_netrebate,
      year == 2000 ~ 0, .default = NA_real_
    )) |>
    arrange(year) |>
    mutate(period = row_number())
  known <- dt_ccsr |> filter(!is.na(rebate_dollars))
  if (nrow(known) >= 2) {
    fit <- lm(rebate_dollars ~ period, data = known)
    dt_ccsr <- dt_ccsr |> mutate(predicted_rebate_dollars = predict(fit, newdata = dt_ccsr))
  } else {
    dt_ccsr <- dt_ccsr |> mutate(predicted_rebate_dollars = 0)
  }
  dt_ccsr
})

# Step 93z: Subtract backcasted rebates from 2001-2006
for (y in 2001:2006) {
  adj <- backcasted_all |> filter(year == y, rx_dollars_netrebate > 0) |> select(ccsr, predicted_rebate_dollars)
  key <- paste0(y, "_A")
  if (!is.null(mktscn_ccsr[[key]])) {
    mktscn_ccsr[[key]] <- mktscn_ccsr[[key]] |>
      left_join(adj, by = "ccsr") |>
      mutate(dollars = if_else(!is.na(predicted_rebate_dollars), dollars - predicted_rebate_dollars, dollars)) |>
      select(-predicted_rebate_dollars)
  }
}

# Step 99: Apply 2004_A rebates to 2004_B
rebates_2004 <- backcasted_all |> filter(year == 2004) |> select(ccsrdum, predicted_rebate_dollars)
if (!is.null(mktscn_ccsr[["2004_B"]])) {
  mktscn_ccsr[["2004_B"]] <- mktscn_ccsr[["2004_B"]] |>
    left_join(rebates_2004, by = "ccsrdum") |>
    mutate(dollars = case_when(
      rx_dollars_netrebate > 0 & !is.na(predicted_rebate_dollars) ~ dollars - predicted_rebate_dollars,
      is.na(dollars) ~ ipop_pay, .default = dollars
    )) |> select(-predicted_rebate_dollars)
}
rm(backcasted_all, expend_2000_2007); gc()

# ---- Sub-Phase 6B: Tag blending ----  <- UPDATE HERE #31
cat("  Step 200: Tag blending...\n")

# Helper: chain one year backward
chain_backward <- function(prev_dt, cur_key, nxt_key) {
  cur <- mktscn_ccsr[[cur_key]]
  nxt <- mktscn_ccsr[[nxt_key]]
  prev_dt |>
    select(ccsr, prev_dollars = dollars, prev_patients = patients) |>
    full_join(cur |> select(ccsr, cur_d = dollars, cur_p = patients, year, ipop_pay,
                            rx_dollars_netrebate, ccsr_label, ccsr_chpt, ccsr_chpt_label, ccsrdum), by = "ccsr") |>
    full_join(nxt |> select(ccsr, nxt_d = dollars, nxt_p = patients), by = "ccsr") |>
    mutate(dollars = prev_dollars * (cur_d / nxt_d), patients = prev_patients * (cur_p / nxt_p))
}

# Segment 1: 2017_B anchor -> 2016 -> 2015 -> ... -> 2012
`_200_2016` <- mktscn_ccsr[["2017_B"]] |>
  select(ccsr, prev_dollars = dollars, prev_patients = patients) |>
  full_join(mktscn_ccsr[["2016_A"]] |> select(ccsr, cur_d = dollars, cur_p = patients, year, ipop_pay,
                                              rx_dollars_netrebate, ccsr_label, ccsr_chpt, ccsr_chpt_label, ccsrdum), by = "ccsr") |>
  full_join(mktscn_ccsr[["2017_A"]] |> select(ccsr, nxt_d = dollars, nxt_p = patients), by = "ccsr") |>
  mutate(dollars = prev_dollars * (cur_d / nxt_d), patients = prev_patients * (cur_p / nxt_p))

prev <- `_200_2016`
blended <- list(`2016` = prev)
for (y in 2015:2012) {
  prev <- chain_backward(prev, paste0(y, "_A"), paste0(y + 1, "_A"))
  blended[[as.character(y)]] <- prev
}

# Break year 2011: use tag B
blended[["2011"]] <- chain_backward(prev, "2011_B", "2012_A")
prev <- blended[["2011"]]

# Segment 2: 2010 through 2007
# Switch at 2010: use 2011_A growth rates
`_200_2010` <- prev |>
  select(ccsr, prev_dollars = dollars, prev_patients = patients) |>
  full_join(mktscn_ccsr[["2010_A"]] |> select(ccsr, cur_d = dollars, cur_p = patients, year, ipop_pay,
                                              rx_dollars_netrebate, ccsr_label, ccsr_chpt, ccsr_chpt_label, ccsrdum), by = "ccsr") |>
  full_join(mktscn_ccsr[["2011_A"]] |> select(ccsr, nxt_d = dollars, nxt_p = patients), by = "ccsr") |>
  mutate(dollars = prev_dollars * (cur_d / nxt_d), patients = prev_patients * (cur_p / nxt_p))
blended[["2010"]] <- `_200_2010`
prev <- `_200_2010`

for (y in 2009:2007) {
  prev <- chain_backward(prev, paste0(y, "_A"), paste0(y + 1, "_A"))
  blended[[as.character(y)]] <- prev
}

# 2006-2005: rebate-adjusted datasets
for (y in 2006:2005) {
  prev <- chain_backward(prev, paste0(y, "_A"), paste0(y + 1, "_A"))
  blended[[as.character(y)]] <- prev
}

# Break year 2004: use tag B
blended[["2004"]] <- chain_backward(prev, "2004_B", "2005_A")
prev <- blended[["2004"]]

# Segment 3: Switch at 2003
`_200_2003` <- prev |>
  select(ccsr, prev_dollars = dollars, prev_patients = patients) |>
  full_join(mktscn_ccsr[["2003_A"]] |> select(ccsr, cur_d = dollars, cur_p = patients, year, ipop_pay,
                                              rx_dollars_netrebate, ccsr_label, ccsr_chpt, ccsr_chpt_label, ccsrdum), by = "ccsr") |>
  full_join(mktscn_ccsr[["2004_A"]] |> select(ccsr, nxt_d = dollars, nxt_p = patients), by = "ccsr") |>
  mutate(dollars = prev_dollars * (cur_d / nxt_d), patients = prev_patients * (cur_p / nxt_p))
blended[["2003"]] <- `_200_2003`
prev <- `_200_2003`

for (y in 2002:2000) {
  prev <- chain_backward(prev, paste0(y, "_A"), paste0(y + 1, "_A"))
  blended[[as.character(y)]] <- prev
}


###########################################################################################
##   PHASE 7: NHEA BENCHMARKING (Steps 201-214)                                        ##
###########################################################################################
cat("Phase 7: NHEA benchmarking...\n")

# Step 201: Stack  <- UPDATE HERE #32-33
keep_cols <- c("ccsr", "ccsr_label", "ccsr_chpt", "ccsr_chpt_label", "year", "dollars", "patients")

blended_list <- map(2000:2015, \(y) blended[[as.character(y)]] |> select(any_of(keep_cols)))
direct_list <- list(
  mktscn_ccsr[["2016_A"]] |> select(any_of(keep_cols)),
  mktscn_ccsr[["2017_B"]] |> select(any_of(keep_cols))
)
recent_list <- map(2018:2023, \(y) mktscn_ccsr[[paste0(y, "_A")]] |> select(any_of(keep_cols)))
`_201_forindex` <- bind_rows(c(blended_list, direct_list, recent_list))

# Steps 202-203: MCE indexes
`_202_weight` <- `_201_forindex` |> filter(year == BASEYR) |>
  select(ccsr, lag_dollars = dollars, lag_patients = patients)
`_203_compare` <- `_201_forindex` |>
  left_join(`_202_weight`, by = "ccsr") |>
  mutate(MCE_incld_clms = (dollars / patients) / (lag_dollars / lag_patients),
         Paas_incld_Clms = 1 / MCE_incld_clms)

# Steps 204-209: CCSR shares
`_204_agg` <- `_203_compare` |> group_by(year) |>
  summarize(paytotal_year = sum(dollars, na.rm = TRUE), .groups = "drop")
`_209_compare` <- `_203_compare` |>
  left_join(`_204_agg`, by = "year") |>
  mutate(share = dollars / paytotal_year)

# NHEA table imports
cat("  Importing NHEA tables...\n")
import_nhea_service <- function(table_num, shortname) {
  files <- list.files(dir_inputs, pattern = paste0("Table.*", table_num, ".*\\.xlsx"), full.names = TRUE)
  dt <- read_excel_file(files[1])
  nms <- names(dt)
  dt |>
    slice(1:32) |>
    transmute(year = as.integer(.data[[nms[1]]]),
              oop = as.numeric(.data[[nms[3]]]),
              expenditure = as.numeric(.data[[nms[5]]])) |>
    filter(year >= 2000, !is.na(year)) |>
    transmute(year, !!paste0("private_", shortname, "_exp_w_oop") := oop + expenditure)
}

nhea_07 <- import_nhea_service("7", "physclin")
nhea_08 <- import_nhea_service("8", "hosp")
nhea_11 <- import_nhea_service("11", "othprof")
nhea_14 <- import_nhea_service("14", "homehlth")
nhea_16 <- import_nhea_service("16", "rx")

# Table 21
files_21 <- list.files(dir_inputs, pattern = "Table.*21.*\\.xlsx", full.names = TRUE)
nhea_21_raw <- read_excel_file(files_21[1])
names(nhea_21_raw)[1] <- "var1"
nhea_21_raw <- nhea_21_raw |> slice(1:10)
year_cols <- names(nhea_21_raw)[names(nhea_21_raw) != "var1"]
year_mapping <- 2000:(2000 + length(year_cols) - 1)

nhea_21_emp <- tibble(year = year_mapping,
                      private_emp = as.numeric(unlist(nhea_21_raw |> filter(str_detect(var1, "Employer Sponsored")) |>
                                                        slice(1) |> select(all_of(year_cols)))))
nhea_21_oth <- tibble(year = year_mapping,
                      private_oth = as.numeric(unlist(nhea_21_raw |> filter(str_detect(var1, "Direct Purchase")) |>
                                                        slice(1) |> select(all_of(year_cols)))))

# Step 213: Merge NHEA tables
`_213_nhea` <- reduce(list(nhea_07, nhea_08, nhea_11, nhea_14, nhea_16, nhea_21_emp, nhea_21_oth),
                      \(x, y) left_join(x, y, by = "year")) |>
  filter(year <= BLEND_NEWYEAR) |>
  mutate(nhea_health = private_hosp_exp_w_oop + private_physclin_exp_w_oop +
           private_othprof_exp_w_oop + private_homehlth_exp_w_oop + private_rx_exp_w_oop,
         private_total = private_emp + private_oth,
         emp_share = private_emp / private_total,
         nhea_health_emp = nhea_health * emp_share) |>
  select(year, nhea_health_emp)

# Step 214: Apply NHEA benchmarking
cat("  Step 214: Benchmarking...\n")
`_214_Spending_on_ccc_mce` <- `_209_compare` |>
  select(year, ccsr, ccsr_label, ccsr_chpt, ccsr_chpt_label, dollars, patients, share) |>
  left_join(`_213_nhea`, by = "year") |>
  mutate(nhea_all = share * nhea_health_emp,
         nhea_dollars = nhea_all * 1e9,
         number_of_episodes = patients * (nhea_dollars / dollars),
         cost_per_case = nhea_dollars / number_of_episodes)

final_output <- `_214_Spending_on_ccc_mce` |>
  select(year, ccsr, ccsr_label, ccsr_chpt, ccsr_chpt_label,
         nhea_dollars, number_of_episodes, cost_per_case,
         uncontrolled_mktscn_dollars = dollars, patients)

# COMMENTED OUT: Export
# write.xlsx(final_output, file.path(dir_outputs,
#   paste0("employer_sponsored_ccsr_output00_23_", format(Sys.Date(), "%d%b%Y"), ".xlsx")))

cat("Employer_Sponsored.R completed at", format(Sys.time()), "\n")
sink()
cat("Complete. final_output:", nrow(final_output), "rows x", ncol(final_output), "cols\n")
