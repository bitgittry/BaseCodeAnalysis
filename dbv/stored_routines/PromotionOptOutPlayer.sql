DROP procedure IF EXISTS `PromotionOptOutPlayer`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionOptOutPlayer`(promotionID BIGINT, clientStatID BIGINT, sessionID BIGINT, OUT statusCode INT)
root:BEGIN
  
  DECLARE promotionIDCheck, promotionPlayerStatusID, childPromotionID BIGINT DEFAULT -1;
  DECLARE dailyFlag, optInFlag, isParent, requirementAchieved TINYINT(1) DEFAULT 0;
  DECLARE achievementEndDate DATETIME;
  DECLARE numPlayersOptedIn INT DEFAULT 0;
  
  SET statusCode = 10;
  
  SELECT promotion_id, achievement_daily_flag, need_to_opt_in_flag, achievement_end_date, is_parent 
  INTO promotionIDCheck, dailyFlag, optInFlag, achievementEndDate, isParent
  FROM gaming_promotions
  WHERE promotion_id=promotionID;
  IF (promotionIDCheck=-1) THEN 
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (isParent=1) THEN
    SELECT promotion_id INTO childPromotionID
    FROM gaming_promotions
    WHERE parent_promotion_id=promotionID AND is_current=1;
  END IF;
  IF (achievementEndDate < NOW() OR (isParent=1 AND childPromotionID=-1)) THEN 
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  SELECT promotion_player_status_id, requirement_achieved INTO promotionPlayerStatusID, requirementAchieved 
  FROM gaming_promotions_player_statuses 
  WHERE promotion_id=promotionID AND client_stat_id=clientStatID AND is_active=1 AND is_current=1; 
  
  IF (promotionPlayerStatusID=-1) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF (requirementAchieved) THEN
    SET statusCode=4; 
    LEAVE root;
  END IF;

    
  INSERT gaming_promotions_players_opted_in (promotion_id, client_stat_id, opted_in, is_automatic, status_date, session_id)
  VALUES (promotionID, clientStatID, 0, 0, NOW(), sessionID)
  ON DUPLICATE KEY UPDATE opted_in=0, status_date=NOW();
  
  UPDATE gaming_promotions_player_statuses SET is_active=0, is_current=0, opted_out_date=NOW() WHERE promotion_player_status_id=promotionPlayerStatusID;   
  
  SELECT COUNT(1) INTO numPlayersOptedIn FROM gaming_promotions_player_statuses WHERE ((isParent=0 AND promotion_id=promotionID) OR (isParent=1 AND child_promotion_id=childPromotionID)) AND is_active=1;
  UPDATE gaming_promotions SET num_players_opted_in=numPlayersOptedIn, can_opt_in=IF(num_players_opted_in<max_players,1,0) WHERE promotion_id=promotionID;
  SET statusCode=0;
END root$$

DELIMITER ;

