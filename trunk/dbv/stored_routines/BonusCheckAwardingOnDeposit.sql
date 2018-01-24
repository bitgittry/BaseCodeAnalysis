DROP procedure IF EXISTS `BonusCheckAwardingOnDeposit`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusCheckAwardingOnDeposit`(balanceHistoryID BIGINT, clientStatID BIGINT)
root: BEGIN
  -- Better check for awarded bonuses on this deposit 
  -- Getting only the latest bonus rule with the specified voucher 
  -- For First Ever using num_deposits in gaming_client_stats. This optimizes the query and also caters for when importing players from another system but not all deposit transactions have been imported.
  -- Checking if pre-auth is enabled before running any queries on gaming_bonus_instances_pre
  -- Forcing indexes: super optimized 

  DECLARE varDone,bonusEnabledFlag, bonusDepositEnabledFlag, alreadyGivenBonus, willAwardBonusWithRuleID, selectedBonusNotApplicableAwardOtherBonus, bonusPreAuth, restrictByVoucherCode,isDepositBonus TINYINT(1) DEFAULT 0;
  DECLARE balanceHistoryIDCheck, bonusRuleID, bonusRuleGetCounterID, bonusRuleIDSelected, bonusRuleIDSelectedCur, paymentMethodID BIGINT DEFAULT -1;
  DECLARE depositAmount DECIMAL(18, 5) DEFAULT 0; 
  DECLARE voucherCode VARCHAR(45);
  DECLARE numTotalDeposits INT DEFAULT 0;

  DECLARE bonusToAward CURSOR FOR
  SELECT bonus_rule_id,deposit_bonus FROM 
  (
	  SELECT bonus_rule_id,deposit_bonus,priority,datetime_created FROM 
	  (
		  SELECT child_bonus_rule_id AS bonus_rule_id, IF(deposit_counter_rules.bonus_rule_id IS NOT NULL,1,0) AS deposit_bonus,IFNULL(direct_give_rules_b.priority,deposit_rules.priority) AS priority,IFNULL(direct_give_rules_b.datetime_created,deposit_rules.datetime_created) AS datetime_created
		  FROM gaming_bonus_rules_bundles
		  LEFT JOIN gaming_bonus_rule_get_counter_rules AS deposit_counter_rules ON deposit_counter_rules.bonus_rule_id = gaming_bonus_rules_bundles.child_bonus_rule_id
		  LEFT JOIN gaming_bonus_rules_direct_gvs AS direct_give_rules ON direct_give_rules.bonus_rule_id = gaming_bonus_rules_bundles.child_bonus_rule_id
		  LEFT JOIN gaming_bonus_rules AS direct_give_rules_b ON direct_give_rules_b.bonus_rule_id = direct_give_rules.bonus_rule_id AND PlayerSelectionIsPlayerInSelection(direct_give_rules_b.player_selection_id,clientStatID)
		  LEFT JOIN gaming_bonus_rules AS deposit_rules ON deposit_rules.bonus_rule_id = gaming_bonus_rules_bundles.child_bonus_rule_id
		  WHERE (parent_bonus_rule_id=bonusRuleIDSelected OR deposit_rules.is_generic) AND (deposit_counter_rules.bonus_rule_id IS NOT NULL OR direct_give_rules_b.bonus_rule_id IS NOT NULL)  AND
		  ((deposit_counter_rules.bonus_rule_id IS NOT NULL AND deposit_counter_rules.bonus_rule_get_counter_id=bonusRuleGetCounterID ) OR (direct_give_rules_b.bonus_rule_id IS NOT NULL))
		  UNION
		  SELECT gaming_bonus_rules.bonus_rule_id,1,priority,datetime_created
		  FROM gaming_bonus_rule_get_counter_rules
		  JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = gaming_bonus_rule_get_counter_rules.bonus_rule_id 
		  WHERE (gaming_bonus_rules.bonus_rule_id = bonusRuleIDSelected OR gaming_bonus_rules.is_generic  OR voucher_code = voucherCode) AND gaming_bonus_rule_get_counter_rules.bonus_rule_get_counter_id=bonusRuleGetCounterID
	  ) AS a
	  ORDER BY priority,datetime_created
  )AS b;

DECLARE CONTINUE HANDLER FOR NOT FOUND SET varDone = TRUE; 


  -- INSERT INTO gaming_bonus_rule_get_counter_rules (bonus_rule_get_counter_id, bonus_rule_id, filter_start_date, order_no) VALUES(1,1,NOW(),1);

  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  SELECT value_bool INTO bonusDepositEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_DEPOSIT_ENABLED';
  SELECT value_bool INTO selectedBonusNotApplicableAwardOtherBonus FROM gaming_settings WHERE name='BONUS_DEPOSIT_BONUS_NOTAPPLICABLE_AWARD_OTHERBONUS';
  SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';
  
  IF (NOT (bonusEnabledFlag AND bonusDepositEnabledFlag)) THEN
    LEAVE root;
  END IF;
  
  SELECT num_deposits INTO numTotalDeposits FROM gaming_client_stats WHERE client_stat_id=clientStatID;

  CALL PlayerSelectionUpdatePlayerCacheBonus(clientStatID);
  
  SELECT balance_history_id, amount, selected_bonus_rule_id, payment_method_id, voucher_code  
  INTO balanceHistoryIDCheck, depositAmount, bonusRuleID, paymentMethodID, voucherCode 
  FROM gaming_balance_history  
  WHERE balance_history_id=balanceHistoryID AND client_stat_id=clientStatID AND gaming_balance_history.client_stat_balance_updated
  FOR UPDATE; 

  IF (balanceHistoryIDCheck<>balanceHistoryID) OR (bonusRuleID=-1 AND voucherCode IS NULL) THEN
    LEAVE root;
  END IF;

  SELECT IF(COUNT(bonus_instance_id) > 0, 1, 0) INTO alreadyGivenBonus 
  FROM gaming_bonus_instances FORCE INDEX (extra_id)
  JOIN gaming_bonus_rules_deposits ON gaming_bonus_instances.extra_id = balanceHistoryID AND gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules_deposits.bonus_rule_id
	AND gaming_bonus_instances.client_stat_id = clientStatID;

  IF (alreadyGivenBonus) THEN
    LEAVE root;
  END IF;
  
  IF (bonusPreAuth=1) THEN
	  SELECT IF(COUNT(bonus_instance_pre_id) > 0, 1, 0) INTO alreadyGivenBonus 
	  FROM gaming_bonus_instances_pre FORCE INDEX (extra_id) 
	  JOIN gaming_bonus_rules_deposits ON gaming_bonus_instances_pre.extra_id=balanceHistoryID AND gaming_bonus_instances_pre.bonus_rule_id=gaming_bonus_rules_deposits.bonus_rule_id
		AND gaming_bonus_instances_pre.client_stat_id = clientStatID;
	  
	  IF (alreadyGivenBonus) THEN
		LEAVE root;
	  END IF;
  END IF;
  
  SET voucherCode=TRIM(voucherCode); SET voucherCode=IF(voucherCode='', NULL, voucherCode);
  IF (voucherCode IS NOT NULL) THEN 
	SELECT bonus_rule_id INTO bonusRuleID FROM gaming_bonus_rules WHERE voucher_code=voucherCode AND is_active=1  AND PlayerSelectionIsPlayerInSelection(player_selection_id,clientStatID) 
	ORDER BY bonus_rule_id DESC LIMIT 1;
	
    IF (bonusRuleID IS NOT NULL AND bonusRuleID!=-1) THEN
		UPDATE gaming_balance_history SET selected_bonus_rule_id=bonusRuleID WHERE balance_history_id=balanceHistoryID;
	END IF;
  END IF;
  
  
  INSERT INTO gaming_bonus_rule_get_counter (date_added) VALUES (NOW());
  SET bonusRuleGetCounterID=LAST_INSERT_ID();
  

  SET @order_no=0;
  INSERT INTO gaming_bonus_rule_get_counter_rules (bonus_rule_get_counter_id, bonus_rule_id, filter_start_date, order_no) 
  SELECT bonusRuleGetCounterID, bonus_rule_id, deposit_occurrency_num_filter_start_date, @order_no:=@order_no+1
  FROM
  (
    SELECT bonus_rule_id, deposit_occurrency_num_filter_start_date, interval_repeat_until_awarded, is_generic
    FROM 
    (
      SELECT gaming_bonus_rules_deposits.is_percentage, gaming_bonus_rules_deposits.interval_repeat_until_awarded,
        IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, 
        gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_rules.bonus_rule_id, gaming_client_stats.client_stat_id, 
		IF(is_percentage, MathSaturate(depositAmount*IFNULL(IFNULL(deposit_ranges.percentage, gaming_bonus_rules_deposits_percentages.percentage), gaming_bonus_rules_deposits.percentage), percentage_max_amount), IFNULL(deposit_ranges.amount, fixed_amount)) AS bonus_amount,
        occurrence_num_min, occurrence_num_max, gaming_bonus_awarding_interval_types.name AS awarding_interval_type,max_amount,award_bonus_max, 
        CASE 
          WHEN gaming_bonus_awarding_interval_types.name='FIRST_BONUS' THEN activation_start_date 
		  WHEN gaming_bonus_awarding_interval_types.name='DAILY' THEN CURDATE()
          WHEN gaming_bonus_awarding_interval_types.name='WEEK' THEN DateGetWeekStart()
          WHEN gaming_bonus_awarding_interval_types.name='MONTH' THEN DateGetMonthStart()
          WHEN gaming_bonus_awarding_interval_types.name='FIRST_EVER' THEN DateGetFirstEverStart()
        END AS bonus_filter_start_date,
        CASE 
          WHEN gaming_bonus_awarding_interval_types.name='FIRST_BONUS' THEN activation_start_date 
		  WHEN gaming_bonus_awarding_interval_types.name='DAILY' THEN activation_start_date
          WHEN gaming_bonus_awarding_interval_types.name='WEEK' THEN activation_start_date
          WHEN gaming_bonus_awarding_interval_types.name='MONTH' THEN activation_start_date
          WHEN gaming_bonus_awarding_interval_types.name='FIRST_EVER' THEN DateGetFirstEverStart()
        END AS deposit_occurrency_num_filter_start_date,
        (SELECT 
            (SELECT COUNT(*)
            FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
            WHERE gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID)
            +
            (SELECT COUNT(*)
            FROM gaming_bonus_instances_pre 
            WHERE gaming_bonus_instances_pre.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID
                  AND gaming_bonus_instances_pre.status = 1))
          AS bonuses_awarded_num,
        gaming_bonus_rules.priority, max_count_per_interval, is_generic
      FROM gaming_bonus_rules 
      JOIN gaming_bonus_rules_deposits ON 
        (gaming_bonus_rules.is_active AND allow_awarding_bonuses) AND 
        (NOW() BETWEEN activation_start_date AND activation_end_date) AND
        gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_deposits.bonus_rule_id 
      JOIN gaming_bonus_awarding_interval_types ON gaming_bonus_rules_deposits.bonus_awarding_interval_type_id=gaming_bonus_awarding_interval_types.bonus_awarding_interval_type_id
      JOIN gaming_player_selections_player_cache AS cache FORCE INDEX (PRIMARY) ON gaming_bonus_rules.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID AND cache.player_in_selection=1
      JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID        
      JOIN gaming_bonus_rules_deposits_amounts ON gaming_bonus_rules_deposits.bonus_rule_id=gaming_bonus_rules_deposits_amounts.bonus_rule_id AND gaming_bonus_rules_deposits_amounts.currency_id=gaming_client_stats.currency_id      
	  LEFT JOIN gaming_bonus_rules_deposits_pay_methods AS pay_methods ON gaming_bonus_rules.bonus_rule_id=pay_methods.bonus_rule_id AND pay_methods.payment_method_id=paymentMethodID
	  LEFT JOIN gaming_bonus_rule_max_awarding ON gaming_bonus_rule_max_awarding.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND gaming_bonus_rule_max_awarding.currency_id=gaming_client_stats.currency_id
      LEFT JOIN gaming_bonus_rules_deposits_percentages ON gaming_bonus_rules_deposits.bonus_rule_id=gaming_bonus_rules_deposits_percentages.bonus_rule_id AND gaming_bonus_rules_deposits_percentages.deposit_occurrence_num=@depositOccurenceNumCur
      LEFT JOIN gaming_bonus_rules_deposits_ranges AS deposit_ranges ON gaming_bonus_rules_deposits.bonus_rule_id=deposit_ranges.bonus_rule_id AND deposit_ranges.currency_id=gaming_client_stats.currency_id AND (depositAmount BETWEEN deposit_ranges.min_deposit AND deposit_ranges.max_deposit)
      LEFT JOIN gaming_bonus_rules_weekdays ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_bonus_rules_weekdays.bonus_rule_id AND gaming_bonus_rules_weekdays.day_no = DAYOFWEEK(NOW())
	  WHERE (gaming_bonus_rules.awarded_times_threshold IS NULL OR gaming_bonus_rules.awarded_times < gaming_bonus_rules.awarded_times_threshold) AND (depositAmount>=min_deposit_amount) AND (gaming_bonus_rules_deposits.restrict_payment_method=0 OR pay_methods.payment_method_id IS NOT NULL) AND (gaming_bonus_rules_deposits.restrict_weekday = 0 OR gaming_bonus_rules_weekdays.day_no IS NOT NULL) 
			AND ((voucherCode is not null AND voucherCode=gaming_bonus_rules.voucher_code) OR (gaming_bonus_rules.restrict_by_voucher_code=0))
    ) AS BD 
    WHERE 
    (awarding_interval_type IN ('WEEK','MONTH','DAILY') AND interval_repeat_until_awarded AND ((award_bonus_max = 0) OR (BD.bonuses_awarded_num <award_bonus_max)) AND   
    (
      
      IF (BD.occurrence_num_max =0,true,(BD.bonuses_awarded_num < BD.occurrence_num_max)) AND
		numTotalDeposits >= BD.occurrence_num_min AND 
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
    (awarding_interval_type IN ('WEEK','MONTH','DAILY') AND interval_repeat_until_awarded=0 AND ((award_bonus_max = 0) OR (BD.bonuses_awarded_num <award_bonus_max)) AND   
    (
      
      IF (BD.occurrence_num_max =0,true,(BD.bonuses_awarded_num < BD.occurrence_num_max)) AND
		numTotalDeposits >= BD.occurrence_num_min AND 
      IF(max_amount IS NULL,
		  ( 
			
			IFNULL((SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
			FROM gaming_bonus_instances  FORCE INDEX (player_rule_date)
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
			FROM gaming_bonus_instances  FORCE INDEX (player_rule_date)
			WHERE (gaming_bonus_instances.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= BD.bonus_filter_start_date)   
		  ),0)+
		  IF (bonusPreAuth=0, 0, 
		  IFNULL((
			SELECT SUM(gaming_bonus_instances_pre.bonus_amount)  
			FROM gaming_bonus_instances_pre FORCE INDEX (player_rule_date_created)
			WHERE (gaming_bonus_instances_pre.bonus_rule_id=BD.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID AND gaming_bonus_instances_pre.date_created >= BD.bonus_filter_start_date AND gaming_bonus_instances_pre.status=1)   
		  ),0)) +
		  bonus_amount <= max_amount
		) AND 
      ( 
        SELECT COUNT(gaming_transactions.transaction_id) AS occurence_num_cur 
        FROM gaming_transactions FORCE INDEX (player_transaction_type)
        JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' 
		WHERE gaming_transactions.client_stat_id=clientStatID AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id  AND gaming_transactions.timestamp >= BD.bonus_filter_start_date  
      )=1
    )) OR
    (awarding_interval_type IN ('FIRST_BONUS','FIRST_EVER') AND ((award_bonus_max = 0) OR (BD.bonuses_awarded_num <award_bonus_max)) AND
    (
	  IF (awarding_interval_type IN ('FIRST_EVER'), numTotalDeposits,
      ( 
        SELECT COUNT(gaming_transactions.transaction_id) AS occurence_num_cur 
        FROM gaming_transactions FORCE INDEX (player_transaction_type)
        JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit'  
		WHERE gaming_transactions.client_stat_id=clientStatID AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND gaming_transactions.timestamp >= BD.bonus_filter_start_date 
      )) BETWEEN BD.occurrence_num_min AND occurrence_num_max 
    ))
    ORDER BY is_generic, BD.priority ASC, BD.expiry_date DESC
  ) AS XX;
  
  SET willAwardBonusWithRuleID=0;
  SELECT 1 INTO willAwardBonusWithRuleID
  FROM gaming_bonus_rule_get_counter_rules
  WHERE bonus_rule_get_counter_id=bonusRuleGetCounterID AND bonus_rule_id=bonusRuleID
  LIMIT 1;
  
  SELECT bonus_rule_id, filter_start_date INTO bonusRuleIDSelected, @filterStartDate
  FROM gaming_bonus_rule_get_counter_rules
  WHERE bonus_rule_get_counter_id=bonusRuleGetCounterID AND (willAwardBonusWithRuleID=0 OR bonus_rule_id=bonusRuleID)
  ORDER BY order_no
  LIMIT 1;

  IF (bonusRuleID!=0 AND willAwardBonusWithRuleID=0 AND selectedBonusNotApplicableAwardOtherBonus=0) THEN
    LEAVE root;
  END IF;
  
  IF (bonusRuleIDSelected!=-1) THEN
	OPEN bonusToAward;
	curser_loop: LOOP
		SET varDone=0;

		FETCH bonusToAward INTO bonusRuleIDSelectedCur,isDepositBonus;		
		IF varDone THEN
		  LEAVE curser_loop;
		END IF;

		IF (isDepositBonus) THEN
			CALL BonusGiveDepositBonus(bonusRuleIDSelectedCur,clientStatID,depositAmount,balanceHistoryID, @filterStartDate);
		ELSE
			CALL BonusGiveDirectGiveBonus(bonusRuleIDSelectedCur,clientStatID,balanceHistoryID, @bonusIntanceGenID);
		END IF;
	END LOOP;
    CLOSE bonusToAward;
  END IF; 

  DELETE FROM gaming_bonus_rule_get_counter_rules WHERE bonus_rule_get_counter_id=bonusRuleGetCounterID;

END root$$

DELIMITER ;

