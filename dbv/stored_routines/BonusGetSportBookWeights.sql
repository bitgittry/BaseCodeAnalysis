-- -------------------------------------
-- BonusGetSportBookWeights.sql
-- -------------------------------------

DROP procedure IF EXISTS `BonusGetSportBookWeights`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetSportBookWeights`(bonusRuleID BIGINT)
BEGIN
	
  SELECT sp.sb_sport_id, sp.name, sp.ext_sport_id, sp.game_manufacturer_id, crit.eligibility_criterias_id 
  FROM gaming_bonus_rules_wgr_sb_eligibility_criterias AS crit
  JOIN gaming_bonus_rules_wgr_sb_profile_selections AS sel ON crit.eligibility_criterias_id = sel.eligibility_criterias_id
  LEFT JOIN gaming_sb_sports AS sp ON sel.sb_entity_id = sp.sb_sport_id
  WHERE crit.bonus_rule_id = bonusRuleID AND sel.sb_entity_type_id = 1
  GROUP BY sp.sb_sport_id, crit.eligibility_criterias_id;
  
  SELECT reg.sb_region_id, reg.name, reg.ext_region_id, reg.sb_sport_id, crit.eligibility_criterias_id
  FROM gaming_bonus_rules_wgr_sb_eligibility_criterias AS crit 
  JOIN gaming_bonus_rules_wgr_sb_profile_selections AS sel ON crit.eligibility_criterias_id = sel.eligibility_criterias_id
  LEFT JOIN gaming_sb_regions AS reg ON sel.sb_entity_id = reg.sb_region_id
  WHERE crit.bonus_rule_id = bonusRuleID AND sel.sb_entity_type_id = 2
  GROUP BY reg.sb_region_id, crit.eligibility_criterias_id;
  
  SELECT gr.sb_group_id, gr.name, gr.ext_group_id, gr.sb_region_id, crit.eligibility_criterias_id
  FROM gaming_bonus_rules_wgr_sb_eligibility_criterias AS crit
  JOIN gaming_bonus_rules_wgr_sb_profile_selections AS sel ON crit.eligibility_criterias_id = sel.eligibility_criterias_id
  LEFT JOIN gaming_sb_groups AS gr ON sel.sb_entity_id = gr.sb_group_id
  WHERE crit.bonus_rule_id = bonusRuleID AND sel.sb_entity_type_id = 3
  GROUP BY gr.sb_group_id, sel.eligibility_criterias_id;
 
  SELECT ev.sb_event_id, ev.name, ev.ext_event_id, ev.date_end, ev.sb_group_id, crit.eligibility_criterias_id
  FROM gaming_bonus_rules_wgr_sb_eligibility_criterias AS crit
  JOIN gaming_bonus_rules_wgr_sb_profile_selections AS sel ON crit.eligibility_criterias_id = sel.eligibility_criterias_id
  LEFT JOIN gaming_sb_events AS ev ON sel.sb_entity_id = ev.sb_event_id
  WHERE crit.bonus_rule_id = bonusRuleID AND sel.sb_entity_type_id = 4
  GROUP BY ev.sb_event_id, sel.eligibility_criterias_id;
  
  SELECT mar.sb_market_id, mar.name, mar.ext_market_id, mar.sb_event_id, crit.eligibility_criterias_id 
  FROM gaming_bonus_rules_wgr_sb_eligibility_criterias AS crit
  JOIN gaming_bonus_rules_wgr_sb_profile_selections AS sel ON crit.eligibility_criterias_id = sel.eligibility_criterias_id
  LEFT JOIN gaming_sb_markets AS mar ON sel.sb_entity_id = mar.sb_market_id
  WHERE crit.bonus_rule_id = bonusRuleID AND sel.sb_entity_type_id = 5
  GROUP BY mar.sb_market_id, crit.eligibility_criterias_id;

 	-- singles 
  SELECT crit.eligibility_criterias_id, weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order, weight.min_odd, weight.max_odd, 
		 NULL AS sb_multiple_type_id_from, NULL AS sb_multiple_type_id_to, weight.sb_multiple_type_id, weight.sb_weight_range_id, weight.weight
  FROM gaming_bonus_rules_wgr_sb_eligibility_criterias AS crit
  JOIN gaming_bonus_rules_wgr_sb_weights AS weight ON crit.eligibility_criterias_id = weight.eligibility_criterias_id 
  WHERE crit.bonus_rule_id = bonusRuleID AND weight.sb_weight_range_id IS NULL AND weight.min_odd > 0
  ORDER BY weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order;
  
    -- Accumulators 
  SELECT weight.eligibility_criterias_id, weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order, weight.min_odd, weight.max_odd, 
		 rng.sb_multiple_type_id_from, multTo.sb_multiple_type_id AS sb_multiple_type_id_to, weight.sb_multiple_type_id, weight.sb_weight_range_id, weight.weight
  FROM gaming_bonus_rules_wgr_sb_weights AS weight
  JOIN gaming_sb_weight_profiles_weights_ranges AS rng ON weight.sb_weight_range_id = rng.sb_weight_range_id
  JOIN gaming_sb_multiple_types AS multFrom ON rng.sb_multiple_type_id_from = multFrom.sb_multiple_type_id AND multFrom.is_system_bet = 0
  LEFT JOIN gaming_sb_multiple_types AS multTo ON rng.sb_multiple_type_id_to = multTo.sb_multiple_type_id AND multTo.is_system_bet = 0
  WHERE weight.bonus_rule_id = bonusRuleID AND weight.sb_weight_range_id IS NOT NULL AND weight.min_odd > 0
  ORDER BY weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order;
  
  -- Simple system
  SELECT weight.eligibility_criterias_id, weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order, weight.min_odd, weight.max_odd, 
		 rng.sb_multiple_type_id_from, multTo.sb_multiple_type_id AS sb_multiple_type_id_to, weight.sb_multiple_type_id, weight.sb_weight_range_id, weight.weight
  FROM gaming_bonus_rules_wgr_sb_weights AS weight
  JOIN gaming_sb_weight_profiles_weights_ranges AS rng ON weight.sb_weight_range_id = rng.sb_weight_range_id
  JOIN gaming_sb_multiple_types AS multFrom ON rng.sb_multiple_type_id_from = multFrom.sb_multiple_type_id AND multFrom.is_system_bet = 0
  LEFT JOIN gaming_sb_multiple_types AS multTo ON rng.sb_multiple_type_id_to = multTo.sb_multiple_type_id AND multTo.is_system_bet = 0
  WHERE weight.bonus_rule_id = bonusRuleID AND weight.sb_weight_range_id IS NOT NULL AND weight.min_odd = 0
  ORDER BY weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order;
  
  -- Full system
  SELECT weight.eligibility_criterias_id, weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order, weight.min_odd, weight.max_odd, 
		 NULL AS sb_multiple_type_id_from, NULL AS sb_multiple_type_id_to, weight.sb_multiple_type_id, weight.sb_weight_range_id, weight.weight
  FROM gaming_bonus_rules_wgr_sb_weights AS weight
  JOIN gaming_sb_multiple_types AS mult ON weight.sb_multiple_type_id= mult.sb_multiple_type_id AND mult.is_system_bet = 1
  WHERE weight.bonus_rule_id = bonusRuleID AND weight.sb_multiple_type_id IS NOT NULL
  ORDER BY weight.sb_entity_type_id, weight.sb_entity_id, weight.odd_order;
  
END$$

DELIMITER ;

