DROP procedure IF EXISTS `BonusAuthPlayerBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusAuthPlayerBonus`(bonusInstancePreID BIGINT, clientStatID BIGINT, varReason VARCHAR(1024), userID BIGINT, sessionID BIGINT, OUT bonusInstanceID BIGINT, OUT statusCode INT)
root: BEGIN
  -- Updating status of free round to OnAwarded
  
  DECLARE varStatus INT DEFAULT 0;
  DECLARE bonusInstancePreIDCheck, cwFreeRoundID BIGINT DEFAULT -1;
  DECLARE awardingType VARCHAR(80);
  DECLARE isFreeRounds TINYINT(1) DEFAULT 0;
  
  SET bonusInstanceID=-1;
  
  SELECT client_stat_id INTO clientStatID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
  
  
  SELECT gaming_bonus_instances_pre.bonus_instance_pre_id, gaming_bonus_instances_pre.status, gaming_bonus_types_awarding.name, gaming_bonus_rules.is_free_rounds, gaming_bonus_instances_pre.cw_free_round_id
  INTO bonusInstancePreIDCheck, varStatus, awardingType, isFreeRounds, cwFreeRoundID
  FROM gaming_bonus_instances_pre 
  JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = gaming_bonus_instances_pre.bonus_rule_id
  JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
  WHERE bonus_instance_pre_id=bonusInstancePreID AND client_stat_id=clientStatID;

  IF (bonusInstancePreIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (varStatus!=1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  INSERT INTO gaming_bonus_instances 
    (priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, extra_id, award_selector, reason, transfer_every_x, transfer_every_amount, bonus_instance_pre_id,ring_fenced_amount_given,current_ring_fenced_amount,deposited_amount,cw_free_round_id,is_free_rounds,is_free_rounds_mode)
  SELECT 
    gbip.priority, gbip.bonus_amount, gbip.bonus_amount, gbip.wager_requirement, gbip.wager_requirement, NOW(),
    IFNULL(gbip.expiry_date_fixed, DATE_ADD(NOW(), INTERVAL gbip.expiry_days_from_awarding DAY)) AS expiry_date, gaming_bonus_rules.bonus_rule_id, clientStatID, IFNULL(gbip.extra_id,sessionID), gbip.award_selector, gbip.reason,
    CASE gaming_bonus_types_release.name
      WHEN 'EveryXWager' THEN gaming_bonus_rules.transfer_every_x_wager
      WHEN 'EveryReleaseAmount' THEN ROUND(gbip.wager_requirement_multiplier/(gbip.bonus_amount/wager_restrictions.release_every_amount),2)
      ELSE NULL
    END,
    CASE gaming_bonus_types_release.name
      WHEN 'EveryXWager' THEN ROUND(gbip.bonus_amount/(gbip.wager_requirement_multiplier/gaming_bonus_rules.transfer_every_x_wager), 0)
      WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
      ELSE NULL
    END,
	gbip.bonus_instance_pre_id,gbip.ring_fenced_amount_given,gbip.current_ring_fenced_amount,gbip.deposited_amount,cw_free_round_id,IF(cw_free_round_id IS NULL,0,1),IF(cw_free_round_id IS NULL,0,1)
  FROM gaming_bonus_instances_pre AS gbip
  JOIN gaming_bonus_rules ON gbip.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  LEFT JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
  LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
  LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
  WHERE gbip.bonus_instance_pre_id=bonusInstancePreID
  LIMIT 1;
  
  SET bonusInstanceID=LAST_INSERT_ID();
  
  IF (bonusInstanceID!=-1) THEN
    UPDATE gaming_bonus_instances_pre SET status=2, status_date=NOW(), auth_user_id=userID, auth_reason=varReason WHERE bonus_instance_pre_id=bonusInstancePreID;
	CALL BonusOnAwardedUpdateStats(bonusInstanceID);
  END IF;

    IF (isFreeRounds) THEN
		UPDATE gaming_cw_free_rounds 
		SET cw_free_round_status_id=2 -- OnAwarded
		WHERE cw_free_round_id=cwFreeRoundID;
	END IF;

	IF (awardingType='CashBonus' AND bonusInstanceID!=-1 AND isFreeRounds = 0) THEN
		CALL BonusRedeemAllBonus(bonusInstanceID, sessionID, -1, 'CashBonus','CashBonus', NULL);
	END IF;
  
  SET statusCode=0;

END root$$

DELIMITER ;

