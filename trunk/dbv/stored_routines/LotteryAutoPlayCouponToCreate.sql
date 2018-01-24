DROP procedure IF EXISTS `LotteryAutoPlayCouponToCreate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LotteryAutoPlayCouponToCreate`(currentDate DATETIME)
BEGIN
	SELECT 
		gaming_lottery_subscriptions.lottery_coupon_id, gaming_lottery_subscriptions.next_draw_number
	FROM gaming_lottery_subscriptions
    JOIN gaming_lottery_auto_play_statuses ON gaming_lottery_subscriptions.lottery_auto_play_status_id = gaming_lottery_auto_play_statuses.lottery_auto_play_status_id
			AND gaming_lottery_auto_play_statuses.name = 'Pending'
	JOIN gaming_lottery_coupons ON gaming_lottery_subscriptions.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id
    JOIN gaming_lottery_dbg_tickets ON gaming_lottery_coupons.lottery_coupon_id = gaming_lottery_dbg_tickets.lottery_coupon_id AND 
		gaming_lottery_dbg_tickets.is_primary_game = 1
	JOIN gaming_lottery_draws ON gaming_lottery_draws.game_id = gaming_lottery_dbg_tickets.game_id AND gaming_lottery_draws.status = 2
    WHERE gaming_lottery_subscriptions.is_active = 1 AND gaming_lottery_subscriptions.next_subscription_date <= currentDate AND
	    gaming_lottery_subscriptions.next_subscription_date != '0001-01-01 00:00:00' AND (
		(play_for_num_draws IS NOT NULL AND num_coupon_bought < play_for_num_draws) OR 
        (play_until_date IS NOT NULL AND play_until_date >= currentDate) OR
        (play_until_date IS NULL AND play_for_num_draws IS NULL));
    
    UPDATE gaming_lottery_subscriptions
    SET num_coupon_bought = num_coupon_bought + 1
    WHERE gaming_lottery_subscriptions.is_active = 1 AND gaming_lottery_subscriptions.next_subscription_date <= currentDate AND 
    gaming_lottery_subscriptions.next_subscription_date != '0001-01-01 00:00:00';
        
	UPDATE gaming_lottery_subscriptions
    SET is_active =0
    WHERE gaming_lottery_subscriptions.is_active = 1 AND gaming_lottery_subscriptions.next_subscription_date <= currentDate 
		 AND  ((play_for_num_draws IS NOT NULL AND num_coupon_bought >= play_for_num_draws) OR  (play_until_date IS NOT NULL AND play_until_date <= currentDate));
    
    
END$$

DELIMITER ;

