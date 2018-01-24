DROP procedure IF EXISTS `CommonWalletFinSoftCancelWinByBetRef`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletFinSoftCancelWinByBetRef`(clientStatID BIGINT, transactionRef VARCHAR(100), betRef VARCHAR(40), cancelBet TINYINT(1), canCommit TINYINT(1), OUT statusCode INT)
root: BEGIN

  

  DECLARE gameManufacturerName VARCHAR(20) DEFAULT 'FinSoft';

  DECLARE gameManufacturerID BIGINT DEFAULT 7; 
  DECLARE clientWagerTypeID BIGINT DEFAULT 3;

  DECLARE sbBetWinID, gamePlayID,winGamePlayID, sbBetID, sbBetIDCheck, sbExtraID, clientStatIDCheck, gameRoundID, sessionID,clientID,currencyID,gamePlayMessageTypeID, countryID, countryTaxID BIGINT DEFAULT -1; 
  DECLARE cancelAmount, cancelAmountBase, cancelReal, cancelBonus, cancelBonusWinLocked,betTotal,winAmount,exchangeRate,
			taxBet, taxWin, roundBetTotal, roundWinTotal, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, roundBetTotalReal, roundWinTotalReal,  amountTaxPlayer, amountTaxOperator, taxModificationOperator, taxModificationPlayer, roundWinTotalFull, roundBetTotalFull DECIMAL(18,5) DEFAULT 0;

  DECLARE gamePlayIDReturned,gamePlayWinCounterID BIGINT DEFAULT NULL;

  DECLARE numTransactions INT DEFAULT 0;

  DECLARE liveBetType TINYINT(4) DEFAULT 2;

  DECLARE deviceType,licenseTypeID TINYINT(4) DEFAULT 1;
  DECLARE bonusEnabledFlag,playLimitEnabled, applyNetDeduction, winTaxPaidByOperator, taxEnabled, sportsTaxCountryEnabled  TINYINT(1);
  DECLARE NumSingles INT DEFAULT 1;
 SET statusCode=0;

  

  SELECT client_id,client_stat_id,currency_id INTO clientID,clientStatID,currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;

  SELECT sb_bet_id, game_play_id INTO sbBetIDCheck, gamePlayIDReturned FROM gaming_sb_bet_history WHERE transaction_ref=transactionRef AND sb_bet_transaction_type_id=8; 
  

  IF (sbBetIDCheck!=-1) THEN 
    SET statusCode=0;

    IF (canCommit) THEN COMMIT AND CHAIN; END IF;

    CALL CommonWalletSBReturnTransactionData(gamePlayIDReturned, sbBetID, sbExtraID, 'Win', clientStatID); 

    LEAVE root;

  END IF;

	SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, IFNULL(gs3.value_bool,0) AS vb3
    INTO playLimitEnabled, bonusEnabledFlag, taxEnabled
    FROM gaming_settings gs1 
    JOIN gaming_settings gs2 ON (gs2.name='IS_BONUS_ENABLED')
    LEFT JOIN gaming_settings gs3 ON (gs3.name='TAX_ON_GAMEPLAY_ENABLED')
    WHERE gs1.name='PLAY_LIMIT_ENABLED';

  

  
  SELECT gaming_sb_bets.sb_bet_id, gaming_game_plays.game_play_id, gaming_game_plays.game_play_id_win, gaming_game_plays.game_round_id, gaming_game_plays.session_id, gaming_game_plays.amount_total, gaming_game_plays.sb_bet_id, 

    gaming_game_plays.sb_extra_id, gaming_game_plays.game_play_message_type_id, gaming_game_plays.device_type, gaming_game_rounds.num_transactions 

  INTO sbBetID, gamePlayID, winGamePlayID, gameRoundID, sessionID, betTotal, sbBetID, sbExtraID, gamePlayMessageTypeID, deviceType, numTransactions

  FROM gaming_sb_bet_singles 

  JOIN gaming_sb_bets ON gaming_sb_bet_singles.bet_ref=betRef AND gaming_sb_bets.sb_bet_id=gaming_sb_bet_singles.sb_bet_id

    AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID AND gaming_sb_bets.status_code!=1

  JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id AND gaming_sb_bet_singles.sb_selection_id=gaming_game_plays.sb_extra_id AND 

    gaming_game_plays.game_play_message_type_id=8 AND gaming_game_plays.payment_transaction_type_id=12

  JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id

  ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1; 
  

  
  IF (gamePlayID=-1) THEN

    SELECT gaming_sb_bets.sb_bet_id, gaming_game_plays.game_play_id, gaming_game_plays.game_play_id_win, gaming_game_plays.game_round_id, gaming_game_plays.session_id, gaming_game_plays.amount_total, gaming_game_plays.sb_bet_id, 

      gaming_game_plays.sb_extra_id, gaming_game_plays.game_play_message_type_id, gaming_game_plays.device_type, gaming_game_rounds.num_transactions,gaming_sb_bet_multiples.num_singles

    INTO sbBetID, gamePlayID, winGamePlayID, gameRoundID, sessionID, betTotal, sbBetID, sbExtraID, gamePlayMessageTypeID, deviceType, numTransactions,NumSingles

    FROM gaming_sb_bet_multiples 

    JOIN gaming_sb_bets ON gaming_sb_bet_multiples.bet_ref=betRef AND gaming_sb_bets.sb_bet_id=gaming_sb_bet_multiples.sb_bet_id

      AND gaming_sb_bets.game_manufacturer_id=gameManufacturerID AND gaming_sb_bets.status_code!=1 

    JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id AND gaming_sb_bet_multiples.sb_multiple_type_id=gaming_game_plays.sb_extra_id AND 

      gaming_game_plays.game_play_message_type_id=10 AND gaming_game_plays.payment_transaction_type_id=12

    JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id

    ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1; 
  END IF;
  
   IF (gamePlayID=-1 OR IFNULL(winGamePlayID,-1)=-1) THEN

    SET statusCode=2;

    LEAVE root;

  END IF;

  
  SELECT SUM(amount_total),license_type_id,exchange_rate INTO winAmount,licenseTypeID,exchangeRate
  FROM gaming_game_plays WHERE game_round_id = gameRoundID AND payment_Transaction_type_id IN (46,13);

  SET cancelAmount = winAmount;

  

  IF (bonusEnabledFlag) THEN 

    

    SET cancelBonusWinLocked = 0; 
    SET cancelBonus = 0;

    SET cancelReal = winAmount;
    SET @cancelBonus = 0;
    SET @cancelBonusWinLocked = 0;
	SET @bonusTransfered = 0;
	SET @cancelFromRealWinLocked = 0;
	SET @cancelFromRealBonus = 0;
	SET @bonusLostWhenTransferedToReal = 0;
	SET @cancelBonusTemp =0;
	SET @cancelBonusWLTemp =0;
	SET @canceledReal =0;
	SET @canceledRealWL =0;

    

    SET @numPlayBonusInstances=0;

    SELECT COUNT(*) INTO @numPlayBonusInstances

    FROM gaming_game_plays_bonus_instances_wins 

    WHERE win_game_play_id=winGamePlayID; 
    

    IF (@numPlayBonusInstances>0) THEN

      SET @bonusDeduct=cancelBonus;

      SET @bonusWinLockedDeduct=cancelBonusWinLocked;

      

      INSERT INTO gaming_game_plays_win_counter (date_created, game_round_id) VALUES (NOW(), gameRoundID);

      SET gamePlayWinCounterID=LAST_INSERT_ID();

      

      
		INSERT INTO gaming_game_plays_bonus_instances_wins (game_play_win_counter_id, game_play_bonus_instance_id, bonus_instance_id, bonus_rule_id, timestamp, exchange_rate, win_real, win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, client_stat_id, win_game_play_id, add_wager_contribution)
		SELECT gamePlayWinCounterID,game_play_bonus_instance_id,bonus_instance_id,bonus_rule_id, NOW(),exchange_rate,win_real,win_bonus,win_bonus_win_locked,lost_win_bonus,lost_win_bonus_win_locked,client_stat_id,winGamePlayID,add_wager_contribution
		FROM (

			SELECT ggpbiw.game_play_bonus_instance_id, ggpbiw.bonus_instance_id, ggpbiw.bonus_rule_id, exchange_rate,
				SUM(win_real*-1) AS win_real,
				IF(gbi.bonus_amount_remaining<SUM(win_bonus),gbi.bonus_amount_remaining,SUM(win_bonus))*-1 AS win_bonus,
				@canceledReal:=IF(gbi.bonus_amount_remaining<SUM(win_bonus),@canceledReal+SUM(win_bonus)-gbi.bonus_amount_remaining,@canceledReal),
				IF(gbi.current_win_locked_amount<SUM(win_bonus_win_locked),gbi.current_win_locked_amount,SUM(win_bonus_win_locked))*-1 AS win_bonus_win_locked,
				@canceledRealWL:=IF(gbi.current_win_locked_amount- @canceledReal<SUM(win_bonus_win_locked),@canceledRealWL - @canceledReal + SUM(win_bonus_win_locked) - gbi.bonus_amount_remaining,@canceledReal),
				SUM(lost_win_bonus*-1) AS lost_win_bonus, SUM(lost_win_bonus_win_locked*-1) AS lost_win_bonus_win_locked, ggpbiw.client_stat_id, add_wager_contribution*-1 AS add_wager_contribution

			FROM gaming_game_plays_bonus_instances_wins AS ggpbiw
			JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id = ggpbiw.bonus_instance_id
			WHERE ggpbiw.win_game_play_id=winGamePlayID
			GROUP BY ggpbiw.bonus_instance_id
		) AS ggpbiw;

            


      
      UPDATE gaming_game_plays_bonus_instances

      JOIN gaming_bonus_instances ON gaming_game_plays_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id

	  SET

        gaming_game_plays_bonus_instances.win_bonus=IF(gaming_bonus_instances.is_active=1, 0, gaming_game_plays_bonus_instances.win_bonus), 

        gaming_game_plays_bonus_instances.win_bonus_win_locked=IF(gaming_bonus_instances.is_active=1, 0, gaming_game_plays_bonus_instances.win_bonus_win_locked), 

        gaming_game_plays_bonus_instances.win_real=IF(gaming_bonus_instances.is_active=1, 0, gaming_game_plays_bonus_instances.win_real),

        gaming_game_plays_bonus_instances.lost_win_bonus=IF(gaming_bonus_instances.is_active=1, 0, gaming_game_plays_bonus_instances.lost_win_bonus), 

        gaming_game_plays_bonus_instances.lost_win_bonus_win_locked=IF(gaming_bonus_instances.is_active=1, 0, gaming_game_plays_bonus_instances.lost_win_bonus_win_locked)

      WHERE 

        gaming_game_plays_bonus_instances.game_play_id=gamePlayID;

        

      UPDATE gaming_bonus_instances

      JOIN 

      (

			SELECT ggpbiw.bonus_instance_id, 
				@cancelBonusTemp := IF (is_secured=0 OR is_lost=0, IF(gbi.bonus_amount_remaining<win_bonus,gbi.bonus_amount_remaining,win_bonus),0) AS win_bonus_deduct,
		 		@cancelFromRealBonus := IF (is_lost=0, @cancelFromRealBonus,@cancelFromRealBonus + @cancelBonusTemp),
				@cancelBonus := IF (is_lost=0, @cancelBonus + @cancelBonusTemp,@cancelBonus),
				@bonusLostWhenTransferedToReal := IF(is_secured=0,@bonusLostWhenTransferedToReal,ROUND(@bonusLostWhenTransferedToReal+(lost_win_bonus_win_locked+lost_win_bonus),0)),
				@cancelBonusWLTemp := IF (is_secured=0 OR is_lost=0, IF(gbi.current_win_locked_amount<win_bonus_win_locked,gbi.current_win_locked_amount,win_bonus_win_locked),0) AS win_bonus_win_locked_deduct,
		  		@cancelFromRealWinLocked := IF (is_lost=0, @cancelFromRealWinLocked,@cancelFromRealWinLocked + @cancelBonusWLTemp),
				@cancelBonusWinLocked := IF (is_lost=0, @cancelBonusWinLocked + @cancelBonusWLTemp,@cancelBonusWinLocked),
				add_wager_contribution AS remove_from_wagering
			FROM gaming_game_plays_bonus_instances_wins AS ggpbiw
			JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id = ggpbiw.bonus_instance_id
			WHERE ggpbiw.win_game_play_id=winGamePlayID AND game_play_win_counter_id=gamePlayWinCounterID

      ) AS PB ON gaming_bonus_instances.bonus_instance_id=PB.bonus_instance_id  

      SET 

        bonus_amount_remaining=bonus_amount_remaining+PB.win_bonus_deduct,

        current_win_locked_amount=current_win_locked_amount+PB.win_bonus_win_locked_deduct,

        total_amount_won=0,

        
        bonus_wager_requirement=IF(gaming_bonus_instances.is_active, bonus_wager_requirement-remove_from_wagering,bonus_wager_requirement),
		bonus_wager_requirement_remain=IF(gaming_bonus_instances.is_active, bonus_wager_requirement_remain-remove_from_wagering,bonus_wager_requirement_remain);

		SET cancelReal = cancelReal + @cancelBonus + @cancelBonusWinLocked + @cancelFromRealBonus+@bonusLostWhenTransferedToReal +@cancelFromRealWinLocked - ROUND(@canceledRealWL,0);

      

    END IF; 

  

  ELSE 
    SET cancelReal=winAmount;

    SET cancelBonus=0; SET cancelBonusWinLocked=0; 
	SET @cancelBonus = 0;
    SET @cancelBonusWinLocked = 0;

    SET @cancelBonusLost=0; SET @cancelBonusWinLockedLost=0;

  END IF; 
  

  SET cancelAmountBase=ROUND(cancelAmount/exchangeRate,5);
  
  
  IF (taxEnabled) THEN
	SELECT bet_total, win_total, amount_tax_operator, amount_tax_player, bet_real, win_real
	INTO roundBetTotal, roundWinTotal, taxAlreadyChargedOperator, taxAlreadyChargedPlayer, roundBetTotalReal, roundWinTotalReal
	FROM gaming_game_rounds
	WHERE game_round_id=gameRoundID;

	SELECT clients_locations.country_id, gaming_countries.sports_tax INTO countryID, sportsTaxCountryEnabled  
	FROM clients_locations
	JOIN gaming_countries ON gaming_countries.country_id = clients_locations.country_id
	WHERE clients_locations.client_id = clientID AND clients_locations.is_primary = 1;
	  
	SET amountTaxPlayer = 0.0;
	SET amountTaxOperator = 0.0;
	SET taxModificationOperator = 0.0;
	SET taxModificationPlayer = 0.0;

	IF (countryID > 0 AND sportsTaxCountryEnabled = 1) THEN
	  
	  SELECT country_tax_id, bet_tax, win_tax, apply_net_deduction, tax_paid_by_operator_win INTO countryTaxID, taxBet, taxWin, applyNetDeduction, winTaxPaidByOperator
	  FROM gaming_country_tax AS gct
	  WHERE gct.country_id = countryID AND gct.is_current =  1 AND gct.licence_type_id = licenseTypeID AND gct.is_active = 1 LIMIT 1;
    
	  SET roundWinTotalFull = roundWinTotalReal - cancelReal; 

	  IF(countryTaxID > 0) THEN
		  IF(roundWinTotalFull > 0) THEN
			 IF(applyNetDeduction = 1) THEN
				IF(winTaxPaidByOperator = 0) THEN
					SET amountTaxPlayer = ABS(roundWinTotalFull - roundBetTotalReal) * taxWin; 
					SET amountTaxOperator = 0.0;
				ELSE 
					SET amountTaxPlayer = 0.0;
					SET amountTaxOperator = ABS(roundWinTotalFull - roundBetTotalReal) * taxWin; 
				END IF;
			ELSE 
				IF(winTaxPaidByOperator = 0) THEN
					SET amountTaxPlayer = ABS(roundWinTotalFull) * taxWin; 
					SET amountTaxOperator = 0.0;
				ELSE 
					SET amountTaxPlayer = 0.0;
					SET amountTaxOperator = ABS(roundWinTotalFull) * taxWin; 
				END IF;
			END IF;
		   ELSE
				SET amountTaxPlayer = 0.0;
				SET amountTaxOperator = roundBetTotalReal * taxWin;
		   END IF; 
	   END IF; 
    END IF; 
  END IF; 

  SET taxModificationOperator = amountTaxOperator - taxAlreadyChargedOperator;
  SET taxModificationPlayer = amountTaxPlayer - taxAlreadyChargedPlayer;
  
   UPDATE gaming_client_stats AS gcs

  LEFT JOIN gaming_client_sessions AS gcsession ON gcsession.session_id=sessionID   

  LEFT JOIN gaming_client_wager_stats AS gcws ON gcws.client_stat_id=clientStatID AND gcws.client_wager_type_id=clientWagerTypeID

  SET 

    gcs.total_real_won=gcs.total_real_won-cancelReal, gcs.current_real_balance=gcs.current_real_balance-cancelReal - taxModificationPlayer, 

    gcs.total_bonus_won=gcs.total_bonus_won+@cancelBonus, gcs.current_bonus_balance=gcs.current_bonus_balance+@cancelBonus, 

    gcs.total_bonus_win_locked_won=gcs.total_bonus_win_locked_won+@cancelBonusWinLocked, gcs.current_bonus_win_locked_balance=current_bonus_win_locked_balance+@cancelBonusWinLocked, 

    gcs.total_real_won_base=gcs.total_real_won_base-(cancelReal/exchangeRate), gcs.total_bonus_won_base=gcs.total_bonus_won_base+((@cancelBonus+@cancelBonusWinLocked)/exchangeRate), gcs.total_tax_paid = gcs.total_tax_paid + taxModificationPlayer,

    
    gcsession.total_win=gcsession.total_win-cancelAmount, gcsession.total_win_base=gcsession.total_win_base-cancelAmountBase, gcsession.total_win_real=gcsession.total_win_real-cancelReal, gcsession.total_win_bonus=gcsession.total_win_bonus-(@cancelBonus+@cancelBonusWinLocked),

    
    gcws.num_wins=gcws.num_wins-IF(cancelAmount>0, 1, 0), gcws.total_real_won=gcws.total_real_won-cancelReal, gcws.total_bonus_won=gcws.total_bonus_won-(@cancelBonus+@cancelBonusWinLocked)

  WHERE gcs.client_stat_id=clientStatID;  

  

  
  INSERT INTO gaming_game_plays 

  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_other, bonus_lost, bonus_win_locked_lost, jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, game_round_id, payment_transaction_type_id, is_win_placed, is_processed, balance_real_after, balance_bonus_after, currency_id, round_transaction_no, gaming_game_plays.game_play_message_type_id, sb_extra_id, sb_bet_id, license_type_id, device_type,pending_bet_real, pending_bet_bonus, amount_tax_operator, amount_tax_player,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 

  SELECT cancelAmount*-1, cancelAmountBase*-1, exchange_rate, cancelReal*-1, @cancelBonus, @cancelBonusWinLocked, amount_other, @cancelFromRealBonus, @cancelFromRealWinLocked, 0, NOW(), gameManufacturerID, clientID, clientStatID, gameRoundID, gaming_payment_transaction_type.payment_transaction_type_id, 1, 1, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, currencyID, numTransactions+1, gaming_game_plays.game_play_message_type_id, sbExtraID, sbBetID, licenseTypeID, gaming_game_plays.device_type,pending_bets_real, pending_bets_bonus, taxModificationOperator, taxModificationPlayer,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)

  FROM gaming_payment_transaction_type

  JOIN gaming_client_stats ON gaming_payment_transaction_type.name='WinCancelled' AND gaming_client_stats.client_stat_id=clientStatID

  JOIN gaming_game_plays ON gaming_game_plays.game_play_id=winGamePlayID

  LEFT JOIN gaming_game_play_message_types ON gaming_game_play_message_types.game_play_message_type_id=IF(gamePlayMessageTypeID=8,12,13);
  

  SET gamePlayIDReturned=LAST_INSERT_ID();
  
  CALL GameUpdateRingFencedBalances(clientStatID,gamePlayIDReturned);  

  
  INSERT INTO gaming_game_plays_sb (game_play_id, payment_transaction_type_id, amount_total, amount_total_base, amount_real, amount_real_base, amount_bonus, amount_bonus_base, timestamp, exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, sb_bet_type, device_type, units)

  SELECT gamePlayIDReturned, payment_transaction_type_id, cancelAmount*-1/NumSingles, cancelAmountBase*-1/NumSingles, cancelReal*-1/NumSingles, cancelReal/exchange_rate*-1/NumSingles, (@cancelBonus + @cancelBonusWinLocked)/NumSingles, (@cancelBonus + @cancelBonusWinLocked)/exchange_rate/NumSingles, NOW(), exchange_rate, game_manufacturer_id, client_id, client_stat_id, currency_id, country_id, round_transaction_no, sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id, sb_bet_id, sb_multiple_type_id, liveBetType, deviceType, units

  FROM gaming_game_plays_sb

  WHERE (game_play_id=gamePlayID OR game_play_id=winGamePlayID) AND payment_transaction_type_id=13 
  GROUP BY sb_sport_id, sb_region_id, sb_group_id, sb_event_id, sb_market_id, sb_selection_id;

  

  
  IF (playLimitEnabled AND cancelAmount>0) THEN 

    CALL PlayLimitsUpdate(clientStatID, 'sportsbook', winAmount*-1, 0);

  END IF;

  

  
  
  UPDATE gaming_game_rounds AS ggr

  SET 

    ggr.win_total=win_total-cancelAmount, win_total_base=ROUND(win_total_base-cancelAmountBase,5), win_real=win_real-cancelReal, win_bonus=win_bonus-cancelBonus, win_bonus_win_locked=win_bonus_win_locked-cancelBonusWinLocked, win_bet_diffence_base=win_total_base-bet_total_base,

    ggr.num_transactions=ggr.num_transactions+1, ggr.amount_tax_operator = amountTaxOperator, ggr.amount_tax_player = amountTaxPlayer


  WHERE game_round_id=gameRoundID;

  

  
  UPDATE gaming_game_plays SET is_win_placed=0 WHERE game_play_id=gamePlayID;

	INSERT INTO gaming_sb_bet_history (sb_bet_id, sb_bet_transaction_type_id, timestamp, amount, transaction_ref, game_play_id, sb_extra_id) 
	SELECT sbBetID, sb_bet_transaction_type_id, NOW(), winAmount*-1, transactionRef, gamePlayIDReturned, sbExtraID
	FROM gaming_sb_bet_transaction_types WHERE name='CancelWin';

	  

  
  CALL CommonWalletSBReturnTransactionData(gamePlayIDReturned, sbBetID, sbExtraID, 'Win', clientStatID);

  

  IF (cancelBet) THEN

    CALL PlaceSBBetCancel(clientStatID, gamePlayID,gameRoundID, betTotal, 1, deviceType, @gamePlayIDReturned, @statusCode);

  END IF;

  

END root$$

DELIMITER ;

