## Load your packages, e.g. library(targets).
source("./packages.R")

## Load your R files
lapply(list.files("./R", full.names = TRUE), source)

## tar_plan supports drake-style targets and also tar_target()
tar_plan(

  ## initial files and data in -----
  tar_target(metadata_file,
             "data/working/sample_metadata.csv",
             format = "file"),
  sample_info = readr::read_csv(metadata_file) |>
    janitor::clean_names() |>
    dplyr::mutate(sample_id = janitor::make_clean_names(sample_id)) |>
    collapse_drinking(),

  tar_target(feature_measured_file,
             "data/working/feature_intensities.csv",
             format = "file"),

  feature_intensities = readr::read_csv(feature_measured_file) |>
    janitor::clean_names() |>
    dplyr::mutate(feature_id = feature_metadata$feature_id),

  feature_intensities_nourea = feature_intensities |>
    dplyr::filter(!(feature_id %in% "urea")),

  medians_nourea = compare_medians(feature_intensities,
                                   feature_intensities_nourea),

  tar_target(feature_metadata_file,
             "data/working/feature_metadata.csv",
             format = "file"),
  feature_metadata = readr::read_csv(feature_metadata_file) |>
    janitor::clean_names() |>
    dplyr::mutate(feature_id = janitor::make_clean_names(bin_base_name),
                  feature_name = stringr::str_to_sentence(bin_base_name),
                  feature_label = dplyr::case_when(
                    feature_name %in% "Phenoxyacetic acid" ~ "PA",
                    feature_name %in% "Ribonic acid" ~ "RA",
                    feature_name %in% "Isoleucine" ~ "IL",
                    feature_name %in% "3-aminoisobutyric acid" ~ "3AIBA",
                    feature_name %in% "6-deoxyglucitol" ~ "6DG",
                    TRUE ~ feature_name
                  ),
                  named = dplyr::case_when(
                    grepl("x[[:digit:]]{2}", feature_id) ~ FALSE,
                    TRUE ~ TRUE
                  )),

  tar_target(sample_osmolarity_file,
             "data/working/sample_osmolarity.csv",
             format = "file"),
  sample_osmolarity = readr::read_csv(sample_osmolarity_file) |>
    janitor::clean_names() |>
    dplyr::mutate(sample_id = janitor::make_clean_names(sample_id)),

  all_info = add_pooled_osmolarity(feature_intensities,
                                   sample_info,
                                   sample_osmolarity),

  all_info_nodiabetic = all_info |>
    dplyr::mutate(diabetes_bl = dplyr::case_when(
      diabetes_bl %in% "N/A" ~ "No",
      TRUE ~ diabetes_bl
    )) |>
    dplyr::filter(sample_id %in% samples_gr_only_nout),

  ## analysis -----
  pancreatitis_colors = list(
    all_groups = c("0" = "#0066FF",
                   "1" = "#55FF55",
                   "6" = "#FF0000"),
    slimmed_groups = c("0" = "#0066FF",
                       "1" = "#55FF55",
                       "4" = "#FF0000")
  ),
  # pancreatitis_colors = create_colors(),

  ## check for left-censorship --------
  left_censoring = test_left_censorship(feature_intensities |>
                                          dplyr::select(all_of(all_info$sample_id)) |>
                                          as.matrix(),
                                        all_info$cohort_c),

  ## normalization various ways ----
  norm_functions = list(none = no_normalization,
                          median = median_normalization,
                          osmolarity = osmolarity_normalization,
                          osmo_med = osmolarity_median_normalization),
  normalized_data = purrr::map(norm_functions, function(in_function){
    in_function(feature_intensities,
                all_info)
    }),

  mean_sd_intensity = find_intensity_cutoff(normalized_data$osmo_med),
  mean_cutoff = 0.2,

  normalized_data_zero = normalized_data$osmo_med |>
    dplyr::mutate(intensity = dplyr::case_when(
      intensity < mean_cutoff ~ 0,
      TRUE ~ intensity
    )),

  outlier_data = purrr::map(normalized_data, check_outliers),
  pca_runs = purrr::map(normalized_data, run_pca, all_info),
  ici_cor = run_ici(normalized_data$osmo_med),

  outlier_data_0 = check_outliers(normalized_data_zero),
  pca_0 = run_pca(normalized_data_zero, all_info),
  ici_0 = run_ici(normalized_data_zero),

  ## remove pooled samples ----
  feature_intensities_gronly = feature_intensities |>
    dplyr::select(-tidyselect::starts_with("pool")),
  normalized_gr_only_all = purrr::map(norm_functions, function(in_function){
    in_function(feature_intensities_gronly,
                all_info)
  }),

  samples_gr_only = all_info |>
    dplyr::filter(cohort_c %in% c(1, 6)) |>
    dplyr::pull(sample_id),

  normalized_gr_only = normalized_gr_only_all$median |>
    dplyr::filter(sample_id %in% samples_gr_only),

  pca_gr_only = run_pca(normalized_gr_only, all_info),
  pca_vs_attributes_gr_only = test_pcs(pca_gr_only),
  ici_cor_gr = run_ici(normalized_gr_only),
  pca_loadings_gr_only = test_loadings(pca_gr_only),

  outlier_samples_gr_only = check_sample_outliers(normalized_gr_only,
                                                  ici_cor_gr,
                                                  all_info),

  samples_gr_only_nout = intersect(samples_gr_only, outlier_samples_gr_only$both |>
                                     dplyr::filter(!outlier) |>
                                     dplyr::pull(sample_id)),


  normalized_gr_only_nout = normalized_gr_only |>
    dplyr::filter(sample_id %in% samples_gr_only_nout),

  pca_gr_only_nout = run_pca(normalized_gr_only_nout, all_info |> dplyr::filter(sample_id %in% samples_gr_only_nout)),
  pca_vs_attributes_gr_only_nout = test_pcs(pca_gr_only_nout),
  pca_loadings_gr_only_nout = test_loadings(pca_gr_only_nout),


  gr_info_nodiabetic = all_info |>
    dplyr::mutate(diabetes_bl = dplyr::case_when(
      diabetes_bl %in% "N/A" ~ "No",
      TRUE ~ diabetes_bl
    )) |>
    dplyr::filter(sample_id %in% samples_gr_only_nout),

  ## feature correlations
  ici_cor_features_gr = run_ici_features(normalized_gr_only_nout,
                                         samples_gr_only_nout),

  feature_clusters = purrr::map(c(1.1, 1.15, 1.2),
                               create_clusters,
                               ici_cor_features_gr,
                               feature_metadata),



  kegg_data = get_kegg_compound_data(),

  kegg_annotations = create_kegg_annotations(feature_metadata,
                                                        kegg_data),

  kegg_cluster_enrichment = purrr::map(feature_clusters,
                                          enrich_clusters,
                                          kegg_annotations,
                                          feature_id = "kegg"),

  ## ratios instead ----------
  feature_imputed = impute_lowest(feature_intensities_gronly),
  feature_ratios = calculate_ratios(feature_imputed,
                                    all_info_nodiabetic),
  ici_cor_ratios = run_ici(feature_ratios),

## differential analysis ----
  gr_diff_cut = 0.05,
  gr_differences = run_t_tests(feature_intensities = normalized_gr_only_nout,
                               samples = samples_gr_only_nout,
                               comparisons = c(6, 1),
                               sample_info = gr_info_nodiabetic,
                               p_cut = gr_diff_cut),
  gr_differences_metabolite = add_metabolite_id(gr_differences,
                                                feature_metadata),

  gr_differences_raincloud = create_raincloud_plots(gr_differences,
                                          feature_intensities = normalized_gr_only_nout,
                                          feature_metadata = feature_metadata,
                                          comparisons = c("CP" = 6, "Control" = 1),
                                          sample_info = gr_info_nodiabetic,
                                          colors = pancreatitis_colors$all_groups,
                                          use_samples = samples_gr_only_nout),



  gr_ratio_cut = 0.01,
  gr_ratio_differences = run_t_tests(feature_intensities = feature_ratios,
                                     samples = samples_gr_only_nout,
                                     comparisons = c(6, 1),
                                     sample_info = all_info,
                                     p_cut = gr_ratio_cut),
  gr_ratio_differences_metabolite = add_metabolite_ratio(gr_ratio_differences,
                                                      feature_metadata),

  gr_ratio_ranked_logfc = create_ranked_ratio_logfc_table(gr_ratio_differences_metabolite),

  gr_ratio_direct_compare = compare_direct_ratio(gr_differences_metabolite,
                                                 gr_ratio_differences_metabolite),

  # gr_ratio_differences_raincloud = create_raincloud_plots(gr_ratio_differences,
  #                                         feature_intensities = feature_ratios,
  #                                         feature_metadata = NULL,
  #                                         comparisons = c(6, 1),
  #                                         sample_info = all_info,
  #                                         colors = pancreatitis_colors$all_groups),

  gr_low_mannose_reasons = table_low_mannose(normalized_data$median,
                                             all_info),

  gr_diff_anova = compare_anova(normalized_data$median,
                                    all_info_nodiabetic),

  gr_ratio_anova = compare_anova(feature_ratios,
                                 all_info_nodiabetic,
                                 p_cut = gr_ratio_cut),

  gr_ratio_anova_metabolite = add_metabolite_ratio(gr_ratio_anova$anova_mway, feature_metadata),


  ## rocs --------
  gr_classifications = calculate_classifications(normalized_data$median,
                                                 samples_gr_only_nout,
                                                 c(6, 1),
                                                 all_info,
                                                 gr_differences),

  gr_classification_plots = plot_classifications(gr_classifications,
                                                 feature_metadata),

  ## other statistical tests -------
  gr_diff_othertests = run_other_anovas(normalized_gr_only,
                                        all_info_nodiabetic,
                                        c("6", "1")),

  ## compare anova and t-tests -----
  gr_other_comparisons = compare_gr_other(gr_differences_metabolite,
                                          gr_diff_othertests),


  ## reactome annotations from pubchem -----
  reactome_pathways = get_reactome_pathways(),
  reactome_2_compound = get_reactome_pubchem("data/reactome_compounds/"),
  cid_synonyms = get_cid_synonyms("data/pubchem_compounds"),
  substance_chebi = jsonlite::fromJSON("data/pubchem_substance_chebi.json")$InformationList$Information |>
    tidyr::unnest(RegistryID) |>
    dplyr::transmute(sid = SID,
                     chebi = gsub("CHEBI:", "", RegistryID)),
  kegg_other = kegg_to_other(),
  sid_to_query = find_chebi_matches(kegg_other, substance_chebi),
  sid_to_cid = get_substance_compound("data/pubchem_substances"),
  kegg_synonym = get_all_kegg_compound(),
  feature_metadata2 = rematch_pubchem(feature_metadata,
                                      cid_synonyms,
                                      substance_chebi,
                                      kegg_other,
                                      sid_to_cid),
  reactome_annotations = create_reactome_annotations(reactome_2_compound,
                                                     reactome_pathways),

  reactome_cluster_enrichment = purrr::map(feature_clusters,
                                       enrich_clusters,
                                       reactome_annotations,
                                       feature_id = "pub_chem"),

  ## reports -----
  tar_quarto(qcqa, "doc/qcqa.qmd"),
  tar_quarto(differential_analysis, "doc/differential_analysis.qmd"),

  ## dependencies ----
  tar_target(renv_lockfile,
             "renv.lock",
             format = "file"),

  tar_target(dependencies,
             {
               renv_lockfile
               devtools::session_info(pkgs = "installed", to_file = "session-info.txt")
             }),

  tar_quarto(software_code_availability, "doc/software_code_availability.qmd"),

  ## output for others ----
  data_dictionary = create_data_dictionary(),

  tabular_output = openxlsx::write.xlsx(list(dictionary = data_dictionary,
                                           direct = gr_differences_metabolite,
                                           ratio = gr_ratio_differences_metabolite,
                                           ratio_anova = gr_ratio_anova_metabolite,
                                           ratio_ranked_list = gr_ratio_ranked_logfc,
                                           normalized_all = normalized_data$osmo_med,
                                           normalized_green_red = normalized_gr_only,
                                           sample_metadata = all_info),
                                      "doc/output_tables.xlsx",
                                      overwrite = TRUE),

  red_green_log2_output = create_csv(normalized_data$median,
                                   gr_differences_metabolite |>
                                     dplyr::filter(significant) |>
                                     dplyr::pull(feature_id),
                                   samples_gr_only,
                                   c(6, 1),
                                   all_info),

  matrix_red_green = generate_matrix_output(normalized_data$median,
                                            samples_gr_only_nout),
  red_green_info = all_info |>
    dplyr::filter(sample_id %in% samples_gr_only_nout) |>
    dplyr::select(sample_id, disease_cohort, cohort_group),

  tar_target(out_matrix,
             write.table(matrix_red_green, file = "data/red_green_matrix.csv",
                         sep = ",", col.names = TRUE, row.names = TRUE)),
  tar_target(out_info,
             write.table(red_green_info, file = "data/red_green_info.csv",
                         sep = ",", col.names = TRUE, row.names = FALSE)),

  tar_target(out_rainclouds,
             write_rainclouds(gr_differences_raincloud, directory = "raincloud_plots"))

)
