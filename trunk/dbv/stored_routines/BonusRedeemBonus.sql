DROP procedure IF EXISTS `BonusRedeemBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusRedeemBonus`(bonusInstanceID BIGINT, sessionID BIGINT, userID BIGINT, redeemReason VARCHAR(1024),transactionType VARCHAR(20), gamePlayID BIGINT)
BEGIN

DECLARE clientStatID BIGINT;
DECLARE exchangeRate, bonusTransferred, bonusWinLockedTransferred, bonusTransferedTotal, bonusTransferredLost, bonusWinLockedTransferredLost DECIMAL(18,5);
DECLARE curBonusAmount, curWinLockedAmount, curBonusTransferredTotal,RingFencedAmount,RingFencedAmountSB,RingFencedAmountCasino,RingFencedAmountPoker DECIMAL(18,5);
DECLARE WagerType VARCHAR(20);	

SELECT value_string INTO WagerType FROM gaming_settings WHERE name = 'PLAY_WAGER_TYPE';

SELECT client_stat_id, bonus_amount_remaining,current_win_locked_amount, bonus_transfered_total ,
IFNULL(IF(ring_fenced_by_bonus_rules,current_ring_fenced_amount,0),0),IFNULL(IF(ring_fenced_by_license_type=3,current_ring_fenced_amount,0),0),
IFNULL(IF(ring_fenced_by_license_type=1,current_ring_fenced_amount,0),0),IFNULL(IF(ring_fenced_by_license_type=2,current_ring_fenced_amount,0),0)
INTO clientStatID, curBonusAmount,curWinLockedAmount, curBonusTransferredTotal,RingFencedAmount,RingFencedAmountSB,RingFencedAmountCasino,RingFencedAmountPoker
FROM gaming_bonus_instances 
LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_bonus_instances.bonus_rule_id
WHERE bonus_instance_id=bonusInstanceID;

IF (curBonusAmount = 0 AND curWinLockedAmount = 0 AND WagerType = 'Type2') THEN 
	UPDATE gaming_bonus_instances AS gbi
	JOIN gaming_bonus_rules ON gbi.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
	SET gbi.bonus_amount_remaining=0, gbi.current_win_locked_amount=0, gbi.is_active=0, gbi.is_secured=0, gbi.secured_date=null, gbi.is_used_all=1, gbi.used_all_date=NOW(), current_ring_fenced_amount=0
	WHERE bonus_instance_id=bonusInstanceID;

ELSE
	UPDATE gaming_bonus_instances AS gbi
	JOIN gaming_bonus_rules ON gbi.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
	SET gbi.bonus_amount_remaining=0, gbi.current_win_locked_amount=0, gbi.is_active=0, gbi.is_secured=1, gbi.secured_date=now(), gbi.redeem_reason=redeemReason, gbi.redeem_session_id=sessionID, gbi.redeem_user_id=userID, 
		gbi.bonus_transfered_total = gbi.bonus_transfered_total + (CASE transfer_type.name
				  WHEN 'All' THEN curBonusAmount+curWinLockedAmount
				  WHEN 'Bonus' THEN curBonusAmount
				  WHEN 'BonusWinLocked' THEN curWinLockedAmount
				  WHEN 'UpToBonusAmount' THEN LEAST(gbi.bonus_amount_given, curBonusAmount+curWinLockedAmount)
				  WHEN 'UpToPercentage' THEN LEAST(gbi.bonus_amount_given*transfer_upto_percentage, curBonusAmount+curWinLockedAmount)
				  WHEN 'ReleaseBonus' THEN LEAST(gbi.bonus_amount_given-gbi.bonus_transfered_total, curBonusAmount+curWinLockedAmount)
				  WHEN 'ReleaseAllBonus' THEN curBonusAmount+curWinLockedAmount
				  ELSE 0
				END),current_ring_fenced_amount=0
	WHERE bonus_instance_id=bonusInstanceID;

END IF;

SELECT exchange_rate INTO exchangeRate
FROM gaming_operators 
JOIN gaming_operator_currency ON gaming_operators.operator_id=gaming_operator_currency.operator_id
JOIN gaming_client_stats AS gcs ON gcs.client_stat_id=clientStatID AND gcs.currency_id=gaming_operator_currency.currency_id
WHERE gaming_operators.is_main_operator=1;

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

CALL PlaceBetBonusCashExchange (clientStatID, gamePlayID, sessionID, transactionType, exchangeRate, IFNULL(bonusTransferedTotal, 0), 
	   bonusTransferred, bonusWinLockedTransferred, bonusTransferredLost, bonusWinLockedTransferredLost,bonusInstanceID,RingFencedAmount,RingFencedAmountSB,RingFencedAmountCasino,RingFencedAmountPoker,NULL);

END$$

DELIMITER ;

