DROP procedure IF EXISTS `PlayerGetGameSessionTrail`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerGetGameSessionTrail`(clientStatID BIGINT, gameSessionID BIGINT)
BEGIN
  -- will retrieve all transaction with gameSessionID	
  -- optimized but returns up to 5000 rows
  -- added lottery
  -- Sports Book v2
  -- Sports Book Desription improvement

  DECLARE sportsBookActive, poolBeetingActive, lotteryActive TINYINT(1) DEFAULT 0;	
  DECLARE firstResult, countPlus1, perPage INT DEFAULT 0;

  SET @client_stat_id=clientStatID;
  SET @date_from='2010-01-01';
  SET @date_to='3000-01-01';

  SET @perPage=5000; 
  SET @pageNo=1;
  SET @firstResult=(@pageNo-1)*@perPage; 
 
  SET @a=@firstResult+1;
  SET @b=@firstResult+@perPage;
  SET @n=0;

  SET perPage=@perPage;
  SET firstResult=@a-1;
  SET countPlus1=firstResult+@perPage+1;
  
  SET @convertDivide=100;
  SET @currencySymbol='';
  
  SELECT value_bool INTO sportsBookActive FROM gaming_settings WHERE name='SPORTSBOOK_ACTIVE' LIMIT 1;
  SELECT value_bool INTO poolBeetingActive FROM gaming_settings WHERE name='POOL_BETTING_ACTIVE' LIMIT 1;
  SELECT value_bool INTO lotteryActive FROM gaming_settings WHERE name='LOTTO_ACTIVE' LIMIT 1;

  SELECT gaming_currency.symbol INTO @currencySymbol FROM gaming_currency JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gaming_currency.currency_id=gaming_client_stats.currency_id;
    
  IF (sportsBookActive=0 AND poolBeetingActive=0 AND lotteryActive=0) THEN

		SELECT 
		  game_play_id AS trail_id,
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
		  IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult > 0, gaming_game_plays.amount_real, NULL) AS `credit_real`,
		  ABS(IF(gaming_game_plays.amount_real*gaming_game_plays.sign_mult < 0, gaming_game_plays.amount_real, NULL)) AS `debit_real`,
		  IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult > 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-amount_free_bet, 2), NULL) AS `credit_bonus`,
		  ABS(IF((gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked)*gaming_game_plays.sign_mult < 0, ROUND(gaming_game_plays.amount_bonus+gaming_game_plays.amount_bonus_win_locked-amount_free_bet, 2), NULL)) AS `debit_bonus`,
		  IF((amount_free_bet)*gaming_game_plays.sign_mult > 0, ROUND(amount_free_bet, 2), NULL) AS `credit_freebet`,
		  ABS(IF((amount_free_bet)*gaming_game_plays.sign_mult < 0, ROUND(amount_free_bet, 2), NULL)) AS `debit_freebet`,
		  gaming_game_plays.balance_real_after AS `balance_real`, gaming_game_plays.balance_bonus_after AS `balance_bonus`,
		  gaming_game_plays.pending_bet_real, gaming_game_plays.pending_bet_bonus,
		  gaming_game_plays.game_round_id AS `game_round_id`, gaming_games.game_id, 
		  IF(gaming_payment_transaction_type.name='Win' AND bet_total>win_total, 'Loss', IF(gaming_payment_transaction_type.is_user_adjustment_type, 'Adjustment', gaming_payment_transaction_type.name)) AS transaction_type, gaming_license_type.name AS license_type,
		  gaming_game_plays.amount_total, bet_total, IF(play_messages.is_round_finished, win_total, NULL) AS win_total, IF(play_messages.is_round_finished OR play_messages.name='PJWin', jackpot_win, NULL) AS jackpot_win, play_messages.name AS play_message_type,
		  gaming_game_plays.loyalty_points, gaming_game_plays.loyalty_points_bonus,gaming_transactions.withdrawal_pending_after, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, gaming_payment_method.name AS payment_method
		FROM gaming_game_plays FORCE INDEX (game_session_id)
		LEFT JOIN gaming_transactions ON gaming_game_plays.transaction_id = gaming_transactions.transaction_id
		JOIN gaming_payment_transaction_type ON 
		  gaming_game_plays.game_session_id=gameSessionID AND (gaming_game_plays.timestamp BETWEEN @date_from AND @date_to) AND
		  gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
		  gaming_payment_transaction_type.hide_from_player=0 
		JOIN gaming_license_type ON gaming_game_plays.license_type_id = gaming_license_type.license_type_id
		LEFT JOIN gaming_games ON gaming_game_plays.game_id=gaming_games.game_id
		LEFT JOIN gaming_game_play_message_types AS play_messages ON gaming_game_plays.game_play_message_type_id=play_messages.game_play_message_type_id
		LEFT JOIN gaming_game_rounds ON gaming_game_plays.game_round_id=gaming_game_rounds.game_round_id
		LEFT JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id
        LEFT JOIN gaming_balance_history ON gaming_balance_history.balance_history_id = gaming_transactions.balance_history_id
        LEFT JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = gaming_balance_history.payment_method_id
		ORDER BY gaming_game_plays.game_play_id DESC
		LIMIT firstResult, perPage;

  ELSE

		-- casino, poker, sports book, pool beeting, lottery
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
						CONCAT(
							play_messages.message, ' - ',
							IF (gaming_sb_selections_win.name IS NOT NULL, 
								CONCAT(IFNULL(CONCAT(gaming_sb_events_win.name, ' - ', gaming_sb_markets_win.name, ' - '),'Sport - '), gaming_sb_selections_win.name), 
								gaming_sb_multiple_types_win.name
							)
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
								) , ' - ', @currencySymbol, ROUND(gaming_game_plays.amount_total/@convertDivide,2)
						   ),
							-- Other
							gaming_payment_transaction_type.display_name
						 )
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
		  IF(gaming_payment_transaction_type.name='Win' AND gaming_game_rounds.bet_total>gaming_game_rounds.win_total, 'Loss', IF(gaming_payment_transaction_type.is_user_adjustment_type, 'Adjustment', gaming_payment_transaction_type.name)) AS transaction_type, gaming_license_type.name AS license_type,
		  gaming_game_plays.amount_total, gaming_game_rounds.bet_total, IF(play_messages.is_round_finished, gaming_game_rounds.win_total, NULL) AS win_total, IF(play_messages.is_round_finished OR play_messages.name='PJWin', jackpot_win, NULL) AS jackpot_win, play_messages.name AS play_message_type,
		  gaming_game_plays.loyalty_points, gaming_game_plays.loyalty_points_bonus, gaming_transactions.withdrawal_pending_after, gaming_game_plays.sb_bet_id, gaming_game_plays.sb_extra_id, gaming_payment_method.name AS payment_method

		FROM gaming_game_plays FORCE INDEX (game_session_id)
		LEFT JOIN gaming_transactions ON gaming_game_plays.transaction_id = gaming_transactions.transaction_id
		JOIN gaming_payment_transaction_type ON 
		  gaming_game_plays.game_session_id=gameSessionID AND (gaming_game_plays.timestamp BETWEEN @date_from AND @date_to) AND
		  gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
		  gaming_payment_transaction_type.hide_from_player=0 
		JOIN gaming_license_type ON gaming_game_plays.license_type_id = gaming_license_type.license_type_id
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
		-- Lottery
		LEFT JOIN gaming_lottery_coupons ON gaming_game_plays.sb_bet_id=gaming_lottery_coupons.lottery_coupon_id AND gaming_license_type.license_type_id=6
		LEFT JOIN gaming_lottery_coupon_games ON gaming_lottery_coupons.num_games=1 AND gaming_lottery_coupons.lottery_coupon_id=gaming_lottery_coupon_games.lottery_coupon_id
		LEFT JOIN gaming_games AS lottery_coupon_game ON gaming_lottery_coupon_games.game_id=lottery_coupon_game.game_id
		LEFT JOIN gaming_lottery_dbg_tickets ON gaming_lottery_coupons.num_tickets=1 AND gaming_lottery_dbg_tickets.lottery_coupon_id=gaming_lottery_coupons.lottery_coupon_id
		LEFT JOIN gaming_lottery_dbg_ticket_entries AS ticket_entries ON gaming_lottery_coupons.num_ticket_entries=1 AND ticket_entries.lottery_dbg_ticket_id=gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
		LEFT JOIN gaming_lottery_participations AS lottery_participation ON gaming_lottery_coupons.num_participations=1 AND lottery_participation.lottery_dbg_ticket_id=gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
		LEFT JOIN gaming_lottery_draws ON lottery_participation.lottery_draw_id=gaming_lottery_draws.lottery_draw_id
		LEFT JOIN gaming_games AS lottery_game ON gaming_lottery_draws.game_id=lottery_game.game_id
		LEFT JOIN gaming_lottery_participations AS lottery_win_participation ON gaming_game_plays.sb_extra_id=lottery_win_participation.lottery_participation_id
		LEFT JOIN gaming_lottery_draws AS lottery_win_draw ON lottery_win_participation.lottery_draw_id=lottery_win_draw.lottery_draw_id
		LEFT JOIN gaming_games AS lottery_win_draw_game ON gaming_lottery_draws.game_id=lottery_win_draw_game.game_id
		LEFT JOIN gaming_lottery_dbg_tickets AS lottery_win_ticket ON lottery_win_participation.lottery_dbg_ticket_id=lottery_win_ticket.lottery_dbg_ticket_id AND lottery_win_ticket.num_ticket_entries=1
		LEFT JOIN gaming_lottery_dbg_ticket_entries AS win_ticket_entry ON win_ticket_entry.lottery_dbg_ticket_id=lottery_win_ticket.lottery_dbg_ticket_id
        LEFT JOIN gaming_balance_history ON gaming_balance_history.balance_history_id = gaming_transactions.balance_history_id
        LEFT JOIN gaming_payment_method ON gaming_payment_method.payment_method_id = gaming_balance_history.payment_method_id
		ORDER BY gaming_game_plays.game_play_id DESC 
		LIMIT firstResult, perPage;

  END IF;

END$$

DELIMITER ;

