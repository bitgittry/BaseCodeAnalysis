DROP procedure IF EXISTS `PlayCloseRound`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayCloseRound`(
  gameRoundID BIGINT, checkWinZero TINYINT(1), checkRoundFinishMessage TINYINT(1), returnData TINYINT(1))
root:BEGIN
  
  -- fully optimized
  -- Included bonus used_all and is_active=0 while cathering for both Type1 and Type2
  
  DECLARE gameRoundIDCheck, clientStatID, clientID, operatorGameID BIGINT DEFAULT -1;
  DECLARE isOpen, isWinPlaced, taxEnabled, bonusesUsedAllWhenZero, playerHasZeroBalance, 
	allowSetUsedAll, playerHasActiveBonuses, possibleHasWins TINYINT(1) DEFAULT 0;
  DECLARE gamePlayID, sessionID, gameSessionID, currencyID BIGINT DEFAULT -1; 
  DECLARE isMessageRoundFinished TINYINT(1) DEFAULT 1;
  DECLARE roundBetTotal, roundWinTotal, exchangeRate, taxAmount, taxOnReturn,
	roundBetTotalReal, roundWinTotalReal DECIMAL(18, 5) DEFAULT 0; 
  DECLARE taxAppliedOnType, wagerType VARCHAR(20) DEFAULT NULL;
  DECLARE taxCycleID, licenseTypeID INT DEFAULT NULL;
  
  SELECT game_round_id, client_stat_id, operator_game_id, NOT is_round_finished, 
	bet_total, win_total, bet_real, win_real, license_type_id, num_transactions>1 
  INTO gameRoundIDCheck, clientStatID, operatorGameID, isOpen, 
	roundBetTotal, roundWinTotal, roundBetTotalReal, roundWinTotalReal, licenseTypeID, possibleHasWins  
  FROM gaming_game_rounds 
  WHERE game_round_id=gameRoundID;

  SELECT client_stat_id, client_id, currency_id, (current_bonus_balance+current_real_balance+current_bonus_win_locked_balance)=0 
  INTO clientStatID, clientID, currencyID, playerHasZeroBalance
  FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
  
  SELECT exchange_rate INTO exchangeRate
  FROM gaming_operator_currency 
  STRAIGHT_JOIN gaming_operators ON gaming_operator_currency.currency_id=currencyID AND 
    gaming_operators.is_main_operator AND gaming_operator_currency.operator_id=gaming_operators.operator_id;
   
  IF (isOpen AND gameRoundID!=-1) THEN
    
	SELECT gs1.value_string AS vb1, gs2.value_bool AS vb2, gs3.value_bool AS vb3 
    INTO wagerType, taxEnabled, bonusesUsedAllWhenZero
	FROM gaming_settings gs1 
	STRAIGHT_JOIN gaming_settings gs2 ON gs2.name='TAX_ON_GAMEPLAY_ENABLED'
    STRAIGHT_JOIN gaming_settings gs3 ON gs3.name='TYPE_TWO_BONUSES_USED_ALL_WHEN_ZERO'
    WHERE gs1.name='PLAY_WAGER_TYPE';
    
    -- TAX
    IF (taxEnabled) THEN
    
		-- betTotal is the sum of gaming_games_plays.amount_total of the bets in this round not processed (is_win_place = 0)
		CALL TaxCalculateTax(licenseTypeID, clientStatID, clientID, roundWinTotalReal, roundBetTotalReal, taxAmount, taxAppliedOnType, taxCycleID);
        
    END IF; -- END TAX
    
    -- At every step if we are gonna place a win of 0 we will skip various logic as this will be done in the PlaceWin
    -- This includes 1. Having tax amount 2. Any bonuses to redeem
    
    SET checkWinZero = checkWinZero OR taxAmount > 0;
    
    IF (checkWinZero=0) THEN
    
		SET allowSetUsedAll=wagerType='Type1';
		SET @curUsedAll=0;
		SET @anyUsedAll=0;
		
		SET @curRedeemThreshold=0;
		SET @anyRedeemThreshold=0;
		
		UPDATE 
		(
		  SELECT play_bonuses.bonus_instance_id, COUNT(*) AS num_found, 
			-- used_all
			@curUsedAll:=((gbi.open_rounds-1)<=0 AND gbi.is_free_rounds_mode=0 AND ROUND(
				gbi.bonus_amount_remaining+gbi.current_win_locked_amount+gbi.reserved_bonus_funds)=0) AS now_used_all,
			@anyUsedAll:=@anyUsedAll OR @curUsedAll AS any_used_all,
			-- redeem threshould
			@curRedeemThreshold:=(IFNULL(gaming_bonus_rules.redeem_threshold_enabled, 0) = 1 AND IFNULL(gaming_bonus_rules.redeem_threshold_on_deposit, 0) = 0 AND
				restrictions.redeem_threshold >= (gbi.bonus_amount_remaining+gbi.current_win_locked_amount) AND (gbi.open_rounds-1)<=0) AS redeem_bonus,
			@anyRedeemThreshold:=@anyRedeemThreshold OR @curRedeemThreshold AS any_reedem_bonus
		  FROM gaming_game_plays FORCE INDEX (game_round_id)
		  STRAIGHT_JOIN gaming_game_plays_bonus_instances AS play_bonuses ON 
			gaming_game_plays.game_round_id=gameRoundID AND
			play_bonuses.game_play_id=gaming_game_plays.game_play_id
		  STRAIGHT_JOIN gaming_bonus_instances AS gbi ON 
			gbi.bonus_instance_id=play_bonuses.bonus_instance_id
		  STRAIGHT_JOIN gaming_bonus_rules ON 
			gaming_bonus_rules.bonus_rule_id=gbi.bonus_rule_id 
		  LEFT JOIN gaming_bonus_rules_wager_restrictions AS restrictions ON 
			restrictions.bonus_rule_id=gbi.bonus_rule_id AND restrictions.currency_id=currencyID
		  GROUP BY play_bonuses.bonus_instance_id
		) AS BB
		STRAIGHT_JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id=BB.bonus_instance_id
		SET gbi.open_rounds=gbi.open_rounds-1,
			gbi.is_used_all=IF(gbi.is_active=1 AND BB.now_used_all AND allowSetUsedAll, 1, gbi.is_used_all),
			gbi.used_all_date=IF(BB.now_used_all AND used_all_date IS NULL, NOW(), used_all_date),
			gbi.is_active=IF(BB.now_used_all AND allowSetUsedAll, 0, gbi.is_active)
		WHERE @anyRedeemThreshold=0;
        
        SET checkWinZero=checkWinZero OR @anyRedeemThreshold;
		
        IF (checkWinZero=0) THEN
    
			IF (wagerType='Type2' AND bonusesUsedAllWhenZero AND playerHasZeroBalance AND @anyUsedAll) THEN

				SELECT IF (COUNT(1) > 0, 1, 0) 
				INTO playerHasActiveBonuses 
				FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses) 
				WHERE client_stat_id = clientStatID AND is_active = 1;

				IF (playerHasActiveBonuses) THEN 
					CALL BonusForfeitBonus(sessionID, clientStatID, 0, 0, 'IsUsedAll', 'TYPE_TWO_BONUSES_USED_ALL_WHEN_ZERO - Used All');
				END IF;
			END IF;
			
			UPDATE gaming_game_rounds SET date_time_end=NOW(), is_round_finished=1, is_cancelled=(num_bets=0), is_processed=IF(num_bets=0, 1, is_processed) 
			WHERE game_round_id=gameRoundID; 
            
		END IF;
    
    END IF;
    
    IF (checkWinZero OR taxAmount > 0) THEN
     
      SELECT game_play_id, session_id, game_session_id
      INTO gamePlayID, sessionID, gameSessionID
      FROM gaming_game_plays FORCE INDEX (game_round_id)
      STRAIGHT_JOIN gaming_game_rounds ON gaming_game_plays.game_round_id = gaming_game_rounds.game_round_id AND gaming_game_rounds.is_round_finished = 0
      STRAIGHT_JOIN gaming_payment_transaction_type AS transaction_type ON 
        (transaction_type.name='Bet' AND gaming_game_plays.payment_transaction_type_id=transaction_type.payment_transaction_type_id) 
      WHERE gaming_game_plays.game_round_id = gameRoundID
      ORDER BY game_play_id DESC LIMIT 1;
      
      IF (gamePlayID!=-1) THEN
        
        SET @winAmount=0;
        SET @clearBonusLost=1; SET @winTransactionRef=NULL; SET @closeRound=1; 
        SET @returnData=0; SET @minimalData=1;
        SET @gamePlayIDReturned=NULL; SET @winStatusCode=0;
		
        IF (wagerType='Type2') THEN
        
			CALL PlaceWinTypeTwo(
				gameRoundID, sessionID, gameSessionID, @winAmount, @clearBonusLost, @winTransactionRef, 
				@closeRound, 0, @returnData, @minimalData, @gamePlayIDReturned, @winStatusCode); 
                
		ELSE
		
			CALL PlaceWin(
				gameRoundID, sessionID, gameSessionID, @winAmount, @clearBonusLost, @winTransactionRef, 
				@closeRound, 0, @returnData, @minimalData, @gamePlayIDReturned, @winStatusCode); 
                
		END IF; 
        
		SET isWinPlaced=@gamePlayIDReturned IS NOT NULL;
        
      END IF;
    END IF;
   
  
  END IF; -- END IF
   
  IF (NOT isWinPlaced AND possibleHasWins) THEN
    
      SET gamePlayID=-1;
      SELECT game_play_id, message_type.is_round_finished
      INTO gamePlayID, isMessageRoundFinished
      FROM gaming_game_plays FORCE INDEX (game_round_id)
      STRAIGHT_JOIN gaming_payment_transaction_type AS transaction_type ON 
		 gaming_game_plays.payment_transaction_type_id=transaction_type.payment_transaction_type_id AND transaction_type.name='Win'
      STRAIGHT_JOIN gaming_game_play_message_types AS message_type ON 
		gaming_game_plays.game_play_message_type_id=message_type.game_play_message_type_id
	  WHERE gaming_game_plays.game_round_id=gameRoundID
      ORDER BY gaming_game_plays.game_play_id DESC LIMIT 1;  
      
      SET @gamePlayIDReturned = gamePlayID;
      
      IF (gamePlayID!=-1 AND isMessageRoundFinished=0) THEN
        SET @messageType=IF(roundWinTotal<=roundBetTotal,'HandLoses','HandWins');
        UPDATE gaming_game_plays
        STRAIGHT_JOIN gaming_game_play_message_types AS message_type ON 
			gaming_game_plays.game_play_id=gamePlayID AND message_type.name=@messageType
        SET gaming_game_plays.game_play_message_type_id=message_type.game_play_message_type_id;
      END IF;
  END IF;
  
  IF (returnData) THEN

	CALL PlayReturnPlayBalanceData(clientStatID, operatorGameID);

    SELECT gameRoundID AS game_round_id;

  END IF;
  
END root$$

DELIMITER ;

