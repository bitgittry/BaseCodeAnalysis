
DROP procedure IF EXISTS `PromotionOptInPlayer`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionOptInPlayer`(promotionID BIGINT, clientStatID BIGINT, evenIfNotInSelection TINYINT(1), promotionGroupID BIGINT, bonusCode VARCHAR(45), sessionID BIGINT, OUT statusCode INT)
root:BEGIN
  

  DECLARE promotionIDCheck, playerSelectionID, promotionPlayerStatusID, clientStatIDCheck, promotionGroupIDCheck, currencyID BIGINT DEFAULT -1;
  DECLARE promotionActive, dailyFlag, optInFlag, alreadyOptedIn, canOptIn, promotionGroupChecked, alreadyOptedInGroup, isInGroup, isParent, restrictByBonusCode, isRecurrence, canNotOptInPerPlayer, awardThresholdNotExceeded TINYINT(1) DEFAULT 0;
  DECLARE achievementEndDate DATETIME;
  DECLARE numPlayersOptedIn INT DEFAULT 0;
  DECLARE childPromotionID, currentPromotionRecurrenceDateID, previousPromotionPlayerStatusID, previousPromotionRecurrenceDateID BIGINT DEFAULT NULL; 
  DECLARE bonusCodeCheck VARCHAR (45);  

  IF (promotionGroupID IS NOT NULL) THEN
    
    SELECT promotion_group_id INTO promotionGroupIDCheck
    FROM gaming_promotion_groups
    WHERE promotion_group_id=promotionGroupID AND is_active=1;
    IF (promotionGroupIDCheck=-1) THEN 
      SET statusCode=11;
      LEAVE root;
    END IF;
    
    SELECT client_stat_id INTO clientStatIDCheck
    FROM gaming_client_stats
    WHERE client_stat_id=clientStatID AND is_active=1
    FOR UPDATE;
    
    SELECT gaming_promotion_groups_promotions.promotion_id INTO promotionIDCheck
    FROM gaming_promotion_groups 
    JOIN gaming_promotion_groups_promotions ON 
      gaming_promotion_groups.promotion_group_id=promotionGroupID AND gaming_promotion_groups_promotions.promotion_id=promotionID AND
      gaming_promotion_groups.promotion_group_id=gaming_promotion_groups_promotions.promotion_group_id;
      
    IF (promotionIDCheck=-1) THEN
      SET statusCode=12;
      LEAVE root;
    END IF;
     
    SELECT 1 INTO alreadyOptedInGroup
    FROM gaming_promotion_groups 
    JOIN gaming_promotion_groups_promotions ON 
      gaming_promotion_groups.promotion_group_id=promotionGroupID AND 
      gaming_promotion_groups.promotion_group_id=gaming_promotion_groups_promotions.promotion_group_id
    JOIN gaming_promotions_player_statuses AS player_statuses ON 
      player_statuses.client_stat_id=clientStatID AND player_statuses.is_active=1 AND player_statuses.is_current=1 AND
      gaming_promotion_groups_promotions.promotion_id=player_statuses.promotion_id;
    
    IF (alreadyOptedInGroup=1) THEN
      SET statusCode=4;
      LEAVE root;
    END IF;
  
    SET promotionGroupChecked=1;
  ELSE
    SET promotionGroupChecked=0;
  END IF;

  
  IF (promotionID IS NULL AND bonusCode IS NOT NULL) THEN
	SELECT promotion_id INTO promotionID FROM gaming_promotions WHERE bonus_code=bonusCode AND is_active=1 AND is_hidden=0 ORDER BY promotion_id DESC LIMIT 1;		
  END IF;

  SELECT promotion_id, is_active, achievement_daily_flag, player_selection_id, need_to_opt_in_flag, achievement_end_date, can_opt_in, is_in_group, is_parent, restrict_by_bonus_code, bonus_code, recurrence_enabled   
  INTO promotionIDCheck, promotionActive, dailyFlag, playerSelectionID, optInFlag, achievementEndDate, canOptIn, isInGroup, isParent, restrictByBonusCode, bonusCodeCheck, isRecurrence
  FROM gaming_promotions
  WHERE promotion_id=promotionID AND is_child=0 FOR UPDATE;
  
  IF (promotionIDCheck=-1 AND bonusCode IS NULL) THEN 
    SET statusCode=1;
    LEAVE root;
  END IF;

  IF (promotionActive=0) THEN 
    SET statusCode=6;
    LEAVE root;
  END IF;

	-- commented for INBUGCL-188 - "Product: When the operator uses opt-in, there should be no check for the bonus\promotion code. - the player should be added to the selection right away."
  -- IF (restrictByBonusCode=1 AND (bonusCode IS NULL OR bonusCode != bonusCodeCheck)) THEN
	-- SET statusCode = 14;
	-- LEAVE root;
  -- END IF;

	-- break only if bonus code is supplied but does not match the promotion's code
  IF (restrictByBonusCode=1 AND bonusCode IS NOT NULL AND bonusCode != bonusCodeCheck) THEN
	SET statusCode = 14;
	LEAVE root;
  END IF;
  
  IF (isParent=1) THEN
    SELECT promotion_id INTO childPromotionID
    FROM gaming_promotions
    WHERE parent_promotion_id=promotionID AND is_current=1;
  END IF;
  IF (achievementEndDate < NOW() OR (isParent=1 AND childPromotionID=-1)) THEN 
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF (promotionGroupChecked=0 AND isInGroup=1) THEN
    SET statusCode=13;
    LEAVE root;
  END IF;
  
  SELECT client_stat_id, currency_id INTO clientStatIDCheck, currencyID
  FROM gaming_client_stats
  WHERE client_stat_id=clientStatID AND is_active=1;
  
  IF (clientStatIDCheck=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  IF (evenIfNotInSelection = 0) THEN 
    IF (PlayerSelectionIsPlayerInSelection(playerSelectionID, clientStatID)!=1) THEN
      SET statusCode=2;
      LEAVE root;
    END IF;
  END IF;
  
  SET alreadyOptedIn=0;
  SELECT 1, promotion_player_status_id, promotion_recurrence_date_id
  INTO alreadyOptedIn, previousPromotionPlayerStatusID, previousPromotionRecurrenceDateID
  FROM gaming_promotions_player_statuses 
  WHERE promotion_id=promotionID AND client_stat_id=clientStatID AND is_active=1 AND is_current=1;

  IF (isRecurrence) THEN
	SELECT recurrence_dates.promotion_recurrence_date_id, IF(IFNULL(recurrence_dates.awarded_prize_count, 0) < IFNULL(gaming_promotions.award_num_players_per_occurence, 999999999999), 1, 0) 
	INTO currentPromotionRecurrenceDateID, awardThresholdNotExceeded
	FROM gaming_promotions_recurrence_dates AS recurrence_dates FORCE INDEX (promotion_active_current)
	JOIN gaming_promotions ON gaming_promotions.promotion_id = recurrence_dates.promotion_id
	WHERE recurrence_dates.promotion_id=promotionID AND recurrence_dates.is_active=1 AND recurrence_dates.is_current=1;
	
  
    IF (currentPromotionRecurrenceDateID IS NUll)THEN
		SET statusCode = 17;
        LEAVE root;
	END IF;
   

	
	IF (awardThresholdNotExceeded=0) THEN
        SET statusCode=15;
	    LEAVE root;
		END IF;

        
	   SET canNotOptInPerPlayer = 0;
	   SELECT COUNT(*) INTO canNotOptInPerPlayer
	   FROM gaming_promotions_players_opted_in gppo
       JOIN gaming_promotions ON gaming_promotions.promotion_id = gppo.promotion_id
	   WHERE gppo.promotion_id = promotionID AND gppo.client_stat_id = clientStatID AND gppo.awarded_prize_count >= IFNULL(gaming_promotions.award_num_times_per_player, 999999999999);  

      IF (canNotOptInPerPlayer > 0) THEN
        SET statusCode=16;
	    LEAVE root;
		END IF;

    IF (alreadyOptedIn=1) THEN
	  IF (previousPromotionRecurrenceDateID=currentPromotionRecurrenceDateID) THEN
	    SET statusCode=4;
	    LEAVE root;
	  ELSE
		UPDATE gaming_promotions_player_statuses SET is_current=0 WHERE promotion_player_status_id=previousPromotionPlayerStatusID;
	  END IF;
	END IF;
  ELSE
	IF (alreadyOptedIn=1) THEN
	  SET statusCode=4;
	  LEAVE root;
	END IF;
  END IF;
      
  IF (canOptIn=0) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;    
  
  INSERT gaming_promotions_players_opted_in (promotion_id, client_stat_id, opted_in, is_automatic, status_date, session_id)
  VALUES (promotionID, clientStatID, 1, 0, NOW(), sessionID)
  ON DUPLICATE KEY UPDATE opted_in=1, status_date=NOW();		
  
  INSERT INTO gaming_promotions_player_statuses (promotion_id, child_promotion_id, client_stat_id, priority, opted_in_date, achieved_days, currency_id, session_id, promotion_recurrence_date_id, start_date, end_date)
  SELECT gaming_promotions.promotion_id, childPromotionID, clientStatID, gaming_promotions.priority, NOW(), IF(gaming_promotions.achievement_daily_flag,0,NULL), currencyID, sessionID, 
	recurrence_dates.promotion_recurrence_date_id, IFNULL(recurrence_dates.start_date, gaming_promotions.achievement_start_date), IFNULL(recurrence_dates.end_date, gaming_promotions.achievement_end_date)
  FROM gaming_promotions 
  LEFT JOIN gaming_promotions_recurrence_dates AS recurrence_dates ON recurrence_dates.promotion_recurrence_date_id=currentPromotionRecurrenceDateID
  WHERE gaming_promotions.promotion_id=promotionID;
  
  SET promotionPlayerStatusID=LAST_INSERT_ID();  
  
  IF (dailyFlag=1) THEN  
    INSERT INTO gaming_promotions_player_statuses_daily (promotion_player_status_id, promotion_status_day_id, promotion_id)
    SELECT gaming_promotions_player_statuses.promotion_player_status_id, gaming_promotions_status_days.promotion_status_day_id, gaming_promotions_player_statuses.promotion_id
    FROM gaming_promotions_player_statuses
    JOIN gaming_promotions_status_days ON
      gaming_promotions_player_statuses.promotion_player_status_id=promotionPlayerStatusID AND 
      gaming_promotions_player_statuses.promotion_id=gaming_promotions_status_days.promotion_id AND
      (gaming_promotions_player_statuses.promotion_recurrence_date_id IS NULL OR gaming_promotions_player_statuses.promotion_recurrence_date_id=gaming_promotions_status_days.promotion_recurrence_date_id); 
  END IF;
  
  
  SELECT COUNT(1) INTO numPlayersOptedIn FROM gaming_promotions_player_statuses WHERE ((isParent=0 AND promotion_id=promotionID) OR (isParent=1 AND child_promotion_id=childPromotionID)) AND is_active=1;
  UPDATE gaming_promotions SET num_players_opted_in=numPlayersOptedIn, can_opt_in=IF(num_players_opted_in<max_players,1,0) WHERE promotion_id=promotionID;
      
  SELECT promotionPlayerStatusID AS promotion_player_status_id;
  SET statusCode=0;
  

END root$$

DELIMITER ;

