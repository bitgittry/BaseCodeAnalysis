DROP procedure IF EXISTS `BonusGetBonusesWhichPlayerCanAchieve`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetBonusesWhichPlayerCanAchieve`(clientStatID BIGINT, currencyID BIGINT)
BEGIN
	DECLARE bonusRuleGetCounterID BIGINT DEFAULT -1;
  
  CALL PlayerSelectionUpdatePlayerCache(clientStatID);
  
  
  INSERT INTO gaming_bonus_rule_get_counter (date_added) VALUES (NOW());
  SET bonusRuleGetCounterID=LAST_INSERT_ID();
  
  INSERT INTO gaming_bonus_rule_get_counter_rules (bonus_rule_get_counter_id, bonus_rule_id, filter_start_date, player_selection_id, player_in_selection) 
  SELECT bonusRuleGetCounterID, BD.bonus_rule_id, BD.bonus_filter_start_date, player_selection_id, IFNULL(player_in_selection, PlayerSelectionIsPlayerInSelection(player_selection_id, clientStatID))
  FROM
  (
    SELECT gaming_bonus_rules.bonus_rule_id, IF(gaming_bonus_rules_deposits.bonus_rule_id IS NULL, 0, 1) is_deposit, IF(gaming_bonus_rules_logins.bonus_rule_id IS NULL, 0, 1) is_login, 
    gaming_bonus_rules_deposits.occurrence_num_min AS deposit_occurrence_num_min, gaming_bonus_rules_deposits.occurrence_num_max AS deposit_occurrence_num_max, 
    gaming_bonus_rules_logins.occurrence_num_min AS login_occurrence_num_min, gaming_bonus_rules_logins.occurrence_num_max AS login_occurrence_num_max, 
    gaming_bonus_awarding_interval_types.name AS awarding_interval_type, clientStatID AS client_stat_id, gaming_bonus_rules.player_selection_id, cache.player_in_selection,max_amount,
    CASE 
      WHEN gaming_bonus_awarding_interval_types.name='FIRST_BONUS' THEN activation_start_date 
      WHEN gaming_bonus_awarding_interval_types.name='WEEK' THEN DateGetWeekStart()
      WHEN gaming_bonus_awarding_interval_types.name='MONTH' THEN DateGetMonthStart()
      WHEN gaming_bonus_awarding_interval_types.name='FIRST_EVER' THEN DateGetFirstEverStart()
	  WHEN gaming_bonus_awarding_interval_types.name='DAILY' THEN CURDATE()
    END AS bonus_filter_start_date,
(SELECT COUNT(*) FROM gaming_bonus_instances WHERE gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID)
          AS bonuses_awarded_num, max_count_per_interval
    FROM gaming_bonus_rules 
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
    LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_deposits.bonus_rule_id     
    LEFT JOIN gaming_bonus_rules_logins ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_logins.bonus_rule_id 
    LEFT JOIN gaming_bonus_awarding_interval_types ON 
      gaming_bonus_rules_deposits.bonus_awarding_interval_type_id=gaming_bonus_awarding_interval_types.bonus_awarding_interval_type_id OR 
      gaming_bonus_rules_logins.bonus_awarding_interval_type_id=gaming_bonus_awarding_interval_types.bonus_awarding_interval_type_id 
    LEFT JOIN gaming_player_selections_player_cache AS cache ON gaming_bonus_rules.player_selection_id=cache.player_selection_id
	LEFT JOIN gaming_bonus_rule_max_awarding ON gaming_bonus_rule_max_awarding.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND gaming_bonus_rule_max_awarding.currency_id=gaming_client_stats.currency_id
    WHERE 
      activation_end_date >= NOW() AND allow_awarding_bonuses=1 AND is_active=1 AND is_hidden=0 
      AND (IFNULL(cache.player_in_selection, PlayerSelectionIsPlayerInSelection(gaming_bonus_rules.player_selection_id, clientStatID)))
  ) AS BD 
  WHERE
    (awarding_interval_type IN ('WEEK','MONTH','DAILY') AND interval_repeat_until_awarded AND   
		(
		  
		  IF (BD.occurrence_num_max =0,true,(BD.bonuses_awarded_num < BD.occurrence_num_max)) AND
		  (
			SELECT COUNT(gaming_transactions.transaction_id)+1 AS occurence_num_cur 
			FROM gaming_transactions
			JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id 
			WHERE (gaming_transactions.client_stat_id=clientStatID) 
		  ) >= BD.occurrence_num_min AND 
		  IF(max_amount IS NULL AND max_count_per_interval IS NULL,
			  ( 
				SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
				FROM gaming_bonus_instances
				WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)   
			  )=0, 1)
			AND IF (max_amount IS NOT NULL,
			  IFNULL((
				SELECT SUM(gaming_bonus_instances.bonus_amount_given) AS occurence_num_cur  
				FROM gaming_bonus_instances
				WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)   
			  ),0) < max_amount,1
			)  
			AND
		   IF(max_count_per_interval IS NOT NULL,

			   ( 
				SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
				FROM gaming_bonus_instances
				WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)   
			  ) < max_count_per_interval, 1
			) 
		)
	) OR
	(awarding_interval_type IN ('WEEK','MONTH','DAILY') AND interval_repeat_until_awarded=0 AND   
		(
		  
		  IF (BD.occurrence_num_max =0,true,(BD.bonuses_awarded_num < BD.occurrence_num_max)) AND
		  (
			SELECT COUNT(gaming_transactions.transaction_id)+1 AS occurence_num_cur 
			FROM gaming_transactions
			JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id 
			WHERE (gaming_transactions.client_stat_id=clientStatID) 
		  ) >= BD.occurrence_num_min AND 
		   IF(max_amount IS NULL,
			  ( 
				SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
				FROM gaming_bonus_instances
				WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)   
			  )=0, 
			  IFNULL((
				SELECT SUM(gaming_bonus_instances.bonus_amount_given) AS occurence_num_cur  
				FROM gaming_bonus_instances
				WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)   
			  ),0) < max_amount
			) AND 
		  ( 
			SELECT COUNT(gaming_transactions.transaction_id) AS occurence_num_cur 
			FROM gaming_transactions
			JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id 
			WHERE (gaming_transactions.client_stat_id=clientStatID AND gaming_transactions.timestamp >= BD.bonus_filter_start_date)  
		  )=0
		)
	)
    OR
    (awarding_interval_type IN ('FIRST_EVER','FIRST_BONUS') AND(
      ( 
        BD.is_deposit=0 OR  
        (
          SELECT COUNT(gaming_balance_history.client_stat_id) + 1 AS occurence_num_cur 
          FROM gaming_client_stats 
          LEFT JOIN gaming_balance_history ON gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.client_stat_id=gaming_balance_history.client_stat_id 
          JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' AND gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id 
          JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name='Accepted' AND gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id 
          WHERE 
            (gaming_balance_history.timestamp >= BD.bonus_filter_start_date)  
        ) BETWEEN BD.deposit_occurrence_num_min AND BD.deposit_occurrence_num_max 
      ) 
      AND 
      ( 
        BD.is_login=0 OR 
        (
          SELECT COUNT(extra_id) + 1 AS occurence_num_cur
          FROM gaming_client_stats 
          LEFT JOIN sessions_main ON 
            gaming_client_stats.client_stat_id=clientStatID AND 
            gaming_client_stats.client_stat_id=sessions_main.extra_id 
          WHERE 
            sessions_main.date_open >= BD.bonus_filter_start_date 
        ) BETWEEN BD.login_occurrence_num_min AND BD.login_occurrence_num_max 
      )  
    ));
  
  
  SELECT gaming_bonus_rule_get_counter_rules.bonus_rule_id, COUNT(gaming_bonus_rule_get_counter_rules.bonus_rule_id) AS deposit_occurence_num_cur 
  FROM gaming_client_stats 
  LEFT JOIN gaming_balance_history ON gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.client_stat_id=gaming_balance_history.client_stat_id 
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' AND gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id 
  JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name='Accepted' AND gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id 
  JOIN gaming_bonus_rule_get_counter_rules ON gaming_bonus_rule_get_counter_rules.bonus_rule_get_counter_id=bonusRuleGetCounterID 
  JOIN gaming_bonus_rules_deposits ON gaming_bonus_rule_get_counter_rules.bonus_rule_id=gaming_bonus_rules_deposits.bonus_rule_id 
  WHERE 
    (gaming_balance_history.timestamp >= gaming_bonus_rule_get_counter_rules.filter_start_date)  
  GROUP BY gaming_bonus_rule_get_counter_rules.bonus_rule_id;
  
  
  SELECT gaming_bonus_rule_get_counter_rules.bonus_rule_id, COUNT(gaming_bonus_rule_get_counter_rules.bonus_rule_id) AS login_occurence_num_cur
  FROM gaming_client_stats 
  LEFT JOIN sessions_main ON 
    gaming_client_stats.client_stat_id=clientStatID AND 
    gaming_client_stats.client_stat_id=sessions_main.extra_id 
  JOIN gaming_bonus_rule_get_counter_rules ON gaming_bonus_rule_get_counter_rules.bonus_rule_get_counter_id=bonusRuleGetCounterID 
  JOIN gaming_bonus_rules_logins ON gaming_bonus_rule_get_counter_rules.bonus_rule_id=gaming_bonus_rules_logins.bonus_rule_id 
  WHERE 
    sessions_main.date_open >= gaming_bonus_rule_get_counter_rules.filter_start_date 
  GROUP BY gaming_bonus_rule_get_counter_rules.bonus_rule_id;
  
  
  CALL BonusGetAllBonusesByRuleCounterIDAndCurrencyID(bonusRuleGetCounterID, currencyID, 0);
   
END$$

DELIMITER ;

