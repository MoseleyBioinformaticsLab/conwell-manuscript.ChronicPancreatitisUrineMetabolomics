create_ranked_ratio_logfc_table = function(gr_ratio_differences_metabolite)
{
  # tar_load(gr_ratio_differences_metabolite)
  gr_ratio_ranked_significant = gr_ratio_differences_metabolite |>
    dplyr::filter(significant) |>
    dplyr::mutate(LogFC = abs(LogFC))

  ratio_met1 = gr_ratio_ranked_significant |>
    dplyr::select(metabolite1, LogFC) |>
    dplyr::mutate(metabolite = metabolite1,
                  metabolite1 = NULL)
  ratio_met2 = gr_ratio_ranked_significant |>
    dplyr::select(metabolite2, LogFC) |>
    dplyr::mutate(metabolite = metabolite2,
                  metabolite2 = NULL)

  ratio_all_sum = dplyr::bind_rows(ratio_met1, ratio_met2) |>
    dplyr::group_by(metabolite) |>
    dplyr::summarise(LogFC_sum = sum(LogFC),
                     N_ratio = dplyr::n()) |>
    dplyr::arrange(dplyr::desc(LogFC_sum))
  ratio_all_sum
}

run_t_tests = function(feature_intensities,
                       samples,
                       comparisons,
                       sample_info,
                       p_cut)
{
  # feature_intensities = tar_read(normalized_data)$median
  # samples = tar_read(samples_gr_only_nout)
  # comparisons = c(6, 1)
  # sample_info = tar_read(all_info)
  # p_cut = 0.05
  force(p_cut)
  if (is.null(feature_intensities$sample_id)) {
    feature_intensities_long = feature_intensities |>
      tidyr::pivot_longer(-feature_id,
                          names_to = "sample_id",
                          values_to = "intensity") |>
      dplyr::mutate(log_intensity = log2(intensity))
    feature_intensities_long = dplyr::left_join(feature_intensities_long, sample_info[, c("sample_id", "cohort_c")],
                                                by = "sample_id")
  } else {
    feature_intensities_long = feature_intensities |>
      dplyr::mutate(log_intensity = log2(intensity))
  }

  just_compares = feature_intensities_long |>
    dplyr::filter(cohort_c %in% comparisons)
  just_compares = just_compares |>
    dplyr::filter(sample_id %in% samples)
  split_feature = split(just_compares, just_compares$feature_id)

  calculate_tstat = function(data_df)
  {
    # data_df = split_feature[[1]]
    y_values = data_df |>
      dplyr::filter(cohort_c %in% comparisons[2]) |>
      dplyr::pull(log_intensity)
    y_values = y_values[!(is.infinite(y_values) | is.nan(y_values))]
    x_values = data_df |>
      dplyr::filter(cohort_c %in% comparisons[1]) |>
      dplyr::pull(log_intensity)
    x_values = x_values[!(is.infinite(x_values) | is.nan(x_values))]
    t_res = t.test(x_values, y_values, alternative = "two.sided", var.equal = FALSE)

    tidy_res = broom::tidy(t_res)
    tidy_res$stderr = t_res$stderr
    tidy_res$feature_id = data_df$feature_id[1]
    tidy_res$n_x = length(x_values)
    tidy_res$n_y = length(y_values)
    n_names = length(tidy_res)
    tidy_res
  }

  t_res = purrr::map(split_feature, calculate_tstat) |>
    dplyr::bind_rows()
  named_compare = c("LogFC", janitor::make_clean_names(comparisons), paste0("n_", janitor::make_clean_names(comparisons)))
  rename_vec = c("estimate", "estimate1", "estimate2", "n_x", "n_y")
  names(rename_vec) = named_compare
  t_res = t_res |>
    dplyr::rename(tidyselect::all_of(rename_vec)) |>
    dplyr::mutate(p.adjust = p.adjust(p.value, method = "BH", n = nrow(t_res)),
                  significant = p.adjust <= p_cut)
  t_res
}

add_metabolite_id = function(diff_results,
                             feature_metadata)
{
  # diff_results = tar_read(gr_differences)
  # tar_load(feature_metadata)
  diff_results_id = dplyr::left_join(diff_results, feature_metadata[, c("feature_id", "bin_base_name", "pub_chem", "kegg")],
                                    by = "feature_id")
  diff_results_id = diff_results_id |>
    dplyr::mutate(metabolite = bin_base_name,
                  bin_base_name = NULL)
  diff_results_id
}

