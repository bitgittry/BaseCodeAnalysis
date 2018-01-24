DROP procedure IF EXISTS `AggregationUpdatePlayerDailyBalanceForIntervalUsingTimestamp`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `AggregationUpdatePlayerDailyBalanceForIntervalUsingTimestamp`(queryDateIntervalID BIGINT)
root:BEGIN    

COMMIT;

  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; 
  START TRANSACTION;  

  SET @systemEndDate='3000-01-01';
  SET @queryDateIntervalID=queryDateIntervalID; 

-- GET system end date in system number	
SET @systemEndDateDays=TO_DAYS(@systemEndDate);

-- FILL date variables from Intervals table for current Interval 
SELECT 
    current_interval.query_date_interval_id,
    current_interval.date_from,
    current_interval.date_to,
    current_interval.query_date_interval_type_id
INTO @currentQueryDateIntervalID , @currentIntervalStart , @currentIntervalEnd , @currentIntervalType FROM
    gaming_query_date_intervals current_interval
WHERE
    current_interval.query_date_interval_id = @queryDateIntervalID;   

-- FILL date variables from Intervals table for Next interval
SELECT 
    MIN(query_date_interval_id), MIN(date_from)
INTO @nextQueryDateIntervalID , @nextIntervalStart FROM
    gaming_query_date_intervals
WHERE
    query_date_interval_type_id = @currentIntervalType
        AND date_from > @currentIntervalEnd;

  -- GET system start date in system number
  SET @currentIntervalDays=TO_DAYS(@currentIntervalStart);

  -- Insert 'NEW' players that signed up within this period
  INSERT INTO gaming_client_daily_balances 
			(query_date_interval_id, client_stat_id, client_id, date_from_int, date_to_int, real_balance, bonus_balance, bonus_win_locked_balance, pending_withdrawals, pending_bets_real, pending_bets_bonus,
			 exchange_rate,currency_id,loyalty_points_balance, ring_fenced_sb_balance, ring_fenced_casino_balance, ring_fenced_poker_balance, ring_fenced_pb_balance)
  SELECT 	@queryDateIntervalID, gaming_client_stats.client_stat_id, gaming_clients.client_id, @currentIntervalDays, @systemEndDateDays,0,0,0,0,0,0,1,0,0,0,0,0,0
  FROM 		gaming_clients  
		JOIN gaming_client_stats 
			ON gaming_clients.sign_up_date BETWEEN @currentIntervalStart AND @currentIntervalEnd 
			AND gaming_clients.client_id=gaming_client_stats.client_id 
			AND gaming_client_stats.is_active = 1  
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

-- UPDATE the System End date of previous (yesterday) period, with this period's start system date
UPDATE gaming_client_daily_balances AS gcdb
        JOIN
    (SELECT 
        client_stat_id
    FROM
        gaming_game_plays
    WHERE
        `timestamp` BETWEEN @currentIntervalStart AND @currentIntervalEnd
    GROUP BY client_stat_id) AS XX ON (XX.client_stat_id = gcdb.client_stat_id) 
SET 
    gcdb.date_to_int = @currentIntervalDays
WHERE
    gcdb.date_to_int = @systemEndDateDays
        AND gcdb.date_from_int != @currentIntervalDays;

-- Remove Existing
DELETE FROM gaming_client_daily_balances 
WHERE
    query_date_interval_id = @nextQueryDateIntervalID;

