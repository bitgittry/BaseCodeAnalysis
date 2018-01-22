DROP procedure IF EXISTS `PromotionGetPlayerStatuses`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionGetPlayerStatuses`(promotionID BIGINT, requirementAchievedOnly TINYINT(1), promotionRecurrenceDateID BIGINT)
BEGIN
  
  SELECT gaming_promotions.num_players_opted_in AS num_players, num_requirement_achieved, award_num_players, num_players_awarded, num_selected, award_num_players-num_players_awarded-num_selected AS remain_to_select
  FROM gaming_promotions
  JOIN
  (
    SELECT COUNT(promotion_player_status_id) AS num_selected
    FROM gaming_promotions_player_statuses
    WHERE promotion_id=promotionID AND requirement_achieved=1 AND selected_for_bonus=1 AND has_awarded_bonus=0
    AND (IFNULL(promotion_recurrence_date_id, 0) = promotionRecurrenceDateID OR promotionRecurrenceDateID = 0)
  ) AS NumSelected
  JOIN
  (
    SELECT COUNT(promotion_player_status_id) AS num_requirement_achieved
    FROM gaming_promotions_player_statuses
    WHERE promotion_id=promotionID AND requirement_achieved=1
	AND (IFNULL(promotion_recurrence_date_id, 0) = promotionRecurrenceDateID OR promotionRecurrenceDateID = 0)
  ) AS NumRequiremntAchieved
  WHERE promotion_id=promotionID;
  

  SELECT promotion_player_status_id, player_statuses.promotion_id, gaming_promotions.name AS promotion_name, player_statuses.child_promotion_id, player_statuses.client_stat_id, total_bet, total_win, total_loss, num_rounds, requirement_achieved, requirement_achieved_date, selected_for_bonus, has_awarded_bonus, player_statuses.priority, opted_in_date, opted_out_date, player_statuses.is_active, player_statuses.is_current, player_statuses.achieved_amount, player_statuses.achieved_percentage, player_statuses.achieved_days
    , gaming_promotions_achievement_types.name AS achievement_type, gaming_promotions.achievement_start_date AS promotion_start_date, gaming_promotions.achievement_end_date AS promotion_end_date, gaming_promotions.achievement_end_date<NOW() AS has_expired, player_statuses.promotion_recurrence_date_id,
	player_statuses.start_date, player_statuses.end_date, recurrence_date.recurrence_no, recurrence_date.is_current AS recurrence_is_current
  FROM gaming_promotions_player_statuses AS player_statuses
  JOIN gaming_promotions ON 
    player_statuses.promotion_id=promotionID AND (requirementAchievedOnly=0 OR requirement_achieved=1) AND player_statuses.is_active=1 AND
    player_statuses.promotion_id=gaming_promotions.promotion_id
  JOIN gaming_promotions_achievement_types ON gaming_promotions.promotion_achievement_type_id=gaming_promotions_achievement_types.promotion_achievement_type_id
  LEFT JOIN gaming_promotions_recurrence_dates AS recurrence_date ON recurrence_date.promotion_recurrence_date_id=player_statuses.promotion_recurrence_date_id
  WHERE IFNULL(player_statuses.promotion_recurrence_date_id, 0) = promotionRecurrenceDateID OR promotionRecurrenceDateID = 0;

  SELECT promotion_status_day_id, day_no, day_start_time, day_end_time, date_display
  FROM gaming_promotions_status_days 
  WHERE promotion_id=promotionID AND (IFNULL(promotion_recurrence_date_id, 0) = promotionRecurrenceDateID OR promotionRecurrenceDateID = 0);
END$$

DELIMITER ;