add_metabolite_ratio = function(ratio_results,
                                feature_metadata)
{
  # ratio_results = tar_read(gr_ratio_differences)
  # tar_load(feature_metadata)
  # ratio_results = tar_read(gr_ratio_anova)
  ratio_results = ratio_results |>
    tidyr::separate_wider_delim(cols = "feature_id", delim = ":",
                                names = c("feature1", "feature2"))
  gr_ratio_met1 = dplyr::left_join(ratio_results, feature_metadata[, c("feature_id", "bin_base_name")],
                                   by = c("feature1" = "feature_id"))
  gr_ratio_met1 = gr_ratio_met1 |>
    dplyr::mutate(metabolite1 = bin_base_name,
                  bin_base_name = NULL)
  gr_ratio_met2 = dplyr::left_join(gr_ratio_met1, feature_metadata[, c("feature_id", "bin_base_name")],
                                   by = c("feature2" = "feature_id"))
  gr_ratio_met2 = gr_ratio_met2 |>
    dplyr::mutate(metabolite2 = bin_base_name,
                  bin_base_name = NULL)
  gr_ratio_met2
}

create_raincloud_plots = function(gr_differences,
                             feature_intensities,
                             feature_metadata,
                             comparisons = c(6, 1),
                             sample_info,
                             colors,
                             use_samples)
{

  # tar_load(gr_differences)
  # feature_intensities = tar_read(normalized_data)$median
  # tar_load(feature_metadata)
  # comparisons = c("CP" = 6, "Control" = 1)
  # sample_info = tar_read(all_info)
  # p_cut = 0.05
  # colors = tar_read(pancreatitis_colors)$all_groups
  # use_samples = tar_read(samples_gr_only_nout)

  sample_info = sample_info |>
    dplyr::filter(sample_id %in% use_samples)
  gr_differences_sig = gr_differences |>
    dplyr::filter(significant) |>
    dplyr::arrange(p.value)
  use_features = gr_differences_sig$feature_id
  feature_intensities_sig = feature_intensities |>
    dplyr::filter(cohort_c %in% comparisons, feature_id %in% gr_differences_sig$feature_id,
                  sample_id %in% use_samples)
  feature_intensities_sig = dplyr::left_join(feature_intensities_sig, sample_info[, c("sample_id", "cohort_group", "gender", "diabetes_bl")],
                                             by = "sample_id")
  if (!is.null(feature_metadata)) {
    feature_intensities_sig = dplyr::left_join(feature_intensities_sig, feature_metadata[, c("feature_id", "feature_name", "feature_label")],
                                               by = "feature_id")

  } else {
    feature_intensities_sig = feature_intensities_sig |>
      dplyr::mutate(bin_base_name = feature_id)
  }

  comparisons_df = data.frame(cohort_desc = names(comparisons),
                              cohort_c = comparisons)
  feature_intensities_sig = dplyr::left_join(feature_intensities_sig, comparisons_df, by = "cohort_c")
  split_feature = split(feature_intensities_sig, feature_intensities_sig$feature_id)
  split_feature = split_feature[use_features]
  out_raincloud = purrr::map(split_feature, function(in_feature){
    # in_feature = split_feature[[1]]
    feature_plot = in_feature |>
      dplyr::mutate(log_int = log2(intensity),
                    cohort_c = as.factor(cohort_c)) |>
      ggplot(aes(x = cohort_desc, y = log_int, fill = cohort_c)) +
      geom_rain() +
      scale_colour_manual(values = colors) +
      scale_fill_manual(values = colors) +
      theme(legend.position = "none", axis.title = element_text(size = 12)) +
      labs(subtitle = in_feature$feature_name,
           x = "Group", y = "Log2(Abundance)")
    feature_plot
  })
  out_raincloud
}

