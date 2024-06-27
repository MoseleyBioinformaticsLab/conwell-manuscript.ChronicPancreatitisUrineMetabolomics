run_pca = function(use_intensity, all_info)
{
  # use_intensity = tar_read(normalized_data)$osmo_med
  # all_info = tar_read(all_info)
  wide_intensity = use_intensity |>
    dplyr::filter(sample_id %in% all_info$sample_id) |>
    dplyr::mutate(log_intensity = log(intensity)) |>
    dplyr::select(sample_id, feature_id, log_intensity) |>
    tidyr::pivot_wider(id_cols = "feature_id",
                       names_from = "sample_id",
                       values_from = "log_intensity")
  wide_matrix = wide_intensity |>
    dplyr::select(-feature_id) |>
    as.matrix()
  rownames(wide_matrix) = wide_intensity$feature_id
  order_wide = tibble::tibble(sample_id = colnames(wide_matrix))
  all_info = dplyr::left_join(order_wide, all_info, by = "sample_id")
  min_intensity = wide_matrix[!is.infinite(wide_matrix)] |> min()
  wide_matrix[is.infinite(wide_matrix)] = min_intensity
  wide_pca = prcomp(t(wide_matrix), center = TRUE, scale. = FALSE)
  out_pca = dplyr::bind_cols(wide_pca$x, all_info)
  pca_var = visqc_score_contributions(wide_pca$x)
  list(pca = out_pca,
       variance = pca_var,
       raw_pca = wide_pca)
}

run_ici = function(use_intensity)
{
  wide_intensity = use_intensity |>
    dplyr::select(sample_id, feature_id, intensity) |>
    tidyr::pivot_wider(id_cols = "feature_id",
                       names_from = "sample_id",
                       values_from = "intensity") |>
    dplyr::select(-feature_id) |>
    as.matrix()
  ici_cor = ici_kendalltau(wide_intensity, perspective = "global", scale_max = TRUE)
  ici_cor
}

check_sample_outliers = function(use_intensity, ici_cor, sample_info)
{
  # use_intensity = tar_read(normalized_gr_only)
  # ici_cor = tar_read(ici_cor_gr)
  # sample_info = tar_read(all_info)
  wide_intensity = use_intensity |>
    dplyr::select(sample_id, feature_id, intensity) |>
    tidyr::pivot_wider(id_cols = "feature_id",
                       names_from = "sample_id",
                       values_from = "intensity") |>
    dplyr::select(-feature_id) |>
    as.matrix()
  wide_intensity = log2(wide_intensity)
  use_cor = ici_cor$cor
  tmp_info = tibble::tibble(sample_id = rownames(use_cor))
  sample_info = dplyr::left_join(tmp_info, sample_info, by = "sample_id")
  med_cor = median_correlations(use_cor, sample_info$cohort_c)
  out_fraction = outlier_fraction(t(wide_intensity), sample_classes = sample_info$cohort_c)
  sample_outliers_cor = determine_outliers(median_correlations = med_cor)
  sample_outliers_frac = determine_outliers(outlier_fraction = out_fraction)
  sample_outliers_both = determine_outliers(median_correlations = med_cor, outlier_fraction = out_fraction)
  sample_outliers_both_alt = alt_outlier_determination(sample_outliers_both)
  sample_outliers_cor_alt = alt_outlier_determination(sample_outliers_cor)
  list(cor = sample_outliers_cor,
       frac = sample_outliers_frac,
       both = sample_outliers_both,
       alt_cor = sample_outliers_cor_alt,
       alt_both = sample_outliers_both_alt)
}

alt_outlier_determination = function(score_df)
{
  # score_df = sample_outliers_both
  split_class = split(score_df, score_df$sample_class)
  is_outlier = purrr::map(split_class, \(in_class){
    in_class$outlier = FALSE
    test_data = outliers::grubbs.test(in_class$score, type = 10)
    if (test_data$p.value <= 0.05) {
      which_max = which.max(in_class$score)
      in_class$outlier[which_max] = TRUE
    }
    in_class
  }) |>
    purrr::list_rbind()
  is_outlier
}

calculate_variance_with_signal = function(use_intensity,
                                          all_info)
{
  NULL
}

