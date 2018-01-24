-- -------------------------------------
-- SBWeightCalculateForLoyaltyPoints.sql
-- -------------------------------------

DROP FUNCTION IF EXISTS `SBWeightCalculateForLoyaltyPoints`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1`  FUNCTION `SBWeightCalculateForLoyaltyPoints`(sbBetID BIGINT)
	RETURNS DECIMAL(18,5)
BEGIN
  DECLARE finalWeight DECIMAL(18,5) DEFAULT 0;
  DECLARE singlesWeight, multiplesWeight DECIMAL(18,5);

  -- For all singles get weights of all eligible selections
  SELECT MIN(wght.weight) INTO finalWeight
  FROM gaming_sb_bet_singles AS sing FORCE INDEX (sb_bet_id)
  STRAIGHT_JOIN gaming_sb_selections AS sel ON sing.sb_selection_id = sel.sb_selection_id
  STRAIGHT_JOIN gaming_loyalty_points_sb_profiles AS prof ON sel.game_manufacturer_id = prof.game_manufacturer_id
  STRAIGHT_JOIN gaming_loyalty_points_wgr_sb_eligibility_criterias AS crit ON prof.loyalty_points_sb_profile_id = crit.loyalty_points_sb_profile_id
  STRAIGHT_JOIN gaming_loyalty_points_wgr_sb_profile_selections AS wsel1 
    ON crit.eligibility_criterias_id = wsel1.eligibility_criterias_id AND wsel1.sb_entity_type_id = 1 AND (wsel1.sb_entity_id IS NULL OR wsel1.sb_entity_id = sel.sb_sport_id)
  STRAIGHT_JOIN gaming_loyalty_points_wgr_sb_profile_selections AS wsel2
    ON wsel1.eligibility_criterias_id = wsel2.eligibility_criterias_id AND wsel2.sb_entity_type_id = 2 AND (wsel2.sb_entity_id IS NULL OR wsel2.sb_entity_id = sel.sb_region_id) 
  STRAIGHT_JOIN gaming_loyalty_points_wgr_sb_profile_selections AS wsel3
    ON wsel2.eligibility_criterias_id = wsel3.eligibility_criterias_id AND wsel3.sb_entity_type_id = 3 AND (wsel3.sb_entity_id IS NULL OR wsel3.sb_entity_id = sel.sb_group_id)
  STRAIGHT_JOIN gaming_loyalty_points_wgr_sb_profile_selections AS wsel4
    ON wsel3.eligibility_criterias_id = wsel4.eligibility_criterias_id AND wsel4.sb_entity_type_id = 4 AND (wsel4.sb_entity_id IS NULL OR wsel4.sb_entity_id = sel.sb_event_id) 
  STRAIGHT_JOIN gaming_loyalty_points_wgr_sb_profile_selections AS wsel5
    ON wsel4.eligibility_criterias_id = wsel5.eligibility_criterias_id AND wsel5.sb_entity_type_id = 5 AND (wsel5.sb_entity_id IS NULL OR wsel5.sb_entity_id = sel.sb_market_id)
  STRAIGHT_JOIN gaming_loyalty_points_wgr_sb_weights AS wght 
    ON wsel5.eligibility_criterias_id = wght.eligibility_criterias_id
    AND (sing.odd >= wght.min_odd AND (wght.max_odd IS NULL OR sing.odd < wght.max_odd)) 
    AND (prof.general_min_odd_per_selection IS NULL OR sing.odd >= prof.general_min_odd_per_selection)
  WHERE sing.sb_bet_id = sbBetID;

  -- For all multiples get weights of all eligible selections per accumulators, simple systems and full systems
  SELECT MIN(mult_wght.weight) INTO multiplesWeight
  FROM
  (
  	SELECT mul.sb_bet_multiple_id, COUNT(DISTINCT mulsin.sb_bet_multiple_single_id) AS num_singles, 
  	wght.min_odd AS weight_min_odd, wght.max_odd AS weight_max_odd, wght.weight AS weight, prof.general_min_odd_per_selection AS profile_min_odd
  	FROM gaming_sb_bet_multiples AS mul FORCE INDEX (sb_bet_id)
  	STRAIGHT_JOIN gaming_sb_bet_multiples_singles AS mulsin FORCE INDEX (sb_bet_multiple_id) ON mul.sb_bet_multiple_id = mulsin.sb_bet_multiple_id
  	STRAIGHT_JOIN gaming_sb_selections AS sel ON mulsin.sb_selection_id = sel.sb_selection_id
    STRAIGHT_JOIN gaming_loyalty_points_sb_profiles AS prof ON sel.game_manufacturer_id = prof.game_manufacturer_id
    STRAIGHT_JOIN gaming_loyalty_points_wgr_sb_eligibility_criterias AS crit ON prof.loyalty_points_sb_profile_id = crit.loyalty_points_sb_profile_id
  	STRAIGHT_JOIN gaming_loyalty_points_wgr_sb_profile_selections AS wsel1 
        ON crit.eligibility_criterias_id = wsel1.eligibility_criterias_id AND wsel1.sb_entity_type_id = 1 AND (wsel1.sb_entity_id IS NULL OR wsel1.sb_entity_id = sel.sb_sport_id)
  	STRAIGHT_JOIN gaming_loyalty_points_wgr_sb_profile_selections AS wsel2
        ON wsel1.eligibility_criterias_id = wsel2.eligibility_criterias_id AND wsel2.sb_entity_type_id = 2 AND (wsel2.sb_entity_id IS NULL OR wsel2.sb_entity_id = sel.sb_region_id) 
  	STRAIGHT_JOIN gaming_loyalty_points_wgr_sb_profile_selections AS wsel3
        ON wsel2.eligibility_criterias_id = wsel3.eligibility_criterias_id AND wsel3.sb_entity_type_id = 3 AND (wsel3.sb_entity_id IS NULL OR wsel3.sb_entity_id = sel.sb_group_id)
  	STRAIGHT_JOIN gaming_loyalty_points_wgr_sb_profile_selections AS wsel4
        ON wsel3.eligibility_criterias_id = wsel4.eligibility_criterias_id AND wsel4.sb_entity_type_id = 4 AND (wsel4.sb_entity_id IS NULL OR wsel4.sb_entity_id = sel.sb_event_id) 
  	STRAIGHT_JOIN gaming_loyalty_points_wgr_sb_profile_selections AS wsel5
        ON wsel4.eligibility_criterias_id = wsel5.eligibility_criterias_id AND wsel5.sb_entity_type_id = 5 AND (wsel5.sb_entity_id IS NULL OR wsel5.sb_entity_id = sel.sb_market_id)
  	STRAIGHT_JOIN gaming_loyalty_points_wgr_sb_weights AS wght 
        ON wsel5.eligibility_criterias_id = wght.eligibility_criterias_id OR prof.loyalty_points_sb_profile_id = wght.loyalty_points_sb_profile_id
  	WHERE mul.sb_bet_id = sbBetID 
        AND (wght.sb_multiple_type_id IS NULL OR wght.sb_multiple_type_id = mul.sb_multiple_type_id)
        AND (wght.sb_weight_range_id IS NULL OR SBWeightCheckRangeID(mul.sb_multiple_type_id, wght.sb_weight_range_id) IS NOT NULL)
  	GROUP BY mul.sb_bet_multiple_id, wght.min_odd
  ) AS mult_wght 
  STRAIGHT_JOIN gaming_sb_bet_multiples AS mult FORCE INDEX (PRIMARY) ON 
  mult.sb_bet_multiple_id = mult_wght.sb_bet_multiple_id AND 
  mult.num_singles = mult_wght.num_singles AND
  (mult.odd >= mult_wght.weight_min_odd AND (mult_wght.weight_max_odd IS NULL OR mult.odd < mult_wght.weight_max_odd)) AND
  (mult_wght.profile_min_odd IS NULL OR mult.odd >= mult_wght.profile_min_odd);

  SELECT IF(finalWeight IS NULL OR multiplesWeight IS NULL, COALESCE(finalWeight, multiplesWeight, 0), LEAST(finalWeight, multiplesWeight)) INTO finalWeight;
  
  RETURN finalWeight;
  
END$$

DELIMITER ;