compare_direct_ratio = function(gr_differences_metabolite,
                                gr_ratio_differences_metabolite)
{
  # tar_load(gr_differences_metabolite)
  # tar_load(gr_ratio_differences_metabolite)
  # p_cut = 0.05
  gr_diff_sig = gr_differences_metabolite |>
    dplyr::filter(significant)
  gr_ratio_sig = gr_ratio_differences_metabolite |>
    dplyr::filter(significant)
  diff_metabolite = unique(gr_diff_sig$metabolite)
  ratio_metabolites = gr_ratio_sig |>
    dplyr::select(metabolite1, metabolite2)
  new_ratio = ratio_metabolites |>
    dplyr::filter(!((metabolite1 %in% diff_metabolite) | (metabolite2 %in% diff_metabolite)))
  new_ratio
}

table_low_mannose = function(feature_intensities,
                             all_info)
{
  # feature_intensities = tar_read(normalized_data)$median
  # tar_load(all_info)
  feature_intensities = feature_intensities |>
    dplyr::mutate(log_int = log2(intensity))
  low_mannose = feature_intensities |>
    dplyr::filter(feature_id %in% "mannose",
                  cohort_c %in% c(1, 6),
                  log_int <= -4)
  c16 = all_info |>
    dplyr::filter(cohort_c %in% c(1, 6))
  c16 = c16 |>
    dplyr::mutate(mannose = dplyr::case_when(
      sample_id %in% low_mannose$sample_id ~ "low",
      TRUE ~ "high"
    ))
  c16_tables = purrr::map(colnames(c16), function(in_name){
    if (inherits(c16[[in_name]], "character")) {
      table(c16[, c("mannose", in_name)])
    }
  })
  c16_tables
}


compare_anova = function(feature_values,
                         all_info,
                         use_cohorts = c("6", "1"),
                         p_cut = 0.05)
{
  # feature_values = tar_read(normalized_data)$median
  # all_info = tar_read(all_info_nodiabetic)
  # use_cohorts = c("6", "1")
  # p_cut = 0.05
  force(p_cut)
  if (is.null(feature_values$sample_id)) {
    feature_values_long = feature_values |>
      tidyr::pivot_longer(-feature_id,
                          names_to = "sample_id",
                          values_to = "intensity") |>
      dplyr::mutate(log_intensity = log2(intensity))
    feature_values_long = dplyr::inner_join(feature_values_long, all_info[, c("sample_id", "cohort_c")],
                                                by = "sample_id")
  } else {
    feature_values_long = feature_values |>
      dplyr::mutate(log_intensity = log2(intensity))
  }

  feature_info = dplyr::inner_join(feature_values_long, all_info[, c("sample_id", "diabetes_bl", "gender")],
                                  by = "sample_id")
  feature_info = feature_info |>
    dplyr::filter(cohort_c %in% use_cohorts, intensity > 0) |>
    dplyr::mutate(cohort_c = factor(cohort_c),
                  log_intensity = log2(intensity))

  split_feature = split(feature_info, feature_info$feature_id)

  n_test = length(unique(feature_info$feature_id))

  anova_cohort = purrr::map(split_feature, function(in_feature){
    out_aov = oneway.test(log_intensity ~ cohort_c, data = in_feature, var.equal = FALSE)
    out_df = suppressMessages(broom::tidy(out_aov))
    out_df$feature_id = in_feature$feature_id[1]
    out_df
  }) |>
    dplyr::bind_rows() |>
    dplyr::mutate(p.adjust = p.adjust(p.value, method = "BH", n = n_test))

  anova_features = purrr::map(split_feature, function(in_feature){
    # in_feature = split_feature[[1]]
    out_aov = aov(log_intensity ~ cohort_c + gender + diabetes_bl + cohort_c:gender + cohort_c:diabetes_bl,
                  data = in_feature)
    out_df = broom::tidy(out_aov)
    out_df$feature_id = in_feature$feature_id[1]
    out_df
  }) |>
    dplyr::bind_rows() |>
    dplyr::filter(!(term %in% "Residuals")) |>
    dplyr::group_by(term) |>
    dplyr::mutate(p.adjust = p.adjust(p.value, method = "BH", n = n_test)) |>
    dplyr::ungroup()
  all_features = anova_features[, "feature_id"] |>
    dplyr::distinct()
  split_term = split(anova_features, anova_features$term)
  p_by_term = purrr::map(split_term, function(in_term){
    # in_term = split_term[[1]]
    rename_vals = "p.adjust"
    names(rename_vals) = in_term$term[1]
    out_data = in_term |>
      dplyr::select(feature_id, p.adjust)
    out_data = dplyr::left_join(out_data, all_features, by = "feature_id")
    out_data = out_data |>
      dplyr::rename(tidyselect::all_of(rename_vals))
    out_data |>
      dplyr::select(-feature_id)
  }) |>
    dplyr::bind_cols()
  sig_by_term = purrr::map(p_by_term, ~ .x <= p_cut) |>
    dplyr::bind_cols()
  sig_by_term$feature_id = all_features$feature_id

  sig_cohort_gender = sig_by_term |>
    dplyr::filter(cohort_c, gender)
  sig_cohort_diabetes = sig_by_term |>
    dplyr::filter(cohort_c, diabetes_bl)
  sig_diabetes_gender = sig_by_term |>
    dplyr::filter(diabetes_bl, gender)

  sig_diabetes = sig_by_term |>
    dplyr::filter(diabetes_bl)
  sig_gender = sig_by_term |>
    dplyr::filter(gender)

  list(anova_mway = anova_features,
       anova_cohort_only = anova_cohort,
       sig_list = list(cohort_gender = sig_cohort_gender,
                       cohort_diabetes = sig_cohort_diabetes,
                       diabetes_gender = sig_diabetes_gender,
                       diabetes = sig_diabetes,
                       gender = sig_gender))
}

