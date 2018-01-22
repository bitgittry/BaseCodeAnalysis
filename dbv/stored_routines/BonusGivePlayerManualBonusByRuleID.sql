
DROP procedure IF EXISTS `BonusGivePlayerManualBonusByRuleID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGivePlayerManualBonusByRuleID`(bonusRuleID BIGINT, sessionID BIGINT, clientStatID BIGINT, bonusAmount DECIMAL(18, 5), wagerRequirementMultiplier DECIMAL(18, 5), expiryDaysFromAwarding INT,
  expiryDateFixed DATETIME, freeRoundExpiryDaysFromAwarding INT, freeRoundExpiryDateFixed DATETIME, numFreeRounds INT,varReason TEXT, OUT statusCode INT)
root: BEGIN
  
  DECLARE bonusEnabledFlag, bonusHidden, bonusActive TINYINT(1) DEFAULT 0;
  DECLARE bonusRuleIDCheck, clientStatIDCheck, bonusInstanceID, bonusInstancePreID BIGINT DEFAULT -1;
  DECLARE minAmount, maxAmount DECIMAL(18,5) DEFAULT 0;
  DECLARE playerInSelection, validWagerReq, validDaysFromAwarding, validDateFixed, validAmount, bonusPreAuth,isFreeBonus,bonusActivated,awardLimitReached,isFreeRounds,freeRoundsOutsideLimit,validFreeRoundsDaysFromAwarding, validFreeRoundsDateFixed TINYINT(1) DEFAULT 0;
  DECLARE awardingType VARCHAR(80);
  DECLARE awardedTimes INT DEFAULT 0;
  DECLARE awardedTimesThreshold INT DEFAULT NULL;
  
  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';
  
  SET statusCode=NULL;

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
    ((wagerRequirementMultiplier>=min_wager_requirement_multiplier AND wagerRequirementMultiplier<=max_wager_requirement_multiplier) OR is_free_bonus) AS valid_wager_req, 
    (expiryDaysFromAwarding IS NULL OR (expiryDaysFromAwarding>=min_expiry_days_from_awarding AND expiryDaysFromAwarding<=max_expiry_days_from_awarding)) AS valid_days_from_awarding, 
    (expiryDateFixed IS NULL OR expiryDateFixed>=min_expiry_date_fixed AND expiryDateFixed<=max_expiry_date_fixed), gbr.is_free_bonus,
	IF(activation_start_date < NOW() ,1,0),IF (award_bonus_max > 0 AND award_bonus_max <= IFNULL(num_times_awarded,0),1,0), gbr.awarded_times + 1, gbr.awarded_times_threshold,is_free_rounds,
	IF((is_free_rounds = 0 AND numFreeRounds = 0) OR ((is_free_rounds = 0 AND  numFreeRounds IS NULL) OR numFreeRounds BETWEEN min_free_rounds AND max_free_rounds),0,1),
(freeRoundExpiryDaysFromAwarding IS NULL OR (freeRoundExpiryDaysFromAwarding>=min_free_rounds_expiry_days_from_awarding AND freeRoundExpiryDaysFromAwarding<=max_free_rounds_expiry_days_from_awarding)) AS valid_free_round_days_from_awarding, 
(freeRoundExpiryDateFixed IS NULL OR (freeRoundExpiryDateFixed>=min_free_rounds_expiry_date_fixed AND freeRoundExpiryDateFixed<=max_free_rounds_expiry_date_fixed)) AS valid_free_round_date_fixed,
gbr.is_active, gbr.is_hidden

  INTO bonusRuleIDCheck, playerInSelection, validAmount, validWagerReq, validDaysFromAwarding, validDateFixed,isFreeBonus,bonusActivated,awardLimitReached, awardedTimes, awardedTimesThreshold,
	isFreeRounds,freeRoundsOutsideLimit, validFreeRoundsDaysFromAwarding, validFreeRoundsDateFixed, bonusActive, bonusHidden
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

  IF (isFreeRounds=0 AND NOT validAmount) THEN
    SET statusCode=4;
    LEAVE root;
  END IF;
  
  IF (NOT validWagerReq) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;
  
  IF (NOT validDaysFromAwarding OR NOT validDateFixed) THEN
    SET statusCode=6;
    LEAVE root;
  END IF;

  IF (NOT bonusActivated) THEN
    SET statusCode=8;
    LEAVE root;
  END IF;

  IF (awardLimitReached) THEN
    SET statusCode=9;
    LEAVE root;
  END IF; 
  
  IF (awardedTimesThreshold IS NOT NULL AND awardedTimes > awardedTimesThreshold) THEN
    SET statusCode=10;
    LEAVE root;
  END IF;


