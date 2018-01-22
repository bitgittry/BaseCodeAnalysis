DROP procedure IF EXISTS `PromotionChangeActiveFlag`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionChangeActiveFlag`(promotionID BIGINT, isActive TINYINT(1), sessionID BIGINT, OUT statusCode INT)
root:BEGIN
  -- calling optimized PromotionReCreatePlayerStatusesOnPromotionUpdate
  -- Added call to PromotionsSetCurrentOccurrencesJob 
  
  DECLARE promotionIDCheck BIGINT DEFAULT -1;
  DECLARE isActivated TINYINT(1) DEFAULT 0;
  DECLARE achievementEndDate datetime;  

  SELECT promotion_id, is_activated,achievement_end_date INTO promotionIDCheck, isActivated, achievementEndDate
  FROM gaming_promotions
  WHERE promotion_id=promotionID AND gaming_promotions.is_hidden=0;
  
  IF (promotionIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  IF (achievementEndDate<now()) THEN
    SET statusCode=6;
    LEAVE root;
  END IF;

  UPDATE gaming_promotions SET is_active=isActive, is_activated=isActive, session_id=sessionID WHERE promotion_id=promotionID AND is_active!=isActive;
    
  IF (isActive=1 AND isActivated=0) THEN
	UPDATE gaming_promotions_recurrence_dates FORCE INDEX (promotion_id) SET is_current=1 WHERE promotion_id=promotionID AND recurrence_no=1;
	CALL PromotionsSetCurrentOccurrencesJob(promotionID);
    CALL PromotionReCreatePlayerStatusesOnPromotionUpdate(promotionID, statusCode);
  ELSE
    SET statusCode = 0;
  END IF;
  
END root$$

DELIMITER ;

