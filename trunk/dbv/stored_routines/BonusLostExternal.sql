DROP procedure IF EXISTS `BonusLostExternal`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusLostExternal`(sessionID BIGINT,  bonusInstanceID BIGINT, evenIfSecured TINYINT(1), bonusLostType VARCHAR(80),lostAmount DECIMAL(18, 5),lostWinLockedAmount DECIMAL(18, 5), uniqueTransactionRef VARCHAR(45),OUT statusCode INT)
root: BEGIN
  
	/*
		Return codes:
		1-bonusInstanceID does not exist or does not belong to the specified customer
		2-provided transaction reference is not unique
	*/

  DECLARE bonusEnabledFlag TINYINT(1) DEFAULT 0;
  DECLARE hasRecordsForTransactionRef,hasRecordsForTransactionRefAndBonusInstanceID INT;
  DECLARE bonusLostCounterID, clientStatIDCheck BIGINT DEFAULT -1;
  DECLARE clientStatID BIGINT;


  DECLARE exchangeRate,adjustmentAmount, adjustmentWinLockedAmount DECIMAL(18,5) DEFAULT 0.0;
  DECLARE curBonusAmount, curWinLockedAmount, curBonusTransferredTotal,RingFencedAmount,RingFencedAmountSB,RingFencedAmountCasino,RingFencedAmountPoker DECIMAL(18,5);

  
  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  
  SELECT count(*) INTO hasRecordsForTransactionRef FROM gaming_transactions WHERE unique_transaction_ref=uniqueTransactionRef;
  SELECT count(*) INTO hasRecordsForTransactionRefAndBonusInstanceID FROM gaming_transactions WHERE unique_transaction_ref=uniqueTransactionRef AND extra2_id=bonusInstanceID;
  SET hasRecordsForTransactionRef=IFNULL(hasRecordsForTransactionRef,0);
  SET hasRecordsForTransactionRefAndBonusInstanceID=IFNULL(hasRecordsForTransactionRefAndBonusInstanceID,0);
  
  SELECT cs.client_stat_id, 
			bonus_amount_remaining,
			current_win_locked_amount, 
			bonus_transfered_total ,
			IFNULL(IF(ring_fenced_by_bonus_rules,bi.current_ring_fenced_amount,0),0),
			IFNULL(IF(ring_fenced_by_license_type=3,bi.current_ring_fenced_amount,0),0),
			IFNULL(IF(ring_fenced_by_license_type=1,bi.current_ring_fenced_amount,0),0),
			IFNULL(IF(ring_fenced_by_license_type=2,bi.current_ring_fenced_amount,0),0)
		INTO clientStatID, 
			curBonusAmount,
			curWinLockedAmount, 
			curBonusTransferredTotal,
			RingFencedAmount,
			RingFencedAmountSB,
			RingFencedAmountCasino,
			RingFencedAmountPoker 
	FROM gaming_bonus_instances bi 
	JOIN gaming_client_stats cs ON bi.client_stat_id=cs.client_stat_id 
	JOIN gaming_clients c ON c.client_id=cs.client_id
	JOIN sessions_main sm ON sm.extra_id=c.client_id AND sm.active=1
	LEFT JOIN gaming_bonus_rules_deposits dep ON dep.bonus_rule_id = bi.bonus_rule_id
	WHERE bonus_instance_id=bonusInstanceID AND (c.ext_client_id=sessionID OR sm.session_id=sessionID);

	IF(clientStatID IS NULL) THEN
		SET statusCode=1;
		LEAVE root;
	END IF;

	IF(hasRecordsForTransactionRef>0) THEN
		IF(hasRecordsForTransactionRefAndBonusInstanceID<=0) THEN
			SET statusCode=2;
			LEAVE root;
		END IF;
		SET statusCode=0;
		 SELECT ROUND(current_real_balance+IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance, 0)+IFNULL(FreeRounds.free_rounds_balance, 0), 0) AS current_balance, current_real_balance, 
			 ROUND(IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance, 0)+IFNULL(FreeRounds.free_rounds_balance, 0),0) AS current_bonus_balance, gaming_currency.currency_code, ROUND(pl_exchange_rate.exchange_rate/gm_exchange_rate.exchange_rate,5) AS exchange_rate,
			gaming_client_stats.current_ring_fenced_amount, gaming_client_stats.current_ring_fenced_sb, gaming_client_stats.current_ring_fenced_casino, gaming_client_stats.current_ring_fenced_poker,1 as already_processed
		  FROM gaming_client_stats  
		  JOIN gaming_currency ON client_stat_id=clientStatID AND gaming_client_stats.currency_id=gaming_currency.currency_id 
		  LEFT JOIN
		  (
			SELECT SUM(gbi.bonus_amount_remaining) AS current_bonus_balance, SUM(gbi.current_win_locked_amount) AS current_bonus_win_locked_balance
			FROM gaming_bonus_instances AS gbi
			WHERE  (gbi.client_stat_id=clientStatID AND gbi.is_active=1) 
		  ) AS Bonuses ON 1=1
		  LEFT JOIN
		  (
			SELECT SUM(num_rounds_remaining * gbrfra.max_bet) AS free_rounds_balance 
			FROM gaming_bonus_free_rounds AS gbfr
			JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gbfr.client_stat_id=gaming_client_stats.client_stat_id AND gbfr.is_active
			JOIN gaming_bonus_rules_free_rounds_amounts AS gbrfra ON gbfr.bonus_rule_id=gbrfra.bonus_rule_id AND gbrfra.currency_id=gaming_client_stats.currency_id
		  ) AS FreeRounds ON 1=1
		  JOIN gaming_operators ON gaming_operators.is_main_operator=1
		  LEFT JOIN gaming_currency AS gm_currency ON gm_currency.currency_code=gaming_operators.currency_id
		  LEFT JOIN gaming_operator_currency AS gm_exchange_rate ON gaming_operators.operator_id=gm_exchange_rate.operator_id AND gm_currency.currency_id=gm_exchange_rate.currency_id 
		  LEFT JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=gaming_currency.currency_id; 
		LEAVE root;
	END IF;
  
  
  IF NOT (bonusEnabledFlag) THEN
    SELECT bonusLostCounterID;
    LEAVE root;
  END IF;

 	IF(lostAmount IS NOT NULL) THEN
		IF(lostAmount<>curBonusAmount) THEN
			SET adjustmentAmount = lostAmount-curBonusAmount;
		END IF;
		SET curBonusAmount=lostAmount;
		SET curBonusTransferredTotal=lostAmount;
	END IF;

	IF(lostWinLockedAmount IS NOT NULL) THEN
		IF(lostWinLockedAmount<>curWinLockedAmount) THEN
			SET adjustmentWinLockedAmount = lostWinLockedAmount-curWinLockedAmount;
		END IF;
		SET curWinLockedAmount=lostWinLockedAmount;
	END IF;


	SELECT exchange_rate INTO exchangeRate
	FROM gaming_operators 
	JOIN gaming_operator_currency ON gaming_operators.operator_id=gaming_operator_currency.operator_id
	JOIN gaming_client_stats AS gcs ON gcs.client_stat_id=clientStatID AND gcs.currency_id=gaming_operator_currency.currency_id
	WHERE gaming_operators.is_main_operator=1;


	CALL BonusAdjustBalance(clientStatID, sessionID, 'BonusAdjustment', exchangeRate, bonusInstanceID , adjustmentAmount , adjustmentWinLockedAmount, 0.0, 0.0, 0.0, 0.0);
	
  
  SELECT client_stat_id INTO clientStatID 
  FROM gaming_bonus_instances 
  WHERE bonus_instance_id=bonusInstanceID;
  
  SELECT client_stat_id INTO clientStatIDCheck
  FROM gaming_client_stats
  WHERE client_stat_id=clientStatID
  FOR UPDATE;
  
	INSERT INTO gaming_bonus_lost_counter (date_created)
  VALUES (NOW());
  
  SET bonusLostCounterID=LAST_INSERT_ID();
  
  
  INSERT INTO gaming_bonus_lost_counter_bonus_instances(bonus_lost_counter_id, bonus_instance_id)
  SELECT bonusLostCounterID, bonus_instance_id
  FROM gaming_bonus_instances
  WHERE 
    gaming_bonus_instances.client_stat_id=clientStatID AND
    (bonusInstanceID=0 OR gaming_bonus_instances.bonus_instance_id=bonusInstanceID) AND 
    ((NOT is_secured OR evenIfSecured) AND NOT is_lost); 
  
  
  IF (ROW_COUNT() > 0) THEN 
    CALL BonusOnLostUpdateStats(bonusLostCounterID, bonusLostType, sessionID, sessionID, NULL,1,uniqueTransactionRef); 
  END IF;

  SET statusCode=0;
 
  SELECT ROUND(current_real_balance+IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance, 0)+IFNULL(FreeRounds.free_rounds_balance, 0), 0) AS current_balance, current_real_balance, 
  ROUND(IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance, 0)+IFNULL(FreeRounds.free_rounds_balance, 0),0) AS current_bonus_balance, gaming_currency.currency_code, ROUND(pl_exchange_rate.exchange_rate/gm_exchange_rate.exchange_rate,5) AS exchange_rate,
	gaming_client_stats.current_ring_fenced_amount, gaming_client_stats.current_ring_fenced_sb, gaming_client_stats.current_ring_fenced_casino, gaming_client_stats.current_ring_fenced_poker, 0 as already_processed
  FROM gaming_client_stats  
  JOIN gaming_currency ON client_stat_id=clientStatID AND gaming_client_stats.currency_id=gaming_currency.currency_id 
  LEFT JOIN
  (
	SELECT SUM(gbi.bonus_amount_remaining) AS current_bonus_balance, SUM(gbi.current_win_locked_amount) AS current_bonus_win_locked_balance
	FROM gaming_bonus_instances AS gbi
	WHERE  (gbi.client_stat_id=clientStatID AND gbi.is_active=1) 
  ) AS Bonuses ON 1=1
  LEFT JOIN
  (
	SELECT SUM(num_rounds_remaining * gbrfra.max_bet) AS free_rounds_balance 
	FROM gaming_bonus_free_rounds AS gbfr
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gbfr.client_stat_id=gaming_client_stats.client_stat_id AND gbfr.is_active
	JOIN gaming_bonus_rules_free_rounds_amounts AS gbrfra ON gbfr.bonus_rule_id=gbrfra.bonus_rule_id AND gbrfra.currency_id=gaming_client_stats.currency_id
  ) AS FreeRounds ON 1=1
  JOIN gaming_operators ON gaming_operators.is_main_operator=1
  LEFT JOIN gaming_currency AS gm_currency ON gm_currency.currency_code=gaming_operators.currency_id
  LEFT JOIN gaming_operator_currency AS gm_exchange_rate ON gaming_operators.operator_id=gm_exchange_rate.operator_id AND gm_currency.currency_id=gm_exchange_rate.currency_id 
  LEFT JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=gaming_currency.currency_id; 

END root$$

DELIMITER ;