-- INSERT active players (from game_plays). use the next interval ID as the current interval ID.
  INSERT INTO gaming_client_daily_balances 
	(`query_date_interval_id`, `client_stat_id`, `client_id`, `date_from_int`, `date_to_int`, `real_balance`,`bonus_balance`, `bonus_win_locked_balance`, 
	 `pending_withdrawals`, `pending_bets_real`, `pending_bets_bonus`,`exchange_rate`,`currency_id`,`loyalty_points_balance`, `ring_fenced_sb_balance`, 
	 `ring_fenced_casino_balance`, `ring_fenced_poker_balance`, `ring_fenced_pb_balance`)
    SELECT 		@nextQueryDateIntervalID, balance_end.client_stat_id, balance_end.client_id, @currentIntervalDays, @systemEndDateDays, 
			IF(real_balance IS NULL, 0, real_balance) as `real_balance`, 
			IF (bonus_balance IS NULL, 0, bonus_balance) as `bonus_balance`, 
			IF (bonus_win_locked_balance IS NULL, 0, bonus_win_locked_balance) as `bonus_win_locked_balance`, 
			IFNULL(txn_pending_after.txn_withdrawal_pending_after,0), 
			IF (pending_bet_real IS NULL, 0, pending_bet_real) as `pending_bet_real`, 
			IF (pending_bet_bonus IS NULL, 0, pending_bet_bonus) as `pending_bet_bonus`,			
			exchange_rate, IFNULL(currency_id,0), IFNULL(loyalty_points_after,0), 
			IFNULL(ringFenced.ring_fenced_sb_after,0), IFNULL(ringFenced.ring_fenced_casino_after,0), IFNULL(ringFenced.ring_fenced_poker_after,0), IFNULL(ringFenced.ring_fenced_pb_after,0)
  FROM 	
	(
		SELECT * FROM (
			SELECT 		
			@rank := IF(client_stat_id = @prev_client_stat_id, (@rank + 1), 0) AS rank,
			@prev_client_stat_id := client_stat_id AS prev_client_stat_id,
			mainPlay.game_play_id, mainPlay.`timestamp`, mainPlay.client_stat_id, mainPlay.client_id, mainPlay.balance_real_after as `real_balance`, 
			mainPlay.balance_bonus_after as `bonus_balance`, mainPlay.balance_bonus_win_locked_after as `bonus_win_locked_balance`, 
			mainPlay.pending_bet_real, mainPlay.pending_bet_bonus, mainPlay.exchange_rate, mainPlay.currency_id, loyalty_points_after					
			FROM 		gaming_game_plays mainPlay,(SELECT @rank := 0) _x	
			WHERE 		mainPlay.`timestamp` BETWEEN @currentIntervalStart AND @currentIntervalEnd	              
			ORDER BY client_stat_id, `timestamp` desc, game_play_id desc
		) AS x WHERE x.rank = 0
	) AS balance_end
	LEFT JOIN gaming_game_play_ring_fenced ringFenced 
		ON ringFenced.game_play_id = balance_end.game_play_id
	LEFT JOIN
	( 
		SELECT 		gt_main.withdrawal_pending_after AS txn_withdrawal_pending_after, txn_client_stat_id as client_stat_id
		FROM   		gaming_transactions gt_main
		JOIN 
					(
						SELECT	 	MAX(gt_sub.transaction_id) AS txn_latest_ID, gt_sub.client_stat_id AS txn_client_stat_id
						FROM     	gaming_transactions gt_sub 
						WHERE    	gt_sub.`timestamp` <= @currentIntervalEnd
						GROUP BY 	gt_sub.client_stat_id 
					) txn 
					ON gt_main.client_stat_id = txn.txn_client_stat_id AND gt_main.transaction_id = txn.txn_latest_ID				
		WHERE    	gt_main.`timestamp` <= @currentIntervalEnd 	
	) AS txn_pending_after
		ON balance_end.client_stat_id = txn_pending_after.client_stat_id 
  ON DUPLICATE KEY UPDATE 
  `real_balance`= values(`real_balance`),
  `bonus_balance`=values(`bonus_balance`), 
  `bonus_win_locked_balance`=values(`bonus_win_locked_balance`),  
  `pending_withdrawals`=values(`pending_withdrawals`), 
  `pending_bets_real`=values(`pending_bets_real`), 
  `pending_bets_bonus`=values(`pending_bets_real`),  
  `exchange_rate`=values(`exchange_rate`),
  `currency_id`=values(`currency_id`),
  `loyalty_points_balance`=values(`loyalty_points_balance`);
  
  COMMIT;

END root$$

DELIMITER ;

