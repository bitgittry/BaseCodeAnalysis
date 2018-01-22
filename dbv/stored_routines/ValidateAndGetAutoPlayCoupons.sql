DROP procedure IF EXISTS `ValidateAndGetAutoPlayCoupons`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `ValidateAndGetAutoPlayCoupons`()
BEGIN

	DECLARE retryAttempts, intervalBetweenAttempts INT;
    
    SELECT value_int INTO retryAttempts FROM gaming_settings WHERE name = 'AUTO_PLAY_SUBSCRITPION_NUMBER_RETRIES_BEFORE_FAILURE';
    SELECT value_int INTO intervalBetweenAttempts FROM gaming_settings WHERE name = 'AUTO_PLAY_SUBSCRITPION_NUMBER_MINUTES_BETWEEN_RETRIES';

	UPDATE gaming_lottery_dbg_tickets
	JOIN (
		SELECT gaming_lottery_dbg_tickets.lottery_dbg_ticket_id ,current_draw.draw_number - MIN(gaming_lottery_draws.draw_number) AS advance_draws
		FROM  gaming_lottery_dbg_tickets
		JOIN gaming_lottery_auto_play_coupons ON gaming_lottery_dbg_tickets.lottery_coupon_id = gaming_lottery_auto_play_coupons.lottery_coupon_id
		JOIN gaming_lottery_coupon_games AS primary_game ON primary_game.lottery_coupon_id = gaming_lottery_auto_play_coupons.lottery_coupon_id AND primary_game.order_num = 1
		JOIN gaming_lottery_draws AS current_draw ON primary_game.game_id = current_draw.game_id AND current_draw.status = 2 /* current active draw*/
		JOIN gaming_lottery_draws AS primary_game_draw ON primary_game_draw.game_id = primary_game.game_id AND primary_game_draw.draw_number = gaming_lottery_auto_play_coupons.draw_number
		JOIN gaming_lottery_draws ON gaming_lottery_dbg_tickets.game_id = gaming_lottery_draws.game_id AND gaming_lottery_draws.draw_date >= primary_game_draw.draw_date
	) AS ticketsToUpdate ON gaming_lottery_dbg_tickets.lottery_dbg_ticket_id = ticketsToUpdate.lottery_dbg_ticket_id
	SET gaming_lottery_dbg_tickets.advance_draws = ticketsToUpdate.advance_draws;

	UPDATE gaming_lottery_auto_play_coupons
	JOIN gaming_lottery_dbg_tickets ON  gaming_lottery_dbg_tickets.lottery_coupon_id = gaming_lottery_auto_play_coupons.lottery_coupon_id
	JOIN gaming_lottery_coupon_games AS primary_game ON primary_game.lottery_coupon_id = gaming_lottery_auto_play_coupons.lottery_coupon_id AND primary_game.order_num = 1
	JOIN gaming_lottery_draws ON primary_game.game_id = gaming_lottery_draws.game_id AND gaming_lottery_auto_play_coupons.draw_number = gaming_lottery_draws.draw_number
	JOIN gaming_lottery_subscription_game_rules ON gaming_lottery_subscription_game_rules.game_id = primary_game.game_id
	SET lottery_auto_play_status_id =  7, remarks = 'Bet attempt is less than minutes before draw'
	WHERE TIMESTAMPDIFF(MINUTE,NOW(),gaming_lottery_draws.draw_date) < gaming_lottery_subscription_game_rules.accept_bet_minutes_before_draw;

	UPDATE gaming_lottery_auto_play_coupons
	JOIN gaming_lottery_dbg_tickets ON  gaming_lottery_dbg_tickets.lottery_coupon_id = gaming_lottery_auto_play_coupons.lottery_coupon_id
	JOIN gaming_lottery_coupon_games AS primary_game ON primary_game.lottery_coupon_id = gaming_lottery_auto_play_coupons.lottery_coupon_id AND primary_game.order_num = 1
	JOIN gaming_lottery_draws ON primary_game.game_id = gaming_lottery_draws.game_id AND gaming_lottery_auto_play_coupons.draw_number = gaming_lottery_draws.draw_number
	LEFT JOIN gaming_lottery_draw_prizes ON gaming_lottery_draw_prizes.lottery_draw_id = gaming_lottery_draw_prizes.lottery_draw_id AND category_type = 1
	JOIN gaming_lottery_subscription_game_rules ON gaming_lottery_subscription_game_rules.game_id = primary_game.game_id AND prize_condition_enabled = 1
	JOIN gaming_lottery_coupons ON gaming_lottery_auto_play_coupons.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id
	JOIN gaming_lottery_subscriptions ON gaming_lottery_subscriptions.lottery_subscription_id = gaming_lottery_coupons.lottery_subscription_id
	SET gaming_lottery_auto_play_coupons.lottery_auto_play_status_id =  7, remarks = 'Amount Under Jackpot value'
	WHERE IFNULL(gaming_lottery_draw_prizes.jackpot,999999999999) < IFNULL(gaming_lottery_subscriptions.min_top_prize_value,0);

	SELECT gaming_lottery_auto_play_coupons.lottery_coupon_id, last_attempt, num_failed, gaming_game_manufacturers.name
	FROM gaming_lottery_auto_play_coupons
	JOIN gaming_lottery_coupons ON gaming_lottery_auto_play_coupons.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id
	JOIN gaming_game_manufacturers ON gaming_lottery_coupons.game_manufacturer_id = gaming_game_manufacturers.game_manufacturer_id
	WHERE lottery_auto_play_status_id = 1 OR (lottery_auto_play_status_id = 3 AND num_failed <= retryAttempts AND NOW() > DATE_ADD(last_attempt , INTERVAL intervalBetweenAttempts MINUTE));

	UPDATE gaming_lottery_auto_play_coupons
	SET lottery_auto_play_status_id  = 8
	WHERE lottery_auto_play_status_id = 1 OR (lottery_auto_play_status_id = 3 AND num_failed <= retryAttempts AND NOW() > DATE_ADD(last_attempt , INTERVAL intervalBetweenAttempts MINUTE));
    
END$$

DELIMITER ;

