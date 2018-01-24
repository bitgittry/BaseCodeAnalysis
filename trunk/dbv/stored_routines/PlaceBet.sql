DROP procedure IF EXISTS `PlaceBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceBet`(
  operatorGameID BIGINT, operatorGameIDMinigame BIGINT, sessionID BIGINT, gameSessionID BIGINT, clientStatID BIGINT, betAmount DECIMAL(18, 5), 
  jackpotContribution DECIMAL(18, 5), gamePlayKey VARCHAR(80), gameRoundID BIGINT, ignorePlayLimit TINYINT(1), ignoreSessionExpiry TINYINT(1), 
  allowUseBonusLost TINYINT(1), roundType VARCHAR(20), transactionRef VARCHAR(80), roundRef VARCHAR(80), realMoneyOnly TINYINT(1), platformType VARCHAR(20), 
  minimalData TINYINT(1), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root:BEGIN  
 
  DECLARE totalPlayerBalance, betOther, betReal, betFreeBet, betFreeBetWinLocked, betBonus, betBonusWinLocked, betBonusLost, balanceReal, balanceFreeBet, 
	balaneFreeBetWinLocked, balanceBonus, balanceWinLocked, balanceBonusLost, betRemain, exchangeRate, betTotalBase,FreeBonusAmount,loyaltyBetBonus,
    loyaltyPoints, loyaltyPointsBonus, balanceRealBefore, balanceBonusBefore, lockedRealFunds DECIMAL(18, 5) DEFAULT 0;
  DECLARE clientStatIDStat, clientStatIDCheck, clientID, gamePlayID, currencyID, gameID, gameManufacturerID, operatorGameIDCheck, 
	fraudClientEventID, bonusFreeRoundID, gamePlayExtraID, gamePlayBetCounterID, vipLevelMin BIGINT DEFAULT -1;
  DECLARE playerRestrictionEnabled, playLimitEnabled, isLimitExceeded, bonusEnabledFlag, bonusFreeRoundEnabled, bonusRewardEnabledFlag, isGameBlocked, 
	disableBonusMoney, isAccountClosed, fraudEnabled, disallowPlay, isPlayAllowed, loyaltyPointsEnabled, fingFencedEnabled, ruleEngineEnabled TINYINT(1) DEFAULT 0;
  DECLARE bonusReqContributeRealOnly, bonusMismatch, isSessionOpen, isNewRound, taxEnabled, dominantNoLoyaltyPoints, licenceCountryRestriction TINYINT(1) DEFAULT 0;
  DECLARE numBonuses, numApplicableBonuses, roundNumTransactions INT DEFAULT 0;
  DECLARE licenseType VARCHAR(20) DEFAULT NULL;
  DECLARE clientWagerTypeID INT DEFAULT -1;
  DECLARE licenseTypeID TINYINT(4) DEFAULT 1;
  DECLARE vipLevelID BIGINT DEFAULT NULL;
  DECLARE isChipTransfer,isProcessedCT,isRoundClosedCT TINYINT(1) DEFAULT 0; 
  DECLARE dateTimeEndCT DATETIME DEFAULT NULL;
  DECLARE currentVipType VARCHAR(100) DEFAULT ''; 

  SET gamePlayIDReturned=NULL; 
  SET gamePlayExtraID=NULL;
  SET roundType='Normal';

  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, gs4.value_bool as vb4, IFNULL(gs5.value_bool,0) as vb5, 
	IFNULL(gs6.value_bool,0) AS vb6, IFNULL(gs7.value_bool,0) AS vb7, IFNULL(gs8.value_bool,0) AS vb8, IFNULL(gs9.value_bool,0) AS vb9, 
    IFNULL(gs10.value_bool,0) AS vb10, IFNULL(gs11.value_bool,0) AS vb11, IFNULL(gs12.value_bool,0) AS vb12
  INTO playLimitEnabled, bonusEnabledFlag, bonusFreeRoundEnabled, bonusRewardEnabledFlag, fraudEnabled, 
	bonusReqContributeRealOnly, playerRestrictionEnabled, loyaltyPointsEnabled, taxEnabled, 
    licenceCountryRestriction, fingFencedEnabled, ruleEngineEnabled
  FROM gaming_settings gs1 
    STRAIGHT_JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
    STRAIGHT_JOIN gaming_settings gs3 ON (gs3.name='IS_BONUS_FREE_ROUND_ENABLED')
    STRAIGHT_JOIN gaming_settings gs4 ON (gs4.name='IS_BONUS_REWARD_ENABLED')
    STRAIGHT_JOIN gaming_settings gs5 ON (gs5.name='FRAUD_ENABLED')
    LEFT JOIN gaming_settings gs6 ON (gs6.name='BONUS_CONTRIBUTION_REAL_MONEY_ONLY')
    LEFT JOIN gaming_settings gs7 ON (gs7.name='PLAYER_RESTRICTION_ENABLED')
	LEFT JOIN gaming_settings gs8 ON (gs8.name='LOYALTY_POINTS_WAGER_ENABLED')
    LEFT JOIN gaming_settings gs9 ON (gs9.name='TAX_ON_GAMEPLAY_ENABLED')
	LEFT JOIN gaming_settings gs10 ON (gs10.name='LICENCE_COUNTRY_RESTRICTION_ENABLED')
    LEFT JOIN gaming_settings gs11 ON (gs11.name='RING_FENCED_ENABLED')
    LEFT JOIN gaming_settings gs12 ON (gs12.name='RULE_ENGINE_ENABLED')
    WHERE gs1.name='PLAY_LIMIT_ENABLED';

  SET bonusFreeRoundEnabled=bonusEnabledFlag AND bonusFreeRoundEnabled;
  SET bonusRewardEnabledFlag=bonusEnabledFlag AND bonusRewardEnabledFlag;
  
  IF (platformType IS NULL) THEN
		SELECT platform_type INTO platformType 
        FROM sessions_main
		LEFT JOIN gaming_platform_types ON gaming_platform_types.platform_type_id = sessions_main.platform_type_id
		WHERE sessions_main.session_id = sessionID;
   END IF;

  CALL PlatformTypesGetPlatformsByPlatformType(platformType, NULL, @platformTypeID, @platformType, @channelTypeID, @channelType);
    
  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats
  WHERE gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.is_active=1
  FOR UPDATE;
  
  SELECT gaming_client_stats.client_stat_id, gaming_clients.client_id, gaming_operator_currency.currency_id, 
	current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_bonus_lost, 
    IF(gaming_clients.is_account_closed OR gaming_fraud_rule_client_settings.block_account, 1, 0), 
	gaming_clients.is_play_allowed AND !gaming_fraud_rule_client_settings.block_gameplay, 
    gaming_clients.vip_level, gaming_clients.vip_level_id, locked_real_funds, gaming_operator_currency.exchange_rate
  INTO clientStatIDCheck, clientID, currencyID, balanceReal, balanceBonus, balanceWinLocked, balanceBonusLost, 
	isAccountClosed, isPlayAllowed, vipLevelMin, vipLevelID, lockedRealFunds, exchangeRate    
  FROM gaming_client_stats FORCE INDEX (PRIMARY)
  STRAIGHT_JOIN gaming_operator_currency ON gaming_operator_currency.currency_id=gaming_client_stats.currency_id
  STRAIGHT_JOIN gaming_clients ON 
    gaming_clients.client_id=gaming_client_stats.client_id
  LEFT JOIN gaming_fraud_rule_client_settings ON 
	gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id
  WHERE gaming_client_stats.client_stat_id=clientStatID;
 
  SET balanceRealBefore=balanceReal;
  SET balanceBonusBefore=balanceBonus+balanceWinLocked;
  
  SET balanceReal=IF(balanceReal<0, 0, balanceReal);

  
  if (clientStatIDCheck=-1 OR isAccountClosed=1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  
  IF (isPlayAllowed=0 AND ignorePlayLimit=0) THEN 
    SET statusCode=6; 
    LEAVE root;
  END IF;  
  
  SELECT gaming_operator_games.operator_game_id, gaming_operator_games.is_game_blocked, gaming_operator_games.disable_bonus_money, 
    gaming_games.game_id, gaming_games.game_manufacturer_id, gaming_license_type.name, gaming_license_type.license_type_id, gaming_games.client_wager_type_id,
	IF(gaming_game_manufacturers.is_chip_transfer=0,num_applicable_bonuses,0), IF(gaming_game_manufacturers.is_chip_transfer=0,IFNULL(Bonuses.current_bonus_balance,0),0), IF(gaming_game_manufacturers.is_chip_transfer=0,IFNULL(Bonuses.current_bonus_win_locked_balance,0),0),gaming_game_manufacturers.is_chip_transfer
  INTO operatorGameIDCheck, isGameBlocked, disableBonusMoney, gameID, gameManufacturerID, licenseType, licenseTypeID, clientWagerTypeID, 
    numApplicableBonuses, balanceBonus, balanceWinLocked,isChipTransfer
  FROM gaming_operator_games
  STRAIGHT_JOIN gaming_games ON gaming_operator_games.operator_game_id=operatorGameID AND 
	gaming_operator_games.game_id=gaming_games.game_id
  STRAIGHT_JOIN gaming_game_manufacturers ON gaming_game_manufacturers.game_manufacturer_id = gaming_games.game_manufacturer_id
  STRAIGHT_JOIN gaming_license_type ON gaming_license_type.license_type_id = gaming_games.license_type_id
  LEFT JOIN
  (
    SELECT COUNT(*) AS num_applicable_bonuses, SUM(gbi.bonus_amount_remaining) AS current_bonus_balance, SUM(gbi.current_win_locked_amount) AS current_bonus_win_locked_balance
    FROM gaming_bonus_instances AS gbi FORCE INDEX (client_active_bonuses)
    STRAIGHT_JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON 
		(gbi.client_stat_id=clientStatID AND gbi.is_active=1 AND gbi.is_free_rounds_mode=0) AND 
		(gbi.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=operatorGameID)
    STRAIGHT_JOIN gaming_bonus_rules AS gbr ON gbi.bonus_rule_id=gbr.bonus_rule_id
    STRAIGHT_JOIN gaming_bonus_types_awarding AS gbta ON gbr.bonus_type_awarding_id=gbta.bonus_type_awarding_id
    STRAIGHT_JOIN gaming_bonus_types ON gbr.bonus_type_id=gaming_bonus_types.bonus_type_id
    LEFT JOIN sessions_main ON sessions_main.session_id=sessionID
    LEFT JOIN gaming_bonus_rules_platform_types AS platform_types ON 
		gbr.bonus_rule_id=platform_types.bonus_rule_id AND 
        sessions_main.platform_type_id=platform_types.platform_type_id
    WHERE (gbr.restrict_platform_type=0 OR platform_types.platform_type_id IS NOT NULL)
  ) AS Bonuses ON 1=1;

  IF(licenceCountryRestriction) THEN
	  
	  IF (SELECT !WagerRestrictionCheckCanWager(licenseTypeID, sessionID)) THEN 
		SET statusCode=9; 
		LEAVE root;
	  END IF;
  END IF;
  
  SET balanceWinLocked=balanceWinLocked+balaneFreeBetWinLocked; 
  SET balaneFreeBetWinLocked=0;
  
  IF (disableBonusMoney OR bonusEnabledFlag=0 OR realMoneyOnly=1) THEN
    SET balanceBonus=0;
    SET balanceWinLocked=0; 
    SET balanceFreeBet=0; 
    SET balaneFreeBetWinLocked=0;
  END IF;
  
  IF (operatorGameIDCheck<>operatorGameID OR (isGameBlocked=1 AND ignorePlayLimit=0)) THEN 
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  
  IF (playerRestrictionEnabled) THEN
    SET @numRestrictions=0;
    SET @restrictionType=NULL;
    SELECT restriction_types.name, COUNT(*) INTO @restrictionType, @numRestrictions
    FROM gaming_player_restrictions FORCE INDEX (client_active_non_expired)
    STRAIGHT_JOIN gaming_player_restriction_types AS restriction_types ON 
		restriction_types.is_active=1 AND restriction_types.disallow_play=1 AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
    LEFT JOIN gaming_license_type ON gaming_player_restrictions.license_type_id=gaming_license_type.license_type_id
    WHERE (gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND restrict_until_date>NOW()) AND
		(restrict_from_date<NOW() AND (gaming_license_type.name IS NULL OR (gaming_license_type.name=licenseType OR gaming_license_type.name = 'all')));
  
    IF (@numRestrictions > 0) THEN
      SET statusCode=8;
      LEAVE root;
    END IF;
  END IF;  
  
  IF (ignoreSessionExpiry=0) THEN
    SELECT gaming_game_sessions.game_session_id, gaming_game_sessions.is_open, operator_game_id 
    INTO gameSessionID, isSessionOpen, operatorGameID 
    FROM gaming_game_sessions
    WHERE gaming_game_sessions.game_session_id=gameSessionID;
    
    IF (isSessionOpen=0) THEN
      SET statusCode=7;
      LEAVE root;
    END IF;
  END IF;
  
  IF (fraudEnabled AND ignorePlayLimit=0) THEN
    SELECT fraud_client_event_id, disallow_play 
    INTO fraudClientEventID, disallowPlay
    FROM gaming_fraud_client_events FORCE INDEX (client_id_current_event)
	STRAIGHT_JOIN gaming_fraud_classification_types ON 
		(gaming_fraud_client_events.client_id=clientID AND gaming_fraud_client_events.is_current=1) 
		AND gaming_fraud_client_events.fraud_classification_type_id=gaming_fraud_classification_types.fraud_classification_type_id;
  
    IF (fraudClientEventID<>-1 AND disallowPlay=1) THEN
      SET statusCode=3;
      LEAVE root;
    END IF;
  END IF;
  
  IF (gameRoundID IS NOT NULL) THEN
    SELECT gaming_game_round_types.name INTO roundType
    FROM gaming_game_rounds
    STRAIGHT_JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id
    WHERE gaming_game_rounds.game_round_id=gameRoundID;
  END IF;
  
  IF (roundType='Normal') THEN
    
    SET totalPlayerBalance = IF(disableBonusMoney=1 OR realMoneyOnly=1, balanceReal, balanceReal+(balanceBonus+balanceWinLocked)+(balanceFreeBet+balaneFreeBetWinLocked)+balanceBonusLost);
    
    IF (totalPlayerBalance < betAmount) THEN 
      SET statusCode=4;
      LEAVE root;
    END IF;
    
    
    IF (playLimitEnabled AND ignorePlayLimit=0) THEN 
      SET isLimitExceeded=PlayLimitCheckExceededWithGame(betAmount, sessionID, clientStatID, licenseType, gameID);
      IF (isLimitExceeded>0) THEN
        SET statusCode=5;
        LEAVE root;
      END IF;
    END IF;

	/* -- Used as pre-caution
    IF (bonusEnabledFlag AND realMoneyOnly=0) THEN
      SELECT IF(current_bonus_balance!=IFNULL(bonus_amount_remaining,0) OR current_bonus_win_locked_balance!=IFNULL(current_win_locked_amount,0), 1, 0) 
      INTO bonusMismatch 
      FROM gaming_client_stats 
      LEFT JOIN
      (
        SELECT client_stat_id, SUM(bonus_amount_remaining) AS bonus_amount_remaining, SUM(current_win_locked_amount) AS current_win_locked_amount
        FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses)
        WHERE gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 AND gaming_bonus_instances.is_free_rounds_mode=0
        GROUP BY client_stat_id
      ) AS PB ON gaming_client_stats.client_stat_id=PB.client_stat_id
      WHERE gaming_client_stats.client_stat_id=clientStatID; 
      
      IF (bonusMismatch=1) THEN
        CALL BonusAdjustBonusBalance(clientStatID);
      END IF;
    END IF;
    */
    
  END IF;
    
  SET dominantNoLoyaltyPoints = 0;
  SET loyaltyBetBonus=0;
  IF (roundType='Normal') THEN
    SET betRemain=betAmount;
    
    IF (disableBonusMoney=0 AND bonusEnabledFlag AND (numApplicableBonuses>0)) THEN 
      
      SET @betRemain=betRemain;
      SET @bonusCounter=0;
      SET @betReal=0;
      SET @betBonus=0;
      SET @betBonusWinLocked=0;
      SET @freeBetBonus=0;
      
      INSERT INTO gaming_game_plays_bet_counter (date_created, client_stat_id) VALUES (NOW(), clientStatID);
      SET gamePlayBetCounterID=LAST_INSERT_ID();
      
      INSERT INTO gaming_game_plays_bonus_instances_pre (game_play_bet_counter_id, bonus_instance_id, bet_total, bet_real, bet_bonus, bet_bonus_win_locked, bonus_order, no_loyalty_points)
      SELECT gamePlayBetCounterID, bonus_instance_id, bet_real+free_bet_bonus+bet_bonus+bet_bonus_win_locked AS bet_total, bet_real, bet_bonus+free_bet_bonus, bet_bonus_win_locked, bonusCounter, no_loyalty_points
      FROM
      (
        SELECT
          bonus_instance_id AS bonus_instance_id, 
          @freeBetBonus:=IF(realMoneyOnly, 0, IF(awarding_type='FreeBet', IF(bonus_amount_remaining>@betRemain, @betRemain, bonus_amount_remaining), 0)) AS free_bet_bonus,
		  @betRemain:=@betRemain-@freeBetBonus,   
          @betReal:=IF(@bonusCounter=0, IF(balanceReal>@betRemain, @betRemain, balanceReal), 0) AS bet_real,
		  @betRemain:=@betRemain-@betReal,  
          @betBonusWinLocked:=IF(realMoneyOnly, 0, IF(current_win_locked_amount>@betRemain, @betRemain, current_win_locked_amount)) AS bet_bonus_win_locked,
		  @betRemain:=@betRemain-@betBonusWinLocked,
          @betBonus:=IF(realMoneyOnly, 0, IF(awarding_type!='FreeBet',IF(bonus_amount_remaining>@betRemain, @betRemain, bonus_amount_remaining),0)) AS bet_bonus,
		  @betRemain:=@betRemain-@betBonus, @bonusCounter:=@bonusCounter+1 AS bonusCounter, no_loyalty_points
        FROM
        (
          SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_types_awarding.name AS awarding_type, bonus_amount_remaining, current_win_locked_amount, gaming_bonus_rules.no_loyalty_points
          FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses)
          STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
          STRAIGHT_JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
          STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
          STRAIGHT_JOIN gaming_bonus_rules_wgr_req_weights ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules_wgr_req_weights.bonus_rule_id AND gaming_bonus_rules_wgr_req_weights.operator_game_id=operatorGameID 
          LEFT JOIN sessions_main ON sessions_main.session_id=sessionID
          LEFT JOIN gaming_bonus_rules_platform_types AS platform_types ON gaming_bonus_rules.bonus_rule_id=platform_types.bonus_rule_id AND sessions_main.platform_type_id=platform_types.platform_type_id
          WHERE (gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 AND gaming_bonus_instances.is_free_rounds_mode=0) AND (gaming_bonus_rules.restrict_platform_type=0 OR platform_types.platform_type_id IS NOT NULL)
          ORDER BY gaming_bonus_types_awarding.`order` ASC, gaming_bonus_instances.priority ASC, gaming_bonus_instances.given_date ASC, gaming_bonus_instances.bonus_instance_id ASC
        ) AS XX
        HAVING free_bet_bonus!=0 OR bet_real!=0 OR bet_bonus!=0 OR bet_bonus_win_locked!=0
      ) AS XY;

      SELECT IFNULL(COUNT(*),0), SUM(bet_real), SUM(bet_bonus), SUM(bet_bonus_win_locked), 
		SUM(IF(no_loyalty_points, 0, bet_bonus+bet_bonus_win_locked)),
        SUM(IF(bonus_order = 1, no_loyalty_points, 0))
      INTO numBonuses, betReal, betBonus, betBonusWinLocked, loyaltyBetBonus, dominantNoLoyaltyPoints 
      FROM gaming_game_plays_bonus_instances_pre FORCE INDEX (PRIMARY)
      WHERE game_play_bet_counter_id=gamePlayBetCounterID;
      
      IF (numBonuses IS NULL OR numBonuses=0) THEN
        SET betReal=LEAST(betRemain, balanceReal); SET betBonus=0; SET betBonusWinLocked=0; SET betRemain=betRemain-betReal; 
      ELSE
        SET betRemain=betRemain-(betReal+betBonus+betBonusWinLocked);
      END IF;
    ELSE
      IF (betRemain > 0) THEN
        IF (balanceReal >= betRemain) THEN
          SET betReal=ROUND(betRemain, 5);
          SET betRemain=0;
        ELSE
          SET betReal=ROUND(balanceReal, 5);
          SET betRemain=ROUND(betRemain-betReal,0);
        END IF;
      END IF;
      SET betBonusWinLocked=0;
      SET betBonus=0;
    END IF;
	
	
    IF (betRemain > 0 AND allowUseBonusLost AND balanceBonusLost>=betRemain) THEN
        SET betBonusLost=betRemain;
		SET betRemain=0;
	END IF;
    
    IF (betRemain > 0) THEN
      SET statusCode=4;
      LEAVE root;
    END IF;
    
    SET betTotalBase=ROUND(betAmount/exchangeRate,5);  
  
  ELSEIF (roundType='FreeRound') THEN
    
    SET betTotalBase=0;
    SET betOther=betAmount;
    SET betReal=0;
    SET betBonus=0;
    SET betBonusWinLocked=0;
    SET betBonusLost=0;
    
  END IF;

  SELECT SUM(bet_bonus) INTO FreeBonusAmount 
  FROM gaming_game_plays_bonus_instances_pre FORCE INDEX (PRIMARY)
  STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id = gaming_game_plays_bonus_instances_pre.bonus_instance_id
  STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
  STRAIGHT_JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
  WHERE gaming_game_plays_bonus_instances_pre.game_play_bet_counter_id = gamePlayBetCounterID AND (gaming_bonus_types_awarding.name='FreeBet' OR is_free_bonus = 1);

  SET FreeBonusAmount = IFNULL(FreeBonusAmount,0);

  IF (loyaltyPointsEnabled=1) THEN
	  SELECT COALESCE(glpg.loyalty_points /glpg.amount, glpgc.loyalty_points / glpgc.amount, glpgc_parent.loyalty_points / glpgc_parent.amount, 0) * (betReal), 
			COALESCE(glpg.loyalty_points /glpg.amount, glpgc.loyalty_points / glpgc.amount, glpgc_parent.loyalty_points / glpgc_parent.amount, 0) * (loyaltyBetBonus) 
	  INTO loyaltyPoints, loyaltyPointsBonus
	  FROM gaming_games FORCE INDEX (PRIMARY)
	  STRAIGHT_JOIN gaming_game_categories_games ON gaming_games.game_id = gaming_game_categories_games.game_id
	  STRAIGHT_JOIN gaming_game_categories ON gaming_game_categories.game_category_id = gaming_game_categories_games.game_category_id
	  LEFT JOIN gaming_loyalty_points_games AS glpg ON gaming_games.game_id = glpg.game_id AND glpg.currency_id = currencyID AND glpg.vip_level_id = vipLevelID
	  LEFT JOIN gaming_loyalty_points_game_categories AS glpgc ON glpgc.game_category_id = gaming_game_categories.game_category_id
				AND glpgc.vip_level_id = vipLevelID AND glpgc.currency_id = currencyID
      LEFT JOIN gaming_loyalty_points_game_categories AS glpgc_parent ON glpgc_parent.game_category_id = gaming_game_categories.parent_game_category_id
				AND glpgc_parent.vip_level_id = vipLevelID AND glpgc_parent.currency_id = currencyID          
	  WHERE gaming_games.game_id = gameID AND (glpg.amount IS NOT NULL OR glpgc.amount IS NOT NULL OR glpgc_parent.amount IS NOT NULL)
	  LIMIT 1;

	  IF (dominantNoLoyaltyPoints=1) THEN
		SET loyaltyPoints = 0;
      END IF;
  ELSE
	  SET loyaltyPoints = 0;
	  SET loyaltyPointsBonus = 0;
  END IF;

  IF(vipLevelID IS NULL) THEN
     SET loyaltyPoints = 0;
     SET loyaltyPointsBonus = 0;
  ELSE
	SET loyaltyPoints=IFNULL(loyaltyPoints, 0);
    SET loyaltyPointsBonus=IFNULL(loyaltyPointsBonus, 0);
	  SELECT set_type INTO currentVipType FROM gaming_vip_levels vip WHERE vip.vip_level_id=vipLevelID;
  END IF;
  
  UPDATE gaming_client_stats AS gcs
  LEFT JOIN gaming_game_sessions AS ggs ON ggs.game_session_id=gameSessionID
  LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
  LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
  SET 
	gcs.total_wallet_real_played_online = IF(@channelType = 'online', gcs.total_wallet_real_played_online + betReal, gcs.total_wallet_real_played_online),
	gcs.total_wallet_real_played_retail = IF(@channelType = 'retail', gcs.total_wallet_real_played_retail + betReal, gcs.total_wallet_real_played_retail),
	gcs.total_wallet_real_played_self_service = IF(@channelType = 'self-service' ,gcs.total_wallet_real_played_self_service + betReal, gcs.total_wallet_real_played_self_service),
    gcs.total_wallet_real_played = gcs.total_wallet_real_played_online + gcs.total_wallet_real_played_retail + gcs.total_wallet_real_played_self_service,
	gcs.total_real_played = IF(@channelType NOT IN ('online','retail','self-service'),gcs.total_real_played+betReal, gcs.total_wallet_real_played + gcs.total_cash_played),
	gcs.locked_real_funds = GREATEST(0, gcs.locked_real_funds - betReal),

	gcs.current_real_balance=gcs.current_real_balance-betReal,
    gcs.total_bonus_played=gcs.total_bonus_played+betBonus, gcs.current_bonus_balance=gcs.current_bonus_balance-betBonus, 
    gcs.total_bonus_win_locked_played=gcs.total_bonus_win_locked_played+betBonusWinLocked, gcs.current_bonus_win_locked_balance=gcs.current_bonus_win_locked_balance-betBonusWinLocked, 
    gcs.total_real_played_base=gcs.total_real_played_base +IFNULL((betReal/exchangeRate),0), gcs.total_bonus_played_base=gcs.total_bonus_played_base+((betBonus+betBonusWinLocked)/exchangeRate),
    gcs.last_played_date=NOW(), gcs.current_bonus_lost=0,
	gcs.total_loyalty_points_given = gcs.total_loyalty_points_given + IFNULL(loyaltyPoints,0) , gcs.current_loyalty_points = gcs.current_loyalty_points + IFNULL(loyaltyPoints,0) ,
	gcs.total_loyalty_points_given_bonus = gcs.total_loyalty_points_given_bonus + IFNULL(loyaltyPointsBonus,0) ,
    gcs.loyalty_points_running_total = IF(currentVipType = 'LoyaltyPointsPeriod', gcs.loyalty_points_running_total + IFNULL(loyaltyPoints,0), gcs.loyalty_points_running_total),
	  
      ggs.total_bet=ggs.total_bet+betAmount, ggs.total_bet_base=ggs.total_bet_base+betTotalBase, ggs.bets=ggs.bets+1, ggs.total_bet_real=ggs.total_bet_real+betReal, ggs.total_bet_bonus=ggs.total_bet_bonus+betBonus+betBonusWinLocked,
	  ggs.loyalty_points=ggs.loyalty_points+ IFNULL(loyaltyPoints,0), ggs.loyalty_points_bonus=ggs.loyalty_points_bonus+ IFNULL(loyaltyPointsBonus,0),
      
      gcss.total_bet=gcss.total_bet+betAmount,gcss.total_bet_base=gcss.total_bet_base+betTotalBase, gcss.bets=gcss.bets+1, gcss.total_bet_real=gcss.total_bet_real+betReal, gcss.total_bet_bonus=gcss.total_bet_bonus+betBonus+betBonusWinLocked,
	  gcss.loyalty_points=gcss.loyalty_points+ IFNULL(loyaltyPoints,0), gcss.loyalty_points_bonus=gcss.loyalty_points_bonus+ IFNULL(loyaltyPointsBonus,0),	

      gcws.num_bets=gcws.num_bets+1, gcws.total_real_wagered=gcws.total_real_wagered+betReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered+betBonus+betBonusWinLocked,
      gcws.first_wagered_date=IFNULL(gcws.first_wagered_date, NOW()), gcws.last_wagered_date=NOW(),
      gcws.loyalty_points=gcws.loyalty_points+ IFNULL(loyaltyPoints,0), gcws.loyalty_points_bonus=gcws.loyalty_points_bonus+ IFNULL(loyaltyPointsBonus,0)
  WHERE gcs.client_stat_id = clientStatID;
  
	IF (isChipTransfer) THEN
		SET isProcessedCT =1 ;
		SET isRoundClosedCT = 1;
		SET dateTimeEndCT = NOW();
	END IF;

	
  IF (gameRoundID IS NULL) THEN

		INSERT INTO gaming_game_rounds
			(bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,bet_free_bet, bet_bonus_lost, jackpot_contribution, num_bets, num_transactions, date_time_start,date_time_end, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, round_ref, license_type_id,is_round_finished, balance_real_before, balance_bonus_before, loyalty_points, loyalty_points_bonus) 
		SELECT betAmount, betTotalBase, exchangeRate, betReal, betBonus, betBonusWinLocked,FreeBonusAmount, betBonusLost, jackpotContribution, 1, 1,NOW(), dateTimeEndCT, gameID, gameManufacturerID, operatorGameID, clientID, clientStatID, isProcessedCT, gaming_game_round_types.game_round_type_id, currencyID, roundRef, licenseTypeID ,isRoundClosedCT, balanceRealBefore, balanceBonusBefore, loyaltyPoints, loyaltyPointsBonus
		FROM gaming_game_round_types
		WHERE gaming_game_round_types.name=roundType;

		SET gameRoundID=LAST_INSERT_ID();
		SET isNewRound=1;
        SET roundNumTransactions=1;
  ELSE
		SET @roundNumTransactions=0;
        
		UPDATE gaming_game_rounds
		SET bet_total=bet_total+betAmount, bet_total_base=bet_total_base+betTotalBase, bet_real=bet_real+betReal, 
			bet_bonus=bet_bonus+betBonus, bet_bonus_win_locked=bet_bonus_win_locked+betBonusWinLocked,
            bet_free_bet=bet_free_bet + FreeBonusAmount, bet_bonus_lost=bet_bonus_lost+betBonusLost,
			jackpot_contribution=jackpot_contribution+jackpotContribution, num_bets=num_bets+1, num_transactions=(@roundNumTransactions:=(num_transactions+1)), 
			date_time_end=dateTimeEndCT, is_round_finished= isRoundClosedCT, 
            loyalty_points =loyalty_points + loyaltyPoints, loyalty_points_bonus = loyalty_points_bonus + loyaltyPointsBonus
		WHERE game_round_id=gameRoundID;
        
        SET roundNumTransactions=@roundNumTransactions;
  END IF;
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus,amount_free_bet, amount_bonus_win_locked, amount_other, bonus_lost, jackpot_contribution, 
   timestamp, game_id, game_manufacturer_id, operator_game_id, client_id, client_stat_id, session_id, game_session_id, game_round_id, payment_transaction_type_id, 
   balance_real_after, balance_bonus_after, is_win_placed, is_processed, currency_id, round_transaction_no, game_play_message_type_id, sign_mult, extra_id, 
   license_type_id, pending_bet_real, pending_bet_bonus, loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus, platform_type_id, 
   released_locked_funds) 
  SELECT betAmount, betTotalBase, exchangeRate, betReal, betBonus,FreeBonusAmount, betBonusWinLocked, betOther, betBonusLost, jackpotContribution, 
	NOW(), gameID, gameManufacturerID, operatorGameID, clientID, clientStatID, sessionID, gameSessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 
    current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, 0, 0, currencyID, roundNumTransactions, game_play_message_type_id, -1, gamePlayExtraID, 
    licenseTypeID, pending_bets_real, pending_bets_bonus, IFNULL(loyaltyPoints,0), IFNULL(gaming_client_stats.current_loyalty_points, 0),
	IFNULL(loyaltyPointsBonus,0), IFNULL(gaming_client_stats.total_loyalty_points_given_bonus - gaming_client_stats.total_loyalty_points_used_bonus,0), gaming_platform_types.platform_type_id, 
    LEAST(lockedRealFunds, betReal)
  FROM gaming_client_stats FORCE INDEX (PRIMARY)
  STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Bet'
  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=(IF(roundNumTransactions<=1,'InitialBet','AdditionalBet') COLLATE utf8_general_ci) 
  LEFT JOIN gaming_platform_types ON gaming_platform_types.platform_type=@platformType
  WHERE gaming_client_stats.client_stat_id=clientStatID;
  
  SET gamePlayID=LAST_INSERT_ID();   

  IF (fingFencedEnabled) THEN
	CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);  
  END IF;
  
  IF (ruleEngineEnabled) THEN
	INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 1, gamePlayID;
  END IF;
  
  IF(vipLevelID IS NOT NULL AND loyaltyPoints!=0) THEN
     CALL PlayerUpdateVIPLevel(clientStatID, 0);
  END IF;
  
  
  IF (playLimitEnabled AND roundType='Normal' AND betAmount > 0) THEN 
    CALL PlayLimitsUpdateWithGame(sessionID, clientStatID, licenseType, betAmount, 1, gameID);
  END IF;
  
  IF (taxEnabled) THEN
    #Check for tax cycles
	INSERT INTO gaming_tax_cycles (country_tax_id, client_stat_id, deferred_tax_amount, cycle_start_date, cycle_end_date, is_active, cycle_client_counter)
	SELECT gaming_country_tax.country_tax_id, gaming_client_stats.client_stat_id, 0, NOW(), '3000-01-01 00:00:00', 1, (SELECT COUNT(tax_cycle_id)+1 FROM gaming_tax_cycles WHERE client_stat_id = gaming_client_stats.client_stat_id)
		FROM gaming_country_tax
		JOIN gaming_countries as gc ON gaming_country_tax.country_id = gc.country_id
		JOIN clients_locations ON gaming_country_tax.country_id = clients_locations.country_id and clients_locations.is_active = 1
		JOIN gaming_client_stats ON gaming_client_stats.client_id = clients_locations.client_id AND gaming_client_stats.is_active = 1
		LEFT JOIN gaming_tax_cycles ON gaming_client_stats.client_stat_id = gaming_tax_cycles.client_stat_id 
			AND gaming_tax_cycles.country_tax_id = gaming_country_tax.country_tax_id
			AND gaming_tax_cycles.is_active = 1
	WHERE gaming_client_stats.client_stat_id = clientStatID
		AND gaming_country_tax.licence_type_id = licenseTypeID
		AND gaming_country_tax.is_active = 1
		AND gaming_country_tax.is_current = 1
		AND tax_cycle_id is null
		AND ((gc.casino_tax = 1 AND (licenseTypeID = 1)) OR (gc.sports_tax = 1 AND (licenseTypeID = 3)) OR (gc.poker_tax = 1 AND (licenseTypeID = 2)));
  END IF;
  
  IF (bonusEnabledFlag) THEN 
    IF (betAmount > 0 AND roundType='Normal' AND numBonuses>0) THEN 
      SET @transferBonusMoneyFlag=1;
      
      SET @betBonusDeductWagerRequirement=betAmount; 
      SET @wager_requirement_non_weighted=0;
      SET @wager_requirement_contribution=0;
      SET @betBonus=0;
      SET @betBonusWinLocked=0;
      SET @nowWagerReqMet=0;
      SET @hasReleaseBonus=0;
      
      INSERT INTO gaming_game_plays_bonus_instances (game_play_id, bonus_instance_id, bonus_rule_id, client_stat_id, timestamp, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,
        wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, 
        now_release_bonus, bonus_wager_requirement_remain_after)
      SELECT gamePlayID, bonus_instance_id, gaming_bonus_instances.bonus_rule_id, clientStatID, NOW(), exchangeRate,
        
        
            
        gaming_bonus_instances.bet_real, gaming_bonus_instances.bet_bonus, gaming_bonus_instances.bet_bonus_win_locked,
        
        @wager_requirement_non_weighted:=IF(gaming_bonus_instances.is_free_bonus=1,0,IF(ROUND(gaming_bonus_instances.bet_total*IFNULL(bonus_wgr_req_weigth, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain/IFNULL(bonus_wgr_req_weigth, 0)/IFNULL(license_weight_mod, 1), gaming_bonus_instances.bet_total)) AS wager_requirement_non_weighted, 
        @wager_requirement_contribution:=IF(gaming_bonus_instances.is_free_bonus=1,0,IF(ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,100000000*100),gaming_bonus_instances.bet_total)*IFNULL(bonus_wgr_req_weigth, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, ROUND(LEAST(IFNULL(wgr_restrictions.max_wager_contibution_before_weight,1000000*100),gaming_bonus_instances.bet_total)*IFNULL(bonus_wgr_req_weigth, 0)*IFNULL(license_weight_mod, 1), 5))) AS wager_requirement_contribution_pre,
        @wager_requirement_contribution:=IF(gaming_bonus_instances.is_free_bonus=1,0,LEAST(IFNULL(wgr_restrictions.max_wager_contibution,100000000*100), IF(wager_req_real_only OR bonusReqContributeRealOnly, ROUND(GREATEST(@wager_requirement_contribution-((gaming_bonus_instances.bet_bonus+gaming_bonus_instances.bet_bonus_win_locked)*IFNULL(bonus_wgr_req_weigth,0)*IFNULL(license_weight_mod, 1)),0), 5), @wager_requirement_contribution))) AS wager_requirement_contribution, 
        
        @nowWagerReqMet:=IF (bonus_wager_requirement_remain-@wager_requirement_contribution=0 AND gaming_bonus_instances.is_free_bonus=0,1,0) AS now_wager_requirement_met,
        
        IF (@nowWagerReqMet=0 AND is_release_bonus AND ((bonus_wager_requirement-bonus_wager_requirement_remain)+@wager_requirement_contribution)>=
          ((transfer_every_x_last+transfer_every_x_wager)*bonus_amount_given), 1, 0) AS now_release_bonus,
        bonus_wager_requirement_remain-@wager_requirement_contribution AS bonus_wager_requirement_remain_after
      FROM 
      (
        SELECT bonus_transaction.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, gaming_bonus_rules.wager_req_real_only, bonus_transaction.bet_total, bonus_transaction.bet_real, bonus_transaction.bet_bonus, bonus_transaction.bet_bonus_win_locked, bonus_wager_requirement_remain, IF(licenseTypeID=1,gaming_bonus_rules.casino_weight_mod, IF(licenseTypeID=2,gaming_bonus_rules.poker_weight_mod,1)) AS license_weight_mod,
          bonus_amount_given, bonus_wager_requirement, gaming_bonus_instances.transfer_every_x AS transfer_every_x_wager, gaming_bonus_instances.transfer_every_x_last, transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus') AS is_release_bonus,gaming_bonus_rules.is_free_bonus
        FROM gaming_game_plays_bonus_instances_pre AS bonus_transaction FORCE INDEX (PRIMARY)
        STRAIGHT_JOIN gaming_bonus_instances ON bonus_transaction.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
        STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
        STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
        WHERE bonus_transaction.game_play_bet_counter_id=gamePlayBetCounterID 
      ) AS gaming_bonus_instances  
      STRAIGHT_JOIN gaming_bonus_rules_wgr_req_weights ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules_wgr_req_weights.bonus_rule_id AND gaming_bonus_rules_wgr_req_weights.operator_game_id=operatorGameID 
      LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON gaming_bonus_instances.bonus_rule_id=wgr_restrictions.bonus_rule_id AND wgr_restrictions.currency_id=currencyID;

      IF (ROW_COUNT() > 0) THEN
        
        UPDATE gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
        STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
        SET bonus_amount_remaining=bonus_amount_remaining-bet_bonus, current_win_locked_amount=current_win_locked_amount-bet_bonus_win_locked,
            bonus_wager_requirement_remain=bonus_wager_requirement_remain-wager_requirement_contribution,
            is_secured=IF(now_wager_requirement_met=1,1,is_secured), secured_date=IF(now_wager_requirement_met=1,NOW(),NULL),
            gaming_bonus_instances.open_rounds=IF(isNewRound, gaming_bonus_instances.open_rounds+1, gaming_bonus_instances.open_rounds),
			gaming_bonus_instances.is_active=IF(is_active=0, 0, IF(now_wager_requirement_met=1,0,1))
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;           
		
        UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id) 
        STRAIGHT_JOIN gaming_bonus_instances ON ggpbi.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
        STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
        STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
        SET 
            ggpbi.bonus_transfered_total=(CASE transfer_type.name
              WHEN 'All' THEN bonus_amount_remaining+current_win_locked_amount
              WHEN 'Bonus' THEN bonus_amount_remaining
              WHEN 'BonusWinLocked' THEN current_win_locked_amount
              WHEN 'UpToBonusAmount' THEN LEAST(bonus_amount_given, bonus_amount_remaining+current_win_locked_amount)
              WHEN 'UpToPercentage' THEN LEAST(bonus_amount_given*transfer_upto_percentage, bonus_amount_remaining+current_win_locked_amount)
              WHEN 'ReleaseBonus' THEN LEAST(IFNULL(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total,0), bonus_amount_remaining+current_win_locked_amount)
              WHEN 'ReleaseAllBonus' THEN bonus_amount_remaining+current_win_locked_amount
              ELSE 0
            END),
            ggpbi.bonus_transfered=IF(transfer_type.name='BonusWinLocked', 0, LEAST(IFNULL(ggpbi.bonus_transfered_total,0), bonus_amount_remaining)),
            ggpbi.bonus_win_locked_transfered=IF(transfer_type.name='Bonus', 0, IFNULL(ggpbi.bonus_transfered_total,0)-ggpbi.bonus_transfered),
            bonus_transfered_lost=bonus_amount_remaining-bonus_transfered,
            bonus_win_locked_transfered_lost=current_win_locked_amount-bonus_win_locked_transfered,
            bonus_amount_remaining=0,current_win_locked_amount=0, current_ring_fenced_amount=0,  
            gaming_bonus_instances.bonus_transfered_total=IFNULL(gaming_bonus_instances.bonus_transfered_total,0)+IFNULL(ggpbi.bonus_transfered_total,0),
            gaming_bonus_instances.session_id=sessionID
        WHERE ggpbi.game_play_id=gamePlayID AND now_wager_requirement_met=1 AND now_used_all=0;
      
        
        SET @requireTransfer=0;
        SET @bonusTransfered=0;
        SET @bonusWinLockedTransfered=0;
        SET @bonusTransferedLost=0;
        SET @bonusWinLockedTransferedLost=0;

		SET @ringFencedAmount=0;
		SET @ringFencedAmountSB=0;
		SET @ringFencedAmountCasino=0;
		SET @ringFencedAmountPoker=0;
        
        SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0)  ,
		ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
        INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
		@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
        FROM gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
		LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id	
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_wager_requirement_met=1 AND now_used_all=0;

        SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
        SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;
        IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
          CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusRequirementMet', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker, NULL);
        END IF; 
        
        UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
        STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=ggpbi.bonus_instance_id
        STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
        STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON 
          gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id AND transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus')
        SET 
            ggpbi.bonus_transfered_total=LEAST(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))* 
              gaming_bonus_instances.transfer_every_amount, 
              bonus_amount_remaining+current_win_locked_amount), 
            ggpbi.bonus_transfered=LEAST(IFNULL(ggpbi.bonus_transfered_total,0), bonus_amount_remaining),
            ggpbi.bonus_win_locked_transfered=IFNULL(ggpbi.bonus_transfered_total,0)-ggpbi.bonus_transfered,
            bonus_amount_remaining=bonus_amount_remaining-bonus_transfered, current_win_locked_amount=current_win_locked_amount-bonus_win_locked_transfered,  
            gaming_bonus_instances.transfer_every_x_last=gaming_bonus_instances.transfer_every_x_last+(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))*gaming_bonus_instances.transfer_every_x),
            gaming_bonus_instances.bonus_transfered_total=IFNULL(gaming_bonus_instances.bonus_transfered_total,0)+IFNULL(ggpbi.bonus_transfered_total,0),
            gaming_bonus_instances.session_id=sessionID
        WHERE ggpbi.game_play_id=gamePlayID AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;
        
        SET @requireTransfer=0;
        SET @bonusTransfered=0;
        SET @bonusWinLockedTransfered=0;
        SET @bonusTransferedLost=0;
        SET @bonusWinLockedTransferedLost=0;
		SET @ringFencedAmount=0;
		SET @ringFencedAmountSB=0;
		SET @ringFencedAmountCasino=0;
		SET @ringFencedAmountPoker=0;
        
        SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0) ,
		ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
        INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
		@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
        FROM gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
		LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;

        SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
        SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;
        IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
          CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusCashExchange', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker, NULL);
        END IF; 
      
      END IF; 
    
      
    END IF; 
  END IF; 
  
  CALL PlayReturnData(gamePlayID, gameRoundID, clientStatID , operatorGameID, minimalData);
  
  SET gamePlayIDReturned = gamePlayID;
  SET statusCode=0;
END$$

DELIMITER ;

