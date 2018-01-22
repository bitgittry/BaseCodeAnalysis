DROP procedure IF EXISTS `LotterySubscriptionDelete`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LotterySubscriptionDelete`(lotterySubscriptionID BIGINT, isDeleted TINYINT(0))
BEGIN
	DECLARE clientID BIGINT;

	UPDATE gaming_lottery_subscriptions SET
	is_active = 0,
	is_hidden = isDeleted
	WHERE lottery_subscription_id = lotterySubscriptionID;

	SELECT client_id INTO clientID FROM gaming_lottery_subscriptions 
	WHERE lottery_subscription_id = lotterySubscriptionID;
	
	CALL NotificationEventCreate(530, lotterySubscriptionID, clientID, 0);	
	
END$$

DELIMITER ;
