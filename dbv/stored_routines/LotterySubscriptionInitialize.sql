DROP procedure IF EXISTS `LotterySubscriptionInitialize`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LotterySubscriptionInitialize`(lotterySubscriptionID BIGINT)
BEGIN

	UPDATE gaming_lottery_subscriptions
	JOIN (
		SELECT 
			gaming_lottery_subscriptions.lottery_subscription_id,
			MIN(next_draws.draw_number) AS new_draw_number,
			IFNULL(
				IF(bet_on_draw.draw_date IS NULL,
					DATE_ADD(
						MIN(next_draws.draw_date),
						INTERVAL -gaming_lottery_subscription_game_rules.play_num_hours_before_draw HOUR),

				bet_on_draw.draw_date),
                '0001-01-01 00:00:00'
			) AS new_subscription_date
		FROM gaming_lottery_subscriptions
		JOIN gaming_lottery_subscription_game_rules ON gaming_lottery_subscriptions.primary_game_id = gaming_lottery_subscription_game_rules.game_id
		JOIN gaming_lottery_draws AS next_draws ON next_draws.game_id = gaming_lottery_subscriptions.primary_game_id 
			AND next_draws.draw_date >= GREATEST(NOW(),ADDTIME(CAST(DATE(gaming_lottery_subscriptions.play_from_date) AS DATETIME), IFNULL(gaming_lottery_subscription_game_rules.play_time,0))) 
			AND next_draws.status <= 2 
		LEFT JOIN gaming_lottery_draws AS bet_on_draw ON advanced_draws IS NOT NULL 
			AND next_draws.draw_number - advanced_draws = bet_on_draw.draw_number 
			AND next_draws.game_id = bet_on_draw.game_id
		WHERE gaming_lottery_subscriptions.lottery_subscription_id =  lotterySubscriptionID
		GROUP BY gaming_lottery_subscriptions.lottery_subscription_id
	) AS next_subscriptions ON gaming_lottery_subscriptions.lottery_subscription_id = next_subscriptions.lottery_subscription_id
	SET 
	gaming_lottery_subscriptions.next_subscription_date = new_subscription_date,
	gaming_lottery_subscriptions.next_draw_number = new_draw_number;
    
    
    UPDATE gaming_lottery_coupons
    JOIN gaming_lottery_subscriptions ON gaming_lottery_subscriptions.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id
		SET gaming_lottery_coupons.lottery_subscription_id = lotterySubscriptionID
	WHERE gaming_lottery_subscriptions.lottery_subscription_id = lotterySubscriptionID;
	
    
END$$

DELIMITER ;