create_data_dictionary = function()
{
  out_dictionary = tibble::tribble(
    ~table, ~header, ~meaning,
    "direct", "LogFC", "Log-Fold-Change",
    "direct", "x6", "Mean log abundance in cohort 6",
    "direct", "x1", "Mean log abundance in cohort 1",
    "direct", "statistic", "The difference between x6 and x1",
    "direct", "p.value", "The p-value returned from the t-test",
    "direct", "parameter", "T-statistic",
    "direct", "conf.low", "95% confidence lower limit of the difference in x6 - x1",
    "direct", "conf.high", "95% confidence higher limit of the difference in x6 - x1",
    "direct", "method", "The test that was run",
    "direct", "alternative", "The alternative hypothesis",
    "direct", "feature_id", "The feature ID that works as a row name in R",
    "direct", "p.adjust", "adjusted p-value",
    "direct", "significant", "is the metabolite significant (p.adust <= 0.05)",
    "direct", "pub_chem", "PubChem ID",
    "direct", "kegg", "KEGG metabolite ID",
    "direct", "metabolite", "full metabolite name",
    "ratio", "LogFC", "Log-Fold-Change",
    "ratio", "x6", "Mean log-ratio in cohort 6",
    "ratio", "x1", "Mean log-ratio in cohort 1",
    "ratio", "statistic", "The difference between x6 and x1",
    "ratio", "p.value", "The p-value returned from the t-test",
    "ratio", "parameter", "T-statistic",
    "ratio", "conf.low", "95% confidence lower limit of the difference in x6 - x1",
    "ratio", "conf.high", "95% confidence higher limit of the difference in x6 - x1",
    "ratio", "method", "The test that was run",
    "ratio", "alternative", "The alternative hypothesis",
    "ratio", "feature_id", "The feature ID that works as a row name in R",
    "ratio", "p.adjust", "adjusted p-value",
    "ratio", "significant", "is the metabolite ratio significant (p.adust <= 0.05)",
    "ratio", "metabolite1", "the metabolite in the numerator of the ratio",
    "ratio", "metabolite2", "the metabolite in the denominator of the ratio"

  )
  out_dictionary
}


# transform_intensities_wide = function(long_data)
# {
#   long_data = tar_read(normalized_data)$osmo_med
#   wide_data = long_data |>
#
#     tidyr::pivot_wider()
# }

run_ici_features = function(use_intensity,
                            sample_ids = NULL)
{
  if (!is.null(sample_ids)) {
    use_intensity = use_intensity |>
      dplyr::filter(sample_id %in% sample_ids)
  }
  # use_intensity = tar_read(normalized_data)[["osmo_med"]]
  wide_intensity = use_intensity |>
    dplyr::select(sample_id, feature_id, intensity) |>
    dplyr::filter(!grepl("^pool", sample_id)) |>
    tidyr::pivot_wider(id_cols = "feature_id",
                       names_from = "sample_id",
                       values_from = "intensity")
  wide_intensity_matrix = wide_intensity |>
    dplyr::select(-feature_id) |>
    as.matrix()
  rownames(wide_intensity_matrix) = wide_intensity$feature_id
  ici_cor = ici_kendalltau(t(wide_intensity_matrix), perspective = "global", scale_max = TRUE)
  ici_cor
}

