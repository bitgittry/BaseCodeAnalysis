DROP procedure IF EXISTS `AggregationUpdatePlayerDailyBalanceForInterval`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `AggregationUpdatePlayerDailyBalanceForInterval`(queryDateIntervalID BIGINT)
root:BEGIN

  -- optimized
  
  COMMIT; -- just in case
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    SET @systemEndDate='3000-01-01';
    SET @queryDateIntervalID=queryDateIntervalID;
    SET @systemEndDateDays=TO_DAYS(@systemEndDate);
	SET @dateTimeNow=NOW();
	
	SELECT 
		current_interval.query_date_interval_id,
		current_interval.date_from,
		current_interval.date_to,
		current_interval.query_date_interval_type_id
	INTO @currentQueryDateIntervalID , @currentIntervalStart , @currentIntervalEnd , @currentIntervalType 
	FROM gaming_query_date_intervals current_interval
	WHERE current_interval.query_date_interval_id = @queryDateIntervalID;

	SELECT MIN(query_date_interval_id), MIN(date_from)
	INTO @nextQueryDateIntervalID , @nextIntervalStart 
	FROM gaming_query_date_intervals
	WHERE query_date_interval_type_id = @currentIntervalType AND date_from > @currentIntervalEnd;

	SET @currentIntervalDays=TO_DAYS(@currentIntervalStart);
	SET @currentIntervalEnd=LEAST(@currentIntervalEnd, @dateTimeNow);

	SELECT game_play_id INTO @startGamePlayID FROM gaming_game_plays WHERE `timestamp` >= @currentIntervalStart ORDER BY timestamp LIMIT 1;
    SELECT game_play_id INTO @endGamePlayID  FROM gaming_game_plays WHERE `timestamp` <= @currentIntervalEnd ORDER BY timestamp DESC LIMIT 1;	

    SELECT transaction_id INTO @startTxnID FROM gaming_transactions WHERE `timestamp` >= @currentIntervalStart ORDER BY timestamp LIMIT 1;
    SELECT transaction_id INTO @endTxnID FROM gaming_transactions WHERE `timestamp` <= @currentIntervalEnd ORDER BY timestamp DESC LIMIT 1; 

	-- insert newly registered players
	  DELETE gaming_client_daily_balances
      FROM gaming_client_daily_balances
	  JOIN gaming_clients FORCE INDEX (sign_up_date) ON gaming_clients.sign_up_date BETWEEN @currentIntervalStart AND @currentIntervalEnd
		AND gaming_client_daily_balances.client_id=gaming_clients.client_id;

	  INSERT INTO gaming_client_daily_balances (
		 query_date_interval_id, client_stat_id, client_id, date_from_int, date_to_int, real_balance, bonus_balance, bonus_win_locked_balance, pending_withdrawals, pending_bets_real,
	     pending_bets_bonus, exchange_rate,currency_id,loyalty_points_balance, ring_fenced_sb_balance, ring_fenced_casino_balance, ring_fenced_poker_balance, ring_fenced_pb_balance, vip_level_id)
	  SELECT @queryDateIntervalID, gaming_client_stats.client_stat_id, gaming_clients.client_id, @currentIntervalDays, @systemEndDateDays,0,0,0,0,0,0,1,0,0,0,0,0,0, gaming_clients.vip_level_id
	  FROM  gaming_clients FORCE INDEX (sign_up_date)
	  JOIN gaming_client_stats ON gaming_clients.sign_up_date BETWEEN @currentIntervalStart AND @currentIntervalEnd
	     AND (gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active = 1)
	  ON DUPLICATE KEY UPDATE
		 real_balance=0,
		 bonus_balance=0,
		 bonus_win_locked_balance=0,
		 pending_withdrawals=0,
		 pending_bets_real=0,
		 pending_bets_bonus=0,
		 exchange_rate=1,
		 currency_id=0,
		 loyalty_points_balance=0,
		 ring_fenced_sb_balance=0,
		 ring_fenced_casino_balance=0,
		 ring_fenced_poker_balance=0,
		 ring_fenced_pb_balance=0;

	-- if the player had any activity than end the balance of the current day 
	UPDATE gaming_client_daily_balances AS gcdb
	JOIN
	(
		SELECT client_stat_id FROM gaming_game_plays WHERE game_play_id BETWEEN @startGamePlayID AND @endGamePlayID GROUP BY client_stat_id
	) AS XX ON (XX.client_stat_id = gcdb.client_stat_id) 
	SET gcdb.date_to_int = @currentIntervalDays
	WHERE gcdb.date_to_int = @systemEndDateDays AND gcdb.date_from_int != @currentIntervalDays;

	-- delete needed if the aggregation for the current date is re-run

	DELETE FROM gaming_client_daily_balances WHERE query_date_interval_id = @nextQueryDateIntervalID;

	-- insert new date with starting balance
	INSERT INTO gaming_client_daily_balances
	 (`query_date_interval_id`, `client_stat_id`, `client_id`, `date_from_int`, `date_to_int`, `real_balance`,`bonus_balance`, `bonus_win_locked_balance`,
	  `pending_withdrawals`, `pending_bets_real`, `pending_bets_bonus`,`exchange_rate`,`currency_id`,`loyalty_points_balance`, `ring_fenced_sb_balance`,
	  `ring_fenced_casino_balance`, `ring_fenced_poker_balance`, `ring_fenced_pb_balance`, vip_level_id)
	SELECT   @nextQueryDateIntervalID, balance_end.client_stat_id, balance_end.client_id, @currentIntervalDays, @systemEndDateDays,
	   IF(real_balance IS NULL, 0, real_balance) as `real_balance`,
	   IF (bonus_balance IS NULL, 0, bonus_balance) as `bonus_balance`,
	   IF (bonus_win_locked_balance IS NULL, 0, bonus_win_locked_balance) as `bonus_win_locked_balance`,
	   IFNULL(txn_pending_after.txn_withdrawal_pending_after,0),
	   IF (pending_bet_real IS NULL, 0, pending_bet_real) as `pending_bet_real`,
	   IF (pending_bet_bonus IS NULL, 0, pending_bet_bonus) as `pending_bet_bonus`,
	   exchange_rate, IFNULL(currency_id,0), IFNULL(loyalty_points_after,0),
	   IFNULL(ringFenced.ring_fenced_sb_after,0), IFNULL(ringFenced.ring_fenced_casino_after,0), IFNULL(ringFenced.ring_fenced_poker_after,0),
	   IFNULL(ringFenced.ring_fenced_pb_after,0),
	   gaming_clients.vip_level_id
	 FROM
	 (
		  SELECT mainPlay.game_play_id, mainPlay.`timestamp`, mainPlay.client_stat_id, mainPlay.client_id, mainPlay.balance_real_after as `real_balance`,
			 mainPlay.balance_bonus_after as `bonus_balance`, mainPlay.balance_bonus_win_locked_after as `bonus_win_locked_balance`,
			 mainPlay.pending_bet_real, mainPlay.pending_bet_bonus, mainPlay.exchange_rate, mainPlay.currency_id, loyalty_points_after
		  FROM  gaming_game_plays mainPlay
		  JOIN
		  (
			  SELECT MAX(subPlay.game_play_id) AS game_play_id
			  FROM  gaming_game_plays subPlay
			  WHERE  subPlay.game_play_id BETWEEN @startGamePlayID AND @endGamePlayID
			  GROUP BY subPlay.client_stat_id
		  ) AS subPlay ON mainPlay.game_play_id = subPlay.game_play_id 
	 ) AS balance_end
     JOIN gaming_clients ON balance_end.client_id=gaming_clients.client_id
	 LEFT JOIN gaming_game_play_ring_fenced ringFenced ON ringFenced.game_play_id = balance_end.game_play_id
	 LEFT JOIN
	 (
	    SELECT  gt_main.withdrawal_pending_after AS txn_withdrawal_pending_after, gt_main.client_stat_id 
	    FROM     gaming_transactions gt_main
	    JOIN
		 (
		    SELECT   MAX(gt_sub.transaction_id) AS transaction_id
		    FROM      gaming_transactions gt_sub
		    WHERE     gt_sub.transaction_id BETWEEN @startTxnID AND @endTxnID
		    GROUP BY  client_stat_id
		 ) txn
		 ON gt_main.transaction_id = txn.transaction_id
	 ) AS txn_pending_after ON balance_end.client_stat_id = txn_pending_after.client_stat_id 
	 ON DUPLICATE KEY UPDATE
	  `real_balance`= values(`real_balance`),
	  `bonus_balance`=values(`bonus_balance`),
	  `bonus_win_locked_balance`=values(`bonus_win_locked_balance`),
	  `pending_withdrawals`=values(`pending_withdrawals`),
	  `pending_bets_real`=values(`pending_bets_real`),
	  `pending_bets_bonus`=values(`pending_bets_bonus`),
	  `exchange_rate`=values(`exchange_rate`),
	  `currency_id`=values(`currency_id`),
	  `loyalty_points_balance`=values(`loyalty_points_balance`);

    -- if there are no redemption schemes nothing is updated
	UPDATE gaming_client_daily_balances FORCE INDEX (PRIMARY)
	JOIN
	(
		SELECT gaming_client_daily_balances.query_date_interval_id, gaming_client_daily_balances.client_stat_id,
				MAX(IF(gaming_loyalty_redemption.loyalty_redemption_prize_type_id = 1, gaming_loyalty_redemption_currency_amounts.amount, 0) / gaming_loyalty_redemption.minimum_loyalty_points) AS top_redemption_real_exchage_rate, 
				MAX(IF(gaming_loyalty_redemption.loyalty_redemption_prize_type_id = 2, gaming_loyalty_redemption_currency_amounts.amount, 0) / gaming_loyalty_redemption.minimum_loyalty_points) AS top_redemption_bonus_exchage_rate
		FROM gaming_client_daily_balances
		JOIN gaming_loyalty_redemption ON 
			@currentIntervalStart BETWEEN IFNULL(gaming_loyalty_redemption.date_start, '2010-01-01') AND IFNULL(gaming_loyalty_redemption.date_end, '3000-01-01') AND gaming_loyalty_redemption.is_active=1
			AND gaming_loyalty_redemption.loyalty_redemption_prize_type_id IN (1,2) -- CASH, BONUS
			AND gaming_client_daily_balances.loyalty_points_balance >= gaming_loyalty_redemption.minimum_loyalty_points
		JOIN gaming_loyalty_redemption_currency_amounts ON gaming_loyalty_redemption_currency_amounts.loyalty_redemption_id = gaming_loyalty_redemption.loyalty_redemption_id
			AND gaming_client_daily_balances.currency_id = gaming_loyalty_redemption_currency_amounts.currency_id
		LEFT JOIN gaming_player_selections_player_cache ON gaming_loyalty_redemption.player_selection_id=gaming_player_selections_player_cache.player_selection_id AND gaming_player_selections_player_cache.client_stat_id = gaming_client_daily_balances.client_stat_id 
		WHERE gaming_client_daily_balances.query_date_interval_id = @nextQueryDateIntervalID AND (gaming_loyalty_redemption.is_open_to_all OR IFNULL(gaming_player_selections_player_cache.player_in_selection, 0))
		GROUP BY gaming_client_daily_balances.query_date_interval_id, gaming_client_daily_balances.client_stat_id
	) AS A ON A.query_date_interval_id = gaming_client_daily_balances.query_date_interval_id AND A.client_stat_id=gaming_client_daily_balances.client_stat_id
	SET 
		gaming_client_daily_balances.top_redemption_real_exchage_rate = A.top_redemption_real_exchage_rate,
		gaming_client_daily_balances.top_redemption_bonus_exchage_rate = A.top_redemption_bonus_exchage_rate
	WHERE gaming_client_daily_balances.query_date_interval_id = @nextQueryDateIntervalID;

	COMMIT; -- just in case

END root$$

DELIMITER ;

