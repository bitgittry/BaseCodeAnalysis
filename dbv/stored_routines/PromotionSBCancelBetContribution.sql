-- -------------------------------------
-- PromotionSBCancelBetContribution.sql
-- -------------------------------------
DROP procedure IF EXISTS `PromotionSBCancelBetContribution`;

DELIMITER $$

CREATE DEFINER = 'bit8_admin'@'127.0.0.1'
PROCEDURE PromotionSBCancelBetContribution(sbBetId BIGINT)
root:BEGIN
	DECLARE isPrizeAwarded, contributeRealMoneyOnly TinyInt(1);
	DECLARE betAmountContributed DECIMAL(18,5);
		
	SELECT pps.has_awarded_bonus 
	INTO isPrizeAwarded
	FROM gaming_game_rounds_promotion_contributions AS contributions
	JOIN gaming_promotions_player_statuses AS pps ON contributions.promotion_player_status_id = pps.promotion_player_status_id
	JOIN gaming_game_rounds AS rounds ON rounds.game_round_id = contributions.game_round_id
	WHERE rounds.sb_bet_id = sbBetID AND rounds.license_type_id = 3 AND rounds.sb_extra_id IS NOT NULL;
	
	IF (isPrizeAwarded = 1) THEN
		LEAVE root;
	END IF;
		
    SELECT value_bool INTO contributeRealMoneyOnly FROM gaming_settings WHERE name='PROMOTION_CONTRIBUTION_REAL_MONEY_ONLY'; 

    SELECT
    LEAST( IFNULL(wager_restrictions.max_wager_contibution, 10000000000), 
           IF(gaming_promotions.is_single AND gaming_promotions_achievement_types.name='Bet' AND gppa.max_cap IS NOT NULL, gppa.max_cap, 1000000000000),
           contributions.bet,
           ( LEAST(IFNULL(wager_restrictions.max_wager_contibution_before_weight, 10000000000),
                   IF(contributeRealMoneyOnly OR gaming_promotions.wager_req_real_only, bet_real, bet_total)) * 
             IF(sb_weights.weight IS NULL OR sb_weights_multiple.weight IS NULL, 
                COALESCE(sb_weights.weight, sb_weights_multiple.weight), 
                LEAST(sb_weights.weight, sb_weights_multiple.weight)
               )
           )
         ) AS bet_amount
    INTO betAmountContributed
    FROM gaming_game_rounds_promotion_contributions AS contributions
    JOIN gaming_game_rounds AS rounds ON rounds.game_round_id = contributions.game_round_id
    JOIN gaming_promotions_player_statuses AS pps ON pps.promotion_player_status_id = contributions.promotion_player_status_id
    JOIN gaming_promotions ON gaming_promotions.promotion_id = pps.promotion_id
    JOIN gaming_promotions_achievement_types ON 
        gaming_promotions.promotion_achievement_type_id = gaming_promotions_achievement_types.promotion_achievement_type_id
    LEFT JOIN gaming_promotions_prize_amounts AS gppa ON
        gaming_promotions.promotion_id = gppa.promotion_id AND 
        pps.currency_id = gppa.currency_id
    LEFT JOIN gaming_promotion_wager_restrictions AS wager_restrictions ON
        wager_restrictions.promotion_id = gaming_promotions.promotion_id AND
        wager_restrictions.currency_id = pps.currency_id
    LEFT JOIN  
    (
        SELECT ggr.game_round_id, crit.promotion_id, sing.odd, AVG(wght.weight) AS weight
        FROM gaming_game_rounds_promotion_contributions AS contr
        JOIN gaming_promotions AS promo ON 
            promo.is_active=1 AND 
            contr.timestamp BETWEEN promo.achievement_start_date AND promo.achievement_end_date AND 
            NOT promo.promotion_achievement_type_id = 5
        JOIN gaming_game_rounds AS ggr ON 
            ggr.game_round_id = contr.game_round_id AND
            ggr.sb_extra_id IS NOT NULL AND 
            ggr.game_round_type_id = 4 AND          
            ggr.date_time_start BETWEEN promo.achievement_start_date AND promo.achievement_end_date 
        STRAIGHT_JOIN gaming_sb_bet_singles AS sing FORCE INDEX (sb_bet_id) ON 
            ggr.sb_bet_id=sing.sb_bet_id AND 
            ggr.sb_extra_id=sing.sb_selection_id
        STRAIGHT_JOIN gaming_sb_selections AS sel ON sing.sb_selection_id = sel.sb_selection_id
        STRAIGHT_JOIN gaming_promotions_wgr_sb_eligibility_criterias AS crit ON promo.promotion_id = crit.promotion_id
        STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel1 ON 
            crit.eligibility_criterias_id = wsel1.eligibility_criterias_id AND 
            wsel1.sb_entity_type_id = 1 AND 
            (wsel1.sb_entity_id IS NULL OR wsel1.sb_entity_id = sel.sb_sport_id)
        STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel2 ON 
            wsel1.eligibility_criterias_id = wsel2.eligibility_criterias_id AND 
            wsel2.sb_entity_type_id = 2 AND 
            (wsel2.sb_entity_id IS NULL OR wsel2.sb_entity_id = sel.sb_region_id) 
        STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel3 ON 
            wsel2.eligibility_criterias_id = wsel3.eligibility_criterias_id AND 
            wsel3.sb_entity_type_id = 3 AND 
            (wsel3.sb_entity_id IS NULL OR wsel3.sb_entity_id = sel.sb_group_id)
        STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel4 ON 
            wsel3.eligibility_criterias_id = wsel4.eligibility_criterias_id AND 
            wsel4.sb_entity_type_id = 4 AND 
            (wsel4.sb_entity_id IS NULL OR wsel4.sb_entity_id = sel.sb_event_id) 
        STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel5 ON 
            wsel4.eligibility_criterias_id = wsel5.eligibility_criterias_id AND 
            wsel5.sb_entity_type_id = 5 AND 
            (wsel5.sb_entity_id IS NULL OR wsel5.sb_entity_id = sel.sb_market_id)
        STRAIGHT_JOIN gaming_promotions_wgr_sb_weights AS wght ON 
            wsel5.eligibility_criterias_id = wght.eligibility_criterias_id
        WHERE sing.odd >= wght.min_odd AND (wght.max_odd IS NULL OR sing.odd < wght.max_odd)
        GROUP BY crit.promotion_id, ggr.game_round_id 
    ) AS sb_weights ON 
        rounds.game_round_id = sb_weights.game_round_id AND 
        gaming_promotions.promotion_id = sb_weights.promotion_id AND 
        pps.promotion_id = sb_weights.promotion_id AND
        (gaming_promotions.min_odd IS NULL OR sb_weights.odd >= gaming_promotions.min_odd)          
    LEFT JOIN
    (
        SELECT ggr.game_round_id, crit.promotion_id, mul.odd, AVG(wght.weight) AS weight
        FROM gaming_game_rounds_promotion_contributions AS contr
        JOIN gaming_promotions AS promo ON 
            promo.is_active=1 AND 
            contr.timestamp BETWEEN promo.achievement_start_date AND promo.achievement_end_date AND 
            NOT promo.promotion_achievement_type_id = 5
        JOIN gaming_game_rounds AS ggr ON 
            ggr.game_round_id = contr.game_round_id AND
            ggr.sb_extra_id IS NOT NULL AND 
            ggr.game_round_type_id = 4 AND           
            ggr.date_time_start BETWEEN promo.achievement_start_date AND promo.achievement_end_date 
        STRAIGHT_JOIN gaming_sb_bet_multiples AS mul FORCE INDEX (sb_bet_id) ON 
            ggr.sb_bet_id = mul.sb_bet_id AND 
            ggr.sb_extra_id = mul.sb_multiple_type_id
        STRAIGHT_JOIN gaming_sb_bet_multiples_singles AS mulsin FORCE INDEX (sb_bet_multiple_id) ON mul.sb_bet_multiple_id = mulsin.sb_bet_multiple_id
        STRAIGHT_JOIN gaming_sb_selections AS sel ON mulsin.sb_selection_id = sel.sb_selection_id
        STRAIGHT_JOIN gaming_promotions_wgr_sb_eligibility_criterias AS crit ON promo.promotion_id = crit.promotion_id
        STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel1 ON 
            crit.eligibility_criterias_id = wsel1.eligibility_criterias_id AND 
            wsel1.sb_entity_type_id = 1 AND 
            (wsel1.sb_entity_id IS NULL OR wsel1.sb_entity_id = sel.sb_sport_id)
        STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel2 ON 
            wsel1.eligibility_criterias_id = wsel2.eligibility_criterias_id AND 
            wsel2.sb_entity_type_id = 2 AND 
            (wsel2.sb_entity_id IS NULL OR wsel2.sb_entity_id = sel.sb_region_id) 
        STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel3 ON 
            wsel2.eligibility_criterias_id = wsel3.eligibility_criterias_id AND 
            wsel3.sb_entity_type_id = 3 AND 
            (wsel3.sb_entity_id IS NULL OR wsel3.sb_entity_id = sel.sb_group_id)
        STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel4 ON 
            wsel3.eligibility_criterias_id = wsel4.eligibility_criterias_id AND 
            wsel4.sb_entity_type_id = 4 AND 
            (wsel4.sb_entity_id IS NULL OR wsel4.sb_entity_id = sel.sb_event_id) 
        STRAIGHT_JOIN gaming_promotions_wgr_sb_profile_selections AS wsel5 ON 
            wsel4.eligibility_criterias_id = wsel5.eligibility_criterias_id AND 
            wsel5.sb_entity_type_id = 5 AND 
            (wsel5.sb_entity_id IS NULL OR wsel5.sb_entity_id = sel.sb_market_id)
        STRAIGHT_JOIN gaming_promotions_wgr_sb_weights AS wght ON 
            wsel5.eligibility_criterias_id = wght.eligibility_criterias_id OR 
            promo.promotion_id = wght.promotion_id
        WHERE mul.odd >= wght.min_odd AND 
            (wght.sb_multiple_type_id IS NULL OR wght.sb_multiple_type_id = mul.sb_multiple_type_id) AND 
            (wght.sb_weight_range_id IS NULL OR SBWeightCheckRangeID(mul.sb_multiple_type_id, wght.sb_weight_range_id) IS NOT NULL) AND                   
            (wght.max_odd IS NULL OR mul.odd < wght.max_odd)
        GROUP BY crit.promotion_id, ggr.game_round_id 
    ) AS sb_weights_multiple ON 
        rounds.game_round_id = sb_weights_multiple.game_round_id AND 
        gaming_promotions.promotion_id = sb_weights_multiple.promotion_id AND 
        pps.promotion_id = sb_weights_multiple.promotion_id AND
        (gaming_promotions.min_odd IS NULL OR sb_weights_multiple.odd >= gaming_promotions.min_odd)
    WHERE rounds.sb_bet_id = sbBetId and rounds.license_type_id = 3 AND rounds.sb_extra_id IS NOT NULL
    LIMIT 1;
	
	UPDATE gaming_promotions_player_statuses_daily AS ppsd
	JOIN gaming_game_rounds_promotion_contributions AS contributions ON 
			contributions.promotion_player_status_day_id = ppsd.promotion_player_status_day_id
	JOIN gaming_promotions ON ppsd.promotion_id = gaming_promotions.promotion_id
	JOIN gaming_game_rounds AS rounds ON rounds.game_round_id = contributions.game_round_id
	JOIN gaming_promotions_achievement_types AS achievement_types ON gaming_promotions.promotion_achievement_type_id=achievement_types.promotion_achievement_type_id
	JOIN gaming_promotions_player_statuses AS pps ON 
      contributions.promotion_player_status_id=pps.promotion_player_status_id
    LEFT JOIN gaming_promotions_achievement_amounts AS ach_amount ON
      gaming_promotions.promotion_id=ach_amount.promotion_id AND
      pps.currency_id=ach_amount.currency_id
	LEFT JOIN gaming_promotions_achievement_rounds AS ach_num_rounds ON
      gaming_promotions.promotion_id=ach_num_rounds.promotion_id AND
      pps.currency_id=ach_num_rounds.currency_id
	SET
		ppsd.day_bet = ppsd.day_bet - betAmountContributed,
		ppsd.day_win = ppsd.day_win - contributions.win,
		ppsd.day_loss = ppsd.day_loss - contributions.loss,
		ppsd.day_num_rounds = ppsd.day_num_rounds - 1,
		ppsd.daily_requirement_achieved =
			CASE 
				WHEN achievement_types.name='BET' THEN (ppsd.day_bet - betAmountContributed) >= ach_amount.amount
				ELSE 0
			END,
		ppsd.achieved_amount = GREATEST(0, ROUND(
			CASE 
				WHEN achievement_types.name='BET' THEN LEAST(ppsd.day_bet - betAmountContributed, ach_amount.amount)
				ELSE 0
			END, 0)),  
		ppsd.achieved_percentage = GREATEST(0, IFNULL(LEAST(1, ROUND(
			CASE 
				WHEN achievement_types.name='BET' THEN (ppsd.day_bet - betAmountContributed) / ach_amount.amount 
				ELSE 0
			END, 4)), 0))
	WHERE rounds.sb_bet_id = sbBetID AND rounds.license_type_id = 3 AND rounds.sb_extra_id IS NOT NULL;
	
	
	UPDATE gaming_promotions_player_statuses_daily AS ppsd
	JOIN gaming_game_rounds_promotion_contributions AS contributions ON 
			contributions.promotion_player_status_day_id = ppsd.promotion_player_status_day_id
	JOIN gaming_game_rounds AS rounds ON rounds.game_round_id = contributions.game_round_id
	SET 
		ppsd.conseq_cur = ppsd.conseq_cur * ppsd.daily_requirement_achieved
	WHERE rounds.sb_bet_id = sbBetID AND rounds.license_type_id = 3 AND rounds.sb_extra_id IS NOT NULL;


	SET @numDaysAchieved=0;

	UPDATE gaming_promotions_player_statuses AS pps
	JOIN gaming_game_rounds_promotion_contributions AS contributions ON
			contributions.promotion_player_status_id = pps.promotion_player_status_id
	JOIN gaming_promotions ON pps.promotion_id = gaming_promotions.promotion_id
	JOIN gaming_game_rounds AS rounds ON rounds.game_round_id = contributions.game_round_id
	JOIN gaming_promotions_achievement_types AS achievement_types ON gaming_promotions.promotion_achievement_type_id=achievement_types.promotion_achievement_type_id
    LEFT JOIN gaming_promotions_achievement_amounts AS ach_amount ON
      gaming_promotions.promotion_id=ach_amount.promotion_id AND
      pps.currency_id=ach_amount.currency_id
	LEFT JOIN gaming_promotions_achievement_rounds AS ach_num_rounds ON
      gaming_promotions.promotion_id=ach_num_rounds.promotion_id AND
      pps.currency_id=ach_num_rounds.currency_id
	LEFT JOIN gaming_promotions_prize_amounts AS prize_amount ON pps.promotion_id = prize_amount.promotion_id AND pps.currency_id=prize_amount.currency_id
	SET
		gaming_promotions.player_statuses_used = IF(pps.total_bet - betAmountContributed = 0 AND pps.total_win - contributions.win = 0 AND pps.total_loss - contributions.loss = 0 AND pps.num_rounds - 1 = 0, 0, 1),
		pps.total_bet = pps.total_bet - betAmountContributed,
		pps.num_rounds = pps.num_rounds - 1,
		pps.single_achieved_num = LEAST(IF(gaming_promotions.is_single, single_achieved_num - 1, pps.single_achieved_num), gaming_promotions.single_repeat_for),		
		pps.requirement_achieved = IF (gaming_promotions.achieved_disabled, 0,
			CASE
				WHEN gaming_promotions.is_single THEN
				(gaming_promotions.single_repeat_for = LEAST(pps.single_achieved_num - 1, gaming_promotions.single_repeat_for))
				WHEN gaming_promotions.achievement_daily_flag = 0 THEN
					CASE 
						WHEN achievement_types.name='BET' THEN (pps.total_bet - betAmountContributed) >= ach_amount.amount
						ELSE 0
					END  
				WHEN gaming_promotions.achievement_daily_flag=1 AND gaming_promotions.achievement_daily_consequetive_flag=0 THEN
					(
						SELECT @numDaysAchieved:=LEAST(COUNT(1), gaming_promotions.achievement_days_num) AS achievement_days_cur
						FROM gaming_promotions_player_statuses_daily
						WHERE pps.promotion_player_status_id=gaming_promotions_player_statuses_daily.promotion_player_status_id AND gaming_promotions_player_statuses_daily.daily_requirement_achieved=1
					) >= gaming_promotions.achievement_days_num
				WHEN gaming_promotions.achievement_daily_flag=1 AND gaming_promotions.achievement_daily_consequetive_flag=1 THEN 
					(
						SELECT @numDaysAchieved:=LEAST(MAX(conseq_cur), gaming_promotions.achievement_days_num)
						FROM gaming_promotions_player_statuses_daily
						WHERE pps.promotion_player_status_id=gaming_promotions_player_statuses_daily.promotion_player_status_id
					) >= gaming_promotions.achievement_days_num
				END),
		pps.achieved_amount=GREATEST(0, ROUND(
			IF (gaming_promotions.achievement_daily_flag=0,
				CASE 
					WHEN achievement_types.name='BET' AND gaming_promotions.is_single THEN pps.total_bet - LEAST(betAmountContributed, prize_amount.max_cap*1)
					WHEN achievement_types.name='BET' THEN LEAST(pps.total_bet - betAmountContributed, ach_amount.amount)
					ELSE 0
				END,
				CASE 
					WHEN achievement_types.name='BET' THEN LEAST(ach_amount.amount*@numDaysAchieved, ach_amount.amount*gaming_promotions.achievement_days_num)
					ELSE 0
				END
			), 0)),  
		pps.achieved_percentage=GREATEST(0, IFNULL(LEAST(1, ROUND(
			CASE
				WHEN gaming_promotions.achievement_daily_flag=0 THEN
				CASE 
					WHEN gaming_promotions.is_single THEN LEAST(pps.single_achieved_num - 1, gaming_promotions.single_repeat_for)/gaming_promotions.single_repeat_for
					WHEN achievement_types.name='BET' THEN (pps.total_bet - betAmountContributed) / ach_amount.amount 
					ELSE 0
				END  
				WHEN gaming_promotions.achievement_daily_flag=1 THEN 
					@numDaysAchieved/gaming_promotions.achievement_days_num
			END,4)), 0)),
		pps.achieved_days = IF(gaming_promotions.achievement_daily_flag=1, LEAST(gaming_promotions.achievement_days_num, @numDaysAchieved), NULL),
		contributions.bet = contributions.bet - betAmountContributed,
		contributions.win = 0,
		contributions.loss = 0
	WHERE rounds.sb_bet_id = sbBetID AND rounds.license_type_id = 3 AND rounds.sb_extra_id IS NOT NULL;
	
	
END root$$

DELIMITER ;