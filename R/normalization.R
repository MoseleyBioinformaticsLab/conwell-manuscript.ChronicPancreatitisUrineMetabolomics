add_pooled_osmolarity = function(in_intensity,
                                 sample_info,
                                 sample_osmolarity)
{
  # in_intensity = tar_read(feature_intensities)
  # sample_info = tar_read(sample_info)
  # sample_osmolarity = tar_read(sample_osmolarity)

  pool_samples = grep("^pool", colnames(in_intensity), value = TRUE)
  pool_info = tibble::tibble(sample_id = pool_samples,
                             cohort_c = 0,
                             disease_cohort = 0,
                             cohort_group = "Pooled")
  sample_info = dplyr::bind_rows(sample_info,
                                 pool_info)
  pool_osmolarity = tibble::tibble(sample_id = pool_samples,
                                   osmolarity_mmol_l = mean(sample_osmolarity$osmolarity_mmol_l))

  sample_osmolarity = dplyr::bind_rows(sample_osmolarity,
                                       pool_osmolarity)
  all_info = dplyr::left_join(sample_info, sample_osmolarity, by = "sample_id")
  all_info = all_info |>
    dplyr::mutate(disease_sample = paste0(cohort_c, ":", sample_id))

  if (!is.null(all_info$consent_dt)) {
    all_info$year = substr(all_info$consent_dt, 1, 4)
  }
  return(all_info)
}

no_normalization = function(feature_intensities,
                            all_info)
{
  out_intensity = feature_intensities |>
    tidyr::pivot_longer(cols = -feature_id,
                        names_to = "sample_id",
                        values_to = "intensity") |>
    dplyr::mutate(intensity_type = "raw")
  out_intensity = dplyr::left_join(out_intensity, all_info[, c("disease_sample", "sample_id", "cohort_c")], by = "sample_id")
  out_intensity
}

median_normalization = function(feature_intensities,
                                all_info)
{
  long_intensity = feature_intensities |>
    tidyr::pivot_longer(cols = -feature_id,
                        names_to = "sample_id",
                        values_to = "intensity")
  median_values = long_intensity |>
    dplyr::group_by(sample_id) |>
    dplyr::summarise(median = median(intensity))

  tmp_intensity = dplyr::left_join(long_intensity, median_values, by = c("sample_id"))
  out_intensity = tmp_intensity |>
    dplyr::mutate(intensity = intensity / median,
                  intensity_type = "median_normalized") |>
    dplyr::select(-median)
  out_intensity = dplyr::left_join(out_intensity, all_info[, c("disease_sample", "sample_id", "cohort_c")], by = "sample_id")
  out_intensity
}

osmolarity_normalization = function(feature_intensities,
                                all_info)
{
  long_intensity = feature_intensities |>
    tidyr::pivot_longer(cols = -feature_id,
                        names_to = "sample_id",
                        values_to = "intensity")

  tmp_intensity = dplyr::left_join(long_intensity, all_info[, c("osmolarity_mmol_l", "disease_sample", "sample_id", "cohort_c")], by = c("sample_id"))
  out_intensity = tmp_intensity |>
    dplyr::mutate(intensity = intensity / osmolarity_mmol_l,
                  intensity_type = "osmolarity_normalized") |>
    dplyr::select(-osmolarity_mmol_l)

  out_intensity
}

osmolarity_median_normalization = function(feature_intensities,
                                    all_info)
{
  long_intensity = feature_intensities |>
    tidyr::pivot_longer(cols = -feature_id,
                        names_to = "sample_id",
                        values_to = "intensity")

  tmp_intensity = dplyr::left_join(long_intensity, all_info[, c("osmolarity_mmol_l", "disease_sample", "sample_id", "cohort_c")], by = c("sample_id"))
  osmo_intensity = tmp_intensity |>
    dplyr::mutate(intensity = intensity / osmolarity_mmol_l) |>
    dplyr::select(-osmolarity_mmol_l)
  median_osmo = osmo_intensity |>
    dplyr::group_by(sample_id) |>
    dplyr::summarise(median = median(intensity))
  osmo_tmp = dplyr::left_join(osmo_intensity, median_osmo, by = "sample_id")
  out_intensity = osmo_tmp |>
    dplyr::mutate(intensity = intensity / median,
                  intensity_type = "osmolarity_median") |>
    dplyr::select(-median)
  out_intensity
}

