-- -------------------------------------
-- CommonWalletFinSoftGetFunds.sql
-- -------------------------------------
DROP procedure IF EXISTS `CommonWalletFinSoftGetFunds`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletFinSoftGetFunds`(sbBetID BIGINT, clientStatID BIGINT, canCommit TINYINT(1), OUT statusCode INT)
root: BEGIN
  
  DECLARE betAmount, totalPlayerBalance, betReal, betFreeBet, betFreeBetWinLocked, betBonus, betBonusWinLocked DECIMAL(18, 5) DEFAULT 0;
  DECLARE balanceReal, balanceFreeBet, balaneFreeBetWinLocked, balanceBonus, balanceWinLocked, betRemain, exchangeRate, sbOdd,FreeBonusAmount DECIMAL(18, 5) DEFAULT 0;
  DECLARE sbBetIDCheck, sessionID, clientStatID, clientStatIDStat, clientStatIDCheck, clientID, gamePlayID, currencyID, fraudClientEventID, gameRoundID, gameSessionID BIGINT DEFAULT -1;
  DECLARE ignoreSessionExpiry, ignorePlayLimit, playerRestrictionEnabled, playLimitEnabled, isLimitExceeded, bonusEnabledFlag, disableBonusMoney, isAccountClosed, fraudEnabled, disallowPlay, isPlayAllowed, useFreeBet, licenceCountryRestriction TINYINT(1) DEFAULT 0;
  DECLARE roundType, licenseType VARCHAR(20) DEFAULT NULL;
  DECLARE clientWagerTypeID, sessionStatusCode INT DEFAULT -1;
  DECLARE transactionRef VARCHAR(40) DEFAULT NULL;
  DECLARE gameManufacturerName VARCHAR(20) DEFAULT 'FinSoft';
  DECLARE gameManufacturerID BIGINT DEFAULT 7; 
  DECLARE numSingles, numMultiples, licenceTypeID INT DEFAULT 0;
  DECLARE licenseTypeID TINYINT(4) DEFAULT 0;
  SET licenseType='sportsbook';
  SET gameSessionID = NULL;
  SET statusCode=0;
  
  SELECT client_stat_id, transaction_ref, bet_total, num_singles, num_multiplies, use_free_bet 
  INTO clientStatID, transactionRef, betAmount, numSingles, numMultiples, useFreeBet 
  FROM gaming_sb_bets WHERE sb_bet_id=sbBetID;
  
  IF (numSingles>0) THEN
    UPDATE gaming_sb_bet_singles
    JOIN gaming_sb_groups ON gaming_sb_bet_singles.ext_group_id=gaming_sb_groups.ext_group_id AND gaming_sb_groups.game_manufacturer_id=gameManufacturerID
    JOIN gaming_sb_events ON gaming_sb_bet_singles.ext_event_id=gaming_sb_events.ext_event_id AND gaming_sb_events.sb_group_id=gaming_sb_groups.sb_group_id
    JOIN gaming_sb_markets ON gaming_sb_bet_singles.ext_market_id=gaming_sb_markets.ext_market_id AND gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    JOIN gaming_sb_selections ON gaming_sb_bet_singles.ext_selection_id=gaming_sb_selections.ext_selection_id AND gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    SET gaming_sb_bet_singles.sb_selection_id=gaming_sb_selections.sb_selection_id
    WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID;
    
    UPDATE gaming_sb_bet_singles
    JOIN gaming_sb_events ON gaming_sb_bet_singles.ext_event_id=gaming_sb_events.ext_event_id 
    JOIN gaming_sb_markets ON gaming_sb_bet_singles.ext_market_id=gaming_sb_markets.ext_market_id AND gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    JOIN gaming_sb_selections ON gaming_sb_bet_singles.ext_selection_id=gaming_sb_selections.ext_selection_id AND gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    SET gaming_sb_bet_singles.sb_selection_id=gaming_sb_selections.sb_selection_id
    WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID AND gaming_sb_bet_singles.sb_selection_id IS NULL;
	
    UPDATE gaming_sb_bet_singles
    JOIN gaming_sb_markets ON gaming_sb_bet_singles.ext_market_id=gaming_sb_markets.ext_market_id 
    JOIN gaming_sb_selections ON gaming_sb_bet_singles.ext_selection_id=gaming_sb_selections.ext_selection_id AND gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    SET gaming_sb_bet_singles.sb_selection_id=gaming_sb_selections.sb_selection_id
    WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID AND gaming_sb_bet_singles.sb_selection_id IS NULL;
  END IF; 
      
  IF (numMultiples>0) THEN
    INSERT INTO gaming_sb_multiple_types (name, ext_name, `order`, game_manufacturer_id)
    SELECT ext_multiple_type, ext_multiple_type, 100, gameManufacturerID
    FROM gaming_sb_bet_multiples
    WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID AND gaming_sb_bet_multiples.ext_multiple_type NOT IN (SELECT ext_name FROM gaming_sb_multiple_types WHERE game_manufacturer_id=gameManufacturerID);
  
    UPDATE gaming_sb_bet_multiples
    JOIN gaming_sb_multiple_types ON gaming_sb_bet_multiples.ext_multiple_type=gaming_sb_multiple_types.ext_name AND gaming_sb_multiple_types.game_manufacturer_id=gameManufacturerID
    SET gaming_sb_bet_multiples.sb_multiple_type_id=gaming_sb_multiple_types.sb_multiple_type_id
    WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID;
  
    UPDATE gaming_sb_bet_multiples_singles
    JOIN gaming_sb_bet_multiples ON gaming_sb_bet_multiples_singles.sb_bet_multiple_id=gaming_sb_bet_multiples.sb_bet_multiple_id
    JOIN gaming_sb_groups ON gaming_sb_bet_multiples_singles.ext_group_id=gaming_sb_groups.ext_group_id AND gaming_sb_groups.game_manufacturer_id=gameManufacturerID
    JOIN gaming_sb_events ON gaming_sb_bet_multiples_singles.ext_event_id=gaming_sb_events.ext_event_id AND gaming_sb_events.sb_group_id=gaming_sb_groups.sb_group_id
    JOIN gaming_sb_markets ON gaming_sb_bet_multiples_singles.ext_market_id=gaming_sb_markets.ext_market_id AND gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    JOIN gaming_sb_selections ON gaming_sb_bet_multiples_singles.ext_selection_id=gaming_sb_selections.ext_selection_id AND gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    SET gaming_sb_bet_multiples_singles.sb_selection_id=gaming_sb_selections.sb_selection_id
    WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID;
    
    UPDATE gaming_sb_bet_multiples_singles
    JOIN gaming_sb_bet_multiples ON gaming_sb_bet_multiples_singles.sb_bet_multiple_id=gaming_sb_bet_multiples.sb_bet_multiple_id
    JOIN gaming_sb_events ON gaming_sb_bet_multiples_singles.ext_event_id=gaming_sb_events.ext_event_id 
    JOIN gaming_sb_markets ON gaming_sb_bet_multiples_singles.ext_market_id=gaming_sb_markets.ext_market_id AND gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    JOIN gaming_sb_selections ON gaming_sb_bet_multiples_singles.ext_selection_id=gaming_sb_selections.ext_selection_id AND gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    SET gaming_sb_bet_multiples_singles.sb_selection_id=gaming_sb_selections.sb_selection_id
    WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID AND gaming_sb_bet_multiples_singles.sb_selection_id IS NULL;
    
	UPDATE gaming_sb_bet_multiples_singles
    JOIN gaming_sb_bet_multiples ON gaming_sb_bet_multiples_singles.sb_bet_multiple_id=gaming_sb_bet_multiples.sb_bet_multiple_id
    JOIN gaming_sb_markets ON gaming_sb_bet_multiples_singles.ext_market_id=gaming_sb_markets.ext_market_id
    JOIN gaming_sb_selections ON gaming_sb_bet_multiples_singles.ext_selection_id=gaming_sb_selections.ext_selection_id AND gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    SET gaming_sb_bet_multiples_singles.sb_selection_id=gaming_sb_selections.sb_selection_id
    WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID AND gaming_sb_bet_multiples_singles.sb_selection_id IS NULL;
  END IF;
  
  SELECT client_stat_id, bet_total, gaming_sb_bets.game_manufacturer_id, cw_disable_bonus_money, transaction_ref 
  INTO clientStatID, betAmount, gameManufacturerID, disableBonusMoney, transactionRef
  FROM gaming_sb_bets 
  JOIN gaming_game_manufacturers ON gaming_sb_bets.game_manufacturer_id = gaming_game_manufacturers.game_manufacturer_id
  WHERE sb_bet_id=sbBetID;    
  
  SELECT client_stat_id, gaming_client_stats.client_id, currency_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance
  INTO clientStatIDCheck, clientID, currencyID, balanceReal, balanceBonus, balanceWinLocked   
  FROM gaming_client_stats
  WHERE gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.is_active=1 
  FOR UPDATE;
  
  SELECT sb_bet_id, detailed_status_code INTO sbBetIDCheck, statusCode FROM gaming_sb_bets WHERE transaction_ref=transactionRef AND game_manufacturer_id=gameManufacturerID AND status_code!=1 ORDER BY timestamp DESC LIMIT 1;
  IF (sbBetIDCheck!=-1) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF;
    CALL CommonWalletSBReturnData(sbBetIDCheck, clientStatID);
    LEAVE root;
  END IF;
  
  SELECT gaming_clients.is_account_closed OR gaming_fraud_rule_client_settings.block_account, gaming_clients.is_play_allowed AND !gaming_fraud_rule_client_settings.block_gameplay, sessions_main.session_id, sessions_main.status_code 
  INTO isAccountClosed, isPlayAllowed, sessionID, sessionStatusCode
  FROM gaming_clients
  JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
  JOIN sessions_main ON sessions_main.extra_id=gaming_clients.client_id AND sessions_main.is_latest
  WHERE gaming_clients.client_id=clientID;
  
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, gs4.value_bool, IFNULL(gs5.value_bool,0) AS vb5
    INTO playLimitEnabled, bonusEnabledFlag, fraudEnabled, playerRestrictionEnabled, licenceCountryRestriction
    FROM gaming_settings gs1 
    JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
    JOIN gaming_settings gs3 ON (gs3.name='FRAUD_ENABLED')
    JOIN gaming_settings gs4 ON (gs4.name='PLAYER_RESTRICTION_ENABLED')
	LEFT JOIN gaming_settings gs5 ON (gs5.name='LICENCE_COUNTRY_RESTRICTION_ENABLED')
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
  ELSEIF (ignoreSessionExpiry=0 AND sessionStatusCode!=1) THEN
    SET statusCode=7;
  END IF;
  
  IF (statusCode=0 AND playerRestrictionEnabled) THEN
    SET @numRestrictions=0;
    SET @restrictionType=NULL;
    SELECT restriction_types.name, COUNT(*) INTO @restrictionType, @numRestrictions
    FROM gaming_player_restrictions
    JOIN gaming_player_restriction_types AS restriction_types ON restriction_types.is_active=1 AND restriction_types.disallow_play=1 AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
    LEFT JOIN gaming_license_type ON gaming_player_restrictions.license_type_id=gaming_license_type.license_type_id
    WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date AND
      (gaming_license_type.name IS NULL OR gaming_license_type.name=licenseType);
  
    IF (@numRestrictions > 0) THEN
      SET statusCode=8;
    END IF;
  END IF;  
   
  IF (statusCode=0 AND fraudEnabled AND ignorePlayLimit=0) THEN
    SELECT fraud_client_event_id, disallow_play 
    INTO fraudClientEventID, disallowPlay
    FROM gaming_fraud_client_events 
    JOIN gaming_fraud_classification_types ON gaming_fraud_client_events.client_stat_id=clientStatID AND gaming_fraud_client_events.is_current=1
      AND gaming_fraud_client_events.fraud_classification_type_id=gaming_fraud_classification_types.fraud_classification_type_id;
  
    IF (fraudClientEventID<>-1 AND disallowPlay=1) THEN
      SET statusCode=3;
    END IF;
  END IF;
   
  IF (statusCode=0 AND playLimitEnabled AND ignorePlayLimit=0) THEN 
    SET isLimitExceeded=PlayLimitCheckExceeded(betAmount, sessionID, clientStatID, licenseType);
    IF (isLimitExceeded>0) THEN
      SET statusCode=5;
    END IF;
  END IF;
  
  IF (statusCode!=0) THEN
    UPDATE gaming_sb_bets SET status_code=2, detailed_status_code=statusCode WHERE sb_bet_id=sbBetID;
    CALL CommonWalletSBReturnData(sbBetID, clientStatID); 
    LEAVE root;
  END IF;
    
  -- insert into gaming_sb_bets_bonus_rules
  CALL CommonWalletSportsGenericCalculateBonusRuleWeight(sessionID, clientStatID, sbBetID, numSingles, numMultiples);
 
  SELECT IFNULL(SUM(IF(gbta.name='Bonus', gbi.bonus_amount_remaining, 0)),0) AS current_bonus_balance, IFNULL(SUM(IF(gbta.name='Bonus', gbi.current_win_locked_amount, 0)),0) AS current_bonus_win_locked_balance,
    IFNULL(SUM(IF(gbta.name='FreeBet', gbi.bonus_amount_remaining, 0)),0) AS freebet_balance, IFNULL(SUM(IF(gbta.name='FreeBet', gbi.current_win_locked_amount, 0)),0) AS freebet_win_locked_balance
  INTO balanceBonus, balanceWinLocked,  balanceFreeBet,  balaneFreeBetWinLocked
  FROM gaming_bonus_instances AS gbi
  JOIN gaming_sb_bets_bonus_rules ON gaming_sb_bets_bonus_rules.sb_bet_id=sbBetID AND gbi.bonus_rule_id=gaming_sb_bets_bonus_rules.bonus_rule_id
  JOIN gaming_bonus_rules AS gbr ON gbi.bonus_rule_id=gbr.bonus_rule_id
  JOIN gaming_bonus_types_awarding AS gbta ON gbr.bonus_type_awarding_id=gbta.bonus_type_awarding_id
  JOIN gaming_bonus_types ON gbr.bonus_type_id=gaming_bonus_types.bonus_type_id
  WHERE gbi.client_stat_id=clientStatID AND gbi.is_active=1;
  
  SET balanceWinLocked=balanceWinLocked+balaneFreeBetWinLocked; 
  SET balaneFreeBetWinLocked=0;

  SET @BonusCounter =0;
  
  IF (disableBonusMoney OR bonusEnabledFlag=0) THEN
    SET balanceBonus=0;
    SET balanceWinLocked=0; 
    SET balanceFreeBet=0; 
    SET balaneFreeBetWinLocked=0;
  END IF;
  
  IF (useFreeBet) THEN
    SET balanceReal=0;
    SET balanceBonus=0;
    SET balanceWinLocked=0;
    SET balaneFreeBetWinLocked=0;
  ELSE
    SET balanceFreeBet=0;
  END IF;
  
  SET totalPlayerBalance = IF(disableBonusMoney=1, balanceReal, balanceReal+(balanceBonus+balanceWinLocked)+(balanceFreeBet+balaneFreeBetWinLocked));
  
  IF (totalPlayerBalance < betAmount) THEN 
    SET statusCode=4;
  END IF;
      
  IF (statusCode!=0) THEN
    UPDATE gaming_sb_bets SET status_code=2, detailed_status_code=statusCode WHERE sb_bet_id=sbBetID;
    SELECT sb_bet_id, transaction_ref, gaming_sb_bets.status_code, gaming_sb_bets_statuses.status, timestamp, bet_total AS amount_total, amount_real, amount_bonus+amount_bonus_win_locked AS amount_bonus FROM gaming_sb_bets JOIN gaming_sb_bets_statuses ON gaming_sb_bets.status_code=gaming_sb_bets_statuses.status_code WHERE sb_bet_id=sbBetID;
    LEAVE root;
  END IF;    
   
  SET betRemain=betAmount;
  
  IF (disableBonusMoney=0) THEN
    IF (betRemain > 0) THEN
      IF (balanceFreeBet >= betRemain) THEN
        SET betFreeBet=ROUND(betRemain, 5);
        SET betRemain=0;
      ELSE
        SET betFreeBet=ROUND(balanceFreeBet, 5);
        SET betRemain=ROUND(betRemain-betFreeBet,0);
      END IF;
    END IF;
  END IF; 
   
  IF (betRemain > 0) THEN
    IF (balanceReal >= betRemain) THEN
      SET betReal=ROUND(betRemain, 5);
      SET betRemain=0;
    ELSE
      SET betReal=ROUND(balanceReal, 5);
      SET betRemain=ROUND(betRemain-betReal,0);
    END IF;
  END IF;
  IF (disableBonusMoney=0) THEN
    
    IF (betRemain > 0) THEN
      IF (balanceWinLocked >= betRemain) THEN
        SET betBonusWinLocked=ROUND(betRemain,5);
        SET betRemain=0;
      ELSE
        SET betBonusWinLocked=ROUND(balanceWinLocked,5);
        SET betRemain=ROUND(betRemain-betBonusWinLocked,0);
      END IF;
      
    END IF;
    
    IF (betRemain > 0) THEN
      IF (balanceBonus >= betRemain) THEN
        SET betBonus=ROUND(betRemain,5);
        SET betRemain=0;
      ELSE
        SET betBonus=ROUND(balanceBonus,5);
        SET betRemain=ROUND(betRemain-betBonus,0);
      END IF;
      
    END IF;
  END IF;
   
  IF (betRemain > 0) THEN
    SET statusCode=4;
    LEAVE root;
  END IF;
  
  SET betBonus=betBonus+betFreeBet;
  SET betBonusWinLocked=betBonusWinLocked+betFreeBetWinLocked;
  IF (betBonus+betBonusWinLocked > 0) THEN
    SET @betBonusDeduct=betBonus;
    SET @betBonusDeductWinLocked=betBonusWinLocked;
    INSERT INTO gaming_sb_bets_bonuses (sb_bet_id, bonus_instance_id,amount_total, amount_real, amount_bonus, amount_bonus_win_locked, amount_bonus_deduct, amount_bonus_win_locked_deduct)

    SELECT sbBetID, bonus_instance_id, bet_real+bet_bonus+bet_bonus_win_locked,bet_real,bet_bonus,bet_bonus_win_locked,bonusDeductRemain,bonusWinLockedRemain
	FROM (
			SELECT sbBetID, bonus_instance_id, 
			@BonusCounter := @BonusCounter +1,
			@BetReal :=IF(@BonusCounter=1,betReal,0) AS bet_real,
			@betBonus:=IF(@betBonusDeduct>=bonus_amount_remaining, bonus_amount_remaining, @betBonusDeduct) AS bet_bonus,
			@betBonusWinLocked:=IF(@betBonusDeductWinLocked>=current_win_locked_amount,current_win_locked_amount,@betBonusDeductWinLocked) AS bet_bonus_win_locked,
			@betBonusDeduct:=GREATEST(0, @betBonusDeduct-bonus_amount_remaining) AS bonusDeductRemain, 
			@betBonusDeductWinLocked:=GREATEST(0, @betBonusDeductWinLocked-current_win_locked_amount) AS bonusWinLockedRemain
			FROM 
			(
			  SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, IF(useFreeBet, 0, current_win_locked_amount) AS current_win_locked_amount, IF(useFreeBet, IF(gaming_bonus_types_awarding.name='FreeBet', bonus_amount_remaining, 0), IF(gaming_bonus_types_awarding.name='FreeBet', 0, bonus_amount_remaining)) AS bonus_amount_remaining
			  FROM gaming_bonus_instances
			  JOIN gaming_sb_bets_bonus_rules ON gaming_sb_bets_bonus_rules.sb_bet_id=sbBetID AND gaming_bonus_instances.bonus_rule_id=gaming_sb_bets_bonus_rules.bonus_rule_id
			  JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
			  JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
			  WHERE client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 
			  ORDER BY gaming_bonus_types_awarding.order ASC, gaming_bonus_instances.priority ASC, gaming_bonus_instances.given_date ASC
			) AS gaming_bonus_instances  
			HAVING bet_bonus > 0 OR bet_bonus_win_locked > 0) AS b;
    
    UPDATE gaming_bonus_instances 
    JOIN gaming_sb_bets_bonuses ON gaming_bonus_instances.bonus_instance_id=gaming_sb_bets_bonuses.bonus_instance_id
    SET bonus_amount_remaining=bonus_amount_remaining-amount_bonus,
	current_win_locked_amount=current_win_locked_amount-amount_bonus_win_locked,
	reserved_bonus_funds = reserved_bonus_funds + amount_bonus + amount_bonus_win_locked
    WHERE gaming_sb_bets_bonuses.sb_bet_id=sbBetID;   

  END IF;
  
  SELECT SUM(amount_bonus) INTO FreeBonusAmount FROM gaming_sb_bets_bonuses 
  JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id = gaming_sb_bets_bonuses.bonus_instance_id
  JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
  JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
  WHERE sb_bet_id = sbBetID AND (gaming_bonus_types_awarding.name='FreeBet' OR is_free_bonus = 1);

  UPDATE gaming_client_stats AS gcs
  SET current_real_balance=current_real_balance-betReal, current_bonus_balance=current_bonus_balance-betBonus, current_bonus_win_locked_balance=current_bonus_win_locked_balance-betBonusWinLocked,
      pending_bets_real=pending_bets_real+betReal, pending_bets_bonus=pending_bets_bonus+betBonus+betBonusWinLocked
  WHERE gcs.client_stat_id = clientStatID;
  UPDATE gaming_sb_bets SET amount_real=betReal, amount_bonus=betBonus, amount_bonus_win_locked=betBonusWinLocked,amount_free_bet = IFNULL(FreeBonusAmount,0), status_code = 3, detailed_status_code=0 WHERE sb_bet_id=sbBetID;
  
  SELECT exchange_rate into exchangeRate 
  FROM gaming_client_stats
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
  WHERE gaming_client_stats.client_stat_id=clientStatID
  LIMIT 1;
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, amount_other, bonus_lost, jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, pending_bet_real, pending_bet_bonus, currency_id, sign_mult, sb_bet_id, license_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT betAmount, betAmount/exchangeRate, exchangeRate, betReal, betBonus, betBonusWinLocked,IFNULL(FreeBonusAmount,0), 0, 0, 0, NOW(), gameManufacturerID, clientID, clientStatID, sessionID, gaming_payment_transaction_type.payment_transaction_type_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, pending_bets_real, pending_bets_bonus, currencyID, -1, sbBetID, 3,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
  FROM gaming_payment_transaction_type
  JOIN gaming_client_stats ON gaming_payment_transaction_type.name='FundsReservedSports' AND gaming_client_stats.client_stat_id=clientStatID;

  CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());    
  
  INSERT INTO gaming_sb_bet_history (sb_bet_id, sb_bet_transaction_type_id, timestamp, amount) 
  SELECT sbBetID, sb_bet_transaction_type_id, NOW(), betAmount
  FROM gaming_sb_bet_transaction_types WHERE name='GetFunds';
  
  CALL CommonWalletSBReturnData(sbBetID, clientStatID);  

  -- IF (canCommit) THEN COMMIT AND CHAIN; END IF;    casuing alot of stuck funds for nothing should roll back at this point if error occured
  
END root$$

DELIMITER ;