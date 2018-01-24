DROP procedure IF EXISTS `CommonWalletSportsGenericCalculateBonusRuleWeightTypeTwo`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSportsGenericCalculateBonusRuleWeightTypeTwo`(
  sessionID BIGINT, clientStatID BIGINT, sbBetID BIGINT, numSingles INT, numMultiples INT)
BEGIN

  -- Optimized for Paritioning 

  DECLARE partitioningMinusFromMaxForCalc INT DEFAULT 10000;
  DECLARE minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, 
	minSbBetMultipleSingleID, maxSbBetMultipleSingleID BIGINT DEFAULT NULL; 

  SELECT 
	gsbpf.max_sb_bet_single_id-partitioningMinusFromMaxForCalc, gsbpf.max_sb_bet_single_id, 
    gsbpf.max_sb_bet_multiple_id-partitioningMinusFromMaxForCalc, gsbpf.max_sb_bet_multiple_id,
    gsbpf.max_sb_bet_multiple_single_id-partitioningMinusFromMaxForCalc, gsbpf.max_sb_bet_multiple_single_id
  INTO 
    minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, minSbBetMultipleSingleID, maxSbBetMultipleSingleID
  FROM gaming_sb_bets FORCE INDEX (PRIMARY)
  LEFT JOIN gaming_sb_bets_partition_fields AS gsbpf ON gsbpf.sb_bet_id=gaming_sb_bets.sb_bet_id
  WHERE gaming_sb_bets.sb_bet_id=sbBetID;

  -- For all singles check which bonus rules (and by definition which bonus instances are applicable) 
  -- Check weight if null set to 1.0 
  
	IF (numSingles > 0) THEN
		INSERT INTO gaming_sb_bets_bonus_rules (sb_bet_id, bonus_rule_id, weight) 
		SELECT DISTINCT sbBetID, gbi.bonus_rule_id, /*MIN(*/ IFNULL(wght.weight, 1) /*)*/
		FROM (
			SELECT gbi.bonus_rule_id, gbr.restrict_platform_type, gbi.bonus_instance_id, gbr.min_odd
			FROM gaming_bonus_instances AS gbi FORCE INDEX (client_active_bonuses)
			STRAIGHT_JOIN gaming_bonus_rules AS gbr ON gbr.bonus_rule_id = gbi.bonus_rule_id
			WHERE gbi.client_stat_id = clientStatID AND gbi.is_active AND gbi.is_free_rounds_mode = 0
			-- ORDER BY gbi.bonus_instance_id DESC /* LIMIT 1 */
		) AS gbi
		STRAIGHT_JOIN gaming_sb_bet_singles AS sing FORCE INDEX (sb_bet_id) ON
			sing.sb_bet_id = sbBetID AND 
			-- parition filtering
			(sing.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID)
		STRAIGHT_JOIN gaming_sb_selections AS sel ON sing.sb_selection_id = sel.sb_selection_id
		STRAIGHT_JOIN gaming_bonus_rules_wgr_sb_eligibility_criterias AS crit ON gbi.bonus_rule_id = crit.bonus_rule_id
		STRAIGHT_JOIN gaming_bonus_rules_wgr_sb_profile_selections AS wsel1 
			ON crit.eligibility_criterias_id = wsel1.eligibility_criterias_id AND wsel1.sb_entity_type_id = 1 AND (wsel1.sb_entity_id IS NULL OR wsel1.sb_entity_id = sel.sb_sport_id)
		STRAIGHT_JOIN gaming_bonus_rules_wgr_sb_profile_selections AS wsel2
			ON wsel1.eligibility_criterias_id = wsel2.eligibility_criterias_id AND wsel2.sb_entity_type_id = 2 AND (wsel2.sb_entity_id IS NULL OR wsel2.sb_entity_id = sel.sb_region_id) 
		STRAIGHT_JOIN gaming_bonus_rules_wgr_sb_profile_selections AS wsel3
			ON wsel2.eligibility_criterias_id = wsel3.eligibility_criterias_id AND wsel3.sb_entity_type_id = 3 AND (wsel3.sb_entity_id IS NULL OR wsel3.sb_entity_id = sel.sb_group_id)
		STRAIGHT_JOIN gaming_bonus_rules_wgr_sb_profile_selections AS wsel4
			ON wsel3.eligibility_criterias_id = wsel4.eligibility_criterias_id AND wsel4.sb_entity_type_id = 4 AND (wsel4.sb_entity_id IS NULL OR wsel4.sb_entity_id = sel.sb_event_id) 
		STRAIGHT_JOIN gaming_bonus_rules_wgr_sb_profile_selections AS wsel5
			ON wsel4.eligibility_criterias_id = wsel5.eligibility_criterias_id AND wsel5.sb_entity_type_id = 5 AND (wsel5.sb_entity_id IS NULL OR wsel5.sb_entity_id = sel.sb_market_id)
		STRAIGHT_JOIN gaming_bonus_rules_wgr_sb_weights AS wght 
			ON wsel5.eligibility_criterias_id = wght.eligibility_criterias_id
			AND (sing.odd >= wght.min_odd AND (wght.max_odd IS NULL OR sing.odd < wght.max_odd)) 
			AND (gbi.min_odd IS NULL OR sing.odd >= gbi.min_odd)
		LEFT JOIN sessions_main AS sess ON sess.session_id = sessionID
		LEFT JOIN gaming_bonus_rules_platform_types AS platypes ON gbi.bonus_rule_id = platypes.bonus_rule_id AND sess.platform_type_id = platypes.platform_type_id
		WHERE 
            (gbi.restrict_platform_type = 0 OR platypes.platform_type_id IS NOT NULL)
		GROUP BY gbi.bonus_instance_id
		HAVING COUNT(DISTINCT sing.sb_bet_single_id) = numSingles
		ON DUPLICATE KEY UPDATE weight=LEAST(weight, VALUES(weight));
	END IF;

    -- For all multiples check which bonus rules (and by definition which bonus instances are applicable)
	IF (numMultiples > 0) THEN
		INSERT INTO gaming_sb_bets_bonus_rules (sb_bet_id, bonus_rule_id, multiple_confirm, weight) 
    SELECT DISTINCT sbBetID, mult_wght.bonus_rule_id, 1, /*MIN(*/ IFNULL(mult_wght.weight, 1) /*)*/
    FROM
    (
    	SELECT mul.sb_bet_multiple_id, gbi.bonus_rule_id, 
    		COUNT(DISTINCT mulsin.sb_bet_multiple_single_id) AS num_singles, 
    		wght.min_odd AS weight_min_odd, wght.max_odd AS weight_max_odd, wght.weight AS weight, gbi.min_odd AS bonus_rule_min_odd
    	FROM (
    		SELECT gbi.bonus_rule_id, gbr.restrict_platform_type, gbi.bonus_instance_id, gbr.min_odd
    		FROM gaming_bonus_instances AS gbi FORCE INDEX (client_active_bonuses)
    		STRAIGHT_JOIN gaming_bonus_rules AS gbr ON gbr.bonus_rule_id = gbi.bonus_rule_id
    		WHERE gbi.client_stat_id = clientStatID AND gbi.is_active AND gbi.is_free_rounds_mode = 0
    		-- ORDER BY gbi.bonus_instance_id DESC /* LIMIT 1 */
    	) AS gbi
  		STRAIGHT_JOIN gaming_sb_bet_multiples AS mul FORCE INDEX (sb_bet_id) ON
			mul.sb_bet_id = sbBetID AND
			-- parition filtering
			(mul.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID)
  		STRAIGHT_JOIN gaming_sb_bet_multiples_singles AS mulsin FORCE INDEX (sb_bet_multiple_id) ON 
			mul.sb_bet_multiple_id = mulsin.sb_bet_multiple_id AND
             -- parition filtering
			(mulsin.sb_bet_multiple_single_id BETWEEN minSbBetMultipleSingleID AND maxSbBetMultipleSingleID)
  		STRAIGHT_JOIN gaming_sb_selections AS sel ON mulsin.sb_selection_id = sel.sb_selection_id
  		STRAIGHT_JOIN gaming_bonus_rules_wgr_sb_eligibility_criterias AS crit ON gbi.bonus_rule_id = crit.bonus_rule_id
  		STRAIGHT_JOIN gaming_bonus_rules_wgr_sb_profile_selections AS wsel1 
          ON crit.eligibility_criterias_id = wsel1.eligibility_criterias_id AND wsel1.sb_entity_type_id = 1 AND (wsel1.sb_entity_id IS NULL OR wsel1.sb_entity_id = sel.sb_sport_id)
  		STRAIGHT_JOIN gaming_bonus_rules_wgr_sb_profile_selections AS wsel2
          ON wsel1.eligibility_criterias_id = wsel2.eligibility_criterias_id AND wsel2.sb_entity_type_id = 2 AND (wsel2.sb_entity_id IS NULL OR wsel2.sb_entity_id = sel.sb_region_id) 
  		STRAIGHT_JOIN gaming_bonus_rules_wgr_sb_profile_selections AS wsel3
          ON wsel2.eligibility_criterias_id = wsel3.eligibility_criterias_id AND wsel3.sb_entity_type_id = 3 AND (wsel3.sb_entity_id IS NULL OR wsel3.sb_entity_id = sel.sb_group_id)
  		STRAIGHT_JOIN gaming_bonus_rules_wgr_sb_profile_selections AS wsel4
          ON wsel3.eligibility_criterias_id = wsel4.eligibility_criterias_id AND wsel4.sb_entity_type_id = 4 AND (wsel4.sb_entity_id IS NULL OR wsel4.sb_entity_id = sel.sb_event_id) 
  		STRAIGHT_JOIN gaming_bonus_rules_wgr_sb_profile_selections AS wsel5
          ON wsel4.eligibility_criterias_id = wsel5.eligibility_criterias_id AND wsel5.sb_entity_type_id = 5 AND (wsel5.sb_entity_id IS NULL OR wsel5.sb_entity_id = sel.sb_market_id)
  		STRAIGHT_JOIN gaming_bonus_rules_wgr_sb_weights AS wght 
          ON wsel5.eligibility_criterias_id = wght.eligibility_criterias_id OR gbi.bonus_rule_id = wght.bonus_rule_id
      LEFT JOIN sessions_main AS sess ON sess.session_id = sessionID
      LEFT JOIN gaming_bonus_rules_platform_types AS platypes ON gbi.bonus_rule_id = platypes.bonus_rule_id AND sess.platform_type_id = platypes.platform_type_id
  		WHERE (wght.sb_multiple_type_id IS NULL OR wght.sb_multiple_type_id = mul.sb_multiple_type_id)
          AND (wght.sb_weight_range_id IS NULL OR SBWeightCheckRangeID(mul.sb_multiple_type_id, wght.sb_weight_range_id) IS NOT NULL)
          AND (gbi.restrict_platform_type = 0 OR platypes.platform_type_id IS NOT NULL)   
  		GROUP BY mul.sb_bet_multiple_id, gbi.bonus_rule_id, wght.min_odd
  	) AS mult_wght 
  	STRAIGHT_JOIN gaming_sb_bet_multiples AS mult FORCE INDEX (PRIMARY) ON 
		mult.sb_bet_multiple_id = mult_wght.sb_bet_multiple_id AND 
        -- parition filtering
		(mult.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID) AND
		-- other filtering
		mult.num_singles = mult_wght.num_singles AND
		(mult.odd >= mult_wght.weight_min_odd AND (mult_wght.weight_max_odd IS NULL OR mult.odd < mult_wght.weight_max_odd)) AND
		(mult_wght.bonus_rule_min_odd IS NULL OR mult.odd >= mult_wght.bonus_rule_min_odd)
  	GROUP BY mult_wght.bonus_rule_id
  	HAVING COUNT(DISTINCT mult.sb_bet_multiple_id) = numMultiples
		ON DUPLICATE KEY UPDATE multiple_confirm = 1, weight = LEAST(weight, VALUES(weight));
	END IF;
  
END$$

DELIMITER ;

