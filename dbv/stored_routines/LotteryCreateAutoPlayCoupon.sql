DROP procedure IF EXISTS `LotteryCreateAutoPlayCoupon`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LotteryCreateAutoPlayCoupon`(couponID BIGINT, nextDrawNumber BIGINT)
BEGIN

	DECLARE notificationEnabled TINYINT(1) DEFAULT 0;

	SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';

	INSERT INTO gaming_lottery_auto_play_coupons (lottery_coupon_id, draw_number, lottery_auto_play_status_id)
	SELECT couponID, nextDrawNumber, 1;

	IF (notificationEnabled) THEN 
		INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
		SELECT 531, couponID, client_id, 0
        FROM gaming_lottery_coupons
        JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_lottery_coupons.client_stat_id
        WHERE lottery_coupon_id = couponID;
    END IF;	

END$$

DELIMITER ;

