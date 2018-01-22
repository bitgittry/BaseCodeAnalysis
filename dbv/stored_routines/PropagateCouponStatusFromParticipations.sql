DROP function IF EXISTS `PropagateCouponStatusFromParticipations`;

DELIMITER $$
CREATE DEFINER=`root`@`127.0.0.1` FUNCTION `PropagateCouponStatusFromParticipations`(couponID BIGINT, currentCouponStatus INT(4), manualUnblock TINYINT) RETURNS int(4)
			   
BEGIN 

DECLARE allParticipations, openParticipations, winParticipations, pendingWinParticipations, provisionalWinParticipations, paidParticipations, lostParticipations, playingParticipations, newCouponStatus INT(4);

	SELECT 
	   COUNT(*) as totalPart,
	   SUM(IF(part.lottery_participation_status_id = 2101, 1, 0)) as openPart, 
	   SUM(IF(part.lottery_participation_status_id = 2104, 1, 0)) as winningRemain, 
	   SUM(IF(part.lottery_participation_status_id = 2107, 1, 0)) as pendingWinPart,
	   
	   SUM(IF(part.lottery_participation_status_id = 2110, 1, 0)) as provisionalWinPart,		   		   
	   SUM(IF(part.lottery_participation_status_id = 2105, 1, 0)) as paidPart,
	   SUM(IF(part.lottery_participation_status_id = 2106, 1, 0)) as lostPart,
	   SUM(IF(part.lottery_participation_status_id = 2100, 1, 0)) as playingPart
	INTO 
		allParticipations, 
		openParticipations, 
		winParticipations, 		
		pendingWinParticipations, 
		
		provisionalWinParticipations, 
		paidParticipations, 		
		lostParticipations, 
		playingParticipations
		
	FROM gaming_lottery_dbg_tickets tick FORCE INDEX (lottery_coupon_id)
	STRAIGHT_JOIN gaming_lottery_participations part ON 
	  tick.lottery_coupon_id=couponID AND
	  part.lottery_dbg_ticket_id=tick.lottery_dbg_ticket_id;

	IF(allParticipations = playingParticipations) THEN
		SET newCouponStatus = 2101; -- PLAYING
	ELSEIF(allParticipations = lostParticipations) THEN
		SET newCouponStatus = 2108; -- NOT_WINNING
	ELSEIF(openParticipations = allParticipations) THEN
		SET newCouponStatus = 2102; -- PLAYED
	ELSE
		IF(openParticipations > 0) THEN
			IF(winParticipations > 0 OR paidParticipations>0 OR pendingWinParticipations > 0 OR provisionalWinParticipations > 0) then
				SET newCouponStatus = 2105; -- WINNING
			ELSE
				SET newCouponStatus = 2102; -- PLAYED
			END IF;
		ELSE
			IF(winParticipations > 0 OR pendingWinParticipations > 0 OR provisionalWinParticipations > 0) THEN	
				SET newCouponStatus = 2105; -- WINNING
			ELSEIF(paidParticipations > 0) THEN
				SET newCouponStatus = 2107; -- PAID 
			END IF;
		END IF;
	END IF;

	-- If temp blocked, don't change the status unless all the participations are in the final states (nothing to block anymore)
	IF(currentCouponStatus != 2110 OR 
		(currentCouponStatus = 2110 AND ( manualUnblock = 1 OR allParticipations = pendingWinParticipations + paidParticipations + lostParticipations))) THEN
		IF(manualUnblock = 2 AND currentCouponStatus = 2109) THEN -- it comes from undo draw
			RETURN currentCouponStatus;
        ELSE
			RETURN newCouponStatus;
        END IF;
	ELSE
		RETURN currentCouponStatus;
	END IF;
END$$

DELIMITER ;

