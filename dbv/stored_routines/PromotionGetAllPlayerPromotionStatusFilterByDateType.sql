DROP procedure IF EXISTS `PromotionGetAllPlayerPromotionStatusFilterByDateType`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionGetAllPlayerPromotionStatusFilterByDateType`(promotionFilterDateType VARCHAR(80), clientStatID BIGINT, currencyID BIGINT, activeOnly TINYINT(1), operatorGameIDFilter BIGINT, dateFrom DATETIME)
BEGIN
  
  DECLARE promotionGetCounterID BIGINT DEFAULT -1;
	DECLARE curDateTemp DATETIME;
  
  INSERT INTO gaming_promotion_get_counter (date_added) VALUES (NOW());
  SET promotionGetCounterID=LAST_INSERT_ID();
  
  
  SET curDateTemp = NOW();
  CASE promotionFilterDateType 
    WHEN 'ALL' THEN
      INSERT INTO gaming_promotion_get_counter_promotions (promotion_get_counter_id, promotion_id) 
      SELECT promotionGetCounterID, gaming_promotions.promotion_id 
      FROM gaming_promotions 
      JOIN gaming_promotions_player_statuses ON gaming_promotions_player_statuses.client_stat_id=clientStatID AND 
		(dateFrom IS NULL OR (IFNULL(gaming_promotions_player_statuses.start_date,gaming_promotions.achievement_start_date)>=dateFrom)) AND
		gaming_promotions.promotion_id=gaming_promotions_player_statuses.promotion_id  
      WHERE 
        (activeOnly=0 OR gaming_promotions.is_active=1) AND gaming_promotions.is_child=0 AND
        (operatorGameIDFilter=0 OR (SELECT COUNT(operator_game_id) FROM gaming_promotions_games WHERE promotion_id=gaming_promotions.promotion_id AND operator_game_id=operatorGameIDFilter))  
	  GROUP BY gaming_promotions.promotion_id;
	WHEN 'CURRENT' THEN 
      INSERT INTO gaming_promotion_get_counter_promotions (promotion_get_counter_id, promotion_id) 
      SELECT promotionGetCounterID, gaming_promotions.promotion_id 
      FROM gaming_promotions 
      JOIN gaming_promotions_player_statuses ON gaming_promotions_player_statuses.client_stat_id=clientStatID AND gaming_promotions_player_statuses.is_active=1 AND gaming_promotions_player_statuses.is_current=1 AND gaming_promotions.promotion_id=gaming_promotions_player_statuses.promotion_id
      WHERE 
        (achievement_start_date <= curDateTemp AND achievement_end_date >= curDateTemp) AND 
        (activeOnly=0 OR gaming_promotions.is_active=1) AND gaming_promotions.is_child=0 AND
        (operatorGameIDFilter=0 OR (SELECT COUNT(operator_game_id) FROM gaming_promotions_games WHERE promotion_id=gaming_promotions.promotion_id AND operator_game_id=operatorGameIDFilter))
		AND (activeOnly=0 OR gaming_promotions_player_statuses.requirement_achieved=0)
		GROUP BY gaming_promotions.promotion_id;
    WHEN 'CURRENT+FUTURE' THEN 
      INSERT INTO gaming_promotion_get_counter_promotions (promotion_get_counter_id, promotion_id) 
      SELECT promotionGetCounterID, gaming_promotions.promotion_id 
      FROM gaming_promotions 
      JOIN gaming_promotions_player_statuses ON gaming_promotions_player_statuses.client_stat_id=clientStatID AND gaming_promotions_player_statuses.is_active=1 AND gaming_promotions_player_statuses.is_current=1 AND gaming_promotions.promotion_id=gaming_promotions_player_statuses.promotion_id
      WHERE
        (gaming_promotions.achievement_end_date >= curDateTemp) AND 
        (activeOnly=0 OR gaming_promotions.is_active=1) AND gaming_promotions.is_child=0 AND
        (operatorGameIDFilter=0 OR (SELECT COUNT(operator_game_id) FROM gaming_promotions_games WHERE promotion_id=gaming_promotions.promotion_id AND operator_game_id=operatorGameIDFilter))   
	    AND (activeOnly=0 OR gaming_promotions_player_statuses.requirement_achieved=0)
	   GROUP BY gaming_promotions.promotion_id;   
     WHEN 'FUTURE' THEN 
      INSERT INTO gaming_promotion_get_counter_promotions (promotion_get_counter_id, promotion_id) 
      SELECT promotionGetCounterID, gaming_promotions.promotion_id 
      FROM gaming_promotions 
      JOIN gaming_promotions_player_statuses ON gaming_promotions_player_statuses.client_stat_id=clientStatID AND gaming_promotions_player_statuses.is_active=1 AND gaming_promotions_player_statuses.is_current=1 AND gaming_promotions.promotion_id=gaming_promotions_player_statuses.promotion_id 
      WHERE 
        (achievement_start_date >= curDateTemp) AND 
        (activeOnly=0 OR gaming_promotions.is_active=1) AND gaming_promotions.is_child=0 AND
        (operatorGameIDFilter=0 OR (SELECT COUNT(operator_game_id) FROM gaming_promotions_games WHERE promotion_id=gaming_promotions.promotion_id AND operator_game_id=operatorGameIDFilter)) 
   GROUP BY gaming_promotions.promotion_id;
 WHEN 'PAST' THEN 
      INSERT INTO gaming_promotion_get_counter_promotions (promotion_get_counter_id, promotion_id) 
      SELECT promotionGetCounterID, gaming_promotions.promotion_id 
      FROM gaming_promotions 
      JOIN gaming_promotions_player_statuses ON gaming_promotions_player_statuses.client_stat_id=clientStatID AND 
       gaming_promotions_player_statuses.is_active=1 AND gaming_promotions_player_statuses.is_current=1 AND gaming_promotions.promotion_id=gaming_promotions_player_statuses.promotion_id AND
       (dateFrom IS NULL OR (IFNULL(gaming_promotions_player_statuses.start_date,gaming_promotions.achievement_start_date)>=dateFrom)) 
     WHERE 
        (achievement_end_date <= curDateTemp) AND 
        (activeOnly=0 OR gaming_promotions.is_active=1) AND gaming_promotions.is_child=0 AND
        (operatorGameIDFilter=0 OR (SELECT COUNT(operator_game_id) FROM gaming_promotions_games WHERE promotion_id=gaming_promotions.promotion_id AND operator_game_id=operatorGameIDFilter))
	GROUP BY gaming_promotions.promotion_id;
  END CASE;
  
  SELECT promotion_player_status_id, player_statuses.promotion_id, gaming_promotions.name AS promotion_name, player_statuses.child_promotion_id, player_statuses.client_stat_id, total_bet, total_win, total_loss, num_rounds, requirement_achieved, requirement_achieved_date, selected_for_bonus, has_awarded_bonus, player_statuses.priority, 
	opted_in_date, opted_out_date, player_statuses.is_active, player_statuses.is_current, player_statuses.achieved_amount, player_statuses.achieved_percentage, player_statuses.achieved_days,
    gaming_promotions_achievement_types.name AS achievement_type, gaming_promotions.achievement_start_date AS promotion_start_date, gaming_promotions.achievement_end_date AS promotion_end_date, gaming_promotions.achievement_end_date<NOW() AS has_expired, 	
    gaming_promotions_games.promotion_wgr_req_weight AS game_wgr_req_weight, 
    player_statuses.promotion_recurrence_date_id, player_statuses.start_date, player_statuses.end_date,
	recurrence_date.recurrence_no, recurrence_date.is_current AS recurrence_is_current
  FROM gaming_promotions_player_statuses AS player_statuses
  JOIN gaming_promotion_get_counter_promotions ON 
    promotion_get_counter_id=promotionGetCounterID AND 
    player_statuses.promotion_id=gaming_promotion_get_counter_promotions.promotion_id AND 
	(dateFrom IS NUll OR player_statuses.start_date IS NULL OR player_statuses.start_date >= dateFrom) AND
    player_statuses.client_stat_id=clientStatID AND (promotionFilterDateType='All' OR player_statuses.is_active=1)
  JOIN gaming_promotions ON gaming_promotion_get_counter_promotions.promotion_id=gaming_promotions.promotion_id
  JOIN gaming_promotions_achievement_types ON gaming_promotions.promotion_achievement_type_id=gaming_promotions_achievement_types.promotion_achievement_type_id
  LEFT JOIN gaming_promotions_games ON
    (operatorGameIDFilter!=0 AND (gaming_promotions_games.promotion_id=player_statuses.promotion_id AND gaming_promotions_games.operator_game_id=operatorGameIDFilter))
  LEFT JOIN gaming_promotions_recurrence_dates AS recurrence_date ON recurrence_date.promotion_recurrence_date_id=player_statuses.promotion_recurrence_date_id
  ORDER BY player_statuses.priority ASC, player_statuses.opted_in_date DESC;
 
  
  SELECT gaming_promotions_player_statuses_daily.promotion_player_status_id, day_no, day_start_time, day_end_time, gaming_promotions_status_days.date_display,
 day_bet, day_win, day_loss, day_num_rounds, daily_requirement_achieved,
  gaming_promotions_player_statuses_daily.achieved_amount, gaming_promotions_player_statuses_daily.achieved_percentage,
 (NOW() BETWEEN day_start_time AND day_end_time) AS is_current_day 
  FROM gaming_promotions_player_statuses 
  JOIN gaming_promotion_get_counter_promotions ON 
    promotion_get_counter_id=promotionGetCounterID AND 
    gaming_promotions_player_statuses.promotion_id=gaming_promotion_get_counter_promotions.promotion_id AND 
    gaming_promotions_player_statuses.client_stat_id=clientStatID AND gaming_promotions_player_statuses.is_active=1
  JOIN gaming_promotions_player_statuses_daily ON gaming_promotions_player_statuses.promotion_player_status_id=gaming_promotions_player_statuses_daily.promotion_player_status_id 
  JOIN gaming_promotions_status_days ON gaming_promotions_player_statuses_daily.promotion_status_day_id=gaming_promotions_status_days.promotion_status_day_id AND
   (gaming_promotions_player_statuses.promotion_recurrence_date_id IS NULL OR gaming_promotions_player_statuses.promotion_recurrence_date_id=gaming_promotions_status_days.promotion_recurrence_date_id);
 
  
  SET @operatorGameIDFilter=-1;
  CALL PromotionGetAllPromotionsByPromotionCounterIDAndCurrencyID(promotionGetCounterID, currencyID, @operatorGameIDFilter, clientStatID);
  
END$$

DELIMITER ;

