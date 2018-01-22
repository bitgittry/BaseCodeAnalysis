DROP procedure IF EXISTS `BonusRedeemAllBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusRedeemAllBonus`(bonusInstanceID BIGINT, sessionID BIGINT, userID BIGINT, redeemReason VARCHAR(1024),transactionType VARCHAR(20), gamePlayID BIGINT)
BEGIN

	DECLARE clientStatID BIGINT;
	DECLARE exchangeRate DECIMAL(18,5);
	DECLARE curBonusAmount, curWinLockedAmount, curBonusTransferredTotal,RingFencedAmount,RingFencedAmountSB,RingFencedAmountCasino,RingFencedAmountPoker,bonusTransferedTotal DECIMAL(18,5);
	DECLARE WagerType VARCHAR(20);
	DECLARE RedeemThresholdEnabled TINYINT(1);

	
	SELECT value_string INTO WagerType FROM gaming_settings WHERE name = 'PLAY_WAGER_TYPE';

	SELECT client_stat_id, bonus_amount_remaining,current_win_locked_amount, bonus_transfered_total,
	IFNULL(IF(ring_fenced_by_bonus_rules,current_ring_fenced_amount,0),0),IFNULL(IF(ring_fenced_by_license_type=3,current_ring_fenced_amount,0),0),
	IFNULL(IF(ring_fenced_by_license_type=1,current_ring_fenced_amount,0),0),IFNULL(IF(ring_fenced_by_license_type=2,current_ring_fenced_amount,0),0),
	redeem_threshold_enabled 
	INTO clientStatID, curBonusAmount,curWinLockedAmount, curBonusTransferredTotal,RingFencedAmount,RingFencedAmountSB,RingFencedAmountCasino,RingFencedAmountPoker, RedeemThresholdEnabled
	FROM gaming_bonus_instances 
	LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_bonus_instances.bonus_rule_id
	LEFT JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
	WHERE bonus_instance_id=bonusInstanceID; 

    IF (curBonusAmount = 0 AND curWinLockedAmount = 0 AND WagerType = 'Type2') THEN 
		UPDATE gaming_bonus_instances AS gbi
		JOIN gaming_bonus_rules ON gbi.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
		JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
		SET gbi.bonus_amount_remaining=0, gbi.current_win_locked_amount=0, gbi.is_active=0, gbi.is_secured=0, gbi.secured_date=null, gbi.is_used_all=1, gbi.used_all_date=NOW(), gbi.redeem_reason=redeemReason, gbi.redeem_session_id=sessionID, gbi.redeem_user_id=userID, 
			gbi.bonus_transfered_total = gbi.bonus_transfered_total + curBonusAmount+curWinLockedAmount,current_ring_fenced_amount=0
		WHERE bonus_instance_id=bonusInstanceID;
	ELSE
		UPDATE gaming_bonus_instances AS gbi
		JOIN gaming_bonus_rules ON gbi.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
		JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
		SET gbi.bonus_amount_remaining=0, gbi.current_win_locked_amount=0, gbi.is_active=0, gbi.is_secured=1, gbi.secured_date=now(), gbi.redeem_reason=redeemReason, gbi.redeem_session_id=sessionID, gbi.redeem_user_id=userID, 
			gbi.bonus_transfered_total = gbi.bonus_transfered_total + curBonusAmount+curWinLockedAmount,current_ring_fenced_amount=0
		WHERE bonus_instance_id=bonusInstanceID;
	END IF;
	
	SELECT exchange_rate INTO exchangeRate
	FROM gaming_operators 
	JOIN gaming_operator_currency ON gaming_operators.operator_id=gaming_operator_currency.operator_id
	JOIN gaming_client_stats AS gcs ON gcs.client_stat_id=clientStatID AND gcs.currency_id=gaming_operator_currency.currency_id
	WHERE gaming_operators.is_main_operator=1;

	CALL PlaceBetBonusCashExchange (clientStatID, gamePlayID, sessionID, transactionType, exchangeRate, IFNULL(curBonusAmount+curWinLockedAmount, 0), 
		   curBonusAmount, curWinLockedAmount, 0, 0,bonusInstanceID,RingFencedAmount,RingFencedAmountSB,RingFencedAmountCasino,RingFencedAmountPoker,NULL);

END$$

DELIMITER ;