create_clusters = function(cut_height,
                           in_correlation,
                           feature_info)
{
  # use_height = 1.15
  # in_correlation = tar_read(ici_cor_features)
  # feature_info = tar_read(feature_metadata)
  ff_cor = in_correlation$cor
  ff_cor_arrange = similarity_reorder(ff_cor, transform = "sub_1")

  clusters = cutree(as.hclust(ff_cor_arrange$dendrogram), h = cut_height)
  cluster_df = tibble::tibble(feature_id = names(clusters), cluster = clusters,
                              cut_height = cut_height)
  cluster_df = dplyr::left_join(cluster_df, feature_info, by = "feature_id")
  cluster_df
}

create_feature_annotations = function(feature_metadata)
{
  NULL
}

enrich_clusters = function(in_cluster,
                           feature_annotations,
                           feature_id = "kegg")
{
  # in_cluster = tar_read(feature_clusters)[[2]]
  # feature_annotations = tar_read(kegg_annotations)
  # feature_id = "kegg"
  all_features = unique(unlist(feature_annotations@annotation_features))
  trim_cluster = in_cluster |>
    dplyr::filter(.data[[feature_id]] %in% all_features)

  split_cluster = split(trim_cluster[[feature_id]], trim_cluster$cluster)

  enrich_cluster = function(in_cluster,
                         cluster_id,
                         feature_annotations,
                         feature_universe)
  {
    # in_cluster = split_cluster[[1]]
    # cluster_id = names(split_cluster)[1]
    # feature_universe = all_features
    enrich_obj = hypergeometric_feature_enrichment(
      new("hypergeom_features", significant = in_cluster,
          universe = feature_universe,
          annotation = feature_annotations),
      p_adjust = "BH",
      min_features = 2
    )
    enrich_stats = tibble::as_tibble(enrich_obj@statistics@statistic_data)
    enrich_stats$id = enrich_obj@statistics@annotation_id
    enrich_stats$description = feature_annotations@description[enrich_stats$id]
    enrich_stats$cluster = cluster_id
    enrich_stats = enrich_stats |>
      dplyr::filter(counts >= 2) |>
      dplyr::arrange(padjust)

    enrich_stats
  }

  cluster_enrichments = purrr::imap(split_cluster,
                                    enrich_cluster,
                                    feature_annotations = feature_annotations,
                                    feature_universe = all_features)

  enrich_random = function(in_cluster,
                           cluster_id,
                           n_sample,
                           feature_sample,
                           feature_annotations,
                           feature_universe)
  {
    # in_cluster = split_cluster[[1]]
    # cluster_id = names(split_cluster)[1]
    # n_sample = 1000
    # feature_sample = trim_cluster$kegg
    # feature_universe = all_features
    if (length(in_cluster) > 2) {
      cluster_samples = purrr::map(seq(1, n_sample), function(in_rep){
        sample(feature_sample, length(in_cluster)) |> sort()
      })

      is_match = purrr::map_lgl(cluster_samples, \(.x){all(.x %in% in_cluster)})

      if (sum(is_match) > 0) {
        cluster_samples_more = purrr::map(seq(1, sum(is_match)), function(in_rep){
          sample(feature_sample, length(in_cluster)) |> sort()
        })
        cluster_samples = c(cluster_samples[!is_match], cluster_samples_more)
      }

      samples_enrich = furrr::future_imap(cluster_samples,
                                          enrich_cluster,
                                          feature_annotations = feature_annotations,
                                          feature_universe = feature_universe) |>
        dplyr::bind_rows()
      samples_enrich$cluster = cluster_id

      return(samples_enrich)
    } else {
      return(NULL)
    }

  }

  random_enrichments = purrr::imap(split_cluster,
                                   enrich_random,
                                   n_sample = 1000,
                                   feature_sample = trim_cluster[[feature_id]],
                                   feature_annotations = feature_annotations,
                                   feature_universe = all_features)

  null_enrichments = purrr::map_lgl(random_enrichments, is.null)
  zero_enrichments = purrr::map_lgl(cluster_enrichments, \(.x){nrow(.x) == 0})
  keep_enrichments = !(null_enrichments | zero_enrichments)
  random_enrichments = random_enrichments[keep_enrichments]
  compare_enrichments = cluster_enrichments[keep_enrichments]

  compare_random_enrichments = purrr::map(names(compare_enrichments), function(cluster_id){
    # cluster_id = "1"
    hyper_enrich = compare_enrichments[[cluster_id]]
    sample_enrich = random_enrichments[[cluster_id]]

    p_hyper_sample = purrr::map_dbl(seq(1, nrow(hyper_enrich)), function(in_row){
      use_map = hyper_enrich$id[in_row]
      use_p = hyper_enrich$p[in_row]
      use_sample = sample_enrich |>
        dplyr::filter(id %in% use_map) |>
        dplyr::pull(p)
      if (length(use_sample) == 0) {
        return(0)
      } else {
        return(sum(use_sample < use_p) / length(use_sample))
      }

    })
    hyper_enrich$p_random = p_hyper_sample
    hyper_enrich = hyper_enrich |>
      dplyr::arrange(p_random)
    hyper_enrich
  })
  list(clusters = in_cluster,
       enrichment = compare_random_enrichments)
}

