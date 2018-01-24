DROP procedure IF EXISTS `PlaceSBWinGenericType2`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlaceSBWinGenericType2`(
  clientStatID BIGINT, betGamePlayID BIGINT, betGamePlaySBID BIGINT, winAmount DECIMAL(18, 5), closeRound TINYINT(1), 
  OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root: BEGIN
  
  -- Bad Dept and Negative win amount
  -- Minor bug fixing   
  -- Duplicate transaction with bad dept
  -- Fixed when betting only from real money with no bonuses
  -- Storing GamePlayID of original transaction in bad debt transaction as extra_id
  -- Sports Book v2
  -- SportsAdjustment message type
  -- Fixed by joining to gaming_game_plays_sb_bonuses AS play_bonus_instances ON play_bonus_instances.game_play_sb_id=gaming_game_plays_sb.game_play_sb_id
  -- Forced indices
  -- Moved queries to PlaceTransactionOffsetNegativeBalancePreComputred  
  -- Type 2 version
  -- Variable based top bonus (for bonuses forfeited in progress)
  -- Debit implementation
  -- Fixed debit without bonuses
  -- Optimized for Parititioning 
  
  #region
  DECLARE betAmount, exchangeRate DECIMAL(18, 5) DEFAULT 0;
  DECLARE winTotalBase, winReal, winBonus, winBonusWinLocked, winFreeBet, winFreeBetWinLocked, roundBetTotal, roundWinTotal, 
		  betReal, betBonus, betBonusWinLocked, betBonusLost, betBonusTotal, betTotal, FreeBonusAmount, amountTaxPlayer, 
		  amountTaxOperator, taxBet, taxWin, roundWinTotalFullReal, taxAlreadyChargedOperator, 
          taxAlreadyChargedPlayer, taxModificationOperator, taxModificationPlayer, roundBetTotalReal, 
		  roundWinTotalReal, taxOnReturn, taxAmount, roundWinTotalFull DECIMAL(18, 5) DEFAULT 0;
  DECLARE roundWinBonusAlready, roundWinBonusWinLockedAlready, roundWinTotalFullBonus, roundBetTotalBonus DECIMAL(18, 5) DEFAULT 0;
  DECLARE gameRoundID, sessionID, gameManufacturerID, clientStatIDCheck, clientID, currencyID, gamePlayID, 
		  betGamePlayID, gamePlayWinCounterID, betGamePlayIDCheck, sbBetID, betMessageTypeID, betSBExtraID, 
          countryID, countryTaxID, badDeptGamePlayID, badDeptTransactionID BIGINT DEFAULT -1;
  DECLARE dateTimeWin DATETIME DEFAULT NULL;
  DECLARE bonusEnabledFlag, playLimitEnabled, isRoundFinished, updateGamePlayBonusInstanceWin, applyNetDeduction, winTaxPaidByOperator, taxEnabled, 
          isSBSingle, allowNegativeBalance, disallowNegativeBalance, addWagerContributionWithRealBet, isNonWageringCurrent, hasPreviousWinTrans TINYINT(1) DEFAULT 0;
  DECLARE numTransactions, singleMultTypeID INT DEFAULT 0;
  DECLARE licenseType, taxAppliedOnType VARCHAR(20) DEFAULT NULL;
  DECLARE clientWagerTypeID INT DEFAULT 3; 
  DECLARE licenseTypeID TINYINT(4) DEFAULT 3; 
  DECLARE currentRealBalance, badDebtRealAmount DECIMAL(18, 5) DEFAULT 0;
  DECLARE taxCycleID INT DEFAULT NULL;
  #endregion

  /* Type 2 vars */
  DECLARE retType VARCHAR(80);
  DECLARE topBonusInstanceID, gamePlayBetCounterID BIGINT DEFAULT -1;
  DECLARE topBonusApplicable, dominantNoLoyaltyPoints, wagerReqRealOnly TINYINT(1) DEFAULT 0;
  DECLARE bonusRetLostTotal, bonusRetRemainTotal, bonusWagerRequirementRemain, 
          betFromReal, availableBonus, availableBonusWinLocked, availableFreeBet,
          debitReal, debitBonus, debitBonusWinLocked, loyaltyDebitBonus, debitAmountRemain DECIMAL(18,5);
  DECLARE bonusCount, numBonusInstances INT;  
  DECLARE currentBonusAmount, currentRealAmount, currentWinLockedAmount DECIMAL(18,5) DEFAULT 0; 
  DECLARE bonusesUsedAllWhenZero, playerHasActiveBonuses TINYINT(1) DEFAULT 0;
  
  DECLARE ringFencedEnabled TINYINT(4) DEFAULT 1;

  DECLARE partitioningMinusFromMax INT DEFAULT 10000;
  DECLARE minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, 
	minSbBetMultipleSingleID, maxSbBetMultipleSingleID, minGameRoundID, maxGameRoundID, 
    minGamePlaySBID, maxGamePlaySBID, minGamePlayBonusInstanceID, maxGamePlayBonusInstanceID BIGINT DEFAULT NULL;

  -- Irrelevant for now
  #region
  SET gamePlayIDReturned=NULL;
  SET licenseType='sportsbook';
  
 
  -- Get the settings      

  SELECT 
    gs1.value_bool AS vb1, gs2.value_bool AS vb2, IFNULL(gs3.value_bool, 0) AS vb3, IFNULL(gs4.value_bool, 0) AS vb4, 
    IFNULL(gs5.value_bool,0) AS vb5, IFNULL(gs6.value_bool,0) AS vb6, IFNULL(gs7.value_bool, 0) AS vb7
  INTO 
    playLimitEnabled, bonusEnabledFlag, taxEnabled, disallowNegativeBalance, 
    ringFencedEnabled, bonusesUsedAllWhenZero, addWagerContributionWithRealBet
  FROM gaming_settings gs1 
  STRAIGHT_JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
  LEFT JOIN gaming_settings gs3 ON (gs3.name='TAX_ON_GAMEPLAY_ENABLED')
  LEFT JOIN gaming_settings gs4 ON (gs4.name='WAGER_DISALLOW_NEGATIVE_BALANCE')
  LEFT JOIN gaming_settings gs5 ON (gs5.name='RING_FENCED_ENABLED')
  LEFT JOIN gaming_settings gs6 ON (gs6.name='TYPE_TWO_BONUSES_USED_ALL_WHEN_ZERO')
  LEFT JOIN gaming_settings gs7 ON (gs7.name='ADD_WAGER_CONTRIBUTION_WITH_REAL_BET')
  WHERE gs1.name='PLAY_LIMIT_ENABLED';
             
 
  -- Lock the player     

  SELECT client_stat_id, client_id, gaming_client_stats.currency_id, current_real_balance, bet_from_real 
  INTO clientStatIDCheck, clientID, currencyID, currentRealBalance, betFromReal
  FROM gaming_client_stats 
  WHERE client_stat_id=clientStatID
  FOR UPDATE;

  -- Get other player details   
  SELECT country_id INTO countryID FROM clients_locations WHERE clients_locations.client_id=clientID AND clients_locations.is_primary=1; 
  SELECT session_id INTO sessionID FROM sessions_main FORCE INDEX (client_latest_session) WHERE extra_id=clientID AND is_latest;           
  
  -- Get current exchange rate  
  SELECT exchange_rate INTO exchangeRate FROM gaming_operator_currency WHERE gaming_operator_currency.currency_id=currencyID;   
    
  -- Return if player is not found      
  IF (clientStatIDCheck=-1) THEN 
    SET statusCode = 1;
    LEAVE root;
  END IF;               
  
  -- Insert the multiple type if doesn't exist (should be very rare, ideally never)  
  SELECT sb_multiple_type_id INTO singleMultTypeID FROM gaming_sb_multiple_types WHERE name='Single' AND game_manufacturer_id=gameManufacturerID;   

  #endregion


  -- Get the bet/wager transaction information                
  SELECT
    sb_bet_id,
    game_play_id, -- Add - get game play ID, used to retrieve bet bonus instances later
    sb_bet_entry_id,
    game_round_id,
    game_manufacturer_id,
    amount_total,
    0,
    amount_real,
    /**
    * Get amount bonus that funds bet
    */
    amount_bonus - amount_bonus_win_locked_component,
    amount_bonus_win_locked_component,
    sb_multiple_type_id = singleMultTypeID
  INTO sbBetID, betGamePlayID, betSBExtraID, gameRoundID, gameManufacturerID, betTotal, betBonusLost, betReal, betBonus, betBonusWinLocked, isSBSingle
  FROM gaming_game_plays_sb FORCE INDEX (PRIMARY)
  WHERE game_play_sb_id = betGamePlaySBID AND payment_transaction_type_id IN (12, 45)
  ORDER BY game_play_sb_id DESC
  LIMIT 1;
    
  -- Get the round information 
  SELECT num_transactions, bet_total, win_total, is_round_finished, amount_tax_operator, amount_tax_player, bet_real, win_real, win_bonus, win_bonus_win_locked
  INTO numTransactions, roundBetTotal, roundWinTotal, isRoundFinished, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, 
	   roundBetTotalReal, roundWinTotalReal, roundWinBonusAlready, roundWinBonusWinLockedAlready
  FROM gaming_game_rounds FORCE INDEX (PRIMARY)
  WHERE game_round_id=gameRoundID;  
   
  #region
  -- Sanity check       
  IF (sbBetID=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;              
  #endregion
  
  SELECT 
    gsbpf.max_sb_bet_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_single_id, 
    gsbpf.max_sb_bet_multiple_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_id,
    gsbpf.max_sb_bet_multiple_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_single_id,
    gsbpf.min_game_round_id, gsbpf.max_game_round_id, 
    gsbpf.min_game_play_sb_id, gsbpf.max_game_play_sb_id,
    gsbpf.max_game_play_bonus_instance_id-partitioningMinusFromMax, gsbpf.max_game_play_bonus_instance_id
  INTO 
    minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, minSbBetMultipleSingleID, maxSbBetMultipleSingleID,
    minGameRoundID, maxGameRoundID, minGamePlaySBID, maxGamePlaySBID, minGamePlayBonusInstanceID, maxGamePlayBonusInstanceID
  FROM gaming_sb_bets AS gsb
  LEFT JOIN gaming_sb_bets_partition_fields AS gsbpf ON gsbpf.sb_bet_id=gsb.sb_bet_id
  WHERE gsb.sb_bet_id=sbBetID;

--                                                                                          
--   ____   ___  _   _ _   _ ____            _____  _   __  __  ____ _____  _    ____ _____ 
--  | __ ) / _ \| \ | | | | / ___|     _    |_   _|/ \  \ \/ / / ___|_   _|/ \  |  _ |_   _|
--  |  _ \| | | |  \| | | | \___ \   _| |_    | | / _ \  \  /  \___ \ | | / _ \ | |_) || |  
--  | |_) | |_| | |\  | |_| |___) | |_   _|   | |/ ___ \ /  \   ___) || |/ ___ \|  _ < | |  
--  |____/ \___/|_| \_|\___/|____/    |_|     |_/_/   \_/_/\_\ |____/ |_/_/   \_|_| \_\|_|  
--  ======================================================================================================
  #region
  
  -- Default Values
  #region
  
  -- Type 1 & 2 shared
  SET winReal=ABS(winAmount);
  SET winBonus=0; 
  SET winBonusWinLocked=0;   
  SET @winBonusLost=0.0; 
  SET @winBonusWinLocked=0.0;
  SET @winBonusWinLockedLost=0.0; 
  /* Not used right now */ 
  SET @updateBonusInstancesWins=0;  

  -- Not sure if Type 1 specific
  SET FreeBonusAmount=0;

  -- Type 2 specific
  SET @UpdateRealAmount = 0.0;
  SET @winBonusTemp=0.0;
  SET @winBonusCurrent=0.0;                     
  SET @winBonusLostCurrent=0.0;
  SET @winBonusWinLockedLostCurrent=0.0;                
  SET @winRealBonusCurrent=0.0;
  SET @winRealBonusWLCurrent=0.0;  
  SET @winReal=0.0;
  SET @winBonus=0.0;
  SET @isBonusSecured=0;
  SET @isFreeBonusWin=0;
 
  #endregion

  /* insert win counter */
  INSERT INTO gaming_game_plays_win_counter (date_created, game_round_id) VALUES (NOW(), gameRoundID);
  SET gamePlayWinCounterID=LAST_INSERT_ID();

  -- If bonuses enabled OR any bonus used to fund bet
  IF (bonusEnabledFlag) THEN 
    -- This is slightly different from the Lotto - there we wouldn't have the if-statement. This could however improve performance if bonuses are not involved
    
    
    IF (winAmount >= 0) THEN
    
        #region Win
        
        /**
         * Credit - won something        
         */

        /**
         * GET TOP BONUS USED TO FUND THE BET
         */
        SELECT gaming_game_plays_bonus_instances.bonus_instance_id, gaming_bonus_types_bet_returns.name
            INTO topBonusInstanceID, retType
        FROM gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
          STRAIGHT_JOIN gaming_bonus_instances ON 
			gaming_bonus_instances.bonus_instance_id = gaming_game_plays_bonus_instances.bonus_instance_id
          STRAIGHT_JOIN gaming_bonus_rules ON 
			gaming_bonus_rules.bonus_rule_id = gaming_bonus_instances.bonus_rule_id
          STRAIGHT_JOIN gaming_bonus_types_bet_returns ON 
			gaming_bonus_types_bet_returns.bonus_type_bet_return_id = gaming_bonus_rules.bonus_type_bet_return_id
		WHERE gaming_game_plays_bonus_instances.game_play_id = betGamePlayID AND gaming_game_plays_bonus_instances.bonus_order = 1 AND
			-- parition filtering
			(gaming_game_plays_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID) 
		LIMIT 1;
        
        /**
         * Get bonus totals for the bet
         * if retType is Loss then we must deduct the full bonus amount, spent for that win
         * but because we can have multiple win call we need to deduct it only once at first win
         * so we will keep this already deducted amount in the field "bonus_transfered_lost"
         * which should be always NULL or 0 in our case 
         */
        SELECT
            SUM(bet_bonus), SUM(bet_bonus - IFNULL(bonus_transfered_lost, 0)), SUM(bet_bonus - IFNULL(win_bonus, 0)), 
            MAX(IF(is_active AND bonus_wager_requirement = 0 AND bonus_amount_remaining = 0 AND bet_bonus > 0, 1, 0)), COUNT(*)
        INTO 
            betBonusTotal, bonusRetLostTotal, bonusRetRemainTotal,
            isNonWageringCurrent, bonusCount
        FROM gaming_game_plays_bonus_instances FORCE INDEX (game_play_id)
        STRAIGHT_JOIN gaming_bonus_instances 
            ON gaming_game_plays_bonus_instances.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
        WHERE gaming_game_plays_bonus_instances.game_play_id = betGamePlayID AND
			-- parition filtering
			(gaming_game_plays_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID);
    
        IF ( topBonusInstanceID != -1 ) THEN
          
            SET @updateBonusInstancesWins = 1;
          
            IF ( retType = 'Loss' ) THEN
                SET @winAmountTemp = winAmount - bonusRetLostTotal;
                IF (@winAmountTemp < 0) THEN
                    SET @winAmountTemp = 0;
                    SET bonusRetLostTotal = winAmount;
                END IF;
            ELSE
                SET @winAmountTemp = winAmount;
                SET bonusRetLostTotal = 0;
            END IF;
          
            SET @bonusOrder = bonusCount + 1;
            SET @topBonusNo = 1; 

          SELECT 
            play_bonus_instances.bonus_order INTO @topBonusNo
		  FROM gaming_game_plays_bonus_instances AS play_bonus_instances FORCE INDEX (game_play_id)
		  STRAIGHT_JOIN gaming_bonus_instances ON 
			play_bonus_instances.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
		  STRAIGHT_JOIN gaming_bonus_rules ON 
			gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
		  STRAIGHT_JOIN gaming_bonus_types_bet_returns AS bet_returns_type ON 
			gaming_bonus_rules.bonus_type_bet_return_id = bet_returns_type.bonus_type_bet_return_id
		  STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer_type ON 
			gaming_bonus_rules.bonus_type_transfer_id = transfer_type.bonus_type_transfer_id
		  WHERE play_bonus_instances.game_play_id = betGamePlayID AND is_lost = 0 AND
			-- parition filtering
			(play_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID)
	      GROUP BY gaming_bonus_instances.bonus_instance_id
		  ORDER BY IF(bonus_type_awarding_id=2 /* FreeBet */, 1, 0) DESC, is_freebet_phase DESC, gaming_bonus_instances.given_date ASC, gaming_bonus_instances.bonus_instance_id ASC 
          LIMIT 1;         

            INSERT INTO gaming_game_plays_bonus_instances_wins (
                game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, 
                bonus_rule_id, `timestamp`, exchange_rate, win_real, win_bonus, win_bonus_win_locked, 
                lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, win_game_play_id, add_wager_contribution, bonus_order
            )
            SELECT 
                gamePlayWinCounterID, game_play_bonus_instance_id, bonus_instance_id, 
                bonus_rule_id, NOW(), exchangeRate, win_real, win_bonus, win_bonus_win_locked,
                lost_win_bonus, lost_win_bonus_win_locked, clientStatID, NULL, 0, bonusOrder
            FROM
            (
                SELECT
                    -- Index of the bonus
                    @bonusOrder := @bonusOrder - 1 AS bonusOrder,
                    -- Bonus secured flag
                    @isBonusSecured := IF( is_secured, 1, @isBonusSecured ),    
                    game_play_bonus_instance_id, 
                    bonus_instance_id, 
                    bonus_rule_id,
                    -- Temp holder for bonus win
                    @winBonusTemp := ROUND(
                        LEAST( @winAmountTemp, 
                                IF( is_free_bonus = 1, 
                                    IF (@winBonus + bet_bonus < betBonusTotal AND NOT isNonWageringCurrent, -- this is not the current freebet bonus - just top up the bonus amount
                                        bonus_amount_given - bonus_amount_remaining, 
                                        IF(bet_return_type = 'Bonus', LEAST( @winAmountTemp, bonusRetRemainTotal ), 0 ) -- if this is the current bonus - return the bet in the bonus amount when required
                                    ),
                                    GREATEST(0, IF(isNonWageringCurrent, 0, bonus_amount_given - bonus_transfered_total - bonus_amount_remaining )) -- top up the standard bonus, but only if the current bonus has a wagering requirement  
                                )
                        ), 0),              
                    -- Bonus win for this bonus
                    @winBonusCurrent := IF( is_secured = 0 AND is_lost = 0, @winBonusTemp, 0) AS win_bonus,
                    -- If current bonus was secured, set win real from bonus
                    @winRealBonusCurrent := IF( is_secured = 1 AND is_lost = 0 AND is_free_bonus = 0, -- amount to win in real
                        @winBonusTemp,
                        @winRealBonusCurrent
                    ),
                    -- Loop current value, deduct already assigned bonus amount
                    @winAmountTemp := @winAmountTemp - @winBonusCurrent,
                    -- Top-up real if this is top bonus or current free bet bonus 
                    @UpdateRealAmount := IF(is_free_bonus = 1,
                        IF(@winBonus + bet_bonus = betBonusTotal OR isNonWageringCurrent, @winAmountTemp, 0), -- this is the current freebet bonus - win goes to real
                        IF( bonus_order = @topBonusNo, 
                            LEAST(@winAmountTemp, IF( is_lost = 1, bet_from_real, betFromReal )), 
                            0
                        )
                    ),
                    /* Free Bonus Win flag */
                    @isFreeBonusWin := IF( is_free_bonus = 1 AND @UpdateRealAmount > 0, 1, @isFreeBonusWin ),    
                    /* Loop current value, deduct already assigned real amount */
                    @winAmountTemp := @winAmountTemp - @UpdateRealAmount,
                     /* Put what we have so far in Winnings locked */
                    @winRealBonusWLCurrent := IF( bonus_order = @topBonusNo AND is_lost = 0 ,
                        @winAmountTemp,
                        0
                    ) AS win_bonus_win_locked,
                    /* Loop current value, deduct already assigned BWL amount */
                    @winAmountTemp := @winAmountTemp - @winRealBonusWLCurrent,
                    /* Current lost bonus */
                    @winBonusLostCurrent := ROUND(
                        IF( is_secured = 0 AND is_lost = 1 ,
                            @winBonusTemp,
                            0
                        ), 0 ) AS lost_win_bonus,
                    /* Bonus lost win locked amount */
                    @winBonusWinLockedLostCurrent := ROUND(
                        IF( is_secured = 0 AND is_lost = 1 , 
                            @winRealBonusWLCurrent,  
                            0
                        ), 0) AS lost_win_bonus_win_locked,
                    /* Transfer to real current win bonus or Free bonus winnings */
                    @winRealBonusCurrent := IF( is_secured = 1 AND is_free_bonus = 0 AND bonus_order = @topBonusNo , 
                        CASE gg.transfer_type
                            /* Types of bonus transfer logic */
                            WHEN 'All' THEN @winRealBonusWLCurrent + @winRealBonusCurrent - @winBonusLostCurrent - @winBonusWinLockedLostCurrent
                            WHEN 'NonReedemableBonus' THEN @winRealBonusWLCurrent - @winBonusWinLockedLostCurrent
                            WHEN 'Bonus' THEN @winRealBonusCurrent- @winBonusLostCurrent
                            WHEN 'BonusWinLocked' THEN @winRealBonusWLCurrent- @winBonusWinLockedLostCurrent
                            WHEN 'UpToBonusAmount' THEN GREATEST(0, LEAST(bonus_amount_given-bonus_transfered_total, @winRealBonusWLCurrent + @winRealBonusCurrent- @winBonusLostCurrent - @winBonusWinLockedLostCurrent))
                            WHEN 'UpToPercentage' THEN GREATEST(0, LEAST((bonus_amount_given*transfer_upto_percentage)-bonus_transfered_total, @winRealBonusWLCurrent + @winRealBonusCurrent- @winBonusLostCurrent - @winBonusWinLockedLostCurrent))
                            WHEN 'ReleaseBonus' THEN GREATEST(0, LEAST(bonus_amount_given-bonus_transfered_total, @winRealBonusWLCurrent + @winRealBonusCurrent- @winBonusLostCurrent - @winBonusWinLockedLostCurrent))
                            WHEN 'ReleaseAllBonus' THEN @winBonusAllTemp
                            ELSE 0
                        END,
                        IF( is_free_bonus = 1, @UpdateRealAmount, 0)
                    ) AS win_real,
    
                    @winBonus := @winBonus + @winBonusCurrent,
                    @winBonusWinLocked := @winBonusWinLocked + @winRealBonusWLCurrent,
                    @winBonusLost := @winBonusLost + @winBonusLostCurrent,
                    @winBonusWinLockedLost := @winBonusWinLockedLost + @winBonusWinLockedLostCurrent,
                    @winReal := @winReal + @UpdateRealAmount,          
    
                    bonus_amount_remaining, 
                    current_win_locked_amount
                FROM (
                    SELECT 
                        gaming_bonus_instances.bonus_amount_remaining,
                        gaming_bonus_instances.current_win_locked_amount,
                        SUM(bet_bonus_win_locked) AS bet_bonus_win_locked,
                        gaming_bonus_instances.is_secured,
                        gaming_bonus_instances.bonus_amount_given,
                        gaming_bonus_instances.bonus_transfered_total,
                        SUM(bet_bonus) AS bet_bonus,
                        gaming_bonus_instances.is_lost AS is_lost,
                        bonus_order,
                        gaming_bonus_rules.transfer_upto_percentage,
                        transfer.`name` AS transfer_type,
                        bet_returns_type.`name` AS bet_return_type,
                        game_play_bonus_instance_id,
                        gaming_bonus_instances.bonus_instance_id,
                        gaming_bonus_instances.bonus_rule_id,
                        gaming_bonus_instances.bet_from_real,
                        gaming_bonus_rules.is_free_bonus OR gaming_bonus_instances.is_freebet_phase AS is_free_bonus,
                        play_bonus_instances.bet_real
                    FROM gaming_game_plays_bonus_instances AS play_bonus_instances FORCE INDEX (game_play_id)
                    STRAIGHT_JOIN gaming_bonus_instances ON play_bonus_instances.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
                    STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
                    STRAIGHT_JOIN gaming_bonus_types_bet_returns AS bet_returns_type ON gaming_bonus_rules.bonus_type_bet_return_id = bet_returns_type.bonus_type_bet_return_id
                    STRAIGHT_JOIN gaming_bonus_types_transfers AS transfer ON gaming_bonus_rules.bonus_type_transfer_id = transfer.bonus_type_transfer_id
                    WHERE play_bonus_instances.game_play_id = betGamePlayID AND /* changed to bet gameplay ID */
							-- parition filtering
							(play_bonus_instances.game_play_bonus_instance_id BETWEEN minGamePlayBonusInstanceID AND maxGamePlayBonusInstanceID) 
    					GROUP BY gaming_bonus_instances.bonus_instance_id
                    ORDER BY IF(bonus_type_awarding_id=2 /* FreeBet */, 1, 0) ASC, is_freebet_phase ASC, gaming_bonus_instances.given_date DESC, gaming_bonus_instances.bonus_instance_id DESC
                ) AS gg
            ) AS XX ON DUPLICATE KEY UPDATE 
                bonus_instance_id=VALUES(bonus_instance_id), win_real=VALUES(win_real), 
                win_bonus=VALUES(win_bonus), win_bonus_win_locked=VALUES(win_bonus_win_locked), 
                lost_win_bonus=VALUES(lost_win_bonus), lost_win_bonus_win_locked=VALUES(lost_win_bonus_win_locked), 
                client_stat_id=VALUES(client_stat_id);                       

            UPDATE gaming_game_plays_bonus_instances_wins AS ggpbiw FORCE INDEX (PRIMARY)
            STRAIGHT_JOIN gaming_game_plays_bonus_instances AS ggpbi FORCE INDEX (PRIMARY) 
                ON ggpbiw.game_play_win_counter_id=gamePlayWinCounterID AND 
                ggpbi.game_play_bonus_instance_id=ggpbiw.game_play_bonus_instance_id 
            STRAIGHT_JOIN gaming_bonus_instances AS gbi ON ggpbi.bonus_instance_id=gbi.bonus_instance_id
            SET
                ggpbi.win_bonus=IFNULL(ggpbi.win_bonus,0) + ggpbiw.win_bonus - ggpbiw.lost_win_bonus, 
                ggpbi.win_bonus_win_locked=IFNULL(ggpbi.win_bonus_win_locked,0) + ggpbiw.win_bonus_win_locked - ggpbiw.lost_win_bonus_win_locked, 
                ggpbi.win_real = IFNULL(ggpbi.win_real,0) + ggpbiw.win_real,
                ggpbi.lost_win_bonus=IFNULL(ggpbi.lost_win_bonus,0) + ggpbiw.lost_win_bonus,
                ggpbi.lost_win_bonus_win_locked=IFNULL(ggpbi.lost_win_bonus_win_locked,0) + ggpbiw.lost_win_bonus_win_locked,
                ggpbi.bonus_transfered_lost = IFNULL(ggpbi.bonus_transfered_lost, 0) + bonusRetLostTotal,
                ggpbi.now_used_all=IF(ROUND(gbi.bonus_amount_remaining+gbi.current_win_locked_amount+ggpbiw.win_bonus+ggpbiw.win_bonus_win_locked,5)=0, 1, 0);
                                    
            SET winReal=IFNULL(@winReal,0);                
            SET winBonus=IFNULL(@winBonus,0)-IFNULL(@winBonusLost,0);            
            SET winBonusWinLocked = IFNULL(@winBonusWinLocked,0) - IFNULL(@winBonusWinLockedLost,0);
      
            UPDATE 
			(
				SELECT play_bonus.bonus_instance_id, SUM(play_bonus_wins.win_real) AS win_real, SUM(play_bonus_wins.win_bonus-play_bonus_wins.lost_win_bonus) AS win_bonus, 
					SUM(play_bonus_wins.win_bonus_win_locked - play_bonus_wins.lost_win_bonus_win_locked) AS win_bonus_win_locked, MIN(play_bonus.now_used_all) AS now_used_all
				FROM gaming_game_plays_bonus_instances_wins AS play_bonus_wins FORCE INDEX (PRIMARY)
				STRAIGHT_JOIN gaming_game_plays_bonus_instances AS play_bonus FORCE INDEX (PRIMARY) ON play_bonus_wins.game_play_win_counter_id=gamePlayWinCounterID AND 
					play_bonus_wins.game_play_bonus_instance_id=play_bonus.game_play_bonus_instance_id 
				GROUP BY play_bonus.bonus_instance_id
			) AS PB
			STRAIGHT_JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id = PB.bonus_instance_id
			STRAIGHT_JOIN gaming_bonus_rules AS gbr ON gbr.bonus_rule_id = gbi.bonus_rule_id
			SET 
				gbi.bonus_amount_remaining = gbi.bonus_amount_remaining + IFNULL(PB.win_bonus,0),
				gbi.current_win_locked_amount = gbi.current_win_locked_amount + IFNULL(PB.win_bonus_win_locked,0),
				gbi.total_amount_won = gbi.total_amount_won + IFNULL(PB.win_bonus,0) + IFNULL(PB.win_bonus_win_locked,0),
				gbi.bonus_transfered_total = gbi.bonus_transfered_total + IFNULL(PB.win_real,0),
				gbi.is_used_all = IF(gbi.is_active=1 AND PB.now_used_all>0 AND (gbr.is_free_bonus OR gbi.is_freebet_phase), 1, 0),
                gbi.used_all_date = IF(gbi.is_active=1 AND PB.now_used_all>0 AND (gbr.is_free_bonus OR gbi.is_freebet_phase) AND gbi.used_all_date IS NULL, NOW(), gbi.used_all_date),
				gbi.is_active = IF(gbi.is_active=1 AND PB.now_used_all>0 AND (gbr.is_free_bonus OR gbi.is_freebet_phase), 0, gbi.is_active);

			IF (@winBonusLost+@winBonusWinLockedLost>0) THEN
				INSERT INTO gaming_bonus_losts (bonus_instance_id, client_stat_id, bonus_lost_type_id, bonus_amount, bonus_win_locked_amount, extra_id, date_time_lost, session_id)
				SELECT bonus_instance_id, client_stat_id, gaming_bonus_lost_types.bonus_lost_type_id, IFNULL(SUM(lost_win_bonus),0), IFNULL(SUM(lost_win_bonus_win_locked),0), gamePlayWinCounterID, NOW(), sessionID
				FROM gaming_game_plays_bonus_instances_wins AS play_bonus_wins FORCE INDEX (PRIMARY) 
				STRAIGHT_JOIN gaming_bonus_lost_types ON play_bonus_wins.game_play_win_counter_id=gamePlayWinCounterID AND 
					(play_bonus_wins.lost_win_bonus!=0 OR play_bonus_wins.lost_win_bonus_win_locked!=0) 
				WHERE gaming_bonus_lost_types.name='WinAfterLost'
				GROUP BY play_bonus_wins.bonus_instance_id;  
			END IF;
            
        ELSE 

            SET winReal = winAmount;
            SET winBonus = 0;  
            SET winBonusWinLocked = 0; 

        END IF; 

        #endregion
        
    ELSE
    
        #region Debit
        
        /**
         * Debit - charge player funds
         *
         */
        
        /**
         * Get available bonus balances
         */      
        SELECT 
            COUNT(*), 
            IFNULL(SUM(IF(gbta.name='Bonus', gbi.bonus_amount_remaining, 0)),0) AS current_bonus_balance, 
            IFNULL(SUM(gbi.current_win_locked_amount),0) AS current_bonus_win_locked_balance,
            IFNULL(SUM(IF(gbta.name='FreeBet', gbi.bonus_amount_remaining, 0)),0) AS freebet_balance
        INTO 
            numBonusInstances, availableBonus, availableBonusWinLocked, availableFreeBet
        FROM gaming_bonus_instances AS gbi      
        JOIN gaming_bonus_rules AS gbr ON gbi.bonus_rule_id=gbr.bonus_rule_id
        JOIN gaming_bonus_types_awarding AS gbta ON gbr.bonus_type_awarding_id=gbta.bonus_type_awarding_id
        JOIN gaming_bonus_types ON gbr.bonus_type_id=gaming_bonus_types.bonus_type_id
        WHERE gbi.client_stat_id=clientStatID AND gbi.is_active=1;

        SET @debitRemain = ABS(winAmount);
        SET debitAmountRemain = ABS(winAmount);
        SET @bonusCounter = 0;
        SET @debitReal = 0.0;
        SET @debitBonus = availableBonus;
        SET @debitBonusWinLocked = availableBonusWinLocked;
        SET @freeBetBonus = 0.0;
        SET @freeBonusAmount = 0.0;
        SET @topBonusInstance = -1;        

        /* get a gameplay ID for the bonus_pre table */
        INSERT INTO gaming_game_plays_bet_counter (date_created, client_stat_id) VALUES (NOW(), clientStatID);
        SET gamePlayBetCounterID = LAST_INSERT_ID();
        
        /**
         * Split up the deduction in _pre table
         */
        INSERT INTO gaming_game_plays_bonus_instances_pre (
            game_play_bet_counter_id, bonus_instance_id, bet_total, 
            bet_real, bet_bonus, bet_bonus_win_locked,
            bonus_order, no_loyalty_points
        )
        SELECT 
            gamePlayBetCounterID, bonus_instance_id, bet_real+free_bet_bonus+bet_bonus+bet_bonus_win_locked  AS bet_total, 
            bet_real, bet_bonus+free_bet_bonus, bet_bonus_win_locked,
            bonusCounter, no_loyalty_points
        FROM
        (
            SELECT 
                bonus_instance_id AS bonus_instance_id, 
                @freeBetBonus:=IF(awarding_type='FreeBet', IF(bonus_amount_remaining>@debitRemain, @debitRemain, bonus_amount_remaining), 0) AS free_bet_bonus, 
                @debitRemain:=@debitRemain-@freeBetBonus,   
                @debitBonusWinLocked:= IF(current_win_locked_amount>@debitRemain, @debitRemain, current_win_locked_amount) AS bet_bonus_win_locked,
                @debitRemain:=@debitRemain-@debitBonusWinLocked,
                @debitReal:=IF(@bonusCounter=0, IF(currentRealBalance>@debitRemain, @debitRemain, currentRealBalance), 0) AS bet_real, 
                @debitRemain:=@debitRemain-@debitReal,  
                @debitBonus:= IF(awarding_type='FreeBet', 0, IF(bonus_amount_remaining>@debitRemain, @debitRemain, bonus_amount_remaining)) AS bet_bonus,
                @debitRemain:=@debitRemain-@debitBonus, 
                @bonusCounter:=@bonusCounter + 1 AS bonusCounter,
                @freeBonusAmount := @freeBonusAmount + IF(awarding_type='FreeBet' OR is_free_bonus, @freeBetBonus, 0),
                no_loyalty_points
            FROM
            (
                SELECT 
                    gaming_bonus_instances.bonus_instance_id, 
                    gaming_bonus_types_awarding.name AS awarding_type, 
                    bonus_amount_remaining, current_win_locked_amount, 
                    gaming_bonus_rules.no_loyalty_points,
                    current_ring_fenced_amount,
                    is_free_bonus
                FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses)
                STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
                STRAIGHT_JOIN gaming_bonus_types_awarding ON gaming_bonus_rules.bonus_type_awarding_id=gaming_bonus_types_awarding.bonus_type_awarding_id
                WHERE gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 AND gaming_bonus_instances.is_free_rounds_mode=0
                ORDER BY IF(awarding_type='FreeBet', 1, 0) DESC, gaming_bonus_instances.is_freebet_phase DESC, gaming_bonus_instances.bonus_instance_id ASC,gaming_bonus_instances.bonus_instance_id ASC
            ) AS XX
        ) AS XY;

        SET @debitReal = IF (currentRealBalance > debitAmountRemain, debitAmountRemain, currentRealBalance);        
        SET @debitBonus = 0.0;
        SET @debitBonusWinLocked = 0.0;
        SET @debitReal_tmp = 0.0;
        SET @debitBonus_tmp = 0.0;
        SET @debitBonusWinLocked_tmp = 0.0;
        
        SELECT 
            SUM(bet_real), SUM(bet_bonus), SUM(bet_bonus_win_locked)
        INTO 
            @debitReal_tmp, @debitBonus_tmp, @debitBonusWinLocked_tmp
        FROM gaming_game_plays_bonus_instances_pre
        WHERE game_play_bet_counter_id=gamePlayBetCounterID;
        
        -- If there were no bonuses, this will be null
        IF (@debitReal_tmp IS NOT NULL) THEN
            SET @debitReal = @debitReal_tmp;
            SET @debitBonus = @debitBonus_tmp;
            SET @debitBonusWinLocked = @debitBonusWinLocked_tmp;
        END IF;

        SET debitAmountRemain = debitAmountRemain - (@debitReal + @debitBonus + @debitBonusWinLocked);
        SET debitReal = @debitReal;
        SET debitBonus = @debitBonus;
        SET debitBonusWinLocked = @debitBonusWinLocked;
        SET @BonusCounter = 0;
        SET @betBonusDeduct = debitBonus;
        SET @betBonusDeductWinLocked = debitBonusWinLocked;
    
        INSERT INTO gaming_game_plays_bonus_instances_wins (
            game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, 
            bonus_rule_id, timestamp, exchange_rate, 
            win_real, win_bonus, win_bonus_win_locked, 
            lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, 
            win_game_play_id, add_wager_contribution
        )
        SELECT 
            gamePlayWinCounterID, bonus_instance_id /*-1*/ , bonus_instance_id, 
            bonus_rule_id, NOW(), exchangeRate, 
            bet_real*-1, bet_bonus*-1, bet_bonus_win_locked*-1,
            0, 0, clientStatID, 
            NULL, 0
        FROM 
        (
            SELECT 
                sbBetID, 
                bonus_instance_id, 
                bonus_rule_id,
                @BonusCounter := @BonusCounter + 1 AS bonus_order,
                @debitBonusWinLocked := IF(@betBonusDeductWinLocked >= current_win_locked_amount, current_win_locked_amount, @betBonusDeductWinLocked) AS bet_bonus_win_locked,
                @BetReal := IF(@BonusCounter = 1, debitReal, 0) AS bet_real,
                @debitBonus := IF(@betBonusDeduct >= bonus_amount_remaining, bonus_amount_remaining, @betBonusDeduct) AS bet_bonus,
                @betBonusDeduct := GREATEST(0, @betBonusDeduct - @debitBonus) AS bonusDeductRemain, 
                @betBonusDeductWinLocked := GREATEST(0, @betBonusDeductWinLocked - @debitBonusWinLocked) AS bonusWinLockedRemain
            FROM 
            (
                SELECT
                    gbi.bonus_instance_id,
                    gbi.bonus_rule_id,
                    IF(gbta.name = 'FreeBet' OR gbr.is_free_bonus, 0, current_win_locked_amount) AS current_win_locked_amount,
                    bonus_amount_remaining
                FROM gaming_bonus_instances AS gbi FORCE INDEX (client_active_bonuses)    
                STRAIGHT_JOIN gaming_bonus_rules AS gbr ON gbi.bonus_rule_id = gbr.bonus_rule_id
                STRAIGHT_JOIN gaming_bonus_types_awarding AS gbta ON gbr.bonus_type_awarding_id = gbta.bonus_type_awarding_id
                WHERE gbi.client_stat_id = clientStatID AND gbi.is_active = 1          
                ORDER BY gbta.`order` ASC, gbi.priority ASC, gbi.bonus_instance_id ASC
            ) AS applicable  
            HAVING bet_bonus > 0 OR bet_bonus_win_locked > 0
        ) AS b;
    
        -- Update the remaining bonus balance
        UPDATE gaming_game_plays_bonus_instances_wins AS ggpbi FORCE INDEX (PRIMARY)
        STRAIGHT_JOIN gaming_bonus_instances AS gbi ON 
            ggpbi.game_play_win_counter_id=gamePlayWinCounterID AND
            gbi.bonus_instance_id=ggpbi.bonus_instance_id
        SET 
            gbi.bonus_amount_remaining=gbi.bonus_amount_remaining+ggpbi.win_bonus,
            gbi.current_win_locked_amount=gbi.current_win_locked_amount+ggpbi.win_bonus_win_locked ;

        SET winReal = debitReal;
        SET winBonus = debitBonus;
        SET winBonusWinLocked = debitBonusWinLocked;
        SET badDebtRealAmount = debitAmountRemain;
        /* There should be something for free bet here too maybe? */        

        #endregion

    END IF;

  END IF; -- If bonuses are not enabled

 /** 
  *  This was in Type 1 - how relevant is this? 
  * - this should be relevant , as it puts together the relevant amounts for gameplays and client stats   
  */

  IF (winAmount>0) THEN
      SET @winBonusLostFromPrevious= IFNULL( ROUND( ( ( betBonusLost ) / betTotal ) * winAmount, 5 ), 0 );        
  ELSE
    SET @winBonusLostFromPrevious=0;
    -- this should be legit for SB too
    SET winReal=winReal*-1;
    SET winBonus=winBonus*-1;
    SET winBonusWinLocked=winBonusWinLocked*-1;
    SET winFreeBet=winFreeBet*-1;
    SET winFreeBetWinLocked=winFreeBetWinLocked*-1;
  END IF;


  SET winReal=winReal-@winBonusLostFromPrevious;  
 
  SET winTotalBase=ROUND( winAmount / exchangeRate , 5);
  
  #endregion
               


--                                                  
--   _____  _   __  __  ____ _____  _    ____ _____ 
--  |_   _|/ \  \ \/ / / ___|_   _|/ \  |  _ |_   _|
--    | | / _ \  \  /  \___ \ | | / _ \ | |_) || |  
--    | |/ ___ \ /  \   ___) || |/ ___ \|  _ < | |  
--    |_/_/   \_/_/\_\ |____/ |_/_/   \_|_| \_\|_|  
--  ===================================================
/* not touching this stuff for now */

  #region
  IF (taxEnabled AND (closeRound OR IsRoundFinished)) THEN

    SET roundWinTotalFull = roundWinTotalReal + winReal;
    -- betTotal is the sum of gaming_games_plays.amount_total of the bets in this round not processed (is_win_place = 0)
    CALL TaxCalculateTax(licenseTypeID, clientStatID, clientID, roundWinTotalFull, betTotal, taxAmount, taxAppliedOnType, taxCycleID);
  
    IF (taxAppliedOnType = 'OnReturn') THEN
      /*
        a) The tax should be stored in gaming_game_plays.amount_tax_player. 
        b) update gaming_client_stats -> current_real_balance
        c) update gaming_client_stats -> total_tax_paid
      */
  
        SET taxOnReturn = taxAmount;
  
    ELSEIF (taxAppliedOnType = 'Deferred') THEN
        /*
        a) - Update gaming_tax_cycles -> deferred_tax_amount.
        b) - Update gaming_client_stats -> deferred_tax. 
        c) - insert gaming_game_plays -> tax_cycle_id (gaming_tax_cycles) to link to the respective tax cycle.
        d) - insert gaming_game_plays -> amount_tax_player The tax should be stored in the same column as non-deferred tax.
  
        Note: Looking just to gaming_game_plays we can differentiate if is OnReturn or Deferred, checking gaming_game_plays.tax_cycle_id
              If it is filled its deferred tax otherwise its tax on Return.
        */
        IF (ISNULL(taxCycleID)) THEN
        
            SET statusCode = 1;
            LEAVE root;
        END IF;
  
    END IF;

  END IF;
  
--  ===================================================
--   _____  _   __  __  _____ _   _ ____  
--  |_   _|/ \  \ \/ / | ____| \ | |  _ \ 
--    | | / _ \  \  /  |  _| |  \| | | | |
--    | |/ ___ \ /  \  | |___| |\  | |_| |
--    |_/_/   \_/_/\_\ |_____|_| \_|____/ 
--                                  
#endregion
  
--                                                                  
--    ____ _     ___ _____ _   _ _____   ____ _____  _  _____ ____  
--   / ___| |   |_ _| ____| \ | |_   _| / ___|_   _|/ \|_   _/ ___| 
--  | |   | |    | ||  _| |  \| | | |   \___ \ | | / _ \ | | \___ \ 
--  | |___| |___ | || |___| |\  | | |    ___) || |/ ___ \| |  ___) |
--   \____|_____|___|_____|_| \_| |_____|____/ |_/_/   \_|_| |____/ 
--                                 |_____|                       
-- Update player's balance and statitics 
/* Double checked with Lotto place win, should be a-okay */
  #region

  IF (winAmount >= 0) THEN
    UPDATE
      gaming_client_stats AS gcs
      LEFT JOIN gaming_client_sessions AS gcsession ON gcsession.session_id=sessionID
      LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
    SET
      -- client stats
      gcs.total_real_won= ( gcs.total_real_won + winReal ),
      gcs.current_real_balance= ( gcs.current_real_balance + (winReal - taxOnReturn) ),
      gcs.total_bonus_won= ( gcs.total_bonus_won + winBonus ),
      gcs.current_bonus_balance= ( gcs.current_bonus_balance + winBonus ),
      gcs.total_bonus_win_locked_won= ( gcs.total_bonus_win_locked_won + winBonusWinLocked ),
      gcs.current_bonus_win_locked_balance= ( current_bonus_win_locked_balance + winBonusWinLocked ),
      gcs.total_real_won_base= ( gcs.total_real_won_base + ( winReal / exchangeRate ) ),
      gcs.total_bonus_won_base= ( gcs.total_bonus_won_base + ( ( winBonus + winBonusWinLocked ) / exchangeRate ) ),
      gcs.total_tax_paid= ( gcs.total_tax_paid + taxOnReturn ),
      gcs.total_tax_paid_bonus = gcs.total_tax_paid_bonus,
      -- client session
      gcsession.total_win= ( gcsession.total_win + winAmount ),
      gcsession.total_win_base= ( gcsession.total_win_base + winTotalBase ),
      gcsession.total_bet_placed= ( gcsession.total_bet_placed + betTotal ),
      gcsession.total_win_real= ( gcsession.total_win_real + winReal ),
      gcsession.total_win_bonus= ( gcsession.total_win_bonus + winBonus+winBonusWinLocked ),
      -- wager status
      gcws.num_wins= ( gcws.num_wins + IF(winAmount>0, 1, 0) ),
      gcws.total_real_won= ( gcws.total_real_won + winReal ),
      gcws.total_bonus_won= ( gcws.total_bonus_won + winBonus+winBonusWinLocked ),
      -- cumulative deferred tax to later on (when we need to close tax cycle) transfer to the respective tax cycle
      gcs.deferred_tax = ( gcs.deferred_tax + IF(taxAppliedOnType ='Deferred', taxAmount, 0) ),
      -- update bet from real - if credit, deduct until 0, otherwise
      gcs.bet_from_real = GREATEST(0, gcs.bet_from_real - winReal)
    WHERE
      gcs.client_stat_id=clientStatID;

  ELSE

    SET @deductBetFromReal = IF( betFromReal-ABS(winReal) > 0, ABS(winReal), betFromReal );
        
    SET @deductFromReal = ABS(winReal) + badDebtRealAmount;

  
    UPDATE
      gaming_client_stats AS gcs
      LEFT JOIN gaming_client_sessions AS gcsession ON gcsession.session_id=sessionID
      LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID
    SET
      -- update bet from real - first deduct until 0 and then deduct rest from real balance      
      gcs.bet_from_real = gcs.bet_from_real - @deductBetFromReal,
      gcs.current_real_balance = gcs.current_real_balance - (@deductFromReal + taxOnReturn),

      -- client stats
      gcs.total_real_won= ( gcs.total_real_won + winReal ),      
      gcs.total_bonus_won= ( gcs.total_bonus_won + winBonus ),
      gcs.current_bonus_balance= ( gcs.current_bonus_balance + winBonus ),
      gcs.total_bonus_win_locked_won= ( gcs.total_bonus_win_locked_won + winBonusWinLocked ),
      gcs.current_bonus_win_locked_balance= ( current_bonus_win_locked_balance + winBonusWinLocked ),
      gcs.total_real_won_base= ( gcs.total_real_won_base + ( winReal / exchangeRate ) ),
      gcs.total_bonus_won_base= ( gcs.total_bonus_won_base + ( ( winBonus + winBonusWinLocked ) / exchangeRate ) ),
      gcs.total_tax_paid= ( gcs.total_tax_paid + taxOnReturn ),
      gcs.total_tax_paid_bonus = gcs.total_tax_paid_bonus,
      -- client session
      gcsession.total_win= ( gcsession.total_win + winAmount ),
      gcsession.total_win_base= ( gcsession.total_win_base + winTotalBase ),
      gcsession.total_bet_placed= ( gcsession.total_bet_placed + betTotal ),
      gcsession.total_win_real= ( gcsession.total_win_real + winReal ),
      gcsession.total_win_bonus= ( gcsession.total_win_bonus + winBonus+winBonusWinLocked ),
      -- wager status      
      gcws.total_real_won= ( gcws.total_real_won + winReal ),
      gcws.total_bonus_won= ( gcws.total_bonus_won + winBonus+winBonusWinLocked ),
      -- cumulative deferred tax to later on (when we need to close tax cycle) transfer to the respective tax cycle
      gcs.deferred_tax = ( gcs.deferred_tax + IF(taxAppliedOnType ='Deferred', taxAmount, 0) )
      
    WHERE
      gcs.client_stat_id=clientStatID;

  END IF;
  #endregion 


--                                                                     
--    ____    _    __  __ _____     ____  _        _ __   ______       
--   / ___|  / \  |  \/  | ____|   |  _ \| |      / \\ \ / / ___|__/\__
--  | |  _  / _ \ | |\/| |  _|     | |_) | |     / _ \\ V /\___ \\    /
--  | |_| |/ ___ \| |  | | |___    |  __/| |___ / ___ \| |  ___) /_  _\
--   \____/_/   \_|_|  |_|_________|_|   |_____/_/   \_|_| |____/  \/  
--                            |_____|                               
-- Insert into gaming_plays (main transaction)
  #region

  -- Added switch here, to make the gameplay types more readible
  SET @messageType= 
    CASE
      WHEN winAmount=0          THEN 'SportsLoss'
      WHEN winAmount<0          THEN 'SportsAdjustment'
      WHEN isSBSingle='Single'  THEN 'SportsWin'
      /* Any additional message types ?? */
      ELSE 'SportsWinMult'
    END;

  SELECT COUNT(sb_bet_id) INTO hasPreviousWinTrans 
  FROM gaming_game_plays_sb 
  WHERE sb_bet_id = sbBetID AND payment_transaction_type_id = 13 AND
	-- parition filtering
	(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID);
  
  SET @transactionType=
    CASE
      WHEN hasPreviousWinTrans = 0 THEN 'Win'
	  /* winAmount < 0 */
	  WHEN winAmount < 0 AND ABS(winAmount) = roundWinTotal AND hasPreviousWinTrans >0 THEN 'WinCancelled'
      /* Any additional transactiontypes ?? */
      ELSE 'WinAdjustment'
    END;

  INSERT INTO gaming_game_plays 
  (
    amount_total, amount_total_base, exchange_rate, amount_real, 
    amount_bonus, amount_bonus_win_locked, amount_free_bet, 
    amount_other, bonus_lost, bonus_win_locked_lost, jackpot_contribution, 
    timestamp, game_manufacturer_id, client_id, client_stat_id, 
    session_id, game_round_id, payment_transaction_type_id, is_win_placed, 
    balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, 
    round_transaction_no, game_play_message_type_id, sb_extra_id, sb_bet_id, 
    license_type_id, device_type, pending_bet_real, pending_bet_bonus, 
    amount_tax_operator, amount_tax_player, loyalty_points, loyalty_points_after, 
    loyalty_points_bonus, loyalty_points_after_bonus, tax_cycle_id
  ) 
  SELECT
    winAmount, winTotalBase, exchangeRate, winReal,
    winBonus, winBonusWinLocked, FreeBonusAmount, badDebtRealAmount, 
    @winBonusLost, ROUND( @winBonusWinLockedLost + @winBonusLostFromPrevious, 0 ), 0, 
    NOW(), gameManufacturerID, clientID, clientStatID, 
    sessionID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, 
    gcs.current_real_balance, ROUND(gcs.current_bonus_balance+gcs.current_bonus_win_locked_balance, 0), gcs.current_bonus_win_locked_balance, currencyID, 
    numTransactions+1, gaming_game_play_message_types.game_play_message_type_id, betSBExtraID, sbBetID,
    gaming_game_plays.license_type_id, gaming_game_plays.device_type, gcs.pending_bets_real, gcs.pending_bets_bonus, 
    taxModificationOperator, taxModificationPlayer, 0, gcs.current_loyalty_points, 
    0, gcs.total_loyalty_points_given_bonus - gcs.total_loyalty_points_used_bonus, taxCycleID
  FROM gaming_payment_transaction_type
  JOIN gaming_client_stats AS gcs ON gaming_payment_transaction_type.name=@transactionType AND gcs.client_stat_id=clientStatID
  JOIN gaming_game_plays ON gaming_game_plays.game_play_id=betGamePlayID
  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.name=@messageType;
  
  SET gamePlayID=LAST_INSERT_ID();

  #endregion

  IF (select value_bool from gaming_settings where name='RULE_ENGINE_ENABLED')=1 AND ((SELECT amount_total_base FROM gaming_game_plays WHERE game_play_id=gamePlayID)> 0) THEN
      INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 1, gamePlayID;
  END IF;

  -- Update ring fencing balance and statistics
  IF (ringFencedEnabled) THEN
	CALL GameUpdateRingFencedBalances(clientStatID, gamePlayID);
  END IF;
   

  /* if negative balance is disabled */
  IF (disallowNegativeBalance AND badDebtRealAmount > 0) THEN
    /* Neg. balances - in case player wins 50, bets 30 and later the 50 win is cancelled -> -30  */
      CALL PlaceTransactionOffsetNegativeBalancePreComputred(clientStatID, badDebtRealAmount, exchangeRate, gamePlayID, betSBExtraID, sbBetID, 3, badDeptGamePlayID);
  END IF;
  


  -- update bet and win bonus counters
  UPDATE gaming_game_plays_win_counter_bets
    SET win_game_play_id=gamePlayID
  WHERE game_play_win_counter_id=gamePlayWinCounterID;

  /* this never happens - variable is declared, but never changed from "0" */
  IF (updateGamePlayBonusInstanceWin) THEN
    UPDATE gaming_game_plays_bonus_instances_wins SET win_game_play_id=gamePlayID WHERE game_play_win_counter_id=gamePlayWinCounterID;
  END IF;
 
  -- Insert into gaming_game_plays_sb to store extra sports book details and to have all sports book transactions in this table
  INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, 
    game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, 
    sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, units, confirmation_status, amount_bonus_win_locked_component, game_round_id, sb_bet_entry_id)
  SELECT gaming_game_plays.game_play_id, gaming_game_plays.payment_transaction_type_id, gaming_game_plays.amount_total, gaming_game_plays.amount_total_base, gaming_game_plays.amount_real, gaming_game_plays.amount_real/gaming_game_plays.exchange_rate, 
    gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked, (gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)/gaming_game_plays.exchange_rate, gaming_game_plays.timestamp, gaming_game_plays.exchange_rate, 
    bet_play_sb.game_manufacturer_id, clientID, clientStatID, currencyID, countryID, gaming_game_plays.round_transaction_no, bet_play_sb.sb_sport_id, bet_play_sb.sb_region_id, bet_play_sb.sb_group_id, bet_play_sb.sb_event_id, bet_play_sb.sb_market_id, bet_play_sb.sb_selection_id, 
    gaming_game_plays.sb_bet_id, bet_play_sb.sb_multiple_type_id, bet_play_sb.sb_bet_type, bet_play_sb.device_type, 0, 2, gaming_game_plays.amount_bonus_win_locked, bet_play_sb.game_round_id, bet_play_sb.sb_bet_entry_id
  FROM gaming_game_plays
  STRAIGHT_JOIN gaming_game_plays_sb AS bet_play_sb ON bet_play_sb.game_play_sb_id=betGamePlaySBID 
  WHERE gaming_game_plays.game_play_id=gamePlayID;
  
  SET maxGamePlaySBID = LAST_INSERT_ID();

  /* is show sum of wins from the above table (mostly for reports) */
    UPDATE gaming_game_plays_bonus_instances_wins FORCE INDEX (PRIMARY)
    STRAIGHT_JOIN gaming_game_plays_sb_bonuses FORCE INDEX (PRIMARY) ON 
        (gaming_game_plays_sb_bonuses.game_play_sb_id=betGamePlaySBID AND
         gaming_game_plays_bonus_instances_wins.bonus_instance_id=gaming_game_plays_sb_bonuses.bonus_instance_id)
    SET 
        gaming_game_plays_sb_bonuses.win_real = gaming_game_plays_sb_bonuses.win_real + gaming_game_plays_bonus_instances_wins.win_real,
        gaming_game_plays_sb_bonuses.win_bonus = gaming_game_plays_sb_bonuses.win_bonus + gaming_game_plays_bonus_instances_wins.win_bonus,
        gaming_game_plays_sb_bonuses.win_bonus_win_locked = gaming_game_plays_sb_bonuses.win_bonus_win_locked + gaming_game_plays_bonus_instances_wins.win_bonus_win_locked
    WHERE gaming_game_plays_bonus_instances_wins.game_play_win_counter_id=gamePlayWinCounterID;
 
--                                                              
--   ____  _        _ __   __  _     ___ __  __ ___ _____ ____  
--  |  _ \| |      / \\ \ / / | |   |_ _|  \/  |_ _|_   _/ ___| 
--  | |_) | |     / _ \\ V /  | |    | || |\/| || |  | | \___ \ 
--  |  __/| |___ / ___ \| |   | |___ | || |  | || |  | |  ___) |
--  |_|   |_____/_/   \_|_|   |_____|___|_|  |_|___| |_| |____/ 
--      
-- Update play limits current status (loss only) 
  #region
  IF (winAmount > 0 AND playLimitEnabled) THEN
    CALL PlayLimitsUpdate(clientStatID, licenseType, winAmount, 0);
  END IF;
  #endregion

  -- Update the round statistics and close it
  UPDATE gaming_game_rounds
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  SET 
    win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+winTotalBase,5), win_real=win_real+winReal, win_bonus=win_bonus+winBonus,
    win_bonus_win_locked=win_bonus_win_locked+winBonusWinLocked,win_free_bet = win_free_bet + FreeBonusAmount, win_bet_diffence_base=win_total_base-bet_total_base,
    bonus_lost=bonus_lost+@winBonusLost, bonus_win_locked_lost=bonus_win_locked_lost+@winBonusWinLockedLost+@winBonusLostFromPrevious, 
    date_time_end= IF (closeRound, NOW(), date_time_end), is_round_finished=IF (closeRound, 1, is_round_finished), num_transactions=num_transactions+1, 
    balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance, amount_tax_operator = amountTaxOperator, amount_tax_player = amountTaxPlayer
  WHERE gaming_game_rounds.game_round_id=gameRoundID;   
  
  -- Update also the master round statistics
  UPDATE gaming_game_rounds
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  SET 
    win_total=win_total+winAmount, win_total_base=ROUND(win_total_base+winTotalBase,5), win_real=win_real+winReal, win_bonus=win_bonus+winBonus, 
    win_bonus_win_locked=win_bonus_win_locked+winBonusWinLocked, win_free_bet=win_free_bet+FreeBonusAmount,
    bonus_lost=bonus_lost+@winBonusLost, bonus_win_locked_lost=bonus_win_locked_lost+@winBonusWinLockedLost+@winBonusLostFromPrevious, 
    date_time_end=IF(closeRound, NOW(), date_time_end), num_transactions=num_transactions+1, 
    balance_real_after=current_real_balance, balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance, amount_tax_operator = amountTaxOperator, amount_tax_player = amountTaxPlayer
  WHERE gaming_game_rounds.round_ref=sbBetID AND gaming_game_rounds.is_cancelled = 0;

  UPDATE gaming_game_rounds
  SET win_bet_diffence_base=win_total_base-bet_total_base
  WHERE round_ref=sbBetID AND gaming_game_rounds.is_cancelled = 0 AND
	-- parition filtering
	(gaming_game_rounds.game_round_id BETWEEN minGameRoundID AND maxGameRoundID);

  -- Check if bonus is secured
  IF (@isBonusSecured OR @isFreeBonusWin) THEN
      CALL BonusConvertWinningsAfterSecuredDate(gamePlayID, gamePlayWinCounterID);
  END IF;
  
  IF (bonusesUsedAllWhenZero AND bonusEnabledFlag) THEN
      SELECT current_bonus_balance, current_real_balance, current_bonus_win_locked_balance
      INTO currentBonusAmount, currentRealAmount, currentWinLockedAmount
      FROM gaming_client_stats
      WHERE client_stat_id = ClientStatID;

      -- CHECK IF PLAYER HAS ANY ACTIVE BONUSES
      SELECT IF (COUNT(1) > 0, 1, 0) INTO playerHasActiveBonuses FROM gaming_bonus_instances WHERE client_stat_id = clientStatID AND (is_active = 1);

      IF (currentBonusAmount = 0 AND currentRealAmount = 0 AND currentWinLockedAmount = 0 AND playerHasActiveBonuses) THEN -- AND -- has active bonuses)
          CALL BonusForfeitBonus(sessionID, clientStatID, 0, 0, 'IsUsedAll', 'TYPE_TWO_BONUSES_USED_ALL_WHEN_ZERO - Used All');
      END IF;
  END IF;

  
#endregion
--  ======================================================================================================
--   ____   ___  _   _ _   _ ____            _____  _   __  __  _____ _   _ ____  
--  | __ ) / _ \| \ | | | | / ___|     _    |_   _|/ \  \ \/ / | ____| \ | |  _ \ 
--  |  _ \| | | |  \| | | | \___ \   _| |_    | | / _ \  \  /  |  _| |  \| | | | |
--  | |_) | |_| | |\  | |_| |___) | |_   _|   | |/ ___ \ /  \  | |___| |\  | |_| |
--  |____/ \___/|_| \_|\___/|____/    |_|     |_/_/   \_/_/\_\ |_____|_| \_|____/ 
--          

  -- Set output variables
  SET gamePlayIDReturned=gamePlayID;
  SET statusCode=0;

  UPDATE gaming_sb_bets_partition_fields
  SET 
    max_game_play_sb_id=maxGamePlaySBID
  WHERE sb_bet_id=sbBetID;	

  IF (winAmount<0) THEN
      SELECT badDeptGamePlayID AS game_play_id, IF(disallowNegativeBalance, badDebtRealAmount, 0.00000) AS bad_dept_real_amount;
  END IF;
    
END root$$

DELIMITER ;

