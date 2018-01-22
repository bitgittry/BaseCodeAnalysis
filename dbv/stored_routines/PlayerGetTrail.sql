DROP procedure IF EXISTS `PlayerGetTrail`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerGetTrail`(clientStatID BIGINT, dateFrom DATETIME, dateTo DATETIME, perPage INT, pageNo INT, filter INT, channelCode VARCHAR(40), paymentMethod VARCHAR(80), statusCode VARCHAR(40), gameIDF VARCHAR(80))
BEGIN

  -- Optimized with Inner Query
  
  -- 0=all,1=casino/poker,2=sportsbook,3=transaction,4=bonuses,5=poolbetting,6=loyaltypoints,7-lottery anything else will be get all 

  -- super optimized  
  -- added lottery 
  -- Sports Book v2
  -- Sports Book Desription improvement
  -- Sports Cancel Improvement. Actually Sports Win anything other just display play message type
  
  DECLARE sportsBookActive, poolBettingActive, lotteryActive, sportsPoolActive TINYINT(1) DEFAULT 0;	
  DECLARE firstResult, countThreshold INT DEFAULT 0;

  SET @client_stat_id=clientStatID;
  SET @date_from=IFNULL(dateFrom, DATE_SUB(NOW(), INTERVAL 1 MONTH));
  SET @date_to=IFNULL(dateTo, NOW());
  SET @filter=IFNULL(filter, 0);
  
  SET @channel_code = channelCode;
  SET @payment_method = paymentMethod;
  SET @status_code = statusCode;
  SET @game_idf = gameIDF;
  
  SET @perPage=perPage; 
  SET @pageNo=pageNo;
  SET @firstResult=(@pageNo-1)*@perPage; 
 
  SET @a=@firstResult+1;
  SET @b=@firstResult+@perPage;
  SET @n=0;
  
  SET firstResult=@a-1;
  SET countThreshold=(perPage*10)+1;

  SET @convertDivide=100;
  SET @currencySymbol='';
  
  SELECT IFNULL(gs1.value_bool, 0), IFNULL(gs2.value_bool, 0), IFNULL(gs3.value_bool, 0), IFNULL(gs3.value_bool, 0)
  INTO sportsBookActive, poolBettingActive, lotteryActive, sportsPoolActive
  FROM gaming_settings gs1 
  STRAIGHT_JOIN gaming_settings gs2 ON gs2.name='POOL_BETTING_ACTIVE'
  STRAIGHT_JOIN gaming_settings gs3 ON gs3.name='LOTTO_ACTIVE'
  STRAIGHT_JOIN gaming_settings gs4 ON gs4.name='SPORTSPOOL_ACTIVE'
  WHERE gs1.name='SPORTSBOOK_ACTIVE';

  SELECT gaming_currency.symbol INTO @currencySymbol 
  FROM gaming_currency 
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gaming_currency.currency_id=gaming_client_stats.currency_id;
  -- SELECT IF(value_bool,100,1) INTO @convertExtenal FROM gaming_settings WHERE name='PORTAL_CONVERTION_USE_EXTERNAL_FORMAT';
  
  IF (@filter=0 AND
		((lotteryActive=0 AND sportsPoolActive=0) OR
		 (@status_code IS NULL AND @channel_code IS NULL AND @game_idf IS NULL IS NULL))
     ) THEN
  
	SELECT COUNT(*) AS num_transactions
	FROM gaming_game_plays FORCE INDEX (player_date)
	WHERE gaming_game_plays.client_stat_id=@client_stat_id AND gaming_game_plays.timestamp BETWEEN @date_from AND @date_to;
  
  ELSE
	  SELECT COUNT(*) AS num_transactions
	  FROM 
	  (
			SELECT game_play_id 
			FROM gaming_game_plays FORCE INDEX (player_date)
			WHERE gaming_game_plays.client_stat_id=@client_stat_id AND gaming_game_plays.timestamp BETWEEN @date_from AND @date_to
            ORDER BY gaming_game_plays.game_play_id DESC 
			LIMIT countThreshold
	  ) AS XX 
	  STRAIGHT_JOIN gaming_game_plays ON gaming_game_plays.game_play_id=XX.game_play_id
	  JOIN gaming_payment_transaction_type ON 
		gaming_game_plays.client_stat_id=@client_stat_id AND gaming_game_plays.timestamp BETWEEN @date_from AND @date_to AND
		gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
		gaming_payment_transaction_type.hide_from_player=0 AND (@filter=0 OR
		  IF(@filter=1,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id IN (1,2) AND gaming_game_plays.game_id IS NOT NULL,
			IF (@filter=2,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id =3 AND gaming_game_plays.sb_bet_id IS NOT NULL,
				IF (@filter=3,gaming_payment_transaction_type.player_trail_type_id IN (2,3),
					IF (@filter=4,gaming_payment_transaction_type.player_trail_type_id = 4 ,
						IF (@filter=5,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id =5,
							IF (@filter=6, gaming_game_plays.loyalty_points IS NOT NULL AND (gaming_game_plays.loyalty_points>0 OR gaming_game_plays.loyalty_points_bonus>0), 
								IF (@filter=7,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id = 6,
									IF (@filter=8,gaming_payment_transaction_type.payment_transaction_type_id NOT IN(238), 
										IF (@filter=9,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id = 7, 1=1))))))))))
		LEFT JOIN gaming_lottery_coupons ON gaming_lottery_coupons.lottery_coupon_id = gaming_game_plays.sb_bet_id 
		AND CASE @filter 
			WHEN 7 THEN gaming_game_plays.license_type_id = 6 
			WHEN 9 THEN gaming_game_plays.license_type_id = 7
			ELSE gaming_game_plays.license_type_id IN (6,7)
		END
		LEFT JOIN gaming_lottery_dbg_tickets ON gaming_lottery_dbg_tickets.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id
		LEFT JOIN gaming_games ON gaming_games.game_id = gaming_lottery_dbg_tickets.game_id AND gaming_games.game_manufacturer_id = gaming_lottery_dbg_tickets.game_manufacturer_id
		LEFT JOIN gaming_lottery_coupon_statuses ON gaming_lottery_coupon_statuses.lottery_coupon_status_id=gaming_lottery_coupons.lottery_coupon_status_id
		LEFT JOIN gaming_lottery_transactions ON gaming_lottery_transactions.lottery_coupon_id=gaming_lottery_coupons.lottery_coupon_id AND is_bet_transaction = 1
		LEFT JOIN gaming_lottery_channels ON gaming_lottery_channels.lottery_channel_id=gaming_lottery_transactions.lottery_channel_id
		WHERE (gaming_lottery_coupon_statuses.status_code = @status_code OR @status_code IS NULL) 
			AND (gaming_lottery_channels.channel_code = @channel_code OR @channel_code IS NULL)
			AND (gaming_games.manufacturer_game_idf = @game_idf OR @game_idf IS NULL);
  END IF;

  -- Actual Data

  IF (sportsBookActive=0 AND poolBettingActive=0 AND lotteryActive=0 AND sportsPoolActive=0) THEN
		-- casino, poker
		SELECT 
		  gaming_game_plays.game_play_id AS trail_id,
		  gaming_game_plays.timestamp AS `timestamp`,
		  gaming_transactions.balance_history_id,
		  IF(gaming_games.game_id IS NULL, 
			gaming_payment_transaction_type.display_name, 
			CONCAT(
				CONCAT(
					gaming_games.game_description,' - ',play_messages.message,' - ',
					  CASE play_messages.name
						WHEN 'HandWins' THEN CONCAT(IF(jackpot_win>0,CONCAT('Jackpot Win ',@currencySymbol,ROUND(jackpot_win/@convertDivide,2),' - '),''), 'Win ', @currencySymbol, ROUND((win_total-jackpot_win-bet_total)/@convertDivide,2),' - ','Bet ',@currencySymbol, ROUND(bet_total/@convertDivide,2))
						WHEN 'HandLoses' THEN CONCAT(IF(jackpot_win>0,CONCAT('Jackpot Win ',@currencySymbol,ROUND(jackpot_win/@convertDivide,2),' - '),''), 'Loses ', @currencySymbol, ROUND((bet_total-jackpot_win-win_total)/@convertDivide,2),' - ','Bet ',@currencySymbol, ROUND(bet_total/@convertDivide,2))
						ELSE CONCAT(@currencySymbol, ROUND(ABS(gaming_game_plays.amount_total)/@convertDivide,2))
					  END,
					IF (gaming_game_round_types.name IS NULL OR gaming_game_round_types.selector='N',
						'',
						CONCAT(' (', gaming_game_round_types.name,')')
					)
				)
			)) AS `description`,
		  IF(gaming_game_plays.amount_real * gaming_game_plays.sign_mult > 0, gaming_game_plays.amount_real, NULL) AS `credit_real`,
		  ABS(IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult < 0, gaming_game_plays.amount_real, NULL)) AS `debit_real`,
		  IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult > 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-amount_free_bet, 2), NULL) AS `credit_bonus`,
		  ABS(IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult < 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-amount_free_bet, 2), NULL)) AS `debit_bonus`,
		  IF((amount_free_bet)*gaming_game_plays.sign_mult > 0, ROUND(amount_free_bet, 2), NULL) AS `credit_freebet`,
		  ABS(IF((amount_free_bet)*gaming_game_plays.sign_mult < 0, ROUND(amount_free_bet, 2), NULL)) AS `debit_freebet`,
		  gaming_game_plays.balance_real_after AS `balance_real`, gaming_game_plays.balance_bonus_after AS `balance_bonus`,
		  gaming_game_plays.pending_bet_real, gaming_game_plays.pending_bet_bonus,
		  gaming_game_plays.game_round_id AS `game_round_id`, gaming_games.game_id, 
		  IF(gaming_payment_transaction_type.name='Win' AND bet_total>win_total AND gaming_license_type.license_type_id NOT IN (6, 7), 'Loss', IF(gaming_payment_transaction_type.is_user_adjustment_type, 'Adjustment', gaming_payment_transaction_type.name)) AS transaction_type, gaming_license_type.name AS license_type,
		  gaming_game_plays.amount_total, bet_total, IF(play_messages.is_round_finished, win_total, NULL) AS win_total, IF(play_messages.is_round_finished OR play_messages.name='PJWin', jackpot_win, NULL) AS jackpot_win, play_messages.name AS play_message_type,
		  gaming_game_plays.loyalty_points, gaming_game_plays.loyalty_points_bonus,gaming_transactions.withdrawal_pending_after, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, gaming_payment_method.name AS payment_method
		FROM 
		(
			SELECT game_play_id 
			FROM gaming_game_plays FORCE INDEX (player_date)
			WHERE gaming_game_plays.client_stat_id=@client_stat_id AND gaming_game_plays.timestamp BETWEEN @date_from AND @date_to
            ORDER BY gaming_game_plays.game_play_id DESC 
			LIMIT firstResult, perPage
		) AS XX 
		STRAIGHT_JOIN gaming_game_plays ON gaming_game_plays.game_play_id=XX.game_play_id
		JOIN gaming_payment_transaction_type ON 
		  gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
		  gaming_payment_transaction_type.hide_from_player=0 AND (@filter=0 OR 
		  IF(@filter=1,gaming_payment_transaction_type.player_trail_type_id = 1 AND (gaming_game_plays.license_type_id IN (1,2))  AND gaming_game_plays.game_id IS NOT NULL,
			IF (@filter=2,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id =3 AND gaming_game_plays.sb_bet_id IS NOT NULL,
				IF (@filter=3,gaming_payment_transaction_type.player_trail_type_id IN (2,3),
					IF (@filter=4,gaming_payment_transaction_type.player_trail_type_id = 4 ,
						IF (@filter=5,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id =5,
							IF (@filter=6, gaming_game_plays.loyalty_points IS NOT NULL AND (gaming_game_plays.loyalty_points>0 OR gaming_game_plays.loyalty_points_bonus>0), 
								IF (@filter=7,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id = 6, 
									IF (@filter=8,gaming_payment_transaction_type.payment_transaction_type_id NOT IN(238),
										IF (@filter=9,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id = 7, 1=1))))))))))
		JOIN gaming_license_type ON gaming_game_plays.license_type_id = gaming_license_type.license_type_id
        LEFT JOIN gaming_transactions ON gaming_game_plays.transaction_id = gaming_transactions.transaction_id
		LEFT JOIN gaming_games ON gaming_game_plays.game_id=gaming_games.game_id
		LEFT JOIN gaming_game_play_message_types AS play_messages ON gaming_game_plays.game_play_message_type_id=play_messages.game_play_message_type_id
		LEFT JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
		LEFT JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id
        LEFT JOIN gaming_balance_history ON gaming_balance_history.balance_history_id = gaming_transactions.balance_history_id
        LEFT JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = gaming_balance_history.payment_method_id AND (@payment_method IS NULL OR @payment_method = gaming_payment_method.name)
        ORDER BY gaming_game_plays.game_play_id DESC; 
        
  ELSEIF (sportsBookActive=0 AND poolBettingActive=0) THEN

	-- casino, poker, lottery, sportspool
		SELECT 
		  gaming_game_plays.game_play_id AS trail_id,
		  gaming_game_plays.timestamp AS `timestamp`,
		  gaming_transactions.balance_history_id,
		  IF(gaming_license_type.license_type_id IN (1,2) AND gaming_game_plays.game_id IS NOT NULL, 
			-- casino
			 CONCAT(
				CONCAT(
					gaming_games.game_description,' - ',play_messages.message,' - ',
					  CASE play_messages.name
						WHEN 'HandWins' THEN CONCAT(IF(jackpot_win>0,CONCAT('Jackpot Win ',@currencySymbol,ROUND(jackpot_win/@convertDivide,2),' - '),''), 'Win ', @currencySymbol, ROUND((win_total-jackpot_win-bet_total)/@convertDivide,2),' - ','Bet ',@currencySymbol, ROUND(bet_total/@convertDivide,2))
						WHEN 'HandLoses' THEN CONCAT(IF(jackpot_win>0,CONCAT('Jackpot Win ',@currencySymbol,ROUND(jackpot_win/@convertDivide,2),' - '),''), 'Loses ', @currencySymbol, ROUND((bet_total-jackpot_win-win_total)/@convertDivide,2),' - ','Bet ',@currencySymbol, ROUND(bet_total/@convertDivide,2))
						ELSE CONCAT(@currencySymbol, ROUND(ABS(gaming_game_plays.amount_total)/@convertDivide,2))
					  END,
					IF (gaming_game_round_types.name IS NULL OR gaming_game_round_types.selector='N',
						'',
						CONCAT(' (', gaming_game_round_types.name,')')
					)
				)
			 ),
			 IF (gaming_license_type.license_type_id=6, 
				-- Lottery
				CONCAT(play_messages.message, 
					IF (gaming_payment_transaction_type.name IN ('Bet','BetCancelled') AND gaming_lottery_coupons.num_games>1,
						CONCAT(' - Games: ', gaming_lottery_coupons.num_games),
						CONCAT(' - Game: ', IFNULL(lottery_win_draw_game.game_description, IFNULL(lottery_coupon_game.game_description, IFNULL(lottery_game.game_description, gaming_games.game_description))))
					),
					IF (gaming_payment_transaction_type.name IN ('Bet','BetCancelled') AND gaming_lottery_coupons.num_draws>1,
						CONCAT(' - Draws: ', gaming_lottery_coupons.num_draws),
						CONCAT(' - Draw Date: ', DATE(IFNULL(lottery_win_draw.draw_date, gaming_lottery_draws.draw_date)))
					),
					IF (gaming_payment_transaction_type.name IN ('Bet','BetCancelled') AND gaming_lottery_coupons.num_ticket_entries>1,
						CONCAT(' - Tickets: ', gaming_lottery_coupons.num_ticket_entries),
						IFNULL(CONCAT(' - Ticket: ', IFNULL(win_ticket_entry.numbers, ticket_entries.numbers)), '')
				    ), ' - ', @currencySymbol, ROUND(gaming_game_plays.amount_total/@convertDivide,2)), 
			   
			IF (gaming_license_type.license_type_id=7, 
				-- SportsPool
				-- to review draw_date
				CONCAT(play_messages.message, 
					IF (gaming_payment_transaction_type.name IN ('Bet','BetCancelled') AND gaming_lottery_coupons.num_games>1,
						CONCAT(' - Games: ', gaming_lottery_coupons.num_games),
						CONCAT(' - Game: ', IFNULL(lottery_win_draw_game.game_description, IFNULL(lottery_coupon_game.game_description, IFNULL(lottery_game.game_description, gaming_games.game_description))))
					),
					IF (gaming_payment_transaction_type.name IN ('Bet','BetCancelled') AND gaming_lottery_coupons.num_draws>1,
						CONCAT(' - Programs: ', gaming_lottery_coupons.num_draws),
						CONCAT(' - Settlement Date: ', DATE(IFNULL(lottery_win_draw.draw_date, gaming_lottery_draws.draw_date)))
					),
					IF (gaming_payment_transaction_type.name IN ('Bet','BetCancelled') AND gaming_lottery_coupons.num_ticket_entries>1,
						CONCAT(' - Tickets: ', gaming_lottery_coupons.num_ticket_entries),
						IFNULL(CONCAT(' - Ticket: ', IFNULL(win_ticket_group.no_of_combinations, ticket_groups.no_of_combinations)), '')
				    ), ' - ', @currencySymbol, ROUND(gaming_game_plays.amount_total/@convertDivide,2)
			   ),
				-- Other
				gaming_payment_transaction_type.display_name
			 ))
		  ) AS `description`,
		  IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult > 0, gaming_game_plays.amount_real, NULL) AS `credit_real`,
		  ABS(IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult < 0, gaming_game_plays.amount_real, NULL)) AS `debit_real`,
		  IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult > 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-amount_free_bet, 2), NULL) AS `credit_bonus`,
		  ABS(IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult < 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-amount_free_bet, 2), NULL)) AS `debit_bonus`,
		  IF((amount_free_bet)*gaming_game_plays.sign_mult > 0, ROUND(amount_free_bet, 2), NULL) AS `credit_freebet`,
		  ABS(IF((amount_free_bet)*gaming_game_plays.sign_mult < 0, ROUND(amount_free_bet, 2), NULL)) AS `debit_freebet`,
		  gaming_game_plays.balance_real_after AS `balance_real`, gaming_game_plays.balance_bonus_after AS `balance_bonus`,
		  gaming_game_plays.pending_bet_real, gaming_game_plays.pending_bet_bonus,
		  gaming_game_plays.game_round_id AS `game_round_id`, gaming_games.game_id, 
		  IF(gaming_payment_transaction_type.name='Win' AND bet_total>win_total AND gaming_license_type.license_type_id NOT IN (6,7), 'Loss', IF(gaming_payment_transaction_type.is_user_adjustment_type, 'Adjustment', gaming_payment_transaction_type.name)) AS transaction_type, gaming_license_type.name AS license_type,
		  gaming_game_plays.amount_total, bet_total, IF(play_messages.is_round_finished, win_total, NULL) AS win_total, IF(play_messages.is_round_finished OR play_messages.name='PJWin', jackpot_win, NULL) AS jackpot_win, play_messages.name AS play_message_type,
		  gaming_game_plays.loyalty_points, gaming_game_plays.loyalty_points_bonus,gaming_transactions.withdrawal_pending_after, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, gaming_payment_method.name AS payment_method
		FROM 
		(
			SELECT game_play_id 
			FROM gaming_game_plays FORCE INDEX (player_date) 
            WHERE gaming_game_plays.client_stat_id=@client_stat_id AND gaming_game_plays.timestamp BETWEEN @date_from AND @date_to
            ORDER BY gaming_game_plays.game_play_id DESC 
			LIMIT firstResult, perPage
		) AS XX 
		STRAIGHT_JOIN gaming_game_plays ON gaming_game_plays.game_play_id=XX.game_play_id
		JOIN gaming_payment_transaction_type ON 
		  gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND (@filter=0 OR
		  gaming_payment_transaction_type.hide_from_player=0 AND
		  IF(@filter=1,gaming_payment_transaction_type.player_trail_type_id = 1 AND (gaming_game_plays.license_type_id IN (1,2))  AND gaming_game_plays.game_id IS NOT NULL,
			IF (@filter=2,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id =3 AND gaming_game_plays.sb_bet_id IS NOT NULL,
				IF (@filter=3,gaming_payment_transaction_type.player_trail_type_id IN (2,3),
					IF (@filter=4,gaming_payment_transaction_type.player_trail_type_id = 4 ,
						IF (@filter=5,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id =5,
							IF (@filter=6, gaming_game_plays.loyalty_points IS NOT NULL AND (gaming_game_plays.loyalty_points>0 OR gaming_game_plays.loyalty_points_bonus>0), 
								IF (@filter=7,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id = 6, 
									IF (@filter=8,gaming_payment_transaction_type.payment_transaction_type_id NOT IN(238),
										IF (@filter=9,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id = 7, 1=1))))))))))
		JOIN gaming_license_type ON gaming_game_plays.license_type_id = gaming_license_type.license_type_id
        LEFT JOIN gaming_transactions ON gaming_game_plays.transaction_id = gaming_transactions.transaction_id
		LEFT JOIN gaming_games ON gaming_game_plays.game_id=gaming_games.game_id
		LEFT JOIN gaming_game_play_message_types AS play_messages ON gaming_game_plays.game_play_message_type_id=play_messages.game_play_message_type_id
		LEFT JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
		LEFT JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id
		LEFT JOIN gaming_lottery_coupons ON gaming_game_plays.sb_bet_id=gaming_lottery_coupons.lottery_coupon_id 
		AND CASE @filter 
		WHEN 7 THEN gaming_game_plays.license_type_id = 6 
		WHEN 9 THEN gaming_game_plays.license_type_id = 7
		ELSE gaming_game_plays.license_type_id IN (6,7)
		END
		LEFT JOIN gaming_lottery_coupon_statuses ON gaming_lottery_coupon_statuses.lottery_coupon_status_id=gaming_lottery_coupons.lottery_coupon_status_id
		LEFT JOIN gaming_lottery_transactions ON gaming_lottery_transactions.lottery_coupon_id=gaming_lottery_coupons.lottery_coupon_id AND is_bet_transaction = 1
		LEFT JOIN gaming_lottery_channels ON gaming_lottery_channels.lottery_channel_id=gaming_lottery_transactions.lottery_channel_id
		LEFT JOIN gaming_lottery_coupon_games ON gaming_lottery_coupons.lottery_coupon_id=gaming_lottery_coupon_games.lottery_coupon_id
		LEFT JOIN gaming_games AS lottery_coupon_game ON gaming_lottery_coupon_games.game_id=lottery_coupon_game.game_id
		LEFT JOIN gaming_lottery_dbg_tickets ON gaming_lottery_coupons.num_tickets=1 AND gaming_lottery_dbg_tickets.lottery_coupon_id=gaming_lottery_coupons.lottery_coupon_id
		-- Lottery
		LEFT JOIN gaming_lottery_dbg_ticket_entries AS ticket_entries ON gaming_lottery_coupons.num_ticket_entries=1 AND ticket_entries.lottery_dbg_ticket_id=gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
		-- SportsPool
		LEFT JOIN gaming_lottery_dbg_ticket_groups AS ticket_groups ON gaming_lottery_coupons.num_ticket_entries=1 AND ticket_groups.lottery_dbg_ticket_id=gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
		
		LEFT JOIN gaming_lottery_participations AS lottery_participation ON gaming_lottery_coupons.num_participations=1 AND lottery_participation.lottery_dbg_ticket_id=gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
		LEFT JOIN gaming_lottery_draws ON lottery_participation.lottery_draw_id=gaming_lottery_draws.lottery_draw_id
		LEFT JOIN gaming_games AS lottery_game ON gaming_lottery_draws.game_id=lottery_game.game_id
		LEFT JOIN gaming_lottery_participations AS lottery_win_participation ON gaming_game_plays.sb_extra_id=lottery_win_participation.lottery_participation_id 
		AND CASE @filter 
		WHEN 7 THEN gaming_game_plays.license_type_id = 6 
		WHEN 9 THEN gaming_game_plays.license_type_id = 7
		ELSE gaming_game_plays.license_type_id IN (6,7)
		END
		LEFT JOIN gaming_lottery_draws AS lottery_win_draw ON lottery_win_participation.lottery_draw_id=lottery_win_draw.lottery_draw_id
		LEFT JOIN gaming_games AS lottery_win_draw_game ON gaming_lottery_draws.game_id=lottery_win_draw_game.game_id
		LEFT JOIN gaming_lottery_dbg_tickets AS lottery_win_ticket ON lottery_win_participation.lottery_dbg_ticket_id=lottery_win_ticket.lottery_dbg_ticket_id AND lottery_win_ticket.num_ticket_entries=1
		-- Lottery
		LEFT JOIN gaming_lottery_dbg_ticket_entries AS win_ticket_entry ON win_ticket_entry.lottery_dbg_ticket_id=lottery_win_ticket.lottery_dbg_ticket_id
		-- SportsPool
		LEFT JOIN gaming_lottery_dbg_ticket_groups AS win_ticket_group ON win_ticket_group.lottery_dbg_ticket_id=lottery_win_ticket.lottery_dbg_ticket_id

        LEFT JOIN gaming_balance_history ON gaming_balance_history.balance_history_id = gaming_transactions.balance_history_id
        LEFT JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = gaming_balance_history.payment_method_id AND 
			(@payment_method IS NULL OR @payment_method = gaming_payment_method.name)
		WHERE 
			(gaming_lottery_coupon_statuses.status_code = @status_code OR @status_code IS NULL) AND 
            (gaming_lottery_channels.channel_code = @channel_code OR @channel_code IS NULL) AND 
            (lottery_coupon_game.manufacturer_game_idf = @game_idf OR @game_idf IS NULL)
		GROUP BY gaming_game_plays.game_play_id
        ORDER BY gaming_game_plays.game_play_id DESC;

  ELSEIF ((sportsBookActive=1 OR poolBettingActive=1) AND lotteryActive=0 AND sportsPoolActive = 0) THEN
		
		-- casino, poker, sports book, pool betting
		SELECT 
		  gaming_game_plays.game_play_id AS trail_id,
		  gaming_game_plays.timestamp AS `timestamp`,
		  gaming_transactions.balance_history_id,
			  IF(gaming_payment_transaction_type.is_common_wallet_adjustment_type =0, 
			  IF(play_messages.tran_selector = 'p',
				CONCAT(gaming_pb_competitions.name, ' - ', gaming_payment_transaction_type.display_name, ' - ', gaming_pb_pool_types.display_type , ' - ', ROUND(ABS(gaming_game_plays.amount_total)/@convertDivide,2)),
				IF(gaming_game_plays.sb_bet_id IS NOT NULL AND gaming_game_plays.license_type_id=3, 
					IF(gaming_payment_transaction_type.name='Bet',
						CONCAT(play_messages.message, ' - ',
							IFNULL(
								IF (gaming_sb_selections.name IS NOT NULL, 
									CONCAT(IFNULL(CONCAT(gaming_sb_events.name, ' - ', gaming_sb_markets.name, ' - '),'Sport - '), gaming_sb_selections.name), 
									gaming_sb_multiple_types.name
								), 
								CONCAT('Singles: ', gaming_sb_bets.num_singles, ', Multiplies: ', gaming_sb_bets.num_multiplies)
							),
							IF (gaming_game_plays.is_confirmed=1, '', 
									IF(gaming_game_plays.confirmed_amount=0, ' - Awaiting Confirmation', 
										CONCAT(' - Partially Confirmed: ', @currencySymbol, ROUND(ABS(gaming_game_plays.confirmed_amount)/@convertDivide, 2))
									)
								)
						),
						IF (gaming_payment_transaction_type.name='Win',
							CONCAT(
								play_messages.message, ' - ', 
								IF (gaming_sb_selections_win.name IS NOT NULL, 
									CONCAT(IFNULL(CONCAT(gaming_sb_events_win.name, ' - ', gaming_sb_markets_win.name, ' - '),'Sport - '), gaming_sb_selections_win.name), 
									gaming_sb_multiple_types_win.name
								)
							),
                            play_messages.message
						)
				    )
				 ,
					IF (gaming_games.game_id IS NOT NULL,
						CONCAT(
							CONCAT(
								gaming_games.game_description,' - ',play_messages.message,' - ',
								  CASE play_messages.name
									WHEN 'HandWins' THEN CONCAT(IF(gaming_game_rounds.jackpot_win>0,CONCAT('Jackpot Win ',@currencySymbol,ROUND(gaming_game_rounds.jackpot_win/@convertDivide,2),' - '),''), 'Win ', @currencySymbol, ROUND((gaming_game_rounds.win_total-gaming_game_rounds.jackpot_win-gaming_game_rounds.bet_total)/@convertDivide,2),' - ','Bet ',@currencySymbol, ROUND(gaming_game_rounds.bet_total/@convertDivide,2))
									WHEN 'HandLoses' THEN CONCAT(IF(gaming_game_rounds.jackpot_win>0,CONCAT('Jackpot Win ',@currencySymbol,ROUND(gaming_game_rounds.jackpot_win/@convertDivide,2),' - '),''), 'Loses ', @currencySymbol, ROUND((gaming_game_rounds.bet_total-gaming_game_rounds.jackpot_win-gaming_game_rounds.win_total)/@convertDivide,2),' - ','Bet ',@currencySymbol, ROUND(gaming_game_rounds.bet_total/@convertDivide,2))
									ELSE CONCAT(@currencySymbol, ROUND(ABS(gaming_game_plays.amount_total)/@convertDivide,2))
								  END,
								IF (gaming_game_round_types.name IS NULL OR gaming_game_round_types.selector='N',
									'',
									CONCAT(' (', gaming_game_round_types.name,')')
								)
							)
						),
					 gaming_payment_transaction_type.display_name
					)
				)
			),
			gaming_payment_transaction_type.display_name
		  ) AS `description`,
		  IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult > 0, gaming_game_plays.amount_real, NULL) AS `credit_real`,
		  ABS(IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult < 0, gaming_game_plays.amount_real, NULL)) AS `debit_real`,
		  IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult > 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-gaming_game_plays.amount_free_bet, 2), NULL) AS `credit_bonus`,
		  ABS(IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult < 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-gaming_game_plays.amount_free_bet, 2), NULL)) AS `debit_bonus`,
		  IF((gaming_game_plays.amount_free_bet)*gaming_game_plays.sign_mult > 0, ROUND(gaming_game_plays.amount_free_bet, 2), NULL) AS `credit_freebet`,
		  ABS(IF((gaming_game_plays.amount_free_bet)*gaming_game_plays.sign_mult < 0, ROUND(gaming_game_plays.amount_free_bet, 2), NULL)) AS `debit_freebet`,
		  gaming_game_plays.balance_real_after AS `balance_real`, gaming_game_plays.balance_bonus_after AS `balance_bonus`,
		  gaming_game_plays.pending_bet_real, gaming_game_plays.pending_bet_bonus,
		  gaming_game_plays.game_round_id AS `game_round_id`, gaming_games.game_id, 
		  IF(gaming_payment_transaction_type.name='Win' AND gaming_game_rounds.bet_total>gaming_game_rounds.win_total AND gaming_license_type.license_type_id NOT IN (6, 7), 'Loss', IF(gaming_payment_transaction_type.is_user_adjustment_type, 'Adjustment', gaming_payment_transaction_type.name)) AS transaction_type, gaming_license_type.name AS license_type,
		  gaming_game_plays.amount_total, gaming_game_rounds.bet_total, IF(play_messages.is_round_finished, gaming_game_rounds.win_total, NULL) AS win_total, IF(play_messages.is_round_finished OR play_messages.name='PJWin', jackpot_win, NULL) AS jackpot_win, play_messages.name AS play_message_type,
		  gaming_game_plays.loyalty_points, gaming_game_plays.loyalty_points_bonus, gaming_transactions.withdrawal_pending_after, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, gaming_payment_method.name AS payment_method
		FROM 
		(
			SELECT game_play_id 
			FROM gaming_game_plays FORCE INDEX (player_date)
            WHERE gaming_game_plays.client_stat_id=@client_stat_id AND gaming_game_plays.timestamp BETWEEN @date_from AND @date_to
            ORDER BY gaming_game_plays.game_play_id DESC 
			LIMIT firstResult, perPage
		) AS XX 
		STRAIGHT_JOIN gaming_game_plays ON gaming_game_plays.game_play_id=XX.game_play_id
		STRAIGHT_JOIN gaming_payment_transaction_type ON 
		  gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
		  gaming_payment_transaction_type.hide_from_player=0 AND (@filter=0 OR
		  IF(@filter=1,gaming_payment_transaction_type.player_trail_type_id = 1 AND (gaming_game_plays.license_type_id IN (1,2))  AND gaming_game_plays.game_id IS NOT NULL,
			IF (@filter=2,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id =3 AND gaming_game_plays.sb_bet_id IS NOT NULL,
				IF (@filter=3,gaming_payment_transaction_type.player_trail_type_id IN (2,3),
					IF (@filter=4,gaming_payment_transaction_type.player_trail_type_id = 4 ,
						IF (@filter=5,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id =5,
							IF (@filter=6, gaming_game_plays.loyalty_points IS NOT NULL AND (gaming_game_plays.loyalty_points>0 OR gaming_game_plays.loyalty_points_bonus>0), 
								IF (@filter=7,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id = 6, 
									IF (@filter=8,gaming_payment_transaction_type.payment_transaction_type_id NOT IN(238),
										IF (@filter=9,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id = 7, 1=1))))))))))
		STRAIGHT_JOIN gaming_license_type ON gaming_game_plays.license_type_id = gaming_license_type.license_type_id
		LEFT JOIN gaming_transactions ON gaming_game_plays.transaction_id = gaming_transactions.transaction_id
		LEFT JOIN gaming_games ON gaming_game_plays.game_id=gaming_games.game_id
		LEFT JOIN gaming_game_play_message_types AS play_messages ON gaming_game_plays.game_play_message_type_id=play_messages.game_play_message_type_id
		LEFT JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
		LEFT JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id
		-- Sports
		LEFT JOIN gaming_sb_bets ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id
        LEFT JOIN gaming_game_plays_sb ON  (gaming_sb_bets.num_singles+gaming_sb_bets.num_multiplies)=1 AND gaming_game_plays.game_play_id=gaming_game_plays_sb.game_play_id 
		LEFT JOIN gaming_sb_selections ON gaming_sb_bets.num_singles=1 AND gaming_game_plays_sb.sb_selection_id=gaming_sb_selections.sb_selection_id
		LEFT JOIN gaming_sb_markets ON gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
		LEFT JOIN gaming_sb_events ON gaming_sb_markets.sb_event_id = gaming_sb_events.sb_event_id
		LEFT JOIN gaming_sb_multiple_types ON gaming_sb_bets.num_multiplies=1 AND gaming_game_plays_sb.sb_multiple_type_id=gaming_sb_multiple_types.sb_multiple_type_id
			-- Sports Win
		LEFT JOIN gaming_game_plays_sb AS gaming_game_plays_sb_win ON gaming_payment_transaction_type.payment_transaction_type_id IN (13,46) 
			AND gaming_game_plays.game_play_id=gaming_game_plays_sb_win.game_play_id 
		LEFT JOIN gaming_sb_selections AS gaming_sb_selections_win ON gaming_game_plays_sb_win.sb_selection_id=gaming_sb_selections_win.sb_selection_id
		LEFT JOIN gaming_sb_markets AS gaming_sb_markets_win ON gaming_sb_selections_win.sb_market_id=gaming_sb_markets_win.sb_market_id
		LEFT JOIN gaming_sb_events AS gaming_sb_events_win ON gaming_sb_markets_win.sb_event_id = gaming_sb_events_win.sb_event_id
		LEFT JOIN gaming_sb_multiple_types AS gaming_sb_multiple_types_win ON gaming_game_plays_sb_win.sb_multiple_type_id=gaming_sb_multiple_types_win.sb_multiple_type_id
		-- Pool Bettings
		LEFT JOIN gaming_pb_pools ON gaming_game_plays.extra_id = gaming_pb_pools.pb_pool_id
		LEFT JOIN gaming_pb_pool_types ON gaming_pb_pools.pb_pool_type_id = gaming_pb_pool_types.pb_pool_type_id
		LEFT JOIN gaming_pb_competition_pools ON gaming_pb_competition_pools.pb_pool_id = gaming_pb_pools.pb_pool_id
		LEFT JOIN gaming_pb_competitions ON gaming_pb_competitions.pb_competition_id = gaming_pb_competition_pools.pb_competition_id
        LEFT JOIN gaming_balance_history ON gaming_balance_history.balance_history_id = gaming_transactions.balance_history_id
        LEFT JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = gaming_balance_history.payment_method_id 
			AND (@payment_method IS NULL OR @payment_method = gaming_payment_method.name)
		ORDER BY gaming_game_plays.game_play_id DESC;

  ELSE

		-- casino, poker, sports book, pool betting, lottery, sportspool
		SELECT 
		  gaming_game_plays.game_play_id AS trail_id,
		  gaming_game_plays.timestamp AS `timestamp`,
		  gaming_transactions.balance_history_id,
			  IF(gaming_payment_transaction_type.is_common_wallet_adjustment_type =0, 
			  IF(play_messages.tran_selector = 'p',
				CONCAT(gaming_pb_competitions.name, ' - ', gaming_payment_transaction_type.display_name, ' - ', gaming_pb_pool_types.display_type , ' - ', ROUND(ABS(gaming_game_plays.amount_total)/@convertDivide,2)),
				IF(gaming_game_plays.sb_bet_id IS NOT NULL AND gaming_game_plays.license_type_id=3, 
					IF(gaming_payment_transaction_type.name='Bet',
						CONCAT(play_messages.message, ' - ',
							IFNULL(
								IF (gaming_sb_selections.name IS NOT NULL, 
									CONCAT(IFNULL(CONCAT(gaming_sb_events.name, ' - ', gaming_sb_markets.name, ' - '),'Sport - '), gaming_sb_selections.name), 
									gaming_sb_multiple_types.name
								), 
								CONCAT('Singles: ', gaming_sb_bets.num_singles, ', Multiplies: ', gaming_sb_bets.num_multiplies)
							),
							IF (gaming_game_plays.is_confirmed=1, '', 
									IF(gaming_game_plays.confirmed_amount=0, ' - Awaiting Confirmation', 
										CONCAT(' - Partially Confirmed: ', @currencySymbol, ROUND(ABS(gaming_game_plays.confirmed_amount)/@convertDivide, 2))
									)
								)
						),
                        IF (gaming_payment_transaction_type.name='Win',
							CONCAT(
								play_messages.message, ' - ', 
								IF (gaming_sb_selections_win.name IS NOT NULL, 
									CONCAT(IFNULL(CONCAT(gaming_sb_events_win.name, ' - ', gaming_sb_markets_win.name, ' - '),'Sport - '), gaming_sb_selections_win.name), 
									gaming_sb_multiple_types_win.name
								)
							),
                            play_messages.message
						)
				    )
				 ,
					IF (gaming_games.game_id IS NOT NULL,
						CONCAT(
							CONCAT(
								gaming_games.game_description,' - ',play_messages.message,' - ',
								  CASE play_messages.name
									WHEN 'HandWins' THEN CONCAT(IF(gaming_game_rounds.jackpot_win>0,CONCAT('Jackpot Win ',@currencySymbol,ROUND(gaming_game_rounds.jackpot_win/@convertDivide,2),' - '),''), 'Win ', @currencySymbol, ROUND((gaming_game_rounds.win_total-gaming_game_rounds.jackpot_win-gaming_game_rounds.bet_total)/@convertDivide,2),' - ','Bet ',@currencySymbol, ROUND(gaming_game_rounds.bet_total/@convertDivide,2))
									WHEN 'HandLoses' THEN CONCAT(IF(gaming_game_rounds.jackpot_win>0,CONCAT('Jackpot Win ',@currencySymbol,ROUND(gaming_game_rounds.jackpot_win/@convertDivide,2),' - '),''), 'Loses ', @currencySymbol, ROUND((gaming_game_rounds.bet_total-gaming_game_rounds.jackpot_win-gaming_game_rounds.win_total)/@convertDivide,2),' - ','Bet ',@currencySymbol, ROUND(gaming_game_rounds.bet_total/@convertDivide,2))
									ELSE CONCAT(@currencySymbol, ROUND(ABS(gaming_game_plays.amount_total)/@convertDivide,2))
								  END,
								IF (gaming_game_round_types.name IS NULL OR gaming_game_round_types.selector='N',
									'',
									CONCAT(' (', gaming_game_round_types.name,')')
								)
							)
						),
					 IF (gaming_game_plays.license_type_id=6, 
							-- Lottery
							CONCAT(play_messages.message, 
								IF (gaming_payment_transaction_type.name IN ('Bet','BetCancelled') AND gaming_lottery_coupons.num_games>1,
									CONCAT(' - Games: ', gaming_lottery_coupons.num_games),
									CONCAT(' - Game: ', IFNULL(lottery_win_draw_game.game_description, IFNULL(lottery_coupon_game.game_description, IFNULL(lottery_game.game_description, gaming_games.game_description))))
								),
								IF (gaming_payment_transaction_type.name IN ('Bet','BetCancelled') AND gaming_lottery_coupons.num_draws>1,
									CONCAT(' - Draws: ', gaming_lottery_coupons.num_draws),
									CONCAT(' - Draw Date: ', DATE(IFNULL(lottery_win_draw.draw_date, gaming_lottery_draws.draw_date)))
								),
								IF (gaming_payment_transaction_type.name IN ('Bet','BetCancelled') AND gaming_lottery_coupons.num_ticket_entries>1,
									CONCAT(' - Tickets: ', gaming_lottery_coupons.num_ticket_entries),
									IFNULL(CONCAT(' - Ticket: ', IFNULL(win_ticket_entry.numbers, ticket_entries.numbers)), '')
								) , ' - ', @currencySymbol, ROUND(gaming_game_plays.amount_total/@convertDivide,2)), 
					IF (gaming_license_type.license_type_id=7, 
				-- SportsPool
				-- to review draw_date
				CONCAT(play_messages.message, 
					IF (gaming_payment_transaction_type.name IN ('Bet','BetCancelled') AND gaming_lottery_coupons.num_games>1,
						CONCAT(' - Games: ', gaming_lottery_coupons.num_games),
						CONCAT(' - Game: ', IFNULL(lottery_win_draw_game.game_description, IFNULL(lottery_coupon_game.game_description, IFNULL(lottery_game.game_description, gaming_games.game_description))))
					),
					IF (gaming_payment_transaction_type.name IN ('Bet','BetCancelled') AND gaming_lottery_coupons.num_draws>1,
						CONCAT(' - Programs: ', gaming_lottery_coupons.num_draws),
						CONCAT(' - Settlement Date: ', DATE(IFNULL(lottery_win_draw.draw_date, gaming_lottery_draws.draw_date)))
					),
					IF (gaming_payment_transaction_type.name IN ('Bet','BetCancelled') AND gaming_lottery_coupons.num_ticket_entries>1,
						CONCAT(' - Tickets: ', gaming_lottery_coupons.num_ticket_entries),
						IFNULL(CONCAT(' - Ticket: ', IFNULL(win_ticket_group.no_of_combinations, ticket_groups.no_of_combinations)), '')
				    ), ' - ', @currencySymbol, ROUND(gaming_game_plays.amount_total/@convertDivide,2)
				),
							-- Other
							gaming_payment_transaction_type.display_name
						 )
					))
				)
			),
			gaming_payment_transaction_type.display_name
		  ) AS `description`,
		  IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult > 0, gaming_game_plays.amount_real, NULL) AS `credit_real`,
		  ABS(IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult < 0, gaming_game_plays.amount_real, NULL)) AS `debit_real`,
		  IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult > 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-gaming_game_plays.amount_free_bet, 2), NULL) AS `credit_bonus`,
		  ABS(IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult < 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-gaming_game_plays.amount_free_bet, 2), NULL)) AS `debit_bonus`,
		  IF((gaming_game_plays.amount_free_bet)*gaming_game_plays.sign_mult > 0, ROUND(gaming_game_plays.amount_free_bet, 2), NULL) AS `credit_freebet`,
		  ABS(IF((gaming_game_plays.amount_free_bet)*gaming_game_plays.sign_mult < 0, ROUND(gaming_game_plays.amount_free_bet, 2), NULL)) AS `debit_freebet`,
		  gaming_game_plays.balance_real_after AS `balance_real`, gaming_game_plays.balance_bonus_after AS `balance_bonus`,
		  gaming_game_plays.pending_bet_real, gaming_game_plays.pending_bet_bonus,
		  gaming_game_plays.game_round_id AS `game_round_id`, gaming_games.game_id, 
		  IF(gaming_payment_transaction_type.name='Win' AND gaming_game_rounds.bet_total>gaming_game_rounds.win_total AND gaming_license_type.license_type_id NOT IN (6,7), 'Loss', IF(gaming_payment_transaction_type.is_user_adjustment_type, 'Adjustment', gaming_payment_transaction_type.name)) AS transaction_type, gaming_license_type.name AS license_type,
		  gaming_game_plays.amount_total, gaming_game_rounds.bet_total, IF(play_messages.is_round_finished, gaming_game_rounds.win_total, NULL) AS win_total, IF(play_messages.is_round_finished OR play_messages.name='PJWin', jackpot_win, NULL) AS jackpot_win, play_messages.name AS play_message_type,
		  gaming_game_plays.loyalty_points, gaming_game_plays.loyalty_points_bonus, gaming_transactions.withdrawal_pending_after, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, gaming_payment_method.name AS payment_method
		FROM 
		(
			SELECT game_play_id 
			FROM gaming_game_plays FORCE INDEX (player_date)
			WHERE gaming_game_plays.client_stat_id=@client_stat_id AND gaming_game_plays.timestamp BETWEEN @date_from AND @date_to
            ORDER BY gaming_game_plays.game_play_id DESC 
			LIMIT firstResult, perPage
		) AS XX 
		STRAIGHT_JOIN gaming_game_plays ON gaming_game_plays.game_play_id=XX.game_play_id
		JOIN gaming_payment_transaction_type ON 
		  gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
		  gaming_payment_transaction_type.hide_from_player=0 AND (@filter=0 OR
		  IF(@filter=1,gaming_payment_transaction_type.player_trail_type_id = 1 AND (gaming_game_plays.license_type_id IN (1,2))  AND gaming_game_plays.game_id IS NOT NULL,
			IF (@filter=2,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id =3 AND gaming_game_plays.sb_bet_id IS NOT NULL,
				IF (@filter=3,gaming_payment_transaction_type.player_trail_type_id IN (2,3),
					IF (@filter=4,gaming_payment_transaction_type.player_trail_type_id = 4 ,
						IF (@filter=5,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id =5,
							IF (@filter=6, gaming_game_plays.loyalty_points IS NOT NULL AND (gaming_game_plays.loyalty_points>0 OR gaming_game_plays.loyalty_points_bonus>0), 
								IF (@filter=7,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id = 6, 
									IF (@filter=8,gaming_payment_transaction_type.payment_transaction_type_id NOT IN(238),
										IF (@filter=9,gaming_payment_transaction_type.player_trail_type_id = 1 AND gaming_game_plays.license_type_id = 7, 1=1))))))))))
		JOIN gaming_license_type ON gaming_game_plays.license_type_id = gaming_license_type.license_type_id
        LEFT JOIN gaming_transactions ON gaming_game_plays.transaction_id = gaming_transactions.transaction_id
		LEFT JOIN gaming_games ON gaming_game_plays.game_id=gaming_games.game_id
		LEFT JOIN gaming_game_play_message_types AS play_messages ON gaming_game_plays.game_play_message_type_id=play_messages.game_play_message_type_id
		LEFT JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
		LEFT JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id
		-- Sports
		LEFT JOIN gaming_sb_bets ON gaming_game_plays.sb_bet_id=gaming_sb_bets.sb_bet_id
        LEFT JOIN gaming_game_plays_sb ON  (gaming_sb_bets.num_singles+gaming_sb_bets.num_multiplies)=1 AND gaming_game_plays.game_play_id=gaming_game_plays_sb.game_play_id 
		LEFT JOIN gaming_sb_selections ON gaming_sb_bets.num_singles=1 AND gaming_game_plays_sb.sb_selection_id=gaming_sb_selections.sb_selection_id
		LEFT JOIN gaming_sb_markets ON gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
		LEFT JOIN gaming_sb_events ON gaming_sb_markets.sb_event_id = gaming_sb_events.sb_event_id
		LEFT JOIN gaming_sb_multiple_types ON gaming_sb_bets.num_multiplies=1 AND gaming_game_plays_sb.sb_multiple_type_id=gaming_sb_multiple_types.sb_multiple_type_id
			-- Sports Win
		LEFT JOIN gaming_game_plays_sb AS gaming_game_plays_sb_win ON gaming_payment_transaction_type.payment_transaction_type_id IN (13,46) 
			AND gaming_game_plays.game_play_id=gaming_game_plays_sb_win.game_play_id 
		LEFT JOIN gaming_sb_selections AS gaming_sb_selections_win ON gaming_game_plays_sb_win.sb_selection_id=gaming_sb_selections_win.sb_selection_id
		LEFT JOIN gaming_sb_markets AS gaming_sb_markets_win ON gaming_sb_selections_win.sb_market_id=gaming_sb_markets_win.sb_market_id
		LEFT JOIN gaming_sb_events AS gaming_sb_events_win ON gaming_sb_markets_win.sb_event_id = gaming_sb_events_win.sb_event_id
		LEFT JOIN gaming_sb_multiple_types AS gaming_sb_multiple_types_win ON gaming_game_plays_sb_win.sb_multiple_type_id=gaming_sb_multiple_types_win.sb_multiple_type_id
		-- Pool Bettings
		LEFT JOIN gaming_pb_pools ON gaming_game_plays.extra_id = gaming_pb_pools.pb_pool_id
		LEFT JOIN gaming_pb_pool_types ON gaming_pb_pools.pb_pool_type_id = gaming_pb_pool_types.pb_pool_type_id
		LEFT JOIN gaming_pb_competition_pools ON gaming_pb_competition_pools.pb_pool_id = gaming_pb_pools.pb_pool_id
		LEFT JOIN gaming_pb_competitions ON gaming_pb_competitions.pb_competition_id = gaming_pb_competition_pools.pb_competition_id
		-- Lottery/SportsPool
		LEFT JOIN gaming_lottery_coupons ON gaming_game_plays.sb_bet_id=gaming_lottery_coupons.lottery_coupon_id 
		AND CASE @filter 
		WHEN 7 THEN gaming_game_plays.license_type_id = 6 
		WHEN 9 THEN gaming_game_plays.license_type_id = 7
		ELSE gaming_game_plays.license_type_id IN (6,7)
		END
		LEFT JOIN gaming_lottery_coupon_statuses ON gaming_lottery_coupon_statuses.lottery_coupon_status_id=gaming_lottery_coupons.lottery_coupon_status_id
		LEFT JOIN gaming_lottery_transactions ON gaming_lottery_transactions.lottery_coupon_id=gaming_lottery_coupons.lottery_coupon_id AND is_bet_transaction = 1
		LEFT JOIN gaming_lottery_channels ON gaming_lottery_channels.lottery_channel_id=gaming_lottery_transactions.lottery_channel_id		
		LEFT JOIN gaming_lottery_coupon_games ON gaming_lottery_coupons.lottery_coupon_id=gaming_lottery_coupon_games.lottery_coupon_id
		LEFT JOIN gaming_games AS lottery_coupon_game ON gaming_lottery_coupon_games.game_id=lottery_coupon_game.game_id
		LEFT JOIN gaming_lottery_dbg_tickets ON gaming_lottery_coupons.num_tickets=1 AND gaming_lottery_dbg_tickets.lottery_coupon_id=gaming_lottery_coupons.lottery_coupon_id
		-- Lottery
		LEFT JOIN gaming_lottery_dbg_ticket_entries AS ticket_entries ON gaming_lottery_coupons.num_ticket_entries=1 AND ticket_entries.lottery_dbg_ticket_id=gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
		-- SportsPool
		LEFT JOIN gaming_lottery_dbg_ticket_groups AS ticket_groups ON gaming_lottery_coupons.num_ticket_entries=1 AND ticket_groups.lottery_dbg_ticket_id=gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
		
		LEFT JOIN gaming_lottery_participations AS lottery_participation ON gaming_lottery_coupons.num_participations=1 AND lottery_participation.lottery_dbg_ticket_id=gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
		LEFT JOIN gaming_lottery_draws ON lottery_participation.lottery_draw_id=gaming_lottery_draws.lottery_draw_id
		LEFT JOIN gaming_games AS lottery_game ON gaming_lottery_draws.game_id=lottery_game.game_id
		LEFT JOIN gaming_lottery_participations AS lottery_win_participation ON gaming_game_plays.sb_extra_id=lottery_win_participation.lottery_participation_id
		LEFT JOIN gaming_lottery_draws AS lottery_win_draw ON lottery_win_participation.lottery_draw_id=lottery_win_draw.lottery_draw_id
		LEFT JOIN gaming_games AS lottery_win_draw_game ON gaming_lottery_draws.game_id=lottery_win_draw_game.game_id
		LEFT JOIN gaming_lottery_dbg_tickets AS lottery_win_ticket ON lottery_win_participation.lottery_dbg_ticket_id=lottery_win_ticket.lottery_dbg_ticket_id AND lottery_win_ticket.num_ticket_entries=1
		-- Lottery
		LEFT JOIN gaming_lottery_dbg_ticket_entries AS win_ticket_entry ON win_ticket_entry.lottery_dbg_ticket_id=lottery_win_ticket.lottery_dbg_ticket_id
        -- SportsPool
		LEFT JOIN gaming_lottery_dbg_ticket_groups AS win_ticket_group ON win_ticket_group.lottery_dbg_ticket_id=lottery_win_ticket.lottery_dbg_ticket_id

		LEFT JOIN gaming_balance_history ON gaming_balance_history.balance_history_id = gaming_transactions.balance_history_id
        LEFT JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = gaming_balance_history.payment_method_id AND 
			(@payment_method IS NULL OR @payment_method = gaming_payment_method.name)
		WHERE (gaming_lottery_coupon_statuses.status_code = @status_code OR @status_code IS NULL) AND 
			(gaming_lottery_channels.channel_code = @channel_code OR @channel_code IS NULL) AND 
            (lottery_coupon_game.manufacturer_game_idf = @game_idf OR @game_idf IS NULL)
		GROUP BY gaming_game_plays.game_play_id
        ORDER BY gaming_game_plays.game_play_id DESC;
        
  END IF; 

END$$

DELIMITER ;

