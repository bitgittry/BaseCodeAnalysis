DROP procedure IF EXISTS `CommonWalletFinSoftReturnFunds`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletFinSoftReturnFunds`(transactionRef VARCHAR(40), clientStatID BIGINT, returnAmount DECIMAL(18,5), refundReason TINYINT(4), canCommit TINYINT(1), returnData TINYINT(1), OUT statusCode INT)
root: BEGIN
  -- Calling FundsReturnBonusCashExchange without quotes

  DECLARE sbBetID, currencyID, clientID,x,gamePlayID BIGINT DEFAULT -1;
  DECLARE tranStatusCode, prevStatusCode INT DEFAULT 0;
  DECLARE gameManufacturer VARCHAR(20) DEFAULT 'FinSoft';
  DECLARE gameManufacturerID BIGINT DEFAULT 7; 
  DECLARE amountTotal, amountFreeBet, amountReal, amountBonus, amountBonusWinLocked, cancelFreeBet,
			cancelRemain, cancelTotal, cancelReal, cancelBonus, cancelBonusWinLocked, exchangeRate DECIMAL(18,5) DEFAULT 0;
  SET statusCode=0;
  
  SELECT client_stat_id, client_id, currency_id INTO clientStatID, clientID, currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
  
  SELECT sb_bet_id, status_code, bet_total, amount_real, amount_bonus, amount_bonus_win_locked, amount_free_bet
  INTO sbBetID, tranStatusCode, amountTotal, amountReal, amountBonus, amountBonusWinLocked,amountFreeBet
  FROM gaming_sb_bets 
  WHERE transaction_ref=transactionRef AND game_manufacturer_id=gameManufacturerID ORDER BY timestamp DESC LIMIT 1;

  SET @bonusLost=0;
  SET @bonusWinLockedLost=0;
  SET @bonusTurnedReal=0;
  SET @bonusWinLockedTurnedReal=0;

  IF (sbBetID=-1) THEN
    SET statusCode=1;
  END IF;
  
  IF (returnAmount>amountTotal) THEN
    SET statusCode=2;
  END IF;
  
  IF (statusCode!=0) THEN
    IF (canCommit) THEN COMMIT AND CHAIN; END IF;
    CALL CommonWalletSBReturnData(sbBetID, clientStatID);
    LEAVE root;
  END IF;
  
  IF (amountTotal=returnAmount) THEN
    SET tranStatusCode=4; 
    SET cancelReal=amountReal;
    SET cancelBonus=amountBonus;
    SET cancelBonusWinLocked=amountBonusWinLocked;
  ELSE
    SET tranStatusCode=tranStatusCode; 
    SET cancelRemain=returnAmount;
    
    IF (cancelRemain>0) THEN
      SET cancelBonus=LEAST(cancelRemain, amountBonus-amountFreeBet);
      SET cancelRemain=cancelRemain-cancelBonus;
    END IF;
    
    IF (cancelRemain>0) THEN
      SET cancelBonusWinLocked=LEAST(cancelRemain, amountBonusWinLocked);
      SET cancelRemain=cancelRemain-cancelBonusWinLocked;
    END IF;
    
    IF (cancelRemain>0) THEN
      SET cancelReal=LEAST(cancelRemain, amountReal);
      SET cancelRemain=cancelRemain-cancelReal;
    END IF;

    IF (cancelRemain>0) THEN
      SET cancelFreeBet=LEAST(cancelRemain, amountFreeBet);
      SET cancelRemain=cancelRemain-cancelFreeBet;
    END IF;
  END IF;
    
  IF (cancelBonus+cancelBonusWinLocked+IFNULL(cancelFreeBet,0)>0) THEN
      
    SET @cancelBonusDeduct:=cancelBonus + cancelFreeBet;
    SET @cancelBonusWinLockedDeduct:=cancelBonusWinLocked;
    
    UPDATE gaming_sb_bets_bonuses
    JOIN
    (
      SELECT
        gaming_sb_bets_bonuses.bonus_instance_id, gaming_bonus_instances.is_active,gaming_bonus_instances.is_secured,
        @cancelBonus:=LEAST(gaming_sb_bets_bonuses.amount_bonus, @cancelBonusDeduct) AS cancel_bonus,
        @cancelBonusWinLocked:=LEAST(gaming_sb_bets_bonuses.amount_bonus_win_locked, @cancelBonusWinLockedDeduct) AS cancel_bonus_win_locked,
        @cancelBonusDeduct:=GREATEST(0, @cancelBonusDeduct-@cancelBonus) AS bonusDeductRemain, 
        @cancelBonusWinLockedDeduct:=GREATEST(0, @cancelBonusWinLockedDeduct-@cancelBonusWinLocked) AS bonusWinLockedRemain
      FROM gaming_sb_bets_bonuses
      JOIN gaming_bonus_instances ON gaming_sb_bets_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
      WHERE gaming_sb_bets_bonuses.sb_bet_id=sbBetID 
      HAVING cancel_bonus>0 OR cancel_bonus_win_locked>0
    ) AS XX ON gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND gaming_sb_bets_bonuses.bonus_instance_id=XX.bonus_instance_id    
    SET
      gaming_sb_bets_bonuses.amount_bonus=gaming_sb_bets_bonuses.amount_bonus-XX.cancel_bonus,
      gaming_sb_bets_bonuses.amount_bonus_win_locked=gaming_sb_bets_bonuses.amount_bonus_win_locked-XX.cancel_bonus_win_locked,
      gaming_sb_bets_bonuses.cancel_bonus=IF(XX.is_active=1, XX.cancel_bonus, 0), 
      gaming_sb_bets_bonuses.cancel_bonus_win_locked=IF(XX.is_active=1, XX.cancel_bonus_win_locked, 0), 
      gaming_sb_bets_bonuses.lost_bonus=IF(XX.is_active=0 AND XX.is_secured=0, XX.cancel_bonus, 0), 
      gaming_sb_bets_bonuses.lost_bonus_win_locked=IF(XX.is_active=0 AND XX.is_secured=0, XX.cancel_bonus_win_locked, 0),
      gaming_sb_bets_bonuses.turned_real_bonus=IF(XX.is_active=0 AND XX.is_secured=1, XX.cancel_bonus, 0), 
      gaming_sb_bets_bonuses.turned_real_bonus_win_locked=IF(XX.is_active=0 AND XX.is_secured=1, XX.cancel_bonus_win_locked, 0);
      
    SELECT SUM(IFNULL(lost_bonus,0)), SUM(IFNULL(lost_bonus_win_locked,0)) ,SUM(IFNULL(turned_real_bonus,0)), SUM(IFNULL(turned_real_bonus_win_locked,0))
    INTO @bonusLost, @bonusWinLockedLost,@bonusTurnedReal,@bonusWinLockedTurnedReal
    FROM gaming_sb_bets_bonuses
    WHERE gaming_sb_bets_bonuses.sb_bet_id=sbBetID; 
      
    SET cancelBonus=ABS(ROUND(cancelBonus-@bonusLost,0));
    SET cancelBonusWinLocked=ABS(ROUND(cancelBonusWinLocked-@bonusWinLockedLost,0));
        
    
    
    UPDATE gaming_bonus_instances
    JOIN gaming_sb_bets_bonuses ON 
      gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND
      gaming_bonus_instances.bonus_instance_id=gaming_sb_bets_bonuses.bonus_instance_id
    SET 
      bonus_amount_remaining=bonus_amount_remaining+IFNULL(cancel_bonus,0) ,
      current_win_locked_amount=current_win_locked_amount+IFNULL(cancel_bonus_win_locked,0),
	  reserved_bonus_funds = reserved_bonus_funds - IFNULL(cancel_bonus,0) -IFNULL(cancel_bonus_win_locked,0);
	--  is_used_all=0,used_all_date = NULL,
	--  is_active = IF(is_lost = 0 AND expiry_date > NOW(),1,0);
    
    IF (@bonusLost+@bonusWinLockedLost>0) THEN
      
      INSERT INTO gaming_bonus_losts (bonus_instance_id, client_stat_id, bonus_lost_type_id, bonus_amount, bonus_win_locked_amount, extra_id, date_time_lost, session_id)
      SELECT bonus_instance_id, client_stat_id, gaming_bonus_lost_types.bonus_lost_type_id, IFNULL(SUM(lost_bonus),0), IFNULL(SUM(lost_bonus_win_locked),0), NULL, NOW(), NULL
      FROM gaming_sb_bets_bonuses  
	  JOIN gaming_sb_bets ON gaming_sb_bets_bonuses.sb_bet_id = gaming_sb_bets.sb_bet_id
      JOIN gaming_bonus_lost_types ON gaming_bonus_lost_types.name='BetCancelledAfterLostOrSecured'
      WHERE gaming_sb_bets_bonuses.sb_bet_id=sbBetID AND (gaming_sb_bets_bonuses.lost_bonus!=0 OR gaming_sb_bets_bonuses.lost_bonus_win_locked!=0) 
      GROUP BY gaming_sb_bets_bonuses.bonus_instance_id;
    END IF;
  END IF;
  
  
  UPDATE gaming_sb_bets 
  SET bet_total=bet_total-returnAmount, amount_real=amount_real-cancelReal, amount_bonus=amount_bonus-cancelBonus-cancelFreeBet, 
	amount_bonus_win_locked=amount_bonus_win_locked-cancelBonusWinLocked, status_code=tranStatusCode, refund_reason_code=refundReason,
	amount_free_bet = amount_free_bet- cancelFreeBet
  WHERE sb_bet_id=sbBetID;
  
  UPDATE gaming_client_stats 
  SET current_real_balance=current_real_balance+cancelReal, current_bonus_balance=current_bonus_balance+cancelBonus+cancelFreeBet, current_bonus_win_locked_balance=current_bonus_win_locked_balance+cancelBonusWinLocked,
      pending_bets_real=pending_bets_real-cancelReal, pending_bets_bonus=pending_bets_bonus-(cancelBonus+cancelBonusWinLocked + cancelFreeBet + IFNULL(@bonusLost,0)+ IFNULL(@bonusWinLockedLost,0))
  WHERE client_stat_id = clientStatID;
  
  
  SELECT exchange_rate into exchangeRate 
  FROM gaming_client_stats
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id 
  WHERE gaming_client_stats.client_stat_id=clientStatID
  LIMIT 1;
  
  SET cancelTotal=cancelReal+cancelBonus+cancelBonusWinLocked;
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_other, bonus_lost, jackpot_contribution, timestamp, game_manufacturer_id, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, pending_bet_real, pending_bet_bonus, currency_id, sign_mult, sb_bet_id, license_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT cancelTotal, cancelTotal/exchangeRate, exchangeRate, cancelReal, cancelBonus+cancelFreeBet, cancelBonusWinLocked, 0, 0, 0, NOW(), gameManufacturerID, clientID, clientStatID, gaming_payment_transaction_type.payment_transaction_type_id, current_real_balance, current_bonus_balance+current_bonus_win_locked_balance, current_bonus_win_locked_balance, pending_bets_real, pending_bets_bonus, currencyID, 1, sbBetID, 3,0,gaming_client_stats.current_loyalty_points,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
  FROM gaming_payment_transaction_type
  JOIN gaming_client_stats ON gaming_payment_transaction_type.name='FundsReturnedSports' AND gaming_client_stats.client_stat_id=clientStatID;

	SET gamePlayID = LAST_INSERT_ID();

  CALL GameUpdateRingFencedBalances(clientStatID,gamePlayID);    
  
  INSERT INTO gaming_sb_bet_history (sb_bet_id, sb_bet_transaction_type_id, timestamp, amount) 
  SELECT sbBetID, sb_bet_transaction_type_id, NOW(), returnAmount
  FROM gaming_sb_bet_transaction_types WHERE name='ReturnFunds';

	IF (IFNULL(@bonusTurnedReal,0) + IFNULL(@bonusWinLockedTurnedReal,0) > 0) THEN
		CALL FundsReturnBonusCashExchange(clientStatID, gamePlayID, 0, 'BonusTurnedReal',exchangeRate ,
			IFNULL(@bonusTurnedReal,0) + IFNULL(@bonusWinLockedTurnedReal,0), IFNULL(@bonusTurnedReal,0), IFNULL(@bonusWinLockedTurnedReal,0) ,sbBetID);
	END IF;
  
  IF (canCommit) THEN COMMIT AND CHAIN; END IF;
  IF (returnData) THEN CALL CommonWalletSBReturnData(sbBetID, clientStatID); END IF;

END root$$

DELIMITER ;