check_outliers = function(feature_intensities)
{
  # feature_intensities = tar_read(normalized_data)$osmo_med
  log_intensities = feature_intensities |>
    dplyr::filter(intensity > 0) |>
    dplyr::mutate(log_intensity = log(intensity))
  sd_mean = log_intensities |>
    dplyr::summarise(mean = mean(log_intensity),
                     sd = sd(log_intensity),
                     lower = exp(mean - (3 * sd)),
                     upper = exp(mean + (3 * sd)))
  feature_intensities = feature_intensities |>
    dplyr::mutate(outlier = (intensity < sd_mean$lower) | (intensity > sd_mean$upper))
  feature_intensities
}

create_colors = function()
{
  all_groups = c("#1F78B4",
                 ggplot2::scale_color_brewer(palette = "OrRd")$palette(6))
  names(all_groups) = seq(0, 6)
  slimmed_groups = c("#1F78B4",
                     ggplot2::scale_color_brewer(palette = "OrRd")$palette(4))
  names(slimmed_groups) = seq(0, 4)
  return(list(all_groups = all_groups,
              slimmed_groups = slimmed_groups))
}

calculate_ratios = function(feature_intensities,
                            all_info)
{
  # feature_intensities = tar_read(feature_imputed)
  # tar_load(all_info)
  new_data = feature_intensities |>
    dplyr::select(-feature_id) |>
    as.matrix()

  ratio_indices = combn(seq_len(nrow(new_data)), 2)
  ratio_num = new_data[ratio_indices[1, ], ]
  ratio_den = new_data[ratio_indices[2, ], ]

  ratio_matrix = ratio_num / ratio_den
  ratio_df = tibble::as_tibble(ratio_matrix)
  ratio_df$feature_id = paste0(feature_intensities$feature_id[ratio_indices[1, ]], ":", feature_intensities$feature_id[ratio_indices[2, ]])

  ratios_long = ratio_df |>
    tidyr::pivot_longer(-feature_id,
                        names_to = "sample_id",
                        values_to = "intensity")
  ratios_long_attr = dplyr::left_join(ratios_long,
                                      all_info[, c("sample_id", "disease_sample", "cohort_c")],
                                      by = "sample_id")
  ratios_long_attr
}

impute_lowest = function(feature_intensities)
{
  # tar_load(feature_intensities)
  feature_matrix = feature_intensities |>
    dplyr::select(-feature_id) |>
    as.matrix()
  rownames(feature_matrix) = feature_intensities$feature_id
  rows_0 = rowSums(feature_matrix == 0) > 0

  other_not0 = feature_matrix[!rows_0, ]

  has_0 = feature_matrix[rows_0, ]
  for (irow in seq_len(nrow(has_0))) {
    tmp_row = has_0[irow, ]
    where_0 = which(tmp_row == 0)
    min_val = min(tmp_row[tmp_row > 0])
    has_0[irow, where_0] = min_val
  }

  new_data = rbind(other_not0,
                   has_0)
  new_df = tibble::as_tibble(new_data)
  new_df$feature_id = rownames(new_data)
  new_df
}

compare_medians = function(feature_intensities,
                           feature_intensities_nourea)
{
  # tar_load(feature_intensities)
  # tar_load(feature_intensities_nourea)
  all_medians = feature_intensities |>
    tidyr::pivot_longer(-feature_id, values_to = "intensity",
    names_to = "sample_id") |>
    dplyr::group_by(sample_id) |>
    dplyr::summarise(median = median(intensity))

    nourea_medians = feature_intensities_nourea |>
      tidyr::pivot_longer(-feature_id, values_to = "intensity",
      names_to = "sample_id") |>
      dplyr::group_by(sample_id) |>
      dplyr::summarise(median = median(intensity))

    compare_medians = dplyr::left_join(all_medians, nourea_medians, by = "sample_id", suffix = c(".all", ".nourea"))

    compare_fig = compare_medians |>
      ggplot(aes(x = log2(median.all / median.nourea))) +
      geom_histogram(bins = 100)
    compare_fig
}
