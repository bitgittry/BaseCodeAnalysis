DROP procedure IF EXISTS `BonusAwardCashBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusAwardCashBonus`(bonusRuleID BIGINT, sessionID BIGINT, clientStatID BIGINT, bonusAmount DECIMAL(18, 5), varReason TEXT, OUT statusCode INT)
root: BEGIN
  
  DECLARE bonusEnabledFlag TINYINT(1) DEFAULT 0;
  DECLARE bonusRuleIDCheck, clientStatIDCheck, bonusInstanceID, bonusInstancePreID BIGINT DEFAULT -1;
  DECLARE minAmount, maxAmount,wagerRequirementMultiplier DECIMAL(18,5) DEFAULT 0;
  DECLARE playerInSelection, validAmount, bonusPreAuth,isFreeBonus,awardLimitReached TINYINT(1) DEFAULT 0;
  DECLARE expireyDate DATETIME;
  DECLARE dayFromAwarding INT;
  
  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  
  IF NOT (bonusEnabledFlag) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
	
  SELECT client_stat_id INTO clientStatIDCheck
  FROM gaming_client_stats
  WHERE client_stat_id=clientStatID AND is_active FOR UPDATE;
  
  IF (clientStatIDCheck=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;

  SELECT gbr.bonus_rule_id, PlayerSelectionIsPlayerInSelection(gbr.player_selection_id, clientStatID), (bonusAmount>=gbrma.min_amount AND bonusAmount<=gbrma.max_amount) AS valid_amount,
    min_wager_requirement_multiplier, min_expiry_days_from_awarding,min_expiry_date_fixed, gbr.is_free_bonus,if (award_bonus_max > 0 AND award_bonus_max <= IFNULL(num_times_awarded,0),1,0)
  INTO bonusRuleIDCheck, playerInSelection, validAmount, wagerRequirementMultiplier, dayFromAwarding,expireyDate ,isFreeBonus, awardLimitReached
  FROM gaming_bonus_rules AS gbr
  JOIN gaming_bonus_rules_manuals AS gbrm ON gbr.bonus_rule_id=bonusRuleID AND gbr.bonus_rule_id=gbrm.bonus_rule_id
  JOIN gaming_client_stats AS gcs ON gcs.client_stat_id=clientStatID
  JOIN gaming_bonus_rules_manuals_amounts AS gbrma ON gbr.bonus_rule_id=gbrma.bonus_rule_id AND gcs.currency_id=gbrma.currency_id
  LEFT JOIN(
	SELECT COUNT(1) AS num_times_awarded,client_stat_id FROM gaming_bonus_instances
	WHERE bonus_rule_id = bonusRuleID AND client_stat_id = clientStatID
  ) AS count_bonuses ON count_bonuses.client_stat_id = gcs.client_stat_id;




  IF (NOT playerInSelection) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  IF (NOT validAmount) THEN
    SET statusCode=4;
    LEAVE root;
  END IF;
  IF (awardLimitReached) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;

  
    INSERT INTO gaming_bonus_instances 
      (priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, extra_id, reason, transfer_every_x, transfer_every_amount)
    SELECT 
      priority, bonusAmount, bonusAmount, IF(isFreeBonus,0,bonusAmount*wagerRequirementMultiplier),IF(isFreeBonus,0, bonusAmount*wagerRequirementMultiplier), NOW(),
      IFNULL(expireyDate, DATE_ADD(NOW(), INTERVAL dayFromAwarding DAY)) AS expiry_date, gaming_bonus_rules.bonus_rule_id, clientStatID, sessionID, varReason,
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
    WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleID;
  
    SET bonusInstanceID = LAST_INSERT_ID();
     
    
    IF (ROW_COUNT() > 0) THEN
      CALL BonusOnAwardedUpdateStats(bonusInstanceID);
    END IF;
    
	CALL BonusRedeemAllBonus(bonusInstanceID, sessionID, -1, 'CashBonus','CashBonus', NULL);

  
  SET statusCode=0;
END root$$

DELIMITER ;

