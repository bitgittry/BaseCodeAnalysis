DROP PROCEDURE IF EXISTS PlayerGetTrailByTrailID;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerGetTrailByTrailID`(licenseType BIGINT, trailID BIGINT)
BEGIN
SELECT * FROM 
(       SELECT -- Sportsbook 
		  gaming_game_plays.game_play_id AS trail_id,
		  gaming_game_plays.timestamp AS `timestamp`,
		  gaming_transactions.balance_history_id, gaming_payment_transaction_type.display_name AS `description`,
		  IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult > 0, gaming_game_plays.amount_real, NULL) AS `credit_real`,
		  ABS(IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult < 0, gaming_game_plays.amount_real, NULL)) AS `debit_real`,
		  IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult > 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-gaming_game_plays.amount_free_bet, 2), NULL) AS `credit_bonus`,
		  ABS(IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult < 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-gaming_game_plays.amount_free_bet, 2), NULL)) AS `debit_bonus`,
		  IF((gaming_game_plays.amount_free_bet)*gaming_game_plays.sign_mult > 0, ROUND(gaming_game_plays.amount_free_bet, 2), NULL) AS `credit_freebet`,
		  ABS(IF((gaming_game_plays.amount_free_bet)*gaming_game_plays.sign_mult < 0, ROUND(gaming_game_plays.amount_free_bet, 2), NULL)) AS `debit_freebet`,
		  gaming_game_plays.balance_real_after AS `balance_real`, gaming_game_plays.balance_bonus_after AS `balance_bonus`,
		  gaming_game_plays.pending_bet_real, gaming_game_plays.pending_bet_bonus,
		  gaming_game_plays.game_round_id AS `game_round_id`, gaming_game_plays.game_id, 
		  -- IF(gaming_payment_transaction_type.name='Win' AND gaming_game_rounds.bet_total>gaming_game_rounds.win_total AND gaming_game_plays.license_type_id NOT IN (6,7), 'Loss', IF(gaming_payment_transaction_type.is_user_adjustment_type, 'Adjustment', gaming_payment_transaction_type.name)) AS transaction_type, 
          CASE 
			WHEN gaming_payment_transaction_type.name = 'Win' AND gaming_game_rounds.win_total = 0 AND gaming_game_plays.license_type_id NOT IN (6,7) THEN 'Loss'
			WHEN gaming_payment_transaction_type.is_user_adjustment_type THEN 'Adjustment'
			WHEN (gaming_payment_transaction_type.name = 'Bet' OR gaming_payment_transaction_type.name = 'BetAdjustment') AND gaming_sb_bets.status_code = 3 THEN 'fundsreserved'
			ELSE gaming_payment_transaction_type.name
		  END AS transaction_type,
          gaming_license_type.name AS license_type,
		  gaming_game_plays.amount_total, gaming_game_rounds.bet_total, IF(play_messages.is_round_finished, gaming_game_rounds.win_total, NULL) AS win_total, IF(play_messages.is_round_finished OR play_messages.name='PJWin', jackpot_win, NULL) AS jackpot_win, play_messages.name AS play_message_type,
		  gaming_game_plays.loyalty_points, gaming_game_plays.loyalty_points_bonus, gaming_transactions.withdrawal_pending_after, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, gaming_payment_method.name AS payment_method,gaming_sb_bets.transaction_ref as manufacturer_transaction_id
	
		FROM gaming_lottery_dbg_tickets -- FORCE INDEX (lottery_coupon_id)
		LEFT JOIN gaming_sb_bets ON gaming_sb_bets.lottery_dbg_ticket_id = gaming_lottery_dbg_tickets.lottery_dbg_ticket_id  
		AND gaming_lottery_dbg_tickets.lottery_coupon_id = trailID
		JOIN gaming_game_plays ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id AND gaming_game_plays.license_type_id = 3 
		JOIN gaming_payment_transaction_type  FORCE INDEX (primary) ON
		  gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
		  gaming_payment_transaction_type.hide_from_player=0
		-- LEFT JOIN gaming_lottery_transactions ON gaming_lottery_transactions.game_play_id = gaming_game_plays.game_play_id  
		LEFT JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id

		LEFT JOIN gaming_transactions ON gaming_game_plays.transaction_id = gaming_transactions.transaction_id 
			  
		JOIN gaming_license_type ON gaming_game_plays.license_type_id = gaming_license_type.license_type_id 		
		LEFT JOIN gaming_game_play_message_types AS play_messages ON gaming_game_plays.game_play_message_type_id=play_messages.game_play_message_type_id
		
		LEFT JOIN gaming_balance_history ON gaming_balance_history.balance_history_id = gaming_transactions.balance_history_id
        LEFT JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = gaming_balance_history.payment_method_id AND (@payment_method IS NULL OR @payment_method = gaming_payment_method.name)
        
        -- WHERE gaming_game_plays.license_type_id = 3 -- AND 600000000000001 = gaming_lottery_dbg_tickets.lottery_coupon_id
		GROUP BY gaming_game_plays.game_play_id, gaming_game_plays.license_type_id 

		UNION ALL

		SELECT -- Lottery/SportsPool / Poker
		  gaming_game_plays.game_play_id AS trail_id,
		  gaming_game_plays.timestamp AS `timestamp`,
		  gaming_transactions.balance_history_id, gaming_payment_transaction_type.display_name AS `description`,
		  IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult > 0, gaming_game_plays.amount_real, NULL) AS `credit_real`,
		  ABS(IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult < 0, gaming_game_plays.amount_real, NULL)) AS `debit_real`,
		  IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult > 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-gaming_game_plays.amount_free_bet, 2), NULL) AS `credit_bonus`,
		  ABS(IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult < 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-gaming_game_plays.amount_free_bet, 2), NULL)) AS `debit_bonus`,
		  IF((gaming_game_plays.amount_free_bet)*gaming_game_plays.sign_mult > 0, ROUND(gaming_game_plays.amount_free_bet, 2), NULL) AS `credit_freebet`,
		  ABS(IF((gaming_game_plays.amount_free_bet)*gaming_game_plays.sign_mult < 0, ROUND(gaming_game_plays.amount_free_bet, 2), NULL)) AS `debit_freebet`,
		  gaming_game_plays.balance_real_after AS `balance_real`, gaming_game_plays.balance_bonus_after AS `balance_bonus`,
		  gaming_game_plays.pending_bet_real, gaming_game_plays.pending_bet_bonus,
		  gaming_game_plays.game_round_id AS `game_round_id`, gaming_game_plays.game_id, 
		  -- IF(gaming_payment_transaction_type.name='Win' AND gaming_game_rounds.bet_total>gaming_game_rounds.win_total AND gaming_game_plays.license_type_id NOT IN (6,7), 'Loss', IF(gaming_payment_transaction_type.is_user_adjustment_type, 'Adjustment', gaming_payment_transaction_type.name)) AS transaction_type, 
          CASE 
			WHEN gaming_payment_transaction_type.name = 'Win' AND gaming_game_rounds.bet_total>gaming_game_rounds.win_total AND gaming_game_plays.license_type_id NOT IN (6,7) THEN 'Loss'
			WHEN gaming_payment_transaction_type.is_user_adjustment_type THEN 'Adjustment'
			ELSE gaming_payment_transaction_type.name
		  END AS transaction_type,
          gaming_license_type.name AS license_type,
		  gaming_game_plays.amount_total, gaming_game_rounds.bet_total, IF(play_messages.is_round_finished, gaming_game_rounds.win_total, NULL) AS win_total, IF(play_messages.is_round_finished OR play_messages.name='PJWin', jackpot_win, NULL) AS jackpot_win, play_messages.name AS play_message_type,
		  gaming_game_plays.loyalty_points, gaming_game_plays.loyalty_points_bonus, gaming_transactions.withdrawal_pending_after, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, gaming_payment_method.name AS payment_method,gaming_lottery_transactions.lottery_transaction_idf as manufacturer_transaction_id
	
         FROM gaming_game_plays FORCE INDEX (sb_bet_id)
		 LEFT JOIN gaming_lottery_transactions ON gaming_lottery_transactions.game_play_id = gaming_game_plays.game_play_id 
		 -- Lottery/SportsPool / Poker
		 LEFT JOIN gaming_lottery_coupons ON gaming_game_plays.sb_bet_id=gaming_lottery_coupons.lottery_coupon_id
         AND gaming_lottery_coupons.num_tickets = 1

		 LEFT JOIN gaming_transactions ON gaming_game_plays.transaction_id = gaming_transactions.transaction_id 
		 JOIN gaming_payment_transaction_type  FORCE INDEX (primary) ON
		  gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
		  gaming_payment_transaction_type.hide_from_player=0 
		  
		JOIN gaming_license_type ON gaming_game_plays.license_type_id = gaming_license_type.license_type_id 
		
		LEFT JOIN gaming_game_play_message_types AS play_messages ON gaming_game_plays.game_play_message_type_id=play_messages.game_play_message_type_id
		LEFT JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
		LEFT JOIN gaming_balance_history ON gaming_balance_history.balance_history_id = gaming_transactions.balance_history_id
        LEFT JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = gaming_balance_history.payment_method_id AND (@payment_method IS NULL OR @payment_method = gaming_payment_method.name)        
        WHERE  gaming_game_plays.sb_bet_id = trailID AND gaming_game_plays.license_type_id IN (5,6,7) AND gaming_game_plays.license_type_id = licenseType 
        GROUP BY gaming_game_plays.game_play_id, gaming_game_plays.license_type_id
        
        UNION ALL
        
         SELECT -- Casino 
		  gaming_game_plays.game_play_id AS trail_id,
		  gaming_game_plays.timestamp AS `timestamp`,
		  gaming_transactions.balance_history_id, gaming_payment_transaction_type.display_name AS `description`,
		  IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult > 0, gaming_game_plays.amount_real, NULL) AS `credit_real`,
		  ABS(IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult < 0, gaming_game_plays.amount_real, NULL)) AS `debit_real`,
		  IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult > 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-gaming_game_plays.amount_free_bet, 2), NULL) AS `credit_bonus`,
		  ABS(IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult < 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-gaming_game_plays.amount_free_bet, 2), NULL)) AS `debit_bonus`,
		  IF((gaming_game_plays.amount_free_bet)*gaming_game_plays.sign_mult > 0, ROUND(gaming_game_plays.amount_free_bet, 2), NULL) AS `credit_freebet`,
		  ABS(IF((gaming_game_plays.amount_free_bet)*gaming_game_plays.sign_mult < 0, ROUND(gaming_game_plays.amount_free_bet, 2), NULL)) AS `debit_freebet`,
		  gaming_game_plays.balance_real_after AS `balance_real`, gaming_game_plays.balance_bonus_after AS `balance_bonus`,
		  gaming_game_plays.pending_bet_real, gaming_game_plays.pending_bet_bonus,
		  gaming_game_plays.game_round_id AS `game_round_id`, gaming_game_plays.game_id, 
		  -- IF(gaming_payment_transaction_type.name='Win' AND gaming_game_rounds.bet_total>gaming_game_rounds.win_total AND gaming_game_plays.license_type_id NOT IN (6,7), 'Loss', IF(gaming_payment_transaction_type.is_user_adjustment_type, 'Adjustment', gaming_payment_transaction_type.name)) AS transaction_type, 
          CASE 
			WHEN gaming_payment_transaction_type.name = 'Win' AND gaming_game_rounds.bet_total>gaming_game_rounds.win_total AND gaming_game_plays.license_type_id NOT IN (6,7) THEN 'Loss'
			WHEN gaming_payment_transaction_type.is_user_adjustment_type THEN 'Adjustment'
			ELSE gaming_payment_transaction_type.name
		  END AS transaction_type,
          gaming_license_type.name AS license_type,
		  gaming_game_plays.amount_total, gaming_game_rounds.bet_total, IF(play_messages.is_round_finished, gaming_game_rounds.win_total, NULL) AS win_total, IF(play_messages.is_round_finished OR play_messages.name='PJWin', jackpot_win, NULL) AS jackpot_win, play_messages.name AS play_message_type,
		  gaming_game_plays.loyalty_points, gaming_game_plays.loyalty_points_bonus, gaming_transactions.withdrawal_pending_after, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, gaming_payment_method.name AS payment_method, gaming_cw_transactions.transaction_ref as manufacturer_transaction_id
	
         FROM gaming_game_plays FORCE INDEX (game_round_id)
		 LEFT JOIN gaming_cw_transactions FORCE INDEX (game_play_id) ON gaming_cw_transactions.game_play_id = gaming_game_plays.game_play_id
		 LEFT JOIN gaming_transactions ON gaming_game_plays.transaction_id = gaming_transactions.transaction_id 
		 JOIN gaming_payment_transaction_type  FORCE INDEX (primary) ON
		  gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
		  gaming_payment_transaction_type.hide_from_player=0 
		  
		JOIN gaming_license_type ON gaming_game_plays.license_type_id = gaming_license_type.license_type_id 		
		LEFT JOIN gaming_game_play_message_types AS play_messages ON gaming_game_plays.game_play_message_type_id=play_messages.game_play_message_type_id
		LEFT JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
		LEFT JOIN gaming_balance_history ON gaming_balance_history.balance_history_id = gaming_transactions.balance_history_id
        LEFT JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = gaming_balance_history.payment_method_id AND (@payment_method IS NULL OR @payment_method = gaming_payment_method.name)
		
        WHERE  trailID = gaming_game_plays.game_round_id AND gaming_game_plays.license_type_id = licenseType AND gaming_game_plays.license_type_id IN (1,2)       
		GROUP BY gaming_game_plays.game_play_id, gaming_game_plays.license_type_id
        
        
 ) AS main
      ORDER BY  main.license_type,main.trail_id;
	
END$$

DELIMITER ;