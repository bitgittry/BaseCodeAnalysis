-- -------------------------------------
-- PromotionReCreatePlayerStatusesOnPromotionUpdate.sql
-- -------------------------------------
DROP procedure IF EXISTS `PromotionReCreatePlayerStatusesOnPromotionUpdate`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionReCreatePlayerStatusesOnPromotionUpdate`(promotionID BIGINT, OUT statusCode INT)
root:BEGIN                                         
  -- Added Sports Book check for statusCode=5
  -- Added check if promotion is Optinonly then no games should be checked -> SUP-5423
  DECLARE promotionIDCheck, playerSelectionID, promotionTypeID, promotionGetCounterID BIGINT DEFAULT -1;
  DECLARE dailyFlag, optInFlag, statusesAlreadyCreated TINYINT(1) DEFAULT 0;
  DECLARE dayStatusCode, numPlayersOptedIn, maxPlayers, numOptedIn, numToAward, varPriority INT DEFAULT 0;
  DECLARE activationStartDate DATETIME DEFAULT NULL;
  
  SET statusCode = 10;
  SET dayStatusCode = 10;
  
  SELECT promotion_id, achievement_start_date, achievement_daily_flag, player_selection_id, need_to_opt_in_flag, IFNULL(gaming_promotions.max_players, 0), num_players_opted_in, priority
  INTO promotionIDCheck, activationStartDate, dailyFlag, playerSelectionID, optInFlag, maxPlayers, numOptedIn, varPriority
  FROM gaming_promotions
  WHERE promotion_id=promotionID AND gaming_promotions.is_hidden=0
  FOR UPDATE;

  SELECT promotion_achievement_type_id INTO promotionTypeID 
  FROM gaming_promotions
  WHERE promotion_id = promotionID;

  IF (promotionIDCheck=-1) THEN 
    SET statusCode=1;
    LEAVE root;
  END IF;

  IF (activationStartDate<NOW() AND numOptedIn>0) THEN
	SET statusCode=2;
	LEAVE root;
  END IF;
  
  IF(promotionTypeID != 5) THEN
	IF (NOT EXISTS (SELECT * FROM gaming_promotions_games WHERE promotion_id = promotionIDCheck LIMIT 1) AND
		NOT EXISTS (SELECT * FROM gaming_promotions_wgr_sb_weights AS w
					LEFT JOIN gaming_promotions_wgr_sb_eligibility_criterias AS c
						ON c.eligibility_criterias_id = w.eligibility_criterias_id  
					WHERE IF(w.promotion_id > 0, w.promotion_id, c.promotion_id) = promotionIDCheck LIMIT 1)) THEN
		SET statusCode=5;
		LEAVE root;
	END IF;
  END IF;

  IF (dailyFlag=1) THEN  
    SET dayStatusCode=-1;
    SET @deletePrevious=1;
    CALL PromotionMakeDateIntervals(promotionID, @deletePrevious, 1, 'Daily', dayStatusCode);
    
    IF (dayStatusCode<>0) THEN 
      SET statusCode=4;
      LEAVE root;
    END IF;
  END IF;

   DELETE FROM gaming_promotions_player_statuses_daily WHERE promotion_id=promotionID;
   DELETE FROM gaming_promotions_player_statuses WHERE promotion_id=promotionID;
   DELETE FROM gaming_promotions_players_opted_in WHERE promotion_id = promotionID;
   UPDATE gaming_promotions_recurrence_dates SET awarded_prize_count = 0 WHERE promotion_id = promotionID;
 
  IF (optInFlag=0) THEN
    
	IF (maxPlayers!=0) THEN

	  SELECT COUNT(CS.client_stat_id) INTO numToAward    
	  FROM gaming_player_selections_player_cache AS CS
	  WHERE (CS.player_selection_id=playerSelectionID AND CS.player_in_selection=1);

	  IF (numToAward > (maxPlayers - 0)) THEN
		UPDATE gaming_promotions SET is_active=0, is_activated=0 WHERE promotion_id=promotionID;

		SET statusCode=3;
		LEAVE root;
	  END IF;

    END IF;

    INSERT INTO gaming_promotion_get_counter (date_added) VALUES (NOW());
    SET promotionGetCounterID=LAST_INSERT_ID();

	INSERT gaming_promotions_players_opted_in (promotion_id, client_stat_id, opted_in, is_automatic, status_date, session_id, creation_counter_id)
    SELECT promotionID, gaming_client_stats.client_stat_id, 1, 1, NOW(), sessions_main.session_id, promotionGetCounterID 
    FROM sessions_main FORCE INDEX (session_type_status)
    JOIN gaming_player_selections_player_cache AS selected_players ON selected_players.player_selection_id=playerSelectionID AND selected_players.client_stat_id=sessions_main.extra2_id AND selected_players.player_in_selection=1 
    JOIN gaming_client_stats ON selected_players.client_stat_id=gaming_client_stats.client_stat_id
    WHERE (sessions_main.session_type=2 AND sessions_main.status_code=1)
    GROUP BY gaming_client_stats.client_stat_id;

	INSERT INTO gaming_promotions_player_statuses (promotion_id, client_stat_id, priority, opted_in_date, currency_id, promotion_recurrence_date_id, start_date, end_date)
	SELECT promotionID, gaming_client_stats.client_stat_id, varPriority, NOW(), gaming_client_stats.currency_id, recurrence_dates.promotion_recurrence_date_id, recurrence_dates.start_date, recurrence_dates.end_date 
	FROM sessions_main FORCE INDEX (session_type_status)
	JOIN gaming_player_selections_player_cache AS selected_players ON selected_players.player_selection_id=playerSelectionID AND selected_players.client_stat_id=sessions_main.extra2_id AND selected_players.player_in_selection=1 
	JOIN gaming_client_stats ON selected_players.client_stat_id=gaming_client_stats.client_stat_id
	LEFT JOIN gaming_promotions_recurrence_dates AS recurrence_dates ON recurrence_dates.promotion_id= promotionID AND recurrence_dates.is_active=1 AND recurrence_dates.is_current=1
	WHERE (sessions_main.session_type=2 AND sessions_main.status_code=1)
	GROUP BY gaming_client_stats.client_stat_id;
   
      IF (dailyFlag=1) THEN  
        INSERT INTO gaming_promotions_player_statuses_daily (promotion_player_status_id, promotion_status_day_id, promotion_id)
        SELECT gaming_promotions_player_statuses.promotion_player_status_id, gaming_promotions_status_days.promotion_status_day_id, gaming_promotions_player_statuses.promotion_id
        FROM gaming_promotions_player_statuses
        JOIN gaming_promotions_status_days ON
          gaming_promotions_player_statuses.promotion_id=promotionID AND 
          gaming_promotions_player_statuses.promotion_id=gaming_promotions_status_days.promotion_id AND
		 (gaming_promotions_player_statuses.promotion_recurrence_date_id IS NULL OR gaming_promotions_player_statuses.promotion_recurrence_date_id=gaming_promotions_status_days.promotion_recurrence_date_id) ;
      END IF;

  END IF;
  
  SELECT COUNT(1) INTO numPlayersOptedIn FROM gaming_promotions_player_statuses WHERE promotion_id=promotionID AND is_active=1;
  UPDATE gaming_promotions SET num_players_opted_in=numPlayersOptedIn, can_opt_in=IF(num_players_opted_in<max_players,1,0), is_activated=1 WHERE promotion_id=promotionID;

  SET statusCode=0;

END root$$

DELIMITER ;

