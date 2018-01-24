DROP procedure IF EXISTS `BonusCheckPreDepositIfBonusMet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusCheckPreDepositIfBonusMet`(clientStatID BIGINT, depositAmount DECIMAL(18, 5), paymentMethod VARCHAR(30), bonusRuleID BIGINT, bonusCode VARCHAR(45), OUT willAwardBonusWithRuleID INT, OUT statusCode INT)
root:BEGIN
  
  
  DECLARE willAwardBonus, selectedBonusNotApplicableAwardOtherBonus TINYINT(1) DEFAULT 0;
  DECLARE bonusRuleGetCounterID, clientStatIDCheck, currencyID, bonusRuleIDSelected, paymentMethodID, bonusCount BIGINT DEFAULT -1;
  
  SELECT value_bool INTO selectedBonusNotApplicableAwardOtherBonus FROM gaming_settings WHERE name='BONUS_DEPOSIT_BONUS_NOTAPPLICABLE_AWARD_OTHERBONUS';
  
  SELECT client_stat_id, currency_id INTO clientStatIDCheck, currencyID    
  FROM gaming_client_stats
  WHERE client_stat_id=clientStatID; 
  
  SELECT IFNULL(parent_payment_method_id, payment_method_id) INTO paymentMethodID FROM gaming_payment_method WHERE name=paymentMethod LIMIT 1;
  
  IF (clientStatIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  IF(bonusCode IS NOT NULL) THEN 
	SELECT COUNT(bonus_rule_id) INTO bonusCount FROM gaming_bonus_rules WHERE voucher_code=bonusCode AND is_active=1 ORDER BY bonus_rule_id DESC LIMIT 1;

	SELECT bonus_rule_id INTO bonusRuleID FROM gaming_bonus_rules WHERE voucher_code=bonusCode AND is_active=1 AND bonusCount <= 1 ORDER BY bonus_rule_id DESC LIMIT 1;
  END IF;
  
  INSERT INTO gaming_bonus_rule_get_counter (date_added) VALUES (NOW());
  SET bonusRuleGetCounterID=LAST_INSERT_ID();
  
  SET @order_no=0;
  INSERT INTO gaming_bonus_rule_get_counter_rules (bonus_rule_get_counter_id, bonus_rule_id, order_no) 
  SELECT bonusRuleGetCounterID, bonus_rule_id, @order_no:=@order_no+1 
  FROM
  (
    SELECT bonus_rule_id, interval_repeat_until_awarded 
           
    FROM 
    (
      SELECT gaming_bonus_rules_deposits.is_percentage, gaming_bonus_rules_deposits.interval_repeat_until_awarded, 
        IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, 
        gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_rules.bonus_rule_id, gaming_client_stats.client_stat_id, 
		IF(is_percentage, MathSaturate(depositAmount*IFNULL(IFNULL(deposit_ranges.percentage, gaming_bonus_rules_deposits_percentages.percentage), gaming_bonus_rules_deposits.percentage), percentage_max_amount), IFNULL(deposit_ranges.amount, fixed_amount)) AS bonus_amount,
        occurrence_num_min, occurrence_num_max, gaming_bonus_awarding_interval_types.name AS awarding_interval_type,max_amount,award_bonus_max,
        CASE 
          WHEN gaming_bonus_awarding_interval_types.name='FIRST_BONUS' THEN activation_start_date 
          WHEN gaming_bonus_awarding_interval_types.name='WEEK' THEN DateGetWeekStart()
          WHEN gaming_bonus_awarding_interval_types.name='MONTH' THEN DateGetMonthStart()
          WHEN gaming_bonus_awarding_interval_types.name='FIRST_EVER' THEN DateGetFirstEverStart()
		  WHEN gaming_bonus_awarding_interval_types.name='DAILY' THEN CURDATE()
        END AS bonus_filter_start_date,
        (SELECT COUNT(*) FROM gaming_bonus_instances WHERE gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID)
          AS bonuses_awarded_num,
        gaming_bonus_rules.priority,max_count_per_interval, is_generic
      FROM gaming_bonus_rules 
      JOIN gaming_bonus_rules_deposits ON 
        (gaming_bonus_rules.is_active AND allow_awarding_bonuses) AND 
        (NOW() BETWEEN activation_start_date AND activation_end_date) AND
        (gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_deposits.bonus_rule_id) AND
		(selectedBonusNotApplicableAwardOtherBonus=1 OR 
			((gaming_bonus_rules.bonus_rule_id=bonusRuleID AND bonusCount <= 1 ) OR (gaming_bonus_rules.voucher_code = bonusCode AND bonusCount > 1)))
      JOIN gaming_bonus_awarding_interval_types ON gaming_bonus_rules_deposits.bonus_awarding_interval_type_id=gaming_bonus_awarding_interval_types.bonus_awarding_interval_type_id
      LEFT JOIN gaming_player_selections_player_cache AS cache ON gaming_bonus_rules.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
      JOIN gaming_client_stats ON 
        gaming_client_stats.client_stat_id=clientStatID AND 
        IFNULL(cache.player_in_selection, PlayerSelectionIsPlayerInSelection(gaming_bonus_rules.player_selection_id,gaming_client_stats.client_stat_id))  
      JOIN gaming_bonus_rules_deposits_amounts ON 
        gaming_bonus_rules_deposits.bonus_rule_id=gaming_bonus_rules_deposits_amounts.bonus_rule_id 
        AND gaming_bonus_rules_deposits_amounts.currency_id=gaming_client_stats.currency_id
      LEFT JOIN gaming_bonus_rules_deposits_pay_methods AS pay_methods ON gaming_bonus_rules.bonus_rule_id=pay_methods.bonus_rule_id AND pay_methods.payment_method_id=paymentMethodID
	  LEFT JOIN gaming_bonus_rule_max_awarding ON gaming_bonus_rule_max_awarding.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND gaming_bonus_rule_max_awarding.currency_id=gaming_client_stats.currency_id
      LEFT JOIN gaming_bonus_rules_deposits_percentages ON gaming_bonus_rules_deposits.bonus_rule_id=gaming_bonus_rules_deposits_percentages.bonus_rule_id AND gaming_bonus_rules_deposits_percentages.deposit_occurrence_num=@depositOccurenceNumCur
      LEFT JOIN gaming_bonus_rules_deposits_ranges AS deposit_ranges ON gaming_bonus_rules_deposits.bonus_rule_id=deposit_ranges.bonus_rule_id AND deposit_ranges.currency_id=gaming_client_stats.currency_id AND (depositAmount BETWEEN deposit_ranges.min_deposit AND deposit_ranges.max_deposit)
      LEFT JOIN gaming_bonus_rules_weekdays ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_bonus_rules_weekdays.bonus_rule_id AND gaming_bonus_rules_weekdays.day_no = DAYOFWEEK(NOW())
	  WHERE (depositAmount>=min_deposit_amount) AND (gaming_bonus_rules_deposits.restrict_payment_method=0 OR pay_methods.payment_method_id IS NOT NULL) AND (gaming_bonus_rules_deposits.restrict_weekday = 0 OR gaming_bonus_rules_weekdays.day_no IS NOT NULL)
			AND ((bonusCode is not null AND bonusCode=gaming_bonus_rules.voucher_code) OR (gaming_bonus_rules.restrict_by_voucher_code=0))
      
    ) AS BD 
    WHERE 
    (awarding_interval_type IN ('WEEK','MONTH','DAILY') AND (award_bonus_max = 0 OR (BD.bonuses_awarded_num < award_bonus_max))  AND interval_repeat_until_awarded AND   
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
			
			IFNULL((SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
			FROM gaming_bonus_instances
			WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)),0) +
			
			IFNULL((SELECT COUNT(gaming_bonus_instances_pre.bonus_instance_pre_id) AS occurence_num_cur  
			FROM gaming_bonus_instances_pre
			WHERE (gaming_bonus_instances_pre.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID AND gaming_bonus_instances_pre.date_created >= BD.bonus_filter_start_date AND gaming_bonus_instances_pre.status=1)),0) 
		  )=0, 1)
		AND IF (max_amount IS NOT NULL,
			
		  IFNULL((
			SELECT SUM(gaming_bonus_instances.bonus_amount_given) AS occurence_num_cur  
			FROM gaming_bonus_instances
			WHERE ((bonus_rule_id=bonusRuleID AND bonusCount <= 1) 
						OR (bonusCount > 1 AND bonus_rule_id IN (SELECT bonus_rule_id FROM gaming_bonus_rules WHERE voucher_code = bonusCode)))
					AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date
		  ),0)+
		  IFNULL((
			SELECT SUM(gaming_bonus_instances_pre.bonus_amount)  
			FROM gaming_bonus_instances_pre
			WHERE (gaming_bonus_instances_pre.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID AND gaming_bonus_instances_pre.date_created >= BD.bonus_filter_start_date AND gaming_bonus_instances_pre.status=1)   
		  ),0) +
		  bonus_amount <= max_amount,1
		)
	AND 
	IF(max_count_per_interval IS NOT NULL,		
		( 
			
			IFNULL((SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
			FROM gaming_bonus_instances
			WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)),0) +
			
			IFNULL((SELECT COUNT(gaming_bonus_instances_pre.bonus_instance_pre_id) AS occurence_num_cur  
			FROM gaming_bonus_instances_pre
			WHERE (gaming_bonus_instances_pre.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID AND gaming_bonus_instances_pre.date_created >= BD.bonus_filter_start_date AND gaming_bonus_instances_pre.status=1)),0) 
		)<max_count_per_interval, 1
	 )
    )) OR
    (awarding_interval_type IN ('WEEK','MONTH','DAILY') AND (award_bonus_max = 0 OR (BD.bonuses_awarded_num < award_bonus_max))  AND interval_repeat_until_awarded=0 AND  
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
			
			IFNULL((SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
			FROM gaming_bonus_instances
			WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)),0) +
			
			IFNULL((SELECT COUNT(gaming_bonus_instances_pre.bonus_instance_pre_id) AS occurence_num_cur  
			FROM gaming_bonus_instances_pre
			WHERE (gaming_bonus_instances_pre.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID AND gaming_bonus_instances_pre.date_created >= BD.bonus_filter_start_date  AND gaming_bonus_instances_pre.status=1)),0)   
		  )=0, 
		  IFNULL((
			SELECT SUM(gaming_bonus_instances.bonus_amount_given) AS occurence_num_cur  
			FROM gaming_bonus_instances
			WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)   
		  ),0)+
		  IFNULL((
			SELECT SUM(gaming_bonus_instances_pre.bonus_amount)  
			FROM gaming_bonus_instances_pre
			WHERE (gaming_bonus_instances_pre.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID AND gaming_bonus_instances_pre.date_created >= BD.bonus_filter_start_date AND gaming_bonus_instances_pre.status=1)   
		  ),0) +
		  bonus_amount <= max_amount
		) AND 
      ( 
        SELECT COUNT(gaming_transactions.transaction_id) AS occurence_num_cur  
        FROM gaming_transactions
        JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id 
        WHERE (gaming_transactions.client_stat_id=clientStatID AND gaming_transactions.timestamp >= BD.bonus_filter_start_date)  
      )=0
    )) OR
    (awarding_interval_type IN ('FIRST_BONUS','FIRST_EVER') AND (award_bonus_max = 0 OR (BD.bonuses_awarded_num < award_bonus_max)) AND
    (
      
      
      ( 
        SELECT COUNT(gaming_transactions.transaction_id)+1 AS occurence_num_cur 
        FROM gaming_transactions
        JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id 
        WHERE (gaming_transactions.client_stat_id=clientStatID AND gaming_transactions.timestamp >= BD.bonus_filter_start_date)  
      ) BETWEEN BD.occurrence_num_min AND occurrence_num_max 
    ))
    ORDER BY BD.priority ASC, BD.expiry_date DESC
  ) AS XX;
  
  SET willAwardBonusWithRuleID=0;
  SELECT 1 INTO willAwardBonusWithRuleID
  FROM gaming_bonus_rule_get_counter_rules
  WHERE bonus_rule_get_counter_id=bonusRuleGetCounterID 
		AND   ((bonus_rule_id=bonusRuleID AND bonusCount <= 1) 
				OR (bonusCount > 1 AND bonus_rule_id IN (SELECT bonus_rule_id FROM gaming_bonus_rules WHERE voucher_code = bonusCode)))
  LIMIT 1;
  
  IF (willAwardBonusWithRuleID=0 AND bonusRuleID!=0  AND selectedBonusNotApplicableAwardOtherBonus=0) THEN
    DELETE FROM gaming_bonus_rule_get_counter_rules WHERE bonus_rule_get_counter_id=bonusRuleGetCounterID;  
  ELSE
    SELECT bonus_rule_id INTO bonusRuleIDSelected
    FROM gaming_bonus_rule_get_counter_rules
    WHERE bonus_rule_get_counter_id=bonusRuleGetCounterID AND (willAwardBonusWithRuleID=0 OR bonus_rule_id=bonusRuleID)
    ORDER BY order_no
    LIMIT 1;
   
    IF (bonusRuleIDSelected!=-1) THEN
      DELETE FROM gaming_bonus_rule_get_counter_rules
      WHERE bonus_rule_get_counter_id=bonusRuleGetCounterID AND bonus_rule_id!=bonusRuleIDSelected;
    END IF;
  END IF;
  
  CALL BonusGetAllBonusesByRuleCounterIDAndCurrencyID(bonusRuleGetCounterID, currencyID, 0, 0);
  
  SET statusCode=0;
END root$$

DELIMITER ;

