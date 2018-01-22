DROP procedure IF EXISTS `LotterySubscriptionCreate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LotterySubscriptionCreate`(
subscriptionTitle VARCHAR(45),
gameManufacturerID BIGINT,
clientID BIGINT,
primaryGameID BIGINT,
createdDate DATETIME,
isHidden TINYINT(1),
minTopPrizeValue DECIMAL(18,5),
playIntervalType INT,
playWeeklyNumDays INT,
playIntervalEveryNum INT,
playFromDate DATETIME,
playUntilType INT,
playUntilDate DATETIME,
playForNumDraws INT,
playNumConsecutiveDraws INT,
lotteryCouponID BIGINT,
numCouponBought INT,
nextSubscriptionDate DATETIME,
nextDrawNumber BIGINT,
lotterySubscriptionParentID BIGINT)
BEGIN
	DECLARE lotterySubscriptionID BIGINT;

	INSERT INTO gaming_lottery_subscriptions ( 
	subscription_title,
	game_manufacturer_id,
	client_id,
	primary_game_id,
	created_date,
	is_hidden,
	min_top_prize_value,
	play_interval_type,
	play_weekly_num_days,
	play_interval_every_num,
	play_from_date,
	play_until_type,
	play_until_date,
	play_for_num_draws,
	play_num_consecutive_draws,
	lottery_coupon_id,
	num_coupon_bought,
	next_subscription_date,
	next_draw_number,
	lottery_subscription_parent_id
	) VALUES (
	subscriptionTitle,
	gameManufacturerID,
	clientID,
	primaryGameID,
	createdDate,
	isHidden,
	minTopPrizeValue,
	playIntervalType,
	playWeeklyNumDays,
	playIntervalEveryNum,
	playFromDate,
	playUntilType,
	playUntilDate,
	playForNumDraws,
	playNumConsecutiveDraws,
	lotteryCouponID,
	numCouponBought,
	nextSubscriptionDate,
	nextDrawNumber,
	lotterySubscriptionParentID
	);
	
	SELECT LAST_INSERT_ID() INTO lotterySubscriptionID;
	
	CALL NotificationEventCreate(529, lotterySubscriptionID, clientID, 0);	

	SELECT lotterySubscriptionID;

END$$

DELIMITER ;
