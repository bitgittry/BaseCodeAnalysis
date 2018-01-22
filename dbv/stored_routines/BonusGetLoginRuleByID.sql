-- -------------------------------------
-- BonusGetLoginRuleByID.sql
-- -------------------------------------
DROP procedure IF EXISTS `BonusGetLoginRuleByID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetLoginRuleByID`(bonusRuleID BIGINT)
BEGIN
  
  
	SELECT gaming_bonus_rules.bonus_rule_id, gaming_bonus_rules.name, gaming_bonus_rules.description, gaming_bonus_types.name AS bonus_type_name, priority, activation_start_date, activation_end_date, program_cost_threshold,
		wager_requirement_multiplier, expiry_date_fixed, expiry_days_from_awarding, allow_awarding_bonuses, awarded_total, added_to_real_money_total, operator_id, empty_selection, gaming_bonus_rules.player_selection_id,
		datetime_created, gaming_bonus_rules.is_active, gaming_bonus_rules.is_hidden, gaming_bonus_types_awarding.name AS bonus_awarding_type,
		gaming_bonus_types_bet_returns.name AS bonus_bet_return_type, gaming_bonus_types_transfers.name AS bonus_transfer_type, gaming_bonus_types_release.name AS bonus_release_type, wager_req_real_only, transfer_upto_percentage, transfer_every_x_wager, 
		min_odd, withdrawal_limit_num_rounds, over_max_bet_win_contr_multiplier, casino_weight_mod, poker_weight_mod, sportsbook_weight_mod, lottery_weight_mod, sportspool_weight_mod, poolbetting_weight_mod, gaming_bonus_rules.restrict_platform_type, gaming_bonus_rules.forfeit_on_withdraw,
		sb_bet_type_code, cash_transaction_multiplier, single_bet_allowed, accumulators_allowed, system_bets_allowed, accumulator_min_odd_per_selection, system_min_odd_per_selection,		gaming_bonus_awarding_interval_types.name AS login_awarding_interval_type, occurrence_num_min AS login_occurrence_num_min, occurrence_num_max AS login_occurrence_num_max, interval_repeat_until_awarded AS login_interval_repeat_until_awarded,gaming_bonus_rules.is_free_bonus,
		gaming_bonus_rules_logins.restrict_weekday AS login_restrict_weekday, no_loyalty_points, pre_expiry_days, redeem_threshold_enabled, voucher_code, restrict_by_voucher_code, gaming_bonus_rules.comments , gaming_bonus_rules.linking_type, gaming_bonus_rules.redeem_threshold_on_deposit, gaming_bonus_rules.terms_and_conditions,
		award_bonus_max, date_eligable_check, currency_profile_id, game_weight_profile_id, sb_weight_profile_id, lotto_weight_profile_id, sportspool_weight_profile_id,  bonus_custom_type_id,max_count_per_interval, is_generic, gaming_bonus_rules.awarded_times, gaming_bonus_rules.awarded_times_threshold,
		gaming_bonus_rules.is_free_rounds, gaming_bonus_rules.free_round_expiry_date, gaming_bonus_rules.free_round_expiry_days, gaming_bonus_rules.num_free_rounds,
		gaming_bonus_rules.num_free_rounds_threshold, gaming_bonus_rules.num_free_rounds_awarded, num_prerequisites_or
	FROM gaming_bonus_rules 
	JOIN gaming_bonus_types ON gaming_bonus_rules.bonus_type_id=gaming_bonus_types.bonus_type_id 
	JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
	JOIN gaming_bonus_types_bet_returns ON gaming_bonus_rules.bonus_type_bet_return_id=gaming_bonus_types_bet_returns.bonus_type_bet_return_id
	JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id  
	LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
	JOIN gaming_bonus_rules_logins ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_logins.bonus_rule_id 
	JOIN gaming_bonus_awarding_interval_types ON gaming_bonus_rules_logins.bonus_awarding_interval_type_id=gaming_bonus_awarding_interval_types.bonus_awarding_interval_type_id
	WHERE gaming_bonus_rules.bonus_rule_id = bonusRuleID;

	-- free round profiles
	SELECT bonus_free_round_profile_id
    FROM gaming_bonus_rule_free_round_profiles
    WHERE bonus_rule_id = bonusRuleID;

	SELECT 
		gaming_operator_games.game_id, gaming_operator_games.operator_game_id,  
		gaming_bonus_rules_wgr_req_weights.bonus_rule_id, gaming_bonus_rules_wgr_req_weights.bonus_wgr_req_weigth AS bonus_wgr_req_weigth_override, gaming_license_type.name AS license_type 
	FROM gaming_bonus_rules 
	JOIN gaming_bonus_rules_wgr_req_weights ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_wgr_req_weights.bonus_rule_id 
	JOIN gaming_operator_games ON gaming_bonus_rules_wgr_req_weights.operator_game_id=gaming_operator_games.operator_game_id
	JOIN gaming_games ON gaming_operator_games.game_id = gaming_games.game_id AND gaming_games.license_type_id IN (1,2)
	JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id AND gaming_game_manufacturers.is_active=1
	JOIN gaming_license_type ON gaming_license_type.license_type_id = gaming_games.license_type_id
	WHERE gaming_bonus_rules.bonus_rule_id = bonusRuleID;


	SELECT gaming_bonus_rules_tags.bonus_rule_id, gaming_bonus_tags.bonus_tag_id, name, description, gaming_bonus_tags.date_created 
	FROM gaming_bonus_tags 
	JOIN gaming_bonus_rules_tags ON gaming_bonus_tags.bonus_tag_id=gaming_bonus_rules_tags.bonus_tag_id 
	WHERE gaming_bonus_rules_tags.bonus_rule_id =bonusRuleID;

	SELECT gbrwr.bonus_rule_id, gbrwr.min_bet, gbrwr.max_bet, gbrwr.max_wager_contibution, max_wager_contibution_before_weight, release_every_amount, max_bet_add_win_contr, gaming_currency.currency_id, currency_code, redeem_threshold 
	FROM gaming_bonus_rules_wager_restrictions AS gbrwr
	JOIN gaming_currency ON gbrwr.currency_id=gaming_currency.currency_id
	WHERE gbrwr.bonus_rule_id = bonusRuleID;

	SELECT platform_types.bonus_rule_id, platform_types.platform_type_id 
	FROM gaming_bonus_rules_platform_types AS platform_types
	WHERE bonus_rule_id=bonusRuleID; 

	SELECT bonus_bundles.parent_bonus_rule_id, bonus_bundles.child_bonus_rule_id, bonus_rules.name, bonus_rules.description
	FROM gaming_bonus_rules_bundles AS bonus_bundles
	JOIN gaming_bonus_rules AS bonus_rules ON bonus_bundles.child_bonus_rule_id = bonus_rules.bonus_rule_id
	WHERE bonus_bundles.parent_bonus_rule_id=bonusRuleID;

	SELECT bonus_pre_rules.bonus_rule_id, bonus_pre_rules.pre_bonus_rule_id, bonus_rules.name, bonus_rules.description
	FROM gaming_bonus_rules_pre_rules AS bonus_pre_rules
	JOIN gaming_bonus_rules AS bonus_rules ON bonus_pre_rules.pre_bonus_rule_id = bonus_rules.bonus_rule_id
	WHERE bonus_pre_rules.bonus_rule_id=bonusRuleID;

	SELECT gaming_operator_games.game_id, gaming_operator_games.operator_game_id, gaming_bonus_rules_wgr_req_weights.bonus_rule_id, gaming_bonus_rules_wgr_req_weights.bonus_wgr_req_weigth AS bonus_wgr_req_weigth_override, gaming_license_type.name AS license_type 
	FROM gaming_bonus_rules_wgr_req_weights 
	JOIN gaming_operator_games ON gaming_bonus_rules_wgr_req_weights.operator_game_id=gaming_operator_games.operator_game_id
	JOIN gaming_games ON gaming_operator_games.game_id = gaming_games.game_id AND gaming_games.license_type_id IN (6,7)
	JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id AND gaming_game_manufacturers.is_active=1
	JOIN gaming_license_type ON gaming_license_type.license_type_id = gaming_games.license_type_id
	WHERE gaming_bonus_rules_wgr_req_weights.bonus_rule_id=bonusRuleID;

	SELECT gaming_bonus_rules_wgr_draw_weights.bonus_rule_id, gaming_lottery_draws.lottery_draw_id, gaming_lottery_draws.game_id, gaming_bonus_rules_wgr_draw_weights.bonus_wgr_req_weigth AS bonus_wgr_draw_weigth_override 
	FROM gaming_bonus_rules_wgr_draw_weights 
	JOIN gaming_lottery_draws ON gaming_bonus_rules_wgr_draw_weights.lottery_draw_id = gaming_lottery_draws.lottery_draw_id
	WHERE gaming_bonus_rules_wgr_draw_weights.bonus_rule_id=bonusRuleID;

	SELECT gaming_bonus_rules_logins_amounts.bonus_rule_id, amount AS login_amount, gaming_currency.currency_id, currency_code 
	FROM gaming_bonus_rules_logins_amounts 
	JOIN gaming_currency ON  gaming_bonus_rules_logins_amounts.currency_id=gaming_currency.currency_id
	WHERE gaming_bonus_rules_logins_amounts.bonus_rule_id = bonusRuleID;

	SELECT gaming_bonus_rules_weekdays.bonus_rule_id, gaming_bonus_rules_weekdays.day_no
	FROM gaming_bonus_rules_weekdays
	WHERE gaming_bonus_rules_weekdays.bonus_rule_id=bonusRuleID;
END$$

DELIMITER ;

