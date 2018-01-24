DROP procedure IF EXISTS `BonusGivePlayerFreeSpinBonusByRuleID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGivePlayerFreeSpinBonusByRuleID`(bonusRuleID BIGINT, sessionID BIGINT, clientStatID BIGINT, bonusAmount DECIMAL(18, 5), expiryDaysFromAwarding INT, expiryDateFixed DATETIME, varReason TEXT, OUT bonusInstanceID BIGINT, OUT statusCode INT)
root: BEGIN
  
  DECLARE bonusEnabledFlag TINYINT(1) DEFAULT 0;
  DECLARE bonusRuleIDCheck, clientStatIDCheck, bonusInstancePreID BIGINT DEFAULT -1;
  DECLARE minAmount, maxAmount DECIMAL(18,5) DEFAULT 0;
  DECLARE playerInSelection, validAmount, bonusPreAuth,bonusActivated TINYINT(1) DEFAULT 0;
  DECLARE awardingType VARCHAR(80);
  DECLARE wagerRequirementMultiplier DECIMAL(18, 5) DEFAULT 0;
  DECLARE finalExpiryDateFixed DATETIME DEFAULT NULL;

  
  
  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';
  
  IF NOT (bonusEnabledFlag) THEN
    SET statusCode=1654;
    LEAVE root;
  END IF;

  SELECT client_stat_id INTO clientStatIDCheck
  FROM gaming_client_stats
  WHERE client_stat_id=clientStatID AND is_active FOR UPDATE;
  
  IF (clientStatIDCheck=-1) THEN
    SET statusCode=224;
    LEAVE root;
  END IF;
  SELECT gbr.bonus_rule_id, PlayerSelectionIsPlayerInSelection(gbr.player_selection_id, clientStatID), (bonusAmount<=gbrfra.max_win) AS valid_amount,
    gbr.wager_requirement_multiplier, IF(activation_start_date < NOW() ,1,0),
	IFNULL(expiryDateFixed,
		IF(expiryDaysFromAwarding IS NULL, IFNULL(gbr.expiry_date_fixed, DATE_ADD(NOW(), INTERVAL gbr.expiry_days_from_awarding DAY)),
			DATE_ADD(NOW(), INTERVAL expiryDaysFromAwarding DAY)))
  INTO bonusRuleIDCheck, playerInSelection, validAmount, wagerRequirementMultiplier,bonusActivated, finalExpiryDateFixed
  FROM gaming_bonus_rules AS gbr
  JOIN gaming_bonus_rules_free_rounds AS gbrfr ON gbr.bonus_rule_id=gbrfr.bonus_rule_id AND gbr.is_active = 1 AND ((bonusRuleID = 0 AND gbr.is_default = 1) OR gbr.bonus_rule_id = bonusRuleID)
  JOIN gaming_client_stats AS gcs ON gcs.client_stat_id=clientStatID
  JOIN gaming_bonus_rules_free_rounds_amounts AS gbrfra ON gbr.bonus_rule_id=gbrfra.bonus_rule_id AND gcs.currency_id=gbrfra.currency_id;
  
  IF (NOT playerInSelection) THEN
    SET statusCode=1655;
    LEAVE root;
  END IF;
  
  IF (expiryDaysFromAwarding IS NOT NULL AND expiryDateFixed IS NOT NULL) THEN
	SET statusCode = 1614;
	LEAVE root;
  END IF;
  
  IF (NOT validAmount) THEN
    SET statusCode=1637;
    LEAVE root;
  END IF;

  IF (NOT bonusActivated) THEN
    SET statusCode=1592;
    LEAVE root;
  END IF;

  SET bonusPreAuth=0; 
  IF (bonusPreAuth=0) THEN
    INSERT INTO gaming_bonus_instances 
      (priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, extra_id, reason, transfer_every_x, transfer_every_amount)
    SELECT 
      priority, bonusAmount, bonusAmount, bonusAmount*wagerRequirementMultiplier,bonusAmount*wagerRequirementMultiplier, NOW(),
      finalExpiryDateFixed AS expiry_date,
		gaming_bonus_rules.bonus_rule_id, clientStatID, sessionID, varReason,
      CASE gaming_bonus_types_release.name
        WHEN 'EveryXWager' THEN gaming_bonus_rules.transfer_every_x_wager
        WHEN 'EveryReleaseAmount' THEN ROUND(wagerRequirementMultiplier/(bonusAmount/wager_restrictions.release_every_amount),2)
        ELSE NULL
      END,
      CASE gaming_bonus_types_release.name
        WHEN 'EveryXWager' THEN ROUND(bonusAmount/(wagerRequirementMultiplier/gaming_bonus_rules.transfer_every_x_wager), 0)
        WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
        ELSE NULL
      END
    FROM gaming_bonus_rules 
    JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
    LEFT JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
    LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
    LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
    WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleIDCheck;
  
    SET bonusInstanceID = LAST_INSERT_ID();
     
    
    IF (ROW_COUNT() > 0) THEN
      CALL BonusOnAwardedUpdateStats(bonusInstanceID);

		SELECT gaming_bonus_types_awarding.name INTO awardingType
		FROM gaming_bonus_rules 
		JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
		WHERE gaming_bonus_rules.bonus_rule_id = bonusRuleIDCheck;

		IF (awardingType='CashBonus') THEN
			CALL BonusRedeemAllBonus(@bonusInstanceID, sessionID, -1, 'CashBonus','CashBonus', NULL);
		END IF;
    END IF;
    
  ELSE
    INSERT INTO gaming_bonus_instances_pre 
      (bonus_rule_id, client_stat_id, priority, bonus_amount, wager_requirement_multiplier, wager_requirement, expiry_date_fixed, expiry_days_from_awarding, extra_id, session_id, reason, date_created, pre_expiry_date)
    SELECT gaming_bonus_rules.bonus_rule_id, clientStatID, gaming_bonus_rules.priority, bonusAmount, wagerRequirementMultiplier, bonusAmount*wagerRequirementMultiplier AS wager_requirement,
      expiryDateFixed, expiryDaysFromAwarding, sessionID, sessionID, varReason, NOW(), date_add(now(), interval pre_expiry_days day) as pre_expiry_date
    FROM gaming_bonus_rules 
    WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleIDCheck;
    
    SET bonusInstanceID = LAST_INSERT_ID();
  END IF;
  
  SET statusCode=0;
  
END root$$

DELIMITER ;

