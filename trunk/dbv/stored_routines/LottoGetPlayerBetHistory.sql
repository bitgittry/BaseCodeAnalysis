DROP procedure IF EXISTS `LottoGetPlayerBetHistory`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LottoGetPlayerBetHistory`(clientStatID BIGINT, startDate DATETIME, endDate DATETIME, perPage INT, pageNo INT)
BEGIN
	-- optimized
    -- first version
	-- changed unique_code to lottery_coupon_idf

	DECLARE firstResult, countPlus1 INT DEFAULT 0;

	SET @perPage=perPage; 
	SET @pageNo=pageNo;
	SET @firstResult=(@pageNo-1)*@perPage; 
	 
	SET @a=@firstResult+1;
	SET @b=@firstResult+@perPage;
	SET @n=0;

   SET firstResult=@a-1;
   SET countPlus1=firstResult+perPage+1;

  IF (countPlus1 <= 10001) THEN
	  SELECT COUNT(*) AS num_rounds
	  FROM
	  ( 
		SELECT game_round_id
		FROM gaming_game_rounds FORCE INDEX (player_date_time_start)
		JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id 
		JOIN gaming_currency ON gaming_game_rounds.currency_id=gaming_currency.currency_id
		JOIN gaming_operator_games ON gaming_game_rounds.operator_game_id=gaming_operator_games.operator_game_id
		JOIN gaming_games ON gaming_operator_games.game_id=gaming_games.game_id
		WHERE gaming_game_rounds.client_stat_id = clientStatID AND (gaming_game_rounds.date_time_start BETWEEN startDate AND endDate) AND gaming_game_rounds.license_type_id=6
		LIMIT countPlus1
	  ) AS XX; 
  ELSE
	SELECT COUNT(*) AS num_rounds
    FROM gaming_game_rounds FORCE INDEX (player_date_time_start)
	JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id 
	JOIN gaming_currency ON gaming_game_rounds.currency_id=gaming_currency.currency_id
	JOIN gaming_operator_games ON gaming_game_rounds.operator_game_id=gaming_operator_games.operator_game_id
	JOIN gaming_games ON gaming_operator_games.game_id=gaming_games.game_id
	WHERE gaming_game_rounds.client_stat_id = clientStatID AND (gaming_game_rounds.date_time_start BETWEEN startDate AND endDate) AND gaming_game_rounds.license_type_id=6;
  END IF;
	  
		SELECT 
			game_round_id,
			date_time_start,
			date_time_end,
			gaming_games.game_id,
			gaming_games.game_description,
			gaming_currency.currency_code,
			bet_total AS bet_amount,
			bet_real AS bet_real,
			(bet_bonus + bet_bonus_win_locked) AS bet_bonus,
			jackpot_contribution AS jackpot_contribution,
			win_total AS win_total,
			win_real AS win_real,
			(win_bonus + win_bonus_win_locked) AS win_bonus,
			(bonus_lost + bonus_win_locked_lost) AS bonus_lost,
			(balance_real_after+balance_bonus_after) AS balance_total_after,
			balance_real_after AS balance_real_after,
			balance_bonus_after AS balance_bonus_after,
			balance_real_before AS balance_real_before,
			balance_bonus_before AS balance_bonus_before,
			loyalty_points AS loyalty_points,
			loyalty_points_bonus AS loyalty_points_bonus,
			num_bets AS num_bets,
			gaming_game_round_types.name AS round_type, 
			is_round_finished AS is_finshed,
			gaming_platform_types.platform_type AS platform,
			gaming_lottery_coupons.lottery_coupon_id,
			gaming_lottery_coupons.lottery_coupon_idf AS coupon_code,
			gaming_lottery_participations.lottery_participation_id,
			gaming_lottery_participations.participation_idf AS participation_code,
			gaming_lottery_draws.draw_number,
			gaming_lottery_draws.draw_date,
		    gaming_lottery_dbg_tickets.ticket_cost,
			gaming_lottery_dbg_tickets.num_ticket_entries,
			gaming_lottery_dbg_ticket_entries.numbers
		FROM gaming_game_rounds  FORCE INDEX (player_date_time_start)
		JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id 
		JOIN gaming_currency ON gaming_game_rounds.currency_id=gaming_currency.currency_id
		JOIN gaming_operator_games ON gaming_game_rounds.operator_game_id=gaming_operator_games.operator_game_id
		JOIN gaming_games ON gaming_operator_games.game_id=gaming_games.game_id
		JOIN gaming_lottery_coupons ON gaming_game_rounds.sb_bet_id=gaming_lottery_coupons.lottery_coupon_id
		LEFT JOIN gaming_lottery_participations ON gaming_game_rounds.sb_extra_id=gaming_lottery_participations.lottery_participation_id
		LEFT JOIN gaming_lottery_draws ON gaming_lottery_participations.lottery_draw_id=gaming_lottery_draws.lottery_draw_id
		LEFT JOIN gaming_lottery_dbg_tickets ON gaming_lottery_participations.lottery_dbg_ticket_id=gaming_lottery_dbg_tickets.lottery_dbg_ticket_id
		LEFT JOIN gaming_lottery_dbg_ticket_entries ON gaming_lottery_dbg_tickets.num_ticket_entries=1 AND gaming_lottery_dbg_tickets.lottery_dbg_ticket_id=gaming_lottery_dbg_ticket_entries.lottery_dbg_ticket_id
		LEFT JOIN gaming_clients ON gaming_game_rounds.client_id = gaming_clients.client_id
		LEFT JOIN gaming_platform_types ON gaming_clients.platform_type_id = gaming_platform_types.platform_type_id
		WHERE gaming_game_rounds.client_stat_id = clientStatID AND (gaming_game_rounds.date_time_start BETWEEN startDate AND endDate) AND gaming_game_rounds.license_type_id=6
		ORDER BY gaming_game_rounds.date_time_start DESC, gaming_game_rounds.game_round_id DESC
		LIMIT firstResult, perPage;

END$$

DELIMITER ;

