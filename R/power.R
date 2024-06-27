power_from_raw = function(feature_intensities,
                          samples,
                          comparisons,
                          sample_info,
                          power = 0.8)
{
  # feature_intensities = tar_read(normalized_data)$median
  # samples = tar_read(samples_gr_only)
  # comparisons = c(6, 1)
  # sample_info = tar_read(all_info)
  # power = 0.8

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
  split_feature = split(just_compares, just_compares$feature_id)

}

power_from_ttest = function(ttest_res)
{
  # ttest_res = tar_read(gr_differences_metabolite)
  sig_res = ttest_res |>
    dplyr::filter(significant)
  difference = median(abs(sig_res$LogFC))
  sig_sd = median(sig_res$stderr)
  n_sample = power.t.test(delta = difference, sd = sig_sd,
                          sig.level = 0.001,
                          power = 0.8)
}

create_csv = function(feature_intensities,
                      sig_features,
                      samples,
                      comparisons,
                      sample_info)
{
  # feature_intensities = tar_read(normalized_data)$median
  # samples = tar_read(samples_gr_only)
  # comparisons = c(6, 1)
  # sample_info = tar_read(all_info)
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
      dplyr::mutate(log_intensity = log2(intensity),
                    significant = dplyr::case_when(
                      feature_id %in% sig_features ~ TRUE,
                      TRUE ~ FALSE
                    ))
  }

  just_compares = feature_intensities_long |>
    dplyr::filter(cohort_c %in% comparisons)

  comparisons_wide = just_compares |>
    dplyr::select(feature_id, sample_id, log_intensity, significant) |>
    tidyr::pivot_wider(names_from = sample_id,
                       values_from = log_intensity)
  write.table(comparisons_wide,
              file = "data/log2_green_red.csv",
              sep = ",",
              col.names = TRUE,
              row.names = FALSE)

  sample_info_compares = sample_info |>
    dplyr::filter(sample_id %in% just_compares$sample_id) |>
    dplyr::select(sample_id, cohort_c, cohort_group)
  write.table(sample_info_compares,
              file = "data/green_red_info.csv",
              sep = ",",
              col.names = TRUE,
              row.names = FALSE)
  list(values = comparisons_wide,
       info = sample_info_compares)
}
