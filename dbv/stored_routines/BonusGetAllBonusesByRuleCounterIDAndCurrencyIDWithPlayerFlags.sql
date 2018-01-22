-- -------------------------------------
-- BonusGetAllBonusesByRuleCounterIDAndCurrencyIDWithPlayerFlags.sql
-- -------------------------------------
DROP procedure IF EXISTS `BonusGetAllBonusesByRuleCounterIDAndCurrencyIDWithPlayerFlags`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetAllBonusesByRuleCounterIDAndCurrencyIDWithPlayerFlags`(bonusRuleGetCounterID BIGINT, clientStatID BIGINT, currencyID BIGINT, operatorGameIDFilter BIGINT, returnManualBonus TINYINT(1), returnIfNotInSelection TINYINT(1))
BEGIN
	
	-- Main Rule Data
	SELECT gaming_bonus_rules.bonus_rule_id, gaming_bonus_rules.name, gaming_bonus_rules.description, gaming_bonus_types.name AS bonus_type_name, gaming_bonus_rules.priority, 
		gaming_bonus_rules.activation_start_date, gaming_bonus_rules.activation_end_date, gaming_bonus_rules.program_cost_threshold,
		gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_rules.expiry_date_fixed, gaming_bonus_rules.expiry_days_from_awarding, 
        gaming_bonus_rules.allow_awarding_bonuses, gaming_bonus_rules.awarded_total, gaming_bonus_rules.added_to_real_money_total, 
        gaming_bonus_rules.operator_id, empty_selection, gaming_bonus_rules.player_selection_id,
		gaming_bonus_rules.datetime_created, is_active, gaming_bonus_rules.is_hidden, gaming_bonus_types_awarding.name AS bonus_awarding_type,
		gaming_bonus_types_bet_returns.name AS bonus_bet_return_type, gaming_bonus_types_transfers.name AS bonus_transfer_type, 
        gaming_bonus_types_release.name AS bonus_release_type, gaming_bonus_rules.wager_req_real_only, gaming_bonus_rules.transfer_upto_percentage, gaming_bonus_rules.transfer_every_x_wager, 
		gaming_bonus_rules.min_odd, gaming_bonus_rules.withdrawal_limit_num_rounds, gaming_bonus_rules.over_max_bet_win_contr_multiplier, gaming_bonus_rules.casino_weight_mod, gaming_bonus_rules.poker_weight_mod, 
		gaming_bonus_rules.sb_bet_type_code, gaming_bonus_rules.cash_transaction_multiplier, gaming_bonus_rules.single_bet_allowed, gaming_bonus_rules.accumulators_allowed,
		gaming_bonus_rules.system_bets_allowed, gaming_bonus_rules.accumulator_min_odd_per_selection, gaming_bonus_rules.system_min_odd_per_selection, 
		gaming_bonus_rules.sportsbook_weight_mod, gaming_bonus_rules.lottery_weight_mod, gaming_bonus_rules.sportspool_weight_mod, gaming_bonus_rules.poolbetting_weight_mod, 
        gaming_bonus_rules.forfeit_on_withdraw, gaming_bonus_rules.restrict_platform_type,
		-- Currency
		gaming_currency.currency_id, gaming_currency.currency_code, 
		-- Direct Give
		gaming_bonus_rules_direct_gvs_amounts.amount AS directgw_amount, 
		-- Deposit
		gaming_bonus_rules_deposits.is_percentage AS deposit_is_percentage, gaming_bonus_rules_deposits.percentage AS deposit_percentage, 
		gaming_bonus_rules_deposits.forfeit_on_withdraw_flag AS deposit_forfeit_on_withdraw_flag, gaming_bonus_rules_deposits.occurrence_num_min AS deposit_occurrence_num_min, 
        gaming_bonus_rules_deposits.occurrence_num_max AS deposit_occurrence_num_max,
		deposit_awarding_interval_table.name AS deposit_awarding_interval_type, wager_req_include_deposit_amount AS deposit_wager_req_include_deposit_amount, 
        gaming_bonus_rules_deposits.interval_repeat_until_awarded AS deposit_interval_repeat_until_awarded, gaming_bonus_rules_deposits.restrict_payment_method AS deposit_restrict_payment_method, 
        gaming_bonus_rules_deposits.restrict_weekday AS deposit_restrict_weekday, gaming_bonus_rules_deposits.payment_restriction_profile_id,
		gaming_bonus_rules_deposits_amounts.fixed_amount AS deposit_fixed_amount, gaming_bonus_rules_deposits_amounts.percentage_max_amount AS deposit_percentage_max_amount, 
        gaming_bonus_rules_deposits_amounts.min_deposit_amount AS deposit_min_deposit_amount, gaming_bonus_rules.is_free_bonus, 
		-- Free Rounds
		gaming_bonus_rules.is_free_rounds, gaming_bonus_rules.free_round_expiry_date, gaming_bonus_rules.free_round_expiry_days, gaming_bonus_rules.num_free_rounds,
		gaming_bonus_rules.num_free_rounds_threshold, gaming_bonus_rules.num_free_rounds_awarded,
		-- Player Flags
		IFNULL(counter_rules.player_in_selection, PlayerSelectionIsPlayerInSelection(gaming_bonus_rules.player_selection_id,clientStatID)) AS player_is_in_selection, 
		(SELECT COUNT(*) FROM gaming_bonus_instances WHERE gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID 
		  AND (is_lost=0 AND is_used_all=0 AND is_secured=0)) AS player_bonuses_in_balance,
		(SELECT COUNT(*) FROM gaming_bonus_instances WHERE gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID) 
		  AS player_bonuses_awarded,
		(SELECT COUNT(*) FROM gaming_bonus_instances WHERE gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID
		  AND gaming_bonus_instances.given_date >= counter_rules.filter_start_date) AS player_bonuses_awarded_from_interval, gaming_bonus_rules.no_loyalty_points, 
          gaming_bonus_rules.pre_expiry_days, gaming_bonus_rules.redeem_threshold_enabled,
		-- Core
        gaming_bonus_rules.voucher_code, gaming_bonus_rules.restrict_by_voucher_code, gaming_bonus_rules.comments, gaming_bonus_rules.linking_type, gaming_bonus_rules.redeem_threshold_on_deposit,
		gaming_bonus_rules_deposits.ring_fenced_by_bonus_rules, gaming_bonus_rules_deposits.ring_fenced_by_license_type, 
        gaming_bonus_rules.award_bonus_max, gaming_bonus_rules.date_eligable_check, gaming_bonus_rules.currency_profile_id, gaming_bonus_rules.game_weight_profile_id, 
        gaming_bonus_rules.sb_weight_profile_id, gaming_bonus_rules.lotto_weight_profile_id, gaming_bonus_rules.sportspool_weight_profile_id, gaming_bonus_rules.bonus_custom_type_id,
        gaming_bonus_rules.max_count_per_interval, gaming_bonus_rules.is_generic, 
        gaming_bonus_rules.awarded_times, gaming_bonus_rules.awarded_times_threshold, gaming_bonus_rules.num_prerequisites_or,
		-- login
        gaming_bonus_rules_logins_amounts.amount AS login_amount
	FROM gaming_bonus_rule_get_counter_rules AS counter_rules  
	STRAIGHT_JOIN gaming_bonus_rules ON 
		counter_rules.bonus_rule_get_counter_id=bonusRuleGetCounterID AND 
		gaming_bonus_rules.bonus_rule_id=counter_rules.bonus_rule_id AND 
		(returnManualBonus OR gaming_bonus_rules.is_manual_bonus=0)
	STRAIGHT_JOIN gaming_bonus_types ON gaming_bonus_rules.bonus_type_id=gaming_bonus_types.bonus_type_id
	STRAIGHT_JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
	STRAIGHT_JOIN gaming_bonus_types_bet_returns ON gaming_bonus_rules.bonus_type_bet_return_id=gaming_bonus_types_bet_returns.bonus_type_bet_return_id
	STRAIGHT_JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
	STRAIGHT_JOIN gaming_currency ON gaming_currency.currency_id=currencyID 
    LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
	-- Direct Give
	LEFT JOIN gaming_bonus_rules_direct_gvs_amounts ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_direct_gvs_amounts.bonus_rule_id 
		AND gaming_bonus_rules_direct_gvs_amounts.currency_id=gaming_currency.currency_id 
	-- login
    LEFT JOIN gaming_bonus_rules_logins_amounts ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_logins_amounts.bonus_rule_id AND gaming_bonus_rules_logins_amounts.currency_id=gaming_currency.currency_id 
	-- Deposit
	LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_deposits.bonus_rule_id 
	LEFT JOIN gaming_bonus_awarding_interval_types AS deposit_awarding_interval_table ON 
		gaming_bonus_rules_deposits.bonus_awarding_interval_type_id=deposit_awarding_interval_table.bonus_awarding_interval_type_id   
	LEFT JOIN gaming_bonus_rules_deposits_amounts ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_deposits_amounts.bonus_rule_id
		AND gaming_bonus_rules_deposits_amounts.currency_id=gaming_currency.currency_id; 
	
	SELECT 
		gaming_operator_games.game_id, gaming_operator_games.operator_game_id,  
		gaming_bonus_rules_wgr_req_weights.bonus_rule_id, gaming_bonus_rules_wgr_req_weights.bonus_wgr_req_weigth AS bonus_wgr_req_weigth_override, gaming_license_type.name AS license_type 
	FROM gaming_bonus_rule_get_counter_rules 
	STRAIGHT_JOIN gaming_bonus_rules_wgr_req_weights ON 
		bonus_rule_get_counter_id=bonusRuleGetCounterID AND 
		(gaming_bonus_rules_wgr_req_weights.operator_game_id=operatorGameIDFilter) AND 
		gaming_bonus_rule_get_counter_rules.bonus_rule_id=gaming_bonus_rules_wgr_req_weights.bonus_rule_id 
	STRAIGHT_JOIN gaming_operator_games ON gaming_bonus_rules_wgr_req_weights.operator_game_id=gaming_operator_games.operator_game_id
	STRAIGHT_JOIN gaming_games ON gaming_operator_games.game_id = gaming_games.game_id AND gaming_games.license_type_id IN (1,2)
	STRAIGHT_JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id AND gaming_game_manufacturers.is_active=1
	STRAIGHT_JOIN gaming_license_type ON gaming_license_type.license_type_id = gaming_games.license_type_id;

	-- Wager Restrictions
	SELECT gbrwr.bonus_rule_id, gbrwr.min_bet, gbrwr.max_bet, gbrwr.max_wager_contibution, max_wager_contibution_before_weight, release_every_amount, max_bet_add_win_contr, gaming_currency.currency_id, currency_code, redeem_threshold 
	FROM gaming_bonus_rule_get_counter_rules
	STRAIGHT_JOIN gaming_bonus_rules_wager_restrictions AS gbrwr ON bonus_rule_get_counter_id=bonusRuleGetCounterID 
		AND gbrwr.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id 
	STRAIGHT_JOIN gaming_currency ON gbrwr.currency_id=gaming_currency.currency_id AND gaming_currency.currency_id=currencyID;

	-- Platform Types
	SELECT platform_types.bonus_rule_id, platform_types.platform_type_id
	FROM gaming_bonus_rule_get_counter_rules
	STRAIGHT_JOIN gaming_bonus_rules_platform_types AS platform_types ON bonus_rule_get_counter_id=bonusRuleGetCounterID 
		AND platform_types.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id; 

	-- Tags
	SELECT gaming_bonus_rules_tags.bonus_rule_id, gaming_bonus_tags.bonus_tag_id, name, description, gaming_bonus_tags.date_created 
	FROM gaming_bonus_rule_get_counter_rules 
	STRAIGHT_JOIN gaming_bonus_rules_tags ON bonus_rule_get_counter_id=bonusRuleGetCounterID  
		AND gaming_bonus_rules_tags.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_bonus_tags ON  gaming_bonus_tags.bonus_tag_id=gaming_bonus_rules_tags.bonus_tag_id;
    
    -- Rule: Bonus Type - Rewards
	SELECT gaming_bonus_rules_rewards_tigger_bets.bonus_rule_id, trigger_rule_index, bet_amount, give_amount 
	FROM gaming_bonus_rule_get_counter_rules
	STRAIGHT_JOIN gaming_bonus_rules_rewards_tigger_bets ON bonus_rule_get_counter_id=bonusRuleGetCounterID AND gaming_bonus_rules_rewards_tigger_bets.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id;
	
	-- Rule: Bonus Type - Rewards
	SELECT gaming_bonus_rules_rewards_tigger_rounds.bonus_rule_id, trigger_rule_index, num_rounds, min_bet_amount, give_amount 
	FROM gaming_bonus_rule_get_counter_rules
	STRAIGHT_JOIN gaming_bonus_rules_rewards_tigger_rounds ON bonus_rule_get_counter_id=bonusRuleGetCounterID AND gaming_bonus_rules_rewards_tigger_rounds.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id; 

	-- Rule Bundles
	SELECT bonus_bundles.parent_bonus_rule_id, bonus_bundles.child_bonus_rule_id, bonus_rules.name, bonus_rules.description
	FROM gaming_bonus_rule_get_counter_rules
	STRAIGHT_JOIN gaming_bonus_rules_bundles AS bonus_bundles ON bonus_rule_get_counter_id=bonusRuleGetCounterID AND bonus_bundles.parent_bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_bonus_rules AS bonus_rules ON bonus_bundles.child_bonus_rule_id = bonus_rules.bonus_rule_id;

	-- Pre Rules
	SELECT bonus_pre.bonus_rule_id, bonus_pre.pre_bonus_rule_id, bonus_rules.name, bonus_rules.description
	FROM gaming_bonus_rule_get_counter_rules
	STRAIGHT_JOIN gaming_bonus_rules_pre_rules AS bonus_pre ON bonus_rule_get_counter_id=bonusRuleGetCounterID AND bonus_pre.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_bonus_rules AS bonus_rules ON bonus_pre.pre_bonus_rule_id = bonus_rules.bonus_rule_id;

	-- Lottery Games
	SELECT gaming_operator_games.game_id, gaming_operator_games.operator_game_id, gaming_bonus_rules_wgr_req_weights.bonus_rule_id, 
		gaming_bonus_rules_wgr_req_weights.bonus_wgr_req_weigth AS bonus_wgr_req_weigth_override, gaming_license_type.name AS license_type
	FROM gaming_bonus_rule_get_counter_rules 
	STRAIGHT_JOIN gaming_bonus_rules_wgr_req_weights ON bonus_rule_get_counter_id=bonusRuleGetCounterID 
		AND gaming_bonus_rules_wgr_req_weights.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_operator_games ON gaming_bonus_rules_wgr_req_weights.operator_game_id=gaming_operator_games.operator_game_id
	STRAIGHT_JOIN gaming_games ON gaming_operator_games.game_id = gaming_games.game_id AND gaming_games.license_type_id IN (6,7)
    STRAIGHT_JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id = gaming_game_manufacturers.game_manufacturer_id AND gaming_game_manufacturers.is_active = 1
	STRAIGHT_JOIN gaming_license_type ON gaming_license_type.license_type_id = gaming_games.license_type_id;

	-- Lottery Draws
	SELECT gaming_bonus_rules_wgr_draw_weights.bonus_rule_id, gaming_lottery_draws.lottery_draw_id, gaming_lottery_draws.game_id, gaming_bonus_rules_wgr_draw_weights.bonus_wgr_req_weigth AS bonus_wgr_draw_weigth_override 
	FROM gaming_bonus_rule_get_counter_rules 
	STRAIGHT_JOIN gaming_bonus_rules_wgr_draw_weights ON bonus_rule_get_counter_id=bonusRuleGetCounterID 
		AND gaming_bonus_rules_wgr_draw_weights.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_lottery_draws ON gaming_bonus_rules_wgr_draw_weights.lottery_draw_id = gaming_lottery_draws.lottery_draw_id;

	-- Free Rounds Profiles
    SELECT gbrfrp.bonus_rule_id, fr.bonus_free_round_profile_id, fr.game_manufacturer_id, fr.external_profile_idf, fr.description, fr.start_date, fr.end_date, fr.num_rounds, fr.is_active,
		   fr.is_hidden, fr.game_weight_profile_id, fr.date_created
	FROM gaming_bonus_rule_get_counter_rules
	STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_rule_get_counter_rules.bonus_rule_get_counter_id=bonusRuleGetCounterID AND
		gaming_bonus_rules.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_bonus_rule_free_round_profiles gbrfrp ON gbrfrp.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_bonus_free_round_profiles AS fr ON fr.bonus_free_round_profile_id=gbrfrp.bonus_free_round_profile_id;

	
	DELETE FROM gaming_bonus_rule_get_counter WHERE bonus_rule_get_counter_id=bonusRuleGetCounterID;
	DELETE FROM gaming_bonus_rule_get_counter_rules WHERE bonus_rule_get_counter_id=bonusRuleGetCounterID;

   
END$$

DELIMITER ;

