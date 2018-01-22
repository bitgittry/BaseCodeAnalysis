DROP procedure IF EXISTS `LotterySubscriptionEnable`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LotterySubscriptionEnable`(lotterySubscriptionID BIGINT)
BEGIN
	DECLARE clientID BIGINT;

	UPDATE gaming_lottery_subscriptions SET
	is_active = 1
	WHERE lottery_subscription_id = lotterySubscriptionID;

	SELECT client_id INTO clientID FROM gaming_lottery_subscriptions 
	WHERE lottery_subscription_id = lotterySubscriptionID;
	
	CALL NotificationEventCreate(529, lotterySubscriptionID, clientID, 0);	
	
END$$

DELIMITER ;