test_pcs = function(pca_decomp)
{
  # pca_decomp = tar_read(pca_runs_nopool)$osmo_med
  # pca_decomp = tar_read(pca_gr_only_nout)
  just_pca = pca_decomp$pca |>
    dplyr::select(tidyselect::starts_with("PC")) |>
    as.matrix()
  just_info = pca_decomp$pca[, (ncol(just_pca) + 1):ncol(pca_decomp$pca)]
  info_classes = purrr::map(just_info, class)
  test_classes = c("cohort_group", "disease_cohort", "race_pt", "year", "site", "gender", "diabetes_bl", "drink_combo", "etiology", "etoh_etiology")
  for (iclass in test_classes) {
    if ("character" %in% info_classes[[iclass]]) {
      just_info[[iclass]] = factor(just_info[[iclass]])
    }
  }

  score_test = visqc_test_pca_scores(just_pca, just_info[, test_classes])
  score_test
}

test_loadings = function(pca_decomp)
{
  # pca_decomp = tar_read(pca_runs_nopool)$osmo_med
  raw_pca = pca_decomp$raw_pca
  loadings_res = visqc_test_pca_loadings(raw_pca$rotation, c("PC1", "PC2", "PC3", "PC4"))
  loadings_res
}

find_intensity_cutoff = function(intensity_data)
{
  # intensity_data = tar_read(normalized_data)$osmo_med
  sd_rsd = intensity_data |>
    dplyr::group_by(feature_id, cohort_c) |>
    dplyr::summarise(mean = mean(intensity),
                     sd = sd(intensity),
                     rsd = sd / mean,
                     n = dplyr::n())

  sd_rsd_pool = sd_rsd |>
    dplyr::filter(cohort_c %in% 0)

  sd_rsd_other = sd_rsd |>
    dplyr::filter(!(cohort_c %in% 0))

  mean_breaks = seq(0, 100, 0.05)
  sd_breaks_pool = rep(NA, length(mean_breaks) - 1)
  sd_breaks_other = sd_breaks_pool
  for (ibreak in seq_along(sd_breaks_pool)) {
    use_range = mean_breaks[ibreak:(ibreak + 1)]
    sd_vals_pool = sd_rsd_pool |>
      dplyr::filter(dplyr::between(mean, use_range[1], use_range[2]))
    if (nrow(sd_vals_pool) > 0) {
      sd_breaks_pool[ibreak] = sd(sd_vals_pool$sd)
    }
    sd_vals_nopool = sd_rsd_other |>
      dplyr::filter(dplyr::between(mean, use_range[1], use_range[2]))
    if (nrow(sd_vals_nopool) > 0) {
      sd_breaks_other[ibreak] = sd(sd_vals_nopool$sd)
    }

  }
  mean_sd_sd = tibble::tibble(mean = mean_breaks[1:2000], sd_pool = sd_breaks_pool,
                              sd_nopool = sd_breaks_other)
  mean_sd_sd
}

collapse_drinking = function(other_info)
{
  # tar_load(other_info)
  other_info = other_info |>
    dplyr::mutate(drink_combo = dplyr::case_when(
      (drinking_status %in% c("Current", "Past")) & (drinkcat %in% "Do not know/Decline to Answer") ~ "Do not know/Decline to Answer",
      (drinking_status %in% "Current") & (drinkcat %in% c("Heavy drinkers", "Very heavy drinkers")) ~ "Current Heavy/Very heavy drinkers",
      (drinking_status %in% "Current") & (drinkcat %in% c("Moderate drinkers", "Light drinkers")) ~ "Current Light/Moderate drinkers",
      (drinking_status %in% "Never") & (drinkcat %in% "Abstainers") ~ "Abstainers",
      (drinking_status %in% "Past") & (drinkcat %in% c("Heavy drinkers", "Very heavy drinkers")) ~ "Past Heavy/Very heavy drinkders",
      (drinking_status %in% "Past") & (drinkcat %in% c("Moderate drinkers", "Light drinkers")) ~ "Past Light/Moderate drinkers"
    ))
  other_info
}

parse_mz = function(mz_field)
{
  #tar_load(feature_metadata)
  # mz_field = feature_metadata |>
  #   dplyr::filter(bb_id %in% 33458) |>
  #   dplyr::pull(mass_spec)

  split_space = strsplit(mz_field, " ")[[1]]
  split_colon = strsplit(split_space, ":", fixed = TRUE)

  peaks = purrr::map_chr(split_colon, \(in_split){in_split[1]})
  rel_int = purrr::map_chr(split_colon, \(in_split){in_split[2]})
  out_mz = data.frame(peak = as.numeric(peaks), intensity = as.numeric(rel_int))
  out_mz
}
