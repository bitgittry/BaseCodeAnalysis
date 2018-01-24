-- -------------------------------------
-- SportBookRequestCashback.sql
-- -------------------------------------
DROP procedure IF EXISTS `SportBookRequestCashback`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SportBookRequestCashback`(sbCashbackRequestID BIGINT, userID BIGINT, sessionID BIGINT, promotionID BIGINT, varReason TEXT, refundMultiples TINYINT(1), refundLimitPerClient TINYINT(1), cashbackType VARCHAR(40), cashbackPercentage DECIMAL(18,5), sbEventID BIGINT, sbMarketID BIGINT, sbSelectionID BIGINT, bonusRuleID BIGINT, partialPercentage DECIMAL(18,5), OUT statusCode INT)
root:BEGIN
  
  DECLARE lockID, arrayCounterID, bonusRuleAwardCounterID BIGINT DEFAULT -1;
  DECLARE clientStatID, gamePlayID, gameRoundID, gamePlayIDReturned BIGINT DEFAULT -1;
  DECLARE betToCancelAmount DECIMAL(18,5) DEFAULT 0;
  DECLARE noMoreRecords TINYINT(1) DEFAULT 0;
  DECLARE sbBetTypeID TINYINT(4) DEFAULT 0;
  DECLARE selectionToCancel BIGINT DEFAULT -1;

  DECLARE inUse TINYINT(1) DEFAULT 0;
  DECLARE cancelBetCursor CURSOR FOR 
    SELECT gcrb.client_stat_id, gcrb.game_play_id, gcrb.amount_total, ggp.game_round_id
		FROM gaming_sb_cashback_request_bets AS gcrb
	JOIN gaming_game_plays AS ggp ON gcrb.game_play_id = ggp.game_play_id
		WHERE ggp.payment_transaction_type_id=12 AND ggp.is_win_placed=0 AND gcrb.amount_total>0;
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;
  
  SET cashbackPercentage=IFNULL(cashbackPercentage, 1);
  SET cashbackPercentage=IF(cashbackPercentage>1, 1, cashbackPercentage);
  
  SELECT lock_id, in_use INTO lockID, inUse FROM gaming_locks WHERE name='sports_book_cashback_lock' FOR UPDATE;
  
  IF (inUse) THEN 
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (cashbackType NOT IN ('CancelBet', 'Bonus', 'PartialCancelAndBonus')) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  IF (cashbackType='Bonus' AND bonusRuleID IS NULL) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF (sbEventID IS NULL AND sbMarketID IS NULL AND sbSelectionID IS NULL) THEN
    SET statusCode=4;
    LEAVE root;
  END IF;
  
  UPDATE gaming_locks SET in_use=1 WHERE name='sports_book_cashback_lock';
  
  COMMIT AND CHAIN;
  
  IF (sbCashbackRequestID IS NULL) THEN
    INSERT INTO gaming_sb_cashback_requests (user_id, session_id, promotion_id, cashback_type, refund_multiples, refund_limit_per_client, cashback_percentage, sb_event_id, sb_market_id, sb_selection_id, bonus_rule_id, partial_percentage, reason, timestamp)
    SELECT userID, sessionID, promotionID, cashbackType, refundMultiples, refundLimitPerClient, cashbackPercentage, sbEventID, sbMarketID, sbSelectionID, bonusRuleID, partialPercentage, varReason, NOW();
    SET sbCashbackRequestID=LAST_INSERT_ID();
  END IF;
  

  INSERT INTO gaming_sb_cashback_request_bets (sb_cashback_request_id, client_stat_id, game_play_id, amount_total, amount_real, amount_bonus, amount_bonus_win_locked)
  SELECT sbCashbackRequestID, ggps.client_stat_id, ggps.game_play_id, 
    LEAST(IFNULL(null, ggps.amount_total*cashbackPercentage), ggps.amount_total*cashbackPercentage), 
    ggps.amount_real, ggps.amount_bonus, ggp.amount_bonus_win_locked
  FROM gaming_game_plays as ggp
  JOIN gaming_game_plays_sb as ggps ON ggp.game_play_id=ggps.game_play_id AND (ggps.sb_selection_id=sbSelectionID OR ggps.sb_market_id=sbMarketID OR ggps.sb_event_id=sbEventID)
	AND ggp.is_win_placed=0 AND ggp.payment_transaction_type_id=12 AND ggps.sb_multiple_type_id=(SELECT sb_multiple_type_id FROM gaming_sb_multiple_types as gsmt WHERE gsmt.name = "Single" AND ggps.game_manufacturer_id = gsmt.game_manufacturer_id)
  JOIN gaming_client_stats ON ggp.client_stat_id=gaming_client_stats.client_stat_id
  LEFT JOIN gaming_sb_cashback_request_restrictions AS restriction ON restriction.sb_cashback_request_id=sbCashbackRequestID AND restriction.currency_id=gaming_client_stats.currency_id
  LEFT JOIN gaming_promotions_player_statuses ON gaming_promotions_player_statuses.promotion_id=promotionID AND gaming_promotions_player_statuses.client_stat_id=gaming_client_stats.client_stat_id AND gaming_promotions_player_statuses.is_active
  WHERE (promotionID IS NULL OR promotionID IN(0,-1)) OR gaming_promotions_player_statuses.promotion_player_status_id IS NOT NULL;

  SET @rowCount=ROW_COUNT();
  
  IF (refundMultiples) THEN
    INSERT INTO gaming_sb_cashback_request_bets (sb_cashback_request_id, client_stat_id, game_play_id, amount_total, amount_real, amount_bonus, amount_bonus_win_locked)
    SELECT sbCashbackRequestID, gaming_game_plays.client_stat_id, gaming_game_plays.game_play_id, 
      LEAST(IFNULL(restriction.amount, gaming_game_plays.amount_total*cashbackPercentage),gaming_game_plays.amount_total*cashbackPercentage) AS cancelAmount, gaming_game_plays.amount_real, gaming_game_plays.amount_bonus, gaming_game_plays.amount_bonus_win_locked
    FROM (
      SELECT sb_bet_multiple_id FROM gaming_sb_selections  
      JOIN gaming_sb_bet_multiples_singles ON (gaming_sb_selections.sb_selection_id=sbSelectionID OR gaming_sb_selections.sb_market_id=sbMarketID OR gaming_sb_selections.sb_event_id=sbEventID) 
       AND gaming_sb_bet_multiples_singles.sb_selection_id=gaming_sb_selections.sb_selection_id 
      GROUP BY sb_bet_multiple_id
    ) AS MultipleSingles
    JOIN gaming_sb_bet_multiples ON MultipleSingles.sb_bet_multiple_id=gaming_sb_bet_multiples.sb_bet_multiple_id
    JOIN gaming_sb_multiple_types ON gaming_sb_bet_multiples.sb_multiple_type_id=gaming_sb_multiple_types.sb_multiple_type_id
    JOIN gaming_sb_bets ON gaming_sb_bets.sb_bet_id=gaming_sb_bet_multiples.sb_bet_id
	JOIN gaming_game_plays_sb ON gaming_sb_bets.sb_bet_id=gaming_game_plays_sb.sb_bet_id AND gaming_game_plays_sb.sb_multiple_type_id = gaming_sb_multiple_types.sb_multiple_type_id
    JOIN gaming_game_plays ON gaming_game_plays.game_play_id=gaming_game_plays_sb.game_play_id AND gaming_game_plays.is_win_placed=0 AND gaming_game_plays.payment_transaction_type_id=12 AND gaming_game_plays.game_play_message_type_id=10   
    JOIN gaming_client_stats ON gaming_game_plays.client_stat_id=gaming_client_stats.client_stat_id
    LEFT JOIN gaming_sb_cashback_request_restrictions AS restriction ON restriction.sb_cashback_request_id=sbCashbackRequestID AND restriction.currency_id=gaming_client_stats.currency_id
    LEFT JOIN gaming_promotions_player_statuses ON gaming_promotions_player_statuses.promotion_id=promotionID AND gaming_promotions_player_statuses.client_stat_id=gaming_client_stats.client_stat_id AND gaming_promotions_player_statuses.is_active
    WHERE (promotionID IS NULL OR promotionID IN(0,-1)) OR gaming_promotions_player_statuses.promotion_player_status_id IS NOT NULL
	ON DUPLICATE KEY UPDATE game_play_id = VALUES(game_play_id),
							amount_total = VALUES(amount_total),
							amount_real = VALUES(amount_real),
							amount_bonus = VALUES(amount_bonus),
							amount_bonus_win_locked = VALUES(amount_bonus_win_locked);
  
    SET @rowCount=@rowCount+ROW_COUNT();
  END IF;
  
  IF (refundLimitPerClient) THEN 
    SET @clientStatIDCur=0; 
    SET @curLimitAmount=0;
    UPDATE gaming_sb_cashback_request_bets AS cashback_request_bets
    JOIN 
    (
      SELECT @curLimitAmount:=IF(@clientStatIDCur!=client_stat_id, limit_amount, @curLimitAmount) AS reset_limit, LEAST(@curLimitAmount, amount_total) AS amount_total, @curLimitAmount:=@curLimitAmount-LEAST(@curLimitAmount, amount_total) AS remaining_limit, @clientStatIDCur:=client_stat_id AS client_stat_id, game_play_id 
      FROM (
        SELECT cashback_request_bets.game_play_id, cashback_request_bets.client_stat_id, cashback_request_bets.amount_total, request_restrictions.amount AS limit_amount 
        FROM gaming_sb_cashback_request_bets  AS cashback_request_bets
        JOIN gaming_client_stats ON cashback_request_bets.client_stat_id=gaming_client_stats.client_stat_id
        JOIN gaming_sb_cashback_request_restrictions AS request_restrictions ON request_restrictions.sb_cashback_request_id=sbCashbackRequestID AND gaming_client_stats.currency_id=request_restrictions.currency_id
        WHERE cashback_request_bets.sb_cashback_request_id=sbCashbackRequestID ORDER BY cashback_request_bets.client_stat_id, cashback_request_bets.amount_total DESC
      ) AS Bets
    ) AS UpdateValues ON cashback_request_bets.sb_cashback_request_id=sbCashbackRequestID AND cashback_request_bets.game_play_id=UpdateValues.game_play_id
    SET cashback_request_bets.amount_total=UpdateValues.amount_total
    WHERE UpdateValues.amount_total!=cashback_request_bets.amount_total;
  END IF;
  
  IF (@rowCount = 0) THEN
    UPDATE gaming_locks SET in_use=0 WHERE name='sports_book_cashback_lock';
    SET statusCode=5;
    
    COMMIT AND CHAIN;
    LEAVE root;
  END IF;

  SELECT sb_selection_id INTO selectionToCancel FROM gaming_game_plays_sb WHERE (sb_selection_id=sbSelectionID OR sb_market_id=sbMarketID OR sb_event_id=sbEventID) LIMIT 1;

  IF (cashbackType IN ('CancelBet','PartialCancelAndBonus')) THEN
    OPEN cancelBetCursor;
    cancelBetsLabel: LOOP 
      SET noMoreRecords=0;
      
      FETCH cancelBetCursor INTO clientStatID, gamePlayID, betToCancelAmount, gameRoundID;
      IF (noMoreRecords) THEN
        LEAVE cancelBetsLabel;
      END IF;		 
      
      SELECT sb_bet_type_id INTO sbBetTypeID FROM gaming_sb_bets WHERE wager_game_play_id = gamePlayID;

      SET betToCancelAmount=betToCancelAmount*IFNULL(partialPercentage,1);      
      CALL PlaceSBBetCancel(clientStatID, gamePlayID, gameRoundID, betToCancelAmount, sbBetTypeID, 1, selectionToCancel, refundMultiples, gamePlayIDReturned, statusCode);

      IF (statusCode > 0) THEN
		UPDATE gaming_locks SET in_use=0 WHERE name='sports_book_cashback_lock';
		LEAVE root;
	  END IF;

      COMMIT AND CHAIN;
    END LOOP cancelBetsLabel;
    CLOSE cancelBetCursor;  
  END IF; 
  
  IF (cashbackType IN ('Bonus','PartialCancelAndBonus')) THEN
    SET betToCancelAmount=betToCancelAmount*(1-IFNULL(partialPercentage,0));
    
    INSERT INTO gaming_bonus_rule_award_counter(bonus_rule_id, date_created)
    SELECT bonusRuleID, NOW();
    
    SET bonusRuleAwardCounterID=LAST_INSERT_ID();
      
    INSERT INTO gaming_bonus_instances (priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, bonus_rule_award_counter_id, transfer_every_x, transfer_every_amount, session_id, reason) 
    SELECT priority, bonus_amount, bonus_amount, bonus_amount*wager_requirement_multiplier, bonus_amount*wager_requirement_multiplier, NOW(), expiry_date, bonus_rule_id, client_stat_id, bonusRuleAwardCounterID, transfer_every_x, transfer_every_amount, sessionID, 'Sports Book Cashback'
    FROM
    (
      SELECT gaming_bonus_rules.priority, bonus_amount, IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, 
        gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_rules.bonus_rule_id, XX.client_stat_id,
        CASE gaming_bonus_types_release.name
          WHEN 'EveryXWager' THEN gaming_bonus_rules.transfer_every_x_wager
          WHEN 'EveryReleaseAmount' THEN ROUND(gaming_bonus_rules.wager_requirement_multiplier/(XX.bonus_amount/wager_restrictions.release_every_amount),2)
          ELSE NULL
        END AS transfer_every_x, 
        CASE gaming_bonus_types_release.name
          WHEN 'EveryXWager' THEN ROUND(XX.bonus_amount/(gaming_bonus_rules.wager_requirement_multiplier/gaming_bonus_rules.transfer_every_x_wager), 0)
          WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
          ELSE NULL
        END AS transfer_every_amount
      FROM
      (
        SELECT client_stat_id, SUM(cashback_bets.amount_total*(1-IFNULL(partialPercentage,0))) AS bonus_amount
        FROM gaming_sb_cashback_request_bets AS cashback_bets 
        WHERE cashback_bets.sb_cashback_request_id=sbCashbackRequestID AND amount_total>0  
        GROUP BY client_stat_id 
      ) AS XX
      JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id=bonusRuleID
      JOIN gaming_client_stats ON XX.client_stat_id=gaming_client_stats.client_stat_id
      LEFT JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
      LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
      LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
    ) AS XX;
   
    SET @rowCount=ROW_COUNT();
    
    IF (@rowCount > 0) THEN      
      INSERT INTO gaming_bonus_rule_award_counter_client_stats(bonus_rule_award_counter_id, bonus_instance_id, client_stat_id)
      SELECT bonusRuleAwardCounterID, gaming_bonus_instances.bonus_instance_id, gaming_client_stats.client_stat_id
      FROM gaming_client_stats 
      JOIN gaming_bonus_instances ON 
        gaming_bonus_instances.bonus_rule_award_counter_id=bonusRuleAwardCounterID AND 
        gaming_bonus_instances.client_stat_id=gaming_client_stats.client_stat_id
      FOR UPDATE;
        
      CALL BonusOnAwardedUpdateStatsMultipleBonuses(bonusRuleAwardCounterID, 1);
      
      DELETE FROM gaming_bonus_rule_award_counter_client_stats
      WHERE bonus_rule_award_counter_id=bonusRuleAwardCounterID;      
    END IF;
    
    COMMIT AND CHAIN;
  END IF; 
  
  UPDATE gaming_game_plays 
  JOIN gaming_sb_cashback_request_bets AS cashback_bets ON cashback_bets.sb_cashback_request_id=sbCashbackRequestID AND 
    cashback_bets.game_play_id=gaming_game_plays.game_play_id AND gaming_game_plays.is_win_placed=0
  SET is_win_placed=1, is_processed=1;
  
  UPDATE gaming_locks SET in_use=0 WHERE name='sports_book_cashback_lock';
  
  COMMIT AND CHAIN;
  
  SET statusCode=0;
END root$$

DELIMITER ;
