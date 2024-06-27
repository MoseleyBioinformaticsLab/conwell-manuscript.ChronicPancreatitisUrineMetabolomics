calculate_classifications = function(feature_intensities,
                                     samples,
                                     comparisons,
                                     sample_info,
                                     gr_differences)
{
  # feature_intensities = tar_read(normalized_data)$median
  # samples = tar_read(samples_gr_only_nout)
  # comparisons = c(6, 1)
  # sample_info = tar_read(all_info)
  # tar_load(feature_metadata)
  # tar_load(gr_differences)
  gr_significant = gr_differences |>
    dplyr::filter(significant)

  feature_intensities_more = feature_intensities |>
    dplyr::filter(feature_id %in% gr_significant$feature_id,
                  cohort_c %in% comparisons, sample_id %in% samples) |>
    dplyr::mutate(log_intensity = log2(intensity))
  feature_intensities_more = dplyr::left_join(feature_intensities_more, sample_info[, c("sample_id", "age", "gender")], by = "sample_id")

  use_variables = unique(gr_significant$feature_id)


  feature_intensities_more$cohort_c = factor(feature_intensities_more$cohort_c)

  var_models = purrr::map(use_variables, \(in_variable){
    # in_variable = use_variables[1]
    tmp_variable = feature_intensities_more |>
      dplyr::filter(feature_id %in% in_variable)
    out_model = glm(cohort_c ~ log_intensity + age + gender, family = binomial, data = tmp_variable)
    roc_model = suppressMessages(pROC::roc(tmp_variable$cohort_c, predict(out_model, type = "response")))
    roc_model$feature_id = in_variable
    roc_model
  })

  names(var_models) = use_variables
  var_models

}

plot_classifications = function(gr_classifications,
                                feature_metadata)
{
  # tar_load(gr_classifications)
  # tar_load(feature_metadata)
  out_plots = purrr::map(gr_classifications, \(in_classification){
    use_auc = gsub("Area under the curve: ", "", in_classification$auc) |> as.numeric() |>
      format(digits = 2)
    use_label = feature_metadata |>
      dplyr::filter(feature_id %in% in_classification$feature_id) |>
      dplyr::pull(feature_name)

    full_label = paste0(use_label, "  AUC: ", use_auc)

    tmp_plot = pROC::ggroc(in_classification, legacy.axes = TRUE) +
      labs(x = "1 - Specificity", y = "Sensitivity", subtitle = full_label) +
      geom_segment(aes(x = 0, y = 0, xend = 1, yend = 1), color = "gray",
                       linetype = "dashed") +
      coord_equal()
    tmp_plot
  })
  out_plots
}

old_from_rachel = function()
{
  sig_subset <- G_vs_R_sub2 %>%
    select(phenoxyacetic.acid,
           citrulline,
           xylulose,
           lactose,
           ribonic.acid,
           mannose,
           cohort_num,
           AGE,
           gender)

  sig_subset$cohort_num <- as.factor(sig_subset$cohort_num)
  table(sig_subset$cohort_num) #CP is second category, so good to go

  #GLM1 <- glm(cohort_num ~ phenoxyacetic.acid + citrulline + xylulose + lactose + ribonic.acid + mannose, family = binomial, data = sig_subset)

  model2 <- glm(cohort_num ~ mannose + AGE + gender, family = binomial, data = sig_subset)
  summary(model2)
  model3 <- glm(cohort_num ~ phenoxyacetic.acid + AGE + gender, family = binomial, data = sig_subset)
  summary(model3)
  model4 <- glm(cohort_num ~ citrulline + AGE + gender, family = binomial, data = sig_subset)
  summary(model4)
  model5 <- glm(cohort_num ~ ribonic.acid + AGE + gender, family = binomial, data = sig_subset)
  summary(model5)
  model6 <- glm(cohort_num ~ lactose + AGE + gender, family = binomial, data = sig_subset)
  summary(model6)
  model7 <- glm(cohort_num ~ xylulose + AGE + gender, family = binomial, data = sig_subset)
  summary(model7)


#summary(GLM1)$coef


#roc_data <- roc(sig_subset$cohort_num, predict(GLM1, type = "response"))
roc_mannose <- roc(sig_subset$cohort_num, predict(model2, type = "response"))
auc(roc_mannose)
roc_phen <- roc(sig_subset$cohort_num, predict(model3, type = "response"))
auc(roc_phen)
roc_cit <- roc(sig_subset$cohort_num, predict(model4, type = "response"))
auc(roc_cit)
roc_rib <- roc(sig_subset$cohort_num, predict(model5, type = "response"))
auc(roc_rib)
roc_lac <- roc(sig_subset$cohort_num, predict(model6, type = "response"))
auc(roc_lac)
roc_xyl <- roc(sig_subset$cohort_num, predict(model7, type = "response"))
auc(roc_xyl)

roc_data_list <- list(roc_mannose, roc_phen, roc_lac, roc_rib, roc_cit, roc_xyl)
library(gridExtra)

for (i in 1:6) {
  plot.roc(roc_data_list[[i]], main=paste("ROC Curve for", i), col="maroon")
}


par(mfrow = c(3,2))
plot(roc_mannose, main = "ROC Curve for Mannose", legacy.axes = TRUE, rev = FALSE, col = "black")
plot(roc_cit, main = "ROC Curve for Citrulline", legacy.axes = TRUE, rev = FALSE, col = "black")
plot.roc(roc_rib, main = "ROC Curve for Ribonic Acid", legacy.axes = TRUE, rev = FALSE, col = "black")
plot(roc_lac, main = "ROC Curve for Lactose", legacy.axes = TRUE, rev = FALSE, col = "black")
plot.roc(roc_xyl, main = "ROC Curve for Xylulose", legacy.axes = TRUE, rev = FALSE, col = "black")
plot.roc(roc_phen, main = "ROC Curve for Phenoxyacetic Acid", legacy.axes = TRUE, rev = FALSE, col = "black")

plot_man <- plot(roc_mannose, main = "ROC Curve for Mannose", legacy.axes = TRUE, rev = FALSE, col = "black")
plot_cit <- plot(roc_cit, main = "ROC Curve for Citrulline", legacy.axes = TRUE, rev = FALSE, col = "black")
plot_rib <- plot.roc(roc_rib, main = "ROC Curve for Ribonic Acid", legacy.axes = TRUE, rev = FALSE, col = "black")
plot_lac <- plot(roc_lac, main = "ROC Curve for Lactose", legacy.axes = TRUE, rev = FALSE, col = "black")
plot_xyl <- plot.roc(roc_xyl, main = "ROC Curve for Xylulose", legacy.axes = TRUE, rev = FALSE, col = "black")
plot_phen <- plot.roc(roc_phen, main = "ROC Curve for Phenoxyacetic Acid", legacy.axes = TRUE, rev = FALSE, col = "black")

grid.arrange(plot_man, plot_cit, plot_rib, plot_lac, plot_xyl, plot_phen, ncol = 3)

}
