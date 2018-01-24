-- -------------------------------------
-- BonusGetRewardRules.sql
-- -------------------------------------
DROP procedure IF EXISTS `BonusGetRewardRules`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetRewardRules`(bonusRuleIDArray TEXT)
BEGIN
	
  DECLARE bonusRuleGetCounterID BIGINT DEFAULT -1;
  
  SET bonusRuleGetCounterID=BonusGetRulesInsertIDArray(bonusRuleIDArray,',');
  
  
  SELECT gaming_bonus_rules.bonus_rule_id, gaming_bonus_rules.name, gaming_bonus_rules.description, gaming_bonus_types.name AS bonus_type_name, priority, activation_start_date, activation_end_date, program_cost_threshold,
    wager_requirement_multiplier, expiry_date_fixed, expiry_days_from_awarding, allow_awarding_bonuses, awarded_total, added_to_real_money_total, operator_id, empty_selection, gaming_bonus_rules.player_selection_id,
    datetime_created, gaming_bonus_rules.is_active, gaming_bonus_rules.is_hidden, 
    sb_bet_type_code, cash_transaction_multiplier, single_bet_allowed, accumulators_allowed, system_bets_allowed, accumulator_min_odd_per_selection, system_min_odd_per_selection,    gaming_bonus_rules_rewards_trigger_types.name AS reward_trigger_type, trigger_reset_counter_bet_amount AS reward_trigger_reset_counter_bet_amount, 
    trigger_reset_counter_num_rounds AS reward_trigger_reset_counter_num_rounds, gaming_bonus_rules_rewards_credit_types.name AS reward_credit_type, 
    are_all_games_selected AS reward_are_all_games_selected, gaming_bonus_rules.comments, gaming_bonus_rules.redeem_threshold_on_deposit, gaming_bonus_rules.terms_and_conditions,gaming_bonus_rules.bonus_custom_type_id,
	gaming_bonus_rules.is_free_rounds, gaming_bonus_rules.free_round_expiry_date, gaming_bonus_rules.free_round_expiry_days, gaming_bonus_rules.num_free_rounds,
	gaming_bonus_rules.num_free_rounds_threshold, gaming_bonus_rules.num_free_rounds_awarded,
	gaming_games.has_auto_play,gaming_games.is_frequent_draws,gaming_games.is_passive
  FROM gaming_bonus_rules 
  JOIN gaming_bonus_rule_get_counter_rules ON bonus_rule_get_counter_id=bonusRuleGetCounterID AND gaming_bonus_rules.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id 
  JOIN gaming_bonus_types ON gaming_bonus_rules.bonus_type_id=gaming_bonus_types.bonus_type_id 
  JOIN gaming_bonus_rules_rewards ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_rewards.bonus_rule_id 
  JOIN gaming_bonus_rules_rewards_trigger_types ON gaming_bonus_rules_rewards.bonus_rules_rewards_trigger_type_id=gaming_bonus_rules_rewards_trigger_types.bonus_rules_rewards_trigger_type_id 
  JOIN gaming_bonus_rules_rewards_credit_types ON gaming_bonus_rules_rewards.bonus_rules_rewards_credit_type_id=gaming_bonus_rules_rewards_credit_types.bonus_rules_rewards_credit_type_id;
 
  -- free rouund profiles
  SELECT gaming_bonus_rule_free_round_profiles.bonus_rule_id, gaming_bonus_rule_free_round_profiles.bonus_free_round_profile_id
  FROM gaming_bonus_rule_free_round_profiles
  JOIN gaming_bonus_rule_get_counter_rules ON bonus_rule_get_counter_id=bonusRuleGetCounterID AND gaming_bonus_rule_free_round_profiles.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id;
    
  SELECT game_category_id, name, description, date_created, is_unassigend_category, level, parent_game_category_id 
  FROM gaming_game_categories 
  WHERE is_hidden=0;
  
  SELECT gaming_games.game_id, manufacturer_game_idf, game_name, game_description, manufacturer_game_type, 
    gaming_game_manufacturers.game_manufacturer_id, gaming_game_manufacturers.name, 
    gaming_operator_games.operator_game_id, gaming_operator_games.bonus_wgr_req_weigth,  
    gaming_game_categories.game_category_id, parent_game_category_id,  
    gaming_bonus_rules_wgr_req_weights.bonus_rule_id, gaming_bonus_rules_wgr_req_weights.bonus_wgr_req_weigth AS bonus_wgr_req_weigth_override 
  FROM gaming_game_categories 
  JOIN gaming_game_categories_games ON gaming_game_categories.game_category_id=gaming_game_categories_games.game_category_id 
  JOIN gaming_games ON gaming_game_categories_games.game_id=gaming_games.game_id  
  JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id = gaming_game_manufacturers.game_manufacturer_id 
  JOIN gaming_operator_games ON gaming_games.game_id = gaming_operator_games.game_id 
  JOIN gaming_bonus_rules_wgr_req_weights ON gaming_operator_games.operator_game_id=gaming_bonus_rules_wgr_req_weights.operator_game_id 
  JOIN gaming_bonus_rule_get_counter_rules ON bonus_rule_get_counter_id=bonusRuleGetCounterID AND gaming_bonus_rules_wgr_req_weights.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id; 
  
  SELECT gaming_bonus_rules_tags.bonus_rule_id, gaming_bonus_tags.bonus_tag_id, name, description, gaming_bonus_tags.date_created 
  FROM gaming_bonus_tags 
  JOIN gaming_bonus_rules_tags ON gaming_bonus_tags.bonus_tag_id=gaming_bonus_rules_tags.bonus_tag_id 
  JOIN gaming_bonus_rule_get_counter_rules ON bonus_rule_get_counter_id=bonusRuleGetCounterID AND gaming_bonus_rules_tags.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id;
  
  SELECT gaming_bonus_rules_rewards_tigger_bets.bonus_rule_id, trigger_rule_index, bet_amount, give_amount 
  FROM gaming_bonus_rules_rewards_tigger_bets 
  JOIN gaming_bonus_rule_get_counter_rules ON bonus_rule_get_counter_id=bonusRuleGetCounterID AND gaming_bonus_rules_rewards_tigger_bets.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id;
  SELECT gaming_bonus_rules_rewards_tigger_rounds.bonus_rule_id, trigger_rule_index, num_rounds, min_bet_amount, give_amount 
  FROM gaming_bonus_rules_rewards_tigger_rounds 
  JOIN gaming_bonus_rule_get_counter_rules ON bonus_rule_get_counter_id=bonusRuleGetCounterID AND gaming_bonus_rules_rewards_tigger_rounds.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id; 
  
  SELECT gaming_games.game_id, manufacturer_game_idf, game_name, game_description, manufacturer_game_type, 
    gaming_game_manufacturers.game_manufacturer_id, gaming_game_manufacturers.name, 
    gaming_operator_games.operator_game_id, gaming_operator_games.bonus_wgr_req_weigth,  
    gaming_game_categories.game_category_id, parent_game_category_id,
    gaming_bonus_rules_rewards_operator_games.bonus_rule_id 
  FROM gaming_game_categories 
  JOIN gaming_game_categories_games ON gaming_game_categories.game_category_id=gaming_game_categories_games.game_category_id 
  JOIN gaming_games ON gaming_game_categories_games.game_id=gaming_games.game_id  
  JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id = gaming_game_manufacturers.game_manufacturer_id 
  JOIN gaming_operator_games ON gaming_games.game_id = gaming_operator_games.game_id 
  JOIN gaming_bonus_rules_rewards_operator_games ON gaming_operator_games.operator_game_id=gaming_bonus_rules_rewards_operator_games.operator_game_id  
  JOIN gaming_bonus_rule_get_counter_rules ON bonus_rule_get_counter_id=bonusRuleGetCounterID AND gaming_bonus_rules_rewards_operator_games.bonus_rule_id=gaming_bonus_rule_get_counter_rules.bonus_rule_id; 
  DELETE FROM gaming_bonus_rule_get_counter_rules 
  WHERE bonus_rule_get_counter_id=bonusRuleGetCounterID;
END$$

DELIMITER ;

