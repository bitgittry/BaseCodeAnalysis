DROP function IF EXISTS `LotteryPlayerGetFavouriteCouponOrNull`;

DELIMITER $$
CREATE FUNCTION `LotteryPlayerGetFavouriteCouponOrNull` (lottery_coupon_id BIGINT, game_manufacturer_id BIGINT)
  RETURNS BIGINT
BEGIN
	DECLARE favouriteCouponID BIGINT DEFAULT NULL;	
	
	SELECT
		gcflc.favourite_coupon_id INTO favouriteCouponID
	FROM
		gaming_client_favourite_lottery_coupons	gcflc
	LEFT JOIN gaming_lottery_coupons glc ON glc.lottery_coupon_id = gcflc.lottery_coupon_id
	WHERE
		glc.lottery_coupon_id = lottery_coupon_id AND
		glc.game_manufacturer_id = game_manufacturer_id;
		
			
		
	RETURN favouriteCouponID;

END$$

DELIMITER ;