generate_matrix_output = function(use_intensity,
                                  sample_ids = NULL)
{
  use_intensity = tar_read(normalized_data)$osmo_med
  sample_ids = tar_read(samples_gr_only_nout)
  if (!is.null(sample_ids)) {
    use_intensity = use_intensity |>
      dplyr::filter(sample_id %in% sample_ids)
  }
  wide_intensity = use_intensity |>
    dplyr::select(sample_id, feature_id, intensity) |>
    dplyr::filter(!grepl("^pool", sample_id)) |>
    tidyr::pivot_wider(id_cols = "feature_id",
                       names_from = "sample_id",
                       values_from = "intensity")
  wide_intensity_matrix = wide_intensity |>
    dplyr::select(-feature_id) |>
    as.matrix()
  rownames(wide_intensity_matrix) = wide_intensity$feature_id
  t_wide_intensity = t(wide_intensity_matrix)
  t_wide_intensity
}

run_other_anovas = function(feature_values,
                            all_info,
                            use_cohorts = c("6", "1"))
{
  # feature_values = tar_read(normalized_data)$median
  # all_info = tar_read(all_info_nodiabetic)
  # use_cohorts = c("6", "1")
  # p_cut = 0.05
  if (is.null(feature_values$sample_id)) {
    feature_values_long = feature_values |>
      tidyr::pivot_longer(-feature_id,
                          names_to = "sample_id",
                          values_to = "intensity") |>
      dplyr::mutate(log_intensity = log2(intensity))
    feature_values_long = dplyr::inner_join(feature_values_long, all_info,
                                           by = "sample_id")
  } else {
    feature_values_long = feature_values |>
      dplyr::mutate(log_intensity = log2(intensity))
    feature_values_long = dplyr::inner_join(feature_values_long,
                                           all_info |> dplyr::select(-cohort_c, -disease_sample),
                                           by = "sample_id")
  }

  feature_values_long = feature_values_long |>
    dplyr::filter(cohort_c %in% use_cohorts)

  # other things to test
  # - age
  # - smoking (set NA to "Never")
  # - race (remove NA??)
  # - bmi_current / bmi_current_grp
  # - gender (remove NA)
  # - etiology (remove -999)
  # - drinking (maybe combined drinkcat and current)
  # - dxa_result (N/A to Normal)
  # - diabetes_bl (where setting N/A to No, already done)
  # - gender


  test_columns = c("age", "smoking", "race", "bmi_current_grp",
                   "gender", "etiology", "drink_combo",
                   "dxa_result", "diabetes_bl", "gender")

  out_tests = purrr::map(test_columns, \(in_column){
    #in_column = "etiology"
    use_cols = c("feature_id", "log_intensity", in_column)
    tmp_data = feature_values_long |>
      dplyr::select(all_of(use_cols))
    tmp_data$test_column = tmp_data[[in_column]]

    if (is.character(tmp_data[["test_column"]])) {
      if (any(grepl("-999", tmp_data[["test_column"]]))) {
        tmp_data = tmp_data[!tmp_data[["test_column"]] %in% "-999", ]
      }
      if (any(grepl("N/A", tmp_data[["test_column"]]))) {
        tmp_data[grepl("N/A", tmp_data[["test_column"]]), "test_column"] = "Normal"
      }
    }
    out_stats = run_anova(tmp_data)
    out_stats$variable = in_column
    out_stats
  }) |>
    purrr::list_rbind()

  out_tests

}

