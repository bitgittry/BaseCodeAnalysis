DROP procedure IF EXISTS `AggregationCreateTransactionAggregationsForInterval`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `AggregationCreateTransactionAggregationsForInterval`(queryDateIntervalID BIGINT)
BEGIN  
	-- Removed test player check when inserting into gaming_game_transactions_aggregation_licence_player
	-- !! Need to modify queries to store both live and test players. If the aggregation is at player level we can join with the player to check if it is a test player.
			-- if is not at player level than need to add a field is_test_data
	-- Safe guard for sb_sport_id & sb_event_id being null
	--  Added lottery aggragations
	--  Moved Sports Book Entties Checking and Creation to SportsCreateDefaultSportsEntities
	-- Added new sports book aggregations
	-- Imported from INLW 
	-- New fields Added in gaming_game_transactions_aggregation_player_game_pc for Game Manufacturer Report 
	-- SUP 6323 : change to the gaming_game_transactions_aggregation_player_game_pc in order to use report engine 
	-- Manual merge of 21345
	-- Code Review for SUP 6323 

	COMMIT; -- just in case
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, gs4.value_bool as vb4, gs5.value_bool as vb5, gs6.value_bool as vb6, gs7.value_bool as vb7, gs8.value_bool as vb8
	INTO @casinoActive, @pokerActive, @sportsBookActive, @bonusEnabled, @promotionEnabled, @tournamentEnabled,@poolBettingActive, @lotterySportsPoolActive
	FROM gaming_settings gs1 
	JOIN gaming_settings gs2 ON (gs2.name='POKER_ACTIVE')
	JOIN gaming_settings gs3 ON (gs3.name='SPORTSBOOK_ACTIVE')
	JOIN gaming_settings gs4 ON (gs4.name='IS_BONUS_ENABLED') 
	JOIN gaming_settings gs5 ON (gs5.name='IS_PROMOTION_ENABLED')
	JOIN gaming_settings gs6 ON (gs6.name='IS_TOURNAMENTS_ENABLED')
	JOIN gaming_settings gs7 ON (gs7.name='POOL_BETTING_ACTIVE')
	JOIN gaming_settings gs8 ON (gs8.name='LOTTO_ACTIVE')
	WHERE gs1.name='CASINO_ACTIVE';
  
	IF (!@lotterySportsPoolActive) THEN
		SELECT value_bool INTO @lotterySportsPoolActive FROM gaming_settings WHERE name  = 'SPORTSPOOL_ACTIVE';
	END IF;
  

	SELECT 
		operator_id, currency_id
	INTO @operatorID , @currencyID FROM
		gaming_operators
	WHERE
		is_main_operator = 1
	LIMIT 1;
	SELECT 
		query_date_interval_id, date_from, date_to
	INTO @queryDateIntervalID , @dateFrom , @dateTo FROM
		gaming_query_date_intervals
	WHERE
		query_date_interval_id = queryDateIntervalID;


	-- by affiliate, license, test player
	-- businessobject : AggregationTnxAffiliateLicense
	DELETE FROM gaming_game_transactions_aggregation_affiliate WHERE    query_date_interval_id = @queryDateIntervalID;

	INSERT INTO gaming_game_transactions_aggregation_affiliate (affiliate_id, license_type_id,
		bet_total, bet_real, bet_bonus, bet_bonus_win_locked, jackpot_contribution, 
		win_total, win_real, win_bonus, win_bonus_win_locked, num_rounds, loyalty_points,
		currency_id, query_date_interval_id, date_from, date_to, test_players)
	SELECT gaming_affiliates.affiliate_id, gaming_game_plays.license_type_id,
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_total*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_total, 
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_real*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_real,
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_bonus*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_bonus, 
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_bonus, 
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), jackpot_contribution/exchange_rate, 0)), 0), 5) AS jackpot_contribution,
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_total/exchange_rate, 0)), 0), 5) AS win_total, 
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_real/exchange_rate, 0)), 0), 5) AS win_real,
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_bonus/exchange_rate, 0)), 0), 5) AS win_bonus, 
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_bonus_win_locked/exchange_rate, 0)), 0), 5)  AS win_bonus_win_locked,
		SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1, 1, 0)) AS num_rounds,
		ROUND(IFNULL(SUM(loyalty_points),0), 5) AS loyalty_points,
		@currencyID, @queryDateIntervalID, @dateFrom, @dateTo, gaming_clients.is_test_player
	FROM gaming_game_plays  FORCE INDEX (timestamp) 
	STRAIGHT_JOIN gaming_payment_transaction_type AS tran_type ON gaming_game_plays.timestamp BETWEEN @dateFrom AND @dateTo AND 
		tran_type.name IN ('Bet', 'BetCancelled', 'Win', 'PJWin') AND 
		gaming_game_plays.payment_transaction_type_id=tran_type.payment_transaction_type_id
	STRAIGHT_JOIN gaming_clients ON gaming_game_plays.client_id=gaming_clients.client_id
	STRAIGHT_JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
	GROUP BY gaming_clients.affiliate_id, gaming_game_plays.license_type_id, gaming_clients.is_test_player;


	-- by client rounds, license
	-- businessobject : AggregationTnxClientRoundsLicense
	DELETE FROM gaming_game_transactions_aggregation_player_rounds WHERE query_date_interval_id = @queryDateIntervalID;

	INSERT INTO gaming_game_transactions_aggregation_player_rounds (client_id, license_type_id,
		bet_real, bet_bonus,  win_real, win_bonus,
		query_date_interval_id, date_from, date_to,
		num_of_rounds)
	SELECT gaming_game_rounds.client_id, gaming_game_rounds.license_type_id, 
		ROUND(SUM(bet_real/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)),5), 
		ROUND(SUM((bet_bonus+bet_bonus_win_locked)/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)),5), 
		ROUND(SUM(win_real/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)),5), 
		ROUND(SUM((win_bonus+win_bonus_win_locked)/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)),5),
		@queryDateIntervalID, @dateFrom, @dateTo, COUNT(gaming_game_rounds.game_round_id)
	FROM gaming_game_rounds FORCE INDEX (date_time_end)
	STRAIGHT_JOIN gaming_clients ON gaming_game_rounds.client_id=gaming_clients.client_id
	STRAIGHT_JOIN gaming_operator_currency ON gaming_game_rounds.currency_id=gaming_operator_currency.currency_id
	WHERE gaming_game_rounds.is_cancelled=0 and gaming_game_rounds.date_time_end BETWEEN @dateFrom AND @dateTo AND 
		-- for lottery and sports book eliminate parent round
		(gaming_game_rounds.license_type_id NOT IN (3, 6, 7) OR (gaming_game_rounds.sb_bet_id IS NOT NULL AND gaming_game_rounds.sb_extra_id IS NOT NULL))


	GROUP BY gaming_game_rounds.client_id, gaming_game_rounds.license_type_id;

	IF (@casinoActive OR @pokerActive OR @lotterySportsPoolActive) THEN

		-- by operator, game, test player
		-- businessobject : AggregationTnxOperatorGame
		DELETE FROM gaming_game_transactions_aggregation_game WHERE query_date_interval_id=@queryDateIntervalID;

	END IF; -- @casinoActive OR @pokerActive OR @lotterySportsPoolActive

	IF (@lotterySportsPoolActive) THEN

		-- by operator, game, test player
		-- businessobject : AggregationTnxOperatorGame
		INSERT INTO gaming_game_transactions_aggregation_game (
			game_manufacturer_id, game_id, operator_game_id, 
			bet_total, bet_real, bet_bonus, bet_bonus_win_locked, jackpot_contribution, 
			win_total, win_real, win_bonus, win_bonus_win_locked, jackpot_win, num_rounds, loyalty_points,
			currency_id, query_date_interval_id, date_from, date_to, num_players, test_players)
		SELECT MAX(IFNULL(games.game_manufacturer_id,0)) as game_manufacturer_id, MAX(IFNULL(games.game_id,0)) as game_id, MAX(gaming_operator_games.operator_game_id) as operator_game_id, 
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_total*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_total*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_total, 
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_real*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_real*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_real,
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_bonus*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_bonus*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_bonus, 
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), jackpot_contribution/exchange_rate, 0)), 0), 5) AS jackpot_contribution,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_total/exchange_rate, 0)), 0), 5) AS win_total, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_real/exchange_rate, 0)), 0), 5) AS win_real,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_bonus/exchange_rate, 0)), 0), 5) AS win_bonus, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_bonus_win_locked/exchange_rate, 0)), 0), 5) AS win_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (14), entries.amount_real/exchange_rate, 0)), 0), 5) AS jackpot_win,
			SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1, 1, 0)) AS num_rounds,
			ROUND(IFNULL(SUM(entries.loyalty_points),0), 5) AS loyalty_points,
			@currencyID, @queryDateIntervalID, @dateFrom, @dateTo, COUNT(DISTINCT(client_stat_id)), gaming_clients.is_test_player
		FROM gaming_game_plays plays FORCE INDEX (timestamp)
		STRAIGHT_JOIN gaming_game_plays_lottery_entries entries ON 
			plays.timestamp BETWEEN @dateFrom AND @dateTo AND plays.license_type_id IN (6, 7) AND
			plays.game_play_id = entries.game_play_id
		STRAIGHT_JOIN gaming_payment_transaction_type AS tran_type ON tran_type.name IN ('Bet', 'BetCancelled', 'Win', 'PJWin') AND 
			plays.payment_transaction_type_id=tran_type.payment_transaction_type_id
		STRAIGHT_JOIN gaming_clients ON plays.client_id=gaming_clients.client_id
		STRAIGHT_JOIN gaming_games games ON games.game_id=plays.game_id
		STRAIGHT_JOIN gaming_operator_games ON gaming_operator_games.game_id=games.game_id AND gaming_operator_games.operator_id=@operatorID
		GROUP BY gaming_operator_games.operator_game_id, gaming_clients.is_test_player;

	END IF; -- @lotterySportsPoolActive
	
	IF (@casinoActive OR @pokerActive) THEN

		-- by operator, game, test player
		-- businessobject : AggregationTnxOperatorGame
		INSERT INTO gaming_game_transactions_aggregation_game (
			game_manufacturer_id, game_id, operator_game_id, 
			bet_total, bet_real, bet_bonus, bet_bonus_win_locked, jackpot_contribution, 
			win_total, win_real, win_bonus, win_bonus_win_locked, jackpot_win, num_rounds, loyalty_points,
			currency_id, query_date_interval_id, date_from, date_to, num_players, test_players)
		SELECT game_manufacturer_id, game_id, operator_game_id, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_total*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_total, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_real*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_real,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_bonus*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_bonus, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), jackpot_contribution/exchange_rate, 0)), 0), 5) AS jackpot_contribution,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_total/exchange_rate, 0)), 0), 5) AS win_total, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_real/exchange_rate, 0)), 0), 5) AS win_real,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_bonus/exchange_rate, 0)), 0), 5) AS win_bonus, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_bonus_win_locked/exchange_rate, 0)), 0), 5) AS win_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (14), amount_real/exchange_rate, 0)), 0), 5) AS jackpot_win,
			SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1, 1, 0)) AS num_rounds,
			ROUND(IFNULL(SUM(loyalty_points),0), 5) AS loyalty_points,
			@currencyID, @queryDateIntervalID, @dateFrom, @dateTo, COUNT(DISTINCT(client_stat_id)), gaming_clients.is_test_player
		FROM gaming_game_plays  FORCE INDEX (timestamp) 
		STRAIGHT_JOIN gaming_payment_transaction_type AS tran_type ON gaming_game_plays.timestamp BETWEEN @dateFrom AND @dateTo AND 
			tran_type.name IN ('Bet','BetCancelled', 'Win', 'PJWin') AND 
			gaming_game_plays.payment_transaction_type_id=tran_type.payment_transaction_type_id AND 
			gaming_game_plays.game_id IS NOT NULL AND license_type_id NOT IN (3, 6, 7)
		STRAIGHT_JOIN gaming_clients ON gaming_game_plays.client_id=gaming_clients.client_id
		GROUP BY gaming_game_plays.operator_game_id, gaming_clients.is_test_player;

	END IF; -- @casinoActive OR @pokerActive

	IF (@casinoActive OR @pokerActive OR @lotterySportsPoolActive) THEN

		-- Update the gaming_operator_games table with total played amount
		UPDATE gaming_operator_games gog
			JOIN 
		(SELECT 
			operator_game_id, SUM(bet_total) AS betTotal
		FROM
			gaming_game_transactions_aggregation_game ggtag
		WHERE
			query_date_interval_id = @queryDateIntervalID
		GROUP BY operator_game_id) AS agg ON gog.operator_game_id = agg.operator_game_id 


		SET gog.total_played = gog.total_played + agg.betTotal
		WHERE agg.operator_game_id = gog.operator_game_id;


		-- by player, game
		-- businessobject : AggregationTnxPlayerGame
		DELETE FROM gaming_game_transactions_aggregation_player_game WHERE query_date_interval_id = @queryDateIntervalID;

	END IF; -- @casinoActive OR @pokerActive OR @lotterySportsPoolActive

	IF (@lotterySportsPoolActive) THEN

		INSERT INTO gaming_game_transactions_aggregation_player_game (
			client_stat_id, client_id, game_manufacturer_id, game_id, operator_game_id, 
			bet_total, bet_real, bet_bonus, bet_bonus_win_locked, jackpot_contribution, 
			win_total, win_real, win_bonus, win_bonus_win_locked, jackpot_win, num_rounds, loyalty_points,
			currency_id, query_date_interval_id, date_from, date_to, has_bet,bet_real_using_loyalty_points,bet_bonus_using_loyalty_points,
			bet_bonus_win_locked_using_loyalty_points, bet_cash, win_cash, bet_cash_using_loyalty_points, num_rounds_cash)
		SELECT 
      plays.client_stat_id, plays.client_id, MAX(IFNULL(games.game_manufacturer_id,0)) as game_manufacturer_id, 
      MAX(IFNULL(games.game_id,0)) as game_id, MAX(IFNULL(gaming_operator_games.operator_game_id,0)) as operator_game_id, 
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_total*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_total*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_total, 
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_real*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_real*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_real,
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_bonus*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_bonus*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_bonus, 
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), jackpot_contribution/exchange_rate, 0)), 0), 5) AS jackpot_contribution,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_total/exchange_rate, 0)), 0), 5) AS win_total, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_real/exchange_rate, 0)), 0), 5) AS win_real,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_bonus/exchange_rate, 0)), 0), 5) AS win_bonus, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_bonus_win_locked/exchange_rate, 0)), 0), 5) AS win_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (14), entries.amount_real/exchange_rate, 0)), 0), 5) AS jackpot_win,
			SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1 AND plays.amount_cash = 0, 1, 0)) AS num_rounds,
			ROUND(IFNULL(SUM(plays.loyalty_points), 0), 5) AS loyalty_points,
			@currencyID, @queryDateIntervalID, @dateFrom, @dateTo, MAX(IF(plays.payment_transaction_type_id = 12, 1,0)) AS has_bet,
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_real*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_real*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_real_using_loyalty_points,
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_bonus_using_loyalty_points, 
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_bonus_win_locked_using_loyalty_points,
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_cash*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_cash*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_cash,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_cash/exchange_rate, 0)), 0), 5) AS win_cash,
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_cash*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_cash*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_cash_using_loyalty_points,
			SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1 AND entries.amount_cash > 0, 1, 0)) AS num_rounds_cash
		FROM gaming_game_plays AS plays FORCE INDEX (timestamp) 
		STRAIGHT_JOIN gaming_game_plays_lottery_entries AS entries ON 
			plays.timestamp BETWEEN @dateFrom AND @dateTo AND plays.license_type_id IN (6, 7) AND
			plays.game_play_id = entries.game_play_id
		STRAIGHT_JOIN gaming_payment_transaction_type AS tran_type ON tran_type.name IN ('Bet','BetCancelled','Win','PJWin') AND 
			plays.payment_transaction_type_id=tran_type.payment_transaction_type_id
		STRAIGHT_JOIN gaming_clients ON plays.client_id=gaming_clients.client_id
		STRAIGHT_JOIN gaming_lottery_draws draws ON draws.lottery_draw_id=entries.lottery_draw_id
		STRAIGHT_JOIN gaming_games games ON games.game_id=draws.game_id
		STRAIGHT_JOIN gaming_operator_games ON gaming_operator_games.game_id=games.game_id AND gaming_operator_games.operator_id=@operatorID
		GROUP BY plays.client_stat_id, gaming_operator_games.operator_game_id;

	END IF; -- @lotterySportsPoolActive
 
	IF (@casinoActive OR @pokerActive) THEN

		INSERT INTO gaming_game_transactions_aggregation_player_game (
			client_stat_id, client_id, game_manufacturer_id, game_id, operator_game_id, 
			bet_total, bet_real, bet_bonus, bet_bonus_win_locked, jackpot_contribution, 
			win_total, win_real, win_bonus, win_bonus_win_locked, jackpot_win, num_rounds, loyalty_points,
			currency_id, query_date_interval_id, date_from, date_to, has_bet,bet_real_using_loyalty_points,bet_bonus_using_loyalty_points,
			bet_bonus_win_locked_using_loyalty_points, bet_cash, win_cash, bet_cash_using_loyalty_points, num_rounds_cash)
		SELECT gaming_game_plays.client_stat_id, gaming_game_plays.client_id, game_manufacturer_id, game_id, operator_game_id, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_total*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_total, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_real*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_real,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_bonus*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_bonus, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), jackpot_contribution/exchange_rate, 0)), 0), 5) AS jackpot_contribution,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_total/exchange_rate, 0)), 0), 5) AS win_total, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_real/exchange_rate, 0)), 0), 5) AS win_real,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_bonus/exchange_rate, 0)), 0), 5) AS win_bonus, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_bonus_win_locked/exchange_rate, 0)), 0), 5) AS win_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (14), amount_real/exchange_rate, 0)), 0), 5) AS jackpot_win,
			SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1 AND amount_cash = 0, 1, 0)) AS num_rounds,
			ROUND(IFNULL(SUM(loyalty_points), 0), 5) AS loyalty_points,
			@currencyID, @queryDateIntervalID, @dateFrom, @dateTo, MAX(IF(gaming_game_plays.payment_transaction_type_id = 12, 1,0)) AS has_bet,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20) AND IFNULL(loyalty_points,0) != 0, amount_real*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_real_using_loyalty_points,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20) AND IFNULL(loyalty_points,0) != 0, amount_bonus*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_bonus_using_loyalty_points, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20) AND IFNULL(loyalty_points,0) != 0, amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_bonus_win_locked_using_loyalty_points,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_cash*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_cash,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_cash/exchange_rate, 0)), 0), 5) AS win_cash,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20) AND IFNULL(loyalty_points,0) != 0, amount_cash*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_cash_using_loyalty_points,
			SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1 AND amount_cash > 0, 1, 0)) AS num_rounds_cash
		FROM gaming_game_plays  FORCE INDEX (timestamp) 
		STRAIGHT_JOIN gaming_payment_transaction_type AS tran_type ON 
			gaming_game_plays.timestamp BETWEEN @dateFrom AND @dateTo AND 
			gaming_game_plays.game_id IS NOT NULL AND gaming_game_plays.license_type_id NOT IN (3, 6, 7) AND
            tran_type.name IN ('Bet','BetCancelled','Win','PJWin') AND 
			gaming_game_plays.payment_transaction_type_id=tran_type.payment_transaction_type_id 
		STRAIGHT_JOIN gaming_clients ON gaming_game_plays.client_id=gaming_clients.client_id
		GROUP BY gaming_game_plays.client_stat_id, gaming_game_plays.operator_game_id;

	END IF; -- @casinoActive OR @pokerActive

	IF (@casinoActive OR @pokerActive OR @lotterySportsPoolActive) THEN

		DELETE FROM gaming_game_transactions_aggregation_player_game_payment_method WHERE query_date_interval_id = @queryDateIntervalID;

	END IF; -- @casinoActive OR @pokerActive OR @lotterySportsPoolActive

	IF (@lotterySportsPoolActive) THEN

		-- New table to aggregate cash transactions additionally by payment method
		INSERT INTO gaming_game_transactions_aggregation_player_game_payment_method (
			client_stat_id, client_id, game_manufacturer_id, game_id, operator_game_id, 
			num_rounds, loyalty_points, currency_id, query_date_interval_id, date_from, date_to, has_bet, bet_cash, 
			win_cash, bet_cash_using_loyalty_points, payment_method_id)
		SELECT plays.client_stat_id, plays.client_id, MAX(IFNULL(games.game_manufacturer_id,0)) as game_manufacturer_id, 
			MAX(IFNULL(games.game_id,0)) as game_id, MAX(IFNULL(gaming_operator_games.operator_game_id,0)) as operator_game_id,  
			SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1, 1, 0)) AS num_rounds,
			ROUND(IFNULL(SUM(entries.loyalty_points), 0), 5) AS loyalty_points,
			@currencyID, @queryDateIntervalID, @dateFrom, @dateTo, MAX(IF(plays.payment_transaction_type_id = 12, 1,0)) AS has_bet,
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_cash*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_cash*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_cash,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_cash/exchange_rate, 0)), 0), 5) AS win_cash,
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_cash*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_cash*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_cash_using_loyalty_points,
			plays.payment_method_id
		FROM gaming_game_plays AS plays FORCE INDEX (timestamp)  
		STRAIGHT_JOIN gaming_game_plays_lottery_entries AS entries ON 
			plays.timestamp BETWEEN @dateFrom AND @dateTo AND plays.license_type_id IN (6, 7) AND
			plays.game_play_id = entries.game_play_id
		STRAIGHT_JOIN gaming_payment_transaction_type AS tran_type ON tran_type.name IN ('Bet','BetCancelled','Win','PJWin') AND 
			plays.payment_transaction_type_id=tran_type.payment_transaction_type_id
		STRAIGHT_JOIN gaming_clients ON plays.client_id=gaming_clients.client_id
		STRAIGHT_JOIN gaming_lottery_draws draws ON draws.lottery_draw_id=entries.lottery_draw_id
		STRAIGHT_JOIN gaming_games games ON games.game_id=draws.game_id	
		STRAIGHT_JOIN gaming_operator_games ON gaming_operator_games.game_id=games.game_id AND gaming_operator_games.operator_id=@operatorID
		WHERE plays.amount_cash > 0
		GROUP BY plays.client_stat_id, gaming_operator_games.operator_game_id, plays.payment_method_id;

	END IF; -- @lotterySportsPoolActive

	IF (@casinoActive OR @pokerActive) THEN

		-- New table to aggregate cash transactions additionally by payment method
		INSERT INTO gaming_game_transactions_aggregation_player_game_payment_method (
			client_stat_id, client_id, game_manufacturer_id, game_id, operator_game_id, 
			num_rounds, loyalty_points, currency_id, query_date_interval_id, date_from, date_to, has_bet, bet_cash, win_cash, 
			bet_cash_using_loyalty_points, payment_method_id)
		SELECT gaming_game_plays.client_stat_id, gaming_game_plays.client_id, game_manufacturer_id, game_id, operator_game_id, 
			SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1, 1, 0)) AS num_rounds,
			ROUND(IFNULL(SUM(loyalty_points), 0), 5) AS loyalty_points,
			@currencyID, @queryDateIntervalID, @dateFrom, @dateTo, MAX(IF(gaming_game_plays.payment_transaction_type_id = 12, 1,0)) AS has_bet,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_cash*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_cash,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_cash/exchange_rate, 0)), 0), 5) AS win_cash,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20) AND IFNULL(loyalty_points,0) != 0, amount_cash*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_cash_using_loyalty_points,
			gaming_game_plays.payment_method_id
		FROM gaming_game_plays FORCE INDEX (timestamp) 
		STRAIGHT_JOIN gaming_payment_transaction_type AS tran_type ON 
			gaming_game_plays.timestamp BETWEEN @dateFrom AND @dateTo AND 
            gaming_game_plays.game_id IS NOT NULL AND gaming_game_plays.license_type_id NOT IN (3, 6, 7) AND
			tran_type.name IN ('Bet', 'BetCancelled', 'Win', 'PJWin') AND 
			gaming_game_plays.payment_transaction_type_id=tran_type.payment_transaction_type_id  
		STRAIGHT_JOIN gaming_clients ON gaming_game_plays.client_id=gaming_clients.client_id
		WHERE gaming_game_plays.amount_cash > 0
		GROUP BY gaming_game_plays.client_stat_id, gaming_game_plays.operator_game_id, gaming_game_plays.payment_method_id;

	END IF; -- @casinoActive OR @pokerActive

	IF (@casinoActive OR @pokerActive OR @lotterySportsPoolActive) THEN

		DELETE FROM gaming_game_transactions_aggregation_player_game_pc WHERE query_date_interval_id = @queryDateIntervalID;

	END IF; -- @casinoActive OR @pokerActive OR @lotterySportsPoolActive

	IF (@lotterySportsPoolActive) THEN

		-- by player, game
		-- businessobject : AggregationTnxPlayerGamePc
		INSERT INTO gaming_game_transactions_aggregation_player_game_pc (
			client_stat_id, client_id, game_manufacturer_id, game_id, operator_game_id, 
			bet_total, bet_real, bet_bonus, bet_bonus_win_locked, jackpot_contribution, 
			win_total, win_real, win_bonus, win_bonus_win_locked, jackpot_win, num_rounds, loyalty_points,
			currency_id, query_date_interval_id, date_from, date_to, has_bet,bet_real_using_loyalty_points,bet_bonus_using_loyalty_points,
			bet_bonus_win_locked_using_loyalty_points,
      win_base,bet_real_cancelled,bet_real_cancelled_base,bet_bonus_cancelled,bet_bonus_cancelled_base
      ,bet_real_using_only_bet, bet_bonus_using_only_bet
      ,bet_real_using_only_bet_base, bet_bonus_using_only_bet_base
      ,bet_total_base,win_real_base,win_bonus_win_locked_base,win_bonus_base
	  ,num_cw_rounds
      )
		SELECT plays.client_stat_id, plays.client_id, MAX(IFNULL(games.game_manufacturer_id,0)) as game_manufacturer_id, MAX(IFNULL(games.game_id,0)) as game_id, MAX(IFNULL(gaming_operator_games.operator_game_id,0)) as operator_game_id,   
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_total*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_total*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_total, 
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_real*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_real*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_real,
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_bonus*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_bonus*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_bonus, 
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), jackpot_contribution, 0)), 0), 5) AS jackpot_contribution,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_total, 0)), 0), 5) AS win_total, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_real, 0)), 0), 5) AS win_real,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_bonus, 0)), 0), 5) AS win_bonus, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_bonus_win_locked, 0)), 0), 5) AS win_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (14), entries.amount_real, 0)), 0), 5) AS jackpot_win,
			SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1, 1, 0)) AS num_rounds,
			ROUND(IFNULL(SUM(entries.loyalty_points), 0), 5) AS loyalty_points,
			gaming_client_stats.currency_id, @queryDateIntervalID, @dateFrom, @dateTo, MAX(IF(plays.payment_transaction_type_id = 12, 1,0)) AS has_bet,
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_real*sign_mult*-1, 0) - 
				IF(tran_type.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_real*sign_mult*-1, 0)
			), 0), 5) AS bet_real_using_loyalty_points,
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus*sign_mult*-1, 0) -
				IF(tran_type.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus*sign_mult*-1, 0)
			), 0), 5) AS bet_bonus_using_loyalty_points, 
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus_win_locked*sign_mult*-1, 0) - 
				IF(tran_type.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus_win_locked*sign_mult*-1, 0)
			), 0), 5) AS bet_bonus_win_locked_using_loyalty_points, 
			ROUND(
				  IFNULL(
						  SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_total_base,0)) -   
						  SUM(IF(tran_type.payment_transaction_type_id IN (13,14),(plays.bonus_lost + plays.bonus_win_locked_lost),0))
					  ,0)
				  ,5) AS win_base, 
			  ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (20), plays.amount_real*sign_mult,0)),0),5) AS bet_real_cancelled, 
			  ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (20), plays.amount_real*sign_mult,0)),0),5) AS bet_real_cancelled_base, 
			  ROUND(
				  IFNULL(
						  SUM(IF(tran_type.payment_transaction_type_id IN (20), plays.amount_bonus*sign_mult,0)) + 
						  SUM(IF(tran_type.payment_transaction_type_id IN (20), plays.amount_bonus_win_locked*sign_mult,0))
					  ,0)
				  ,5) AS bet_bonus_cancelled, 
			  ROUND(
				  IFNULL(
						  SUM(IF(tran_type.payment_transaction_type_id IN (20), plays.amount_bonus*sign_mult,0)) + 
						  SUM(IF(tran_type.payment_transaction_type_id IN (20), plays.amount_bonus_win_locked*sign_mult,0))
					  ,0)
				  ,5) AS bet_bonus_cancelled_base,
			  ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), plays.amount_real  * sign_mult * -1, 0)), 0), 5) AS bet_real_using_only_bet,
			  ROUND(
				  IFNULL(
						  SUM(IF(tran_type.payment_transaction_type_id IN (12), plays.amount_bonus * sign_mult * -1, 0)) + 
						  SUM(IF(tran_type.payment_transaction_type_id IN (12), plays.amount_bonus_win_locked * sign_mult * -1, 0))
					  ,0)/plays.exchange_rate  
				   ,5)  AS bet_bonus_using_only_bet_base,
			  ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), plays.amount_real  * sign_mult * -1, 0)), 0) / plays.exchange_rate, 5) AS bet_real_using_only_bet_base,
			  ROUND(
				  IFNULL(
						  SUM(IF(tran_type.payment_transaction_type_id IN (12), plays.amount_bonus * sign_mult * -1, 0)) +
						  SUM(IF(tran_type.payment_transaction_type_id IN (12), plays.amount_bonus_win_locked * sign_mult * -1, 0))
					  ,0)/plays.exchange_rate
				   ,5) AS bet_bonus_using_only_bet_base,
			  ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), plays.amount_total*sign_mult*-1, 0)),0)/plays.exchange_rate, 5)  AS bet_total_base,
			  ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_real,  0)), 0)/plays.exchange_rate, 5) AS win_real_base,
			  ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_bonus_win_locked, 0)), 0)/plays.exchange_rate, 5) AS win_bonus_win_locked,
			  ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_bonus, 0)), 0)/plays.exchange_rate, 5) AS win_bonus_base,
			  COUNT(DISTINCT(game_round_id)) AS num_cw_rounds
 FROM gaming_game_plays AS plays FORCE INDEX (timestamp) 
		STRAIGHT_JOIN gaming_game_plays_lottery_entries AS entries ON 
			plays.timestamp BETWEEN @dateFrom AND @dateTo AND plays.license_type_id IN (6, 7) AND
			plays.game_play_id = entries.game_play_id
		STRAIGHT_JOIN gaming_payment_transaction_type AS tran_type ON tran_type.name IN ('Bet','BetCancelled','Win','PJWin') AND 
			plays.payment_transaction_type_id=tran_type.payment_transaction_type_id
		STRAIGHT_JOIN gaming_clients ON plays.client_id=gaming_clients.client_id
		STRAIGHT_JOIN gaming_client_stats ON plays.client_stat_id=gaming_client_stats.client_stat_id
		STRAIGHT_JOIN gaming_lottery_draws draws ON draws.lottery_draw_id=entries.lottery_draw_id
		STRAIGHT_JOIN gaming_games games ON games.game_id=draws.game_id	   
		STRAIGHT_JOIN gaming_operator_games ON gaming_operator_games.game_id=games.game_id AND gaming_operator_games.operator_id=@operatorID 
		LEFT JOIN gaming_game_plays_cw_free_rounds AS free_round ON plays.game_play_id = free_round.game_play_id
		GROUP BY plays.client_stat_id, gaming_operator_games.operator_game_id;

	END IF; -- @lotterySportsPoolActive

	IF (@casinoActive OR @pokerActive) THEN

		-- by player, game
		-- businessobject : AggregationTnxPlayerGamePc
		INSERT INTO gaming_game_transactions_aggregation_player_game_pc (
			client_stat_id, client_id, game_manufacturer_id, game_id, operator_game_id, 
			bet_total, bet_real, bet_bonus, bet_bonus_win_locked, jackpot_contribution, 
			win_total, win_real, win_bonus, win_bonus_win_locked, jackpot_win, num_rounds, loyalty_points,
			currency_id, query_date_interval_id, date_from, date_to, has_bet,bet_real_using_loyalty_points,bet_bonus_using_loyalty_points,
			bet_bonus_win_locked_using_loyalty_points,
      win_base,bet_real_cancelled,bet_real_cancelled_base,bet_bonus_cancelled,bet_bonus_cancelled_base
      ,bet_real_using_only_bet, bet_bonus_using_only_bet
      ,bet_real_using_only_bet_base, bet_bonus_using_only_bet_base
      ,bet_total_base,win_real_base,win_bonus_win_locked_base,win_bonus_base
	  ,num_cw_rounds
    )
		SELECT gaming_game_plays.client_stat_id, gaming_game_plays.client_id, game_manufacturer_id, game_id, operator_game_id, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_total*sign_mult*-1, 0)), 0), 5) AS bet_total, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_real*sign_mult*-1, 0)), 0), 5) AS bet_real,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_bonus*sign_mult*-1, 0)), 0), 5) AS bet_bonus, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_bonus_win_locked*sign_mult*-1, 0)), 0), 5) AS bet_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), jackpot_contribution, 0)), 0), 5) AS jackpot_contribution,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_total, 0)), 0), 5) AS win_total, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_real, 0)), 0), 5) AS win_real,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_bonus, 0)), 0), 5) AS win_bonus, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_bonus_win_locked, 0)), 0), 5) AS win_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (14), amount_real, 0)), 0), 5) AS jackpot_win,
			SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1, 1, 0)) AS num_rounds,
			ROUND(IFNULL(SUM(loyalty_points), 0), 5) AS loyalty_points,
			gaming_client_stats.currency_id, @queryDateIntervalID, @dateFrom, @dateTo, MAX(IF(gaming_game_plays.payment_transaction_type_id = 12, 1,0)) AS has_bet,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20) AND IFNULL(loyalty_points,0) != 0, amount_real*sign_mult*-1, 0)), 0), 5) AS bet_real_using_loyalty_points,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20) AND IFNULL(loyalty_points,0) != 0, amount_bonus*sign_mult*-1, 0)), 0), 5) AS bet_bonus_using_loyalty_points, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20) AND IFNULL(loyalty_points,0) != 0, amount_bonus_win_locked*sign_mult*-1, 0)), 0), 5) AS bet_bonus_win_locked_using_loyalty_points,
			ROUND(SUM(IF (tran_type.payment_transaction_type_id IN (13,14), amount_total_base,0)),5) - ROUND(SUM(IF (tran_type.payment_transaction_type_id IN (13,14),((gaming_game_plays.bonus_lost + gaming_game_plays.bonus_win_locked_lost)),0))/gaming_game_plays.exchange_rate,5) AS win_base, 
			ROUND(SUM(IF (tran_type.payment_transaction_type_id IN (20), gaming_game_plays.amount_real*sign_mult,0)),5) AS bet_real_cancelled, 
			ROUND(SUM(IF (tran_type.payment_transaction_type_id IN (20), gaming_game_plays.amount_real*sign_mult,0)),5)/gaming_game_plays.exchange_rate AS bet_real_cancelled_base, 
			ROUND(SUM(IF (tran_type.payment_transaction_type_id IN (20), gaming_game_plays.amount_bonus*sign_mult,0)) + SUM(IF(tran_type.payment_transaction_type_id IN (20),   gaming_game_plays.amount_bonus_win_locked*sign_mult,0)),5) AS bet_bonus_cancelled, 
			ROUND(IFNULL((SUM(IF(tran_type.payment_transaction_type_id IN (20), gaming_game_plays.amount_bonus*sign_mult,0)) + SUM(IF(tran_type.payment_transaction_type_id IN (20), gaming_game_plays.amount_bonus_win_locked*sign_mult,0)))/gaming_game_plays.exchange_rate,0),5) AS bet_bonus_cancelled_base,          
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), gaming_game_plays.amount_real * sign_mult * -1, 0)), 0), 5) AS bet_real_using_only_bet,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), gaming_game_plays.amount_bonus * sign_mult * -1, 0)), 0) + IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), gaming_game_plays.amount_bonus_win_locked * sign_mult * -1, 0)), 0), 5) AS bet_bonus_using_only_bet,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), gaming_game_plays.amount_real * sign_mult * -1, 0)), 0)/gaming_game_plays.exchange_rate, 5) AS bet_real_using_only_bet_base,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), gaming_game_plays.amount_bonus * sign_mult * -1, 0)), 0) + IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), gaming_game_plays.amount_bonus_win_locked * sign_mult * -1, 0)), 0)/gaming_game_plays.exchange_rate, 5) AS bet_bonus_using_only_bet_base,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), gaming_game_plays.amount_total*sign_mult*-1, 0)), 0)/gaming_game_plays.exchange_rate , 5)AS bet_total_base, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), gaming_game_plays.amount_real, 0))/gaming_game_plays.exchange_rate , 0), 5)AS win_real_base,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_bonus_win_locked, 0))/gaming_game_plays.exchange_rate , 0), 5)AS win_bonus_win_locked_base,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_bonus, 0)), 0)/gaming_game_plays.exchange_rate, 5) AS win_bonus_base,
			COUNT(DISTINCT(game_round_id)) AS num_cw_rounds 
  	FROM gaming_game_plays  FORCE INDEX (timestamp) 
		STRAIGHT_JOIN gaming_payment_transaction_type AS tran_type ON 
			gaming_game_plays.timestamp BETWEEN @dateFrom AND @dateTo AND 
            gaming_game_plays.game_id IS NOT NULL AND gaming_game_plays.license_type_id NOT IN (3, 6, 7) AND
			tran_type.name IN ('Bet', 'BetCancelled', 'Win', 'PJWin') AND 
			gaming_game_plays.payment_transaction_type_id=tran_type.payment_transaction_type_id 
		STRAIGHT_JOIN gaming_clients ON gaming_game_plays.client_id=gaming_clients.client_id
		STRAIGHT_JOIN gaming_client_stats ON gaming_game_plays.client_stat_id=gaming_client_stats.client_stat_id
		LEFT JOIN gaming_game_plays_cw_free_rounds AS free_round ON gaming_game_plays.game_play_id = free_round.game_play_id 
		GROUP BY gaming_game_plays.client_stat_id, gaming_game_plays.operator_game_id;

	END IF; -- @casinoActive OR @pokerActive

	IF(@lotterySportsPoolActive) THEN

		DELETE FROM gaming_game_transactions_aggregation_lottery_draw_platform WHERE query_date_interval_id = @queryDateIntervalID;

		INSERT INTO gaming_game_transactions_aggregation_lottery_draw_platform (lottery_draw_id, game_manufacturer_id, game_id, currency_id, platform_type_id,
			player_count, bet_count, bet_total, bet_real, bet_bonus, bet_bonus_win_locked, jackpot_contribution, gross_total, net_total, win_total, win_real,
			win_bonus, win_bonus_win_locked, jackpot_win, loyalty_points, bet_real_using_loyalty_points, bet_bonus_using_loyalty_points, 
			bet_bonus_win_locked_using_loyalty_points, query_date_interval_id, date_from, date_to)
		SELECT entries.lottery_draw_id, MAX(IFNULL(games.game_manufacturer_id,0)) as game_manufacturer_id, MAX(IFNULL(games.game_id,0)) as game_id, MAX(plays.currency_id) as currency_id, 
			MAX(IFNULL(plays.platform_type_id, (SELECT gaming_game_plays_platform.platform_type_id FROM gaming_game_plays as gaming_game_plays_platform 
			WHERE gaming_game_plays_platform.client_id = plays.client_id AND gaming_game_plays_platform.sb_bet_id = plays.sb_bet_id AND gaming_game_plays_platform.is_cancelled = 0))) as platform_type_id, COUNT(DISTINCT plays.client_id) as player_count, 
			SUM(IF(plays.payment_transaction_type_id IN (12,20),1,0)) as bet_count,
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12), entries.amount_total*sign_mult*-1/exchange_rate, 0) -
				IF(plays.payment_transaction_type_id IN (20), entries.amount_total*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_total, 
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12), entries.amount_real*sign_mult*-1/exchange_rate, 0) -
				IF(plays.payment_transaction_type_id IN (20), entries.amount_real*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_real,
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12), entries.amount_bonus*sign_mult*-1/exchange_rate, 0) -
				IF(plays.payment_transaction_type_id IN (20), entries.amount_bonus*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_bonus, 
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12), entries.amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0) -
				IF(plays.payment_transaction_type_id IN (20), entries.amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (12), plays.jackpot_contribution, 0)), 0), 5) AS jackpot_contribution,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14),prizes.gross,0)), 0), 5) as gross_total,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14),prizes.net,0)), 0), 5) as net_total,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14), entries.amount_total, 0)), 0), 5) AS win_total, 
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14), entries.amount_real, 0)), 0), 5) AS win_real,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14), entries.amount_bonus, 0)), 0), 5) AS win_bonus, 
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14), entries.amount_bonus_win_locked, 0)), 0), 5) AS win_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (14), entries.amount_real, 0)), 0), 5) AS jackpot_win,
			ROUND(IFNULL(SUM(entries.loyalty_points), 0), 5) AS loyalty_points,
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_real*sign_mult*-1, 0) - 
				IF(plays.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_real*sign_mult*-1, 0)
			), 0), 5) AS bet_real_using_loyalty_points,
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus*sign_mult*-1, 0) -
				IF(plays.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus*sign_mult*-1, 0)
			), 0), 5) AS bet_bonus_using_loyalty_points, 
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus_win_locked*sign_mult*-1, 0) - 
				IF(plays.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus_win_locked*sign_mult*-1, 0)
			), 0), 5) AS bet_bonus_win_locked_using_loyalty_points, 
			@queryDateIntervalID, @dateFrom, @dateTo
		FROM gaming_game_plays plays FORCE INDEX (timestamp)
		STRAIGHT_JOIN gaming_game_plays_lottery_entries entries ON plays.timestamp BETWEEN @dateFrom AND @dateTo AND 
			plays.game_play_id = entries.game_play_id
		LEFT JOIN gaming_lottery_draws draws ON draws.lottery_draw_id=entries.lottery_draw_id
		LEFT JOIN gaming_games games ON games.game_id=draws.game_id
		LEFT JOIN gaming_lottery_participation_prizes prizes ON entries.lottery_participation_id = prizes.lottery_participation_id
		GROUP BY entries.lottery_draw_id, plays.platform_type_id;

		DELETE FROM gaming_game_transactions_aggregation_lottery_client_draw WHERE query_date_interval_id = @queryDateIntervalID;

		INSERT INTO gaming_game_transactions_aggregation_lottery_client_draw (
			client_id, lottery_draw_id, game_manufacturer_id, game_id, 
			currency_id, platform_type_id, player_count, bet_count, 
			bet_total, bet_real, bet_bonus, bet_bonus_win_locked, 
			jackpot_contribution, gross_total, net_total, win_total, 
			win_real, win_bonus, win_bonus_win_locked, jackpot_win, 
			loyalty_points, bet_real_using_loyalty_points, bet_bonus_using_loyalty_points,bet_bonus_win_locked_using_loyalty_points, 
			query_date_interval_id, date_from, date_to, bet_cash, 
			win_cash, bet_cash_using_loyalty_points, gross_total_cash, net_total_cash, 
			player_count_cash, bet_count_cash
		)
		SELECT plays.client_id, entries.lottery_draw_id, MAX(IFNULL(games.game_manufacturer_id,0)) as game_manufacturer_id, 
			MAX(IFNULL(games.game_id,0)) as game_id, MAX(plays.currency_id) as currency_id, 
			MAX(IFNULL(plays.platform_type_id, (SELECT gaming_game_plays_platform.platform_type_id FROM gaming_game_plays as gaming_game_plays_platform 
			WHERE gaming_game_plays_platform.client_id = plays.client_id AND gaming_game_plays_platform.sb_bet_id = plays.sb_bet_id AND gaming_game_plays_platform.is_cancelled = 0))) as platform_type_id, COUNT(DISTINCT CASE WHEN plays.amount_cash = 0 THEN plays.client_id END) as player_count, 
            SUM(
				IF(plays.payment_transaction_type_id IN (12)  AND plays.amount_cash = 0, 1, 0) -
				IF(plays.payment_transaction_type_id IN (20)  AND plays.amount_cash = 0, 1, 0)
			) as bet_count,
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12), entries.amount_total*sign_mult*-1/exchange_rate, 0) -
				IF(plays.payment_transaction_type_id IN (20), entries.amount_total*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_total, 
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12), entries.amount_real*sign_mult*-1/exchange_rate, 0) -
				IF(plays.payment_transaction_type_id IN (20), entries.amount_real*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_real,
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12), entries.amount_bonus*sign_mult*-1/exchange_rate, 0) -
				IF(plays.payment_transaction_type_id IN (20), entries.amount_bonus*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_bonus, 
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12), entries.amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0) -
				IF(plays.payment_transaction_type_id IN (20), entries.amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (12), plays.jackpot_contribution, 0)), 0), 5) AS jackpot_contribution,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14),prizes.gross,0)), 0), 5) as gross_total,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14),prizes.net,0)), 0), 5) as net_total,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14), entries.amount_total, 0)), 0), 5) AS win_total, 
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14), entries.amount_real, 0)), 0), 5) AS win_real,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14), entries.amount_bonus, 0)), 0), 5) AS win_bonus,  
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14), entries.amount_bonus_win_locked, 0)), 0), 5) AS win_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (14), entries.amount_real, 0)), 0), 5) AS jackpot_win,
			ROUND(IFNULL(SUM(entries.loyalty_points), 0), 5) AS loyalty_points,
				ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_real*sign_mult*-1, 0) - 
				IF(plays.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_real*sign_mult*-1, 0)
			), 0), 5) AS bet_real_using_loyalty_points,
				ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus*sign_mult*-1, 0) -
				IF(plays.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus*sign_mult*-1, 0)
			), 0), 5) AS bet_bonus_using_loyalty_points, 
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus_win_locked*sign_mult*-1, 0) - 
				IF(plays.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_bonus_win_locked*sign_mult*-1, 0)
			), 0), 5) AS bet_bonus_win_locked_using_loyalty_points, 
			@queryDateIntervalID, @dateFrom, @dateTo,
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12), entries.amount_cash*sign_mult*-1/exchange_rate, 0) -
				IF(plays.payment_transaction_type_id IN (20), entries.amount_cash*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_cash, 			
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14), entries.amount_cash/exchange_rate, 0)), 0), 5) AS win_cash,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (12,20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_cash*sign_mult*-1/exchange_rate, 0)), 0), 5) AS bet_cash_using_loyalty_points,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14) AND entries.amount_cash > 0,prizes.gross,0)), 0), 5) as gross_total_cash,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14) AND entries.amount_cash > 0,prizes.net,0)), 0), 5) as net_total_cash,
			COUNT(DISTINCT CASE WHEN entries.amount_cash > 0 THEN plays.client_id END) as player_count_cash, 
			SUM(
				IF(plays.payment_transaction_type_id IN (12)  AND plays.amount_cash <> 0, 1, 0) -
				IF(plays.payment_transaction_type_id IN (20)  AND plays.amount_cash <> 0, 1, 0)
			) as bet_count_cash
		FROM gaming_game_plays plays FORCE INDEX (timestamp) 
		STRAIGHT_JOIN gaming_game_plays_lottery_entries entries ON plays.timestamp BETWEEN @dateFrom AND @dateTo AND plays.license_type_id IN (6, 7) AND
			plays.game_play_id = entries.game_play_id
		LEFT JOIN gaming_lottery_draws draws ON draws.lottery_draw_id=entries.lottery_draw_id
		LEFT JOIN gaming_games games ON games.game_id=draws.game_id
		LEFT JOIN gaming_lottery_participation_prizes prizes ON entries.lottery_participation_id = prizes.lottery_participation_id
		GROUP BY plays.client_id,entries.lottery_draw_id, plays.platform_type_id;

		DELETE FROM gaming_game_transactions_aggregation_lottery_client_draw_pm WHERE query_date_interval_id = @queryDateIntervalID;

		INSERT INTO gaming_game_transactions_aggregation_lottery_client_draw_pm (client_id, lottery_draw_id, game_manufacturer_id, game_id, currency_id, platform_type_id,
			player_count, bet_count, gross_total, net_total, loyalty_points, query_date_interval_id, date_from, date_to, bet_cash, win_cash, bet_cash_using_loyalty_points, payment_method_id)
		SELECT plays.client_id, entries.lottery_draw_id, MAX(IFNULL(games.game_manufacturer_id,0)) as game_manufacturer_id, MAX(IFNULL(games.game_id,0)) as game_id, MAX(plays.currency_id) as currency_id, 
			MAX(IFNULL(plays.platform_type_id, (SELECT gaming_game_plays_platform.platform_type_id FROM gaming_game_plays as gaming_game_plays_platform 
			WHERE gaming_game_plays_platform.client_id = plays.client_id AND gaming_game_plays_platform.sb_bet_id = plays.sb_bet_id AND gaming_game_plays_platform.is_cancelled = 0))) 
			as platform_type_id, COUNT(DISTINCT plays.client_id) as player_count, 
			SUM(
				IF(plays.payment_transaction_type_id IN (12), 1, 0) -
				IF(plays.payment_transaction_type_id IN (20), 1, 0)
			) as bet_count,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14),prizes.gross,0)), 0), 5) as gross_total,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14),prizes.net,0)), 0), 5) as net_total,
			ROUND(IFNULL(SUM(entries.loyalty_points), 0), 5) AS loyalty_points,
			@queryDateIntervalID, @dateFrom, @dateTo,
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12), entries.amount_cash*sign_mult*-1/exchange_rate, 0) - 
				IF(plays.payment_transaction_type_id IN (20), entries.amount_cash*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_cash,
			ROUND(IFNULL(SUM(IF(plays.payment_transaction_type_id IN (13,14), entries.amount_cash/exchange_rate, 0)), 0), 5) AS win_cash,
			ROUND(IFNULL(SUM(
				IF(plays.payment_transaction_type_id IN (12) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_cash*sign_mult*-1/exchange_rate, 0) - 
				IF(plays.payment_transaction_type_id IN (20) AND IFNULL(entries.loyalty_points,0) != 0, entries.amount_cash*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_cash_using_loyalty_points,
			plays.payment_method_id
		FROM gaming_game_plays plays FORCE INDEX (timestamp)
		STRAIGHT_JOIN gaming_game_plays_lottery_entries entries ON plays.timestamp BETWEEN @dateFrom AND @dateTo AND plays.license_type_id IN (6,7) AND
			plays.game_play_id = entries.game_play_id
		LEFT JOIN gaming_lottery_draws draws ON draws.lottery_draw_id=entries.lottery_draw_id
		LEFT JOIN gaming_games games ON games.game_id=draws.game_id
		LEFT JOIN gaming_lottery_participation_prizes prizes ON entries.lottery_participation_id = prizes.lottery_participation_id
		WHERE plays.amount_cash > 0
		GROUP BY plays.client_id,entries.lottery_draw_id, plays.platform_type_id, plays.payment_method_id;

	END IF;

	IF (@sportsBookActive) THEN

		-- Default Sports Entities should have already been created but just in case
		CALL SportsCreateDefaultSportsEntities();

		-- by sb sport, test player
		-- businessobject : AggregationTnxSbSport
		DELETE FROM gaming_game_transactions_aggregation_sb_sport WHERE query_date_interval_id=@queryDateIntervalID;

		INSERT INTO gaming_game_transactions_aggregation_sb_sport (sb_sport_id, game_manufacturer_id,
			bet_real, bet_bonus, win_real, win_bonus, num_units, 
			query_date_interval_id, date_from, date_to,num_players, test_players)
		SELECT IFNULL(sb_sport_id, 0), game_manufacturer_id,
	    ROUND(IFNULL(SUM(
        (CASE 
          WHEN payment_transaction_type_id IN (12) THEN amount_real_base
          WHEN payment_transaction_type_id IN (20) THEN amount_real_base*-1
          ELSE 0

         END)
			), 0), 5) AS bet_real,
      ROUND(IFNULL(SUM(
        (CASE 
          WHEN payment_transaction_type_id IN (12) THEN amount_bonus_base
          WHEN payment_transaction_type_id IN (20) THEN amount_bonus_base*-1
          ELSE 0

         END)   
			), 0), 5) AS bet_bonus,
      ROUND(IFNULL(SUM(
				IF(payment_transaction_type_id IN (13, 14), amount_real_base, 0)				
			), 0), 5) AS win_real,
      ROUND(IFNULL(SUM(
				IF(payment_transaction_type_id IN (13, 14), amount_bonus_base, 0)				
			), 0), 5) AS win_bonus,
			SUM(units) AS num_units,
			@queryDateIntervalID, @dateFrom, @dateTo,COUNT(DISTINCT(client_stat_id)), gaming_clients.is_test_player
		FROM gaming_game_plays_sb  FORCE INDEX (timestamp) 
		JOIN gaming_clients ON gaming_game_plays_sb.client_id = gaming_clients.client_id
		WHERE gaming_game_plays_sb.timestamp BETWEEN @dateFrom AND @dateTo AND gaming_game_plays_sb.sb_sport_id
		GROUP BY IFNULL(gaming_game_plays_sb.sb_sport_id, 0), gaming_clients.is_test_player;

		-- Update events which where null and entered as id 0 to the defualt event
		UPDATE gaming_game_transactions_aggregation_sb_sport AS agg FORCE INDEX (query_date_interval_id)
		JOIN gaming_sb_sports ON gaming_sb_sports.game_manufacturer_id=agg.game_manufacturer_id AND gaming_sb_sports.ext_sport_id='default'
		SET agg.sb_sport_id=gaming_sb_sports.sb_sport_id
		WHERE agg.query_date_interval_id=@queryDateIntervalID AND agg.sb_sport_id=0;

		-- by sb event, test player
		-- businessobject : AggregationTnxSbEvent
		DELETE FROM gaming_game_transactions_aggregation_sb_event WHERE query_date_interval_id = @queryDateIntervalID;


INSERT INTO gaming_game_transactions_aggregation_sb_event (sb_event_id, game_manufacturer_id,
			bet_real, bet_bonus, win_real, win_bonus, num_units, 
			query_date_interval_id, date_from, date_to, test_players)
		SELECT IFNULL(sb_event_id, 0), game_manufacturer_id, ROUND(IFNULL(SUM(

        (CASE 
          WHEN payment_transaction_type_id IN (12) THEN amount_real_base
          WHEN payment_transaction_type_id IN (20) THEN amount_real_base*-1
          ELSE 0

         END)  
			), 0), 5) AS bet_real,
      ROUND(IFNULL(SUM(
        (CASE 
          WHEN payment_transaction_type_id IN (12) THEN amount_bonus_base
          WHEN payment_transaction_type_id IN (20) THEN amount_bonus_base*-1
          ELSE 0

         END)  
			), 0), 5) AS bet_bonus,
      ROUND(IFNULL(SUM(
				IF(payment_transaction_type_id IN (13, 14), amount_real_base, 0)				
			), 0), 5) AS win_real,
      ROUND(IFNULL(SUM(
				IF(payment_transaction_type_id IN (13, 14), amount_bonus_base, 0)				
			), 0), 5) AS win_bonus,
			SUM(units) AS num_units,
			@queryDateIntervalID, @dateFrom, @dateTo, gaming_clients.is_test_player
		FROM gaming_game_plays_sb  FORCE INDEX (timestamp) 
		JOIN gaming_clients ON gaming_game_plays_sb.client_id = gaming_clients.client_id
		WHERE gaming_game_plays_sb.timestamp BETWEEN @dateFrom AND @dateTo AND gaming_game_plays_sb.sb_event_id
		GROUP BY IFNULL(gaming_game_plays_sb.sb_event_id, 0), gaming_clients.is_test_player;

		-- Update events which where null and entered as id 0 to the defualt event
		UPDATE gaming_game_transactions_aggregation_sb_event AS agg FORCE INDEX (query_date_interval_id)
		JOIN gaming_sb_sports ON gaming_sb_sports.game_manufacturer_id=agg.game_manufacturer_id AND gaming_sb_sports.ext_sport_id='default'
		JOIN gaming_sb_regions ON gaming_sb_sports.sb_sport_id=gaming_sb_regions.sb_sport_id AND gaming_sb_regions.ext_region_id='default'
		JOIN gaming_sb_groups ON gaming_sb_regions.sb_region_id=gaming_sb_groups.sb_region_id AND gaming_sb_groups.ext_group_id='default'
		JOIN gaming_sb_events ON gaming_sb_groups.sb_group_id=gaming_sb_events.sb_group_id AND gaming_sb_events.ext_event_id='default'
		SET agg.sb_event_id=gaming_sb_events.sb_event_id
		WHERE agg.query_date_interval_id=@queryDateIntervalID AND agg.sb_event_id=0;

		-- player, sport, multiple_type
		DELETE FROM gaming_game_transactions_aggregation_sb_player_sport WHERE query_date_interval_id=@queryDateIntervalID;

		INSERT INTO gaming_game_transactions_aggregation_sb_player_sport (client_id, client_stat_id, sb_sport_id, sb_multiple_type_id, game_manufacturer_id,
			bet_real, bet_bonus, win_real, win_bonus, num_units, 
			query_date_interval_id, date_from, date_to)
		SELECT client_id, client_stat_id, IFNULL(sb_sport_id, 0), IFNULL(sb_multiple_type_id, 0), game_manufacturer_id,
		ROUND(IFNULL(SUM(
        (CASE 
          WHEN payment_transaction_type_id IN (12) THEN amount_real_base
          WHEN payment_transaction_type_id IN (20) THEN amount_real_base*-1
          ELSE 0

         END)   
			), 0), 5) AS bet_real,
      ROUND(IFNULL(SUM(
        (CASE 
          WHEN payment_transaction_type_id IN (12) THEN amount_bonus_base
          WHEN payment_transaction_type_id IN (20) THEN amount_bonus_base*-1
          ELSE 0

         END) 
			), 0), 5) AS bet_bonus,
      ROUND(IFNULL(SUM(
				IF(payment_transaction_type_id IN (13, 14), amount_real_base, 0)				
			), 0), 5) AS win_real,
      ROUND(IFNULL(SUM(
				IF(payment_transaction_type_id IN (13, 14), amount_bonus_base, 0)				
			), 0), 5) AS win_bonus,
			SUM(units) AS num_units,
			@queryDateIntervalID, @dateFrom, @dateTo
		FROM gaming_game_plays_sb  FORCE INDEX (timestamp) 
		WHERE gaming_game_plays_sb.timestamp BETWEEN @dateFrom AND @dateTo 
		GROUP BY gaming_game_plays_sb.client_stat_id, IFNULL(gaming_game_plays_sb.sb_sport_id, 0), IFNULL(gaming_game_plays_sb.sb_multiple_type_id, 0);

		-- Multiple Type, Sport, Test Players: Yes/No
		DELETE FROM gaming_game_transactions_aggregation_sb_multiple_type_sport WHERE query_date_interval_id=@queryDateIntervalID;

		INSERT INTO gaming_game_transactions_aggregation_sb_multiple_type_sport (sb_multiple_type_id, sb_sport_id, game_manufacturer_id,
			bet_real, bet_bonus, win_real, win_bonus, num_units, 
			query_date_interval_id, date_from, date_to, num_players, test_players)
		SELECT sb_multiple_type_id, IFNULL(sb_sport_id, 0), game_manufacturer_id,
			ROUND(IFNULL(SUM(
        (CASE 
          WHEN payment_transaction_type_id IN (12) THEN amount_real_base
          WHEN payment_transaction_type_id IN (20) THEN amount_real_base*-1
          ELSE 0

         END)    
			), 0), 5) AS bet_real,
      ROUND(IFNULL(SUM(
        (CASE 
          WHEN payment_transaction_type_id IN (12) THEN amount_bonus_base
          WHEN payment_transaction_type_id IN (20) THEN amount_bonus_base*-1
          ELSE 0

         END)    
			), 0), 5) AS bet_bonus,
      ROUND(IFNULL(SUM(
				IF(payment_transaction_type_id IN (13, 14), amount_real_base, 0)				
			), 0), 5) AS win_real,
      ROUND(IFNULL(SUM(
				IF(payment_transaction_type_id IN (13,14), amount_bonus_base, 0)				
			), 0), 5) AS win_bonus,
			SUM(units) AS num_units,
			@queryDateIntervalID, @dateFrom, @dateTo, COUNT(DISTINCT(client_stat_id)), gaming_clients.is_test_player
		FROM gaming_game_plays_sb  FORCE INDEX (timestamp) 
		JOIN gaming_clients ON gaming_game_plays_sb.client_id = gaming_clients.client_id
		WHERE gaming_game_plays_sb.timestamp BETWEEN @dateFrom AND @dateTo AND gaming_game_plays_sb.sb_sport_id IS NOT NULL
		GROUP BY IFNULL(gaming_game_plays_sb.sb_multiple_type_id,0), IFNULL(gaming_game_plays_sb.sb_sport_id, 0), gaming_clients.is_test_player;

	END IF;

  --  ////////////
  -- Pool betting --
  -- ////////////
  IF (@poolBettingActive) THEN
    
	-- by pb league, site, test player
	-- businessobject : AggregationTnxPlayerGamePc
    DELETE FROM gaming_game_transactions_aggregation_pb_leagues WHERE query_date_interval_id=@queryDateIntervalID;
    INSERT INTO gaming_game_transactions_aggregation_pb_leagues (pb_league_id, game_manufacturer_id,
      bet_real, bet_bonus, win_real, win_bonus, num_units, operator_commision, platform_commision,
      query_date_interval_id, date_from, date_to,num_players, site_id, cash_in_real, cash_in_bonus, test_players)
    SELECT pb_league_id, gaming_game_plays.game_manufacturer_id,
      ROUND(IFNULL(SUM(IF(gaming_game_plays_pb.payment_transaction_type_id IN (12,20,140), amount_real_base * IF(gaming_game_plays_pb.payment_transaction_type_id IN (20,140),-1,1),  0)), 0), 5) AS bet_real,
      ROUND(IFNULL(SUM(IF(gaming_game_plays_pb.payment_transaction_type_id IN (12,20,140), amount_bonus_base* IF(gaming_game_plays_pb.payment_transaction_type_id IN (20,140),-1,1), 0)), 0), 5) AS bet_bonus,
      ROUND(IFNULL(SUM(IF(gaming_game_plays_pb.payment_transaction_type_id IN (13), amount_real_base,  0)), 0), 5) AS win_real,
      ROUND(IFNULL(SUM(IF(gaming_game_plays_pb.payment_transaction_type_id IN (13), amount_bonus_base, 0)), 0), 5) AS win_bonus, 
      SUM(units) AS num_units,SUM(operator_commision_base) AS operator_commision,SUM(platform_commision_base) AS platform_commision,
      @queryDateIntervalID, @dateFrom, @dateTo,COUNT(DISTINCT(gaming_game_plays_pb.client_stat_id)), IFNULL(sessions_main.site_id, 1), 
	  ROUND(IFNULL(SUM(IF(gaming_game_plays_pb.payment_transaction_type_id IN (231), amount_real_base,0)), 0), 5) AS cash_in_real,
	  ROUND(IFNULL(SUM(IF(gaming_game_plays_pb.payment_transaction_type_id IN (231), amount_bonus_base,0)), 0), 5) AS cash_in_bonus, 
	gaming_clients.is_test_player
    FROM gaming_game_plays_pb  FORCE INDEX (timestamp) 
	JOIN gaming_pb_pools ON gaming_game_plays_pb.pb_pool_id = gaming_pb_pools.pb_pool_id
	JOIN gaming_clients ON gaming_game_plays_pb.client_id = gaming_clients.client_id
	JOIN gaming_game_plays ON gaming_game_plays_pb.game_play_id = gaming_game_plays.game_play_id
	LEFT JOIN sessions_main ON gaming_game_plays.session_id = sessions_main.session_id
    WHERE gaming_game_plays_pb.timestamp BETWEEN @dateFrom AND @dateTo 
    GROUP BY gaming_game_plays_pb.pb_league_id, IFNULL(sessions_main.site_id, 1), gaming_clients.is_test_player;

	-- By Pool (poolbetting)
	-- by pb pool, site, test player
	-- businessobject : AggregationTnxPlayerGamePc
	DELETE FROM gaming_game_transactions_aggregation_pb_pool WHERE query_date_interval_id=@queryDateIntervalID;
	
    INSERT INTO gaming_game_transactions_aggregation_pb_pool (pb_pool_id, game_manufacturer_id,
      bet_real, bet_bonus, win_real, win_bonus, num_units, operator_commission, platform_commission,
      query_date_interval_id, date_from, date_to,num_players, site_id, cash_in_real, cash_in_bonus, test_players)
    SELECT gaming_pb_pools.pb_pool_id, gaming_game_plays.game_manufacturer_id,
      ROUND(IFNULL(SUM(IF(gaming_game_plays_pb.payment_transaction_type_id IN (12,20,140), amount_real_base * IF(gaming_game_plays_pb.payment_transaction_type_id IN (20,140),-1,1),  0)), 0), 5) AS bet_real,
      ROUND(IFNULL(SUM(IF(gaming_game_plays_pb.payment_transaction_type_id IN (12,20,140), amount_bonus_base* IF(gaming_game_plays_pb.payment_transaction_type_id IN (20,140),-1,1), 0)), 0), 5) AS bet_bonus,
      ROUND(IFNULL(SUM(IF(gaming_game_plays_pb.payment_transaction_type_id IN (13), amount_real_base,  0)), 0), 5) AS win_real,
      ROUND(IFNULL(SUM(IF(gaming_game_plays_pb.payment_transaction_type_id IN (13), amount_bonus_base, 0)), 0), 5) AS win_bonus, 
      SUM(units) AS num_units,SUM(operator_commision_base) AS operator_commision,SUM(platform_commision_base) AS platform_commision,
      @queryDateIntervalID, @dateFrom, @dateTo,COUNT(DISTINCT(gaming_game_plays_pb.client_stat_id)), IFNULL(sessions_main.site_id, 1), 
	  ROUND(IFNULL(SUM(IF(gaming_game_plays_pb.payment_transaction_type_id IN (231), amount_real_base,0)), 0), 5) AS cash_in_real,
	  ROUND(IFNULL(SUM(IF(gaming_game_plays_pb.payment_transaction_type_id IN (231), amount_bonus_base,0)), 0), 5) AS cash_in_bonus,
		gaming_clients.is_test_player
    FROM gaming_game_plays_pb  FORCE INDEX (timestamp) 
	JOIN gaming_pb_pools ON gaming_game_plays_pb.pb_pool_id = gaming_pb_pools.pb_pool_id
	JOIN gaming_clients ON gaming_game_plays_pb.client_id = gaming_clients.client_id
	JOIN gaming_game_plays ON gaming_game_plays_pb.game_play_id = gaming_game_plays.game_play_id
	LEFT JOIN sessions_main ON gaming_game_plays.session_id = sessions_main.session_id
    WHERE gaming_game_plays_pb.timestamp BETWEEN @dateFrom AND @dateTo 
    GROUP BY gaming_game_plays_pb.pb_pool_id, IFNULL(sessions_main.site_id, 1), gaming_clients.is_test_player;
  
  END IF;

  IF (@bonusEnabled) THEN
	-- by bonus rule, test player
	-- businessobject : AggregationTnxPlayerGamePc
    DELETE FROM gaming_game_transactions_aggregation_bonus WHERE query_date_interval_id=@queryDateIntervalID;
    INSERT INTO gaming_game_transactions_aggregation_bonus (bonus_rule_id, bet_real, bet_bonus, wager_contribution, win_real, win_bonus, num_units, num_players,
      query_date_interval_id, date_from, date_to, test_players)
    SELECT gaming_bonus_rules.bonus_rule_id, IFNULL(Bets.bet_real,0), IFNULL(Bets.bet_bonus,0), IFNULL(Bets.wager_contribution,0), 
     IFNULL(Wins.win_real,0), IFNULL(Wins.win_bonus,0), IFNULL(Bets.num_units,0), IFNULL(Bets.num_players,0), @queryDateIntervalID, @dateFrom, @dateTo,
	Bets.is_test_player
    FROM gaming_bonus_rules
    LEFT JOIN
    (
      SELECT bonus_rule_id, COUNT(game_play_bonus_instance_id) AS num_units, COUNT(DISTINCT gaming_game_plays_bonus_instances.client_stat_id) AS num_players, SUM(bet_real/exchange_rate) AS bet_real, 
		SUM((bet_bonus+bet_bonus_win_locked)/exchange_rate) AS bet_bonus, SUM((wager_requirement_contribution-IFNULL(wager_requirement_contribution_cancelled,0))/exchange_rate) AS wager_contribution,
	gaming_clients.is_test_player
      FROM gaming_game_plays_bonus_instances
			JOIN gaming_client_stats ON gaming_game_plays_bonus_instances.client_stat_id = gaming_client_stats.client_stat_id
    JOIN gaming_clients ON gaming_client_stats.client_id = gaming_clients.client_id

      WHERE timestamp BETWEEN @dateFrom AND @dateTo
      GROUP BY bonus_rule_id, gaming_clients.is_test_player
    ) AS Bets ON gaming_bonus_rules.bonus_rule_id=Bets.bonus_rule_id
    LEFT JOIN
    (
  SELECT gaming_game_plays_bonus_instances_wins.bonus_rule_id, 
   IFNULL(SUM(gaming_game_plays.amount_real/gaming_game_plays_bonus_instances_wins.exchange_rate),0) AS win_real,
   SUM((gaming_game_plays_bonus_instances_wins.win_bonus+gaming_game_plays_bonus_instances_wins.win_bonus_win_locked)/gaming_game_plays_bonus_instances_wins.exchange_rate) AS win_bonus, 
	gaming_clients.is_test_player
  FROM gaming_game_plays_bonus_instances_wins
JOIN gaming_client_stats ON gaming_game_plays_bonus_instances_wins.client_stat_id = gaming_client_stats.client_stat_id
    JOIN gaming_clients ON gaming_client_stats.client_id = gaming_clients.client_id

  LEFT JOIN gaming_game_plays_bonus_instances 
   ON gaming_game_plays_bonus_instances_wins.game_play_bonus_instance_id = gaming_game_plays_bonus_instances.game_play_bonus_instance_id
  LEFT JOIN gaming_game_plays 
   ON gaming_game_plays_bonus_instances_wins.win_game_play_id = gaming_game_plays.game_play_id AND gaming_game_plays_bonus_instances.bonus_order=1
  WHERE gaming_game_plays_bonus_instances_wins.timestamp BETWEEN @dateFrom AND @dateTo
  GROUP BY bonus_rule_id, gaming_clients.is_test_player
 ) AS Wins ON gaming_bonus_rules.bonus_rule_id=Wins.bonus_rule_id and  Bets.is_test_player=Wins.is_test_player
    WHERE Bets.bonus_rule_id IS NOT NULL OR Wins.bonus_rule_id IS NOT NULL;
  END IF;

  IF (@promotionEnabled) THEN
	-- by promotion, test player
	-- businessobject : AggregationTnxPlayerGamePc
    DELETE FROM  gaming_game_transactions_aggregation_promotion WHERE query_date_interval_id=@queryDateIntervalID;
    INSERT INTO gaming_game_transactions_aggregation_promotion (promotion_id, bet_real, bet_bonus, win_real, win_bonus, win_contribution, bet_contribution, loss_contribution, num_units, num_players, 
      query_date_interval_id, date_from, date_to, test_players)
    SELECT contributions.promotion_id, SUM(gaming_game_rounds.bet_real/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)) AS bet_real, SUM((gaming_game_rounds.bet_bonus+gaming_game_rounds.bet_bonus_win_locked)/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)) AS bet_bonus, 
      SUM(gaming_game_rounds.win_real/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)) AS win_real, SUM((gaming_game_rounds.win_bonus+gaming_game_rounds.win_bonus_win_locked)/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)) AS win_bonus, 
      SUM(contributions.bet/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)) AS bet_contribution, SUM(contributions.win/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)) AS win_contribution, SUM(contributions.loss/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)) AS loss_contribution,
      COUNT(gaming_game_rounds.game_round_id) AS num_units, COUNT(DISTINCT gaming_game_rounds.client_stat_id) AS num_players, @queryDateIntervalID, @dateFrom, @dateTo, gaming_clients.is_test_player
    FROM gaming_game_rounds_promotion_contributions AS contributions
    JOIN gaming_game_rounds ON contributions.timestamp BETWEEN @dateFrom AND @dateTo AND contributions.game_round_id=gaming_game_rounds.game_round_id
    JOIN gaming_operator_currency ON gaming_game_rounds.currency_id=gaming_operator_currency.currency_id
  JOIN gaming_clients ON gaming_game_rounds.client_id=gaming_clients.client_id
	GROUP BY contributions.promotion_id, gaming_clients.is_test_player;
    
  END IF;

  IF (@tournamentEnabled) THEN
	-- by tournament, test player
	-- businessobject : AggregationTnxTournament
    DELETE FROM  gaming_game_transactions_aggregation_tournament WHERE query_date_interval_id=@queryDateIntervalID;
    INSERT INTO gaming_game_transactions_aggregation_tournament (tournament_id, bet_real, bet_bonus, win_real, win_bonus, win_contribution, bet_contribution, loss_contribution, num_units, num_players, 
      query_date_interval_id, date_from, date_to, test_players)
    SELECT contributions.tournament_id, SUM(gaming_game_rounds.bet_real/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)) AS bet_real, SUM((gaming_game_rounds.bet_bonus+gaming_game_rounds.bet_bonus_win_locked)/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)) AS bet_bonus, 
      SUM(gaming_game_rounds.win_real/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)) AS win_real, SUM((gaming_game_rounds.win_bonus+gaming_game_rounds.win_bonus_win_locked)/IFNULL(gaming_game_rounds.exchange_rate,gaming_operator_currency.exchange_rate)) AS win_bonus, 
      SUM(contributions.bet) AS bet_contribution, SUM(contributions.win) AS win_contribution, SUM(contributions.loss) AS loss_contribution, 
      COUNT(gaming_game_rounds.game_round_id) AS num_units, COUNT(DISTINCT gaming_game_rounds.client_stat_id) AS num_players, @queryDateIntervalID, @dateFrom, @dateTo, gaming_clients.is_test_player
    FROM gaming_game_rounds_tournament_contributions AS contributions
    JOIN gaming_game_rounds ON contributions.timestamp BETWEEN @dateFrom AND @dateTo AND contributions.game_round_id=gaming_game_rounds.game_round_id
	JOIN gaming_operator_currency ON gaming_game_rounds.currency_id=gaming_operator_currency.currency_id	
	JOIN gaming_clients ON gaming_game_rounds.client_id=gaming_clients.client_id
	GROUP BY contributions.tournament_id, gaming_clients.is_test_player;

  END IF;


	-- By Player, Licence, site
	-- businessobject : AggregationTnxPlayerLicenseSite
	DELETE FROM gaming_game_transactions_aggregation_licence_player WHERE query_date_interval_id = @queryDateIntervalID;
    INSERT INTO gaming_game_transactions_aggregation_licence_player (
      client_stat_id, client_id, 
      bet_total, bet_real, bet_bonus, bet_bonus_win_locked, jackpot_contribution, 
      win_total, win_real, win_bonus, win_bonus_win_locked, jackpot_win, num_rounds, loyalty_points,
      currency_id, query_date_interval_id, date_from, date_to, has_bet, site_id, licence_type_id, cash_in_real, cash_in_bonus, operator_commission, platform_commission)
	SELECT plays.client_stat_id, plays.client_id, 
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), plays.amount_total*sign_mult*-1/plays.exchange_rate, 0)), 0), 5) AS bet_total, 
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), plays.amount_real*sign_mult*-1/plays.exchange_rate, 0)), 0), 5) AS bet_real,
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), plays.amount_bonus*sign_mult*-1/plays.exchange_rate, 0)), 0), 5) AS bet_bonus, 
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), plays.amount_bonus_win_locked*sign_mult*-1/plays.exchange_rate, 0)), 0), 5) AS bet_bonus_win_locked,
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), plays.jackpot_contribution/plays.exchange_rate, 0)), 0), 5) AS jackpot_contribution,
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), plays.amount_total/plays.exchange_rate, 0)), 0), 5) AS win_total, 
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), plays.amount_real/plays.exchange_rate, 0)), 0), 5) AS win_real,
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), plays.amount_bonus/plays.exchange_rate, 0)), 0), 5) AS win_bonus, 
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), plays.amount_bonus_win_locked/plays.exchange_rate, 0)), 0), 5) AS win_bonus_win_locked,
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (14), plays.amount_real/plays.exchange_rate, 0)), 0), 5) AS jackpot_win,
      SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1, 1, 0)) AS num_rounds,
	  ROUND(IFNULL(SUM(loyalty_points), 0), 5) AS loyalty_points,
      @currencyID, @queryDateIntervalID, @dateFrom, @dateTo, MAX(IF(plays.payment_transaction_type_id = 12, 1,0)) AS has_bet,
	  IFNULL(sessions_main.site_id, 1), IFNULL(plays.license_type_id,1), ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (231), plays.amount_real/plays.exchange_rate, 0)), 0), 5) AS cash_in_real,
	  ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (231), plays.amount_bonus/plays.exchange_rate, 0)), 0), 5) AS cash_in_bonus, 
	  ROUND(IFNULL(SUM(IF(stats.gross_revenue IS NOT NULL, stats.gross_revenue, 0)), 0), 5) + ROUND(IFNULL(SUM(IF(Pools.operator_commission IS NOT NULL, Pools.operator_commission, 0)), 0), 5) AS operator_commission,
	  ROUND(IFNULL(SUM(IF(Pools.platform_commission IS NOT NULL, Pools.platform_commission, 0)), 0), 5) AS platform_commission  
    FROM gaming_game_plays plays FORCE INDEX (timestamp) 
    JOIN gaming_payment_transaction_type AS tran_type ON plays.timestamp BETWEEN @dateFrom AND @dateTo 
		AND plays.payment_transaction_type_id=tran_type.payment_transaction_type_id
    JOIN gaming_clients ON plays.client_id=gaming_clients.client_id
	LEFT JOIN sessions_main ON plays.session_id = sessions_main.session_id
	LEFT JOIN gaming_game_manufacturers_player_stats stats ON stats.client_stat_id = plays.client_stat_id
	LEFT JOIN ((SELECT game_play_id, ROUND(IFNULL(SUM(IF(pb.operator_commision IS NOT NULL, pb.operator_commision, 0)), 0), 5) AS operator_commission, 
			   ROUND(IFNULL(SUM(IF(pb.platform_commision IS NOT NULL, pb.platform_commision, 0)), 0), 5) AS platform_commission
				FROM gaming_game_plays_pb pb
				WHERE timestamp BETWEEN @dateFrom AND @dateTo
				GROUP BY pb.game_play_id)) Pools ON Pools.game_play_id = plays.game_play_id
    GROUP BY plays.client_stat_id, plays.license_type_id, IFNULL(sessions_main.site_id, 1);

