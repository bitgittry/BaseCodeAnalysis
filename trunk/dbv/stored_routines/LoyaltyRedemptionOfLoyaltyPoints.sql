DROP procedure IF EXISTS `LoyaltyRedemptionOfLoyaltyPoints`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LoyaltyRedemptionOfLoyaltyPoints`(clientStatId BIGINT, loyaltyRedemptionId BIGINT, sessionID BIGINT, OUT statusCode INT)
root: BEGIN
	  
	DECLARE clientStatIDCheck, currencyID, operatorID, loyaltyRedemptionIDCheck, playerSelId, 
		extraID, loyaltyRedemptionTransactionID, bonusInstanceID BIGINT DEFAULT 0;
	DECLARE prizeCostCurrencyID, prizeID BIGINT;
	DECLARE minEnrolmentDays, minVipLevel, playerVIPLevel, freeRoundExpiryDaysFromAwarding, expiryDaysFromAwarding INT DEFAULT 0;
	DECLARE prizeTypeID,  limitedOfferAmount, freeRounds,numFreeRounds INT DEFAULT NULL;
	DECLARE isActive, isOpenToAll, isPlayerInSelection,isFreeRounds, isActiveBonus, allowAwardingBonuses TINYINT(1) DEFAULT 0;	
	DECLARE currentLoyaltyPoints, minLoyaltyPoints, prizeAmount, prizeCost, playerExchangeRate, 
		prizeCostExchangeRate, prizeCostBase, prizeCostPlayer, prizeAmountBase,wagerRequirementMultiplier DECIMAL(18,5) DEFAULT 0;
	DECLARE playerSignedUpDate, freeRoundExpiryDateFixed, expiryDateFixed, dateEnd DATETIME;
	DECLARE prizeType VARCHAR(100);
	DECLARE tournamentStatusID BIGINT;

	SET statusCode=0;

    SELECT client_stat_id, gaming_client_stats.currency_id, gaming_client_stats.current_loyalty_points, gaming_clients.vip_level, gaming_clients.sign_up_date
	INTO clientStatIDCheck, currencyID, currentLoyaltyPoints, playerVIPLevel, playerSignedUpDate
    FROM gaming_client_stats 
	JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
	WHERE gaming_client_stats.client_stat_id=clientStatId
	FOR UPDATE;

	SELECT operator_id INTO operatorID FROM gaming_operators WHERE is_main_operator=1;

    IF (clientStatIDCheck=0) THEN
		SET statusCode=0;
		LEAVE root;
	END IF;

	
	SELECT loyalty_redemption_id, is_active, loyalty_redemption_prize_type_id,loyalty_redemption_prize_id, extra_id, 
		minimum_loyalty_points, is_open_to_all, player_selection_id, limited_offer_placings_balance, minimum_vip_level, minimum_enrolment_age_days, free_rounds, date_end
	INTO loyaltyRedemptionIDCheck, isActive, prizeTypeID, prizeID, extraID, 
		minLoyaltyPoints, isOpenToAll, playerSelId, limitedOfferAmount, minVipLevel, minEnrolmentDays, freeRounds, dateEnd
	FROM gaming_loyalty_redemption 
	WHERE loyalty_redemption_id=loyaltyRedemptionId AND is_active=1 
	FOR UPDATE;
	
	SELECT prize_type INTO prizeType FROM gaming_loyalty_redemption_prize_types WHERE loyalty_redemption_prize_type_id = prizeTypeID;

	SELECT amount INTO prizeAmount FROM gaming_loyalty_redemption_currency_amounts ca 
	JOIN gaming_loyalty_redemption rd ON (ca.loyalty_redemption_id=rd.loyalty_redemption_id)
	JOIN gaming_loyalty_redemption_prize_types pt ON (pt.loyalty_redemption_prize_type_id=rd.loyalty_redemption_prize_type_id) AND prize_type IN ('CASH','BONUS')
	WHERE ca.loyalty_redemption_id=loyaltyRedemptionId AND ca.currency_id=currencyID;

	IF (prizeType = 'BONUS') THEN    
    	SELECT 	is_active, allow_awarding_bonuses
		INTO 	isActiveBonus, allowAwardingBonuses
		FROM 	gaming_bonus_rules 			
		WHERE 	bonus_rule_id = extraID;
    ELSE
		SET isActiveBonus = 1;
		SET allowAwardingBonuses = 1;
	END IF;


	IF (loyaltyRedemptionIDCheck=0) THEN
		SET statusCode=12;
		LEAVE root;
	END IF;

		
	IF (isActive=0) THEN
		SET statusCode=2;
		LEAVE root;
	END IF;
    
    IF (dateEnd IS NOT NULL AND dateEnd<NOW()) THEN
		SET statusCode=2;
		LEAVE root;
    END IF;

	IF (currentLoyaltyPoints<minLoyaltyPoints) THEN
		SET statusCode=1;
		LEAVE root;
	END IF;
	
	IF (isOpenToAll = 0) THEN
		SET isPlayerInSelection = PlayerSelectionIsPlayerInSelection(playerSelId, clientStatId);
		IF (isPlayerInSelection=0) THEN
			SET statusCode=5;
			LEAVE root;
		END IF;
	END IF;

	IF (limitedOfferAmount IS NOT NULL AND limitedOfferAmount<=0) THEN
		SET statusCode=6;
		LEAVE root;
	END IF;

	IF (minVIPLevel IS NOT NULL AND playerVIPLevel < minVIPLevel) THEN
		SET statusCode=3;
		LEAVE root;
	END IF;	

	IF (minEnrolmentDays IS NOT NULL AND minEnrolmentDays > 0) THEN
		IF (DATEDIFF(NOW(), playerSignedUpDate) < minEnrolmentDays) THEN
			SET statusCode=7;
			LEAVE root;
		END IF;
	END IF;

	IF (isActiveBonus = 0 OR allowAwardingBonuses = 0) THEN
		SET statusCode=15;
		LEAVE root;
	END IF;		
	
	UPDATE gaming_client_stats 
    SET total_loyalty_points_used = total_loyalty_points_used+minLoyaltyPoints, current_loyalty_points = current_loyalty_points - minLoyaltyPoints 
    WHERE client_stat_id=clientStatId;
	
	IF (limitedOfferAmount IS NOT NULL) THEN
		UPDATE gaming_loyalty_redemption SET limited_offer_placings_balance=limited_offer_placings_balance-1 WHERE loyalty_redemption_id=loyaltyRedemptionId; 
	END IF;

	-- Get Prize Cost and Prize CurrencyID if any
	SELECT cost, cost_currency_id INTO prizeCost, prizeCostCurrencyID 
	FROM gaming_loyalty_redemption_prizes prizes
	JOIN gaming_loyalty_redemption redemption ON (prizes.loyalty_redemption_prize_id = redemption.loyalty_redemption_prize_id) 
	WHERE loyalty_redemption_id=loyaltyRedemptionId;

	SET playerExchangeRate		= 0.0;
	SET prizeCostExchangeRate	= 0.0;
	SET prizeCostBase   		= 0.0;
	SET prizeCostPlayer 		= 0.0;
	SET prizeAmountBase			= 0.0;

	SELECT exchange_rate INTO  playerExchangeRate
	FROM gaming_operator_currency 
	WHERE gaming_operator_currency.operator_id=operatorID AND gaming_operator_currency.currency_id=currencyID;	

	IF(prizeCostCurrencyID IS NOT NULL) THEN

		SELECT exchange_rate INTO  prizeCostExchangeRate
		FROM gaming_operator_currency 
		WHERE gaming_operator_currency.operator_id=operatorID AND gaming_operator_currency.currency_id=prizeCostCurrencyID;		
	
		SET prizeCostBase   = prizeCost/prizeCostExchangeRate;
		SET prizeCostPlayer = prizeCostBase*playerExchangeRate;
		
	END IF;
    
    IF (prizeType = 'BONUS') THEN
    
    		SELECT is_free_rounds,free_round_expiry_date,free_round_expiry_days,wager_requirement_multiplier,IFNULL(gaming_bonus_rules.num_free_rounds,num_rounds),expiry_days_from_awarding,expiry_date_fixed
			INTO isFreeRounds,freeRoundExpiryDateFixed,freeRoundExpiryDaysFromAwarding,wagerRequirementMultiplier,numFreeRounds,expiryDaysFromAwarding,expiryDateFixed
			FROM gaming_bonus_rules 
            LEFT JOIN gaming_bonus_rule_free_round_profiles ON gaming_bonus_rule_free_round_profiles.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
			LEFT JOIN gaming_bonus_free_round_profiles ON gaming_bonus_rule_free_round_profiles.bonus_free_round_profile_id = gaming_bonus_free_round_profiles.bonus_free_round_profile_id -- incase we ever have aa manuf without a profile
			WHERE gaming_bonus_rules.bonus_rule_id = extraID;
        
	END IF;

	CASE prizeType
		WHEN 'CASH' THEN
			SET prizeAmountBase = prizeAmount/playerExchangeRate;
		WHEN 'BONUS' THEN
			SET prizeAmountBase = prizeAmount/playerExchangeRate;
		ELSE
			SET prizeAmountBase = 0;
	END CASE;

	INSERT INTO gaming_loyalty_redemption_transactions (loyalty_redemption_id, loyalty_redemption_prize_type_id, loyalty_redemption_prize_id, extra_id, loyalty_points, amount, free_rounds, transaction_date, limited_offer_placing, client_stat_id, currency_id, session_id, amount_base, cost, cost_base)
	VALUES (loyaltyRedemptionId, prizeTypeID, prizeID, extraID, minLoyaltyPoints, prizeAmount, freeRounds, NOW(), limitedOfferAmount, clientStatId, currencyID, sessionID, prizeAmountBase, prizeCostPlayer, prizeCostBase);

	SET loyaltyRedemptionTransactionID=LAST_INSERT_ID();
	 
	SELECT loyalty_redemption_transaction_id, loyalty_redemption_prize_type_id, prizeType AS prize_type, extra_id, loyalty_points, amount, free_rounds, transaction_date, limited_offer_placing
	FROM gaming_loyalty_redemption_transactions
	WHERE loyalty_redemption_transaction_id=loyaltyRedemptionTransactionID;

    CASE prizeType
	  WHEN 'CASH' THEN
		CALL TransactionAdjustRealMoneyLoyaltyRedemption(sessionID, clientStatId, prizeAmount, 
			'LoyaltyRedemption', loyaltyRedemptionId, loyaltyRedemptionTransactionID, minLoyaltyPoints*-1, @statusCode);
      WHEN 'BONUS' THEN

		IF (!isFreeRounds) THEN 
			INSERT INTO gaming_bonus_instances 
			  (priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, extra_id, reason, transfer_every_x, transfer_every_amount)
			SELECT 
			  priority, prizeAmount, prizeAmount, IF(gaming_bonus_rules.is_free_bonus,0,prizeAmount*gaming_bonus_rules.wager_requirement_multiplier),IF(gaming_bonus_rules.is_free_bonus,0, prizeAmount*gaming_bonus_rules.wager_requirement_multiplier), NOW(),
			  IFNULL(gaming_bonus_rules.expiry_date_fixed, DATE_ADD(NOW(), INTERVAL gaming_bonus_rules.expiry_days_from_awarding DAY)) AS expiry_date, gaming_bonus_rules.bonus_rule_id, clientStatId, 0, 'LoyaltyRedemption',
			  CASE gaming_bonus_types_release.name
				WHEN 'EveryXWager' THEN gaming_bonus_rules.transfer_every_x_wager
				WHEN 'EveryReleaseAmount' THEN ROUND(wager_requirement_multiplier/(prizeAmount/wager_restrictions.release_every_amount),2)
				ELSE NULL
			  END,
			  CASE gaming_bonus_types_release.name
				WHEN 'EveryXWager' THEN ROUND(prizeAmount/(wager_requirement_multiplier/gaming_bonus_rules.transfer_every_x_wager), 0)
				WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
				ELSE NULL
			  END
			FROM gaming_bonus_rules 
			JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatId
			LEFT JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
			LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
			LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
			WHERE gaming_bonus_rules.bonus_rule_id=extraID
			LIMIT 1;
		  
			SET bonusInstanceID = LAST_INSERT_ID();
			 
			IF (bonusInstanceID != 0) THEN
			  CALL BonusOnAwardedUpdateStatsWithLoyaltyPoints(bonusInstanceID, minLoyaltyPoints*-1);
				
				SET @awardingType=NULL;
				SELECT gaming_bonus_types_awarding.name INTO @awardingType
				FROM gaming_bonus_rules 
				JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
				WHERE gaming_bonus_rules.bonus_rule_id = extraID;

				IF (@awardingType='CashBonus') THEN
					CALL BonusRedeemAllBonus(bonusInstanceID, 0, -1, 'CashBonus','CashBonus', NULL);
				END IF;
			END IF;
        ELSE
			CALL BonusAwardCWFreeRoundBonus (extraID, clientStatID, sessionID,IFNULL(freeRoundExpiryDateFixed, DATE_ADD(NOW(), INTERVAL freeRoundExpiryDaysFromAwarding DAY)),IFNULL(expiryDateFixed, DATE_ADD(NOW(), INTERVAL expiryDaysFromAwarding DAY)),  
				wagerRequirementMultiplier,IFNULL(freeRounds,numFreeRounds), sessionID,'LoyaltyRedemption', 0,0, 0,1,bonusInstanceID, statusCode);
        END IF;

	  WHEN 'PROMOTION' THEN
		CALL PromotionOptInPlayer(extraID, clientStatId, 1, NULL, NULL, sessionID, @statusCode);
		-- make an adjustment of 0 money just to log the loyalty points deducted
		CALL TransactionAdjustRealMoneyLoyaltyRedemption(sessionID, clientStatId, 0, 
			'LoyaltyRedemption', loyaltyRedemptionId, loyaltyRedemptionTransactionID, minLoyaltyPoints*-1, @statusCode);
	  WHEN 'TOURNAMENT' THEN		
		SET @tournamentStatusID = 0;
		CALL TournamentOptIn(extraID, clientStatId, 1, @statusCode, @tournamentStatusID); -- OUT tournamentStatusID BIGINT
		-- make an adjustment of 0 money just to log the loyalty points deducted
		CALL TransactionAdjustRealMoneyLoyaltyRedemption(sessionID, clientStatId, 0, 
			'LoyaltyRedemption', loyaltyRedemptionId, loyaltyRedemptionTransactionID, minLoyaltyPoints*-1, @statusCode);	  
	  WHEN 'FreeRounds' THEN
		INSERT INTO gaming_bonus_free_rounds (priority, num_rounds_given, num_rounds_remaining, given_date, expiry_date, bonus_rule_id, client_stat_id, bonus_rule_award_counter_id) 
		SELECT gaming_bonus_rules.priority, freeRounds AS num_rounds_given, freeRounds AS num_rounds_remaining, NOW(), IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, 
		  gaming_bonus_rules.bonus_rule_id, clientStatId, 0
		FROM gaming_bonus_rules 
		WHERE bonus_rule_id=extraID;
		-- make an adjustment of 0 money just to log the loyalty points deducted
		CALL TransactionAdjustRealMoneyLoyaltyRedemption(sessionID, clientStatId, 0, 
			'LoyaltyRedemption', loyaltyRedemptionId, loyaltyRedemptionTransactionID, minLoyaltyPoints*-1, @statusCode);
	  ELSE
		SET @statusCode=0;
		-- make an adjustment of 0 money just to log the loyalty points deducted
		CALL TransactionAdjustRealMoneyLoyaltyRedemption(sessionID, clientStatId, 0, 
			'LoyaltyRedemption', loyaltyRedemptionId, loyaltyRedemptionTransactionID, minLoyaltyPoints*-1, @statusCode);
	END CASE;
END root$$

DELIMITER ;

