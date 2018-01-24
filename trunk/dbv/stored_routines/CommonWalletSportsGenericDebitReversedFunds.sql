DROP procedure IF EXISTS `CommonWalletSportsGenericDebitReversedFunds`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSportsGenericDebitReversedFunds`(
  sbBetID BIGINT, minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN

  -- First Version :)  
  -- Checking only with payment_transaction_type_id=12 
  -- Forced indices
  -- Added support for Debit Lower than the reserved amount 
  -- Optimized for partitioning 
  
  DECLARE gameManufacturerID, gamePlayID, adjustmentGamePlayID, clientID, clientStatID, gameRoundID, currencyID, 
	clientWagerTypeID, countryID, sessionID, singleMultTypeID BIGINT DEFAULT -1;
  DECLARE isAlreadyProcessed, playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, loyaltyPointsEnabled, 
	taxEnabled, fingFencedEnabled, ruleEngineEnabled TINYINT(1) DEFAULT 0;
  DECLARE numSingles, numMultiples, sbBetStatusCode INT DEFAULT 0;
  DECLARE betAmount, confirmedAmount DECIMAL(18,5) DEFAULT 0;
  DECLARE betReal, betBonus, betBonusWinLocked, betFreeBet DECIMAL(18,5) DEFAULT 0;
  DECLARE betRealConfirmedNow, betBonusConfirmedNow, betBonusWinLockedConfirmedNow, 
	betFreeBetConfirmedNow, betTotalConfirmedNow, singlesLessAmount, multiplesLessAmount,
    cancelledTotalNow, cancelledRealNow, cancelledBonusNow, cancelledBonusWinLockedNow DECIMAL(18,5) DEFAULT 0;
  DECLARE roundType, licenseType VARCHAR(20) DEFAULT NULL; 
  DECLARE licenseTypeID TINYINT(4) DEFAULT 3; -- sports
  
  DECLARE partitioningMinusFromMax INT DEFAULT 10000;
  DECLARE minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, 
	minSbBetMultipleSingleID, maxSbBetMultipleSingleID, minGameRoundID, maxGameRoundID, 
    minGamePlaySBID, maxGamePlaySBID, minGamePlayBonusInstanceID, maxGamePlayBonusInstanceID BIGINT DEFAULT NULL;
  
  SET licenseType='sportsbook';
  
  -- system settings based on operator - per site
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3,
		 gs4.value_bool as vb4, gs5.value_bool as vb5, gs6.value_bool as vb6
    INTO playLimitEnabled, bonusEnabledFlag, loyaltyPointsEnabled, 
		taxEnabled, fingFencedEnabled, ruleEngineEnabled
    FROM gaming_settings gs1 
    STRAIGHT_JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
    STRAIGHT_JOIN gaming_settings gs3 ON (gs3.name='LOYALTY_POINTS_WAGER_ENABLED')
    STRAIGHT_JOIN gaming_settings gs4 ON (gs4.name='TAX_ON_GAMEPLAY_ENABLED')
    STRAIGHT_JOIN gaming_settings gs5 ON (gs5.name='RING_FENCED_ENABLED')
    STRAIGHT_JOIN gaming_settings gs6 ON (gs6.name='RULE_ENGINE_ENABLED')
    WHERE gs1.name='PLAY_LIMIT_ENABLED';
    
  -- Check the bet exists and it is in the correct status
  SELECT gsb.sb_bet_id, gsb.game_manufacturer_id, IFNULL(gsb.wager_game_play_id, -1), 
	gsb.client_stat_id, gsb.bet_total, gsb.num_singles, gsb.num_multiplies, gsb.status_code,
    gsbpf.max_sb_bet_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_single_id, 
    gsbpf.max_sb_bet_multiple_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_id,
    gsbpf.max_sb_bet_multiple_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_single_id,
    gsbpf.min_game_round_id, gsbpf.max_game_round_id, 
    gsbpf.min_game_play_sb_id, gsbpf.max_game_play_sb_id
  INTO sbBetID, gameManufacturerID, gamePlayID, 
	clientStatID, betAmount, numSingles, numMultiples, sbBetStatusCode,
    minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, minSbBetMultipleSingleID, maxSbBetMultipleSingleID,
    minGameRoundID, maxGameRoundID, minGamePlaySBID, maxGamePlaySBID
  FROM gaming_sb_bets AS gsb
  LEFT JOIN gaming_sb_bets_partition_fields AS gsbpf ON gsbpf.sb_bet_id=gsb.sb_bet_id
  WHERE gsb.sb_bet_id=sbBetID;

  IF (gamePlayID=-1 OR clientStatID=-1) THEN
	SET statusCode=1;
	LEAVE root;
  END IF;

  -- Lock Player
  SELECT client_stat_id, client_id, currency_id
  INTO clientStatID, clientID, currencyID 
  FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;

  -- Get How much was confirmed in total for the whole bet slip (before this procedure)
  SELECT IFNULL(SUM(amount_real),0) AS amount_real, 
	IFNULL(SUM(amount_bonus-amount_bonus_win_locked_component),0) AS amount_bonus, 
	IFNULL(SUM(amount_bonus_win_locked_component),0) AS amount_bonus_win_locked
  INTO betReal, betBonus, betBonusWinLocked
  FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id) 
  WHERE sb_bet_id=sbBetID AND 
	-- parition filtering
	(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID) AND
    -- other filtering
    confirmation_status=2 AND payment_transaction_type_id=12;

  -- Adjustment Step 1: Check if the actually debited amount is less than the reserved amount
  IF (numSingles>0) THEN
	  SELECT SUM(gaming_game_rounds.bet_total-gaming_sb_bet_singles.bet_amount)
	  INTO singlesLessAmount
	  FROM gaming_sb_bet_singles FORCE INDEX (sb_bet_id) 
	  STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (sb_bet_entry_id) ON 
		(gaming_sb_bet_singles.sb_bet_id=sbBetID AND gaming_sb_bet_singles.processing_status=1) AND
        -- parition filtering
		(gaming_sb_bet_singles.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID) AND
        -- join
		((gaming_game_rounds.sb_bet_entry_id=gaming_sb_bet_singles.sb_bet_single_id AND gaming_game_rounds.sb_bet_id=sbBetID AND 
			gaming_game_rounds.game_round_type_id=4 AND gaming_game_rounds.license_type_id=3) AND
		  -- parition filtering
          (gaming_game_rounds.game_round_id BETWEEN minGameRoundID AND maxGameRoundID));
   END IF;
  
   IF (numMultiples>0) THEN
	  SELECT SUM(gaming_game_rounds.bet_total-gaming_sb_bet_multiples.bet_amount)
	  INTO multiplesLessAmount
	  FROM gaming_sb_bet_multiples FORCE INDEX (sb_bet_id)
	  STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (sb_bet_entry_id) ON 
		(gaming_sb_bet_multiples.sb_bet_id=sbBetID AND gaming_sb_bet_multiples.processing_status=1) AND
        -- parition filtering
		(gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID) AND
        -- join
		((gaming_game_rounds.sb_bet_entry_id=gaming_sb_bet_multiples.sb_bet_multiple_id AND gaming_game_rounds.sb_bet_id=sbBetID AND
		  gaming_game_rounds.game_round_type_id=5 AND gaming_game_rounds.license_type_id=3) AND
		  -- parition filtering
         (gaming_game_rounds.game_round_id BETWEEN minGameRoundID AND maxGameRoundID));
   END IF;
   
   -- Adjustment Step 2: Enter adjusment transaction if needed
   IF ((singlesLessAmount+multiplesLessAmount)>0) THEN
		
        -- Insert to get game_play_id but values would need to be updated to a later stage
	  INSERT INTO gaming_game_plays 
	  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_free_bet, amount_other, bonus_lost, jackpot_contribution, 
	   timestamp, game_manufacturer_id, client_id, client_stat_id, session_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, 
	   pending_bet_real, pending_bet_bonus, currency_id, sign_mult, sb_bet_id, license_type_id, loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus,
	   confirmed_amount, is_confirmed, game_play_message_type_id, game_round_id) 
	  SELECT singlesLessAmount+multiplesLessAmount, (singlesLessAmount+multiplesLessAmount)/ggp.exchange_rate, ggp.exchange_rate, 0, 0, 0, 0, 0, 0, 0, 
		NOW(), ggp.game_manufacturer_id, ggp.client_id, ggp.client_stat_id, ggp.session_id, gaming_payment_transaction_type.payment_transaction_type_id, 0, 0, 0, 
		0, 0, ggp.currency_id, 1,  ggp.sb_bet_id, ggp.license_type_id, 0, 0, 0, 0,
		0, 0, gaming_game_play_message_types.game_play_message_type_id, ggp.game_round_id
	  FROM gaming_game_plays AS ggp FORCE INDEX (PRIMARY)
	  STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='BetAdjustment' 
	  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=('SportsAdjustment' COLLATE utf8_general_ci)
	  WHERE ggp.game_play_id=gamePlayID;
      
      SET adjustmentGamePlayID=LAST_INSERT_ID();
	  
   END IF;

  -- Update the status of gaming_game_plays_sb, gaming_sb_bet_singles & gaming_sb_bet_multiples
  SELECT sb_multiple_type_id INTO singleMultTypeID FROM gaming_sb_multiple_types WHERE name='Single' AND game_manufacturer_id=gameManufacturerID; 

  IF (numSingles>0) THEN
	UPDATE gaming_sb_bet_singles FORCE INDEX (sb_bet_id)
	STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (sb_bet_entry_id) ON 
		(gaming_sb_bet_singles.sb_bet_id=sbBetID AND gaming_sb_bet_singles.processing_status=1) AND
        -- parition filtering
		(gaming_sb_bet_singles.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID) AND
        -- join
		(gaming_game_plays_sb.sb_bet_entry_id=gaming_sb_bet_singles.sb_bet_single_id AND gaming_game_plays_sb.sb_multiple_type_id=singleMultTypeID) AND
        -- parition filtering
		(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)
	SET gaming_game_plays_sb.confirmation_status=2;

	-- Adjustment Step 3:
	IF (singlesLessAmount>0) THEN
    
	    -- insert bet adjustment for each single
		INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, 
		  amount_bonus, amount_bonus_base, amount_bonus_win_locked_component, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, 
		  round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, 
		  sb_bet_type, device_type, units, confirmation_status, game_round_id, sb_bet_entry_id)
		SELECT GREATEST(adjustmentGamePlayID, (@adjustmentRatio:=(gaming_game_plays_sb.amount_total-gaming_sb_bet_singles.bet_amount)/gaming_game_plays_sb.amount_total)), 45, 
	       gaming_game_plays_sb.amount_total-gaming_sb_bet_singles.bet_amount, gaming_game_plays_sb.amount_total_base*@adjustmentRatio, 
           gaming_game_plays_sb.amount_real*@adjustmentRatio, gaming_game_plays_sb.amount_real_base*@adjustmentRatio, 
		   gaming_game_plays_sb.amount_bonus*@adjustmentRatio, gaming_game_plays_sb.amount_bonus_base*@adjustmentRatio, 
           gaming_game_plays_sb.amount_bonus_win_locked_component*@adjustmentRatio, NOW(), 
		   gaming_game_plays_sb.exchange_rate, gaming_game_plays_sb.game_manufacturer_id, gaming_game_plays_sb.client_id, 
           gaming_game_plays_sb.client_stat_id, gaming_game_plays_sb.currency_id, gaming_game_plays_sb.country_id,
		   gaming_game_plays_sb.round_transaction_no+100, gaming_game_plays_sb.sb_sport_id, gaming_game_plays_sb.sb_region_id, 
           gaming_game_plays_sb.sb_group_id, gaming_game_plays_sb.sb_event_id, gaming_game_plays_sb.sb_market_id, 
           gaming_game_plays_sb.sb_selection_id, gaming_game_plays_sb.sb_bet_id, gaming_game_plays_sb.sb_multiple_type_id, 
		   gaming_game_plays_sb.sb_bet_type, gaming_game_plays_sb.device_type, 0, 2, 
           gaming_game_plays_sb.game_round_id, gaming_game_plays_sb.sb_bet_entry_id
		FROM gaming_sb_bet_singles FORCE INDEX (sb_bet_id) 
		STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (sb_bet_entry_id) ON 
			(gaming_sb_bet_singles.sb_bet_id=sbBetID AND gaming_sb_bet_singles.processing_status=1) AND
            -- parition filtering
			(gaming_sb_bet_singles.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID) AND
			-- join
            (gaming_game_rounds.sb_bet_entry_id=gaming_sb_bet_singles.sb_bet_single_id AND gaming_game_rounds.sb_bet_id=sbBetID 
				AND gaming_game_rounds.game_round_type_id=4 AND gaming_game_rounds.license_type_id=3) AND
            gaming_game_rounds.bet_total!=gaming_sb_bet_singles.bet_amount AND
            -- parition filtering
			(gaming_game_rounds.game_round_id BETWEEN minGameRoundID AND maxGameRoundID)
		STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (game_play_id) ON 
			gaming_game_plays_sb.game_play_id=gamePlayID AND gaming_game_plays_sb.game_round_id=gaming_game_rounds.game_round_id AND
            -- parition filtering
			(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)
		LEFT JOIN gaming_game_play_message_types ON 
			gaming_game_play_message_types.name=('SportsAdjustment' COLLATE utf8_general_ci);
            
		IF (ROW_COUNT() > 0) THEN
			SET maxGamePlaySBID=ROW_COUNT()+LAST_INSERT_ID()-1;
		END IF;
        
        -- update round bet values
        UPDATE gaming_sb_bet_singles FORCE INDEX (sb_bet_id) 
		STRAIGHT_JOIN gaming_game_rounds AS ggr FORCE INDEX (sb_bet_entry_id) ON 
			(gaming_sb_bet_singles.sb_bet_id=sbBetID AND gaming_sb_bet_singles.processing_status=1) AND
            -- parition filtering
			(gaming_sb_bet_singles.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID) AND
			-- join
            (ggr.sb_bet_entry_id=gaming_sb_bet_singles.sb_bet_single_id AND ggr.sb_bet_id=sbBetID 
				AND ggr.game_round_type_id=4 AND ggr.license_type_id=3) AND
            ggr.bet_total!=gaming_sb_bet_singles.bet_amount AND
            -- parition filtering
			(ggr.game_round_id BETWEEN minGameRoundID AND maxGameRoundID)
		SET ggr.jackpot_contribution=LEAST(ggr.jackpot_contribution, (@adjustmentRatio:=(gaming_sb_bet_singles.bet_amount/ggr.bet_total))),
			ggr.bet_total=ggr.bet_total*@adjustmentRatio, ggr.bet_total_base=ggr.bet_total_base*@adjustmentRatio, 
            ggr.bet_real=ggr.bet_real*@adjustmentRatio, ggr.bet_bonus=ggr.bet_bonus*@adjustmentRatio, ggr.bet_bonus_win_locked=ggr.bet_bonus_win_locked*@adjustmentRatio;
            
	END IF;

	UPDATE gaming_sb_bet_singles FORCE INDEX (sb_bet_id) 
    SET processing_status=2 
    WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID AND gaming_sb_bet_singles.processing_status=1 AND
		-- parition filtering
		(gaming_sb_bet_singles.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID);
    
  END IF;

  IF (numMultiples>0) THEN
  
	UPDATE gaming_sb_bet_multiples FORCE INDEX (sb_bet_id)
	STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (sb_bet_entry_id) ON 
		(gaming_sb_bet_multiples.sb_bet_id=sbBetID AND gaming_sb_bet_multiples.processing_status=1) AND
        -- parition filtering
		(gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID) AND
        -- join
		(gaming_game_plays_sb.sb_bet_entry_id=gaming_sb_bet_multiples.sb_bet_multiple_id AND gaming_game_plays_sb.sb_multiple_type_id!=singleMultTypeID) AND
        -- parition filtering
		(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)
	SET gaming_game_plays_sb.confirmation_status=2;

	-- Adjustment Step 3:
	IF (multiplesLessAmount>0) THEN
    
		-- insert bet adjustment for each multiple
		INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, 
		  amount_bonus, amount_bonus_base, amount_bonus_win_locked_component, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, 
		  round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, 
		  sb_bet_type, device_type, units, confirmation_status, game_round_id, sb_bet_entry_id)
		SELECT GREATEST(adjustmentGamePlayID, (@adjustmentRatio:=(gaming_game_plays_sb.amount_total-gaming_sb_bet_multiples.bet_amount)/gaming_game_plays_sb.amount_total)), 45, 
	       gaming_game_plays_sb.amount_total-gaming_sb_bet_multiples.bet_amount, gaming_game_plays_sb.amount_total_base*@adjustmentRatio, 
           gaming_game_plays_sb.amount_real*@adjustmentRatio, gaming_game_plays_sb.amount_real_base*@adjustmentRatio, 
		   gaming_game_plays_sb.amount_bonus*@adjustmentRatio, gaming_game_plays_sb.amount_bonus_base*@adjustmentRatio, 
           gaming_game_plays_sb.amount_bonus_win_locked_component*@adjustmentRatio, NOW(), 
		   gaming_game_plays_sb.exchange_rate, gaming_game_plays_sb.game_manufacturer_id, gaming_game_plays_sb.client_id, 
           gaming_game_plays_sb.client_stat_id, gaming_game_plays_sb.currency_id, gaming_game_plays_sb.country_id,
		   gaming_game_plays_sb.round_transaction_no+100, gaming_game_plays_sb.sb_sport_id, gaming_game_plays_sb.sb_region_id, 
           gaming_game_plays_sb.sb_group_id, gaming_game_plays_sb.sb_event_id, gaming_game_plays_sb.sb_market_id, 
           gaming_game_plays_sb.sb_selection_id, gaming_game_plays_sb.sb_bet_id, gaming_game_plays_sb.sb_multiple_type_id, 
		   gaming_game_plays_sb.sb_bet_type, gaming_game_plays_sb.device_type, 0, 2, 
           gaming_game_plays_sb.game_round_id, gaming_game_plays_sb.sb_bet_entry_id
		FROM gaming_sb_bet_multiples FORCE INDEX (sb_bet_id)
		STRAIGHT_JOIN gaming_game_rounds FORCE INDEX (sb_bet_entry_id) ON 
			(gaming_sb_bet_multiples.sb_bet_id=sbBetID AND gaming_sb_bet_multiples.processing_status=1) AND
            -- parition filtering
			(gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID) AND
			-- join
			(gaming_game_rounds.sb_bet_entry_id=gaming_sb_bet_multiples.sb_bet_multiple_id AND gaming_game_rounds.sb_bet_id=sbBetID AND
				gaming_game_rounds.game_round_type_id=5 AND gaming_game_rounds.license_type_id=3) AND
			gaming_game_rounds.bet_total!=gaming_sb_bet_multiples.bet_amount AND
            -- parition filtering
			(gaming_game_rounds.game_round_id BETWEEN minGameRoundID AND maxGameRoundID)
		STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (game_play_id) ON 
			gaming_game_plays_sb.game_play_id=gamePlayID AND gaming_game_plays_sb.game_round_id=gaming_game_rounds.game_round_id
            -- parition filtering
			(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)
		LEFT JOIN gaming_game_play_message_types ON 
			gaming_game_play_message_types.name=('SportsAdjustment' COLLATE utf8_general_ci);
        
		IF (ROW_COUNT() > 0) THEN
			SET maxGamePlaySBID=ROW_COUNT()+LAST_INSERT_ID()-1;
		END IF;
        
        -- update round bet values
        UPDATE gaming_sb_bet_multiples FORCE INDEX (sb_bet_id)
		STRAIGHT_JOIN gaming_game_rounds AS ggr FORCE INDEX (sb_bet_entry_id) ON 
			(gaming_sb_bet_multiples.sb_bet_id=sbBetID AND gaming_sb_bet_multiples.processing_status=1) AND
            -- parition filtering
			(gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID) AND
			-- join
            (ggr.sb_bet_entry_id=gaming_sb_bet_multiples.sb_bet_multiple_id AND ggr.sb_bet_id=sbBetID AND
				ggr.game_round_type_id=5 AND ggr.license_type_id=3) AND
			ggr.bet_total!=gaming_sb_bet_multiples.bet_amount AND
            -- parition filtering
			(ggr.game_round_id BETWEEN minGameRoundID AND maxGameRoundID)
		SET ggr.jackpot_contribution=LEAST(ggr.jackpot_contribution, (@adjustmentRatio:=(gaming_sb_bet_multiples.bet_amount/ggr.bet_total))),
			ggr.bet_total=ggr.bet_total*@adjustmentRatio, ggr.bet_total_base=ggr.bet_total_base*@adjustmentRatio, 
            ggr.bet_real=ggr.bet_real*@adjustmentRatio, ggr.bet_bonus=ggr.bet_bonus*@adjustmentRatio, ggr.bet_bonus_win_locked=ggr.bet_bonus_win_locked*@adjustmentRatio;
            
	END IF;
    
	UPDATE gaming_sb_bet_multiples FORCE INDEX (sb_bet_id) 
    SET processing_status=2 
    WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID AND gaming_sb_bet_multiples.processing_status=1 AND
		(gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID);
    
  END IF;

    -- Get How much was confirmed by this stored procedure
  SELECT IFNULL(SUM(amount_real),0)-betReal AS amount_real, 
	IFNULL(SUM(amount_bonus-amount_bonus_win_locked_component),0)-betBonus AS amount_bonus, 
    IFNULL(SUM(amount_bonus_win_locked_component),0)-betBonusWinLocked AS amount_bonus_win_locked
  INTO betRealConfirmedNow, betBonusConfirmedNow, betBonusWinLockedConfirmedNow
  FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id) 
  WHERE sb_bet_id=sbBetID AND confirmation_status=2 AND payment_transaction_type_id=12 AND
	-- parition filtering
	(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID);

  SET betTotalConfirmedNow=betRealConfirmedNow+betBonusConfirmedNow+betBonusWinLockedConfirmedNow;


  -- Adjustment Step 4:
  IF ((singlesLessAmount+multiplesLessAmount)>0) THEN
  
	  -- Get How much was confirmed by this stored procedure
	  SELECT IFNULL(SUM(amount_real),0) AS amount_real, 
		IFNULL(SUM(amount_bonus-amount_bonus_win_locked_component),0) AS amount_bonus, 
		IFNULL(SUM(amount_bonus_win_locked_component),0) AS amount_bonus_win_locked
	  INTO cancelledRealNow, cancelledBonusNow, cancelledBonusWinLockedNow
	  FROM gaming_game_plays_sb FORCE INDEX (game_play_id)
	  WHERE gaming_game_plays_sb.game_play_id=adjustmentGamePlayID AND
		-- parition filtering
		(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID);

	  -- Get Total to cancel
	  SET cancelledTotalNow=cancelledRealNow+cancelledBonusNow+cancelledBonusWinLockedNow;
      
      -- Return bonus funds if needed
      CALL CommonWalletSportsGenericReturnBonuses(sbBetID, maxGamePlaySBID,
		adjustmentGamePlayID, cancelledTotalNow, cancelledRealNow, cancelledBonusNow, cancelledBonusWinLockedNow);
  
	  -- Give the credits back to the player and deduct reserved funds
	  UPDATE gaming_client_stats AS gcs
	  SET
		gcs.current_real_balance=gcs.current_real_balance+cancelledRealNow, gcs.current_bonus_balance=gcs.current_bonus_balance+cancelledBonusNow, gcs.current_bonus_win_locked_balance=gcs.current_bonus_win_locked_balance+cancelledBonusWinLockedNow,
		gcs.pending_bets_real=pending_bets_real-cancelledRealNow, gcs.pending_bets_bonus=pending_bets_bonus-(cancelledBonusNow+cancelledBonusWinLockedNow)
	  WHERE gcs.client_stat_id=clientStatID;
	  
	  -- Fix the values in the cancel transaction
	  UPDATE gaming_game_plays AS ggp FORCE INDEX (PRIMARY)
	  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
	  SET 
		ggp.amount_total=cancelledTotalNow,
		ggp.amount_total_base=cancelledTotalNow/ggp.exchange_rate,
		ggp.amount_real=cancelledRealNow,
		ggp.amount_bonus=cancelledBonusNow,
		ggp.amount_bonus_win_locked=cancelledBonusWinLockedNow, 
		ggp.amount_free_bet=0, -- To Check with Steve
		ggp.amount_other=0,
		ggp.bonus_lost=@bonusLost+@bonusWinLockedLost,
		ggp.balance_real_after=current_real_balance, ggp.balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance, ggp.balance_bonus_win_locked_after=current_bonus_win_locked_balance, 
		ggp.pending_bet_real=gaming_client_stats.pending_bets_real, ggp.pending_bet_bonus=gaming_client_stats.pending_bets_bonus,
		ggp.loyalty_points_after=gaming_client_stats.current_loyalty_points, ggp.loyalty_points_after_bonus= (gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
	  WHERE ggp.game_play_id=adjustmentGamePlayID;
	  
	  -- Update ring fenced statistics
      IF (fingFencedEnabled) THEN
		CALL GameUpdateRingFencedBalances(clientStatID, adjustmentGamePlayID);    
	  END IF;
      
	   -- Update the betslip status
	  UPDATE gaming_sb_bets 
	  SET 
		amount_real=amount_real-cancelledRealNow, amount_bonus=amount_bonus-cancelledBonusNow, 
		amount_bonus_win_locked=amount_bonus_win_locked-cancelledBonusWinLockedNow -- , amount_free_bet=IFNULL(FreeBonusAmount,0), -- Check with Steve
	  WHERE sb_bet_id=sbBetID;
	  
	  IF (playLimitEnabled) THEN 
		CALL PlayLimitsUpdate(clientStatID, licenseType, cancelledTotalNow*-1, 1);
	  END IF;
      
      SET betRealConfirmedNow=betRealConfirmedNow-cancelledRealNow; 
      SET betBonusConfirmedNow=betBonusConfirmedNow-cancelledBonusNow;
      SET betBonusWinLockedConfirmedNow=betBonusWinLockedConfirmedNow-cancelledBonusWinLockedNow;
      SET betTotalConfirmedNow=betTotalConfirmedNow-cancelledTotalNow;
  END IF;

    -- Return Error if there was noting to confirm
  IF (betTotalConfirmedNow>0) THEN

	  -- Deduct Reserved Funds
	  UPDATE gaming_client_stats AS gcs
	  SET gcs.pending_bets_real=pending_bets_real-betRealConfirmedNow, 
		  gcs.pending_bets_bonus=pending_bets_bonus-(betBonusConfirmedNow+betBonusWinLockedConfirmedNow)
	  WHERE gcs.client_stat_id=clientStatID;

	  -- Update the confirmed amount
	  UPDATE gaming_game_plays SET confirmed_amount=confirmed_amount+betTotalConfirmedNow WHERE game_play_id=gamePlayID; 
      
  END IF;
  
  UPDATE gaming_sb_bets_partition_fields
  SET 
    max_game_play_sb_id=maxGamePlaySBID
  WHERE sb_bet_id=sbBetID;

  -- Return data to the application 
  CALL CommonWalletSBReturnData(sbBetID, clientStatID, gamePlayID, minimalData);
  
  SET statusCode=0;

END root$$

DELIMITER ;

