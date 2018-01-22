DROP procedure IF EXISTS `BonusGetPreDepositRules`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetPreDepositRules`(clientStatID BIGINT, OUT statusCode BIGINT)
root:BEGIN
	  
  -- For First Ever using num_deposits in gaming_client_stats. This optimizes the query and also caters for when importing players from another system but not all deposit transactions have been imported.
  -- Checking if pre-auth is enabled before running any queries on gaming_bonus_instances_pre
  -- Forcing indexes: super optimized 

  DECLARE bonusRuleGetCounterID, clientStatIDCheck, currencyID BIGINT DEFAULT -1;
  DECLARE numTotalDeposits INT DEFAULT 0;
  DECLARE bonusPreAuth TINYINT(1) DEFAULT 0;

  SELECT client_stat_id, currency_id, num_deposits INTO clientStatIDCheck, currencyID, numTotalDeposits   
  FROM gaming_client_stats
  WHERE client_stat_id=clientStatID; 

  IF (clientStatIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  CALL PlayerSelectionUpdatePlayerCacheBonus(clientStatID);

  SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';

  INSERT INTO gaming_bonus_rule_get_counter (date_added) VALUES (NOW());
  SET bonusRuleGetCounterID=LAST_INSERT_ID();
  
  INSERT INTO gaming_bonus_rule_get_counter_rules (bonus_rule_get_counter_id, bonus_rule_id) 
  SELECT bonusRuleGetCounterID, bonus_rule_id 
  FROM 
  (
    SELECT gaming_bonus_rules_deposits.is_percentage, gaming_bonus_rules_deposits.interval_repeat_until_awarded,
      IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, 
      gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_rules.bonus_rule_id, gaming_client_stats.client_stat_id, 
      occurrence_num_min, occurrence_num_max, gaming_bonus_awarding_interval_types.name AS awarding_interval_type,max_amount,award_bonus_max,
	  IF(is_percentage, gaming_bonus_rules_deposits.percentage*gaming_bonus_rules_deposits_amounts.min_deposit_amount, fixed_amount) AS bonus_amount,
      CASE 
        WHEN gaming_bonus_awarding_interval_types.name='FIRST_BONUS' THEN activation_start_date 
        WHEN gaming_bonus_awarding_interval_types.name='WEEK' THEN DateGetWeekStart()
        WHEN gaming_bonus_awarding_interval_types.name='MONTH' THEN DateGetMonthStart()
        WHEN gaming_bonus_awarding_interval_types.name='FIRST_EVER' THEN DateGetFirstEverStart()
		WHEN gaming_bonus_awarding_interval_types.name='DAILY' THEN CURDATE()
      END AS bonus_filter_start_date,
      (SELECT 
            (SELECT COUNT(*)
            FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
            WHERE gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID)
            +
            (SELECT COUNT(*)
            FROM gaming_bonus_instances_pre 
            WHERE gaming_bonus_instances_pre.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID
                  AND gaming_bonus_instances_pre.status = 1))
        AS bonuses_awarded_num,max_count_per_interval
    FROM gaming_bonus_rules 
    JOIN gaming_bonus_rules_deposits ON 
      (gaming_bonus_rules.is_active AND allow_awarding_bonuses) AND 
      (NOW() BETWEEN activation_start_date AND activation_end_date) AND
      gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_deposits.bonus_rule_id 
    JOIN gaming_bonus_awarding_interval_types ON gaming_bonus_rules_deposits.bonus_awarding_interval_type_id=gaming_bonus_awarding_interval_types.bonus_awarding_interval_type_id
    JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
	JOIN gaming_player_selections_player_cache AS cache FORCE INDEX (PRIMARY) ON gaming_bonus_rules.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID AND cache.player_in_selection=1
    JOIN gaming_bonus_rules_deposits_amounts ON gaming_bonus_rules_deposits.bonus_rule_id=gaming_bonus_rules_deposits_amounts.bonus_rule_id AND gaming_bonus_rules_deposits_amounts.currency_id=gaming_client_stats.currency_id 
	LEFT JOIN gaming_bonus_rule_max_awarding ON gaming_bonus_rule_max_awarding.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND gaming_bonus_rule_max_awarding.currency_id=gaming_client_stats.currency_id
	LEFT JOIN gaming_bonus_rules_weekdays ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_bonus_rules_weekdays.bonus_rule_id AND gaming_bonus_rules_weekdays.day_no = DAYOFWEEK(NOW())
	WHERE (gaming_bonus_rules.awarded_times_threshold IS NULL OR gaming_bonus_rules.awarded_times < gaming_bonus_rules.awarded_times_threshold) AND (gaming_bonus_rules_deposits.restrict_weekday = 0 OR gaming_bonus_rules_weekdays.day_no IS NOT NULL)        
  ) AS BD 
  WHERE 
    (awarding_interval_type IN ('WEEK','MONTH','DAILY') AND interval_repeat_until_awarded AND   
    (
      
      IF (BD.occurrence_num_max =0,true,(BD.bonuses_awarded_num < BD.occurrence_num_max)) AND
      (numTotalDeposits + 1) >= BD.occurrence_num_min AND 
	  IF(max_amount IS NULL AND max_count_per_interval IS NULL,
		  ( 
			
			IFNULL((SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
			FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
			WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)),0) 
			+
			IF (bonusPreAuth=0, 0,
				IFNULL((SELECT COUNT(gaming_bonus_instances_pre.bonus_instance_pre_id) AS occurence_num_cur  
				FROM gaming_bonus_instances_pre FORCE INDEX (player_rule_date_created)
				WHERE (gaming_bonus_instances_pre.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID AND gaming_bonus_instances_pre.date_created >= BD.bonus_filter_start_date AND gaming_bonus_instances_pre.status=1)),0) 
			)
		  )=0, 1)
		AND IF (max_amount IS NOT NULL,
			
		  IFNULL((
			SELECT SUM(gaming_bonus_instances.bonus_amount_given) AS occurence_num_cur  
			FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
			WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)   
		  ),0)+ 
		  IF (bonusPreAuth=0, 0,	
		  IFNULL((
			SELECT SUM(gaming_bonus_instances_pre.bonus_amount)  
			FROM gaming_bonus_instances_pre FORCE INDEX (player_rule_date_created)
			WHERE (gaming_bonus_instances_pre.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID AND gaming_bonus_instances_pre.date_created >= BD.bonus_filter_start_date AND gaming_bonus_instances_pre.status=1)   
		  ),0)) +
		  bonus_amount <= max_amount,1
		)
		AND 
		IF(max_count_per_interval IS NOT NULL,		
			( 
				
				IFNULL((SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
				FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
				WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)),0) 
				+
				IF (bonusPreAuth=0, 0,
					IFNULL((SELECT COUNT(gaming_bonus_instances_pre.bonus_instance_pre_id) AS occurence_num_cur  
					FROM gaming_bonus_instances_pre FORCE INDEX (player_rule_date_created)
					WHERE (gaming_bonus_instances_pre.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID AND gaming_bonus_instances_pre.date_created >= BD.bonus_filter_start_date AND gaming_bonus_instances_pre.status=1)),0) 
				)
			)<max_count_per_interval, 1
		 )
    )) OR
    (awarding_interval_type IN ('WEEK','MONTH','DAILY') AND interval_repeat_until_awarded=0 AND   
    (
      
      IF (BD.occurrence_num_max =0,true,(BD.bonuses_awarded_num < BD.occurrence_num_max)) AND
      (numTotalDeposits + 1) >= BD.occurrence_num_min AND 
	  IF(max_amount IS NULL,
		  ( 
			IFNULL((SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
			FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
			WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)),0) 
			+
			IF (bonusPreAuth=0, 0,
				IFNULL((SELECT COUNT(gaming_bonus_instances_pre.bonus_instance_pre_id) AS occurence_num_cur  
				FROM gaming_bonus_instances_pre FORCE INDEX (player_rule_date_created)
				WHERE (gaming_bonus_instances_pre.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID AND gaming_bonus_instances_pre.date_created >= BD.bonus_filter_start_date  AND gaming_bonus_instances_pre.status=1)),0)   
			)
		  )=0, 
		  IFNULL((
			SELECT SUM(gaming_bonus_instances.bonus_amount_given) AS occurence_num_cur  
			FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
			WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)   
		  ),0)+
		  IF (bonusPreAuth=0, 0,	
		  IFNULL((
			SELECT SUM(gaming_bonus_instances_pre.bonus_amount)  
			FROM gaming_bonus_instances_pre FORCE INDEX (player_rule_date_created)
			WHERE (gaming_bonus_instances_pre.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID AND gaming_bonus_instances_pre.date_created >= BD.bonus_filter_start_date AND gaming_bonus_instances_pre.status=1)   
		  ),0)) +
		  bonus_amount <= max_amount) AND 
      ( 
        SELECT COUNT(gaming_transactions.transaction_id) AS occurence_num_cur 
        FROM gaming_transactions  FORCE INDEX (player_transaction_type)
        JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit'
        WHERE (gaming_transactions.client_stat_id=clientStatID  AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND gaming_transactions.timestamp >= BD.bonus_filter_start_date)  
      )=0
    )) OR
    (awarding_interval_type IN ('FIRST_BONUS','FIRST_EVER')  AND ((award_bonus_max = 0) OR (BD.bonuses_awarded_num <award_bonus_max)) AND
    (
	  IF (awarding_interval_type IN ('FIRST_EVER'), numTotalDeposits + 1,
      ( 
        SELECT COUNT(gaming_transactions.transaction_id)+1 AS occurence_num_cur 
        FROM gaming_transactions  FORCE INDEX (player_transaction_type)
        JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' 
        WHERE (gaming_transactions.client_stat_id=clientStatID AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND gaming_transactions.timestamp >= BD.bonus_filter_start_date)  
      )) BETWEEN BD.occurrence_num_min AND occurrence_num_max 
    ));
  
  CALL BonusGetAllBonusesByRuleCounterIDAndCurrencyID(bonusRuleGetCounterID, currencyID, 0, 0);
  
  SET statusCode=0;
END root$$

DELIMITER ;

