-- -------------------------------------
-- LoyaltyGetSportBookWeights.sql
-- -------------------------------------

DROP procedure IF EXISTS `LoyaltyGetSportBookWeights`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LoyaltyGetSportBookWeights`(gameManufacturerId BIGINT)
BEGIN
	
  SELECT sp.sb_sport_id, sp.name, sp.ext_sport_id, sp.game_manufacturer_id, crit.eligibility_criterias_id 
  FROM gaming_loyalty_points_wgr_sb_eligibility_criterias AS crit
  JOIN gaming_loyalty_points_sb_profiles AS prof ON crit.loyalty_points_sb_profile_id = prof.loyalty_points_sb_profile_id AND prof.game_manufacturer_id = gameManufacturerId
  JOIN gaming_loyalty_points_wgr_sb_profile_selections AS sel ON crit.eligibility_criterias_id = sel.eligibility_criterias_id
  LEFT JOIN gaming_sb_sports AS sp ON sel.sb_entity_id = sp.sb_sport_id
  WHERE sel.sb_entity_type_id = 1
  GROUP BY sp.sb_sport_id, crit.eligibility_criterias_id;
  
  SELECT reg.sb_region_id, reg.name, reg.ext_region_id, reg.sb_sport_id, crit.eligibility_criterias_id
  FROM gaming_loyalty_points_wgr_sb_eligibility_criterias AS crit 
  JOIN gaming_loyalty_points_sb_profiles AS prof ON crit.loyalty_points_sb_profile_id = prof.loyalty_points_sb_profile_id AND prof.game_manufacturer_id = gameManufacturerId
  JOIN gaming_loyalty_points_wgr_sb_profile_selections AS sel ON crit.eligibility_criterias_id = sel.eligibility_criterias_id
  LEFT JOIN gaming_sb_regions AS reg ON sel.sb_entity_id = reg.sb_region_id
  WHERE sel.sb_entity_type_id = 2
  GROUP BY reg.sb_region_id, crit.eligibility_criterias_id;
  
  SELECT gr.sb_group_id, gr.name, gr.ext_group_id, gr.sb_region_id, crit.eligibility_criterias_id
  FROM gaming_loyalty_points_wgr_sb_eligibility_criterias AS crit
  JOIN gaming_loyalty_points_sb_profiles AS prof ON crit.loyalty_points_sb_profile_id = prof.loyalty_points_sb_profile_id AND prof.game_manufacturer_id = gameManufacturerId
  JOIN gaming_loyalty_points_wgr_sb_profile_selections AS sel ON crit.eligibility_criterias_id = sel.eligibility_criterias_id
  LEFT JOIN gaming_sb_groups AS gr ON sel.sb_entity_id = gr.sb_group_id
  WHERE sel.sb_entity_type_id = 3
  GROUP BY gr.sb_group_id, sel.eligibility_criterias_id;
 
  SELECT ev.sb_event_id, ev.name, ev.ext_event_id, ev.date_end, ev.sb_group_id, crit.eligibility_criterias_id
  FROM gaming_loyalty_points_wgr_sb_eligibility_criterias AS crit
  JOIN gaming_loyalty_points_sb_profiles AS prof ON crit.loyalty_points_sb_profile_id = prof.loyalty_points_sb_profile_id AND prof.game_manufacturer_id = gameManufacturerId
  JOIN gaming_loyalty_points_wgr_sb_profile_selections AS sel ON crit.eligibility_criterias_id = sel.eligibility_criterias_id
  LEFT JOIN gaming_sb_events AS ev ON sel.sb_entity_id = ev.sb_event_id
  WHERE sel.sb_entity_type_id = 4
  GROUP BY ev.sb_event_id, sel.eligibility_criterias_id;
  
  SELECT mar.sb_market_id, mar.name, mar.ext_market_id, mar.sb_event_id, crit.eligibility_criterias_id 
  FROM gaming_loyalty_points_wgr_sb_eligibility_criterias AS crit
  JOIN gaming_loyalty_points_sb_profiles AS prof ON crit.loyalty_points_sb_profile_id = prof.loyalty_points_sb_profile_id AND prof.game_manufacturer_id = gameManufacturerId
  JOIN gaming_loyalty_points_wgr_sb_profile_selections AS sel ON crit.eligibility_criterias_id = sel.eligibility_criterias_id
  LEFT JOIN gaming_sb_markets AS mar ON sel.sb_entity_id = mar.sb_market_id
  WHERE sel.sb_entity_type_id = 5
  GROUP BY mar.sb_market_id, crit.eligibility_criterias_id;

 	-- singles 
  SELECT crit.eligibility_criterias_id, weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order, weight.min_odd, weight.max_odd, 
		 NULL AS sb_multiple_type_id_from, NULL AS sb_multiple_type_id_to, weight.sb_multiple_type_id, weight.sb_weight_range_id, weight.weight
  FROM gaming_loyalty_points_wgr_sb_eligibility_criterias AS crit
  JOIN gaming_loyalty_points_sb_profiles AS prof ON crit.loyalty_points_sb_profile_id = prof.loyalty_points_sb_profile_id AND prof.game_manufacturer_id = gameManufacturerId
  JOIN gaming_loyalty_points_wgr_sb_weights AS weight ON crit.eligibility_criterias_id = weight.eligibility_criterias_id 
  WHERE weight.sb_weight_range_id IS NULL AND weight.min_odd > 0
  ORDER BY weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order;
  
    -- Accumulators 
  SELECT weight.eligibility_criterias_id, weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order, weight.min_odd, weight.max_odd, 
		 rng.sb_multiple_type_id_from, multTo.sb_multiple_type_id AS sb_multiple_type_id_to, weight.sb_multiple_type_id, weight.sb_weight_range_id, weight.weight
  FROM gaming_loyalty_points_wgr_sb_weights AS weight
  JOIN gaming_loyalty_points_sb_profiles AS prof ON weight.loyalty_points_sb_profile_id = prof.loyalty_points_sb_profile_id AND prof.game_manufacturer_id = gameManufacturerId
  JOIN gaming_sb_weight_profiles_weights_ranges AS rng ON weight.sb_weight_range_id = rng.sb_weight_range_id
  JOIN gaming_sb_multiple_types AS multFrom ON rng.sb_multiple_type_id_from = multFrom.sb_multiple_type_id AND multFrom.is_system_bet = 0
  LEFT JOIN gaming_sb_multiple_types AS multTo ON rng.sb_multiple_type_id_to = multTo.sb_multiple_type_id AND multTo.is_system_bet = 0
  WHERE weight.sb_weight_range_id IS NOT NULL AND weight.min_odd > 0
  ORDER BY weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order;
  
  -- Simple system
  SELECT weight.eligibility_criterias_id, weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order, weight.min_odd, weight.max_odd, 
		 rng.sb_multiple_type_id_from, multTo.sb_multiple_type_id AS sb_multiple_type_id_to, weight.sb_multiple_type_id, weight.sb_weight_range_id, weight.weight
  FROM gaming_loyalty_points_wgr_sb_weights AS weight
  JOIN gaming_loyalty_points_sb_profiles AS prof ON weight.loyalty_points_sb_profile_id = prof.loyalty_points_sb_profile_id AND prof.game_manufacturer_id = gameManufacturerId
  JOIN gaming_sb_weight_profiles_weights_ranges AS rng ON weight.sb_weight_range_id = rng.sb_weight_range_id
  JOIN gaming_sb_multiple_types AS multFrom ON rng.sb_multiple_type_id_from = multFrom.sb_multiple_type_id AND multFrom.is_system_bet = 0
  LEFT JOIN gaming_sb_multiple_types AS multTo ON rng.sb_multiple_type_id_to = multTo.sb_multiple_type_id AND multTo.is_system_bet = 0
  WHERE weight.sb_weight_range_id IS NOT NULL AND weight.min_odd = 0
  ORDER BY weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order;
  
  -- Full system
  SELECT weight.eligibility_criterias_id, weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order, weight.min_odd, weight.max_odd, 
		 NULL AS sb_multiple_type_id_from, NULL AS sb_multiple_type_id_to, weight.sb_multiple_type_id, weight.sb_weight_range_id, weight.weight
  FROM gaming_loyalty_points_wgr_sb_weights AS weight
  JOIN gaming_loyalty_points_sb_profiles AS prof ON weight.loyalty_points_sb_profile_id = prof.loyalty_points_sb_profile_id AND prof.game_manufacturer_id = gameManufacturerId
  JOIN gaming_sb_multiple_types AS mult ON weight.sb_multiple_type_id= mult.sb_multiple_type_id AND mult.is_system_bet = 1
  WHERE weight.sb_multiple_type_id IS NOT NULL
  ORDER BY weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order;
  
  -- Check and update list of amounts/loyalty_points according to active currencies / vip levels
  INSERT INTO gaming_loyalty_points_sb (loyalty_points_sb_profile_id, vip_level_id, currency_id, amount, loyalty_points)
  SELECT prof.loyalty_points_sb_profile_id, vl.vip_level_id, oc.currency_id, 0, 0
  FROM gaming_loyalty_points_sb_profiles AS prof 
  JOIN gaming_operator_currency AS oc ON oc.is_active = 1
  JOIN gaming_vip_levels AS vl 
  LEFT JOIN gaming_loyalty_points_sb AS lp ON lp.vip_level_id = vl.vip_level_id AND lp.currency_id = oc.currency_id AND lp.loyalty_points_sb_profile_id = prof.loyalty_points_sb_profile_id 
  WHERE prof.game_manufacturer_id = gameManufacturerId AND (lp.currency_id IS NULL OR lp.vip_level_id IS NULL);
  
  -- Loyalty Points rules for selected game manufacturer
  SELECT lp.vip_level_id, lp.currency_id, lp.amount, lp.loyalty_points
  FROM gaming_loyalty_points_sb AS lp
  JOIN gaming_loyalty_points_sb_profiles AS prof ON lp.loyalty_points_sb_profile_id = prof.loyalty_points_sb_profile_id 
  JOIN gaming_operator_currency AS oc ON lp.currency_id = oc.currency_id AND oc.is_active = 1
  JOIN gaming_vip_levels AS vl ON lp.vip_level_id = vl.vip_level_id 
  WHERE prof.game_manufacturer_id = gameManufacturerId;

END$$

DELIMITER ;

