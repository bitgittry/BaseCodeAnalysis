DROP procedure IF EXISTS `PromotionGetPlayerPromotionStatusFullDetails`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionGetPlayerPromotionStatusFullDetails`(promotionPlayerStatusID BIGINT, OUT statusCode INT)
root: BEGIN
  
  DECLARE promotionPlayerStatusIDCheck, promotionID BIGINT DEFAULT -1;
  SELECT promotion_player_status_id, promotion_id INTO promotionPlayerStatusIDCheck, promotionID
  FROM gaming_promotions_player_statuses
  WHERE promotion_player_status_id=promotionPlayerStatusID;
  IF (promotionPlayerStatusIDCheck=-1 OR promotionID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  SELECT promotion_player_status_id, player_statuses.promotion_id, gaming_promotions.name AS promotion_name, player_statuses.child_promotion_id, player_statuses.client_stat_id, total_bet, total_win, total_loss, num_rounds, requirement_achieved, requirement_achieved_date, selected_for_bonus, has_awarded_bonus, player_statuses.priority, opted_in_date, opted_out_date, player_statuses.is_active, player_statuses.is_current, player_statuses.achieved_amount, player_statuses.achieved_percentage, player_statuses.achieved_days
    , gaming_promotions_achievement_types.name AS achievement_type, gaming_promotions.achievement_start_date AS promotion_start_date, gaming_promotions.achievement_end_date AS promotion_end_date, gaming_promotions.achievement_end_date<NOW() AS has_expired, player_statuses.promotion_recurrence_date_id,
	player_statuses.start_date, player_statuses.end_date,
	recurrence_date.recurrence_no, recurrence_date.is_current AS recurrence_is_current
  FROM gaming_promotions_player_statuses As player_statuses 
  JOIN gaming_promotions ON player_statuses.promotion_id=gaming_promotions.promotion_id
  JOIN gaming_promotions_achievement_types ON gaming_promotions.promotion_achievement_type_id=gaming_promotions_achievement_types.promotion_achievement_type_id
  LEFT JOIN gaming_promotions_recurrence_dates AS recurrence_date ON recurrence_date.promotion_recurrence_date_id=player_statuses.promotion_recurrence_date_id
  WHERE player_statuses.promotion_player_status_id=promotionPlayerStatusID;
  
  SELECT gaming_promotions_player_statuses_daily.promotion_player_status_id, day_no, day_start_time, day_end_time, gaming_promotions_status_days.date_display, day_bet, day_win, day_loss, day_num_rounds, daily_requirement_achieved, gaming_promotions_player_statuses_daily.achieved_amount, gaming_promotions_player_statuses_daily.achieved_percentage, (NOW() BETWEEN day_start_time AND day_end_time) AS is_current_day 
  FROM gaming_promotions_player_statuses  
  JOIN gaming_promotions_player_statuses_daily ON gaming_promotions_player_statuses.promotion_player_status_id=gaming_promotions_player_statuses_daily.promotion_player_status_id  
  JOIN gaming_promotions_status_days ON gaming_promotions_player_statuses_daily.promotion_status_day_id=gaming_promotions_status_days.promotion_status_day_id AND 
	 (gaming_promotions_player_statuses.promotion_recurrence_date_id IS NULL OR gaming_promotions_player_statuses.promotion_recurrence_date_id=gaming_promotions_status_days.promotion_recurrence_date_id)
  WHERE gaming_promotions_player_statuses.promotion_player_status_id=promotionPlayerStatusID;
  
  SELECT round_contributions.game_round_id, gaming_game_rounds.date_time_start AS round_time_start, gaming_game_rounds.date_time_end AS round_time_end, round_contributions.promotion_player_status_id, round_contributions.promotion_player_status_day_id, day_no, gaming_promotions_status_days.date_display AS day_date_display, round_contributions.bet, round_contributions.win, round_contributions.loss
  FROM gaming_game_rounds_promotion_contributions AS round_contributions
  JOIN gaming_game_rounds ON round_contributions.game_round_id=gaming_game_rounds.game_round_id
  JOIN gaming_games ON gaming_game_rounds.game_id=gaming_games.game_id
  JOIN gaming_game_manufacturers ON gaming_game_rounds.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
  LEFT JOIN gaming_promotions_player_statuses_daily ON round_contributions.promotion_player_status_day_id=gaming_promotions_player_statuses_daily.promotion_player_status_day_id  
  LEFT JOIN gaming_promotions_status_days ON gaming_promotions_player_statuses_daily.promotion_status_day_id=gaming_promotions_status_days.promotion_status_day_id
  WHERE round_contributions.promotion_player_status_id=promotionPlayerStatusID;
  
  SET statusCode=0;
END root$$

DELIMITER ;

