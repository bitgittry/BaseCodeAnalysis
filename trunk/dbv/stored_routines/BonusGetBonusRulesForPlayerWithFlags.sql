DROP procedure IF EXISTS `BonusGetBonusRulesForPlayerWithFlags`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetBonusRulesForPlayerWithFlags`(clientStatID BIGINT, currencyID BIGINT, returnManualBonus TINYINT(1), returnIfNotInSelection TINYINT(1), returnDirectGiveBonus TINYINT(1))
BEGIN
  -- using indices  
  -- optimized
  -- To Do: need to add pre-auth bonus checks by querying gaming_bonus_instances_pre
 
  DECLARE bonusRuleGetCounterID, clientID BIGINT DEFAULT -1;
  DECLARE systemStartDate DATETIME DEFAULT DateGetFirstEverStart(); 
  DECLARE numDeposits, numLogins INT DEFAULT 0;
  DECLARE bonusPreAuth TINYINT(1) DEFAULT 0;

  SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';

  CALL PlayerSelectionUpdatePlayerCacheBonus(clientStatID);
  
  SELECT client_id, num_deposits INTO clientID, numDeposits FROM gaming_client_stats WHERE client_stat_id=clientStatID;
  SELECT good_attempts INTO numLogins FROM gaming_clients_login_attempts_totals WHERE client_id=clientID LIMIT 1;

  INSERT INTO gaming_bonus_rule_get_counter (date_added) VALUES (NOW());
  SET bonusRuleGetCounterID=LAST_INSERT_ID();
  
  INSERT INTO gaming_bonus_rule_get_counter_rules (bonus_rule_get_counter_id, bonus_rule_id, filter_start_date, player_selection_id, player_in_selection) 
  SELECT bonusRuleGetCounterID, BD.bonus_rule_id, BD.bonus_filter_start_date, player_selection_id, IFNULL(player_in_selection, PlayerSelectionIsPlayerInSelection(player_selection_id, clientStatID))
  FROM
  (
    SELECT gaming_bonus_rules.bonus_rule_id, gaming_bonus_types.name AS bonus_type, activation_end_date, IF(gaming_bonus_rules_deposits.bonus_rule_id IS NULL, 0, 1) is_deposit, IF(gaming_bonus_rules_logins.bonus_rule_id IS NULL, 0, 1) is_login, 
    gaming_bonus_rules_deposits.occurrence_num_min AS deposit_occurrence_num_min, gaming_bonus_rules_deposits.occurrence_num_max AS deposit_occurrence_num_max, 
    gaming_bonus_rules_logins.occurrence_num_min AS login_occurrence_num_min, gaming_bonus_rules_logins.occurrence_num_max AS login_occurrence_num_max, 
    gaming_bonus_awarding_interval_types.name AS awarding_interval_type, clientStatID AS client_stat_id, is_manual_bonus, gaming_bonus_rules.player_selection_id, cache.player_in_selection,gaming_bonus_rules_deposits.interval_repeat_until_awarded,max_amount,award_bonus_max,
    CASE
      WHEN gaming_bonus_awarding_interval_types.name IS NULL THEN activation_start_date
      WHEN gaming_bonus_awarding_interval_types.name='FIRST_BONUS' THEN activation_start_date 
      WHEN gaming_bonus_awarding_interval_types.name='WEEK' THEN DateGetWeekStart() 
      WHEN gaming_bonus_awarding_interval_types.name='MONTH' THEN DateGetMonthStart()
      WHEN gaming_bonus_awarding_interval_types.name='FIRST_EVER' THEN systemStartDate
	  WHEN gaming_bonus_awarding_interval_types.name='DAILY' THEN CURDATE()
    END AS bonus_filter_start_date,
    (SELECT COUNT(*) FROM gaming_bonus_instances FORCE INDEX (player_rule_date) WHERE gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID)
      AS bonuses_awarded_num, max_count_per_interval, is_generic
    FROM gaming_bonus_rules FORCE INDEX (active_not_expired)
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
    JOIN gaming_player_selections_player_cache AS cache FORCE INDEX (PRIMARY) ON gaming_bonus_rules.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
	JOIN gaming_bonus_types ON gaming_bonus_rules.bonus_type_id = gaming_bonus_types.bonus_type_id
	LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_deposits.bonus_rule_id     
    LEFT JOIN gaming_bonus_rules_logins ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_logins.bonus_rule_id 
    LEFT JOIN gaming_bonus_awarding_interval_types ON 
      gaming_bonus_rules_deposits.bonus_awarding_interval_type_id=gaming_bonus_awarding_interval_types.bonus_awarding_interval_type_id OR 
      gaming_bonus_rules_logins.bonus_awarding_interval_type_id=gaming_bonus_awarding_interval_types.bonus_awarding_interval_type_id 
	LEFT JOIN gaming_bonus_rule_max_awarding ON gaming_bonus_rule_max_awarding.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND gaming_bonus_rule_max_awarding.currency_id=gaming_client_stats.currency_id
    WHERE 
	  (gaming_bonus_types.name != 'FreeRound' AND  gaming_bonus_rules.is_default = 0) AND
	  activation_end_date >= NOW() AND (allow_awarding_bonuses=1 OR (gaming_bonus_rules.bonus_type_id = 1 AND returnDirectGiveBonus = 1)) AND gaming_bonus_rules.is_active=1 AND is_hidden=0 
      AND (returnIfNotInSelection OR (IFNULL(cache.player_in_selection, 0)))
  ) AS BD 
  WHERE
    (is_manual_bonus=1 AND returnManualBonus=1) 
    OR (bonus_type IN ('Manual','DirectGive','FreeRound') AND  activation_end_date>NOW())
    OR (BD.is_deposit=0 AND BD.is_login=0 AND is_manual_bonus=0) 
 
    OR (awarding_interval_type IN ('WEEK','MONTH','DAILY') AND  
    (
      (BD.is_deposit=1 AND 
		(interval_repeat_until_awarded AND   
		(
		  IF (BD.deposit_occurrence_num_max =0,true,(BD.bonuses_awarded_num < BD.deposit_occurrence_num_max)) AND
		  (
			SELECT numDeposits+1 AS occurence_num_cur 
		  ) >= BD.deposit_occurrence_num_min AND 
		   IF(max_amount IS NULL AND max_count_per_interval IS NULL,
			  ( 
				SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
				FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
				WHERE (gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)   
			  )=0, 1)
			AND IF (max_amount IS NOT NULL,
			  IFNULL((
				SELECT SUM(gaming_bonus_instances.bonus_amount_given) AS occurence_num_cur  
				FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
				WHERE (gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)   
			  ),0) < max_amount,1
			)  
			AND
		   IF(max_count_per_interval IS NOT NULL,
			   ( 
				SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
				FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
				WHERE gaming_bonus_instances.client_stat_id=clientStatID AND (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)   
			  ) < max_count_per_interval, 1
			) 
		)
	) OR
	( interval_repeat_until_awarded=0 AND   
		(
		  IF (BD.deposit_occurrence_num_max =0,true,(BD.bonuses_awarded_num < BD.deposit_occurrence_num_max)) AND
		  (
			SELECT numDeposits+1 AS occurence_num_cur 
		  ) >= BD.deposit_occurrence_num_min AND 
		   IF(max_amount IS NULL,
			  ( 
				SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
				FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
				WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)   
			  )=0, 
			  IFNULL((
				SELECT SUM(gaming_bonus_instances.bonus_amount_given) AS occurence_num_cur  
				FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
				WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)   
			  ),0) < max_amount
			) AND 
		  ( 
			SELECT COUNT(gaming_transactions.transaction_id) AS occurence_num_cur 
			FROM gaming_transactions  FORCE INDEX (player_transaction_type)
			JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' AND 
				(gaming_transactions.client_stat_id=clientStatID AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id) 
			WHERE (gaming_transactions.timestamp >= BD.bonus_filter_start_date)  
		  )=0
		)
	))
	   ) OR 
      (BD.is_login=1 AND BD.bonuses_awarded_num < BD.login_occurrence_num_max) 
    )
    OR awarding_interval_type IN ('FIRST_BONUS','FIRST_EVER') AND (award_bonus_max = 0 OR (BD.bonuses_awarded_num < award_bonus_max)) AND
    (
      ( 
        BD.is_deposit=0 OR  
		IF (awarding_interval_type IN ('FIRST_EVER'), numDeposits+1,
        (
          SELECT COUNT(gaming_transactions.transaction_id) + 1 AS occurence_num_cur 
          FROM gaming_transactions FORCE INDEX (player_transaction_type)
          JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' AND 
			(gaming_transactions.client_stat_id=clientStatID AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id) 
          WHERE (gaming_transactions.timestamp >= BD.bonus_filter_start_date) 
        )) <= BD.deposit_occurrence_num_max 
      ) 
      AND 
      ( 
        BD.is_login=0 OR 
        IF (awarding_interval_type IN ('FIRST_EVER'), numLogins+1,
        (
          SELECT COUNT(extra_id) + 1 AS occurence_num_cur
          FROM sessions_main FORCE INDEX  (player_date_open)
          WHERE sessions_main.extra2_id=clientStatID AND sessions_main.date_open >= BD.bonus_filter_start_date 
        )) <= BD.login_occurrence_num_max 
      )  
    );
  
  SELECT gaming_bonus_rule_get_counter_rules.bonus_rule_id, numDeposits, IFNULL(deposit_occurence_num_cur, 0) AS deposit_occurence_num_cur
  FROM gaming_bonus_rule_get_counter_rules 
  JOIN gaming_bonus_rules_deposits ON gaming_bonus_rule_get_counter_rules.bonus_rule_get_counter_id=bonusRuleGetCounterID AND gaming_bonus_rule_get_counter_rules.bonus_rule_id=gaming_bonus_rules_deposits.bonus_rule_id
  LEFT JOIN
  (
    SELECT gaming_bonus_rule_get_counter_rules.bonus_rule_id, IF(gaming_bonus_rule_get_counter_rules.filter_start_date=systemStartDate, numDeposits, COUNT(gaming_bonus_rule_get_counter_rules.bonus_rule_id)) AS deposit_occurence_num_cur 
    FROM gaming_transactions FORCE INDEX (player_transaction_type)
    JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' AND 
		gaming_transactions.client_stat_id=clientStatID AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id 
    JOIN gaming_bonus_rule_get_counter_rules ON gaming_bonus_rule_get_counter_rules.bonus_rule_get_counter_id=bonusRuleGetCounterID 
    JOIN gaming_bonus_rules_deposits ON gaming_bonus_rule_get_counter_rules.bonus_rule_id=gaming_bonus_rules_deposits.bonus_rule_id 
    WHERE (gaming_transactions.timestamp >= gaming_bonus_rule_get_counter_rules.filter_start_date)  
    GROUP BY gaming_bonus_rule_get_counter_rules.bonus_rule_id
  ) AS NumDepositsInInterval ON gaming_bonus_rule_get_counter_rules.bonus_rule_id=NumDepositsInInterval.bonus_rule_id;
  
  
  SELECT gaming_bonus_rule_get_counter_rules.bonus_rule_id, numLogins, IFNULL(login_occurence_num_cur, 0) AS login_occurence_num_cur
  FROM gaming_bonus_rule_get_counter_rules 
  JOIN gaming_bonus_rules_logins ON gaming_bonus_rule_get_counter_rules.bonus_rule_get_counter_id=bonusRuleGetCounterID AND gaming_bonus_rule_get_counter_rules.bonus_rule_id=gaming_bonus_rules_logins.bonus_rule_id
  LEFT JOIN
  (
    SELECT gaming_bonus_rule_get_counter_rules.bonus_rule_id, IF(gaming_bonus_rule_get_counter_rules.filter_start_date=systemStartDate, numLogins, COUNT(gaming_bonus_rule_get_counter_rules.bonus_rule_id)) AS login_occurence_num_cur
    FROM gaming_bonus_rule_get_counter_rules 
    JOIN gaming_bonus_rules_logins ON gaming_bonus_rule_get_counter_rules.bonus_rule_get_counter_id=bonusRuleGetCounterID 
	  AND gaming_bonus_rule_get_counter_rules.bonus_rule_id=gaming_bonus_rules_logins.bonus_rule_id 
    JOIN sessions_main FORCE INDEX (player_date_open) ON sessions_main.extra2_id=clientStatID AND sessions_main.date_open >= gaming_bonus_rule_get_counter_rules.filter_start_date 
    GROUP BY gaming_bonus_rule_get_counter_rules.bonus_rule_id
  ) AS NumLoginsInInterval ON gaming_bonus_rule_get_counter_rules.bonus_rule_id=NumLoginsInInterval.bonus_rule_id;
  
  CALL BonusGetAllBonusesByRuleCounterIDAndCurrencyIDWithPlayerFlags(bonusRuleGetCounterID, clientStatID, currencyID, 0, returnManualBonus, returnIfNotInSelection);
   
END$$

DELIMITER ;

