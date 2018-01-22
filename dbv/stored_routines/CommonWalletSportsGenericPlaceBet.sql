DROP procedure IF EXISTS `CommonWalletSportsGenericPlaceBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSportsGenericPlaceBet`(
  sbBetID BIGINT, minimalData TINYINT(1), OUT statusCode INT)
root: BEGIN

  -- First Version :)
  -- All singles and multiples in (gaming_game_plays_sb) which have not been cancelled will be accepted/confirmed
  -- Updates the wagering requirement of a bonus  
  -- Checking with payment_transaction_type_id IN (12, 45)
  -- Checking if there is nothing to commit return immediately
  -- Forced indices
  -- Recalcualte Bonus Wagering Requirement if SPORTS_BOOK_RECALCULATE_BONUS_CONTRIBUTION_WEIGHT_ON_COMMIT setting is on
  -- WHERE gaming_game_plays_sb.sb_bet_id=sbBetID AND sb_bonuses.wager_requirement_non_weighted > 0
  -- Performance: 2017-01-15
  -- Optimized for Parititioning
  
  DECLARE gameManufacturerID, gamePlayID, clientID, clientStatID, gameRoundID, currencyID, clientWagerTypeID, countryID, sessionID BIGINT DEFAULT -1;
  DECLARE isAlreadyProcessed, playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, isProcessed TINYINT(1) DEFAULT 0;
  DECLARE numSingles, numMultiples, sbBetStatusCode, commmitedBetEntries INT DEFAULT 0;
  DECLARE betAmount, betRealRemain, betBonusRemain, betBonusWinLockedRemain, FreeBonusAmount DECIMAL(18,5) DEFAULT 0;
  DECLARE betReal, betBonus, betBonusWinLocked, betFreeBet DECIMAL(18,5) DEFAULT 0;
  DECLARE betRealConfirmedNow, betBonusConfirmedNow, betBonusWinLockedConfirmedNow, betFreeBetConfirmedNow DECIMAL(18,5) DEFAULT 0;
  DECLARE bxBetAmount, bxBetReal, bxBetBonus, bxBetBonusWinLocked DECIMAL(18,5) DEFAULT 0;
  DECLARE balanceReal, balanceBonus, balanceWinLocked, betRemain, exchangeRate, betAmountBase, sbOdd, 
	pendingBetsReal, pendingBetsBonus, loyaltyPoints, loyaltyPointsBonus DECIMAL(18, 5) DEFAULT 0;
  DECLARE roundType, licenseType VARCHAR(20) DEFAULT NULL;
  DECLARE licenseTypeID TINYINT(4) DEFAULT 3; 
  DECLARE recalcualteBonusWeight, isCouponBet TINYINT(1) DEFAULT 0;

  DECLARE partitioningMinusFromMax INT DEFAULT 10000;
  DECLARE minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, 
	minSbBetMultipleSingleID, maxSbBetMultipleSingleID, minGameRoundID, maxGameRoundID, 
    minGamePlaySBID, maxGamePlaySBID, minGamePlayBonusInstanceID, maxGamePlayBonusInstanceID BIGINT DEFAULT NULL; 

  SET statusCode=0;
   
  -- Check the bet exists and it is in the correct status
  SELECT gsb.sb_bet_id, gsb.game_manufacturer_id, IFNULL(gsb.wager_game_play_id, -1), gsb.client_stat_id, gsb.bet_total, 
	gsb.num_singles, gsb.num_multiplies, gsb.status_code, gsb.amount_real, gsb.amount_bonus, gsb.amount_bonus_win_locked, gsb.amount_free_bet, 
    gsb.is_processed, gsb.lottery_dbg_ticket_id IS NOT NULL,
    gsbpf.max_sb_bet_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_single_id, 
    gsbpf.max_sb_bet_multiple_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_id,
    gsbpf.max_sb_bet_multiple_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_single_id,
    gsbpf.min_game_round_id, gsbpf.max_game_round_id, 
    gsbpf.min_game_play_sb_id, gsbpf.max_game_play_sb_id
  INTO sbBetID, gameManufacturerID, gamePlayID, clientStatID, betAmount, 
	numSingles, numMultiples, sbBetStatusCode, betReal, betBonus, betBonusWinlocked, betFreeBet, 
    isProcessed, isCouponBet,
    minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, minSbBetMultipleSingleID, maxSbBetMultipleSingleID,
    minGameRoundID, maxGameRoundID, minGamePlaySBID, maxGamePlaySBID
  FROM gaming_sb_bets AS gsb
  LEFT JOIN gaming_sb_bets_partition_fields AS gsbpf ON gsbpf.sb_bet_id=gsb.sb_bet_id
  WHERE gsb.sb_bet_id=sbBetID;
  
  IF (sbBetID=-1 OR clientStatID=-1 OR gamePlayID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  IF (sbBetStatusCode NOT IN (3,6) OR isProcessed=1) THEN 
    SET statusCode=2;
	IF (isCouponBet) THEN
		SELECT game_round_id INTO gameRoundID FROM gaming_game_plays WHERE game_play_id = gamePlayID;
		CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID, minimalData);
		CALL PlayReturnBonusInfoOnWin(gamePlayID);
	ELSE
		CALL CommonWalletSBReturnData(sbBetID, clientStatID, gamePlayID, minimalData);
	END IF;
    LEAVE root;
  END IF;	

  -- Get Settings
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, IFNULL(gs4.value_bool, 0)
  INTO playLimitEnabled, bonusEnabledFlag, bonusReqContributeRealOnly, recalcualteBonusWeight
  FROM gaming_settings gs1 
  STRAIGHT_JOIN gaming_settings gs2 ON gs2.name='IS_BONUS_ENABLED'
  STRAIGHT_JOIN gaming_settings gs3 ON gs3.name='BONUS_CONTRIBUTION_REAL_MONEY_ONLY'
  LEFT JOIN gaming_settings gs4 ON gs4.name='SPORTS_BOOK_RECALCULATE_BONUS_CONTRIBUTION_WEIGHT_ON_COMMIT'
  WHERE gs1.name='PLAY_LIMIT_ENABLED';
  
  SET licenseType='sportsbook';
  SELECT client_wager_type_id INTO clientWagerTypeID FROM gaming_client_wager_types WHERE name='sb'; 

  -- Lock Player
  SELECT client_stat_id, client_id, currency_id, current_real_balance, 
	current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, IFNULL(pending_bets_real,0), pending_bets_bonus
  INTO clientStatID, clientID, currencyID, balanceReal, balanceBonus, balanceWinLocked, pendingBetsReal, pendingBetsBonus 
  FROM gaming_client_stats 
  WHERE client_stat_id=clientStatID 
  FOR UPDATE;
  
  -- Get Country ID
  SELECT country_id INTO countryID FROM clients_locations FORCE INDEX (client_id) WHERE clients_locations.client_id=clientID AND clients_locations.is_primary=1; 
  
  -- Get Session ID of Reserve Funds
  SELECT session_id INTO sessionID FROM gaming_game_plays WHERE game_play_id=gamePlayID;

  -- Check how much is confirmed now and that needs to be deducted from the reserved funds
  SELECT IFNULL(SUM(amount_real),0) AS amount_real, IFNULL(SUM(amount_bonus-amount_bonus_win_locked_component),0) AS amount_bonus, 
	IFNULL(SUM(amount_bonus_win_locked_component),0) AS amount_bonus_win_locked
  INTO betRealConfirmedNow, betBonusConfirmedNow, betBonusWinLockedConfirmedNow
  FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
  WHERE sb_bet_id=sbBetID AND 
	-- parition filtering
	(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID) AND
	-- other filtering
	(confirmation_status=0 AND payment_transaction_type_id IN (12, 45));

  -- Set to confirmed all bet slips which have not been explicitily cancelled
  UPDATE gaming_game_plays_sb FORCE INDEX (sb_bet_id) 
  SET confirmation_status=2 
  WHERE sb_bet_id=sbBetID AND 
	-- parition filtering
	(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID) AND
	-- other filtering
	(confirmation_status=0 AND payment_transaction_type_id IN (12, 45));
  
  UPDATE gaming_sb_bet_singles FORCE INDEX (sb_bet_id) 
  SET processing_status=2
  WHERE gaming_sb_bet_singles.sb_bet_id=sbBetID AND 
	-- parition filtering
	(gaming_sb_bet_singles.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID) AND
	-- other filtering
	gaming_sb_bet_singles.processing_status<>3;

  UPDATE gaming_sb_bet_multiples FORCE INDEX (sb_bet_id) 
  SET processing_status=2 
  WHERE gaming_sb_bet_multiples.sb_bet_id=sbBetID AND 
	-- parition filtering
	(gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID) AND
	-- other filtering
    gaming_sb_bet_multiples.processing_status<>3;

  -- Get How much was confirmed in total for the whole bet slip
  SELECT COUNT(*), IFNULL(SUM(amount_real),0) AS amount_real, IFNULL(SUM(amount_bonus-amount_bonus_win_locked_component),0) AS amount_bonus, 
	IFNULL(SUM(amount_bonus_win_locked_component),0) AS amount_bonus_win_locked
  INTO commmitedBetEntries, betReal, betBonus, betBonusWinLocked
  FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
  WHERE sb_bet_id=sbBetID AND 
	-- parition filtering
	(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID) AND
	-- other filtering
	confirmation_status=2;

  IF (commmitedBetEntries=0) THEN
	UPDATE gaming_sb_bets FORCE INDEX (PRIMARY) SET bet_total=bet_total-betAmount, is_processed=1, is_success=1, status_code=5 WHERE sb_bet_id=sbBetID;
    
	CALL CommonWalletSBReturnData(sbBetID, clientStatID, gamePlayID, minimalData);
    SET statusCode=0;
    
  END IF;

  -- Update the SB Bet figures
  UPDATE gaming_sb_bets
  SET gaming_sb_bets.amount_real=betReal, gaming_sb_bets.amount_bonus=betBonus, gaming_sb_bets.amount_bonus_win_locked=betBonusWinLocked,
	  gaming_sb_bets.bet_total=betReal+betBonus+betBonusWinLocked
  WHERE sb_bet_id=sbBetID;

  -- Get Currenty Exchange Rate
  SELECT exchange_rate into exchangeRate 
  FROM gaming_client_stats
  STRAIGHT_JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
  WHERE gaming_client_stats.client_stat_id=clientStatID;
  
  SET betAmountBase=ROUND(betAmount/exchangeRate, 5);
  
  -- Update player totals
  UPDATE gaming_client_stats AS gcs
  LEFT JOIN gaming_client_sessions AS gcss ON gcss.session_id=sessionID
  LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
  SET -- gaming_client_stats
	  gcs.pending_bets_real=pending_bets_real-betRealConfirmedNow, gcs.pending_bets_bonus=pending_bets_bonus-(betBonusConfirmedNow+betBonusWinLockedConfirmedNow),
	  gcs.total_real_played=gcs.total_real_played+betReal, 
      gcs.total_bonus_played=gcs.total_bonus_played+betBonus, 
      gcs.total_bonus_win_locked_played=gcs.total_bonus_win_locked_played+betBonusWinLocked, 
      gcs.total_real_played_base=gcs.total_real_played_base+(betReal/exchangeRate), gcs.total_bonus_played_base=gcs.total_bonus_played_base+((betBonus+betBonusWinLocked)/exchangeRate),
      gcs.last_played_date=NOW(), 
      -- gaming_client_sessions
      gcss.total_bet=gcss.total_bet+betAmount,gcss.total_bet_base=gcss.total_bet_base+betAmountBase, gcss.bets=gcss.bets+numSingles+numMultiples, gcss.total_bet_real=gcss.total_bet_real+betReal, gcss.total_bet_bonus=gcss.total_bet_bonus+betBonus+betBonusWinLocked,
      -- gaming_client_wager_stats
      gcws.num_bets=gcws.num_bets+numSingles+numMultiples, gcws.total_real_wagered=gcws.total_real_wagered+betReal, gcws.total_bonus_wagered=gcws.total_bonus_wagered+betBonus+betBonusWinLocked,
      gcws.first_wagered_date=IFNULL(gcws.first_wagered_date, NOW()), gcws.last_wagered_date=NOW()
  WHERE gcs.client_stat_id = clientStatID;
  
  -- Update confirmed amount
  UPDATE gaming_game_plays
  SET is_confirmed=1, confirmed_amount=betReal+betBonus+betBonusWinLocked, is_processed=0  
  WHERE game_play_id=gamePlayID;
  
  -- Update bonus tables and check if the bonuses requirement has met 
  IF (bonusEnabledFlag AND betAmount>0) THEN
    
	SET @wagerReqNonWeighted=0;
    SET @wagerReqWeightedBeforeReal=0;
	SET @wagerReqWeighted=0;

    /* -- Used in Type2
	SELECT SUM(wager_requirement_non_weighted) AS wager_requirement_non_weighted, 
		SUM(wager_requirement_contribution_before_real_only) AS wager_requirement_contribution_before_real_only,
		SUM(wager_requirement_contribution) AS wager_requirement_contribution
	INTO @wagerReqNonWeighted, @wagerReqWeightedBeforeReal, @wagerReqWeighted
	FROM gaming_game_plays_sb FORCE INDEX (game_play_id)
	STRAIGHT_JOIN gaming_game_plays_sb_bonuses ON gaming_game_plays_sb_bonuses.game_play_sb_id  = gaming_game_plays_sb.game_play_sb_id
	WHERE gaming_game_plays_sb.game_play_id = gamePlayID;
    */
    
    IF (recalcualteBonusWeight) THEN
	-- updated gaming_sb_bets_bonus_rules
		CALL CommonWalletSportsGenericCalculateBonusRuleWeight(sessionID, clientStatID, sbBetID, numSingles, numMultiples);
	  
		UPDATE 
		(
			SELECT gaming_game_plays_sb.game_play_sb_id, sb_bonuses.bonus_instance_id, 
				@wagerNonWeighted := sb_bonuses.bet_bonus_win_locked+sb_bonuses.bet_real+sb_bonuses.bet_bonus AS wagerNonWeighted,
				@wagerWeighted :=
						ROUND(
							LEAST(
									IFNULL(wgr_restrictions.max_wager_contibution_before_weight, 100000000*100),
									@wagerNonWeighted
								  )*IFNULL(gaming_sb_bets_bonus_rules.weight, 0)*IFNULL(gaming_bonus_rules.sportsbook_weight_mod, 1),

						5),
				IF(@wagerWeighted>=gaming_bonus_instances.bonus_wager_requirement_remain, gaming_bonus_instances.bonus_wager_requirement_remain, @wagerWeighted) AS wager_requirement_contribution_pre,
				@wagerNonWeighted:= IF(gaming_bonus_rules.wager_req_real_only OR bonusReqContributeRealOnly, sb_bonuses.bet_real, sb_bonuses.bet_bonus_win_locked+sb_bonuses.bet_real+sb_bonuses.bet_bonus),
				@wagerWeighted :=IF(gaming_bonus_instances.is_freebet_phase, 0,
						ROUND(
							LEAST(
									IFNULL(wgr_restrictions.max_wager_contibution_before_weight, 100000000*100),
									@wagerNonWeighted
								  )*IFNULL(gaming_sb_bets_bonus_rules.weight, 0)*IFNULL(gaming_bonus_rules.sportsbook_weight_mod, 1),

						5)) AS wager_requirement_contribution           
			FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
			STRAIGHT_JOIN gaming_game_plays_sb_bonuses AS sb_bonuses ON 
				gaming_game_plays_sb.game_play_sb_id=sb_bonuses.game_play_sb_id
			STRAIGHT_JOIN gaming_bonus_instances ON 
				sb_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
			STRAIGHT_JOIN gaming_bonus_rules ON 
				gaming_bonus_rules.bonus_rule_id=gaming_bonus_instances.bonus_rule_id 
			LEFT JOIN  gaming_sb_bets_bonus_rules ON 
				gaming_sb_bets_bonus_rules.sb_bet_id=gaming_game_plays_sb.sb_bet_id AND 
                gaming_sb_bets_bonus_rules.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
			LEFT JOIN gaming_bonus_rules_wager_restrictions AS wgr_restrictions ON 
				gaming_bonus_rules.bonus_rule_id=wgr_restrictions.bonus_rule_id AND 
                wgr_restrictions.currency_id=currencyID
			WHERE gaming_game_plays_sb.sb_bet_id=sbBetID AND 
				-- parition filtering
				(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID) AND
				-- other filtering
				sb_bonuses.wager_requirement_non_weighted > 0
		) AS XX STRAIGHT_JOIN gaming_game_plays_sb_bonuses FORCE INDEX (PRIMARY) ON 
			gaming_game_plays_sb_bonuses.game_play_sb_id=XX.game_play_sb_id AND 
            gaming_game_plays_sb_bonuses.bonus_instance_id=XX.bonus_instance_id
		SET 
			gaming_game_plays_sb_bonuses.wager_requirement_non_weighted=XX.wagerNonWeighted,
			gaming_game_plays_sb_bonuses.wager_requirement_contribution_before_real_only=XX.wager_requirement_contribution_pre, 
			gaming_game_plays_sb_bonuses.wager_requirement_contribution=XX.wager_requirement_contribution;
	END IF;
    
    SET @countWagerReqMet=0;
    SET @countReleaseBonus=0;
    
	INSERT INTO gaming_game_plays_bonus_instances (game_play_id, bonus_instance_id, bonus_rule_id, client_stat_id, timestamp, exchange_rate, bet_real, bet_bonus, bet_bonus_win_locked,
			wager_requirement_non_weighted, wager_requirement_contribution_before_real_only, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus, bonus_wager_requirement_remain_after,bonus_order)
	SELECT game_play_id, bonus_instance_id, bonus_rule_id, clientStatID, NOW(), exchangeRate, bet_real, bet_bonus, bet_bonus_win_locked,
		wager_requirement_non_weighted, wager_requirement_contribution_pre, wager_requirement_contribution, now_wager_requirement_met, now_release_bonus,
		bonus_wager_requirement_remain_after, bonus_order
	FROM (
		SELECT game_play_id, bonus_instance_id, gaming_bonus_instances.bonus_rule_id, clientStatID, exchangeRate,
			gaming_bonus_instances.bet_real, gaming_bonus_instances.bet_ring_fenced, gaming_bonus_instances.bet_bonus, gaming_bonus_instances.bet_bonus_win_locked,
			@tempWagerNonWeighted := IF(bonus_wager_requirement_remain<wager_requirement_non_weighted, bonus_wager_requirement_remain, wager_requirement_non_weighted) AS wager_requirement_non_weighted,
			@wagerReqNonWeighted := GREATEST(0,wager_requirement_non_weighted - @tempWagerNonWeighted),
			@tempWagerReqWeightedBeforeReal := IF(bonus_wager_requirement_remain<wager_requirement_contribution_before_real_only, bonus_wager_requirement_remain, wager_requirement_contribution_before_real_only) AS wager_requirement_contribution_pre,
			@wagerReqWeightedBeforeReal:= GREATEST(0,wager_requirement_contribution_before_real_only-@tempWagerReqWeightedBeforeReal), 
			@tempWagerReqWeighted := IF(bonus_wager_requirement_remain<wager_requirement_contribution, bonus_wager_requirement_remain, wager_requirement_contribution) AS wager_requirement_contribution,
			@wagerReqWeighted := GREATEST(0,wager_requirement_contribution- @tempWagerReqWeighted),
			@nowWagerReqMet:=IF ((bonus_wager_requirement_remain-@tempWagerReqWeighted)=0 AND is_free_bonus=0, 1 ,0) AS now_wager_requirement_met,
			@nowReleaseBonus:=IF (@nowWagerReqMet=0 AND is_release_bonus AND ((bonus_wager_requirement-bonus_wager_requirement_remain)+@wagerReqWeighted)>=((transfer_every_x_last+transfer_every_x_wager)*bonus_amount_given), 1, 0) AS now_release_bonus,
			bonus_wager_requirement_remain-@wagerReqWeighted AS bonus_wager_requirement_remain_after,
			bonus_order,
            @countWagerReqMet:=@countWagerReqMet+IF(@nowWagerReqMet, 1, 0),
            @countReleaseBonus:=@countReleaseBonus+IF(@nowReleaseBonus, 1, 0)
		FROM 
		(
			SELECT BonusTransactions.game_play_id, BonusTransactions.bonus_instance_id, gaming_bonus_instances.bonus_rule_id, gaming_bonus_rules.wager_req_real_only, 
			  BonusTransactions.bet_real, BonusTransactions.bet_ring_fenced, BonusTransactions.bet_bonus, BonusTransactions.bet_bonus_win_locked, gaming_bonus_rules.sportsbook_weight_mod AS license_weight_mod,
			  BonusTransactions.wager_requirement_non_weighted, BonusTransactions.wager_requirement_contribution_before_real_only, BonusTransactions.wager_requirement_contribution,
			  gaming_bonus_instances.bonus_amount_given, gaming_bonus_instances.bonus_wager_requirement, gaming_bonus_instances.bonus_wager_requirement_remain,
			  gaming_bonus_instances.transfer_every_x AS transfer_every_x_wager, gaming_bonus_instances.transfer_every_x_last, IFNULL(transfer_type.name,'') IN ('ReleaseBonus','ReleaseAllBonus') AS is_release_bonus, 
			  IFNULL(gaming_sb_bets_bonuses.bonus_order, 100) AS bonus_order, gaming_bonus_rules.is_free_bonus, gaming_bonus_instances.is_freebet_phase, 0 AS ring_fence_only
			FROM (
				SELECT gaming_game_plays_sb.game_play_id, sb_bonuses.bonus_instance_id,
					SUM(sb_bonuses.bet_real) AS bet_real, SUM(sb_bonuses.bet_bonus) AS bet_bonus, SUM(sb_bonuses.bet_bonus_win_locked) AS bet_bonus_win_locked, SUM(sb_bonuses.bet_ring_fenced) AS bet_ring_fenced,
					SUM(sb_bonuses.wager_requirement_non_weighted) AS wager_requirement_non_weighted, SUM(sb_bonuses.wager_requirement_contribution_before_real_only) AS wager_requirement_contribution_before_real_only,
					SUM(sb_bonuses.wager_requirement_contribution) AS wager_requirement_contribution
				FROM gaming_game_plays_sb FORCE INDEX (sb_bet_id)
				STRAIGHT_JOIN gaming_game_plays_sb_bonuses AS sb_bonuses ON 
					sb_bonuses.game_play_sb_id=gaming_game_plays_sb.game_play_sb_id 
				WHERE gaming_game_plays_sb.sb_bet_id=sbBetID AND 
					-- parition filtering
					(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID) AND
					-- other filtering
                    gaming_game_plays_sb.confirmation_status=2 
				GROUP BY sb_bonuses.bonus_instance_id
			) AS BonusTransactions
			STRAIGHT_JOIN gaming_bonus_instances ON 
				BonusTransactions.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
			STRAIGHT_JOIN gaming_bonus_rules ON 
				gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
			LEFT JOIN gaming_sb_bets_bonuses ON 
				gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND 
                gaming_bonus_instances.bonus_instance_id=gaming_sb_bets_bonuses.bonus_instance_id
			LEFT JOIN gaming_bonus_types_transfers AS transfer_type ON 
				gaming_bonus_rules.bonus_type_transfer_id=transfer_type.bonus_type_transfer_id
			ORDER BY IFNULL(gaming_sb_bets_bonuses.bonus_order, 100), gaming_bonus_instances.priority
		) AS gaming_bonus_instances  
	) AS a;

     IF (ROW_COUNT()>0) THEN
    
		SET maxGamePlayBonusInstanceID=ROW_COUNT()+LAST_INSERT_ID()-1;
		SET minGamePlayBonusInstanceID=maxGamePlayBonusInstanceID-partitioningMinusFromMax;
		
		-- Bonus balance has already been updated but we need to update the bonus_wager_requirement_remain
		UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
		STRAIGHT_JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id=ggpbi.bonus_instance_id
		SET gbi.bonus_wager_requirement_remain=gbi.bonus_wager_requirement_remain-ggpbi.wager_requirement_contribution,
			gbi.is_secured=IF(ggpbi.now_wager_requirement_met=1, 1, gbi.is_secured), gbi.secured_date=IF(ggpbi.now_wager_requirement_met=1,NOW(),NULL),
			gbi.reserved_bonus_funds = gbi.reserved_bonus_funds - (ggpbi.bet_bonus + ggpbi.bet_bonus_win_locked)
			-- -- current_ring_fenced_amount=current_ring_fenced_amount-bet_ring_fenced,
			-- gaming_bonus_instances.open_rounds=gaming_bonus_instances.open_rounds+1
		WHERE ggpbi.game_play_id=gamePlayID
			-- parition filtering
			AND (ggpbi.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID);  
      
        IF (@countWagerReqMet>0) THEN
      
			-- Wagering Requirement Met
			UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
			STRAIGHT_JOIN gaming_bonus_instances ON 
				gaming_bonus_instances.bonus_instance_id=ggpbi.bonus_instance_id
			STRAIGHT_JOIN gaming_bonus_rules ON 
				gaming_bonus_rules.bonus_rule_id=gaming_bonus_instances.bonus_rule_id
			STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON 
				transfer_type.bonus_type_transfer_id=gaming_bonus_rules.bonus_type_transfer_id
			SET 
				ggpbi.bonus_transfered_total=(CASE transfer_type.name
				  WHEN 'All' THEN gaming_bonus_instances.bonus_amount_remaining+gaming_bonus_instances.current_win_locked_amount
				  WHEN 'Bonus' THEN gaming_bonus_instances.bonus_amount_remaining
				  WHEN 'BonusWinLocked' THEN gaming_bonus_instances.current_win_locked_amount
				  WHEN 'UpToBonusAmount' THEN LEAST(gaming_bonus_instances.bonus_amount_given, gaming_bonus_instances.bonus_amount_remaining+gaming_bonus_instances.current_win_locked_amount)
				  WHEN 'UpToPercentage' THEN LEAST(gaming_bonus_instances.bonus_amount_given*gaming_bonus_rules.transfer_upto_percentage, gaming_bonus_instances.bonus_amount_remaining+gaming_bonus_instances.current_win_locked_amount)
				  WHEN 'ReleaseBonus' THEN LEAST(gaming_bonus_instances.bonus_amount_given-gaming_bonus_instances.bonus_transfered_total, 
					gaming_bonus_instances.bonus_amount_remaining+gaming_bonus_instances.current_win_locked_amount)
				  WHEN 'ReleaseAllBonus' THEN gaming_bonus_instances.bonus_amount_remaining+gaming_bonus_instances.current_win_locked_amount
				  ELSE 0
				END),
				ggpbi.bonus_transfered=IF(transfer_type.name='BonusWinLocked', 0, LEAST(ggpbi.bonus_transfered_total, bonus_amount_remaining)),
				ggpbi.bonus_win_locked_transfered=IF(transfer_type.name='Bonus', 0, ggpbi.bonus_transfered_total-ggpbi.bonus_transfered),
				ggpbi.bonus_transfered_lost=bonus_amount_remaining-ggpbi.bonus_transfered,
				ggpbi.bonus_win_locked_transfered_lost=current_win_locked_amount-bonus_win_locked_transfered,
				bonus_amount_remaining=0,
				current_win_locked_amount=0, 
				current_ring_fenced_amount=0,  
				gaming_bonus_instances.bonus_transfered_total=gaming_bonus_instances.bonus_transfered_total+ggpbi.bonus_transfered_total,
				gaming_bonus_instances.session_id=sessionID
			WHERE ggpbi.game_play_id=gamePlayID AND
				-- parition filtering
				-- (ggpbi.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID) AND 
				-- other filtering
				(ggpbi.now_wager_requirement_met=1 AND ggpbi.now_used_all=0);
		  
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
			WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND 
				-- parition filtering
				-- (gaming_game_plays_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID) AND 
				-- other filtering
				(now_wager_requirement_met=1 AND now_used_all=0);
			
			SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
			SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;
			IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
			  CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusRequirementMet', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
			END IF; 
		END IF;
        
        -- Slow Release
        IF (@countReleaseBonus>0) THEN
			UPDATE gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (game_play_id)
			STRAIGHT_JOIN gaming_bonus_instances ON 
				gaming_bonus_instances.bonus_instance_id=ggpbi.bonus_instance_id
			STRAIGHT_JOIN gaming_bonus_rules ON 
				gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
			STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON 
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
			WHERE ggpbi.game_play_id=gamePlayID AND 
				-- parition filtering
				-- (ggpbi.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID) AND
				-- other filtering
				(ggpbi.now_release_bonus=1 AND ggpbi.now_used_all=0 AND ggpbi.now_wager_requirement_met=0);
				
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
			WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND 
				-- parition filtering
				-- (gaming_game_plays_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID) AND 
				-- other filtering
				(now_release_bonus=1 AND now_used_all=0 AND now_wager_requirement_met=0);

			SET @bonusTransferedTotal=ROUND(@bonusTransfered+@bonusWinLockedTransfered,0);
			SET @bonusTransferedLostTotal=@bonusTransferedLost+@bonusWinLockedTransferedLost;
			IF (@requireTransfer=1 AND (@bonusTransferedTotal>0 OR @bonusTransferedLostTotal>0)) THEN
			  CALL PlaceBetBonusCashExchange(clientStatID, gamePlayID, sessionID, 'BonusCashExchange', exchangeRate, @bonusTransferedTotal, @bonusTransfered, @bonusWinLockedTransfered, @bonusTransferedLost, @bonusWinLockedTransferedLost,NULL,@ringFencedAmount,@ringFencedAmountSB,@ringFencedAmountCasino,@ringFencedAmountPoker,NULL);
			END IF; 
		END IF;

      END IF; 

  END IF; 

  -- If the bonus is secured than it is no longer active
  UPDATE gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
  STRAIGHT_JOIN gaming_bonus_instances ON 
	gaming_bonus_instances.bonus_instance_id=gaming_game_plays_bonus_instances.bonus_instance_id
  SET 
	gaming_bonus_instances.is_active=IF(is_active=0, 0, IF(is_secured,0,1))
  WHERE gaming_game_plays_bonus_instances.game_play_id=gamePlayID AND
	-- parition filtering
	gaming_game_plays_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID;
    
  UPDATE gaming_sb_bets 
  SET bet_total=bet_total-betAmount, is_processed=1, is_success=1, status_code=5
  WHERE sb_bet_id=sbBetID;

  UPDATE gaming_sb_bets_partition_fields
  SET 
    max_game_play_bonus_instance_id=maxGamePlayBonusInstanceID
  WHERE sb_bet_id=sbBetID;

	IF (isCouponBet) THEN
		
        SELECT game_round_id INTO gameRoundID FROM gaming_game_plays WHERE game_play_id = gamePlayID;
		CALL PlayReturnDataWithoutGame(gamePlayID, gameRoundID, clientStatID, gameManufacturerID, minimalData);
		CALL PlayReturnBonusInfoOnWin(gamePlayID);
	
    ELSE
	
    IF (select value_bool from gaming_settings where name='RULE_ENGINE_ENABLED')=1 THEN
        INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 1, gamePlayID;
    END IF;
    
		CALL CommonWalletSBReturnData(sbBetID, clientStatID, gamePlayID, minimalData);
	
    END IF;

  CALL NotificationEventCreate(700, sbBetID, clientStatID, 0);
  
  SET statusCode=0;
END root$$

DELIMITER ;

