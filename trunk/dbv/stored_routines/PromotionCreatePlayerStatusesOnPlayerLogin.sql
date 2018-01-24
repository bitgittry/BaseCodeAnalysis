DROP procedure IF EXISTS `PromotionCreatePlayerStatusesOnPlayerLogin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionCreatePlayerStatusesOnPlayerLogin`(clientStatID BIGINT)
root: BEGIN
  -- Optimized, quering on gaming_player_selections_player_cache
  -- Fixed when adding num_players_opted_in  

  DECLARE promotionGetCounterID, clientStatIDCheck, currencyID BIGINT DEFAULT -1;
  DECLARE promotionEnabledFlag TINYINT(1) DEFAULT 0;
  DECLARE dateTimeNow DATETIME DEFAULT NOW();
   
  SELECT value_bool INTO promotionEnabledFlag FROM gaming_settings WHERE name='IS_PROMOTION_ENABLED';
	
  IF (promotionEnabledFlag=0) THEN
    LEAVE root;
  END IF;
  
  SELECT client_stat_id, currency_id INTO clientStatIDCheck, currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
  
  -- UPDATE THE CURRENT OCCURENCE TO FALSE
  UPDATE gaming_promotions_player_statuses AS gpps 
  JOIN gaming_promotions ON gpps.promotion_id=gaming_promotions.promotion_id AND gaming_promotions.recurrence_enabled
  LEFT JOIN gaming_promotions_recurrence_dates AS recurrence_dates FORCE INDEX (promotion_active_current) ON 
	recurrence_dates.promotion_id=gaming_promotions.promotion_id AND recurrence_dates.is_active=1 AND recurrence_dates.is_current=1 
  SET gpps.is_current=0 
  WHERE (gpps.client_stat_id=clientStatID AND gpps.is_current=1 AND gpps.end_date<dateTimeNow) AND
	(recurrence_dates.promotion_recurrence_date_id IS NULL OR gpps.promotion_recurrence_date_id!=recurrence_dates.promotion_recurrence_date_id);

  INSERT INTO gaming_promotion_get_counter (date_added) VALUES (NOW());
  SET promotionGetCounterID=LAST_INSERT_ID();

  INSERT gaming_promotions_players_opted_in (promotion_id, client_stat_id, opted_in, is_automatic, status_date, session_id, creation_counter_id)
  SELECT gaming_promotions.promotion_id, clientStatID, 1, NOT gaming_promotions.need_to_opt_in_flag, NOW(), gaming_promotions.session_id, promotionGetCounterID 
  FROM gaming_promotions
  LEFT JOIN gaming_player_selections_player_cache AS CS ON CS.player_selection_id=gaming_promotions.player_selection_id AND CS.client_stat_id=clientStatID  
  LEFT JOIN gaming_promotions AS child_promotion ON child_promotion.parent_promotion_id=gaming_promotions.promotion_id AND child_promotion.is_current=1
  LEFT JOIN gaming_promotions_players_opted_in AS gpps ON gpps.promotion_id=gaming_promotions.promotion_id AND gpps.client_stat_id=clientStatID 
  LEFT JOIN gaming_promotions_recurrence_dates AS recurrence_dates FORCE INDEX (promotion_active_current) ON 
      recurrence_dates.promotion_id= gaming_promotions.promotion_id AND recurrence_dates.is_active=1 AND recurrence_dates.is_current=1
  WHERE (gaming_promotions.achievement_end_date>=NOW() AND gaming_promotions.is_active=1 AND gaming_promotions.need_to_opt_in_flag=0 AND
		(gaming_promotions.can_opt_in=1 AND gaming_promotions.num_players_opted_in<gaming_promotions.max_players)) 
	AND IFNULL(CS.player_in_selection, PlayerSelectionIsPlayerInSelectionCached(gaming_promotions.player_selection_id, clientStatID))=1    
	AND gpps.client_stat_id IS NULL AND IFNULL(gpps.awarded_prize_count, 0) < IFNULL(gaming_promotions.award_num_times_per_player, 9999999999999)
	AND IFNULL(recurrence_dates.awarded_prize_count, 0) < IFNULL(gaming_promotions.award_num_players_per_occurence, 999999999999);
	

  INSERT INTO gaming_promotions_player_statuses (promotion_id, child_promotion_id, client_stat_id, priority, opted_in_date, currency_id, creation_counter_id, promotion_recurrence_date_id, start_date, end_date)
  SELECT gaming_promotions.promotion_id, child_promotion.promotion_id, clientStatID, gaming_promotions.priority, NOW(), currencyID, promotionGetCounterID,
  recurrence_dates.promotion_recurrence_date_id, IFNULL(recurrence_dates.start_date, gaming_promotions.achievement_start_date), IFNULL(recurrence_dates.end_date, gaming_promotions.achievement_end_date)
  FROM gaming_promotions
  LEFT JOIN gaming_player_selections_player_cache AS CS ON CS.player_selection_id=gaming_promotions.player_selection_id AND CS.client_stat_id=clientStatID  
  LEFT JOIN gaming_promotions AS child_promotion ON child_promotion.parent_promotion_id=gaming_promotions.promotion_id AND child_promotion.is_current=1
  LEFT JOIN gaming_promotions_player_statuses AS gpps ON gpps.promotion_id=gaming_promotions.promotion_id AND gpps.client_stat_id=clientStatID AND gpps.is_current=1
  LEFT JOIN gaming_promotions_recurrence_dates AS recurrence_dates ON recurrence_dates.promotion_id=gaming_promotions.promotion_id 
  AND recurrence_dates.is_active=1 AND recurrence_dates.is_current=1 
  LEFT JOIN gaming_promotions_players_opted_in AS gppo ON gppo.promotion_id = gaming_promotions.promotion_id AND gppo.client_stat_id = clientStatID AND gppo.opted_in = 1
  WHERE (gaming_promotions.achievement_end_date>=NOW() AND gaming_promotions.is_active=1 AND 
	((gaming_promotions.need_to_opt_in_flag=0 AND IFNULL(gppo.creation_counter_id,0)=promotionGetCounterID) 
	  OR (gpps.client_stat_id IS NULL AND gppo.client_stat_id IS NOT NULL AND gppo.opted_in = 1 AND
	(gaming_promotions.auto_opt_in_next = 1 OR (gaming_promotions.auto_opt_in_next = 0 AND gaming_promotions.need_to_opt_in_flag = 0)))) AND 
		(gaming_promotions.can_opt_in=1 AND gaming_promotions.num_players_opted_in<gaming_promotions.max_players)) 
	AND ((IFNULL(CS.player_in_selection, PlayerSelectionIsPlayerInSelectionCached(gaming_promotions.player_selection_id, clientStatID))=1) OR
        gaming_promotions.auto_opt_in_next = 1)
	AND gpps.promotion_player_status_id IS NULL AND IFNULL(gppo.awarded_prize_count, 0) < IFNULL(gaming_promotions.award_num_times_per_player, 999999999999)
    AND IFNULL(recurrence_dates.awarded_prize_count, 0) < IFNULL(gaming_promotions.award_num_players_per_occurence, 999999999999);
   
  INSERT INTO gaming_promotions_player_statuses_daily (promotion_player_status_id, promotion_status_day_id, promotion_id)
  SELECT gaming_promotions_player_statuses.promotion_player_status_id, gaming_promotions_status_days.promotion_status_day_id, gaming_promotions_player_statuses.promotion_id
  FROM gaming_promotions_player_statuses
  JOIN gaming_promotions_status_days ON 
    gaming_promotions_player_statuses.promotion_id=gaming_promotions_status_days.promotion_id AND 
	(gaming_promotions_player_statuses.promotion_recurrence_date_id IS NULL OR gaming_promotions_player_statuses.promotion_recurrence_date_id=gaming_promotions_status_days.promotion_recurrence_date_id) 
  WHERE gaming_promotions_player_statuses.creation_counter_id=promotionGetCounterID AND gaming_promotions_player_statuses.client_stat_id=clientStatID AND gaming_promotions_player_statuses.is_current = 1; 

  COMMIT AND CHAIN;  
    
  UPDATE gaming_promotions
  JOIN gaming_promotions_player_statuses ON gaming_promotions_player_statuses.creation_counter_id=promotionGetCounterID AND gaming_promotions_player_statuses.client_stat_id=clientStatID
	AND gaming_promotions.promotion_id=gaming_promotions_player_statuses.promotion_id
  SET num_players_opted_in=num_players_opted_in+1, can_opt_in=IF((num_players_opted_in+1)<max_players,1,0);
  
  COMMIT AND CHAIN;  
    
END root$$

DELIMITER ;

