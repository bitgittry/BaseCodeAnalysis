DROP procedure IF EXISTS `CommonWalletSportsGenericCreditCustomerByBetRef`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSportsGenericCreditCustomerByBetRef`(
  gameManufacturerID BIGINT, transactionRef VARCHAR(100), betTransactionRef VARCHAR(80), betRef VARCHAR(40), winAmount DECIMAL(18,5), 
  closeRound TINYINT(1), isSystemBet TINYINT(1), isCancelBetCall TINYINT(1), minimalData TINYINT(1), OUT gamePlayIDReturned BIGINT, OUT statusCode INT)
root: BEGIN

  -- Negative WinAmount: needed to return bad dept amount
  -- Checking with win_game_play_id  
  -- Calling new proc PlaceSBWinGenericType1
  -- Forced indices
  -- Added join with gaming_game_rounds, to check game_round_type_id is either Sports or SportsMult (in case two gaming_game_plays_sb exist with same sb_bet_entry_id)
  -- Win 0 and isSystemBet returing statusCode 20 and player balance
  -- Optimized for Parititioning

  DECLARE sbBetWinID, gamePlayID, gamePlaySBID, sbBetID, clientStatIDCheck, clientStatID, badDeptGamePlayID, gameRoundID BIGINT DEFAULT -1;
  DECLARE liveBetType TINYINT(4) DEFAULT 2;
  DECLARE deviceType TINYINT(4) DEFAULT 1;
  DECLARE betType, wagerType VARCHAR(20) DEFAULT NULL;
  DECLARE badDebtRealAmount, roundWinAmount DECIMAL(18,5) DEFAULT 0;
  DECLARE numSingles, numMultiples INT DEFAULT 0;
  DECLARE isCouponBet TINYINT(1) DEFAULT 0;
  
  DECLARE partitioningMinusFromMax INT DEFAULT 10000;
  DECLARE minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, 
	minSbBetMultipleSingleID, maxSbBetMultipleSingleID, minGameRoundID, maxGameRoundID, 
    minGamePlaySBID, maxGamePlaySBID, minGamePlayBonusInstanceID, maxGamePlayBonusInstanceID BIGINT DEFAULT NULL; 
  
  SET gamePlayIDReturned = NULL;
  SET statusCode=0; 
    
  SELECT gs1.value_string INTO wagerType
  FROM gaming_settings gs1     
  WHERE gs1.name='PLAY_WAGER_TYPE';

  -- Branko added this line because SuperBet requested to send in Credit and Debit Customer without the player session
  SELECT gsb.client_stat_id, gsb.sb_bet_id, gsb.num_singles, gsb.num_multiplies, gsb.lottery_dbg_ticket_id IS NOT NULL,
	gsbpf.max_sb_bet_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_single_id, 
    gsbpf.max_sb_bet_multiple_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_id,
    gsbpf.max_sb_bet_multiple_single_id-partitioningMinusFromMax, gsbpf.max_sb_bet_multiple_single_id,
    gsbpf.min_game_round_id, gsbpf.max_game_round_id, 
    gsbpf.min_game_play_sb_id, gsbpf.max_game_play_sb_id,
    gsbpf.max_game_play_bonus_instance_id-partitioningMinusFromMax, gsbpf.max_game_play_bonus_instance_id
  INTO clientStatID, sbBetID , numSingles , numMultiples, isCouponBet,
	minSbBetSingleID, maxSbBetSingleID, minSbBetMultipleID, maxSbBetMultipleID, minSbBetMultipleSingleID, maxSbBetMultipleSingleID,
    minGameRoundID, maxGameRoundID, minGamePlaySBID, maxGamePlaySBID, minGamePlayBonusInstanceID, maxGamePlayBonusInstanceID
  FROM gaming_sb_bets AS gsb FORCE INDEX (transaction_ref)
  LEFT JOIN gaming_sb_bets_partition_fields AS gsbpf ON gsbpf.sb_bet_id=gsb.sb_bet_id
  WHERE gsb.transaction_ref = betTransactionRef AND gsb.game_manufacturer_id = gameManufacturerID;
  
  -- select sbBetID;
  IF (sbBetID=-1) THEN
	  SET statusCode=2;
  END IF;

  -- Check if the win is already processed
  IF (isCancelBetCall = 1) THEN
	-- if the bet is already canceled
    SELECT gwc.sb_bet_win_id, gwc.win_game_play_id
    INTO sbBetWinID , gamePlayIDReturned 
		FROM gaming_sb_bet_wins gw FORCE INDEX (sb_bet_id)
		STRAIGHT_JOIN gaming_sb_bet_wins gwc ON gwc.game_play_id = gw.game_play_id
		STRAIGHT_JOIN gaming_game_plays ggpwc ON ggpwc.game_play_id = gwc.win_game_play_id
		WHERE gw.sb_bet_id=sbBetID AND gw.transaction_ref = transactionRef AND gw.status_code = 0 AND ggpwc.payment_transaction_type_id IN (20, 247) 
        LIMIT 1;
	
    IF (sbBetWinID = -1 AND gamePlayIDReturned IS NULL) THEN
  		-- if we have win amount without cancel win
  		SELECT gwc.sb_bet_win_id, gwc.win_game_play_id
  		INTO sbBetWinID , gamePlayIDReturned 
  		FROM gaming_sb_bet_wins gw FORCE INDEX (sb_bet_id)
  		STRAIGHT_JOIN gaming_sb_bet_wins gwc ON gwc.game_play_id = gw.game_play_id
  		STRAIGHT_JOIN gaming_game_plays ggpwc ON ggpwc.game_play_id = gwc.win_game_play_id
  		WHERE gw.sb_bet_id=sbBetID AND gw.transaction_ref = transactionRef AND gw.status_code = 0
  		GROUP BY gw.sb_bet_win_id
  		HAVING SUM(ggpwc.amount_total) != 0
  		LIMIT 1;
		
  		-- if we have loss (win = 0)
  		IF (sbBetWinID = -1 AND gamePlayIDReturned IS NULL) THEN
  			SELECT gw.sb_bet_win_id, gw.win_game_play_id
  			INTO sbBetWinID , gamePlayIDReturned 
  			FROM gaming_sb_bet_wins gw FORCE INDEX (sb_bet_id)
  			STRAIGHT_JOIN gaming_sb_bet_wins gwc ON gwc.game_play_id = gw.game_play_id
  			STRAIGHT_JOIN gaming_game_plays ggpwc ON ggpwc.game_play_id = gwc.win_game_play_id
  			WHERE gw.sb_bet_id=sbBetID AND gw.transaction_ref = transactionRef AND gw.status_code = 0 AND ggpwc.amount_total = 0
  			GROUP BY gw.sb_bet_win_id
  			HAVING COUNT(ggpwc.amount_total) % 2 = 1
  			LIMIT 1;
  		END IF;
	  END IF;
  ELSE
  
  	SELECT sb_bet_win_id, win_game_play_id
  	INTO sbBetWinID , gamePlayIDReturned 
  	FROM gaming_sb_bet_wins FORCE INDEX (sb_bet_id)
  	WHERE sb_bet_id=sbBetID AND transaction_ref = transactionRef AND status_code = 0
  	LIMIT 1;

  END IF;

  -- if bet already exists skip the procedure
  -- check if provider is Amelco (we use betRef as transactionRef) make adjustment
  IF (sbBetWinID != -1) THEN

    IF (winAmount < 0) THEN

		SELECT game_play_id, amount_real 
		INTO badDeptGamePlayID, badDebtRealAmount
		FROM gaming_game_plays FORCE INDEX (extra_id)
		STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='BadDebt' 
			AND gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
		WHERE gaming_game_plays.extra_id=gamePlayIDReturned 
		LIMIT 1;

		SELECT 
    badDeptGamePlayID AS game_play_id,
    badDebtRealAmount AS bad_dept_real_amount;

    END IF;

  	IF (isCouponBet) THEN
  		SELECT game_round_id INTO gameRoundID FROM gaming_game_plays WHERE game_play_id = gamePlayIDReturned;
        
  		CALL PlayReturnDataWithoutGame(gamePlayIDReturned, gameRoundID, clientStatID, gameManufacturerID, minimalData);
  		CALL PlayReturnBonusInfoOnWin(gamePlayIDReturned);
  	ELSE
   
  		CALL CommonWalletSBReturnDataOnWin(clientStatID, gamePlayIDReturned, minimalData);
  	END IF;

    LEAVE root;

  END IF;


  
  IF (numSingles > 0 AND gamePlayID=-1) THEN
    -- Checking among the singles
    SELECT gaming_game_plays.game_play_id, gaming_game_plays_sb.game_play_sb_id
	INTO gamePlayID, gamePlaySBID
    FROM gaming_sb_bets FORCE INDEX (PRIMARY)
	STRAIGHT_JOIN gaming_sb_bet_singles FORCE INDEX (sb_bet_id) ON 
		(gaming_sb_bets.sb_bet_id=sbBetID AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID 
			AND gaming_sb_bets.status_code!=1 AND gaming_sb_bets.client_stat_id=clientStatID) 
	  AND (gaming_sb_bet_singles.sb_bet_id=gaming_sb_bets.sb_bet_id AND
		-- parition filtering
		(gaming_sb_bet_singles.sb_bet_single_id BETWEEN minSbBetSingleID AND maxSbBetSingleID)
	  AND ((numSingles=1 AND numMultiples=0) 
	  OR gaming_sb_bet_singles.bet_ref=betRef)) 
	STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (sb_bet_entry_id) ON 
		gaming_game_plays_sb.sb_bet_entry_id=gaming_sb_bet_singles.sb_bet_single_id AND 
		gaming_game_plays_sb.sb_bet_id=gaming_sb_bets.sb_bet_id AND
		-- parition filtering
		(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)
	STRAIGHT_JOIN gaming_game_plays FORCE INDEX (PRIMARY) ON 
	  gaming_game_plays.game_play_id=gaming_game_plays_sb.game_play_id
	  AND gaming_game_plays.payment_transaction_type_id IN (12, 45) 
	  AND gaming_game_plays.license_type_id=3
	STRAIGHT_JOIN gaming_game_rounds ggr FORCE INDEX (PRIMARY) ON 
	  ggr.game_round_id=gaming_game_plays_sb.game_round_id
	STRAIGHT_JOIN gaming_game_round_types ggrt FORCE INDEX (PRIMARY) ON 
	  ggr.game_round_type_id = ggrt.game_round_type_id 
	  AND name = 'Sports'
	  AND ggr.is_cancelled = 0
    ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1; 
    
  END IF;

    
  IF (numMultiples > 0 AND gamePlayID=-1) THEN
    -- Checking among the multiples
    SELECT gaming_game_plays.game_play_id, gaming_game_plays_sb.game_play_sb_id
      INTO gamePlayID, gamePlaySBID
    FROM 
      gaming_sb_bets FORCE INDEX (PRIMARY)
        STRAIGHT_JOIN gaming_sb_bet_multiples ON 
  	      (gaming_sb_bets.sb_bet_id=sbBetID 
          AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID 
  		    AND gaming_sb_bets.status_code!=1 
          AND gaming_sb_bets.client_stat_id=clientStatID)
          AND (gaming_sb_bets.sb_bet_id=gaming_sb_bet_multiples.sb_bet_id AND
				-- parition filtering
				(gaming_sb_bet_multiples.sb_bet_multiple_id BETWEEN minSbBetMultipleID AND maxSbBetMultipleID)
			AND ((numMultiples=1 AND numSingles=0) 
                OR gaming_sb_bet_multiples.bet_ref=gaming_sb_bet_multiples.ext_multiple_type -- IFLEX does not have bet_ref for multiples 
				OR gaming_sb_bet_multiples.bet_ref=betRef))
        STRAIGHT_JOIN gaming_game_plays_sb FORCE INDEX (sb_bet_entry_id) ON 
			gaming_game_plays_sb.sb_bet_entry_id=gaming_sb_bet_multiples.sb_bet_multiple_id AND 
            gaming_game_plays_sb.sb_bet_id=gaming_sb_bets.sb_bet_id AND
            -- parition filtering
			(gaming_game_plays_sb.game_play_sb_id BETWEEN minGamePlaySBID AND maxGamePlaySBID)
        STRAIGHT_JOIN gaming_game_plays FORCE INDEX (PRIMARY) ON 
          gaming_game_plays.game_play_id=gaming_game_plays_sb.game_play_id
  	      AND gaming_game_plays.payment_transaction_type_id IN (12, 45) 
          AND gaming_game_plays.license_type_id=3
        STRAIGHT_JOIN gaming_game_rounds ggr FORCE INDEX (PRIMARY) ON 
          ggr.game_round_id=gaming_game_plays_sb.game_round_id
        STRAIGHT_JOIN gaming_game_round_types ggrt FORCE INDEX (PRIMARY) ON 
          ggr.game_round_type_id = ggrt.game_round_type_id 
          AND name = 'SportsMult'
		  AND ggr.is_cancelled = 0
      ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1;    
  END IF;
  
 
  IF (statusCode=0 AND (gamePlayID=-1)) THEN
    SET statusCode=1;
  END IF;
  
  IF (statusCode=0 AND (sbBetID=-1)) THEN
    SET statusCode=2;
  END IF;

  SELECT SUM(win_total)
    INTO roundWinAmount
  FROM gaming_game_rounds
  WHERE sb_bet_id = sbBetID;
  
  IF (isSystemBet && ((closeRound = 0 AND winAmount = 0) || (closeRound = 1 AND winAmount = 0 AND roundWinAmount > 0))) THEN
	CALL PlayReturnPlayBalanceData(clientStatID, NULL);
    
    SET statusCode=20;
    LEAVE root;
  END IF;
  
  
  IF ( statusCode = 0 ) THEN
    SET @closeRound = closeRound;  
    IF ( wagerType = 'Type1' ) THEN   
      /* Old Type 1 SP */      
      -- select 'type1';
       CALL PlaceSBWinGenericType1(clientStatID, gamePlayID, gamePlaySBID, winAmount, @closeRound, gamePlayIDReturned, statusCode);
    ELSEIF ( wagerType = 'Type2' ) THEN   
      /* Type 2 SP */
      -- select 'type2';
       CALL PlaceSBWinGenericType2(clientStatID, gamePlayID, gamePlaySBID, winAmount, @closeRound, gamePlayIDReturned, statusCode);
    ELSE
      /* unsupported wager type */
      SET statusCode = 10;
      LEAVE root;
    END IF;
  END IF;

  INSERT INTO gaming_sb_bet_wins (sb_bet_id, game_play_id, win_game_play_id, transaction_ref, status_code, timestamp, client_stat_id)
  SELECT sbBetID, gamePlayID, gamePlayIDReturned, transactionRef, statusCode, NOW(), clientStatID;
  
  IF (isCouponBet) THEN

	SELECT game_round_id INTO gameRoundID FROM gaming_game_plays WHERE game_play_id = gamePlayIDReturned;
	
    CALL PlayReturnDataWithoutGame(gamePlayIDReturned, gameRoundID, clientStatID, gameManufacturerID, minimalData);
	CALL PlayReturnBonusInfoOnWin(gamePlayIDReturned);

  ELSE

	CALL CommonWalletSBReturnDataOnWin(clientStatID, gamePlayIDReturned, minimalData);

  END IF;


  
END root$$

DELIMITER ;

