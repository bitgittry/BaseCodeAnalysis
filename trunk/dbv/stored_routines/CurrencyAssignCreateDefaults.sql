DROP procedure IF EXISTS `CurrencyAssignCreateDefaults`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CurrencyAssignCreateDefaults`(operatorID BIGINT, sessionID BIGINT)
BEGIN
  SET @operator_id=operatorID;
  SET @session_id=sessionID;
	
    -- 1. gaming_payment_amounts 
  INSERT INTO gaming_payment_amounts (
    currency_id, min_deposit, min_withdrawal, max_deposit, max_withdrawal, 
    before_kyc_deposit_limit, before_kyc_withdrawal_limit, session_id)
  SELECT 
    NewPaymentAmounts.currency_id, ROUND(min_deposit*exchange_rate,0), ROUND(min_withdrawal*exchange_rate,0), ROUND(max_deposit*exchange_rate,0), ROUND(max_withdrawal*exchange_rate,0), 
    ROUND(before_kyc_deposit_limit*exchange_rate,0), ROUND(before_kyc_withdrawal_limit*exchange_rate,0), @session_id
  FROM gaming_operators
  JOIN gaming_payment_amounts ON 
    operator_id=@operator_id AND gaming_operators.currency_id=gaming_payment_amounts.currency_id -- gaming_operators.currency_id: base currency of operator
  JOIN
  (
    SELECT gaming_operator_currency.currency_id, gaming_operator_currency.exchange_rate
    FROM gaming_operator_currency 
    JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0
    WHERE gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND gaming_operator_currency.currency_id NOT IN (SELECT currency_id FROM gaming_payment_amounts)
  ) AS NewPaymentAmounts ON 1=1;
  
  -- 2. gaming_transfer_limit_amounts
  INSERT INTO gaming_transfer_limit_amounts (transfer_limit_id, currency_id, admin_max_amount, session_id)
  SELECT 
    gaming_transfer_limit_amounts.transfer_limit_id, gaming_operator_currency.currency_id, ROUND(gaming_transfer_limit_amounts.admin_max_amount*exchange_rate,0), @session_id
  FROM gaming_operators
  JOIN gaming_transfer_limit_amounts ON -- base currency
    operator_id=@operator_id AND gaming_operators.currency_id=gaming_transfer_limit_amounts.currency_id -- gaming_operators.currency_id: base currency of operator
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT limit_amounts.currency_id 
      FROM gaming_transfer_limit_amounts AS limit_amounts
      WHERE limit_amounts.transfer_limit_id=gaming_transfer_limit_amounts.transfer_limit_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;
    
  -- ------------------------------------------------------------------
  -- 3. bonuses 
  
    -- gaming_bonus_rules_direct_gvs_amounts
  INSERT INTO gaming_bonus_rules_direct_gvs_amounts (bonus_rule_id, currency_id, amount)
  SELECT amount_base_currency.bonus_rule_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.amount*exchange_rate,0)
  FROM gaming_operators
  JOIN gaming_bonus_rules_direct_gvs_amounts AS amount_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=amount_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT amount_currencies.currency_id 
      FROM gaming_bonus_rules_direct_gvs_amounts AS amount_currencies
      WHERE amount_currencies.bonus_rule_id=amount_base_currency.bonus_rule_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;
  
    -- gaming_bonus_rules_deposits_amounts
  INSERT INTO gaming_bonus_rules_deposits_amounts (bonus_rule_id, currency_id, fixed_amount, percentage_max_amount, min_deposit_amount)
  SELECT amount_base_currency.bonus_rule_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.fixed_amount*exchange_rate,0), ROUND(amount_base_currency.percentage_max_amount*exchange_rate,0), ROUND(amount_base_currency.min_deposit_amount*exchange_rate,0)
  FROM gaming_operators
  JOIN gaming_bonus_rules_deposits_amounts AS amount_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=amount_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT amount_currencies.currency_id 
      FROM gaming_bonus_rules_deposits_amounts AS amount_currencies
      WHERE amount_currencies.bonus_rule_id=amount_base_currency.bonus_rule_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;  
    
  -- gaming_bonus_rules_logins_amounts
  INSERT INTO gaming_bonus_rules_logins_amounts (bonus_rule_id, currency_id, amount)
  SELECT amount_base_currency.bonus_rule_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.amount*exchange_rate,0)
  FROM gaming_operators
  JOIN gaming_bonus_rules_logins_amounts AS amount_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=amount_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT amount_currencies.currency_id 
      FROM gaming_bonus_rules_logins_amounts AS amount_currencies
      WHERE amount_currencies.bonus_rule_id=amount_base_currency.bonus_rule_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;
   
  -- gaming_bonus_rules_for_promotions_amounts
  INSERT INTO gaming_bonus_rules_for_promotions_amounts (bonus_rule_id, currency_id, amount)
  SELECT amount_base_currency.bonus_rule_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.amount*exchange_rate,0)
  FROM gaming_operators
  JOIN gaming_bonus_rules_for_promotions_amounts AS amount_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=amount_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT amount_currencies.currency_id 
      FROM gaming_bonus_rules_for_promotions_amounts AS amount_currencies
      WHERE amount_currencies.bonus_rule_id=amount_base_currency.bonus_rule_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;
    
  -- gaming_bonus_rules_manuals_amounts
  INSERT INTO gaming_bonus_rules_manuals_amounts (bonus_rule_id, currency_id, min_amount, max_amount)
  SELECT amount_base_currency.bonus_rule_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.min_amount*exchange_rate,0), ROUND(amount_base_currency.max_amount*exchange_rate,0)
  FROM gaming_operators
  JOIN gaming_bonus_rules_manuals_amounts AS amount_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=amount_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT amount_currencies.currency_id 
      FROM gaming_bonus_rules_manuals_amounts AS amount_currencies
      WHERE amount_currencies.bonus_rule_id=amount_base_currency.bonus_rule_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;  

  -- gaming_bonus_rules_free_rounds_amount
  INSERT INTO gaming_bonus_rules_free_rounds_amounts (bonus_rule_id, currency_id, min_bet, max_bet, max_win_total, max_win)
  SELECT amount_base_currency.bonus_rule_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.min_bet*exchange_rate,0), ROUND(amount_base_currency.max_bet*exchange_rate,0),  ROUND(amount_base_currency.max_win_total*exchange_rate,0),  ROUND(amount_base_currency.max_win*exchange_rate,0)
  FROM gaming_operators
  JOIN gaming_bonus_rules_free_rounds_amounts AS amount_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=amount_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT amount_currencies.currency_id 
      FROM gaming_bonus_rules_free_rounds_amounts AS amount_currencies
      WHERE amount_currencies.bonus_rule_id=amount_base_currency.bonus_rule_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;  
    
  INSERT INTO gaming_bonus_rules_wager_restrictions (bonus_rule_id, currency_id, min_bet, max_bet,max_wager_contibution,max_wager_contibution_before_weight,release_every_amount,max_bet_add_win_contr)
  SELECT amount_base_currency.bonus_rule_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.min_bet*exchange_rate,0), 
  ROUND(amount_base_currency.max_bet*exchange_rate,0),ROUND(amount_base_currency.max_wager_contibution*exchange_rate,0),
  ROUND(amount_base_currency.max_wager_contibution_before_weight*exchange_rate,0),ROUND(amount_base_currency.release_every_amount*exchange_rate,0),
  ROUND(amount_base_currency.max_bet_add_win_contr*exchange_rate,0)
  FROM gaming_operators
  JOIN gaming_bonus_rules_wager_restrictions AS amount_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=amount_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT wagering_currencies.currency_id 
      FROM gaming_bonus_rules_wager_restrictions AS wagering_currencies
      WHERE wagering_currencies.bonus_rule_id=amount_base_currency.bonus_rule_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;  
   
    /* -- Bonus Rule Rewards are not set per currency
    
      -- gaming_bonus_rules_rewards_tigger_bets
    INSERT INTO gaming_bonus_rules_rewards_tigger_bets (bonus_rule_id, currency_id, amount)
    SELECT amount_base_currency.bonus_rule_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.amount*exchange_rate,0)
    FROM gaming_operators
    JOIN gaming_bonus_rules_rewards_tigger_bets AS amount_base_currency ON 
      gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=amount_base_currency.currency_id
    JOIN gaming_operator_currency ON 
      gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
      gaming_operator_currency.currency_id NOT IN 
      (
        SELECT amount_currencies.currency_id 
        FROM gaming_bonus_rules_rewards_tigger_bets AS amount_currencies
        WHERE amount_currencies.bonus_rule_id=amount_base_currency.bonus_rule_id
      );
    */
  
  -- ------------------------------------------------------------------
  -- 4. promotions
  
    -- gaming_promotions_achievement_amounts
  INSERT INTO gaming_promotions_achievement_amounts (promotion_id, currency_id, amount)
  SELECT achievement_amount_base_currency.promotion_id, gaming_operator_currency.currency_id, ROUND(achievement_amount_base_currency.amount*exchange_rate,0)
  FROM gaming_operators
  JOIN gaming_promotions_achievement_amounts AS achievement_amount_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=achievement_amount_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT achivement_amounts_currencies.currency_id 
      FROM gaming_promotions_achievement_amounts AS achivement_amounts_currencies
      WHERE achivement_amounts_currencies.promotion_id=achievement_amount_base_currency.promotion_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;
    
    -- gaming_promotions_achievement_rounds
  INSERT INTO gaming_promotions_achievement_rounds (promotion_id, currency_id, num_rounds, min_bet_amount)
  SELECT achievement_round_base_currency.promotion_id, gaming_operator_currency.currency_id, achievement_round_base_currency.num_rounds, ROUND(achievement_round_base_currency.min_bet_amount*exchange_rate,0)
  FROM gaming_operators
  JOIN gaming_promotions_achievement_rounds AS achievement_round_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=achievement_round_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT achivement_rounds_currencies.currency_id 
      FROM gaming_promotions_achievement_rounds AS achivement_rounds_currencies
      WHERE achivement_rounds_currencies.promotion_id=achievement_round_base_currency.promotion_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;
  
  -- gaming_promotion_wager_restrictions 
  INSERT INTO gaming_promotion_wager_restrictions (promotion_id, currency_id, min_bet, max_bet, max_wager_contibution, max_wager_contibution_before_weight)
  SELECT amount_base_currency.promotion_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.min_bet*exchange_rate,0), ROUND(amount_base_currency.max_bet*exchange_rate,0), ROUND(amount_base_currency.max_wager_contibution*exchange_rate,0), ROUND(amount_base_currency.max_wager_contibution_before_weight*exchange_rate,0)
  FROM gaming_operators
  JOIN gaming_promotion_wager_restrictions AS amount_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=amount_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT amount_currencies.currency_id 
      FROM gaming_promotion_wager_restrictions AS amount_currencies
      WHERE amount_currencies.promotion_id=amount_base_currency.promotion_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;

  INSERT INTO gaming_promotions_prize_amounts(promotion_id, currency_id, prize_amount, max_cap, min_cap)
  SELECT amount_base_currency.promotion_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.prize_amount*exchange_rate,0), ROUND(amount_base_currency.max_cap*exchange_rate,0), ROUND(amount_base_currency.min_cap*exchange_rate,0)
  FROM gaming_operators
  JOIN gaming_promotions_prize_amounts AS amount_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=amount_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT amount_currencies.currency_id 
      FROM gaming_promotions_prize_amounts AS amount_currencies
      WHERE amount_currencies.promotion_id=amount_base_currency.promotion_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;
  -- ------------------------------------------------------------------
  -- tournament gaming_tournament_prize_amounts
  
  INSERT INTO gaming_tournament_prize_amounts (tournament_prize_id, currency_id, amount)
  SELECT prize_amount_base_currency.tournament_prize_id, gaming_operator_currency.currency_id, ROUND(prize_amount_base_currency.amount*exchange_rate,0)
  FROM gaming_operators
  JOIN gaming_tournament_prize_amounts AS prize_amount_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=prize_amount_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT prize_currencies.currency_id 
      FROM gaming_tournament_prize_amounts AS prize_currencies
      WHERE prize_currencies.tournament_prize_id=prize_amount_base_currency.tournament_prize_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;
  
  -- tournament wager_restictions
  INSERT INTO gaming_tournament_wager_restrictions (tournament_id, currency_id, min_bet)
  SELECT amount_base_currency.tournament_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.min_bet*exchange_rate,0)
  FROM gaming_operators
  JOIN gaming_tournament_wager_restrictions AS amount_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=amount_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT amount_currencies.currency_id 
      FROM gaming_tournament_wager_restrictions AS amount_currencies
      WHERE amount_currencies.tournament_id=amount_base_currency.tournament_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;

  -- ------------------------------------------------------------------
  -- rule engine gaming_rule_events_vars_currency_value
  
  INSERT INTO gaming_rule_events_vars_currency_value (rule_events_var_id, currency_id, value)
  SELECT events_vars_base_currency.rule_events_var_id, gaming_operator_currency.currency_id, ROUND(events_vars_base_currency.value*exchange_rate,0)
  FROM gaming_operators
  JOIN gaming_rule_events_vars_currency_value AS events_vars_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=events_vars_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT event_var_currencies.currency_id 
      FROM gaming_rule_events_vars_currency_value AS event_var_currencies
      WHERE event_var_currencies.rule_events_var_id=events_vars_base_currency.rule_events_var_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;

  -- ------------------------------------------------------------------
   -- loyalty points
  INSERT INTO gaming_loyalty_points_games (game_id, currency_id, amount, loyalty_points, vip_level_id)
  SELECT amount_base_currency.game_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.amount*exchange_rate,0), amount_base_currency.loyalty_points, gaming_vip_levels.vip_level_id
  FROM gaming_operators
  JOIN gaming_vip_levels ON gaming_operators.operator_id=@operator_id
  JOIN gaming_loyalty_points_games AS amount_base_currency ON 
     gaming_operators.currency_id=amount_base_currency.currency_id AND amount_base_currency.vip_level_id = gaming_vip_levels.vip_level_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT amount_currencies.currency_id 
      FROM gaming_loyalty_points_games AS amount_currencies
      WHERE amount_currencies.game_id=amount_base_currency.game_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;

  INSERT INTO gaming_loyalty_points_game_categories (game_category_id, currency_id, amount, loyalty_points, vip_level_id)
  SELECT amount_base_currency.game_category_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.amount*exchange_rate,0), amount_base_currency.loyalty_points, gaming_vip_levels.vip_level_id
  FROM gaming_operators
  JOIN gaming_vip_levels ON gaming_operators.operator_id=@operator_id
  JOIN gaming_loyalty_points_game_categories AS amount_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=amount_base_currency.currency_id AND amount_base_currency.vip_level_id = gaming_vip_levels.vip_level_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT amount_currencies.currency_id 
      FROM gaming_loyalty_points_game_categories AS amount_currencies
      WHERE amount_currencies.game_category_id=amount_base_currency.game_category_id
    )
  JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;
  
  -- ------------------------------------------------------------------
  -- currency profiles
  
  INSERT INTO gaming_currency_profiles_currencies (currency_profile_id, currency_id, exchange_rate)
  SELECT currency_profile_base_currency.currency_profile_id, gaming_operator_currency.currency_id, gaming_operator_currency.exchange_rate
  FROM gaming_operators
  JOIN gaming_currency_profiles_currencies AS currency_profile_base_currency ON 
    gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=currency_profile_base_currency.currency_id
  JOIN gaming_operator_currency ON 
    gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
    gaming_operator_currency.currency_id NOT IN 
    (
      SELECT currency_profile_currencies.currency_id 
      FROM gaming_currency_profiles_currencies AS currency_profile_currencies
      WHERE currency_profile_currencies.currency_profile_id=currency_profile_base_currency.currency_profile_id
    )
   JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;     
	
	-- free round profiles 
	INSERT INTO gaming_bonus_free_round_profiles_amounts (bonus_free_round_profile_id,currency_id,cost_per_round)
	SELECT amount_base_currency.bonus_free_round_profile_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.cost_per_round*exchange_rate,0)
	FROM gaming_operators
	JOIN gaming_bonus_free_round_profiles_amounts AS amount_base_currency ON
		gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=amount_base_currency.currency_id
	JOIN gaming_operator_currency ON 
	gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
	gaming_operator_currency.currency_id NOT IN 
   	(
	 SELECT amount_currencies.currency_id 
	 FROM gaming_bonus_free_round_profiles_amounts AS amount_currencies
	 WHERE amount_currencies.bonus_free_round_profile_id=amount_base_currency.bonus_free_round_profile_id
    )
    JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;
	
	-- loyalty redemption
	INSERT INTO gaming_loyalty_redemption_currency_amounts (loyalty_redemption_id,currency_id,amount)
	SELECT amount_base_currency.loyalty_redemption_id, gaming_operator_currency.currency_id, ROUND(amount_base_currency.amount*exchange_rate,0)
	FROM gaming_operators
	JOIN gaming_loyalty_redemption_currency_amounts AS amount_base_currency ON
		gaming_operators.operator_id=@operator_id AND gaming_operators.currency_id=amount_base_currency.currency_id
	JOIN gaming_operator_currency ON 
	gaming_operator_currency.operator_id=@operator_id AND gaming_operator_currency.is_active=1 AND
	gaming_operator_currency.currency_id NOT IN 
   	(
	 SELECT amount_currencies.currency_id 
	 FROM gaming_loyalty_redemption_currency_amounts AS amount_currencies
	 WHERE amount_currencies.loyalty_redemption_id=amount_base_currency.loyalty_redemption_id
     )
     JOIN gaming_currency ON gaming_operator_currency.currency_id=gaming_currency.currency_id AND gaming_currency.exchange_rate_only=0;
	
 
END$$

DELIMITER ;

