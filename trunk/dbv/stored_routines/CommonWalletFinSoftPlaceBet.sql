-- -------------------------------------
-- CommonWalletFinSoftPlaceBet.sql
-- -------------------------------------

DROP procedure IF EXISTS `CommonWalletFinSoftPlaceBet`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletFinSoftPlaceBet`(transactionRef VARCHAR(64), sessionID BIGINT, clientStatID BIGINT, canCommit TINYINT(1), OUT statusCode INT)
root: BEGIN
  
  -- UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id) -- forced index and straight_join
  DECLARE gameManufacturerName VARCHAR(80) DEFAULT 'FinSoft';
  DECLARE gameManufacturerID BIGINT DEFAULT 7;
  DECLARE gamePlayID, sbBetID, clientID, gameRoundID, currencyID, clientWagerTypeID, countryID BIGINT DEFAULT -1;
  DECLARE isAlreadyProcessed, playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly TINYINT(1) DEFAULT 0;
  DECLARE numSingles, numMultiples, sbBetStatusCode, noMoreRecords INT DEFAULT 0;
  DECLARE betAmount, betReal, betBonus, betBonusWinLocked,betFreeBet, betRealRemain, betBonusRemain, betBonusWinLockedRemain,FreeBonusAmount DECIMAL(18,5) DEFAULT 0;
  DECLARE bxBetAmount, bxBetReal, bxBetBonus, bxBetBonusWinLocked DECIMAL(18,5) DEFAULT 0;
  DECLARE balanceReal, balanceBonus, balanceWinLocked, betRemain, exchangeRate, betAmountBase, sbOdd, pendingBetsReal, pendingBetsBonus, balanceRealBefore, balanceBonusBefore, loyaltyPoints, loyaltyPointsBonus DECIMAL(18, 5) DEFAULT 0;
  DECLARE roundType, licenseType VARCHAR(20) DEFAULT NULL;
  DECLARE licenseTypeID TINYINT(4) DEFAULT 3; 
  DECLARE liveBetType TINYINT(4) DEFAULT 2; 
  DECLARE deviceType TINYINT(4) DEFAULT 1;
  DECLARE defaultSBSelectionID, defaultSBMultipleTypeID BIGINT DEFAULT NULL;

  DECLARE betsCursor CURSOR FOR 
    SELECT game_play_id, amount_total, amount_real, amount_bonus, amount_bonus_win_locked 
    FROM gaming_game_plays
    WHERE sb_bet_id=sbBetID AND license_type_id = 3 AND payment_transaction_type_id NOT IN (38,39,40,41); 
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;
  
  SET statusCode=0;
  SET licenseType='sportsbook';
  
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, gs4.value_long as vb4, gs5.value_long AS vb5
  INTO playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, defaultSBSelectionID, defaultSBMultipleTypeID
  FROM gaming_settings gs1 
  JOIN gaming_settings gs2 ON gs2.name='IS_BONUS_ENABLED'
  JOIN gaming_settings gs3 ON gs3.name='BONUS_CONTRIBUTION_REAL_MONEY_ONLY'
  LEFT JOIN gaming_settings gs4 ON gs4.name='SPORTS_WAGER_DEFAULT_SELECTION_ID'
  LEFT JOIN gaming_settings gs5 ON gs5.name='SPORTS_WAGER_DEFAULT_MULTIPLE_TYPE_ID'
  WHERE gs1.name='PLAY_LIMIT_ENABLED';
  
  SELECT client_stat_id, client_id, currency_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, pending_bets_real, pending_bets_bonus
  INTO clientStatID, clientID, currencyID, balanceReal, balanceBonus, balanceWinLocked, pendingBetsReal, pendingBetsBonus 
  FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
  
  SET balanceRealBefore=balanceReal;
  SET balanceBonusBefore=balanceBonus+balanceWinLocked;
  
  SELECT country_id INTO countryID
  FROM clients_locations 
  WHERE clients_locations.client_id=clientID AND clients_locations.is_primary=1; 
  
  SELECT sb_bet_id, client_stat_id, transaction_ref, bet_total, num_singles, num_multiplies, status_code, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, sb_bet_type_id, device_type
  INTO sbBetID, clientStatID, transactionRef, betAmount, numSingles, numMultiples, sbBetStatusCode, betReal, betBonus, betBonusWinlocked,betFreeBet, liveBetType, deviceType
  FROM gaming_sb_bets WHERE transaction_ref=transactionRef AND game_manufacturer_id=gameManufacturerID AND status_code!=1
  ORDER BY timestamp DESC
  LIMIT 1;
  
  IF (sbBetID=-1 OR clientStatID=-1) THEN
    SET statusCode=1;
    IF (canCommit) THEN COMMIT AND CHAIN; END IF;
    LEAVE root;
  END IF;
  
  IF (sbBetStatusCode NOT IN (3,6)) THEN 
    SET statusCode=2;
    IF (canCommit) THEN COMMIT AND CHAIN; END IF;
    CALL CommonWalletSBReturnData(sbBetID, clientStatID); 
    LEAVE root;
  END IF;
  
  SELECT exchange_rate into exchangeRate FROM gaming_client_stats
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
  WHERE gaming_client_stats.client_stat_id=clientStatID;
  
  SET betAmountBase=ROUND(betAmount/exchangeRate, 5);
  SELECT client_wager_type_id INTO clientWagerTypeID 
  FROM gaming_client_wager_types WHERE name='sb'; 
  
  UPDATE gaming_client_stats AS gcs
  LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
  LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
  SET total_real_played=total_real_played+betReal, 
      total_bonus_played=total_bonus_played+betBonus, 
      total_bonus_win_locked_played=total_bonus_win_locked_played+betBonusWinLocked, 
      gcs.total_real_played_base=gcs.total_real_played_base+(betReal/exchangeRate), gcs.total_bonus_played_base=gcs.total_bonus_played_base+((betBonus+betBonusWinLocked)/exchangeRate),
      pending_bets_real=pending_bets_real-betReal, pending_bets_bonus=pending_bets_bonus-(betBonus+betBonusWinLocked),
      last_played_date=NOW(), 
      
      gcss.total_bet=gcss.total_bet+betAmount,gcss.total_bet_base=gcss.total_bet_base+betAmountBase, gcss.bets=gcss.bets+numSingles+numMultiples, gcss.total_bet_real=gcss.total_bet_real+betReal, gcss.total_bet_bonus=gcss.total_bet_bonus+betBonus+betBonusWinLocked,
      
      gcws.num_bets=gcws.num_bets+numSingles+numMultiples, gcws.total_real_wagered=gcws.total_real_wagered+betReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered+betBonus+betBonusWinLocked,
      gcws.first_wagered_date=IFNULL(gcws.first_wagered_date, NOW()), gcws.last_wagered_date=NOW()
  WHERE gcs.client_stat_id = clientStatID;
   
  SET @betRealRemain=betReal;
  SET @betBonusRemain=betBonus-betFreeBet;
  SET @betBonusWinLockedRemain=betBonusWinLocked;
  SET @betFreeBetRemain=betFreeBet;
  SET @paymentTransactionTypeID=12; 
  SET @betAmount=NULL;
  SET @betFreeBet=0;
  SET @transactionNum=0;
  
  IF (numSingles > 0) THEN    
    INSERT INTO gaming_sb_bets_bonus_rules (sb_bet_id, bonus_rule_id, weight, wager_confirmed) 
    SELECT DISTINCT sbBetID, gaming_bonus_instances.bonus_rule_id, MIN(sb_weights.weight), 1
    FROM gaming_sb_bet_singles
    JOIN gaming_sb_selections ON gaming_sb_bet_singles.sb_selection_id=gaming_sb_selections.sb_selection_id
    JOIN gaming_bonus_instances ON gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1
    JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	JOIN gaming_bonus_rules_wgr_sb_eligibility_criterias AS criterias ON gaming_bonus_instances.bonus_rule_id = criterias.bonus_rule_id
    JOIN gaming_bonus_rules_wgr_sb_profile_selections AS profile_selection ON criterias.eligibility_criterias_id = profile_selection.eligibility_criterias_id
		AND (
			   (profile_selection.sb_entity_id=gaming_sb_selections.sb_sport_id  AND profile_selection.sb_entity_type_id = 1 )OR 
               (profile_selection.sb_entity_id=gaming_sb_selections.sb_region_id AND profile_selection.sb_entity_type_id = 2 )OR 
               (profile_selection.sb_entity_id=gaming_sb_selections.sb_group_id  AND profile_selection.sb_entity_type_id = 3 )OR
               (profile_selection.sb_entity_id=gaming_sb_selections.sb_event_id  AND profile_selection.sb_entity_type_id = 4 )OR 
               (profile_selection.sb_entity_id=gaming_sb_selections.sb_market_id AND profile_selection.sb_entity_type_id = 5 )
            ) 
	JOIN gaming_bonus_rules_wgr_sb_weights AS sb_weights  ON criterias.eligibility_criterias_id = sb_weights.eligibility_criterias_id 
	AND (gaming_sb_bet_singles.odd>=sb_weights.min_odd AND (sb_weights.max_odd IS NULL OR gaming_sb_bet_singles.odd<sb_weights.max_odd)) 
        AND (gaming_bonus_rules.min_odd IS NULL OR gaming_sb_bet_singles.odd>=gaming_bonus_rules.min_odd)
    WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID
    GROUP BY gaming_bonus_instances.bonus_instance_id
    HAVING COUNT(DISTINCT gaming_sb_bet_singles.sb_bet_single_id)=numSingles
    ON DUPLICATE KEY UPDATE weight=VALUES(weight), wager_confirmed=1;
    
    UPDATE gaming_sb_bets_bonus_rules SET weight=0 WHERE sb_bet_id=sbBetID AND wager_confirmed!=1;
  END IF;
  
  IF (numMultiples > 0) THEN
    INSERT INTO gaming_sb_bets_bonus_rules (sb_bet_id, bonus_rule_id, multiple_confirm, weight, wager_confirmed) 
    SELECT DISTINCT sbBetID, XX.bonus_rule_id, 1, MIN(XX.weight), 1
    FROM gaming_sb_bet_multiples
    JOIN
    (
      SELECT gaming_sb_bet_multiples.sb_bet_multiple_id, gaming_bonus_instances.bonus_rule_id, COUNT(gaming_bonus_instances.bonus_rule_id) AS num_singles, 
        MIN(sb_weights.min_odd) AS weight_min_odd, MIN(sb_weights.weight) AS weight, gaming_bonus_rules.min_odd AS bonus_rule_min_odd
      FROM gaming_sb_bet_multiples
      JOIN gaming_sb_bet_multiples_singles ON gaming_sb_bet_multiples.sb_bet_multiple_id=gaming_sb_bet_multiples_singles.sb_bet_multiple_id
      JOIN gaming_sb_selections ON gaming_sb_bet_multiples_singles.sb_selection_id=gaming_sb_selections.sb_selection_id
      JOIN gaming_bonus_instances ON gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1
      JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	  JOIN gaming_bonus_rules_wgr_sb_eligibility_criterias AS criterias ON gaming_bonus_instances.bonus_rule_id = criterias.bonus_rule_id
      JOIN gaming_bonus_rules_wgr_sb_profile_selections AS profile_selection ON criterias.eligibility_criterias_id = profile_selection.eligibility_criterias_id
		AND (
			   (profile_selection.sb_entity_id=gaming_sb_selections.sb_sport_id  AND profile_selection.sb_entity_type_id = 1 )OR 
               (profile_selection.sb_entity_id=gaming_sb_selections.sb_region_id AND profile_selection.sb_entity_type_id = 2 )OR 
               (profile_selection.sb_entity_id=gaming_sb_selections.sb_group_id  AND profile_selection.sb_entity_type_id = 3 )OR
               (profile_selection.sb_entity_id=gaming_sb_selections.sb_event_id  AND profile_selection.sb_entity_type_id = 4 )OR 
               (profile_selection.sb_entity_id=gaming_sb_selections.sb_market_id AND profile_selection.sb_entity_type_id = 5 )
            ) 
	  JOIN gaming_bonus_rules_wgr_sb_weights AS sb_weights  ON criterias.eligibility_criterias_id = sb_weights.eligibility_criterias_id
      WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID    
      GROUP BY gaming_sb_bet_multiples.sb_bet_multiple_id, gaming_bonus_instances.bonus_instance_id  
    ) AS XX ON gaming_sb_bet_multiples.sb_bet_multiple_id=XX.sb_bet_multiple_id AND gaming_sb_bet_multiples.num_singles=XX.num_singles
    WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID AND (gaming_sb_bet_multiples.odd>=XX.weight_min_odd AND (XX.bonus_rule_min_odd IS NULL OR gaming_sb_bet_multiples.odd>=XX.bonus_rule_min_odd))
    GROUP BY XX.bonus_rule_id
    HAVING COUNT(DISTINCT gaming_sb_bet_multiples.sb_bet_multiple_id)=numMultiples
    ON DUPLICATE KEY UPDATE multiple_confirm=1, weight=VALUES(weight), wager_confirmed=1;
  END IF;
  
  IF (numSingles>0) THEN
    INSERT INTO gaming_game_rounds
    (bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,bet_free_bet, num_bets, num_transactions, date_time_start, game_manufacturer_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, sb_bet_id, sb_extra_id, sb_odd, license_type_id, balance_real_before, balance_bonus_before, loyalty_points, loyalty_points_bonus) 
    SELECT bet_amount, ROUND(bet_amount/exchangeRate,5), exchangeRate, bet_real, bet_bonus+bet_free_bet, bet_bonus_win_locked,bet_free_bet, 1, 1, NOW(), gameManufacturerID, clientID, clientStatID, 0, 4, currencyID, sbBetID, IFNULL(sb_selection_id, defaultSBSelectionID), odd, licenseTypeID, balanceRealBefore, balanceBonusBefore, loyaltyPoints, loyaltyPointsBonus
    FROM 
    (
      SELECT gaming_sb_bet_singles.sb_selection_id, @betAmountRemain:=bet_amount AS bet_amount, odd,
        @betReal:=LEAST(@betRealRemain, @betAmountRemain) AS bet_real, @betAmountRemain:=@betAmountRemain-@betReal,
		@betFreeBet:=LEAST(@betFreeBetRemain, @betAmountRemain) AS bet_free_bet, @betAmountRemain:=@betAmountRemain-@betFreeBet,
        @betBonus:=LEAST(@betBonusRemain, @betAmountRemain) AS bet_bonus, @betAmountRemain:=@betAmountRemain-@betBonus,
        @betBonusWinLocked:=LEAST(@betBonusWinLockedRemain, @betAmountRemain) AS bet_bonus_win_locked, @betAmountRemain:=@betAmountRemain-@betBonusWinLocked,
        @betRealRemain:=@betRealRemain-@betReal, @betBonusRemain:=@betBonusRemain-@betBonus, @betBonusWinLockedRemain:=@betBonusWinLockedRemain-@betBonusWinLocked
      FROM gaming_sb_bet_singles
      WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID
    ) AS XX;
  END IF;
  
  IF (numMultiples>0) THEN
    INSERT INTO gaming_game_rounds
    (bet_total, bet_total_base, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,bet_free_bet, num_bets, num_transactions, date_time_start, game_manufacturer_id, client_id, client_stat_id, is_processed, game_round_type_id, currency_id, sb_bet_id, sb_extra_id, sb_odd, license_type_id, balance_real_before, balance_bonus_before, loyalty_points, loyalty_points_bonus) 
    SELECT bet_amount, ROUND(bet_amount/exchangeRate,5), exchangeRate, bet_real, bet_bonus+bet_free_bet, bet_bonus_win_locked,bet_free_bet, 1, 1, NOW(), gameManufacturerID, clientID, clientStatID, 0, 5, currencyID, sbBetID, IFNULL(sb_multiple_type_id, defaultSBMultipleTypeID), odd, licenseTypeID, balanceRealBefore, balanceBonusBefore, loyaltyPoints, loyaltyPointsBonus
    FROM 
    (
      SELECT gaming_sb_bet_multiples.sb_multiple_type_id, @betAmountRemain:=bet_amount AS bet_amount, odd,
        @betReal:=LEAST(@betRealRemain, @betAmountRemain) AS bet_real, @betAmountRemain:=@betAmountRemain-@betReal,
        @betFreeBet:=LEAST(@betFreeBetRemain, @betAmountRemain) AS bet_free_bet, @betAmountRemain:=@betAmountRemain-@betFreeBet,
        @betBonus:=LEAST(@betBonusRemain, @betAmountRemain) AS bet_bonus, @betAmountRemain:=@betAmountRemain-@betBonus,
        @betBonusWinLocked:=LEAST(@betBonusWinLockedRemain, @betAmountRemain) AS bet_bonus_win_locked, @betAmountRemain:=@betAmountRemain-@betBonusWinLocked,
        @betRealRemain:=@betRealRemain-@betReal, @betBonusRemain:=@betBonusRemain-@betBonus, @betBonusWinLockedRemain:=@betBonusWinLockedRemain-@betBonusWinLocked
      FROM gaming_sb_bet_multiples
      LEFT JOIN gaming_sb_multiple_types ON gaming_sb_bet_multiples.sb_multiple_type_id=gaming_sb_multiple_types.sb_multiple_type_id
      WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID
    ) AS XX;
  END IF;
   
  SET @pendingBetsReal=pendingBetsReal;
  SET @pendingBetsBonus=pendingBetsBonus; 
  
  IF (numSingles>0) THEN
    
    INSERT INTO gaming_game_plays 
    (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, game_round_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, is_win_placed, is_processed, currency_id, round_transaction_no, game_play_message_type_id, sign_mult, sb_extra_id, sb_bet_id, license_type_id, device_type, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
    SELECT bet_total, bet_total_base, exchangeRate, bet_real, bet_bonus, bet_bonus_win_locked,bet_free_bet, NOW(), gameManufacturerID, clientID, clientStatID, sessionID, game_round_id, @paymentTransactionTypeID, balanceReal, balanceBonus, balanceWinLocked, 0, 0, currencyID, 1, 8, -1, sb_extra_id, sbBetID, licenseTypeID, deviceType, @pendingBetsReal:=@pendingBetsReal-bet_real, @pendingBetsBonus:=@pendingBetsBonus-(bet_bonus+bet_bonus_win_locked),0,loyalty_points,0,loyalty_points_bonus
    FROM gaming_game_rounds
    WHERE sb_bet_id=sbBetID AND license_type_id = 3 AND game_round_type_id=4; 

    CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());    
    
    SELECT sb_multiple_type_id INTO @singleMultTypeID FROM gaming_sb_multiple_types WHERE name='Single' AND game_manufacturer_id=gameManufacturerID; 
    
    INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, units)
    SELECT gaming_game_plays.game_play_id, gaming_game_plays.payment_transaction_type_id, gaming_game_plays.amount_total, gaming_game_plays.amount_total_base, gaming_game_plays.amount_real, gaming_game_plays.amount_real/exchange_rate, gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked, (gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)/exchange_rate, gaming_game_plays.timestamp, gaming_game_plays.exchange_rate, gaming_game_plays.game_manufacturer_id, clientID, clientStatID, currencyID, countryID,
      gaming_game_plays.round_transaction_no, gaming_sb_sports.sb_sport_id, gaming_sb_regions.sb_region_id, gaming_sb_groups.sb_group_id, gaming_sb_events.sb_event_id, gaming_sb_markets.sb_market_id, gaming_sb_selections.sb_selection_id, gaming_game_plays.sb_bet_id, @singleMultTypeID, liveBetType, deviceType, 1
    FROM gaming_game_plays FORCE INDEX (sb_bet_single_id)
    JOIN gaming_sb_selections FORCE INDEX (PRIMARY) ON gaming_game_plays.sb_extra_id=gaming_sb_selections.sb_selection_id
    JOIN gaming_sb_markets FORCE INDEX (PRIMARY) ON gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    JOIN gaming_sb_events FORCE INDEX (PRIMARY) ON gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    JOIN gaming_sb_groups FORCE INDEX (PRIMARY) ON gaming_sb_events.sb_group_id=gaming_sb_groups.sb_group_id
    JOIN gaming_sb_regions FORCE INDEX (PRIMARY) ON gaming_sb_groups.sb_region_id=gaming_sb_regions.sb_region_id
    JOIN gaming_sb_sports FORCE INDEX (PRIMARY) ON gaming_sb_regions.sb_sport_id=gaming_sb_sports.sb_sport_id
    WHERE gaming_game_plays.sb_bet_id=sbBetID  AND gaming_game_plays.license_type_id = 3 AND gaming_game_plays.game_play_message_type_id=8; 
 
  END IF;
  
  IF (numMultiples>0) THEN
  
    INSERT INTO gaming_game_plays 
    (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked,amount_free_bet, timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, game_round_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, is_win_placed, is_processed, currency_id, round_transaction_no, game_play_message_type_id, sign_mult, sb_extra_id, sb_bet_id, license_type_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
    SELECT bet_total, bet_total_base, exchangeRate, bet_real, bet_bonus, bet_bonus_win_locked,bet_free_bet, NOW(), gameManufacturerID, clientID, clientStatID, sessionID, game_round_id, @paymentTransactionTypeID, balanceReal, balanceBonus, balanceWinLocked, 0, 0, currencyID, 1, 10, -1, sb_extra_id, sbBetID, licenseTypeID, @pendingBetsReal:=@pendingBetsReal-bet_real, @pendingBetsBonus:=@pendingBetsBonus-(bet_bonus+bet_bonus_win_locked) ,0,loyalty_points,0,loyalty_points_bonus
    FROM gaming_game_rounds
    WHERE sb_bet_id=sbBetID AND license_type_id = 3 AND game_round_type_id=5; 
	
	CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());  
    
    INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, units)
    SELECT gaming_game_plays.game_play_id, gaming_game_plays.payment_transaction_type_id, gaming_game_plays.amount_total/bet_multiple.num_singles, gaming_game_plays.amount_total_base/bet_multiple.num_singles, gaming_game_plays.amount_real/bet_multiple.num_singles, (gaming_game_plays.amount_real/exchange_rate)/bet_multiple.num_singles, (gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)/bet_multiple.num_singles, ((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)/exchange_rate)/bet_multiple.num_singles, 
      gaming_game_plays.timestamp, gaming_game_plays.exchange_rate, gaming_game_plays.game_manufacturer_id, clientID, clientStatID, currencyID, countryID, 
      gaming_game_plays.round_transaction_no, gaming_sb_sports.sb_sport_id, gaming_sb_regions.sb_region_id, gaming_sb_groups.sb_group_id, gaming_sb_events.sb_event_id, gaming_sb_markets.sb_market_id, gaming_sb_selections.sb_selection_id, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, liveBetType, 1/bet_multiple.num_singles
    FROM gaming_game_plays FORCE INDEX (sb_bet_single_id)
    JOIN gaming_sb_bet_multiples AS bet_multiple FORCE INDEX (sb_bet_id) ON gaming_game_plays.sb_bet_id=bet_multiple.sb_bet_id AND gaming_game_plays.sb_extra_id=bet_multiple.sb_multiple_type_id
    JOIN gaming_sb_bet_multiples_singles AS mult_singles FORCE INDEX (sb_bet_multiple_id) ON bet_multiple.sb_bet_multiple_id=mult_singles.sb_bet_multiple_id
    JOIN gaming_sb_selections FORCE INDEX (PRIMARY) ON IFNULL(mult_singles.sb_selection_id,defaultSBSelectionID)=gaming_sb_selections.sb_selection_id
    JOIN gaming_sb_markets FORCE INDEX (PRIMARY) ON gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
    JOIN gaming_sb_events FORCE INDEX (PRIMARY) ON gaming_sb_markets.sb_event_id=gaming_sb_events.sb_event_id
    JOIN gaming_sb_groups FORCE INDEX (PRIMARY) ON gaming_sb_events.sb_group_id=gaming_sb_groups.sb_group_id
    JOIN gaming_sb_regions FORCE INDEX (PRIMARY) ON gaming_sb_groups.sb_region_id=gaming_sb_regions.sb_region_id
    JOIN gaming_sb_sports FORCE INDEX (PRIMARY) ON gaming_sb_regions.sb_sport_id=gaming_sb_sports.sb_sport_id
    WHERE gaming_game_plays.sb_bet_id=sbBetID  AND license_type_id = 3  AND gaming_game_plays.game_play_message_type_id=10; 
    
  END IF;
  
  IF (bonusEnabledFlag AND betAmount>0) THEN
    OPEN betsCursor;
    allBetsLabel: LOOP 
      
      SET noMoreRecords=0;
      FETCH betsCursor INTO gamePlayID, bxBetAmount, bxBetReal, bxBetBonus, bxBetBonusWinLocked;
      IF (noMoreRecords) THEN
        LEAVE allBetsLabel;
      END IF;
    
      SET @transferBonusMoneyFlag=1;
      
      SET @betBonusDeductWagerRequirement=bxBetAmount; 
      SET @wager_requirement_non_weighted=0;
      SET @wager_requirement_contribution=0;
      
      SET @betRealDeduct=bxBetReal*2;
      SET @betBonusDeduct=0; 
      SET @betBonusDeductWinLocked=0; 
      
      SET @betBonus=0;
      SET @betBonusWinLocked=0;
      SET @nowWagerReqMet=0;
      SET @hasReleaseBonus=0;
      
      
      INSERT INTO gaming_game_plays_bonus_instances (sb_bet_id, game_play_id, bonus_instance_id, client_stat_id, timestamp, bonus_rule_id, exchange_rate, 
        bet_real, bet_bonus, bet_bonus_win_locked, bonus_deduct, bonus_deduct_win_locked, wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, bonus_deduct_wager_requirement, bonus_wager_requirement_remain_after)
      SELECT sbBetID, gamePlayID, bonus_instance_id, clientStatID, NOW(), bonus_rule_id, exchangeRate,
        @betRealDeduct:=GREATEST(0, @betRealDeduct-bxBetReal) AS bet_real,
        @betBonus:=IFNULL(amount_bonus*(bxBetBonus/betBonus),0) AS bet_bonus,
        @betBonusWinLocked:=IFNULL(amount_bonus_win_locked*(bxBetBonusWinLocked/betBonusWinlocked),0) AS bet_bonus_win_locked,
        @betBonusDeduct:=0 AS bonusDeductRemain, 
        @betBonusDeductWinLocked:=0 AS bonusWinLockedRemain,
        @wager_requirement_non_weighted:=IF(is_free_bonus=1,0,IF(ROUND(@betBonusDeductWagerRequirement*IFNULL(weight, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain/IFNULL(weight, 1)/IFNULL(license_weight_mod, 1), @betBonusDeductWagerRequirement)) AS wager_requirement_non_weighted, 
		@wager_requirement_contribution:=IF(is_free_bonus=1,0,IF(ROUND(LEAST(IFNULL(max_wager_contibution_before_weight,100000000*100),@betBonusDeductWagerRequirement)*IFNULL(weight, 0)*IFNULL(license_weight_mod, 1), 5)>=bonus_wager_requirement_remain, bonus_wager_requirement_remain, ROUND(LEAST(IFNULL(max_wager_contibution_before_weight,1000000*100),@betBonusDeductWagerRequirement)*IFNULL(weight, 0)*IFNULL(license_weight_mod, 1), 5))) AS wager_requirement_contribution,
		@wager_requirement_contribution:=IF(is_free_bonus=1,0,LEAST(IFNULL(max_wager_contibution,100000000*100), IF(wager_req_real_only OR bonusReqContributeRealOnly, ROUND(GREATEST(@wager_requirement_contribution-(IFNULL(bxBetBonus+bxBetBonusWinLocked,0)*IFNULL(weight,0)*IFNULL(license_weight_mod, 1)),0), 5), @wager_requirement_contribution))), 
	    @nowWagerReqMet:=IF (bonus_wager_requirement_remain-@wager_requirement_contribution<=0 AND is_free_bonus=0,1,0) AS now_wager_requirement_met,
        IF (@nowWagerReqMet=0 AND is_release_bonus AND ((bonus_wager_requirement-bonus_wager_requirement_remain)+@wager_requirement_contribution)>=
          ((transfer_every_x_last+transfer_every_x_wager)*bonus_amount_given), 1, 0) AS now_release_bonus,
        @betBonusDeductWagerRequirement:=GREATEST(0, ROUND(@betBonusDeductWagerRequirement-@wager_requirement_non_weighted, 5)) AS wagerRequirementRemain 
        , bonus_wager_requirement_remain-@wager_requirement_contribution AS bonus_wager_requirement_remain_after
	  FROM 
	  (
		  SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, wager_req_real_only, current_win_locked_amount, bonus_amount_remaining, bonus_wager_requirement_remain, license_weight_mod,
				 bonus_amount_given,given_date, bonus_wager_requirement, transfer_every_x_wager, transfer_every_x_last, is_release_bonus,is_free_bonus,weight,amount_bonus_win_locked,amount_bonus,
				 max_wager_contibution_before_weight,max_wager_contibution
		  FROM 
		  (
				SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, gaming_bonus_rules.wager_req_real_only, current_win_locked_amount, bonus_amount_remaining, bonus_wager_requirement_remain, IFNULL(gaming_bonus_rules.sportsbook_weight_mod, 1) AS license_weight_mod,
				  bonus_amount_given,gaming_bonus_instances.given_date, bonus_wager_requirement, gaming_bonus_instances.transfer_every_x AS transfer_every_x_wager, gaming_bonus_instances.transfer_every_x_last, transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus') AS is_release_bonus,gaming_bonus_rules.is_free_bonus,gaming_bonus_instances.priority
				FROM gaming_bonus_instances
				JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
				JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
				JOIN gaming_bonus_types_transfers AS transfer_type ON gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
				LEFT JOIN gaming_sb_bets_bonuses ON gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND gaming_sb_bets_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
				WHERE gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 
				ORDER BY gaming_bonus_instances.priority ASC, gaming_bonus_instances.given_date ASC, gaming_bonus_instances.bonus_instance_id DESC
			  ) AS gaming_bonus_instances  
			  JOIN gaming_sb_bets_bonus_rules AS sb_bonus_rules ON sb_bonus_rules.sb_bet_id=sbBetID AND gaming_bonus_instances.bonus_rule_id=sb_bonus_rules.bonus_rule_id  
			  LEFT JOIN gaming_sb_bets_bonuses ON gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND gaming_sb_bets_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
			  LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON gaming_bonus_instances.bonus_rule_id=wgr_restrictions.bonus_rule_id AND wgr_restrictions.currency_id=currencyID
			  ORDER BY gaming_bonus_instances.priority ASC, gaming_bonus_instances.given_date ASC, gaming_bonus_instances.bonus_instance_id DESC
		  )AS bonuses
	  HAVING wager_requirement_contribution > 0 OR bet_bonus > 0 OR bet_bonus_win_locked > 0;
      
      IF (ROW_COUNT() > 0) THEN
        
        UPDATE gaming_bonus_instances 
        JOIN gaming_game_plays_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
        SET
            
            bonus_wager_requirement_remain=bonus_wager_requirement_remain-wager_requirement_contribution,
            
            is_secured=IF(now_wager_requirement_met=1,1,is_secured), secured_date=IF(now_wager_requirement_met=1,NOW(),NULL),
			open_rounds = open_rounds + 1,
			reserved_bonus_funds = reserved_bonus_funds - (gaming_game_plays_bonus_instances.bet_bonus + gaming_game_plays_bonus_instances.bet_bonus_win_locked)
           
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
              WHEN 'ReleaseBonus' THEN LEAST(bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, bonus_amount_remaining+current_win_locked_amount)
              WHEN 'ReleaseAllBonus' THEN bonus_amount_remaining+current_win_locked_amount
              ELSE 0
            END),
            ggpbi.bonus_transfered=IF(transfer_type.name='BonusWinLocked', 0, LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining)),
            ggpbi.bonus_win_locked_transfered=IF(transfer_type.name='Bonus', 0, ggpbi.bonus_transfered_total-ggpbi.bonus_transfered),
            ggpbi.bonus_transfered_lost=bonus_amount_remaining-ggpbi.bonus_transfered,
            ggpbi.bonus_win_locked_transfered_lost=current_win_locked_amount-bonus_win_locked_transfered,
            bonus_amount_remaining=0,current_win_locked_amount=0, current_ring_fenced_amount=0,  
            gaming_bonus_instances.bonus_transfered_total=gaming_bonus_instances.bonus_transfered_total+ggpbi.bonus_transfered_total,
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
        
        SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
        INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
		@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
        FROM gaming_game_plays_bonus_instances
		LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_wager_requirement_met=1 AND now_used_all=0;
        
        SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
        SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;
        IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
          CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusRequirementMet', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
        END IF; 
        
        UPDATE gaming_game_plays_bonus_instances AS ggpbi 
        JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id=ggpbi.bonus_instance_id
        JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
        JOIN gaming_bonus_types_transfers AS transfer_type ON 
          gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id AND transfer_type.name IN ('ReleaseBonus','ReleaseAllBonus')
        SET 
            ggpbi.bonus_transfered_total=LEAST(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))* 
              gaming_bonus_instances.transfer_every_amount, 
              bonus_amount_remaining+current_win_locked_amount), 
            ggpbi.bonus_transfered=LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining),
            ggpbi.bonus_win_locked_transfered=ggpbi.bonus_transfered_total-ggpbi.bonus_transfered,
            bonus_amount_remaining=bonus_amount_remaining-bonus_transfered, current_win_locked_amount=current_win_locked_amount-bonus_win_locked_transfered,  
            gaming_bonus_instances.transfer_every_x_last=gaming_bonus_instances.transfer_every_x_last+(FLOOR((((FLOOR((bonus_wager_requirement-bonus_wager_requirement_remain)/bonus_amount_given))-transfer_every_x_last)/gaming_bonus_instances.transfer_every_x))*gaming_bonus_instances.transfer_every_x),
            gaming_bonus_instances.bonus_transfered_total=IFNULL(gaming_bonus_instances.bonus_transfered_total,0)+ggpbi.bonus_transfered_total,
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
        
        SELECT COUNT(*)>0, IFNULL(ROUND(SUM(bonus_transfered),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered),0),0), IFNULL(ROUND(SUM(bonus_transfered_lost),0),0), IFNULL(ROUND(SUM(bonus_win_locked_transfered_lost),0),0)  ,
		ROUND(SUM(IFNULL(IF(ring_fenced_by_bonus_rules,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=3,ring_fenced_transfered,0),0)),0),
		ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=1,ring_fenced_transfered,0),0)),0),ROUND(SUM(IFNULL(IF(ring_fenced_by_license_type=2,ring_fenced_transfered,0),0)),0)
        INTO @requireTransfer, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,
		@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker
        FROM gaming_game_plays_bonus_instances
		LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_game_plays_bonus_instances.bonus_rule_id
        WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0;

        SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
        SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;
        IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
          CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusCashExchange', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
        END IF; 
      END IF; 
      
    END LOOP allBetsLabel;
    CLOSE betsCursor;
  END IF;
 
	 UPDATE gaming_bonus_instances 
	 JOIN gaming_game_plays_bonus_instances ON gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
	 SET
	 	gaming_bonus_instances.is_active=IF(is_active=0,0,IF(is_secured,0,1))
	 WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID;           
  
  UPDATE gaming_sb_bets SET bet_total=bet_total-betAmount, is_processed=1, status_code=5 WHERE sb_bet_id=sbBetID;
  
  IF (playLimitEnabled) THEN 
    CALL PlayLimitsUpdate(clientStatID, licenseType, betAmount, 1);
  END IF;
  
  INSERT INTO gaming_sb_bet_history (sb_bet_id, sb_bet_transaction_type_id, timestamp, amount) 
  SELECT sbBetID, sb_bet_transaction_type_id, NOW(), betAmount
  FROM gaming_sb_bet_transaction_types WHERE name='PlaceBet';
  
  IF (canCommit) THEN COMMIT AND CHAIN; END IF;
  
  CALL CommonWalletSBReturnData(sbBetID, clientStatID);
  SET statusCode=0;
END root$$

DELIMITER ;
