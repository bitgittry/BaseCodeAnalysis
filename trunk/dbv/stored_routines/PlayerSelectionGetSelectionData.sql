DROP procedure IF EXISTS `PlayerSelectionGetSelectionData`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerSelectionGetSelectionData`(playerSelectionID BIGINT)
root:BEGIN


  DECLARE playerSelectionIDCheck, playerFilterID BIGINT DEFAULT -1;
  DECLARE expiryTimeActive	INT(11) DEFAULT NULL;

  SELECT gaming_player_selections.player_selection_id, player_filter_id INTO playerSelectionIDCheck, playerFilterID
  FROM gaming_player_selections 
  LEFT JOIN gaming_player_filters ON gaming_player_selections.player_selection_id=gaming_player_filters.player_selection_id
  WHERE gaming_player_selections.player_selection_id=playerSelectionID;
  
  IF (playerSelectionIDCheck=-1) THEN
    LEAVE root;
  END IF;
  
  
  SELECT player_selection_id, name, description, is_selection_reusable, open_to_all, selected_players, group_selection, player_selection, player_filter, named_sql_query_selection, client_segment, dynamic_filter, dynamic_filter_on_selection, num_players, date_added, is_hidden, is_internal, non_resuable_parent_deleted, 
    exclude_bonus_seeker, exclude_bonus_dont_want, client_segments_num_match, dynamic_filters_num_match, force_run_dynamic_filter, cache_updated, full_cache_updated, player_minutes_to_expire
  FROM gaming_player_selections
  WHERE player_selection_id=playerSelectionID;
   

  
	SELECT player_minutes_to_expire INTO expiryTimeActive FROM gaming_player_selections WHERE gaming_player_selections.player_selection_id =playerSelectionID;
	IF (expiryTimeActive IS NOT NULL) THEN
		SELECT gpssp.client_stat_id, gpssp.include_flag, gpssp.exclude_flag,
		 IF(cache.expiry_date<NOW(),1,0) AS expired_flag
		  FROM gaming_player_selections_selected_players gpssp
			LEFT JOIN gaming_player_selections_player_cache cache 
			ON (gpssp.player_selection_id = cache.player_selection_id AND gpssp.client_stat_id = cache.client_stat_id)
		  WHERE gpssp.player_selection_id=playerSelectionID; 
	ELSE
		SELECT gpssp.client_stat_id, gpssp.include_flag, gpssp.exclude_flag, 0 as expired_flag
		FROM gaming_player_selections_selected_players gpssp
		WHERE gpssp.player_selection_id=playerSelectionID; 
	END IF;

  
  SELECT gaming_player_groups.player_group_id, name, description, num_players, date_created,
    player_groups.include_flag, player_groups.exclude_flag
  FROM gaming_player_selections_player_groups AS player_groups
  JOIN gaming_player_groups ON player_groups.player_selection_id=playerSelectionID AND player_groups.player_group_id=gaming_player_groups.player_group_id AND gaming_player_groups.is_hidden=0;
  
  
  SELECT gaming_player_selections.player_selection_id, name, description, is_selection_reusable, open_to_all, selected_players, group_selection, player_selection, player_filter, named_sql_query_selection, client_segment, dynamic_filter, dynamic_filter_on_selection, num_players, date_added, is_hidden, is_internal, non_resuable_parent_deleted, exclude_bonus_seeker, exclude_bonus_dont_want,
    child_selections.include_flag, child_selections.exclude_flag,gaming_player_selections.client_segments_num_match,gaming_player_selections.dynamic_filters_num_match,gaming_player_selections.force_run_dynamic_filter, gaming_player_selections.cache_updated, gaming_player_selections.full_cache_updated, gaming_player_selections.player_minutes_to_expire
  FROM gaming_player_selections_child_selections AS child_selections
  JOIN gaming_player_selections ON child_selections.player_selection_id=playerSelectionID AND child_selections.child_player_selection_id=gaming_player_selections.player_selection_id AND gaming_player_selections.is_hidden=0;
  
  
  SELECT gaming_client_segments.client_segment_id, gaming_client_segments.client_segment_group_id, gaming_client_segments.name, gaming_client_segments.display_name, gaming_client_segments.is_default,
    client_segments.include_flag, client_segments.exclude_flag
  FROM gaming_player_selections_client_segments AS client_segments
  JOIN gaming_client_segments ON client_segments.player_selection_id=playerSelectionID AND client_segments.client_segment_id=gaming_client_segments.client_segment_id AND gaming_client_segments.is_active=1;
  
  
  SELECT gpsdf.player_selection_dynamic_filter_id, gpdf.dynamic_filter_id, gpdf.`name`, gpdf.friendly_name, gpdf.description, gpdf.sql_data
  FROM `gaming_player_selections_dynamic_filters` gpsdf
  JOIN `gaming_players_dynamic_filters` gpdf ON (gpsdf.dynamic_filter_id = gpdf.dynamic_filter_id)
  WHERE gpsdf.player_selection_id = playerSelectionID AND gpsdf.marked_for_delete=0;
  
  SELECT gpsdf.player_selection_dynamic_filter_id, gpdfv.dynamic_filter_var_id, gpdfvt.name AS dynamic_filter_type, gpdfv.var_reference, gpdfv.default_value, gpsdfv.`value`
  FROM `gaming_player_selections_dynamic_filters` gpsdf
  JOIN `gaming_players_dynamic_filter_vars` gpdfv ON (gpsdf.dynamic_filter_id = gpdfv.dynamic_filter_id)
  JOIN gaming_players_dynamic_filter_var_types gpdfvt ON (gpdfv.dynamic_filter_var_type_id=gpdfvt.dynamic_filter_var_type_id)
  LEFT JOIN `gaming_player_selections_dynamic_filter_vars` gpsdfv ON (gpsdf.player_selection_dynamic_filter_id = gpsdfv.player_selection_dynamic_filter_id AND gpdfv.dynamic_filter_var_id = gpsdfv.dynamic_filter_var_id)
  WHERE gpsdf.player_selection_id = playerSelectionID AND gpsdf.marked_for_delete=0;  
  
  
  IF (playerFilterID IS NULL) THEN
    LEAVE root;
  END IF;
    
  SELECT player_filter_id,player_selection_id,gender,countries_include,countries_exclude,currencies_include,currencies_exclude,
    affiliates_include, affiliates_exclude, bonus_coupons_include, bonus_coupons_exclude, age_range_start, age_range_end, 0 AS num_players 
  FROM gaming_player_filters WHERE player_filter_id=playerFilterID; 
      


  SELECT gaming_countries.country_id, country_code, country_code_alpha3, name, is_active, gaming_countries.phone_prefix
  FROM gaming_player_filters_countries 
  JOIN gaming_countries ON gaming_player_filters_countries.player_filter_id=playerFilterID AND gaming_player_filters_countries.country_id=gaming_countries.country_id;
    
  SELECT gaming_currency.currency_id, currency_code, name, name_short, symbol
  FROM gaming_player_filters_currencies 
  JOIN gaming_currency ON gaming_player_filters_currencies.player_filter_id=playerFilterID AND gaming_player_filters_currencies.currency_id=gaming_currency.currency_id;
    
  SELECT gaming_affiliates.affiliate_id, affiliate_code, external_id, gaming_affiliates.affiliate_system_id, gaming_affiliate_systems.name AS affiliate_system_name, gaming_affiliate_systems.display_name AS affiliate_system,
    firstname, surname, address_1, address_2, postcode, city, country_code, language_code, email, mob, telephone, cost_per_acquisition, notes, sign_up_date, gaming_affiliates.is_active
  FROM gaming_player_filters_affiliates 
  JOIN gaming_affiliates ON gaming_player_filters_affiliates.player_filter_id=playerFilterID AND gaming_player_filters_affiliates.affiliate_id=gaming_affiliates.affiliate_id AND gaming_affiliates.is_hidden=0
  JOIN gaming_affiliate_systems ON gaming_affiliates.affiliate_system_id=gaming_affiliate_systems.affiliate_system_id
  JOIN gaming_affiliate_locations ON gaming_affiliates.affiliate_id=gaming_affiliate_locations.affiliate_id AND gaming_affiliate_locations.is_primary=1 
  JOIN gaming_languages ON gaming_affiliates.language_id=gaming_languages.language_id 
  JOIN gaming_countries ON gaming_affiliate_locations.country_id=gaming_countries.country_id; 
    
  SELECT gaming_bonus_coupons.bonus_coupon_id, display_name, coupon_code, validity_start_date, validity_end_date, require_player_selection, select_num_bonuses, notes, gaming_bonus_coupons.is_active, default_registration_coupon, gaming_bonus_coupons.is_hidden, gaming_bonus_coupons.player_selection_id
  FROM gaming_player_filters_bonus_coupons 
  JOIN gaming_bonus_coupons ON gaming_player_filters_bonus_coupons.player_filter_id=playerFilterID AND gaming_player_filters_bonus_coupons.bonus_coupon_id=gaming_bonus_coupons.bonus_coupon_id AND gaming_bonus_coupons.is_hidden=0;

END root$$

DELIMITER ;