-- By  player game, Licence, Platform Type
	-- businessobject : AggregationTnxPlayerLicenseSite
	DELETE FROM gaming_game_transactions_aggregation_player_game_licence_plat WHERE query_date_interval_id = @queryDateIntervalID;
	INSERT INTO gaming_game_transactions_aggregation_player_game_licence_plat (
	  client_stat_id, platform_type_id, licence_type_id, game_manufacturer_id, game_id, operator_game_id, 
      bet_total, bet_real, bet_bonus, bet_bonus_win_locked, jackpot_contribution, 
      win_total, win_real, win_bonus, win_bonus_win_locked, jackpot_win, num_rounds, loyalty_points,
      currency_id, query_date_interval_id, date_from, date_to, has_bet, cash_in_real, cash_in_bonus, operator_commission, platform_commission,
	  bet_cash, win_cash, num_rounds_cash)
	SELECT  plays.client_stat_id,IFNULL(plays.platform_type_id,IFNULL((SELECT MAX(gaming_game_plays_platform.platform_type_id) FROM gaming_game_plays as gaming_game_plays_platform 
	WHERE gaming_game_plays_platform.client_id = plays.client_id AND gaming_game_plays_platform.sb_bet_id = plays.sb_bet_id AND gaming_game_plays_platform.is_cancelled = 0),1)), IFNULL(plays.license_type_id,1), plays.game_manufacturer_id, IFNULL(gaming_games.game_id, cgames.game_id), IFNULL(gaming_operator_games.operator_game_id, op_games.operator_game_id),
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), plays.amount_total*sign_mult*-1/plays.exchange_rate, 0)), 0), 5) AS bet_total, 
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), plays.amount_real*sign_mult*-1/plays.exchange_rate, 0)), 0), 5) AS bet_real,
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), plays.amount_bonus*sign_mult*-1/plays.exchange_rate, 0)), 0), 5) AS bet_bonus, 
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), plays.amount_bonus_win_locked*sign_mult*-1/plays.exchange_rate, 0)), 0), 5) AS bet_bonus_win_locked,
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), plays.jackpot_contribution/plays.exchange_rate, 0)), 0), 5) AS jackpot_contribution,
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), plays.amount_total/plays.exchange_rate, 0)), 0), 5) AS win_total, 
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), plays.amount_real/plays.exchange_rate, 0)), 0), 5) AS win_real,
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), plays.amount_bonus/plays.exchange_rate, 0)), 0), 5) AS win_bonus, 
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), plays.amount_bonus_win_locked/plays.exchange_rate, 0)), 0), 5) AS win_bonus_win_locked,
      ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (14), plays.amount_real/plays.exchange_rate, 0)), 0), 5) AS jackpot_win,
      SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1, 1, 0)) AS num_rounds,
	  ROUND(IFNULL(SUM(loyalty_points), 0), 5) AS loyalty_points,
      @currencyID, @queryDateIntervalID, @dateFrom, @dateTo, MAX(IF(plays.payment_transaction_type_id = 12, 1,0)) AS has_bet,
	  ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (231), plays.amount_real/plays.exchange_rate, 0)), 0), 5) AS cash_in_real,
	  ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (231), plays.amount_bonus/plays.exchange_rate, 0)), 0), 5) AS cash_in_bonus, 
	  ROUND(IFNULL(SUM(IF(stats.gross_revenue IS NOT NULL, stats.gross_revenue, 0)), 0), 5) + ROUND(IFNULL(SUM(IF(Pools.operator_commission IS NOT NULL, Pools.operator_commission, 0)), 0), 5) AS operator_commission,
	  ROUND(IFNULL(SUM(IF(Pools.platform_commission IS NOT NULL, Pools.platform_commission, 0)), 0), 5) AS platform_commission ,
	  ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), plays.amount_cash*sign_mult*-1/plays.exchange_rate, 0)), 0), 5) AS bet_cash,
	  ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), plays.amount_cash/plays.exchange_rate, 0)), 0), 5) AS win_cash,
	  SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1 AND plays.amount_cash > 0, 1, 0)) AS num_rounds_cash
    FROM gaming_game_plays plays FORCE INDEX (timestamp) 
    LEFT JOIN gaming_games ON plays.game_id = gaming_games.game_id
	LEFT JOIN gaming_lottery_coupon_games cgames ON plays.sb_bet_id = cgames.lottery_coupon_id
	LEFT JOIN gaming_operator_games ON gaming_operator_games.game_id = gaming_games.game_id
	JOIN gaming_operator_games op_games ON op_games.game_id = cgames.game_id
    JOIN gaming_payment_transaction_type AS tran_type ON plays.timestamp BETWEEN @dateFrom AND @dateTo 
		AND plays.payment_transaction_type_id=tran_type.payment_transaction_type_id
    JOIN gaming_clients ON plays.client_id=gaming_clients.client_id
	LEFT JOIN gaming_game_manufacturers_player_stats stats ON stats.client_stat_id = plays.client_stat_id
	LEFT JOIN ((SELECT game_play_id, ROUND(IFNULL(SUM(IF(pb.operator_commision IS NOT NULL, pb.operator_commision, 0)), 0), 5) AS operator_commission, 
			   ROUND(IFNULL(SUM(IF(pb.platform_commision IS NOT NULL, pb.platform_commision, 0)), 0), 5) AS platform_commission
				FROM gaming_game_plays_pb pb
				WHERE timestamp BETWEEN @dateFrom AND @dateTo
				GROUP BY pb.game_play_id)) Pools ON Pools.game_play_id = plays.game_play_id
	WHERE (plays.game_id IS NOT NULL OR plays.sb_bet_id IS NOT NULL) -- This ensures that no rows without a game id will be selected.
    GROUP BY  plays.client_stat_id, plays.game_id, IFNULL(plays.platform_type_id,1), IFNULL(plays.license_type_id,1);
	-- LICENSING AGGREGATIONS
	-- By transaction type, currency, test player
	-- businessobject : AggregationTxnTransactionTypeCurrency
    DELETE FROM gaming_transactions_aggregation_transaction_type WHERE query_date_interval_id = @queryDateIntervalID;
	INSERT INTO gaming_transactions_aggregation_transaction_type 
		(payment_transaction_type_id,currency_id,amount_total,amount_real,amount_bonus,amount_bonus_win_locked,amount_free_round,amount_free_round_win,
		loyalty_points,loyalty_points_bonus,query_date_interval_id,date_from,date_to,num_transactions,exchange_rate, test_players)
	SELECT gaming_transactions.payment_transaction_type_id, gaming_client_stats.currency_id, sum(gaming_transactions.amount_total), sum(gaming_transactions.amount_real), 
		sum(gaming_transactions.amount_bonus), 
		sum(gaming_transactions.amount_bonus_win_locked), 
		sum(gaming_transactions.amount_free_round), 
		sum(gaming_transactions.amount_free_round_win), 
		sum(gaming_transactions.loyalty_points), 
		sum(IFNULL(gaming_transactions.loyalty_points_bonus,0)),@queryDateIntervalID, @dateFrom, @dateTo, count(*),  1 AS exchange_rate,
		gaming_clients.is_test_player
	from gaming_transactions 
	join gaming_client_stats on gaming_transactions.client_stat_id=gaming_client_stats.client_stat_id 
	JOIN gaming_clients ON  gaming_clients.client_id=gaming_client_stats.client_id
		where gaming_transactions.timestamp between @dateFrom and @dateTo 
		group by gaming_transactions.payment_transaction_type_id, gaming_client_stats.currency_id, gaming_clients.is_test_player;

	-- by transaction type, payment gateway, payment method, currency, test player
	-- businessobject : AggregationTxnGatewayPaymentTypeCurrency
	-- testcase : AggregationTxnGatewayPaymentTypeCurrencyTest
    DELETE FROM gaming_transactions_aggregation_payment_type where query_date_interval_id=@queryDateIntervalID;
    INSERT INTO gaming_transactions_aggregation_payment_type (payment_transaction_type_id,payment_gateway_id,payment_method_id,currency_id,
		amount_total,amount_real,amount_bonus,amount_bonus_win_locked,amount_free_round,amount_free_round_win,loyalty_points,loyalty_points_bonus,
		query_date_interval_id,date_from,date_to,num_transactions,exchange_rate, test_players) 
	SELECT gaming_transactions.payment_transaction_type_id, IFNULL(gaming_balance_history.payment_gateway_id, IFNULL(gaming_balance_accounts.payment_gateway_id,0)), 
		ifnull(gaming_balance_history.payment_method_id, gaming_balance_accounts.payment_method_id), gaming_client_stats.currency_id, 
		sum(gaming_transactions.amount_total), sum(gaming_transactions.amount_real), sum(gaming_transactions.amount_bonus), sum(gaming_transactions.amount_bonus_win_locked), 
	sum(gaming_transactions.amount_free_round), sum(gaming_transactions.amount_free_round_win), sum(gaming_transactions.loyalty_points), sum(IFNULL(gaming_transactions.loyalty_points_bonus,0)), 
		@queryDateIntervalID, @dateFrom, @dateTo, count(gaming_transactions.payment_transaction_type_id), 1 AS exchange_rate, 
		gaming_clients.is_test_player
	FROM gaming_transactions 
	JOIN gaming_payment_transaction_type AS transaction_type ON transaction_type.name IN ('Deposit' , 'DepositCancelled', 'Withdrawal' , 'WithdrawalRequest', 'WithdrawalCancelled', 'Cashback' , 'CashbackCancelled') 
		AND gaming_transactions.payment_transaction_type_id=transaction_type.payment_transaction_type_id 
	JOIN gaming_balance_history ON gaming_transactions.balance_history_id=gaming_balance_history.balance_history_id 
	JOIN gaming_client_stats on gaming_transactions.client_stat_id=gaming_client_stats.client_stat_id 
	JOIN gaming_clients ON  gaming_clients.client_id=gaming_client_stats.client_id
	LEFT JOIN gaming_balance_accounts on gaming_balance_accounts.balance_account_id=gaming_balance_history.balance_account_id 
	WHERE gaming_transactions.timestamp BETWEEN @dateFrom AND @dateTo 
	GROUP BY gaming_transactions.payment_transaction_type_id, IFNULL(gaming_balance_history.payment_gateway_id, IFNULL(gaming_balance_accounts.payment_gateway_id,0)),
			gaming_balance_history.payment_method_id, gaming_client_stats.currency_id, gaming_clients.is_test_player;

	-- by game manufacturer, operator game id, currency, test player
	-- businessobject : AggregationTnxGameGameCurrency
	-- testcase : AggregationTnxGameGameCurrencyTest
	DELETE FROM gaming_transactions_aggregation_game where query_date_interval_id=@queryDateIntervalID;
		
	-- Lottery Aggregations	
	-- by game manufacturer, operator game id, currency, test player
	-- businessobject : AggregationTnxGameGameCurrency
	-- testcase : AggregationTnxGameGameCurrencyTest
	INSERT INTO gaming_transactions_aggregation_game (game_manufacturer_id, game_id,  currency_id, query_date_interval_id, bet_total, bet_real, bet_bonus,
	bet_bonus_win_locked, jackpot_contribution, 
	jackpot_contribution_adjustment, win_total, win_real, win_bonus, win_bonus_win_locked, bet_free_round, 
	win_free_round, num_rounds, date_from, date_to,  test_players)
	SELECT 
		game_manufacturer_id, game_id, currency_id, @queryDateIntervalID, 
		bet_total, bet_real, bet_bonus, bet_bonus_win_locked,
		jackpot_contribution, jackpot_contribution_adjustment,
		win_total, win_real, win_bonus, win_bonus_win_locked,
		amount_free_round, amount_free_round_win, num_rounds,
		@dateFrom, @dateTo, lotto.is_test_player
	FROM
		(
		SELECT MAX(IFNULL(plays.game_manufacturer_id,0)) as game_manufacturer_id, MAX(IFNULL(games.game_id,0)) as game_id,  gaming_client_stats.currency_id, 
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_total*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_total*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_total, 
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_real*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_real*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_real,
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_bonus*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_bonus*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_bonus, 
			ROUND(IFNULL(SUM(
				IF(tran_type.payment_transaction_type_id IN (12), entries.amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0) -
				IF(tran_type.payment_transaction_type_id IN (20), entries.amount_bonus_win_locked*sign_mult*-1/exchange_rate, 0)
			), 0), 5) AS bet_bonus_win_locked,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), jackpot_contribution, 0)), 0), 5) AS jackpot_contribution,
			0 as jackpot_contribution_adjustment,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_total, 0)), 0), 5) AS win_total, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_real, 0)), 0), 5) AS win_real,
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_bonus, 0)), 0), 5) AS win_bonus, 
			ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), entries.amount_bonus_win_locked, 0)), 0), 5) AS win_bonus_win_locked,
			IFNULL(ggpcfr.amount_free_round, 0) as amount_free_round,
			IFNULL(ggpcfr.amount_free_round_win, 0) as amount_free_round_win,
			SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1, 1, 0)) AS num_rounds,
			gaming_clients.is_test_player, tran_type.payment_transaction_type_id, round_transaction_no, plays.license_type_id, gaming_operator_games.operator_game_id
		FROM gaming_game_plays plays FORCE INDEX (timestamp)
		STRAIGHT_JOIN gaming_game_plays_lottery_entries entries ON 
			plays.timestamp BETWEEN @dateFrom AND @dateTo AND plays.license_type_id IN (6, 7) AND
			plays.game_play_id = entries.game_play_id
		STRAIGHT_JOIN gaming_payment_transaction_type AS tran_type ON tran_type.name IN ('Bet','BetCancelled','Win','PJWin', 'LoyaltyPoints') AND 
			plays.payment_transaction_type_id=tran_type.payment_transaction_type_id
		STRAIGHT_JOIN gaming_client_stats on plays.client_stat_id=gaming_client_stats.client_stat_id 
		STRAIGHT_JOIN gaming_clients ON plays.client_id=gaming_clients.client_id
		STRAIGHT_JOIN gaming_lottery_draws draws ON draws.lottery_draw_id=entries.lottery_draw_id
		STRAIGHT_JOIN gaming_games games ON games.game_id=draws.game_id
		STRAIGHT_JOIN gaming_operator_games ON gaming_operator_games.game_id=games.game_id AND gaming_operator_games.operator_id=@operatorID 
		LEFT JOIN gaming_game_plays_cw_free_rounds AS ggpcfr ON plays.game_play_id=ggpcfr.game_play_id
		GROUP BY plays.game_manufacturer_id, gaming_operator_games.operator_game_id, gaming_client_stats.currency_id, gaming_clients.is_test_player
		) AS lotto
	WHERE lotto.license_type_id IN (6, 7)
	GROUP BY lotto.game_manufacturer_id, lotto.operator_game_id, lotto.currency_id, lotto.is_test_player;

	-- Other Games Aggregations	
	-- by game manufacturer, operator game id, currency, test player
	-- businessobject : AggregationTnxGameGameCurrency
	-- testcase : AggregationTnxGameGameCurrencyTest
	INSERT INTO gaming_transactions_aggregation_game (game_manufacturer_id, game_id,  currency_id, query_date_interval_id, bet_total, bet_real, bet_bonus,
		bet_bonus_win_locked, jackpot_contribution, 
		jackpot_contribution_adjustment, win_total, win_real, win_bonus, win_bonus_win_locked, bet_free_round, 
		win_free_round, num_rounds, date_from, date_to,  test_players)
	SELECT game_manufacturer_id, game_id,  gaming_client_stats.currency_id, @queryDateIntervalID, 
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_total, 0)), 0), 5) AS bet_total, 
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_real, 0)), 0), 5) AS bet_real,
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_bonus, 0)), 0), 5) AS bet_bonus, 
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12,20), amount_bonus_win_locked, 0)), 0), 5) AS bet_bonus_win_locked,
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (12), jackpot_contribution, 0)), 0), 5) AS jackpot_contribution,
		0 as jackpot_contribution_adjustment,
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_total, 0)), 0), 5) AS win_total, 
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_real, 0)), 0), 5) AS win_real,
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_bonus, 0)), 0), 5) AS win_bonus, 
		ROUND(IFNULL(SUM(IF(tran_type.payment_transaction_type_id IN (13,14), amount_bonus_win_locked, 0)), 0), 5) AS win_bonus_win_locked,
		IFNULL(ggpcfr.amount_free_round, 0) as amount_free_round,
		IFNULL(ggpcfr.amount_free_round_win, 0) as amount_free_round_win,
		SUM(IF(tran_type.payment_transaction_type_id IN (12) AND round_transaction_no=1, 1, 0)) AS num_rounds,
		@dateFrom, @dateTo,
		gaming_clients.is_test_player
	FROM gaming_game_plays FORCE INDEX (timestamp) 
	STRAIGHT_JOIN gaming_payment_transaction_type AS tran_type ON gaming_game_plays.timestamp BETWEEN @dateFrom AND @dateTo AND 
		gaming_game_plays.game_id IS NOT NULL AND gaming_game_plays.license_type_id NOT IN (6, 7) AND
		tran_type.name IN ('Bet','BetCancelled','Win','PJWin') AND 
		gaming_game_plays.payment_transaction_type_id=tran_type.payment_transaction_type_id 
	STRAIGHT_JOIN gaming_client_stats on gaming_game_plays.client_stat_id=gaming_client_stats.client_stat_id 
	STRAIGHT_JOIN gaming_clients ON gaming_game_plays.client_id=gaming_clients.client_id
	LEFT JOIN gaming_game_plays_cw_free_rounds AS ggpcfr ON gaming_game_plays.game_play_id=ggpcfr.game_play_id
	GROUP BY game_manufacturer_id, gaming_game_plays.operator_game_id, gaming_client_stats.currency_id, gaming_clients.is_test_player;
	
    COMMIT; -- just in case
    
END$$

DELIMITER ;

