DROP procedure IF EXISTS `CommonWalletSportsGenericGetFunds`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSportsGenericGetFunds`(
  sbBetID BIGINT, clientStatID BIGINT, canCommit TINYINT(1), minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN

  -- First Version :) 
  -- Bonuses' wagering requiremnt updating is moved to CommonWalletSportsGenericPlaceBet
  -- Inserts into gaming_game_plays_bonus_instances has been moved to CommonWalletSportsGenericPlaceBet	  
  -- Inserting single multiple type if doesn't exist
  -- Moved partitioning of funds to another SP
  -- Sports Book v2
  -- Minor trail change
  -- For Multiples storing as much as possible the sports book entities which are common for better and easier aggregations
  -- Forced indices
  -- Optimized for Parititioning
  
  DECLARE betAmount, totalPlayerBalance, betReal, betFreeBet, betFreeBetWinLocked, betBonus, betBonusWinLocked, lockedRealFunds DECIMAL(18, 5) DEFAULT 0;
  DECLARE balanceReal, balanceFreeBet, balaneFreeBetWinLocked, balanceBonus, balanceWinLocked, betRemain, exchangeRate, sbOdd, FreeBonusAmount DECIMAL(18, 5) DEFAULT 0;
  DECLARE sbBetIDCheck, sessionID, clientStatID, clientStatIDStat, clientStatIDCheck, clientID, gamePlayID, 
	currencyID, fraudClientEventID, gameRoundID, gameSessionID, wagerGamePlayID, singleMultTypeID, parentGameRoundID BIGINT DEFAULT -1;
  DECLARE ignoreSessionExpiry, ignorePlayLimit, playerRestrictionEnabled, playLimitEnabled, isLimitExceeded, 
	bonusEnabledFlag, disableBonusMoney, isAccountClosed, fraudEnabled, disallowPlay, 
    isPlayAllowed, useFreeBet, licenceCountryRestriction, fingFencedEnabled, ruleEngineEnabled,
    taxEnabled TINYINT(1) DEFAULT 0;
  DECLARE clientWagerTypeID, sessionStatusCode, sessionCheckStatusCode INT DEFAULT -1;
  DECLARE transactionRef VARCHAR(40) DEFAULT NULL;
  DECLARE gameManufacturerID, gameID BIGINT DEFAULT NULL; 
  DECLARE numSingles, numMultiples INT DEFAULT 0;
  DECLARE roundType, licenseType, transactionTypeString VARCHAR(20) DEFAULT NULL; 
  DECLARE licenseTypeID TINYINT(4) DEFAULT 3; -- sports
  DECLARE numBonusInstances BIGINT DEFAULT 0;
  DECLARE balanceRealBefore, balanceBonusBefore DECIMAL(18,5) DEFAULT 0;
  DECLARE liveBetType, deviceType INT DEFAULT 1; -- To Change !!
  DECLARE bonusReqContributeRealOnly, isCouponBet TINYINT(1) DEFAULT 0;
  
  DECLARE partitioningMinusFromMax INT DEFAULT 10000;
  DECLARE minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, 
	minSbBetMultipleSingleID, maxSbBetMultipleSingleID, minGameRoundID, maxGameRoundID, 
    minGamePlaySBID, maxGamePlaySBID BIGINT DEFAULT NULL; 
  
  -- *****************************************************
  -- Loyalty Points Bonus variables
  -- *****************************************************
  DECLARE loyaltyPointsEnabledWager, loyaltyPointsEnabled TINYINT(1) DEFAULT 0;
  DECLARE loyaltyPointsBonus, loyaltyPoints, totalLoyaltyPointsGivenBonus, totalLoyaltyPointsUsedBonus,
    loyaltyPointsAmount, loyaltyPointsAward DECIMAL(18,5) DEFAULT 0;
  DECLARE vipLevelID INT;
  DECLARE currentVipType VARCHAR(100) DEFAULT '';

  SET licenseType='sportsbook';
  SET gameSessionID = NULL;
  SET statusCode=0;
  
  -- Loading the betslip data   
  SELECT IF (gaming_sb_bets.status_code!=1, gaming_sb_bets.detailed_status_code, 0), IF(gaming_sb_bets.status_code != 4, gaming_sb_bets.wager_game_play_id, NULL), 
	gaming_sb_bets.client_stat_id, gaming_client_stats.client_id, gaming_sb_bets.bet_total, 
	gaming_sb_bets.transaction_ref, gaming_sb_bets.num_singles, gaming_sb_bets.num_multiplies, gaming_sb_bets.use_free_bet,
	gaming_sb_bets.game_manufacturer_id, gaming_game_manufacturers.cw_disable_bonus_money, 
	current_loyalty_points, total_loyalty_points_given_bonus, total_loyalty_points_used_bonus,
    IF(gaming_lottery_dbg_tickets.lottery_dbg_ticket_id IS NOT NULL, 1, 0), 
	gaming_sb_bets.sb_bet_type_id, gaming_lottery_dbg_tickets.game_id,
	gsbpf.max_sb_bet_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_single_id, 
    gsbpf.max_sb_bet_multiple_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_id,
    gsbpf.max_sb_bet_multiple_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_single_id,
    gsbpf.min_game_round_id, gsbpf.max_game_round_id, IFNULL(gaming_sb_bets.wager_game_play_id, -1)
  INTO statusCode, wagerGamePlayID, 
	clientStatID, clientID, betAmount, 
    transactionRef, numSingles, numMultiples, useFreeBet, 
    gameManufacturerID, disableBonusMoney, 
    loyaltyPoints, totalLoyaltyPointsGivenBonus, totalLoyaltyPointsUsedBonus,
    isCouponBet, liveBetType, gameID,
    minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, minSbBetMultipleSingleID, maxSbBetMultipleSingleID,
    minGameRoundID, maxGameRoundID, gamePlayID
  FROM gaming_sb_bets FORCE INDEX (PRIMARY)
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=gaming_sb_bets.client_stat_id
  STRAIGHT_JOIN gaming_game_manufacturers ON gaming_sb_bets.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
  LEFT JOIN gaming_sb_bets_partition_fields AS gsbpf ON gsbpf.sb_bet_id=gaming_sb_bets.sb_bet_id
  LEFT JOIN gaming_lottery_dbg_tickets ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = gaming_sb_bets.lottery_dbg_ticket_id
  WHERE gaming_sb_bets.sb_bet_id=sbBetID
  ORDER BY gaming_sb_bets.sb_bet_id DESC
  LIMIT 1;

  IF (clientStatID=-1) THEN
	SET statusCode=50;
	LEAVE root;
  END IF;

    -- check if the bet is already prcocessed 
  IF (statusCode!=0 OR IFNULL(wagerGamePlayID,-1)!=-1) THEN
	SET statusCode=IF(statusCode=0, 51, statusCode);
	IF (isCouponBet) THEN 
		
        SELECT game_round_id INTO gameRoundID FROM gaming_game_plays WHERE game_play_id = wagerGamePlayID;
        
		CALL PlayReturnDataWithoutGame(wagerGamePlayID, gameRoundID, clientStatID, gameManufacturerID, minimalData);
		CALL PlayReturnBonusInfoOnBet(wagerGamePlayID);
	ELSE
		CALL CommonWalletSBReturnData(sbBetID, clientStatID, wagerGamePlayID, minimalData);
	END IF;

    LEAVE root;
  END IF;
  
    -- player settings and session information
  SELECT gaming_clients.is_account_closed OR IFNULL(gaming_fraud_rule_client_settings.block_account, 0), 
	gaming_clients.is_play_allowed AND !IFNULL(gaming_fraud_rule_client_settings.block_gameplay, 0), 
    sessions_main.session_id, sessions_main.status_code, vip_level_id
  INTO isAccountClosed, isPlayAllowed, sessionID, sessionStatusCode, vipLevelID
  FROM gaming_clients
  STRAIGHT_JOIN sessions_main FORCE INDEX (client_latest_session) ON sessions_main.extra_id=gaming_clients.client_id AND sessions_main.is_latest
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
  WHERE gaming_clients.client_id=clientID;
  
  CALL CommonWalletCheckSessionByID(sessionID, 0, 1, 1, sessionCheckStatusCode);
  
  IF (numSingles>0) THEN

	-- Insert the multiple type if doesn't exist (should be very rare, ideally never)
    SELECT sb_multiple_type_id INTO singleMultTypeID FROM gaming_sb_multiple_types WHERE name='Single' AND game_manufacturer_id=gameManufacturerID; 

    IF (singleMultTypeID=-1) THEN
      INSERT INTO gaming_sb_multiple_types (name, ext_name, `order`, game_manufacturer_id)
      SELECT 'Single', 'Single', 100, gameManufacturerID;
	  SELECT LAST_INSERT_ID() INTO singleMultTypeID;
    END IF;

    -- updating the singles table bet_id's with our own Id's  
    UPDATE gaming_sb_bet_singles FORCE INDEX (sb_bet_id)
    STRAIGHT_JOIN gaming_sb_groups FORCE INDEX (ext_group_id) ON 
		gaming_sb_bet_singles.ext_group_id=gaming_sb_groups.ext_group_id AND 
        gaming_sb_groups.game_manufacturer_id=gameManufacturerID
    STRAIGHT_JOIN gaming_sb_events FORCE INDEX (unique_event) ON 
		gaming_sb_bet_singles.ext_event_id=gaming_sb_events.ext_event_id AND 
        gaming_sb_events.sb_group_id=gaming_sb_groups.sb_group_id
    STRAIGHT_JOIN gaming_sb_markets FORCE INDEX (unique_market) ON 
		gaming_sb_bet_singles.ext_market_id=gaming_sb_markets.ext_market_id AND 
        gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    STRAIGHT_JOIN gaming_sb_selections FORCE INDEX (unique_selection) ON 
		gaming_sb_bet_singles.ext_selection_id=gaming_sb_selections.ext_selection_id AND 
        gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id AND 
        gaming_sb_selections.name=IFNULL(gaming_sb_bet_singles.ext_selection_name, gaming_sb_selections.name)
    SET gaming_sb_bet_singles.sb_selection_id=gaming_sb_selections.sb_selection_id
    WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID AND 
		-- parition filtering
		gaming_sb_bet_singles.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID;
    
  END IF; 
            
  IF (numMultiples>0) THEN
    -- Insert the multiple type if doesn't exist (should be very rare, ideally never)
    INSERT INTO gaming_sb_multiple_types (name, ext_name, `order`, game_manufacturer_id)
    SELECT ext_multiple_type, ext_multiple_type, 100, gameManufacturerID
    FROM gaming_sb_bet_multiples FORCE INDEX (sb_bet_id)
    WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID AND 
		-- parition filtering
        gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID AND
        -- other filtering
		gaming_sb_bet_multiples.ext_multiple_type NOT IN (SELECT ext_name FROM gaming_sb_multiple_types WHERE game_manufacturer_id=gameManufacturerID);
  
    -- update the multiple_type_id with our own Id's
    UPDATE gaming_sb_bet_multiples FORCE INDEX (sb_bet_id)
    STRAIGHT_JOIN gaming_sb_multiple_types ON 
		gaming_sb_bet_multiples.ext_multiple_type=gaming_sb_multiple_types.ext_name AND 
        gaming_sb_multiple_types.game_manufacturer_id=gameManufacturerID
    SET gaming_sb_bet_multiples.sb_multiple_type_id=gaming_sb_multiple_types.sb_multiple_type_id
    WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID AND
		-- parition filtering
		gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID;
  
    -- update the sb_selection_id with our own Id's
    UPDATE gaming_sb_bet_multiples FORCE INDEX (sb_bet_id)
    STRAIGHT_JOIN gaming_sb_bet_multiples_singles FORCE INDEX (sb_bet_multiple_id) ON 
		gaming_sb_bet_multiples_singles.sb_bet_multiple_id=gaming_sb_bet_multiples.sb_bet_multiple_id AND
        -- parition filtering
        gaming_sb_bet_multiples_singles.sb_bet_multiple_single_id BETWEEN minSbBetMultipleSingleID AND maxSbBetMultipleSingleID
    STRAIGHT_JOIN gaming_sb_groups FORCE INDEX (ext_group_id) ON 
		gaming_sb_bet_multiples_singles.ext_group_id=gaming_sb_groups.ext_group_id AND 
        gaming_sb_groups.game_manufacturer_id=gameManufacturerID
    STRAIGHT_JOIN gaming_sb_events FORCE INDEX (unique_event) ON 
		gaming_sb_bet_multiples_singles.ext_event_id=gaming_sb_events.ext_event_id AND 
        gaming_sb_events.sb_group_id=gaming_sb_groups.sb_group_id
    STRAIGHT_JOIN gaming_sb_markets FORCE INDEX (unique_market) ON 
		gaming_sb_bet_multiples_singles.ext_market_id=gaming_sb_markets.ext_market_id AND 
        gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    STRAIGHT_JOIN gaming_sb_selections FORCE INDEX (unique_selection) ON 
		gaming_sb_bet_multiples_singles.ext_selection_id=gaming_sb_selections.ext_selection_id AND 
        gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id AND 
        gaming_sb_selections.name=IFNULL(gaming_sb_bet_multiples_singles.ext_selection_name,gaming_sb_selections.name)
    SET gaming_sb_bet_multiples_singles.sb_selection_id=gaming_sb_selections.sb_selection_id
    WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID AND
		-- parition filtering
		gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID;

  END IF;

  -- getting the balance and locking the player stats 
  SELECT client_stat_id, gaming_client_stats.client_id, currency_id, current_real_balance, 
	current_bonus_balance, current_bonus_win_locked_balance, locked_real_funds
  INTO clientStatIDCheck, clientID, currencyID, balanceReal, balanceBonus, balanceWinLocked, lockedRealFunds
  FROM gaming_client_stats
  WHERE gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.is_active=1 
  FOR UPDATE;
  
  SET balanceRealBefore=balanceReal;
  SET balanceBonusBefore=balanceBonus+balanceWinLocked;
  
  -- system settings based on operator - per site
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, gs4.value_bool, 
	IFNULL(gs5.value_bool,0) AS vb5, IFNULL(gs6.value_bool,0) AS vb6, IFNULL(gs7.value_bool,0) AS vb7, 
    IFNULL(gs8.value_bool,0) AS vb8, IFNULL(gs9.value_bool,0) AS vb9 
    INTO playLimitEnabled, bonusEnabledFlag, fraudEnabled, playerRestrictionEnabled, 
    licenceCountryRestriction, loyaltyPointsEnabledWager, fingFencedEnabled, ruleEngineEnabled,
    taxEnabled
    FROM gaming_settings gs1 
    STRAIGHT_JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
    STRAIGHT_JOIN gaming_settings gs3 ON (gs3.name='FRAUD_ENABLED')
    STRAIGHT_JOIN gaming_settings gs4 ON (gs4.name='PLAYER_RESTRICTION_ENABLED')
	STRAIGHT_JOIN gaming_settings gs5 ON (gs5.name='LICENCE_COUNTRY_RESTRICTION_ENABLED')
	LEFT JOIN gaming_settings gs6 ON (gs6.name='LOYALTY_POINTS_WAGER_ENABLED')
	LEFT JOIN gaming_settings gs7 ON (gs7.name='RING_FENCED_ENABLED')
    LEFT JOIN gaming_settings gs8 ON (gs8.name='RULE_ENGINE_ENABLED')
    LEFT JOIN gaming_settings gs9 ON (gs9.name='TAX_ON_GAMEPLAY_ENABLED')
    WHERE gs1.name='PLAY_LIMIT_ENABLED';
  
  IF(licenceCountryRestriction) THEN
	  SELECT license_type_id INTO licenseTypeID FROM gaming_license_type WHERE name = licenseType;
	  -- Check if there are any country/ip restrictions for this player 
	  IF (SELECT !WagerRestrictionCheckCanWager(licenseTypeID, sessionID)) THEN 
		SET statusCode=15; 
		LEAVE root;
	  END IF;
  END IF;
      
  if (clientStatIDCheck=-1 OR isAccountClosed=1) THEN
    SET statusCode=1;
  ELSEIF (isPlayAllowed=0 AND ignorePlayLimit=0) THEN 
    SET statusCode=6; 
  ELSEIF (betAmount > (balanceReal+balanceBonus+balanceWinLocked)) THEN
    SET statusCode=4;
  ELSEIF (sessionStatusCode!=1 OR sessionCheckStatusCode!=0) THEN
    SET statusCode=7;
  END IF;    
  
  -- Check that there are no player restrictions disallowing play
  IF (statusCode=0 AND playerRestrictionEnabled) THEN
    SET @numRestrictions=0;
    SET @restrictionType=NULL;
    SELECT restriction_types.name, COUNT(*) INTO @restrictionType, @numRestrictions
    FROM gaming_player_restrictions
    STRAIGHT_JOIN gaming_player_restriction_types AS restriction_types ON 
		restriction_types.is_active=1 AND restriction_types.disallow_play=1 AND 
		gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
    LEFT JOIN gaming_license_type ON gaming_player_restrictions.license_type_id=gaming_license_type.license_type_id
    WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date AND
      (gaming_license_type.name IS NULL OR gaming_license_type.name in ('Sportsbook','All'));
  
    IF (@numRestrictions > 0) THEN
      SET statusCode=8;
    END IF;
  END IF;  
  
  -- Check if the player is allowed to play by the fraud engine
  IF (statusCode=0 AND fraudEnabled AND ignorePlayLimit=0) THEN
    SELECT fraud_client_event_id, disallow_play 
    INTO fraudClientEventID, disallowPlay
    FROM gaming_fraud_client_events 
    STRAIGHT_JOIN gaming_fraud_classification_types ON gaming_fraud_client_events.client_stat_id=clientStatID AND gaming_fraud_client_events.is_current=1
      AND gaming_fraud_client_events.fraud_classification_type_id=gaming_fraud_classification_types.fraud_classification_type_id;
  
    IF (fraudClientEventID<>-1 AND disallowPlay=1) THEN
      SET statusCode=3;
    END IF;
  END IF;
  
  -- Check the player bet limits
  IF (statusCode=0 AND playLimitEnabled AND ignorePlayLimit=0) THEN 
    SET isLimitExceeded=PlayLimitCheckExceeded(betAmount, sessionID, clientStatID, licenseType);
    IF (isLimitExceeded > 0) THEN
      IF (isLimitExceeded = 10) THEN
  	    SET statusCode = 52;
       ELSE
        SET statusCode = 5;
      END IF;
    END IF;
  END IF;
   
  -- if the transaction is rejected return
  IF (statusCode!=0) THEN
    UPDATE gaming_sb_bets SET status_code=2, detailed_status_code=statusCode WHERE sb_bet_id=sbBetID;
    CALL CommonWalletSBReturnData(sbBetID, clientStatID, NULL, minimalData); 
    LEAVE root;
  END IF;
  
  -- insert into gaming_sb_bets_bonus_rules
  CALL CommonWalletSportsGenericCalculateBonusRuleWeight(sessionID, clientStatID, sbBetID, numSingles, numMultiples);
  
  -- If the player doesn't have enough balance return   
  IF (statusCode!=0) THEN
    UPDATE gaming_sb_bets 
    SET status_code=2, detailed_status_code=statusCode 
    WHERE sb_bet_id=sbBetID;
    
    SELECT gaming_sb_bets.sb_bet_id, transaction_ref, gaming_sb_bets.status_code, gaming_sb_bets_statuses.status, timestamp, bet_total AS amount_total, 
		amount_real, amount_bonus+amount_bonus_win_locked AS amount_bonus 
    FROM gaming_sb_bets 
    STRAIGHT_JOIN gaming_sb_bets_statuses ON gaming_sb_bets.status_code=gaming_sb_bets_statuses.status_code 
    WHERE gaming_sb_bets.sb_bet_id=sbBetID;
    
    LEAVE root;
  END IF; 
       
  -- Partition the bet between free bet, real, bonus and bonus win locked
  CALL PlaceBetPartitionWagerComponentsForSports(clientStatID, sbBetID, betAmount, bonusEnabledFlag, disableBonusMoney, useFreeBet, 
	0, numBonusInstances, betReal, betBonus, betBonusWinLocked, betFreeBet, betFreeBetWinLocked, @badDeptReal, statusCode);
  
  IF (statusCode > 0) THEN
    SET statusCode=4;
    LEAVE root;
  END IF;
  
  IF (betBonus+betBonusWinLocked > 0) THEN

	SET @BonusCounter =0;
    SET @betBonusDeduct=betBonus;
    SET @betBonusDeductWinLocked=betBonusWinLocked;

    INSERT INTO gaming_sb_bets_bonuses (sb_bet_id, bonus_instance_id, amount_total, amount_real, amount_bonus, amount_bonus_win_locked, amount_bonus_deduct, amount_bonus_win_locked_deduct, bonus_order)
    SELECT sbBetID, bonus_instance_id, bet_real+bet_bonus+bet_bonus_win_locked, bet_real, bet_bonus,  bet_bonus_win_locked, bonusDeductRemain, bonusWinLockedRemain, bonus_order
	FROM (
		SELECT sbBetID, bonus_instance_id, 
			@BonusCounter := @BonusCounter +1 AS bonus_order,
			@BetReal :=IF(@BonusCounter=1,betReal,0) AS bet_real,
			@betBonus:=IF(@betBonusDeduct>=bonus_amount_remaining, bonus_amount_remaining, @betBonusDeduct) AS bet_bonus,
			@betBonusWinLocked:=IF(@betBonusDeductWinLocked>=current_win_locked_amount,current_win_locked_amount,@betBonusDeductWinLocked) AS bet_bonus_win_locked,
			@betBonusDeduct:=GREATEST(0, @betBonusDeduct-@betBonus) AS bonusDeductRemain, 
			@betBonusDeductWinLocked:=GREATEST(0, @betBonusDeductWinLocked-@betBonusWinLocked) AS bonusWinLockedRemain
			FROM 
			(
			  SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, IF(useFreeBet, 0, current_win_locked_amount) AS current_win_locked_amount, IF(useFreeBet, IF(gaming_bonus_types_awarding.name='FreeBet', bonus_amount_remaining, 0), IF(gaming_bonus_types_awarding.name='FreeBet', 0, bonus_amount_remaining)) AS bonus_amount_remaining
			  FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses)
			  STRAIGHT_JOIN gaming_sb_bets_bonus_rules ON gaming_sb_bets_bonus_rules.sb_bet_id=sbBetID AND gaming_bonus_instances.bonus_rule_id=gaming_sb_bets_bonus_rules.bonus_rule_id
			  STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
			  STRAIGHT_JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
			  WHERE client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 
			  ORDER BY gaming_bonus_types_awarding.`order` ASC, gaming_bonus_instances.priority ASC, gaming_bonus_instances.bonus_instance_id ASC
			) AS gaming_bonus_instances  
			HAVING bet_bonus > 0 OR bet_bonus_win_locked > 0
	) AS b;
    
    -- Update the remaining bonus balance
    UPDATE gaming_sb_bets_bonuses FORCE INDEX (PRIMARY)
    STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_sb_bets_bonuses.bonus_instance_id
    SET bonus_amount_remaining=bonus_amount_remaining-amount_bonus,
	  current_win_locked_amount=current_win_locked_amount-amount_bonus_win_locked,
	  reserved_bonus_funds = reserved_bonus_funds + amount_bonus + amount_bonus_win_locked
    WHERE gaming_sb_bets_bonuses.sb_bet_id=sbBetID;   

  END IF;
  
  -- Check how much of the bonus money was from Free Bet
  SELECT SUM(amount_bonus) 
  INTO FreeBonusAmount 
  FROM gaming_sb_bets_bonuses FORCE INDEX (PRIMARY)
  STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id = gaming_sb_bets_bonuses.bonus_instance_id
  STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
  STRAIGHT_JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
  WHERE gaming_sb_bets_bonuses.sb_bet_id = sbBetID AND (gaming_bonus_types_awarding.name='FreeBet' OR is_free_bonus = 1);

  -- update the player's balance
  UPDATE gaming_client_stats AS gcs
  SET current_real_balance=current_real_balance-betReal, current_bonus_balance=current_bonus_balance-betBonus, 
	  current_bonus_win_locked_balance=current_bonus_win_locked_balance-betBonusWinLocked,
      pending_bets_real=pending_bets_real+betReal, pending_bets_bonus=pending_bets_bonus+betBonus+betBonusWinLocked,
	  locked_real_funds = GREATEST(0, locked_real_funds - betReal)
  WHERE gcs.client_stat_id = clientStatID;

  -- Get  the exchange rate
  SELECT exchange_rate into exchangeRate 
  FROM gaming_client_stats
  STRAIGHT_JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
  WHERE gaming_client_stats.client_stat_id=clientStatID
  LIMIT 1;

  -- check if parent row already exists 
  SET parentGameRoundID = IFNULL(minGameRoundID, -1);

  IF (parentGameRoundID != -1) THEN
      UPDATE gaming_game_rounds
        SET bet_total = betAmount,
		bet_total_base = ROUND(betAmount/exchangeRate,5),
		exchange_rate = exchangeRate,
		bet_real = betReal,
        bet_bonus = betBonus,
        bet_bonus_win_locked = betBonusWinLocked,
        num_transactions = num_transactions + 1,
        balance_real_before = balanceRealBefore,
        balance_bonus_before = balanceBonusBefore, 
        loyalty_points = loyaltyPoints,
        loyalty_points_bonus = loyaltyPointsBonus,
		win_total = 0, win_total_base = 0, win_real = 0, win_bonus = 0, win_bonus_win_locked = 0, win_free_bet = 0, win_bet_diffence_base = 0, bonus_lost = 0,
        bonus_win_locked_lost = 0, date_time_end = NULL, is_round_finished = 0, amount_tax_operator_original = NULL, amount_tax_player_original = NULL,
		is_cancelled = 0
      WHERE game_round_id = parentGameRoundID;

  	  SET gameRoundID = parentGameRoundID;
  ELSE 
	  -- insert parent round
	  INSERT INTO gaming_game_rounds (bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked, bet_bonus_lost, 
		num_bets, num_transactions, date_time_start, game_manufacturer_id, client_id, client_stat_id, is_processed, game_round_type_id, 
        currency_id, round_ref, license_type_id, is_round_finished,balance_real_before, balance_bonus_before, loyalty_points, loyalty_points_bonus, sb_bet_id) 
	  SELECT betAmount, ROUND(betAmount/exchangeRate,5), exchangeRate, betReal, betBonus, betBonusWinLocked, 0, 
		(numSingles + numMultiples), 1, NOW(), gameManufacturerID, clientID, clientStatID, 1, gaming_game_round_types.game_round_type_id, 
        currencyID, sbBetID, licenseTypeID ,1, balanceRealBefore, balanceBonusBefore, loyaltyPoints, loyaltyPointsBonus, sbBetID
	  FROM gaming_game_round_types
	  WHERE gaming_game_round_types.name='Sports';
	  
	  SET gameRoundID=LAST_INSERT_ID();
      SET parentGameRoundID=gameRoundID;
      SET minGameRoundID=gameRoundID;
  END IF;
  
  -- CPREQ-294 : if it is the first bet then 'Bet' else 'BetAdjustment'
  SET transactionTypeString = IF (gamePlayID=-1, 'Bet', 'BetAdjustment');
  
  -- Insert one entry for the betslip
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_free_bet, amount_other, bonus_lost, jackpot_contribution, 
   timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, 
   pending_bet_real, pending_bet_bonus, currency_id, sign_mult, sb_bet_id, license_type_id, loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus,
   confirmed_amount, is_confirmed, game_play_message_type_id, game_round_id, is_win_placed, game_id, released_locked_funds) 
  SELECT betAmount, betAmount/exchangeRate, exchangeRate, betReal, betBonus, betBonusWinLocked, IFNULL(FreeBonusAmount,0), 0, 0, 0, 
	NOW(), gameManufacturerID, clientID, clientStatID, sessionID, gaming_payment_transaction_type.payment_transaction_type_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, 
	pending_bets_real, pending_bets_bonus, currencyID, -1, sbBetID, licenseTypeId, 0, 0, 0, 0,
	0, 0, IF(numMultiples>0, 10, 8) /* game_play_message_type = 'SportsBetMult' or 'SportsBet' */ , gameRoundID, 0, gameID, LEAST(lockedRealFunds, betReal)
  FROM gaming_client_stats
  STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name = transactionTypeString 
  WHERE gaming_client_stats.client_stat_id=clientStatID;

  SET gamePlayID=LAST_INSERT_ID();

  -- Update ring fenced statistics
  IF (fingFencedEnabled) THEN
	CALL GameUpdateRingFencedBalances(clientStatID, gamePlayID);    
  END IF;
   
  SET @currentLoyaltyPoints = 0.0;
  SET @currentLoyaltyPointsBonus = 0.0;
  SET @totalLoyaltyPoints = 0.0;
  SET @totalLoyaltyPointsBonus = 0.0;
     
  -- Insert into gaming_rounds --
  SET @betRealRemain=betReal;
  SET @betBonusRemain=betBonus-betFreeBet;
  SET @betBonusWinLockedRemain=betBonusWinLocked;
  SET @betFreeBetRemain=betFreeBet;
  SET @paymentTransactionTypeID=12; 
  SET @betAmount=NULL;
  SET @betFreeBet=0;
  SET @transactionNum=0;
  
  IF (loyaltyPointsEnabledWager) THEN
	SELECT amount, loyalty_points 
	INTO loyaltyPointsAmount, loyaltyPointsAward
	FROM gaming_loyalty_points_sb
	WHERE currency_id = currencyID AND vip_level_id = vipLevelID;
	  
	SET @loyaltyPointsAwardRatio = IFNULL(loyaltyPointsAward/loyaltyPointsAmount, 0);
    SET @sbLoyaltyPointsWeight = SBWeightCalculateForLoyaltyPoints(sbBetID);
  ELSE
	SET @loyaltyPointsAwardRatio = 0;
    SET @sbLoyaltyPointsWeight = 0;
  END IF;
  
  -- Insert a round for each single in the bet slip

  IF (numSingles>0) THEN

    INSERT INTO gaming_game_rounds
    (game_round_id, bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked, bet_free_bet, num_bets, num_transactions, date_time_start, 
	 game_manufacturer_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, sb_bet_id, sb_extra_id, sb_odd, license_type_id, 
     balance_real_before, balance_bonus_before, loyalty_points, loyalty_points_bonus, sb_bet_entry_id) 
    SELECT game_round_id, bet_amount, ROUND(bet_amount/exchangeRate,5), exchangeRate, bet_real, bet_bonus+bet_free_bet, bet_bonus_win_locked, bet_free_bet, 1, 1, NOW(), 
     gameManufacturerID, clientID, clientStatID, 0, 4, currencyID, sbBetID, sb_selection_id, odd, licenseTypeID, 
     balanceRealBefore, balanceBonusBefore, currentLoyaltyPointsForBet, currentLoyaltyPointsBonusForBet, sb_bet_single_id
    FROM 
    (
      SELECT gaming_game_rounds.game_round_id, gaming_sb_bet_singles.sb_bet_single_id, gaming_sb_bet_singles.sb_selection_id, @betAmountRemain:=bet_amount AS bet_amount, odd,
        @betReal := LEAST(@betRealRemain, @betAmountRemain) AS bet_real, 
		@betAmountRemain := @betAmountRemain - @betReal,
		@betFreeBet := LEAST(@betFreeBetRemain, @betAmountRemain) AS bet_free_bet,
		@betAmountRemain := @betAmountRemain - @betFreeBet,
        @betBonus := LEAST(@betBonusRemain, @betAmountRemain) AS bet_bonus, 
		@betAmountRemain := @betAmountRemain - @betBonus,
        @betBonusWinLocked := LEAST(@betBonusWinLockedRemain, @betAmountRemain) AS bet_bonus_win_locked, 
		@betAmountRemain := @betAmountRemain - @betBonusWinLocked,
        @betRealRemain := @betRealRemain - @betReal, 
		@betBonusRemain := @betBonusRemain - @betBonus, 
		@betBonusWinLockedRemain := @betBonusWinLockedRemain - @betBonusWinLocked,
		@currentLoyaltyPoints := @betReal * @loyaltyPointsAwardRatio * @sbLoyaltyPointsWeight AS currentLoyaltyPointsForBet,
		@currentLoyaltyPointsBonus := (@betBonus + @betBonusWinLocked) * @loyaltyPointsAwardRatio * @sbLoyaltyPointsWeight AS currentLoyaltyPointsBonusForBet,
		@totalLoyaltyPoints := @totalLoyaltyPoints + @currentLoyaltyPoints,
		@totalLoyaltyPointsBonus := @totalLoyaltyPointsBonus + @currentLoyaltyPointsBonus
      FROM gaming_sb_bet_singles FORCE INDEX (sb_bet_id)
      LEFT JOIN gaming_game_rounds FORCE INDEX (sb_bet_entry_id) ON 
		minGameRoundID IS NOT NULL AND gaming_game_rounds.sb_bet_entry_id = gaming_sb_bet_singles.sb_bet_single_id AND 
        -- parition filtering
        (gaming_game_rounds.game_round_id BETWEEN minGameRoundID AND maxGameRoundID) AND
        -- other filtering
        (gaming_game_rounds.game_round_type_id = 4 AND gaming_game_rounds.sb_extra_id IS NOT NULL)
      WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID AND
		  gaming_sb_bet_singles.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID
    ) AS XX
    ON DUPLICATE KEY UPDATE
		bet_total = VALUES(bet_total), bet_total_base = VALUES(bet_total_base), exchange_rate = VALUES(exchange_rate), bet_real = VALUES(bet_real), bet_bonus = VALUES(bet_bonus), bet_bonus_win_locked = VALUES(bet_bonus_win_locked), bet_free_bet = VALUES(bet_free_bet), num_transactions = VALUES(num_transactions), 
        currency_id = VALUES(currency_id), sb_odd = VALUES(sb_odd), balance_real_before = VALUES(balance_real_before), balance_bonus_before = VALUES(balance_bonus_before), loyalty_points = VALUES(loyalty_points), loyalty_points_bonus = VALUES(loyalty_points_bonus),
        win_total = 0, win_total_base = 0, win_real = 0, win_bonus = 0, win_bonus_win_locked = 0, win_free_bet = 0, win_bet_diffence_base = 0, bonus_lost = 0,
        bonus_win_locked_lost = 0, date_time_end = NULL, is_round_finished = 0, amount_tax_operator_original = NULL, amount_tax_player_original = NULL,
        is_cancelled = 0;
    
    IF (ROW_COUNT() > 0) THEN
		SET maxGameRoundID=ROW_COUNT()+LAST_INSERT_ID()-1;
	END IF;

    INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, 
	  amount_bonus, amount_bonus_base, amount_bonus_win_locked_component, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, 
      round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, 
	  sb_bet_type, device_type, units, confirmation_status, game_round_id, sb_bet_entry_id, sign_mult)
    SELECT gamePlayID, gaming_payment_transaction_type.payment_transaction_type_id, gaming_game_rounds.bet_total, gaming_game_rounds.bet_total_base, gaming_game_rounds.bet_real, gaming_game_rounds.bet_real/exchangeRate, gaming_game_rounds.bet_bonus+gaming_game_rounds.bet_bonus_win_locked, (gaming_game_rounds.bet_bonus+gaming_game_rounds.bet_bonus_win_locked)/exchangeRate, gaming_game_rounds.bet_bonus_win_locked, gaming_game_rounds.date_time_start, exchangeRate, gaming_game_rounds.game_manufacturer_id, clientID, clientStatID, currencyID, NULL,
       @transactionNum:=@transactionNum+1 AS round_transaction_no, gaming_sb_sports.sb_sport_id, gaming_sb_regions.sb_region_id, gaming_sb_groups.sb_group_id, gaming_sb_events.sb_event_id, gaming_sb_markets.sb_market_id, gaming_sb_selections.sb_selection_id, gaming_game_rounds.sb_bet_id, singleMultTypeID, 
	   liveBetType, deviceType, 1, 0, gaming_game_rounds.game_round_id, gaming_game_rounds.sb_bet_entry_id, -1
    FROM gaming_game_rounds FORCE INDEX (sb_bet_id)
    STRAIGHT_JOIN gaming_sb_selections ON gaming_game_rounds.sb_extra_id=gaming_sb_selections.sb_selection_id
    STRAIGHT_JOIN gaming_sb_markets ON gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    STRAIGHT_JOIN gaming_sb_events ON gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    STRAIGHT_JOIN gaming_sb_groups ON gaming_sb_events.sb_group_id=gaming_sb_groups.sb_group_id
    STRAIGHT_JOIN gaming_sb_regions ON gaming_sb_groups.sb_region_id=gaming_sb_regions.sb_region_id
    STRAIGHT_JOIN gaming_sb_sports ON gaming_sb_regions.sb_sport_id=gaming_sb_sports.sb_sport_id
    STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name = transactionTypeString
	LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=('SportsBet' COLLATE utf8_general_ci)
    WHERE gaming_game_rounds.sb_bet_id=sbBetID AND 
		-- parition filtering
        (gaming_game_rounds.game_round_id BETWEEN minGameRoundID AND maxGameRoundID) AND
        -- other filtering
        (gaming_game_rounds.license_type_id=3 AND gaming_game_rounds.game_round_type_id=4
			AND gaming_game_rounds.is_cancelled = 0 AND gaming_game_rounds.sb_extra_id IS NOT NULL);

	SET numSingles=ROW_COUNT();
			
	IF (numSingles > 0) THEN
		SET minGamePlaySBID=IFNULL(minGamePlaySBID, LAST_INSERT_ID());
		SET maxGamePlaySBID=numSingles+LAST_INSERT_ID()-1;
	END IF;

  END IF;
  
  -- Insert a round for each multiple in the bet slip
  IF (numMultiples>0) THEN

    INSERT INTO gaming_game_rounds
    (game_round_id, bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,bet_free_bet, num_bets, num_transactions, date_time_start, 
     game_manufacturer_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, sb_bet_id, sb_extra_id, sb_odd, license_type_id, 
     balance_real_before, balance_bonus_before, loyalty_points, loyalty_points_bonus, sb_bet_entry_id) 
    SELECT game_round_id, bet_amount, ROUND(bet_amount/exchangeRate,5), exchangeRate, bet_real, bet_bonus+bet_free_bet, bet_bonus_win_locked, bet_free_bet, 1, 1, NOW(), 
	 gameManufacturerID, clientID, clientStatID, 0, 5, currencyID, sbBetID, sb_multiple_type_id, odd, licenseTypeID, 
	 balanceRealBefore, balanceBonusBefore, currentLoyaltyPointsForBet, currentLoyaltyPointsBonusForBet, sb_bet_multiple_id
    FROM 
    (
      SELECT gaming_game_rounds.game_round_id, gaming_sb_bet_multiples.sb_bet_multiple_id, gaming_sb_bet_multiples.sb_multiple_type_id, @betAmountRemain:=bet_amount AS bet_amount, odd,
        @betReal := LEAST(@betRealRemain, @betAmountRemain) AS bet_real, 
		@betAmountRemain := @betAmountRemain - @betReal,
        @betFreeBet := LEAST(@betFreeBetRemain, @betAmountRemain) AS bet_free_bet,
		@betAmountRemain := @betAmountRemain - @betFreeBet,
        @betBonus := LEAST(@betBonusRemain, @betAmountRemain) AS bet_bonus, 
		@betAmountRemain := @betAmountRemain - @betBonus,
        @betBonusWinLocked:= LEAST(@betBonusWinLockedRemain, @betAmountRemain) AS bet_bonus_win_locked, 
		@betAmountRemain := @betAmountRemain - @betBonusWinLocked,
        @betRealRemain := @betRealRemain - @betReal, 
		@betBonusRemain := @betBonusRemain - @betBonus, 
		@betBonusWinLockedRemain := @betBonusWinLockedRemain - @betBonusWinLocked,
		@currentLoyaltyPoints := @betReal * @loyaltyPointsAwardRatio * @sbLoyaltyPointsWeight AS currentLoyaltyPointsForBet,
		@currentLoyaltyPointsBonus := (@betBonus + @betBonusWinLocked) * @loyaltyPointsAwardRatio * @sbLoyaltyPointsWeight AS currentLoyaltyPointsBonusForBet,
		@totalLoyaltyPoints := @totalLoyaltyPoints + @currentLoyaltyPoints,
		@totalLoyaltyPointsBonus := @totalLoyaltyPointsBonus + @currentLoyaltyPointsBonus
      FROM gaming_sb_bet_multiples FORCE INDEX (sb_bet_id)
      LEFT JOIN gaming_sb_multiple_types ON 
		gaming_sb_bet_multiples.sb_multiple_type_id=gaming_sb_multiple_types.sb_multiple_type_id
      LEFT JOIN gaming_game_rounds FORCE INDEX (sb_bet_entry_id) ON 
		minGameRoundID IS NOT NULL AND gaming_game_rounds.sb_bet_entry_id = gaming_sb_bet_multiples.sb_bet_multiple_id AND 
		-- parition filtering
        (gaming_game_rounds.game_round_id BETWEEN minGameRoundID AND maxGameRoundID) AND
        -- other filtering
        gaming_game_rounds.game_round_type_id = 5 AND gaming_game_rounds.sb_extra_id IS NOT NULL
      WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID AND 
        -- Partition filtering
		gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID
    ) AS XX 
    ON DUPLICATE KEY UPDATE
		bet_total = VALUES(bet_total), bet_total_base = VALUES(bet_total_base), exchange_rate = VALUES(exchange_rate), 
        bet_real = VALUES(bet_real), bet_bonus = VALUES(bet_bonus), bet_bonus_win_locked = VALUES(bet_bonus_win_locked), 
        bet_free_bet = VALUES(bet_free_bet), num_transactions = VALUES(num_transactions), 
        currency_id = VALUES(currency_id), sb_odd = VALUES(sb_odd), 
        balance_real_before = VALUES(balance_real_before), balance_bonus_before = VALUES(balance_bonus_before), 
        loyalty_points = VALUES(loyalty_points), loyalty_points_bonus = VALUES(loyalty_points_bonus),
		win_total = 0, win_total_base = 0, win_real = 0, win_bonus = 0, win_bonus_win_locked = 0, win_free_bet = 0, win_bet_diffence_base = 0, bonus_lost = 0,
        bonus_win_locked_lost = 0, date_time_end = NULL, is_round_finished = 0, amount_tax_operator_original = NULL, amount_tax_player_original = NULL,
        is_cancelled = 0;
        
	IF (ROW_COUNT() > 0) THEN
		SET maxGameRoundID=ROW_COUNT()+LAST_INSERT_ID()-1;
	END IF;

    INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, 
	  amount_bonus, amount_bonus_base, amount_bonus_win_locked_component,
      timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, 
      round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id,
      sb_bet_id, sb_multiple_type_id, sb_bet_type, units, confirmation_status, game_round_id, sb_bet_entry_id, sign_mult)
    SELECT gamePlayID, gaming_payment_transaction_type.payment_transaction_type_id, gaming_game_rounds.bet_total, gaming_game_rounds.bet_total_base, gaming_game_rounds.bet_real, gaming_game_rounds.bet_real/exchangeRate, gaming_game_rounds.bet_bonus+gaming_game_rounds.bet_bonus_win_locked, (gaming_game_rounds.bet_bonus+gaming_game_rounds.bet_bonus_win_locked)/exchangeRate, gaming_game_rounds.bet_bonus_win_locked, 
      gaming_game_rounds.date_time_start, gaming_game_rounds.exchange_rate, gaming_game_rounds.game_manufacturer_id, clientID, clientStatID, currencyID, NULL, 
      @transactionNum:=@transactionNum+1 AS round_transaction_no, SportsID.sb_sport_id, SportsID.sb_region_id, SportsID.sb_group_id, SportsID.sb_event_id, SportsID.sb_market_id, SportsID.sb_selection_id,
      gaming_game_rounds.sb_bet_id, gaming_game_rounds.sb_extra_id, liveBetType, 1, 0, gaming_game_rounds.game_round_id, gaming_game_rounds.sb_bet_entry_id, -1
	FROM gaming_game_rounds FORCE INDEX (sb_bet_id)
    STRAIGHT_JOIN gaming_sb_bet_multiples AS bet_multiple FORCE INDEX (sb_bet_id) ON 
		gaming_game_rounds.sb_bet_id=bet_multiple.sb_bet_id AND gaming_game_rounds.sb_extra_id=bet_multiple.sb_multiple_type_id
    STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name = transactionTypeString
    LEFT JOIN (
		  -- Check each sports entity and if they are the same within the singles of a multiple get the ID
	      SELECT gaming_sb_bet_multiples.sb_bet_multiple_id,
			IF(COUNT(DISTINCT gaming_sb_selections.sb_sport_id)<=1, gaming_sb_selections.sb_sport_id, NULL) AS sb_sport_id,
			IF(COUNT(DISTINCT gaming_sb_selections.sb_region_id)<=1, gaming_sb_selections.sb_region_id, NULL) AS sb_region_id,
			IF(COUNT(DISTINCT gaming_sb_selections.sb_group_id)<=1, gaming_sb_selections.sb_group_id, NULL) AS sb_group_id,
			IF(COUNT(DISTINCT gaming_sb_selections.sb_event_id)<=1, gaming_sb_selections.sb_event_id, NULL) AS sb_event_id,
			IF(COUNT(DISTINCT gaming_sb_selections.sb_market_id)<=1, gaming_sb_selections.sb_market_id, NULL) AS sb_market_id,
			IF(COUNT(DISTINCT gaming_sb_selections.sb_selection_id)<=1, gaming_sb_selections.sb_selection_id, NULL) AS sb_selection_id 
		  FROM gaming_sb_bet_multiples FORCE INDEX (sb_bet_id)
		  STRAIGHT_JOIN gaming_sb_bet_multiples_singles AS gsbms FORCE INDEX (sb_bet_multiple_id) ON 
			gaming_sb_bet_multiples.sb_bet_multiple_id=gsbms.sb_bet_multiple_id
		  STRAIGHT_JOIN gaming_sb_selections ON 
			gsbms.sb_selection_id=gaming_sb_selections.sb_selection_id
		  WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID    
          GROUP BY gaming_sb_bet_multiples.sb_bet_multiple_id
    ) AS SportsID ON bet_multiple.sb_bet_multiple_id=SportsID.sb_bet_multiple_id
	WHERE gaming_game_rounds.sb_bet_id=sbBetID AND 
		-- parition filtering
        (gaming_game_rounds.game_round_id BETWEEN minGameRoundID AND maxGameRoundID) AND
        -- other filtering
		(gaming_game_rounds.license_type_id=3 AND gaming_game_rounds.game_round_type_id=5
		  AND gaming_game_rounds.is_cancelled = 0 AND gaming_game_rounds.sb_extra_id IS NOT NULL);

	SET numMultiples=ROW_COUNT();
			
	IF (numMultiples > 0) THEN
		SET minGamePlaySBID=IFNULL(minGamePlaySBID, LAST_INSERT_ID());
		SET maxGamePlaySBID=numMultiples+LAST_INSERT_ID()-1;
	END IF;

  END IF;  
  

  -- *****************************************************
  -- Set Loyalty Points Enabled
  -- *****************************************************
  SET loyaltyPointsEnabled = IF(loyaltyPointsEnabledWager = 0, 0, 1);
  
    IF (loyaltyPointsEnabled = 0) THEN
		SET @totalLoyaltyPoints = 0;
		SET @totalLoyaltyPointsBonus = 0;
	ELSE 
	
		SET @totalLoyaltyPoints = FLOOR(@totalLoyaltyPoints);
		SET @totalLoyaltyPointsBonus = FLOOR(@totalLoyaltyPointsBonus);
	
		UPDATE gaming_game_rounds
		SET
			loyalty_points = @totalLoyaltyPoints, 
			loyalty_points_bonus = @totalLoyaltyPointsBonus
		WHERE game_round_id = parentGameRoundID;
	END IF;
  
  SELECT client_wager_type_id INTO clientWagerTypeID FROM gaming_client_wager_types WHERE name = 'sb';
  
  SELECT set_type INTO currentVipType FROM gaming_vip_levels vip WHERE vip.vip_level_id=vipLevelID;
  
   -- update the player`s balance and loyalty points
  UPDATE gaming_client_stats AS gcs
  STRAIGHT_JOIN gaming_game_plays AS ggp ON 
	ggp.game_play_id = gamePlayID AND ggp.client_stat_id = gcs.client_stat_id
  LEFT JOIN gaming_client_sessions AS gcss ON 
	gcss.session_id=sessionID
  LEFT JOIN gaming_client_wager_stats AS gcws ON 
	gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
  SET 
	  
	  gcs.total_loyalty_points_given = gcs.total_loyalty_points_given + IFNULL(@totalLoyaltyPoints,0),
	  gcs.current_loyalty_points = gcs.current_loyalty_points + IFNULL(@totalLoyaltyPoints,0),
	  gcs.total_loyalty_points_given_bonus = gcs.total_loyalty_points_given_bonus + IFNULL(@totalLoyaltyPointsBonus,0),
      gcs.loyalty_points_running_total = IF(currentVipType = 'LoyaltyPointsPeriod',gcs.loyalty_points_running_total + IFNULL(@totalLoyaltyPoints,0),gcs.loyalty_points_running_total),
	  
	  -- gaming_client_sessions
	  gcss.total_bet = gcss.total_bet + betAmount,
	  gcss.total_bet_base = gcss.total_bet_base + (betAmount/exchangeRate),
      gcss.bets = gcss.bets + 1,
	  gcss.total_bet_real = gcss.total_bet_real + betReal,
	  gcss.total_bet_bonus = gcss.total_bet_bonus + betBonus + betBonusWinLocked,
	  gcss.loyalty_points = gcss.loyalty_points + IFNULL(@totalLoyaltyPoints,0), 
	  gcss.loyalty_points_bonus = gcss.loyalty_points_bonus + IFNULL(@totalLoyaltyPointsBonus,0),
	  
	  -- gaming_client_wager_types
	  gcws.num_bets = gcws.num_bets + 1,
	  gcws.total_real_wagered = gcws.total_real_wagered + betReal,
	  gcws.total_bonus_wagered = gcws.total_bonus_wagered + betBonus + betBonusWinLocked,
	  gcws.first_wagered_date = IFNULL(gcws.first_wagered_date, NOW()),
	  gcws.last_wagered_date = NOW(),
      gcws.loyalty_points = gcws.loyalty_points + IFNULL(@totalLoyaltyPoints,0),
	  gcws.loyalty_points_bonus = gcws.loyalty_points_bonus + IFNULL(@totalLoyaltyPointsBonus,0),
	  
	  -- gaming_game_plays
	  ggp.loyalty_points = @totalLoyaltyPoints,
	  ggp.loyalty_points_bonus = @totalLoyaltyPointsBonus,
	  ggp.loyalty_points_after = loyaltyPoints + IFNULL(@totalLoyaltyPoints,0),
	  ggp.loyalty_points_after_bonus = IFNULL((totalLoyaltyPointsGivenBonus + IFNULL(@totalLoyaltyPointsBonus,0)) - totalLoyaltyPointsUsedBonus,0)
  WHERE gcs.client_stat_id = clientStatID;
  
  IF(loyaltyPointsEnabled AND vipLevelID IS NOT NULL) THEN
	CALL PlayerUpdateVIPLevel(clientStatID,0);
  END IF;
   

  -- If the player has any applicable bonuses need to insert into gaming_game_plays_sb_bonuses, gaming_game_plays_bonus_instances 
  -- 	and update gaming_bonus_instances wagering requirement (balance was already updated)
  IF (numBonusInstances>0) THEN

    SET @bonusReqContributeRealOnly=bonusReqContributeRealOnly;

	SET @currentBetBonusWinLocked = 0;
	SET @currentBetBonus = 0;
	SET @currentBetreal = 0;
	
	SET @balanceBetBonusWinLocked = 0;
	SET @balanceBetBonus = 0;
	SET @balanceBetreal = betReal;
	
	SET @totalBetBonus = 0;
	SET @totalBetBonusWinLocked = 0;
	SET @totalBetReal = 0;
	
	SET @bonusInstanceID = 0;
	SET @bonusChanged = 0;
	SET @currentPlaySportsID = 0;
	SET @playSportsUpdate = 0;
	SET @wagerNonWeighted = 0;
	SET @wagerTotal = 0;

    SET @playSportWagerRemain=0;

	INSERT INTO gaming_game_plays_sb_bonuses (game_play_sb_id, bonus_instance_id, bet_bonus_win_locked, bet_real, bet_bonus, wager_requirement_non_weighted,
		wager_requirement_contribution_before_real_only, wager_requirement_contribution, wager_requirement_contribution_cancelled)
	SELECT game_play_sb_id, bonus_instance_id, tempBetBonusWinLocked AS final_bet_bonus_win_locked, tempBetReal AS final_bet_real, tempBetBonus AS final_bet_bonus, 
		wagerNonWeighted, wager_requirement_contribution_pre, wager_requirement_contribution AS final_wager_requirement_contribution, 0
	FROM (
		SELECT tmpTable.game_play_sb_id, bonus_instance_id, tempBetBonusWinLocked, tempBetReal, tempBetBonus,
			@wagerNonWeighted:= tempBetBonusWinLocked+tempBetReal+tempBetBonus AS wagerNonWeighted,
			@wagerWeighted :=
					ROUND(
						LEAST(
								IFNULL(wgr_restrictions.max_wager_contibution_before_weight, 100000000*100),
								@wagerNonWeighted
							  )*IFNULL(tmpTable.weight, 0)*IFNULL(gaming_bonus_rules.sportsbook_weight_mod, 1),

					5),
			IF(@wagerWeighted>=tmpTable.bonus_wager_requirement_remain, tmpTable.bonus_wager_requirement_remain, @wagerWeighted) AS wager_requirement_contribution_pre,
			@wagerNonWeighted:= IF(gaming_bonus_rules.wager_req_real_only OR @bonusReqContributeRealOnly, tempBetReal, tempBetBonusWinLocked+tempBetReal+tempBetBonus),
			@wagerWeighted :=IF(tmpTable.is_freebet_phase,0,
					ROUND(
						LEAST(
								IFNULL(wgr_restrictions.max_wager_contibution_before_weight, 100000000*100),
								@wagerNonWeighted
							  )*IFNULL(tmpTable.weight, 0)*IFNULL(gaming_bonus_rules.sportsbook_weight_mod, 1),

					5)),
			IF(@wagerWeighted>=tmpTable.bonus_wager_requirement_remain, tmpTable.bonus_wager_requirement_remain, @wagerWeighted) AS wager_requirement_contribution
			
		FROM (

			SELECT gaming_game_plays_sb.game_play_sb_id, gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id,
				@playSportsUpdate:=IF(gaming_game_plays_sb.game_play_sb_id>@currentPlaySportsID AND @playSportWagerRemain=0, 1, 0) AS d,
				@currentPlaySportsID := IF(@playSportsUpdate, gaming_game_plays_sb.game_play_sb_id, @currentPlaySportsID) AS current_sb_play_id,

				@totalBetBonus := IF(@playSportsUpdate=0, @totalBetBonus, 0) AS total_bet_bonus,
				@totalBetBonusWinLocked := IF(@playSportsUpdate=0, @totalBetBonusWinLocked, 0) AS total_bet_bonus_win_locked,
				@totalBetReal := IF(@playSportsUpdate=0, @totalBetReal ,0) AS total_bet_real,
				
				@bonusChanged := IF(@bonusInstanceID = gaming_bonus_instances.bonus_instance_id, 0, 1) AS bonus_changed,
				@bonusInstanceID := gaming_bonus_instances.bonus_instance_id AS bonus_instance_id_2,
				
				@balanceBetBonusWinLocked := IF(@bonusChanged=1, IFNULL(gaming_sb_bets_bonuses.amount_bonus_win_locked,0), @balanceBetBonusWinLocked) AS balance_bet_bonus_win_locked,
				@balanceBetBonus := IF(@bonusChanged=1, IFNULL(gaming_sb_bets_bonuses.amount_bonus,0), @balanceBetBonus) AS balance_bet_bonus,
				 
				@currentBetBonusWinLocked := 
				  IF(@balanceBetBonusWinLocked>0, 
					IF(@balanceBetBonusWinLocked>(gaming_game_plays_sb.amount_bonus_win_locked_component-@totalBetBonusWinLocked), 
						IF((gaming_game_plays_sb.amount_bonus_win_locked_component-@totalBetBonusWinLocked)<0, 0, gaming_game_plays_sb.amount_bonus_win_locked_component-@totalBetBonusWinLocked), 
						@balanceBetBonusWinLocked
					 )
				   , 0) AS tempBetBonusWinLocked,

				@balanceBetBonusWinLocked := @balanceBetBonusWinLocked - @currentBetBonusWinLocked AS balance_bet_bonus_win_locked_2,
				@totalBetBonusWinLocked := @totalBetBonusWinLocked + @currentBetBonusWinLocked AS total_bet_bonus_win_locked_2,
				
				@currentBetreal := 
				  IF(@balanceBetreal>0, 
					IF(@balanceBetreal > (gaming_game_plays_sb.amount_real-@totalBetReal), 
					  IF((gaming_game_plays_sb.amount_real-@totalBetReal)<0, 0, (gaming_game_plays_sb.amount_real-@totalBetReal)), @balanceBetreal), 0) AS tempBetReal,
				@balanceBetreal := @balanceBetreal - @currentBetreal AS balance_bet_real_2,
				@totalBetReal := @totalBetReal + @currentBetreal AS total_bet_real_2,

				@currentBetBonus := 
				  IF(@balanceBetBonus>0,
					IF(@balanceBetBonus>(gaming_game_plays_sb.amount_bonus-gaming_game_plays_sb.amount_bonus_win_locked_component-@totalBetBonus), 
					  IF((gaming_game_plays_sb.amount_bonus-gaming_game_plays_sb.amount_bonus_win_locked_component-@totalBetBonus)<0, 0, gaming_game_plays_sb.amount_bonus-gaming_game_plays_sb.amount_bonus_win_locked_component-@totalBetBonus), @balanceBetBonus), 0) AS tempBetBonus,
				@balanceBetBonus := @balanceBetBonus - @currentBetBonus AS balance_bet_bonus_2,
				@totalBetBonus := @totalBetBonus + @currentBetBonus AS total_bet_bonus_2,

				@playSportWagerRemain := IF(@playSportsUpdate, gaming_game_plays_sb.amount_real+gaming_game_plays_sb.amount_bonus, @playSportWagerRemain)-(@currentBetreal+@currentBetBonus+@currentBetBonusWinLocked) AS playSportWagerRemain,

				OrderededBonusesTransactions.weight, gaming_bonus_instances.bonus_wager_requirement_remain, gaming_bonus_instances.is_freebet_phase
			FROM 
			(
				SELECT gaming_bonus_instances.bonus_instance_id, gaming_game_plays_sb.game_play_sb_id, gaming_sb_bets_bonus_rules.weight
				FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
				STRAIGHT_JOIN gaming_sb_bets_bonus_rules ON 
					gaming_game_plays_sb.sb_bet_id=gaming_sb_bets_bonus_rules.sb_bet_id
				STRAIGHT_JOIN gaming_bonus_instances ON 
					gaming_game_plays_sb.client_stat_id=gaming_bonus_instances.client_stat_id AND gaming_bonus_instances.is_active
				WHERE gaming_game_plays_sb.sb_bet_id=sbBetID AND 
					-- parition filtering
					(gaming_game_plays_sb.game_play_sb_id BETWEEN (maxGamePlaySBID-partitioningMinusFromMax) AND maxGamePlaySBID) AND
					-- other filtering
                    (gaming_game_plays_sb.payment_transaction_type_id IN (12, 45) AND gaming_game_plays_sb.is_cancelled = 0)
				ORDER BY gaming_bonus_instances.priority, gaming_bonus_instances.bonus_instance_id, gaming_game_plays_sb.game_play_sb_id
			) AS OrderededBonusesTransactions
			STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (PRIMARY) ON 
				OrderededBonusesTransactions.game_play_sb_id=gaming_game_plays_sb.game_play_sb_id
			STRAIGHT_JOIN gaming_bonus_instances FORCE INDEX (PRIMARY) ON 
				OrderededBonusesTransactions.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
			LEFT JOIN gaming_sb_bets_bonuses FORCE INDEX (PRIMARY) ON 
				gaming_sb_bets_bonuses.sb_bet_id=gaming_game_plays_sb.sb_bet_id AND 
                gaming_bonus_instances.bonus_instance_id=gaming_sb_bets_bonuses.bonus_instance_id			
		) AS tmpTable
		STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (PRIMARY) ON 
			gaming_game_plays_sb.game_play_sb_id = tmpTable.game_play_sb_id
		STRAIGHT_JOIN gaming_bonus_rules ON 
			gaming_bonus_rules.bonus_rule_id=tmpTable.bonus_rule_id -- gaming_bonus_rules.bonus_rule_id = topBonusRuleID
		LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON 
			gaming_bonus_rules.bonus_rule_id=wgr_restrictions.bonus_rule_id AND 
            wgr_restrictions.currency_id=currencyID
	) AS tmpTable
    HAVING final_wager_requirement_contribution > 0 OR final_bet_bonus > 0 OR final_bet_bonus_win_locked > 0
	ON DUPLICATE KEY UPDATE
		gaming_game_plays_sb_bonuses.bet_bonus_win_locked=
			gaming_game_plays_sb_bonuses.bet_bonus_win_locked+VALUES(gaming_game_plays_sb_bonuses.bet_bonus_win_locked),
		gaming_game_plays_sb_bonuses.bet_real=
			gaming_game_plays_sb_bonuses.bet_real+VALUES(gaming_game_plays_sb_bonuses.bet_real),
		gaming_game_plays_sb_bonuses.bet_bonus=
			gaming_game_plays_sb_bonuses.bet_bonus+VALUES(gaming_game_plays_sb_bonuses.bet_bonus),

    gaming_game_plays_sb_bonuses.wager_requirement_non_weighted=gaming_game_plays_sb_bonuses.wager_requirement_non_weighted
		+VALUES(gaming_game_plays_sb_bonuses.wager_requirement_non_weighted),
    gaming_game_plays_sb_bonuses.wager_requirement_contribution_before_real_only=gaming_game_plays_sb_bonuses.wager_requirement_contribution_before_real_only
		+VALUES(gaming_game_plays_sb_bonuses.wager_requirement_contribution_before_real_only),
    gaming_game_plays_sb_bonuses.wager_requirement_contribution=gaming_game_plays_sb_bonuses.wager_requirement_contribution
		+VALUES(gaming_game_plays_sb_bonuses.wager_requirement_contribution);

	UPDATE 
    (
		  SELECT used_sb_bonuses.bonus_instance_id, COUNT(*) AS num_rounds
		  FROM gaming_game_plays_sb FORCE INDEX (game_play_id)
		  STRAIGHT_JOIN gaming_game_plays_sb_bonuses AS used_sb_bonuses ON 
			gaming_game_plays_sb.game_play_sb_id=used_sb_bonuses.game_play_sb_id
		  WHERE gaming_game_plays_sb.game_play_id=gamePlayID AND
			-- parition filtering
			(gaming_game_plays_sb.game_play_sb_id BETWEEN (maxGamePlaySBID-partitioningMinusFromMax) AND maxGamePlaySBID)
		  GROUP BY used_sb_bonuses.bonus_instance_id
    ) AS BonusesUsed 
    STRAIGHT_JOIN gaming_bonus_instances AS gbi FORCE INDEX (PRIMARY) ON gbi.bonus_instance_id=BonusesUsed.bonus_instance_id
    SET gbi.open_rounds = gbi.open_rounds + BonusesUsed.num_rounds;
	
  END IF;

  IF (playLimitEnabled) THEN 
    CALL PlayLimitsUpdate(clientStatID, licenseType, betAmount, 1);
  END IF;
 
   -- Update the betslip status
  UPDATE gaming_sb_bets 
  SET amount_real=betReal, amount_bonus=betBonus, amount_bonus_win_locked=betBonusWinLocked, 
	  amount_free_bet=IFNULL(FreeBonusAmount,0), status_code=3, detailed_status_code=0, wager_game_play_id=gamePlayID, is_success=1
  WHERE sb_bet_id=sbBetID;

	IF (isCouponBet) THEN
		CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID, minimalData);
		CALL PlayReturnBonusInfoOnBet(gamePlayID);
	ELSE
		CALL CommonWalletSBReturnData(sbBetID, clientStatID, gamePlayID, minimalData);  
	END IF;  
    
  UPDATE gaming_sb_bets_partition_fields
  SET 
    min_game_round_id=minGameRoundID, 
    max_game_round_id=maxGameRoundID,
    min_game_play_sb_id=minGamePlaySBID,
    max_game_play_sb_id=maxGamePlaySBID
  WHERE sb_bet_id=sbBetID;
  
END root$$

DELIMITER ;

