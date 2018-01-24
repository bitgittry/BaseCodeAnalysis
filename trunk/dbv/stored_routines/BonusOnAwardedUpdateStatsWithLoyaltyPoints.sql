DROP procedure IF EXISTS `BonusOnAwardedUpdateStatsWithLoyaltyPoints`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusOnAwardedUpdateStatsWithLoyaltyPoints`(bonusInstanceID BIGINT, loyaltyPoints DECIMAL(18,5))
BEGIN
  
  

  DECLARE clientStatID, gamePlayID, cwFreeRoundID, bonusRuleID, transactionID BIGINT DEFAULT -1;
  DECLARE exchangeRate DECIMAL(18,5) DEFAULT 1.0;
  DECLARE IsFreeBonus, noficationEnabled TINYINT(1) DEFAULT 0;
  DECLARE awardingType VARCHAR(20) DEFAULT NULL;

  SELECT gaming_operator_currency.exchange_rate, gaming_bonus_instances.bonus_rule_id,is_free_bonus,gaming_bonus_types_awarding.name, cw_free_round_id, gaming_client_stats.client_stat_id 
  INTO exchangeRate, bonusRuleID, IsFreeBonus, awardingType, cwFreeRoundID, clientStatID
  FROM gaming_bonus_instances
  JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = gaming_bonus_instances.bonus_rule_id
  JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
  JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id=gaming_client_stats.client_stat_id
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
  JOIN gaming_operators ON gaming_operators.is_main_operator=1 AND gaming_operator_currency.operator_id=gaming_operators.operator_id
  WHERE gaming_bonus_instances.bonus_instance_id=bonusInstanceID;
  
  
  UPDATE gaming_client_stats 
  JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=bonusInstanceID AND gaming_client_stats.client_stat_id=gaming_bonus_instances.client_stat_id 
  LEFT JOIN gaming_cw_free_rounds ON gaming_cw_free_rounds.cw_free_round_id = gaming_bonus_instances.cw_free_round_id
  LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules_deposits.bonus_rule_id
  SET 
    gaming_client_stats.current_bonus_balance=current_bonus_balance+gaming_bonus_instances.bonus_amount_given,
    gaming_client_stats.total_bonus_awarded=gaming_client_stats.total_bonus_awarded+gaming_bonus_instances.bonus_amount_given,
    gaming_client_stats.total_bonus_awarded_base=gaming_client_stats.total_bonus_awarded_base+ROUND(gaming_bonus_instances.bonus_amount_given/exchangeRate, 5),
	gaming_client_stats.current_ring_fenced_sb = IF (ring_fenced_by_license_type=3,current_ring_fenced_sb+ring_fenced_amount_given,current_ring_fenced_sb),
	gaming_client_stats.current_ring_fenced_casino = IF (ring_fenced_by_license_type=1,current_ring_fenced_casino+ring_fenced_amount_given,current_ring_fenced_casino),
	gaming_client_stats.current_ring_fenced_poker = IF (ring_fenced_by_license_type=2,current_ring_fenced_poker+ring_fenced_amount_given,current_ring_fenced_poker),
	gaming_client_stats.current_ring_fenced_amount = IF (ring_fenced_by_bonus_rules,gaming_client_stats.current_ring_fenced_amount+ring_fenced_amount_given,gaming_client_stats.current_ring_fenced_amount),
	gaming_client_stats.current_free_rounds_amount = gaming_client_stats.current_free_rounds_amount + IFNULL(gaming_cw_free_rounds.cost_per_round * gaming_cw_free_rounds.free_rounds_awarded,0),
	gaming_client_stats.current_free_rounds_num = gaming_client_stats.current_free_rounds_num + IFNULL(gaming_cw_free_rounds.free_rounds_awarded,0);
  
  
  INSERT INTO gaming_transactions
  (payment_transaction_type_id, amount_total, amount_total_base, 
    currency_id, exchange_rate, amount_real, 
	amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, 
	balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, 
	extra_id, extra2_id, pending_bet_real, pending_bet_bonus, withdrawal_pending_after,
	loyalty_points_bonus, loyalty_points_after_bonus, amount_free_round, amount_free_round_win, balance_free_round_after, balance_free_round_win_after) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, bonus_amount_given, ROUND(bonus_amount_given/exchangeRate, 5), 
	gaming_client_stats.currency_id, exchangeRate, 0, bonus_amount_given, 0, 
	loyaltyPoints, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, 
	current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, 
	gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, pending_bets_real, pending_bets_bonus, withdrawal_pending_amount,
	0, (gaming_client_stats.total_loyalty_points_given_bonus - gaming_client_stats.total_loyalty_points_used_bonus),IFNULL(gaming_cw_free_rounds.cost_per_round * gaming_cw_free_rounds.free_rounds_awarded,0),0, gaming_client_stats.current_free_rounds_amount, gaming_client_stats.current_free_rounds_win_locked
  FROM gaming_bonus_instances  
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=IF(gaming_bonus_instances.is_free_rounds = 0,'BonusAwarded','FreeRoundBonusAwarded') 
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=gaming_bonus_instances.client_stat_id 
  LEFT JOIN gaming_cw_free_rounds ON gaming_cw_free_rounds.cw_free_round_id = gaming_bonus_instances.cw_free_round_id
  WHERE gaming_bonus_instances.bonus_instance_id=bonusInstanceID; 
   
  SET transactionID=LAST_INSERT_ID();

  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,
	amount_free_bet, timestamp, client_id, client_stat_id, 
	payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, 
    currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus, 
    loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,
    IF(IsFreeBonus OR awardingType = 'FreeBet',amount_bonus,0) ,timestamp, client_id, client_stat_id, 
	payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after,
    currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus, 
    gaming_transactions.loyalty_points,gaming_transactions.loyalty_points_after, gaming_transactions.loyalty_points_bonus, gaming_transactions.loyalty_points_after_bonus
  FROM gaming_transactions
  WHERE transaction_id=transactionID;

  SET gamePlayID=LAST_INSERT_ID();
  CALL GameUpdateRingFencedBalances(clientStatID, gamePlayID);

  IF (cwFreeRoundID IS NOT NULL) THEN
	  INSERT INTO gaming_game_plays_cw_free_rounds 
      (game_play_id, amount_free_round, amount_free_round_win, balance_free_round_after, balance_free_round_win_after, cw_free_round_id)
	  SELECT gamePlayID, amount_free_round, amount_free_round_win, balance_free_round_after, balance_free_round_win_after, cwFreeRoundID
	  FROM gaming_transactions
	  WHERE transaction_id=transactionID; 
  END IF;
 
  COMMIT AND CHAIN;
  
  UPDATE gaming_bonus_rules 
  JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=bonusInstanceID AND gaming_bonus_rules.bonus_rule_id=gaming_bonus_instances.bonus_rule_id
  SET gaming_bonus_rules.awarded_total=gaming_bonus_rules.awarded_total+(gaming_bonus_instances.bonus_amount_given/exchangeRate);
  
  -- update parent bonus rule's selection (flag and number of included players) when it is part of chained bonuses (prerequisites)  
  UPDATE gaming_bonus_instances AS inst
  JOIN gaming_bonus_rules_pre_rules AS pre ON inst.bonus_rule_id = pre.pre_bonus_rule_id
  JOIN gaming_bonus_rules_pre_rules AS parent ON pre.bonus_rule_id = parent.bonus_rule_id
  JOIN gaming_bonus_rules AS rule ON parent.bonus_rule_id = rule.bonus_rule_id AND rule.linking_type = 'AWARDED'
  JOIN gaming_player_selections AS sel ON rule.player_selection_id = sel.player_selection_id
  SET sel.selected_players = 1, sel.num_players = sel.num_players + 1
  WHERE inst.bonus_instance_id = bonusInstanceID AND rule.num_prerequisites_or IS NOT NULL AND rule.empty_selection = 1;
 
  COMMIT AND CHAIN;

  INSERT INTO gaming_player_selections_selected_players (player_selection_id, client_stat_id, include_flag, exclude_flag) 
  SELECT player_selection_id,client_stat_id,1,0
  FROM (
	  SELECT bonuses.bonus_rule_id,SUM(IF(achieved = 1, 1, 0)) AS achieved,client_stat_id,player_selection_id, bonuses.num_prerequisites_or AS num_prerequisites_or
	  FROM (
		  SELECT parentRule.bonus_rule_id,IF(bonusChildren.bonus_rule_id IS NULL,0,1) AS achieved, gbi.client_stat_id, player_selection_id, num_prerequisites_or
          FROM gaming_bonus_instances gbi
		  STRAIGHT_JOIN gaming_bonus_rules_pre_rules gbrpr ON gbi.bonus_rule_id  = gbrpr.pre_bonus_rule_id
		  STRAIGHT_JOIN gaming_bonus_rules_pre_rules parentRule ON gbrpr.bonus_rule_id = parentRule.bonus_rule_id
		  STRAIGHT_JOIN gaming_bonus_rules ON parentRule.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND linking_type = 'AWARDED'
		  LEFT JOIN gaming_bonus_instances bonusChildren ON parentRule.pre_bonus_rule_id = bonusChildren.bonus_rule_id 
			AND bonusChildren.client_stat_id = gbi.client_stat_id 
		  WHERE gbi.bonus_instance_id  = bonusInstanceID
	  ) AS bonuses
	  GROUP BY bonuses.bonus_rule_id
	  HAVING (num_prerequisites_or IS NOT NULL AND achieved >= num_prerequisites_or)
  ) AS players
  ON DUPLICATE KEY UPDATE include_flag=1;


  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date)
  SELECT players.player_selection_id, players.client_stat_id,1, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = players.player_selection_id)  MINUTE)
  FROM (
	  SELECT bonuses.bonus_rule_id, SUM(IF(achieved = 1, 1, 0)) AS achieved,client_stat_id,player_selection_id, bonuses.num_prerequisites_or AS num_prerequisites_or
	  FROM (
		  SELECT parentRule.bonus_rule_id,IF(bonusChildren.bonus_rule_id IS NULL,0,1) AS achieved, gbi.client_stat_id, player_selection_id, num_prerequisites_or
          FROM gaming_bonus_instances gbi
		  STRAIGHT_JOIN gaming_bonus_rules_pre_rules gbrpr ON gbi.bonus_rule_id  = gbrpr.pre_bonus_rule_id
		  STRAIGHT_JOIN gaming_bonus_rules_pre_rules parentRule ON gbrpr.bonus_rule_id = parentRule.bonus_rule_id
		  STRAIGHT_JOIN gaming_bonus_rules ON parentRule.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND linking_type = 'AWARDED'
		  LEFT JOIN gaming_bonus_instances bonusChildren ON parentRule.pre_bonus_rule_id = bonusChildren.bonus_rule_id AND bonusChildren.client_stat_id = gbi.client_stat_id 
		  WHERE gbi.bonus_instance_id  = bonusInstanceID
	  ) AS bonuses
	  GROUP BY bonuses.bonus_rule_id
	  HAVING (num_prerequisites_or IS NOT NULL AND achieved >= num_prerequisites_or)
  ) AS players
		  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND gaming_player_selections_player_cache.expiry_date IS NULL, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
								  gaming_player_selections_player_cache.player_in_selection=IF(VALUES(player_in_selection), IF(gaming_player_selections_player_cache.expiry_date<NOW(),0,1), 0),
								  gaming_player_selections_player_cache.last_updated=NOW();
  COMMIT AND CHAIN;
 
 
  SET noficationEnabled=0;
  SELECT value_bool INTO noficationEnabled FROM gaming_settings WHERE name='NOTIFICATION_ENABLED';  

  IF (noficationEnabled) THEN
    INSERT INTO notifications_events (notification_event_type_id, event_id) 
    SELECT notification_event_type_id, bonusInstanceID
    FROM notifications_event_types
	WHERE event_name='BonusAwarded';
  END IF;
 
  COMMIT AND CHAIN;

END$$

DELIMITER ;

