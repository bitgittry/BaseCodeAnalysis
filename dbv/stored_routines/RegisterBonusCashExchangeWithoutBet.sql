DROP procedure IF EXISTS `RegisterBonusCashExchangeWithoutBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RegisterBonusCashExchangeWithoutBet`(bonusInstanceID BIGINT, sessionID BIGINT, extClientID VARCHAR(80), 
  transactionType VARCHAR(45), awardedAmount DECIMAL(18, 5),awardedWinLockedAmount DECIMAL(18, 5),redeemReason VARCHAR(1024), 
  uniqueTransactionRef VARCHAR(45),OUT statusCode INT)
root:BEGIN

	/* 
		Return codes:
		1-bonusInstanceID does not exist or does not belong to the specified customer
		2-provided transaction reference is not unique
	*/ 
	DECLARE wagerRequirementMet TINYINT(1) DEFAULT 0;
	DECLARE clientStatID BIGINT;
	DECLARE adjustmentAmount, adjustmentWinLockedAmount DECIMAL(18,5) DEFAULT 0.0;
	DECLARE exchangeRate, bonusTransferred, bonusWinLockedTransferred, bonusTransferedTotal, 
		bonusTransferredLost, bonusWinLockedTransferredLost DECIMAL(18,5);
	DECLARE curBonusAmount, curWinLockedAmount, curBonusTransferredTotal, 
		RingFencedAmount, RingFencedAmountSB, RingFencedAmountCasino, RingFencedAmountPoker DECIMAL(18,5);
	DECLARE hasRecordsForTransactionRef, hasRecordsForTransactionRefAndBonusInstanceID INT;

	SELECT count(*) INTO hasRecordsForTransactionRef 
    FROM gaming_transactions 
    WHERE unique_transaction_ref=uniqueTransactionRef;
	
    SELECT count(*) INTO hasRecordsForTransactionRefAndBonusInstanceID 
    FROM gaming_transactions 
    WHERE unique_transaction_ref=uniqueTransactionRef AND extra2_id=bonusInstanceID;
    
	SET hasRecordsForTransactionRef=IFNULL(hasRecordsForTransactionRef,0);
	SET hasRecordsForTransactionRefAndBonusInstanceID=IFNULL(hasRecordsForTransactionRefAndBonusInstanceID,0);

	SELECT cs.client_stat_id, 
			bonus_amount_remaining,
			current_win_locked_amount, 
			bonus_transfered_total ,
			IFNULL(IF(ring_fenced_by_bonus_rules, bi.current_ring_fenced_amount,0),0),
			IFNULL(IF(ring_fenced_by_license_type=3, bi.current_ring_fenced_amount,0),0),
			IFNULL(IF(ring_fenced_by_license_type=1, bi.current_ring_fenced_amount,0),0),
			IFNULL(IF(ring_fenced_by_license_type=2,  bi.current_ring_fenced_amount,0),0)
		INTO clientStatID, 
			curBonusAmount,
			curWinLockedAmount, 
			curBonusTransferredTotal,
			RingFencedAmount,
			RingFencedAmountSB,
			RingFencedAmountCasino,
			RingFencedAmountPoker 
	FROM gaming_bonus_instances bi 
	STRAIGHT_JOIN gaming_client_stats cs ON bi.client_stat_id=cs.client_stat_id 
	STRAIGHT_JOIN gaming_clients c ON c.client_id=cs.client_id
	STRAIGHT_JOIN sessions_main sm ON sm.extra_id=c.client_id AND sm.active=1
	LEFT JOIN gaming_bonus_rules_deposits dep ON dep.bonus_rule_id = bi.bonus_rule_id
	WHERE bi.bonus_instance_id=bonusInstanceID AND (c.ext_client_id=extClientID OR sm.session_id=sessionID)
    LIMIT 1;
	
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
        
		SELECT ROUND(current_real_balance+IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance, 0), 0) AS current_balance, current_real_balance, 
			ROUND(IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance, 0),0) AS current_bonus_balance, 
            gaming_currency.currency_code, ROUND(pl_exchange_rate.exchange_rate/gm_exchange_rate.exchange_rate,5) AS exchange_rate,
			gaming_client_stats.current_ring_fenced_amount, gaming_client_stats.current_ring_fenced_sb, gaming_client_stats.current_ring_fenced_casino, 
            gaming_client_stats.current_ring_fenced_poker, 1 as already_processed
		FROM gaming_client_stats  
		STRAIGHT_JOIN gaming_currency ON client_stat_id=clientStatID AND gaming_client_stats.currency_id=gaming_currency.currency_id 
		LEFT JOIN
		(
			SELECT SUM(gbi.bonus_amount_remaining) AS current_bonus_balance, SUM(gbi.current_win_locked_amount) AS current_bonus_win_locked_balance
			FROM gaming_bonus_instances AS gbi FORCE INDEX (client_active_bonuses)
			WHERE (gbi.client_stat_id=clientStatID AND gbi.is_active=1) 
		) AS Bonuses ON 1=1
		JOIN gaming_operators ON gaming_operators.is_main_operator=1
		LEFT JOIN gaming_currency AS gm_currency ON gm_currency.currency_code=gaming_operators.currency_id
		LEFT JOIN gaming_operator_currency AS gm_exchange_rate ON gaming_operators.operator_id=gm_exchange_rate.operator_id AND gm_currency.currency_id=gm_exchange_rate.currency_id 
		LEFT JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=gaming_currency.currency_id; 

		LEAVE root;
	END IF;

	IF(transactionType='BonusRequirementMet') THEN
		SET wagerRequirementMet = 1;
	END IF;
	
	SELECT exchange_rate INTO exchangeRate
	FROM gaming_operators 
	JOIN gaming_operator_currency ON gaming_operators.operator_id=gaming_operator_currency.operator_id
	JOIN gaming_client_stats AS gcs ON gcs.client_stat_id=clientStatID AND gcs.currency_id=gaming_operator_currency.currency_id
	WHERE gaming_operators.is_main_operator=1
    LIMIT 1;

	IF(awardedAmount IS NOT NULL) THEN
		IF(awardedAmount<>curBonusAmount) THEN
			SET adjustmentAmount = awardedAmount-curBonusAmount;
		END IF;
		SET curBonusAmount=awardedAmount;
		SET curBonusTransferredTotal=awardedAmount;
	END IF;

	IF(awardedWinLockedAmount IS NOT NULL) THEN
		IF(awardedWinLockedAmount<>curWinLockedAmount) THEN
			SET adjustmentWinLockedAmount = awardedWinLockedAmount-curWinLockedAmount;
		END IF;
		SET curWinLockedAmount=awardedWinLockedAmount;
	END IF;


	CALL BonusAdjustBalance(clientStatID, sessionID, 'BonusAdjustment', exchangeRate, bonusInstanceID , adjustmentAmount , adjustmentWinLockedAmount, 0.0, 0.0, 0.0, 0.0);
	

	UPDATE gaming_bonus_instances AS gbi
		JOIN gaming_bonus_rules ON gbi.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
		JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
		SET gbi.bonus_amount_remaining=bonus_amount_remaining-curBonusAmount, 
		gbi.current_win_locked_amount=current_win_locked_amount-curWinLockedAmount, 
		gbi.is_active=IF(gbi.is_active=0,0,IF(wagerRequirementMet=1,0,1)), 
		gbi.is_secured=IF(wagerRequirementMet=1,1,is_secured), 
		gbi.secured_date=IF(wagerRequirementMet=1,NOW(),NULL), 
		gbi.bonus_transfered_total = gbi.bonus_transfered_total + (
			CASE transfer_type.name
				WHEN 'All' THEN curBonusAmount+curWinLockedAmount
				WHEN 'Bonus' THEN curBonusAmount
				WHEN 'BonusWinLocked' THEN curWinLockedAmount
				WHEN 'UpToBonusAmount' THEN LEAST(gbi.bonus_amount_given, curBonusAmount+curWinLockedAmount)
				WHEN 'UpToPercentage' THEN LEAST(gbi.bonus_amount_given*transfer_upto_percentage, curBonusAmount+curWinLockedAmount)
				WHEN 'ReleaseBonus' THEN LEAST(gbi.bonus_amount_given-gbi.bonus_transfered_total, curBonusAmount+curWinLockedAmount)
				WHEN 'ReleaseAllBonus' THEN curBonusAmount+curWinLockedAmount
				ELSE 0
			END),
		current_ring_fenced_amount=0
		WHERE bonus_instance_id=bonusInstanceID;

	SELECT 
		CASE transfer_type.name
			WHEN 'All' THEN curBonusAmount
			WHEN 'Bonus' THEN curBonusAmount
			WHEN 'BonusWinLocked' THEN 0
			WHEN 'UpToBonusAmount' THEN curBonusAmount/(curBonusAmount+curWinLockedAmount) *(gbi.bonus_transfered_total-curBonusTransferredTotal)
			WHEN 'UpToPercentage' THEN curBonusAmount/(curBonusAmount+curWinLockedAmount) *(gbi.bonus_transfered_total-curBonusTransferredTotal)
			WHEN 'ReleaseBonus' THEN curBonusAmount/(curBonusAmount+curWinLockedAmount) *(gbi.bonus_transfered_total-curBonusTransferredTotal)
			WHEN 'ReleaseAllBonus' THEN curBonusAmount
			ELSE 0
		END,
		CASE transfer_type.name
			WHEN 'All' THEN curWinLockedAmount
			WHEN 'Bonus' THEN 0
			WHEN 'BonusWinLocked' THEN curWinLockedAmount
			WHEN 'UpToBonusAmount' THEN curWinLockedAmount/(curBonusAmount+curWinLockedAmount) * (gbi.bonus_transfered_total-curBonusTransferredTotal)
			WHEN 'UpToPercentage' THEN curWinLockedAmount/(curBonusAmount+curWinLockedAmount) * (gbi.bonus_transfered_total-curBonusTransferredTotal)
			WHEN 'ReleaseBonus' THEN curWinLockedAmount/(curBonusAmount+curWinLockedAmount) * (gbi.bonus_transfered_total-curBonusTransferredTotal)
			WHEN 'ReleaseAllBonus' THEN curWinLockedAmount
			ELSE 0
		END INTO bonusTransferred, bonusWinLockedTransferred
	FROM gaming_bonus_instances AS gbi
	JOIN gaming_bonus_rules ON gbi.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
	WHERE bonus_instance_id=bonusInstanceID;

	SELECT curBonusAmount-bonusTransferred, curWinLockedAmount-bonusWinLockedTransferred, IFNULL(bonusTransferred+bonusWinLockedTransferred, 0) INTO bonusTransferredLost, bonusWinLockedTransferredLost, bonusTransferedTotal;
	
	CALL PlaceBetBonusCashExchange (clientStatID, null, sessionID, transactionType, exchangeRate, IFNULL(bonusTransferedTotal, 0), 
	   bonusTransferred, bonusWinLockedTransferred, bonusTransferredLost, bonusWinLockedTransferredLost,bonusInstanceID,RingFencedAmount,RingFencedAmountSB,RingFencedAmountCasino,RingFencedAmountPoker,uniqueTransactionRef);
	
	SET statusCode=0;
	
  SELECT ROUND(current_real_balance+IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance, 0), 0) AS current_balance, current_real_balance, 
     ROUND(IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance, 0), 0) AS current_bonus_balance, gaming_currency.currency_code, 
     ROUND(pl_exchange_rate.exchange_rate/gm_exchange_rate.exchange_rate,5) AS exchange_rate,
	gaming_client_stats.current_ring_fenced_amount, gaming_client_stats.current_ring_fenced_sb, gaming_client_stats.current_ring_fenced_casino, 
    gaming_client_stats.current_ring_fenced_poker, 0 as already_processed
  FROM gaming_client_stats  
  STRAIGHT_JOIN gaming_currency ON client_stat_id=clientStatID AND gaming_client_stats.currency_id=gaming_currency.currency_id 
  LEFT JOIN
  (
    SELECT SUM(gbi.bonus_amount_remaining) AS current_bonus_balance, SUM(gbi.current_win_locked_amount) AS current_bonus_win_locked_balance
    FROM gaming_bonus_instances AS gbi FORCE INDEX (client_active_bonuses)
    WHERE  (gbi.client_stat_id=clientStatID AND gbi.is_active=1) 
  ) AS Bonuses ON 1=1
  JOIN gaming_operators ON gaming_operators.is_main_operator=1
  LEFT JOIN gaming_currency AS gm_currency ON gm_currency.currency_code=gaming_operators.currency_id
  LEFT JOIN gaming_operator_currency AS gm_exchange_rate ON gaming_operators.operator_id=gm_exchange_rate.operator_id AND gm_currency.currency_id=gm_exchange_rate.currency_id 
  LEFT JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=gaming_currency.currency_id; 

END root$$

DELIMITER ;