IF (bonusActive = 0 OR bonusHidden =1) THEN
	SET statusCode = 14;
	LEAVE root;
END IF;

  IF (isFreeRounds=1) THEN
	 IF (freeRoundsOutsideLimit) THEN
		SET statusCode=11;
		LEAVE root;
	  END IF;

	  IF (NOT validFreeRoundsDaysFromAwarding OR NOT validFreeRoundsDateFixed) THEN
		SET statusCode=12;
		LEAVE root;
	  END IF; 

	  SET @isTransactionTypeFound=0;
	  SELECT 1 INTO @isTransactionTypeFound FROM gaming_payment_transaction_type WHERE gaming_payment_transaction_type.name='FreeRoundBonusAwarded';
	  IF (@isTransactionTypeFound=0) THEN
		SET statusCode=13;
		LEAVE root;
      END IF;	
  END IF;

	IF (isFreeRounds = 0) THEN 
		IF (bonusPreAuth=0) THEN
			INSERT INTO gaming_bonus_instances 
				(priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, extra_id, reason, transfer_every_x, transfer_every_amount)
			SELECT 
				priority, bonusAmount, bonusAmount, IF(isFreeBonus,0,bonusAmount*wagerRequirementMultiplier),IF(isFreeBonus,0, bonusAmount*wagerRequirementMultiplier), NOW(),
				IFNULL(expiryDateFixed, DATE_ADD(NOW(), INTERVAL expiryDaysFromAwarding DAY)) AS expiry_date, gaming_bonus_rules.bonus_rule_id, clientStatID, sessionID, varReason,
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

				SELECT gaming_bonus_types_awarding.name INTO awardingType
				FROM gaming_bonus_rules 
				JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
				WHERE gaming_bonus_rules.bonus_rule_id = bonusRuleID;

				IF (awardingType='CashBonus') THEN
					CALL BonusRedeemAllBonus(bonusInstanceID, sessionID, -1, 'CashBonus','CashBonus', NULL);
				END IF;
			END IF;
 
			SELECT bonusInstanceID AS bonus_instance_id;
		ELSE
			INSERT INTO gaming_bonus_instances_pre 
				(bonus_rule_id, client_stat_id, priority, bonus_amount, wager_requirement_multiplier, wager_requirement, expiry_date_fixed, expiry_days_from_awarding, extra_id, session_id, reason, date_created, pre_expiry_date)
			SELECT gaming_bonus_rules.bonus_rule_id, clientStatID, gaming_bonus_rules.priority, bonusAmount, wagerRequirementMultiplier, bonusAmount*wagerRequirementMultiplier AS wager_requirement,
				expiryDateFixed, expiryDaysFromAwarding, sessionID, sessionID, varReason, NOW(), date_add(now(), interval pre_expiry_days day) as pre_expiry_date
			FROM gaming_bonus_rules 
			WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleID;

			SET bonusInstancePreID = LAST_INSERT_ID();
			SELECT bonusInstancePreID AS bonus_instance_pre_id;
		END IF;
	ELSE

		CALL BonusAwardCWFreeRoundBonus (bonusRuleID, clientStatID, sessionID,IFNULL(freeRoundExpiryDateFixed, DATE_ADD(NOW(), INTERVAL freeRoundExpiryDaysFromAwarding DAY)),IFNULL(expiryDateFixed, DATE_ADD(NOW(), INTERVAL expiryDaysFromAwarding DAY)),  
			wagerRequirementMultiplier,numFreeRounds, sessionID,varReason, 0,0, 0,0,bonusInstanceID, statusCode);

		IF (bonusPreAuth) THEN
			SELECT bonusInstanceID AS bonus_instance_pre_id;
		ELSE
			SELECT bonusInstanceID AS bonus_instance_id;
		END IF;
	END IF;
  
  SET statusCode=IFNULL(statusCode, 0);
  
END root$$

DELIMITER ;

