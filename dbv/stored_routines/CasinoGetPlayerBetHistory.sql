DROP procedure IF EXISTS `CasinoGetPlayerBetHistory`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CasinoGetPlayerBetHistory`(clientStatID BIGINT, startDate DATETIME, endDate DATETIME, perPage INT, pageNo INT)
BEGIN
	-- optimized
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
		WHERE gaming_game_rounds.client_stat_id = clientStatID AND (gaming_game_rounds.date_time_start BETWEEN startDate AND endDate)
		LIMIT countPlus1
	  ) AS XX; 
  ELSE
	SELECT COUNT(*) AS num_rounds
    FROM gaming_game_rounds FORCE INDEX (player_date_time_start)
	JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id 
	JOIN gaming_currency ON gaming_game_rounds.currency_id=gaming_currency.currency_id
	JOIN gaming_operator_games ON gaming_game_rounds.operator_game_id=gaming_operator_games.operator_game_id
	JOIN gaming_games ON gaming_operator_games.game_id=gaming_games.game_id
	WHERE gaming_game_rounds.client_stat_id = clientStatID AND (gaming_game_rounds.date_time_start BETWEEN startDate AND endDate);
  END IF;
	  
		SELECT 
			game_round_id,
			date_time_start,
			date_time_end,
			gaming_games.game_id,
			gaming_games.game_description,
			gaming_currency.currency_code,
			ROUND(bet_total/100, 2) AS bet_amount,
			ROUND(bet_real/100, 2) AS bet_real,
			ROUND((bet_bonus + bet_bonus_win_locked)/100, 2) AS bet_bonus,
			ROUND(jackpot_contribution/100, 2) AS jackpot_contribution,
			ROUND(win_total/100, 2) AS win_total,
			ROUND(win_real/100, 2) AS win_real,
			ROUND(win_bonus + win_bonus_win_locked/100, 2) AS win_bonus,
			ROUND((bonus_lost + bonus_win_locked_lost)/100,2) AS bonus_lost,
			ROUND((balance_real_after+balance_bonus_after)/100,2) AS balance_total_after,
			ROUND(balance_real_after/100, 2) AS balance_real_after,
			ROUND(balance_bonus_after/100,2) AS balance_bonus_after,
			ROUND(balance_real_before/100, 2) AS balance_real_before,
			ROUND(balance_bonus_before/100,2) AS balance_bonus_before,
			ROUND(loyalty_points,2) AS loyalty_points,
			ROUND(loyalty_points_bonus,2) AS loyalty_points_bonus,
			num_bets AS num_bets,
			gaming_game_round_types.name AS round_type, 
			is_round_finished AS is_finshed,
			gaming_platform_types.platform_type AS platform
		FROM gaming_game_rounds  FORCE INDEX (player_date_time_start)
		JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id 
		JOIN gaming_currency ON gaming_game_rounds.currency_id=gaming_currency.currency_id
		JOIN gaming_operator_games ON gaming_game_rounds.operator_game_id=gaming_operator_games.operator_game_id
		JOIN gaming_games ON gaming_operator_games.game_id=gaming_games.game_id
		LEFT JOIN gaming_clients ON gaming_game_rounds.client_id = gaming_clients.client_id
		LEFT JOIN gaming_platform_types ON gaming_clients.platform_type_id = gaming_platform_types.platform_type_id
		WHERE gaming_game_rounds.client_stat_id = clientStatID AND (gaming_game_rounds.date_time_start BETWEEN startDate AND endDate)
		ORDER BY gaming_game_rounds.date_time_start DESC, gaming_game_rounds.game_round_id DESC
		LIMIT firstResult, perPage;

END$$

DELIMITER ;