run_anova = function(long_values)
{
  #long_values = tmp_data
  split_feature = split(long_values, long_values$feature_id)

  out_stats = purrr::map(split_feature, \(in_feature){
    #in_feature = split_feature[[1]]
    in_feature = in_feature |>
      dplyr::filter((!is.infinite(log_intensity)), (!is.nan(log_intensity)))

    aov_res = broom::tidy(aov(log_intensity ~ test_column, data = in_feature))[1, ]
    aov_res$feature_id = in_feature$feature_id[1]
    aov_res
  }) |>
    purrr::list_rbind()
  out_stats$term = NULL
  out_stats$p.adjust = p.adjust(out_stats$p.value, method = "BH")
  out_stats
}


compare_gr_other = function(gr_differences_metabolite,
                            gr_diff_othertests)
{
  # tar_load(gr_differences_metabolite)
  # tar_load(gr_diff_othertests)
  gr_diff_othertests_sig = gr_diff_othertests |>
    dplyr::filter(p.adjust <= 0.05)
  keep_vars = unique(gr_diff_othertests_sig$variable)
  gr_diff_othertests = gr_diff_othertests |>
    dplyr::filter(variable %in% keep_vars)
  gr_sig = gr_differences_metabolite |>
    dplyr::filter(significant)

  gr_other_split = split(gr_diff_othertests_sig$feature_id,
                         gr_diff_othertests_sig$variable)

  gr_split_list = c(gr_other_split,
                    list(stage = gr_sig$feature_id))

  gr_split_matrix = list_to_matrix(gr_split_list)
  has_2_more = rowSums(gr_split_matrix) > 1

  gr_split_2 = gr_split_matrix[has_2_more, ]


  rename_list = c(`Pancreatitis Stage` = "stage",
                  `Diabetes Status` = "diabetes_bl",
                  Age = "age",
                  `Smoking Status` = "smoking",
                  `Drinking Status` = "drink_combo",
                  BMI = "bmi_current_grp"
                  )
  gr_split_2 = gr_split_2[, rename_list]
  colnames(gr_split_2) = names(rename_list)

  comb_mat = make_comb_mat(gr_split_2)
  upset_fig = UpSet(comb_mat,
        set_order = names(rename_list),
        top_annotation = upset_top_annotation(comb_mat, add_numbers = TRUE, numbers_rot = 0,
                                              numbers_gp = gpar(fontsize = 10)),
        right_annotation = upset_right_annotation(comb_mat, add_numbers = TRUE,
                                                  numbers_gp = gpar(fontsize = 10)))

  groups = list(`Group 1` = c("Pancreatitis Stage", "Diabetes Status",
                         "Age", "Smoking Status"),
                `Group 2` = c("Pancreatitis Stage", "Diabetes Status",
                        "Age"),
                `Group 3` = c("Pancreatitis Stage", "Diabetes Status", "Smoking Status"),
                `Group 4` = c("Diabetes Status", "Smoking Status", "BMI"),
                `Group 5` = c("Pancreatitis Stage", "Diabetes Status"),
                `Group 6` = c("Diabetes Status", "Age"),
                `Group 7` = c("Diabetes Status", "Smoking Status"),
                `Group 8` = c("Smoking Status", "Drinking Status"))

  is_in_group = purrr::imap(groups, function(in_group, group_id){
    group_code = paste0(as.numeric(colnames(gr_split_2) %in% in_group), collapse = "")
    data.frame(feature_id = extract_comb(comb_mat, group_code),
               group = group_id)
  }) |>
    purrr::list_rbind()

  multiple_df = dplyr::bind_rows(gr_differences_metabolite |>
                            dplyr::mutate(variable = "stage") |>
                            dplyr::select(feature_id, p.adjust, variable),
                          gr_diff_othertests |>
                            dplyr::select(feature_id, p.adjust, variable)
                          )
  multiple_df = dplyr::left_join(is_in_group, multiple_df, by = "feature_id")
  multiple_df = dplyr::left_join(multiple_df, gr_differences_metabolite |>
                            dplyr::select(feature_id, metabolite), by = "feature_id")

  multiple_wide = multiple_df |>
    dplyr::select(-feature_id) |>
    tidyr::pivot_wider(id_cols = c(metabolite, group), names_from = variable,
                       values_from = p.adjust)

  keep_cols = c(Metabolite = "metabolite", rename_list, group = "group")

  multiple_wide_group = multiple_wide[, keep_cols]
  names(multiple_wide_group) = names(keep_cols)

  multiple_gt = multiple_wide_group |>
    dplyr::group_by(group) |>
    gt::gt() |>
    gt::fmt_number(n_sigfig = 2)

  for (icol in names(rename_list)) {
    which_col = which(names(multiple_wide_group) %in% icol)
    which_row = which(multiple_wide_group[[which_col]] <= 0.05)
    if (length(which_row) > 0) {
      multiple_gt = multiple_gt |>
        gt::tab_style(
          style = list(gt::cell_text(weight = "bold")),
          locations = gt::cells_body(columns = which_col,
                                     rows = which_row))
    }

  }

  single_df = dplyr::bind_rows(
    gr_diff_othertests |>
      dplyr::select(feature_id, variable, p.adjust),
    gr_differences_metabolite |>
      dplyr::mutate(variable = "stage") |>
      dplyr::select(feature_id, variable, p.adjust)
  )
  single_df = single_df |>
    dplyr::filter(feature_id %in% rownames(gr_split_matrix)) |>
    dplyr::filter(!(feature_id %in% multiple_df$feature_id)) |>
    dplyr::filter(variable %in% rename_list)

  single_df = dplyr::left_join(single_df, gr_differences_metabolite |>
                                 dplyr::select(feature_id, metabolite), by = "feature_id")

  split_single = split(single_df[, c("feature_id", "p.adjust", "variable")], single_df$variable)
  single_groups = purrr::map(split_single, \(in_feature){
    tmp_feature = in_feature |>
      dplyr::filter(p.adjust <= 0.05)
    tmp_feature
  }) |>
    purrr::list_rbind()
  single_groups$variable = factor(single_groups$variable, levels = rename_list)
  single_groups = single_groups |>
    dplyr::arrange(variable, p.adjust)


  single_wide = single_df |>
    tidyr::pivot_wider(id_cols = c(feature_id, metabolite), names_from = variable, values_from = p.adjust)
  single_wide = dplyr::left_join(single_groups[, c("feature_id")], single_wide, by = "feature_id")
  single_wide = single_wide |>
    dplyr::select(-feature_id)
  rename_single = c(Metabolite = "metabolite", rename_list)
  single_wide = single_wide[, rename_single]
  names(single_wide) = names(rename_single)

  single_gt = single_wide |>
    gt::gt() |>
    gt::fmt_number(n_sigfig = 2)

  for (icol in names(rename_list)) {
    which_col = which(names(single_wide) %in% icol)
    which_row = which(single_wide[[which_col]] <= 0.05)
    if (length(which_row) > 0) {
      single_gt = single_gt |>
        gt::tab_style(
          style = list(gt::cell_text(weight = "bold")),
          locations = gt::cells_body(columns = which_col,
                                     rows = which_row))
    }

  }
  list(upset = upset_fig,
       multiple_table = multiple_gt,
       single_table = single_gt)
}

write_rainclouds = function(gr_differences_raincloud, directory = "doc/raincloud_plots")
{
  tar_load(gr_differences_raincloud)
  directory = "doc/raincloud_plots"
  if (!fs::dir_exists(directory)) {
    fs::dir_create(directory)
  } else {
    prev_files = fs::dir_ls(directory)
    unlink(prev_files)
  }

  purrr::iwalk(gr_differences_raincloud, \(in_plot, feature_id){
    raincloud_file = paste0(feature_id, ".png")
    out_file = fs::path(directory, raincloud_file)
    ragg::agg_png(out_file, width = 8, height = 8, units = "in", res = 600)
    print(in_plot)
    invisible(dev.off())
  })
  return(NULL)
}
