-- -------------------------------------
-- PromotionGetAllPromotionsByPCounterIDAndCurrencyIDWithPFlags.sql
-- -------------------------------------
DROP procedure IF EXISTS `PromotionGetAllPromotionsByPCounterIDAndCurrencyIDWithPFlags`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionGetAllPromotionsByPCounterIDAndCurrencyIDWithPFlags`(promotionGetCounterID BIGINT, clientStatID BIGINT, currencyID BIGINT, operatorGameIDFilter BIGINT, onlyIfInSelection TINYINT(1), ignoreFlags TINYINT(1))
BEGIN
    
  SELECT gaming_promotions.promotion_id, gaming_promotions.name, description, gaming_promotions.priority, gaming_promotions_achievement_types.name AS promotion_achievement_type, 
    achievement_start_date, achievement_end_date, achievement_daily_flag, achievement_daily_consequetive_flag, achievement_days_num, 
    gaming_promotions.max_players, open_to_all, player_selection_id, need_to_opt_in_flag, gaming_promotions_prize_types.name AS promotion_prize_type, prize_bonus_rule_id, 
    automatic_award_prize_enabled, award_prize_on_achievement, award_prize_on_date, award_num_players, gaming_promotions.is_active, gaming_promotions.is_hidden, gaming_promotions.wager_req_real_only, gaming_promotions.is_percentage, gaming_promotions.award_percentage, gaming_promotions.achieved_disabled,
    num_players_opted_in, can_opt_in, has_given_reward, num_players_awarded, datetime_created, is_child, is_in_group, is_parent, is_activated, gaming_promotions.min_odd,
	gaming_promotions.restrict_by_bonus_code, gaming_promotions.bonus_code, gaming_promotions.calculate_on_bet, gaming_promotions.is_single, gaming_promotions.single_repeat_for, gaming_promotions.single_prize_per_transaction, gaming_promotions.single_prize_netwin,
    gaming_promotions.currency_profile_id, gaming_promotions.game_weight_profile_id, gaming_promotions.sb_weight_profile_id, gaming_promotions.lotto_weight_profile_id, gaming_promotions.sportspool_weight_profile_id,
	gaming_promotions.date_last_updated, gaming_promotions.sb_bet_type_code, gaming_promotions.cash_transaction_multiplier, gaming_promotions.single_bet_allowed, gaming_promotions.accumulators_allowed, gaming_promotions.system_bets_allowed, 
	gaming_promotions.accumulator_min_odd_per_selection, gaming_promotions.system_min_odd_per_selection,

    gaming_currency.currency_id, gaming_currency.currency_code, 
  
    gaming_promotions_achievement_amounts.amount AS amount, 
  
    gaming_promotions_achievement_rounds.num_rounds AS num_rounds, gaming_promotions_achievement_rounds.min_bet_amount AS min_bet_amount, 
  
    prize_amounts.prize_amount, prize_amounts.min_cap, prize_amounts.max_cap,
    gaming_promotions.recurrence_enabled, gaming_promotions.recurrence_start_time, gaming_promotions.recurrence_end_time, gaming_promotions.recurrence_duration_minutes,
    gaming_promotions.recurrence_pattern_interval_type, gaming_promotions.recurrency_pattern_every_num,
	gaming_promotions.recurrence_end_type, gaming_promotions.recurrence_times,
	gaming_promotions.award_prize_timing_type, gaming_promotions.award_prize_timing_num_days, gaming_promotions.award_prize_timing_time, gaming_promotions.award_num_players_per_occurence,
	gaming_promotions.award_num_times_per_player, gaming_promotions.auto_opt_in_next, gaming_promotions.player_net_loss_capping_enabled,
    IF (ignoreFlags=1 OR clientStatID=0, 0, IFNULL(counter_promotions.player_in_selection, PlayerSelectionIsPlayerInSelection(gaming_promotions.player_selection_id,clientStatID))) AS player_is_in_selection, 
    IF (ignoreFlags=1 OR clientStatID=0, 0, IF (gaming_promotions_player_statuses.promotion_player_status_id IS NULL,0,1)) player_has_status,
    IF (ignoreFlags=1 OR clientStatID=0, 0, IF (gaming_promotions_player_statuses.promotion_player_status_id IS NOT NULL AND gaming_promotions_player_statuses.requirement_achieved=1,1,0)) player_requirement_achieved,
	gaming_promotions.award_num_free_rounds, gaming_promotions.award_percentage_free_rounds	
  FROM gaming_promotions 
  JOIN gaming_promotion_get_counter_promotions AS counter_promotions ON promotion_get_counter_id=promotionGetCounterID AND gaming_promotions.promotion_id=counter_promotions.promotion_id
  JOIN gaming_promotions_achievement_types ON gaming_promotions.promotion_achievement_type_id=gaming_promotions_achievement_types.promotion_achievement_type_id 
  JOIN gaming_promotions_prize_types ON gaming_promotions.promotion_prize_type_id=gaming_promotions_prize_types.promotion_prize_type_id 
  JOIN gaming_currency ON gaming_currency.currency_id=currencyID  
    
  LEFT JOIN gaming_promotions_achievement_amounts ON 
    gaming_promotions.promotion_id=gaming_promotions_achievement_amounts.promotion_id AND 
    gaming_promotions_achievement_amounts.currency_id=gaming_currency.currency_id
    
  LEFT JOIN gaming_promotions_achievement_rounds ON 
    gaming_promotions.promotion_id=gaming_promotions_achievement_rounds.promotion_id AND
    gaming_promotions_achievement_rounds.currency_id=gaming_currency.currency_id
    
  LEFT JOIN gaming_promotions_player_statuses ON
    gaming_promotions.promotion_id=gaming_promotions_player_statuses.promotion_id AND 
    gaming_promotions_player_statuses.client_stat_id=clientStatID AND gaming_promotions_player_statuses.is_active=1 AND gaming_promotions_player_statuses.is_current = 1

  LEFT JOIN gaming_promotions_prize_amounts AS prize_amounts ON 
    gaming_promotions.promotion_id=prize_amounts.promotion_id AND
    prize_amounts.currency_id=gaming_currency.currency_id;


  SELECT 
    gaming_operator_games.game_id, gaming_operator_games.operator_game_id,
    gaming_promotions_games.promotion_id, gaming_promotions_games.promotion_wgr_req_weight, gaming_license_type.name AS license_type
  FROM gaming_promotion_get_counter_promotions AS counter_promotions
  JOIN gaming_promotions_games ON 
    counter_promotions.promotion_get_counter_id=promotionGetCounterID AND 
    (operatorGameIDFilter=0 OR gaming_promotions_games.operator_game_id=operatorGameIDFilter) AND 
    counter_promotions.promotion_id=gaming_promotions_games.promotion_id 
  JOIN gaming_operator_games ON gaming_promotions_games.operator_game_id=gaming_operator_games.operator_game_id
  JOIN gaming_games ON gaming_operator_games.game_id = gaming_games.game_id AND gaming_games.license_type_id IN (1, 2)
  JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id = gaming_game_manufacturers.game_manufacturer_id AND gaming_game_manufacturers.is_active = 1
 JOIN gaming_license_type ON gaming_license_type.license_type_id = gaming_games.license_type_id
  WHERE operatorGameIDFilter!=-1;

	SELECT gaming_promotions_recurrence_days.promotion_id, gaming_promotions_recurrence_days.day_no   
	FROM gaming_promotion_get_counter_promotions AS counter_promotions 
  	JOIN gaming_promotions_recurrence_days ON gaming_promotions_recurrence_days.promotion_id = counter_promotions.promotion_id
    WHERE counter_promotions.promotion_get_counter_id=promotionGetCounterID;   

  DELETE FROM gaming_promotion_get_counter_promotions WHERE promotion_get_counter_id=promotionGetCounterID;
  DELETE FROM gaming_promotion_get_counter WHERE promotion_get_counter_id=promotionGetCounterID;
  
  
END$$

DELIMITER ;

