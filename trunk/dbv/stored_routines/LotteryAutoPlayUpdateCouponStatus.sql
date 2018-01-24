DROP procedure IF EXISTS `LotteryAutoPlayUpdateCouponStatus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LotteryAutoPlayUpdateCouponStatus`(lotteryCouponID BIGINT, varFailed INT, varRemarks VARCHAR(256), varStatus INT, notificationTypeID INT)
BEGIN
    -- getting correct client_id
	DECLARE clientID BIGINT;
    
    SELECT gaming_client_stats.client_id INTO clientID 
    FROM gaming_lottery_coupons 
	JOIN gaming_client_stats ON gaming_lottery_coupons.client_stat_id=gaming_client_stats.client_stat_id
	WHERE gaming_lottery_coupons.lottery_coupon_id = lotteryCouponID;

	UPDATE gaming_lottery_auto_play_coupons
	SET lottery_auto_play_status_id = varStatus,
		remarks = varRemarks,
		num_failed = num_failed + varFailed,
		last_attempt = NOW()
	WHERE lottery_coupon_id = lotteryCouponID;

	IF (notificationTypeID != 0) THEN 
		CALL NotificationEventCreate(notificationTypeID,lotteryCouponID, clientID, 0);
    END IF;
									
END$$

DELIMITER ;

