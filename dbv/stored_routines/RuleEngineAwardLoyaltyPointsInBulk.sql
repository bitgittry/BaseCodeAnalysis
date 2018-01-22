DROP procedure IF EXISTS `RuleEngineAwardLoyaltyPointsInBulk`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleEngineAwardLoyaltyPointsInBulk`()
root: BEGIN

	DECLARE arrayCounterID, transactionCounterID BIGINT; 
  
	DECLARE noMoreRecords TINYINT(1) DEFAULT 0;
	DECLARE clientStatIDForCursor BIGINT DEFAULT -1;
  
	DECLARE txnCursor CURSOR FOR 
		SELECT gcs.client_stat_id 
		FROM gaming_clients_loyalty_points_transactions AS gclpt FORCE INDEX (array_counter_id)
        STRAIGHT_JOIN gaming_client_stats AS gcs ON gcs.client_id=gclpt.client_id AND gcs.is_active
		WHERE gclpt.array_counter_id = arrayCounterID;  
	DECLARE CONTINUE HANDLER FOR NOT FOUND
		SET noMoreRecords = 1;
  
	INSERT INTO gaming_array_counter (date_created) VALUES (NOW());
	SET arrayCounterID=LAST_INSERT_ID();
  
	INSERT INTO gaming_clients_loyalty_points_transactions (array_counter_id, client_id, time_stamp, rule_instance_id, amount, amount_total, rule_id, reason) 
	SELECT arrayCounterID, TransactionsData.client_id, NOW(), TransactionsData.rule_instance_id, 
		TransactionsData.LoyaltyPoints, TransactionsData.current_loyalty_points + TransactionsData.LoyaltyPoints,
		TransactionsData.rule_id, 'Rule Engine' 
	FROM
	(
		SELECT Points.value AS LoyaltyPoints, client_id,gaming_rules_instances.rule_instance_id, 
			gaming_rules_instances.rule_id, gaming_client_stats.current_loyalty_points 
		FROM gaming_rules_to_award
		STRAIGHT_JOIN gaming_rules_instances ON gaming_rules_to_award.awarded_state=2 AND 
			gaming_rules_instances.rule_instance_id=gaming_rules_to_award.rule_instance_id 
		STRAIGHT_JOIN gaming_rule_actions ON gaming_rules_instances.rule_id = gaming_rule_actions.rule_id
		STRAIGHT_JOIN 
		(
			SELECT value,rule_action_var_id,rule_action_id,rule_action_type_id 
            FROM gaming_rule_action_vars
			JOIN gaming_rule_action_types_var_types ON 
				gaming_rule_action_types_var_types.rule_action_type_var_id = gaming_rule_action_vars.rule_action_type_var_id AND 
                gaming_rule_action_types_var_types.name='LoyaltyPoints'
		) AS Points ON 
			Points.rule_action_id = gaming_rule_actions.rule_action_id
		STRAIGHT_JOIN gaming_rule_action_types ON gaming_rule_action_types.rule_action_type_id = Points.rule_action_type_id
		STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_rules_instances.client_stat_id
      WHERE gaming_rule_action_types.name='LoyaltyPoints'
	) AS TransactionsData
	
    UNION ALL
    
    SELECT arrayCounterID, referral_client_id,NOW(), TransactionsData.rule_instance_id,
		TransactionsData.LoyaltyPoints, TransactionsData.current_loyalty_points + TransactionsData.LoyaltyPoints,
        TransactionsData.rule_id, 'Rule Engine'
    FROM
	(
		SELECT Points.value AS LoyaltyPoints, gaming_clients.referral_client_id,gaming_rules_instances.rule_instance_id,
			gaming_rules_instances.rule_id, gaming_client_stats.current_loyalty_points  
		FROM gaming_rules_to_award
        STRAIGHT_JOIN gaming_rules_instances ON gaming_rules_to_award.awarded_state=2 AND 
			gaming_rules_instances.rule_instance_id=gaming_rules_to_award.rule_instance_id  
        STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_rules_instances.client_stat_id
        STRAIGHT_JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
        STRAIGHT_JOIN gaming_clients AS referral ON referral.client_id = gaming_clients.referral_client_id
        STRAIGHT_JOIN gaming_rule_actions ON gaming_rules_instances.rule_id = gaming_rule_actions.rule_id AND award_referral=1
        STRAIGHT_JOIN 
        (
			SELECT value,rule_action_var_id,rule_action_id,rule_action_type_id 
            FROM gaming_rule_action_vars
			JOIN gaming_rule_action_types_var_types ON 
				gaming_rule_action_types_var_types.rule_action_type_var_id = gaming_rule_action_vars.rule_action_type_var_id AND 
                gaming_rule_action_types_var_types.name='LoyaltyPoints'
		) AS Points ON Points.rule_action_id = gaming_rule_actions.rule_action_id
        STRAIGHT_JOIN gaming_rule_action_types ON gaming_rule_action_types.rule_action_type_id = Points.rule_action_type_id
        WHERE gaming_rule_action_types.name='LoyaltyPoints'
	) AS TransactionsData;
      
  IF (ROW_COUNT()=0) THEN
	LEAVE root;
  END IF;
   

 
  UPDATE 
  (
		SELECT SUM(AmountGiven.value) AS LoyaltyPointsG, SUM(IFNULL(AmountUsed.value,0)) AS LoyaltyPointsU, gaming_client_stats.client_id 
		FROM gaming_rules_to_award
		STRAIGHT_JOIN gaming_rules_instances ON gaming_rules_to_award.awarded_state=2 AND 
			gaming_rules_instances.rule_instance_id=gaming_rules_to_award.rule_instance_id 
		STRAIGHT_JOIN gaming_rule_actions ON gaming_rules_instances.rule_id = gaming_rule_actions.rule_id
        STRAIGHT_JOIN gaming_rule_action_types ON gaming_rule_action_types.rule_action_type_id = gaming_rule_actions.rule_action_type_id
		STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_rules_instances.client_stat_id
		LEFT JOIN 
        ( 
			SELECT value,rule_action_var_id,rule_action_id,rule_action_type_id 
            FROM gaming_rule_action_vars
			JOIN gaming_rule_action_types_var_types ON 
				gaming_rule_action_types_var_types.rule_action_type_var_id = gaming_rule_action_vars.rule_action_type_var_id AND 
                gaming_rule_action_types_var_types.name='LoyaltyPoints'
			WHERE `value`>0
		) AS AmountGiven ON AmountGiven.rule_action_id=gaming_rule_actions.rule_action_id
		LEFT JOIN 
        ( 
			SELECT value,rule_action_var_id,rule_action_id,rule_action_type_id
            FROM gaming_rule_action_vars
			JOIN gaming_rule_action_types_var_types ON 
				gaming_rule_action_types_var_types.rule_action_type_var_id = gaming_rule_action_vars.rule_action_type_var_id AND 
                gaming_rule_action_types_var_types.name='LoyaltyPoints'
		  WHERE `value`<0
		) AS AmountUsed ON AmountUsed.rule_action_id=gaming_rule_actions.rule_action_id
		WHERE gaming_rule_action_types.name='LoyaltyPoints'
		GROUP BY gaming_client_stats.client_id
		
        UNION ALL
		
        SELECT SUM(AmountGiven.value) AS LoyaltyPointsG, SUM(IFNULL(AmountUsed.value,0)) AS LoyaltyPointsU, referral.client_id 
		FROM gaming_rules_to_award
		STRAIGHT_JOIN gaming_rules_instances ON gaming_rules_to_award.awarded_state=2 AND 
			gaming_rules_instances.rule_instance_id=gaming_rules_to_award.rule_instance_id
		STRAIGHT_JOIN gaming_rule_actions ON gaming_rules_instances.rule_id = gaming_rule_actions.rule_id AND award_referral=1
        STRAIGHT_JOIN gaming_rule_action_types ON gaming_rule_action_types.rule_action_type_id = gaming_rule_actions.rule_action_type_id
		STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_rules_instances.client_stat_id
		STRAIGHT_JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
		STRAIGHT_JOIN gaming_clients AS referral ON referral.client_id = gaming_clients.referral_client_id
		LEFT JOIN 
        ( 
			SELECT value,rule_action_var_id,rule_action_id,rule_action_type_id FROM gaming_rule_action_vars
			JOIN gaming_rule_action_types_var_types ON 
				gaming_rule_action_types_var_types.rule_action_type_var_id = gaming_rule_action_vars.rule_action_type_var_id AND 
                gaming_rule_action_types_var_types.name='LoyaltyPoints'
			WHERE `value`>0
		) AS AmountGiven ON AmountGiven.rule_action_id=gaming_rule_actions.rule_action_id
		LEFT JOIN 
        ( 
			SELECT value,rule_action_var_id,rule_action_id,rule_action_type_id 
			FROM gaming_rule_action_vars
			JOIN gaming_rule_action_types_var_types ON 
				gaming_rule_action_types_var_types.rule_action_type_var_id = gaming_rule_action_vars.rule_action_type_var_id AND 
				gaming_rule_action_types_var_types.name='LoyaltyPoints'
		  WHERE `value`<0
		) AS AmountUsed ON AmountUsed.rule_action_id=gaming_rule_actions.rule_action_id
		WHERE gaming_rule_action_types.name='LoyaltyPoints'
		GROUP BY referral.client_id
  ) AS TransactionsData 
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_id=TransactionsData.client_id AND gaming_client_stats.is_active
  SET 
	total_loyalty_points_given = total_loyalty_points_given + LoyaltyPointsG,
	total_loyalty_points_used = total_loyalty_points_used - LoyaltyPointsU,
	current_loyalty_points = current_loyalty_points + LoyaltyPointsG - LoyaltyPointsU;
  
  INSERT INTO gaming_transaction_counter (date_created) VALUES (NOW());
  SET transactionCounterID=LAST_INSERT_ID();
  
  -- Gaming Transactions
  INSERT INTO gaming_transactions
	(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, 
	 amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, 
	 client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after,  
	 loyalty_points_after, extra_id, session_id, reason, pending_bet_real, 
	 pending_bet_bonus, withdrawal_pending_after, loyalty_points_bonus, loyalty_points_after_bonus, 
     transaction_counter_id) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, 0, 0, gaming_client_stats.currency_id, 0, 
	0, 0, 0, gclpt.amount, NOW(), 
	gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, 
	current_loyalty_points, gclpt.loyalty_points_transaction_id, null, 'Rule Engine', pending_bets_real, 
	pending_bets_bonus, withdrawal_pending_amount, 0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`),
    transactionCounterID
  FROM gaming_clients_loyalty_points_transactions AS gclpt FORCE INDEX (array_counter_id)
  STRAIGHT_JOIN gaming_rules_instances ON gclpt.rule_instance_id=gaming_rules_instances.rule_instance_id
  STRAIGHT_JOIN gaming_client_stats ON gaming_rules_instances.client_stat_id=gaming_client_stats.client_stat_id
  STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name = 'LoyaltyPoints'
  WHERE gclpt.array_counter_id = arrayCounterID;  

  INSERT INTO gaming_game_plays 
	(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, 
	 amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, 
	 balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, extra_id,
	 transaction_id, pending_bet_real, pending_bet_bonus, loyalty_points, loyalty_points_after,loyalty_points_bonus, loyalty_points_after_bonus) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, 
	amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, 
	balance_real_after, balance_bonus_after + balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, extra_id,
	gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points, loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus
  FROM gaming_transactions FORCE INDEX (transaction_counter_id)
  WHERE transaction_counter_id=transactionCounterID;
 
  -- For each player that was awarded loyalty points check if we need to do a VIP Level Progression
	OPEN txnCursor;
	allTxnLabel: LOOP 

		SET noMoreRecords=0;
		FETCH txnCursor INTO clientStatIDForCursor;
		IF (noMoreRecords) THEN
		  LEAVE allTxnLabel;
		END IF;
	  
		CALL PlayerUpdateVIPLevel(clientStatIDForCursor, 0);

	END LOOP allTxnLabel;
	CLOSE txnCursor;
  
END root$$

DELIMITER ;

