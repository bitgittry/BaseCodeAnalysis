DROP procedure IF EXISTS `LotteryScheduleNextBatch`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LotteryScheduleNextBatch`(lastBatchDate DATETIME, lotterySubscriptionID BIGINT)
BEGIN

	UPDATE gaming_lottery_subscriptions
	JOIN (
		SELECT 
			gaming_lottery_subscriptions.lottery_subscription_id,MIN(next_draws.draw_number)  AS new_draw_number,
			IF(bet_on_draw.draw_date IS NULL,
				IFNULL(
					ADDTIME(
						CAST(
							DATE(DATE_ADD(
								MIN(next_draws.draw_date),
								INTERVAL -gaming_lottery_subscription_game_rules.play_num_hours_before_draw HOUR))
						AS DATETIME),
						IFNULL(gaming_lottery_subscription_game_rules.play_time,0)
					),
				'0001-01-01 00:00:00'
				),
                bet_on_draw.draw_date
			) AS new_subscription_date
		FROM gaming_lottery_subscriptions
        JOIN gaming_lottery_auto_play_statuses ON gaming_lottery_subscriptions.lottery_auto_play_status_id = gaming_lottery_auto_play_statuses.lottery_auto_play_status_id
			AND (gaming_lottery_auto_play_statuses.name = 'Pending' OR lotterySubscriptionID != 0)
        JOIN gaming_lottery_subscription_game_rules ON gaming_lottery_subscriptions.primary_game_id = gaming_lottery_subscription_game_rules.game_id
		JOIN gaming_lottery_draws AS current_draw FORCE INDEX (game_draw_date) ON gaming_lottery_subscriptions.primary_game_id=current_draw.game_id AND current_draw.draw_number = gaming_lottery_subscriptions.next_draw_number 
		JOIN gaming_query_date_intervals AS current_interval  ON current_interval.date_from = DATE(current_draw.draw_date) AND current_interval.query_date_interval_type_id = 3
		JOIN gaming_query_date_intervals AS next_interval ON next_interval.date_interval_num = current_interval.date_interval_num + play_interval_every_num
				AND next_interval.query_date_interval_type_id = 3 
		JOIN gaming_lottery_draws AS next_draws ON next_draws.game_id = gaming_lottery_subscriptions.primary_game_id AND next_draws.draw_date >= ADDTIME(next_interval.date_from, gaming_lottery_subscription_game_rules.play_time) AND next_draws.status <= 2 
			AND next_draws.draw_date>GREATEST(NOW(),gaming_lottery_subscriptions.play_from_date)
		LEFT JOIN gaming_lottery_draws AS bet_on_draw ON gaming_lottery_subscription_game_rules.advanced_draws IS NOT NULL 
			AND next_draws.draw_number - gaming_lottery_subscription_game_rules.advanced_draws = bet_on_draw.draw_number 
            AND next_draws.game_id = bet_on_draw.game_id
		WHERE gaming_lottery_subscriptions.is_active = 1 AND play_interval_type = 1 /*Daily*/ AND gaming_lottery_subscriptions.next_subscription_date < lastBatchDate 
			AND (lotterySubscriptionID = 0 OR gaming_lottery_subscriptions.lottery_subscription_id = lotterySubscriptionID)
		GROUP BY gaming_lottery_subscriptions.lottery_subscription_id
	) AS next_subscriptions ON gaming_lottery_subscriptions.lottery_subscription_id = next_subscriptions.lottery_subscription_id
	SET gaming_lottery_subscriptions.next_subscription_date = new_subscription_date, gaming_lottery_subscriptions.next_draw_number = new_draw_number;
    
    
    UPDATE gaming_lottery_subscriptions
	JOIN (
		SELECT 
			gaming_lottery_subscriptions.lottery_subscription_id,MIN(next_draws.draw_number)  AS new_draw_number,
			IF(bet_on_draw.draw_date IS NULL,
				IFNULL(
					ADDTIME(
						CAST(
							DATE(DATE_ADD(
								MIN(next_draws.draw_date),
								INTERVAL -gaming_lottery_subscription_game_rules.play_num_hours_before_draw HOUR))
						AS DATETIME),
						IFNULL(gaming_lottery_subscription_game_rules.play_time,0)
					),
				'0001-01-01 00:00:00'
				),
                bet_on_draw.draw_date
			) AS new_subscription_date
		FROM gaming_lottery_subscriptions
		JOIN gaming_lottery_auto_play_statuses ON gaming_lottery_subscriptions.lottery_auto_play_status_id = gaming_lottery_auto_play_statuses.lottery_auto_play_status_id
			AND (gaming_lottery_auto_play_statuses.name = 'Pending' OR lotterySubscriptionID != 0)
        JOIN gaming_lottery_subscription_game_rules ON gaming_lottery_subscriptions.primary_game_id = gaming_lottery_subscription_game_rules.game_id
		JOIN gaming_lottery_draws AS next_draws ON next_draws.game_id = gaming_lottery_subscriptions.primary_game_id AND next_draws.draw_number > gaming_lottery_subscriptions.next_draw_number AND next_draws.status <= 2 AND next_draws.draw_date>GREATEST(NOW(),gaming_lottery_subscriptions.play_from_date)
		LEFT JOIN gaming_lottery_draws AS bet_on_draw ON gaming_lottery_subscription_game_rules.advanced_draws IS NOT NULL 
			AND next_draws.draw_number - gaming_lottery_subscription_game_rules.advanced_draws = bet_on_draw.draw_number 
            AND next_draws.game_id = bet_on_draw.game_id
		WHERE gaming_lottery_subscriptions.is_active = 1 AND play_interval_type = 5 /*All Draws*/ AND gaming_lottery_subscriptions.next_subscription_date < lastBatchDate
			AND (lotterySubscriptionID = 0 OR gaming_lottery_subscriptions.lottery_subscription_id = lotterySubscriptionID)
		GROUP BY gaming_lottery_subscriptions.lottery_subscription_id
	) AS next_subscriptions ON gaming_lottery_subscriptions.lottery_subscription_id = next_subscriptions.lottery_subscription_id
	SET gaming_lottery_subscriptions.next_subscription_date = new_subscription_date, gaming_lottery_subscriptions.next_draw_number = new_draw_number;
    

    UPDATE gaming_lottery_subscriptions
	JOIN (
		SELECT 
			gaming_lottery_subscriptions.lottery_subscription_id,MIN(next_draws.draw_number)  AS new_draw_number,
			IF(bet_on_draw.draw_date IS NULL,
				IFNULL(
					ADDTIME(
						CAST(
							DATE(DATE_ADD(
								MIN(next_draws.draw_date),
								INTERVAL -gaming_lottery_subscription_game_rules.play_num_hours_before_draw HOUR))
						AS DATETIME),
						IFNULL(gaming_lottery_subscription_game_rules.play_time,0)
					),
                '0001-01-01 00:00:00'
				),
                bet_on_draw.draw_date
			) AS new_subscription_date
		FROM gaming_lottery_subscriptions
		JOIN gaming_lottery_auto_play_statuses ON gaming_lottery_subscriptions.lottery_auto_play_status_id = gaming_lottery_auto_play_statuses.lottery_auto_play_status_id
			AND (gaming_lottery_auto_play_statuses.name = 'Pending' OR lotterySubscriptionID != 0)
		JOIN gaming_lottery_subscription_game_rules ON gaming_lottery_subscriptions.primary_game_id = gaming_lottery_subscription_game_rules.game_id
		JOIN gaming_lottery_draws AS current_draw ON gaming_lottery_subscriptions.primary_game_id=current_draw.game_id AND current_draw.draw_number = gaming_lottery_subscriptions.next_draw_number 
		JOIN gaming_query_date_intervals AS current_interval  ON current_interval.date_from = DATE_ADD(DATE(current_draw.draw_date), INTERVAL(-((DAYOFWEEK(current_draw.draw_date)-2)+7)%7) DAY) AND current_interval.query_date_interval_type_id = 4
		LEFT JOIN gaming_lottery_subscription_days AS subscription_days ON gaming_lottery_subscriptions.lottery_subscription_id = subscription_days.lottery_subscription_id AND subscription_days.day_no > DAYOFWEEK(current_draw.draw_date) AND NOW() < DATE_ADD(current_interval.date_to, INTERVAL -1 DAY)
			-- cant do a 1 to 1 join as today might not be an exact date that matches with the days chosen and still would not know which one is next maybe add order
		JOIN gaming_query_date_intervals AS next_interval ON (subscription_days.lottery_subscription_id IS NULL AND next_interval.query_date_interval_type_id = 4 AND DAYOFWEEK(current_interval.date_to)!= 1 AND next_interval.date_interval_num = current_interval.date_interval_num + 2) OR
			(subscription_days.lottery_subscription_id IS NULL AND next_interval.query_date_interval_type_id = 4 AND DAYOFWEEK(current_interval.date_to)= 1 AND next_interval.date_interval_num = current_interval.date_interval_num + 1) OR
			(subscription_days.lottery_subscription_id IS NOT NULL AND next_interval.query_date_interval_id = current_interval.query_date_interval_id)
		JOIN gaming_lottery_subscription_days AS next_subscription_days ON gaming_lottery_subscriptions.lottery_subscription_id = next_subscription_days.lottery_subscription_id 
			-- cant do a 1 to 1 join as dont know which is first day
		JOIN gaming_lottery_draws AS next_draws ON next_draws.game_id = gaming_lottery_subscriptions.primary_game_id AND
			next_draws.draw_date >= 
				GREATEST(
					ADDTIME(DATE_ADD(next_interval.date_from,INTERVAL 
						IF(subscription_days.day_no IS NOT NULL,
							(subscription_days.day_no-2+7)%7,
							(next_subscription_days.day_no-2+7)%7
						) DAY), gaming_lottery_subscription_game_rules.play_time),
					NOW(),gaming_lottery_subscriptions.play_from_date)
				AND next_draws.status <= 2 
				-- Brian safe guard (cannot bet in the past)
				AND next_draws.draw_date > NOW()
		LEFT JOIN gaming_lottery_draws AS bet_on_draw ON gaming_lottery_subscription_game_rules.advanced_draws IS NOT NULL 
			AND next_draws.draw_number - gaming_lottery_subscription_game_rules.advanced_draws = bet_on_draw.draw_number 
            AND next_draws.game_id = bet_on_draw.game_id
		WHERE gaming_lottery_subscriptions.is_active = 1 AND play_interval_type = 2  AND gaming_lottery_subscriptions.next_subscription_date < NOW()
			AND (lotterySubscriptionID = 0 OR gaming_lottery_subscriptions.lottery_subscription_id = lotterySubscriptionID)
		GROUP BY gaming_lottery_subscriptions.lottery_subscription_id
	) AS next_subscriptions ON gaming_lottery_subscriptions.lottery_subscription_id = next_subscriptions.lottery_subscription_id
	SET gaming_lottery_subscriptions.next_subscription_date = new_subscription_date, gaming_lottery_subscriptions.next_draw_number = new_draw_number;
    
    IF (lotterySubscriptionID != 0) THEN
		UPDATE gaming_lottery_subscriptions
		SET lottery_auto_play_status_id = 5
		WHERE gaming_lottery_subscriptions.lottery_subscription_id = lotterySubscriptionID;
    END IF;
    
END$$

DELIMITER ;

