get_reactome_pathways = function()
{
  library(ReactomeContentService4R)
  pathways = getSchemaClass(class = "Pathway", species = "human", all = TRUE)
  pathways
}

get_reactome_pubchem = function(json_loc)
{
  # json_loc = "data/reactome_compounds/"
  path_files = dir(json_loc, pattern = "json", full.names = TRUE)
  reactome_cids = purrr::map(path_files, \(x){
    # x = path_files[1]
    tmp = jsonlite::fromJSON(x)$InformationList$Information |>
      tidyr::unnest(CID) |>
      dplyr::transmute(reactome = gsub("Reactome:", "", PathwayAccession),
                       cid = CID)
  }) |>
    dplyr::bind_rows()
  reactome_cids
}

kegg_to_other = function()
{
  kegg_chebi = jsonlite::fromJSON(here::here("data/kegg_chebi.json")) |>
    purrr::imap(\(x, y){
      tibble::tibble(kegg = gsub("cpd:", "", y),
                     chebi = gsub("chebi:", "", x))
    }) |>
    dplyr::bind_rows()
  kegg_sid = jsonlite::fromJSON(here::here("data/kegg_pubchem.json")) |>
    purrr::imap(\(x, y){
      tibble::tibble(kegg = gsub("cpd:", "", y),
                     sid = gsub("pubchem:", "", x))
    }) |>
    dplyr::bind_rows()

  list(chebi = kegg_chebi,
       sid = kegg_sid)
}

get_cid_synonyms = function(json_loc)
{
  # json_loc = "data/pubchem_compounds"
  path_files = dir(json_loc, pattern = "JSON", full.names = TRUE)
  cid_synonyms = purrr::map(path_files, \(x){
    # x = path_files[1]
    tmp = jsonlite::fromJSON(x)$InformationList$Information

    first_synonym = purrr::map_chr(tmp$Synonym, \(.y){
      if (length(.y) > 0) {
        return(.y[1])
      } else {
        return(NA_character_)
      }})
    tmp$primary_synonym = first_synonym |> tolower()
    tmp |>
      dplyr::transmute(cid = CID,
                       synonym = Synonym,
                       first_synonym)
  }) |>
    dplyr::bind_rows()
  cid_synonyms
}

find_chebi_matches = function(kegg_other, substance_chebi)
{
  # tar_load(kegg_other)
  # tar_load(substance_chebi)
  kegg_chebi = kegg_other$chebi
  kegg_sid = kegg_other$sid

  intersect_kegg = substance_chebi |>
    dplyr::filter(chebi %in% kegg_chebi$chebi)

  sid_to_query = unique(c(kegg_sid$sid,
                          intersect_kegg$sid))
  sid_to_query
}

get_substance_compound = function(json_loc)
{
  # json_loc = "data/pubchem_substances"
  path_files = dir(json_loc, pattern = "json", full.names = TRUE)
  pubchem_substances = purrr::map(path_files, \(x){
    # x = path_files[1]
    tmp = jsonlite::fromJSON(x)$InformationList$Information
    tmp = tmp |>
      tidyr::unnest(CID) |>
      janitor::clean_names()

  }) |>
    dplyr::bind_rows()
  pubchem_substances
}

rematch_pubchem = function(feature_metadata,
                           cid_synonyms,
                           substance_chebi,
                           kegg_other,
                           sid_to_cid)
{
  tar_load(c(feature_metadata,
             cid_synonyms,
             substance_chebi,
             kegg_other,
             sid_to_cid))

  chebi_cid = dplyr::full_join(substance_chebi, sid_to_cid, by = "sid") |>
    dplyr::filter(!is.na(cid))
  kegg_cid = dplyr::full_join(kegg_other$sid |>
                                dplyr::mutate(sid = as.integer(sid)), sid_to_cid, by = "sid") |>
    dplyr::filter(!is.na(cid), !is.na(kegg)) |>
    dplyr::mutate(kegg_cid = paste0(kegg, ":", cid))
  kegg_chebi_cid = dplyr::full_join(kegg_other$chebi, chebi_cid, by = "chebi") |>
    dplyr::filter(!is.na(cid), !is.na(kegg)) |>
    dplyr::mutate(kegg_cid = paste0(kegg, ":", cid))

  kegg_features = dplyr::inner_join(feature_metadata, kegg_chebi_cid, by = "kegg")
  kegg_mismatch = kegg_features |>
    dplyr::filter(pub_chem != cid)
  kegg_wc = dplyr::left_join(kegg_mismatch[, c("bin_base_name", "pub_chem", "kegg")], cid_synonyms, by = c("pub_chem" = "cid"))
  chebi_pubchem = dplyr::left_join(kegg_mismatch[, c("bin_base_name", "cid", "kegg")], cid_synonyms, by = "cid")

  kegg_vs_pubchem = dplyr::left_join(kegg_wc, chebi_pubchem, by = "kegg", suffix = c(".kegg", ".chebi_pc"))

  kegg_vs_pubchem = kegg_vs_pubchem |>
    dplyr::mutate(kegg_dist = stringdist::stringdist(first_synonym.kegg, bin_base_name.kegg, method = "lv"),
                  chebi_dist = stringdist::stringdist(first_synonym.chebi_pc, bin_base_name.chebi_pc, method = "lv"))
  kegg_vs_pubchem = kegg_vs_pubchem |>
    dplyr::mutate(kegg_dist = dplyr::case_when(
      is.na(kegg_dist) ~ 100,
      TRUE ~ kegg_dist
    ),
    chebi_dist = dplyr::case_when(
      is.na(chebi_dist) ~ 100,
      TRUE ~ chebi_dist
    ))

  chosen_cid = purrr::map_int(seq(1, nrow(kegg_vs_pubchem)), \(irow){
    if (kegg_vs_pubchem$kegg_dist[irow] < kegg_vs_pubchem$chebi_dist[irow]) {
      return(kegg_vs_pubchem$pub_chem[irow])
    } else {
      return(kegg_vs_pubchem$cid[irow])
    }
  })

  discordant_tibble = tibble::tibble(kegg = kegg_vs_pubchem$kegg,
                                     pub_chem = chosen_cid)
  discordant_ids = dplyr::left_join(discordant_tibble, feature_metadata |>
                                      dplyr::select(-pub_chem), by = "kegg") |>
    dplyr::distinct()

  other_features = feature_metadata |>
    dplyr::filter(is.na(kegg) | !(kegg %in% discordant_ids$kegg))

  feature_metadata2 = dplyr::bind_rows(
    other_features,
    discordant_ids
  )
  feature_metadata2
}

create_reactome_annotations = function(reactome_2_compound,
                                       reactome_pathways)
{
  # tar_load(reactome_2_compound)
  # tar_load(reactome_pathways)
  split_maps = split(reactome_2_compound$cid, reactome_2_compound$reactome)
  split_maps = purrr::map(split_maps, unique)
  pathway_descriptions = reactome_pathways$displayName
  names(pathway_descriptions) = reactome_pathways$stId

  intersect_pathways = base::intersect(names(split_maps), names(pathway_descriptions))

  pathway_descriptions = pathway_descriptions[intersect_pathways]
  split_maps = split_maps[intersect_pathways]
  reactome_annotation = categoryCompare2::annotation(split_maps,
                                                 annotation_type = "reactome",
                                                 description = pathway_descriptions,
                                                 feature_type = "metabolite")
  reactome_annotation
}
