DROP procedure IF EXISTS `BonusOnLostUpdateStats`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusOnLostUpdateStats`(
  bonusLostCounterID BIGINT, bonusLostType VARCHAR(80), extraID BIGINT, sessionID BIGINT, 
  forfeitReason VARCHAR(80), isExternal TINYINT(1), uniqueTransactionRef VARCHAR(45))
BEGIN

	DECLARE WagerType VARCHAR(20); 
	DECLARE TransactionType, freeRoundStatus VARCHAR(45);
    DECLARE notificationEnabled, isPortal TINYINT(1) DEFAULT 0;

    SET @bonusLostCounterID=bonusLostCounterID;

	SELECT value_string INTO WagerType FROM gaming_settings WHERE name = 'PLAY_WAGER_TYPE';
   
	IF(isExternal) THEN 
		Set @TransactionType='BonusLostExternal';
	ELSE
		Set @TransactionType='BonusLost';
	END IF;
    
   IF (bonusLostType in ( 'ForfeitByPlayer', 'ExternalLost', 'TransactionWithdraw'))  THEN
		SET isPortal = 1;
	ELSE
		SET isPortal = 0;
    END IF;
   
  INSERT INTO gaming_bonus_losts (bonus_instance_id, client_stat_id, bonus_lost_type_id, bonus_amount, bonus_win_locked_amount, extra_id, date_time_lost, session_id, bonus_lost_counter_id,bonuses_left_for_player,ring_fenced_amount, current_free_rounds_amount, current_free_rounds_num, current_free_rounds_win_locked)   
  SELECT gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.client_stat_id, gaming_bonus_lost_types.bonus_lost_type_id, bonus_amount_remaining, current_win_locked_amount, extraID, NOW(), sessionID, bonusLostCounterID,IFNULL(numBonuses,0),IFNULL(current_ring_fenced_amount,0),  IfNULL(free_rounds_remaining * cost_per_round, 0), IFNULL(free_rounds_remaining, 0), IFNULL(win_total, 0)
  FROM gaming_bonus_lost_counter_bonus_instances AS lost_bonuses
  STRAIGHT_JOIN gaming_bonus_instances ON 
	lost_bonuses.bonus_lost_counter_id=@bonusLostCounterID AND 
    lost_bonuses.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
  STRAIGHT_JOIN gaming_bonus_lost_types 
  LEFT JOIN gaming_cw_free_rounds on gaming_cw_free_rounds.cw_free_round_id = gaming_bonus_instances.cw_free_round_id
  LEFT JOIN
  (
	SELECT COUNT(1) AS numBonuses,gaming_bonus_instances.client_stat_id 
    FROM gaming_bonus_lost_counter_bonus_instances FORCE INDEX (PRIMARY)
	STRAIGHT_JOIN gaming_bonus_instances AS lost_bonus ON 
		bonus_lost_counter_id=@bonusLostCounterID AND
		gaming_bonus_lost_counter_bonus_instances.bonus_instance_id=lost_bonus.bonus_instance_id
	STRAIGHT_JOIN gaming_bonus_instances ON 
		lost_bonus.client_stat_id = gaming_bonus_instances.client_stat_id AND 
		gaming_bonus_instances.is_active AND gaming_bonus_instances.is_freebet_phase=0
	WHERE gaming_bonus_instances.bonus_instance_id NOT IN
	(
		SELECT bonus_instance_id FROM gaming_bonus_lost_counter_bonus_instances WHERE bonus_lost_counter_id=@bonusLostCounterID 
	)
	GROUP BY gaming_bonus_instances.client_stat_id
  ) AS bonusesLeftForPlayer ON gaming_bonus_instances.client_stat_id = bonusesLeftForPlayer.client_stat_id
 WHERE gaming_bonus_lost_types.name=bonusLostType;
   
  IF (WagerType = 'Type1') THEN
	  UPDATE  
	  (
		SELECT gaming_bonus_losts.client_stat_id, SUM(bonus_amount) AS bonus_amount, SUM(bonus_win_locked_amount) AS bonus_win_locked_amount, 
			   SUM(gaming_bonus_losts.current_free_rounds_amount) AS free_rounds_amount, SUM(gaming_bonus_losts.current_free_rounds_num) AS free_rounds_num, SUM(gaming_bonus_losts.current_free_rounds_win_locked) AS free_rounds_win
		FROM gaming_bonus_losts 
		WHERE bonus_lost_counter_id=@bonusLostCounterID
		GROUP BY gaming_bonus_losts.client_stat_id
	  ) AS XX 
      JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=XX.client_stat_id
	  SET 
		current_bonus_balance 			 					 = current_bonus_balance-bonus_amount, 
		current_bonus_win_locked_balance 					 = current_bonus_win_locked_balance-bonus_win_locked_amount,
		gaming_client_stats.current_free_rounds_amount		 = gaming_client_stats.current_free_rounds_amount - free_rounds_amount, 
		gaming_client_stats.current_free_rounds_num          = gaming_client_stats.current_free_rounds_num - free_rounds_num, 
		gaming_client_stats.current_free_rounds_win_locked   = gaming_client_stats.current_free_rounds_win_locked - free_rounds_win,
        
		gaming_client_stats.session_id	 = sessionID;
  ELSE
		UPDATE 
        (
			SELECT gaming_bonus_instances.bonus_instance_id AS BonusInstanceID,gaming_client_stats.bet_from_real
			FROM gaming_bonus_losts FORCE INDEX (bonus_lost_counter_id)
			STRAIGHT_JOIN gaming_bonus_instances ON 
				gaming_bonus_losts.bonus_lost_counter_id=@bonusLostCounterID 
				AND gaming_bonus_losts.client_stat_id = gaming_bonus_instances.client_stat_id AND gaming_bonus_instances.is_active=1 
			STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_bonus_instances.client_stat_id
			GROUP BY gaming_bonus_instances.client_stat_id
			HAVING 
				MIN(CAST(CONCAT(CAST(UNIX_TIMESTAMP(gaming_bonus_instances.given_date) AS CHAR(20)),
					CAST(gaming_bonus_instances.bonus_instance_id AS CHAR (20))) AS UNSIGNED INTEGER))
		) AS lost_top_bonus
        STRAIGHT_JOIN gaming_bonus_instances ON 
			gaming_bonus_instances.bonus_instance_id = lost_top_bonus.BonusInstanceID
		SET gaming_bonus_instances.bet_from_real = lost_top_bonus.bet_from_real;
		
		UPDATE  
		(
			SELECT gaming_bonus_losts.client_stat_id, SUM(bonus_amount) AS bonus_amount, SUM(bonus_win_locked_amount) AS bonus_win_locked_amount ,SUM(deposited_amount) AS deposited_amount,bonuses_left_for_player,
			IFNULL(SUM(IF(ring_fenced_by_bonus_rules,current_ring_fenced_amount,0)),0) AS bon_ring_fenced_amount,IFNULL(SUM(IF(ring_fenced_by_license_type=3,current_ring_fenced_amount,0)),0) AS ring_fenced_sb,
			IFNULL(SUM(IF(ring_fenced_by_license_type=1,current_ring_fenced_amount,0)),0) AS ring_fenced_casino,IFNULL(SUM(IF(ring_fenced_by_license_type=2,current_ring_fenced_amount,0)),0) AS ring_fenced_poker,
			SUM(gaming_bonus_losts.current_free_rounds_amount) AS free_rounds_amount, SUM(gaming_bonus_losts.current_free_rounds_num) AS free_rounds_num, SUM(gaming_bonus_losts.current_free_rounds_win_locked) AS free_rounds_win
			FROM gaming_bonus_losts FORCE INDEX (bonus_lost_counter_id)
			STRAIGHT_JOIN gaming_bonus_instances ON 
				gaming_bonus_losts.bonus_lost_counter_id=@bonusLostCounterID AND
				gaming_bonus_losts.bonus_instance_id = gaming_bonus_instances.bonus_instance_id
			LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules_deposits.bonus_rule_id = gaming_bonus_instances.bonus_rule_id
			GROUP BY gaming_bonus_losts.client_stat_id
		) AS XX 
        STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=XX.client_stat_id
		SET 
			current_bonus_balance=current_bonus_balance-bonus_amount, 
			current_bonus_win_locked_balance=current_bonus_win_locked_balance-bonus_win_locked_amount,
			gaming_client_stats.session_id=sessionID,
			gaming_client_stats.current_ring_fenced_sb = current_ring_fenced_sb-ring_fenced_sb,
			gaming_client_stats.current_ring_fenced_casino = current_ring_fenced_casino-ring_fenced_casino,
			gaming_client_stats.current_ring_fenced_poker = current_ring_fenced_poker-ring_fenced_poker,
			gaming_client_stats.current_ring_fenced_amount = gaming_client_stats.current_ring_fenced_amount-bon_ring_fenced_amount,
			gaming_client_stats.current_free_rounds_amount		 = gaming_client_stats.current_free_rounds_amount - free_rounds_amount, 
			gaming_client_stats.current_free_rounds_num          = gaming_client_stats.current_free_rounds_num - free_rounds_num, 
			gaming_client_stats.current_free_rounds_win_locked   = gaming_client_stats.current_free_rounds_win_locked - free_rounds_win,
			bet_from_real = IF(bonuses_left_for_player=0,0,IF(bet_from_real-XX.deposited_amount<0,0,bet_from_real-XX.deposited_amount));
            
  END IF;
  
  
  SET freeRoundStatus= IF(bonusLostType='Expired', 'Expired', IF (bonusLostType = 'IsUsedAll', 'UsedAll', 'Forfeited'));

  UPDATE gaming_bonus_lost_counter_bonus_instances AS counter_instances 
  JOIN gaming_bonus_instances ON counter_instances.bonus_lost_counter_id=@bonusLostCounterID AND counter_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
  JOIN gaming_cw_free_rounds ON gaming_bonus_instances.cw_free_round_id = gaming_cw_free_rounds.cw_free_round_id
  LEFT JOIN gaming_cw_free_round_statuses AS fr_status ON fr_status.name=freeRoundStatus
  SET 
	gaming_cw_free_rounds.is_active=0,
	gaming_cw_free_rounds.cw_free_round_status_id=IFNULL(fr_status.cw_free_round_status_id, 6);

	IF (bonusLostType = 'IsUsedAll') THEN
	
		UPDATE gaming_bonus_losts FORCE INDEX (bonus_lost_counter_id)
		STRAIGHT_JOIN gaming_bonus_instances ON
			gaming_bonus_losts.bonus_lost_counter_id=@bonusLostCounterID AND
			gaming_bonus_instances.bonus_instance_id=gaming_bonus_losts.bonus_instance_id  
		SET 
			bonus_amount_remaining=0, 
			current_win_locked_amount=0, 
			gaming_bonus_instances.is_active=0,
			gaming_bonus_instances.current_ring_fenced_amount = 0,
			is_used_all=1, 

			used_all_date=NOW(),
			gaming_bonus_instances.session_id=sessionID,
			forfeit_reason='IsUsedAll';
  
	ELSE
	  UPDATE gaming_bonus_losts 
	  STRAIGHT_JOIN gaming_bonus_instances ON
		gaming_bonus_losts.bonus_lost_counter_id=@bonusLostCounterID AND
		gaming_bonus_instances.bonus_instance_id=gaming_bonus_losts.bonus_instance_id  
	  SET 
		bonus_amount_remaining=0, 
		current_win_locked_amount=0, 
		gaming_bonus_instances.is_active=0,
		gaming_bonus_instances.current_ring_fenced_amount = 0,
		is_lost=1, 
		lost_date=NOW(),
		gaming_bonus_instances.session_id=sessionID,
		forfeit_reason=forfeitReason;
	
  
	  INSERT INTO gaming_transactions
	  (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus,extra2_id,unique_transaction_ref) 
	  SELECT gaming_payment_transaction_type.payment_transaction_type_id, (XX.bonus_amount+XX.bonus_win_locked_amount)*-1, ROUND(((XX.bonus_amount+XX.bonus_win_locked_amount)*-1)/gaming_operator_currency.exchange_rate, 5), gaming_client_stats.currency_id, gaming_operator_currency.exchange_rate, 0, XX.bonus_amount*-1, XX.bonus_win_locked_amount*-1, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, @bonusLostCounterID, pending_bets_real, pending_bets_bonus,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`),gaming_bonus_instances.bonus_instance_id,uniqueTransactionRef
	  FROM 
	  (
			SELECT gaming_bonus_losts.bonus_instance_id, SUM(bonus_amount) AS bonus_amount, SUM(bonus_win_locked_amount) AS bonus_win_locked_amount 
			FROM gaming_bonus_losts 
			WHERE bonus_lost_counter_id=@bonusLostCounterID
			GROUP BY gaming_bonus_losts.bonus_instance_id
	  ) AS XX
	  STRAIGHT_JOIN gaming_bonus_instances ON XX.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
	  STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=@TransactionType
	  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=gaming_bonus_instances.client_stat_id 
	  STRAIGHT_JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id;
	  
	  INSERT INTO gaming_game_plays 
	  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus,amount_free_bet, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, IF(is_free_bonus = 1 OR gaming_bonus_types_awarding.name = 'FreeBet',amount_bonus,0), amount_bonus_win_locked, timestamp, client_id, gaming_transactions.client_stat_id, gaming_transactions.payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, gaming_transactions.currency_id, gaming_transactions.session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,gaming_transactions.loyalty_points,gaming_transactions.loyalty_points_after,gaming_transactions.loyalty_points_bonus,gaming_transactions.loyalty_points_after_bonus
	  FROM gaming_transactions  FORCE INDEX (extra_id)
	  STRAIGHT_JOIN gaming_payment_transaction_type ON 
		gaming_transactions.extra_id=@bonusLostCounterID AND
		gaming_payment_transaction_type.name=@TransactionType AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
	  STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id =  gaming_transactions.extra2_id
	  STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
	  STRAIGHT_JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id;

	  SET @ringFencedEnabled=0;
	  SELECT value_bool INTO @ringFencedEnabled FROM gaming_settings WHERE name='RING_FENCED_ENABLED'; 

	  IF (@ringFencedEnabled=1) THEN
		  INSERT INTO 	gaming_game_play_ring_fenced 
						(game_play_id,ring_fenced_sb_after,ring_fenced_casino_after,ring_fenced_poker_after,ring_fenced_pb_after)
		  SELECT gaming_game_plays.game_play_id, gaming_client_stats.current_ring_fenced_sb, gaming_client_stats.current_ring_fenced_casino, gaming_client_stats.current_ring_fenced_poker, 0
		  FROM gaming_transactions FORCE INDEX (extra_id)
		  STRAIGHT_JOIN gaming_payment_transaction_type ON 
			gaming_transactions.extra_id=@bonusLostCounterID AND
			gaming_payment_transaction_type.name=@TransactionType AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
		  STRAIGHT_JOIN gaming_game_plays FORCE INDEX (transaction_id) ON gaming_transactions.transaction_id=gaming_game_plays.transaction_id
		  STRAIGHT_JOIN gaming_client_stats ON gaming_game_plays.client_stat_id=gaming_client_stats.client_stat_id
		  ON DUPLICATE KEY UPDATE   
				`ring_fenced_sb_after`=values(`ring_fenced_sb_after`), 
				`ring_fenced_casino_after`=values(`ring_fenced_casino_after`),  
				`ring_fenced_poker_after`=values(`ring_fenced_poker_after`), 
				`ring_fenced_pb_after`=values(`ring_fenced_pb_after`);
	  END IF;
  END IF;

    SELECT value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';
    IF (notificationEnabled) THEN
    	INSERT INTO notifications_events (notification_event_type_id, event_id, is_portal, is_processing) 
		SELECT 300, bonusLostCounterID, isPortal, 0 ON DUPLICATE KEY UPDATE is_processing=0;
	END IF;
    
    
END$$

DELIMITER ;

