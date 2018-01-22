
DROP procedure IF EXISTS `PromotionManuallySelectPlayersToAward`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionManuallySelectPlayersToAward`(promotionID BIGINT, clientStatIDArray TEXT, sessionID BIGINT, recurrenceDateID BIGINT, OUT statusCode INT)
root: BEGIN
  
  DECLARE promotionIDCheck, bonusRuleAwardCounterID, arrayCounterID, remainToSelectSeries, remainToSelectOccurrence BIGINT DEFAULT -1;
  DECLARE awardSeriesThresholdNotExceeded, numAlreadySelected, numPlayersToSelect, awardOccurenceThresholdNotExceeded INT DEFAULT 0;
  DECLARE prizeType VARCHAR(80) DEFAULT NULL;
  DECLARE hasGivenReward, achievedDisabled, isRecurrence  TINYINT(1) DEFAULT 0;

  SELECT recurrence_enabled INTO isRecurrence FROM gaming_promotions WHERE gaming_promotions.promotion_id=promotionID AND gaming_promotions.is_active=1 FOR UPDATE; 

  IF (isRecurrence = 1 AND recurrenceDateID = 0)THEN
	 SET statusCode = 6;
	 LEAVE root;
	END IF;

  SELECT gaming_promotions.promotion_id, IF(num_players_awarded< IF(award_num_players = 0, 999999999999, award_num_players), 1 , 0), gaming_promotions_prize_types.name AS prize_type, has_given_reward, achieved_disabled,
  IF(IFNULL(recurrence_dates.awarded_prize_count, 0) < IFNULL(gaming_promotions.award_num_players_per_occurence, 999999999999), 1, 0)  
  INTO promotionIDCheck, awardSeriesThresholdNotExceeded, prizeType, hasGivenReward, achievedDisabled, awardOccurenceThresholdNotExceeded
  FROM  gaming_promotions
  JOIN gaming_promotions_prize_types ON gaming_promotions.promotion_prize_type_id=gaming_promotions_prize_types.promotion_prize_type_id
  LEFT JOIN gaming_promotions_recurrence_dates AS recurrence_dates ON gaming_promotions.promotion_id = recurrence_dates.promotion_id 
	AND recurrence_dates.promotion_recurrence_date_id = recurrenceDateID
  WHERE gaming_promotions.promotion_id=promotionID AND gaming_promotions.is_active=1;

  IF (awardSeriesThresholdNotExceeded = 0) THEN
	 SET statusCode = 4;
     LEAVE root;
  END IF;

   IF (awardOccurenceThresholdNotExceeded = 0) THEN
	 SET statusCode = 5;
     LEAVE root;
   END IF;

  IF (promotionIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  IF (hasGivenReward=1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  IF (prizeType='OUTPUT_ONLY') THEN
    SET statusCode=3;
    LEAVE root;
  END IF;

  SET arrayCounterID=ArrayInsertIDArray(clientStatIDArray,',');
  
  
  UPDATE gaming_promotions_player_statuses
  JOIN gaming_array_counter_elems ON gaming_array_counter_elems.array_counter_id=arrayCounterID AND 
    gaming_promotions_player_statuses.promotion_id=promotionID AND gaming_promotions_player_statuses.client_stat_id=gaming_array_counter_elems.elem_id
  LEFT JOIN gaming_promotions_prize_amounts AS prize_amounts ON prize_amounts.promotion_id=promotionID AND prize_amounts.currency_id=gaming_promotions_player_statuses.currency_id
  SET gaming_promotions_player_statuses.selected_for_bonus=1, session_id=sessionID
  WHERE ((achievedDisabled=1 AND gaming_promotions_player_statuses.achieved_amount>=prize_amounts.min_cap) OR requirement_achieved=1) AND has_awarded_bonus=0;
  DELETE FROM gaming_array_counter_elems WHERE array_counter_id=arrayCounterID;
  
  
  SELECT IF(award_num_players = 0, 999999999999, award_num_players)-num_players_awarded-num_selected AS remain_to_select_series,
	award_num_players_per_occurence - recurrence_dates.awarded_prize_count - num_selected AS remain_to_select_occurrence
  INTO remainToSelectSeries, remainToSelectOccurrence
  FROM gaming_promotions
  LEFT JOIN gaming_promotions_recurrence_dates AS recurrence_dates ON gaming_promotions.promotion_id = recurrence_dates.promotion_id
  AND recurrence_dates.promotion_recurrence_date_id = recurrenceDateID 
  JOIN
  (
    SELECT COUNT(promotion_player_status_id) AS num_players
    FROM gaming_promotions_player_statuses
    WHERE promotion_id=promotionID
  ) AS NumPlayers
  JOIN
  (
    SELECT COUNT(promotion_player_status_id) AS num_selected
    FROM gaming_promotions_player_statuses
    WHERE promotion_id=promotionID AND requirement_achieved=1 AND selected_for_bonus=1 AND has_awarded_bonus=0
  ) AS NumSelected
  JOIN
  (
    SELECT COUNT(promotion_player_status_id) AS num_requirement_achieved
    FROM gaming_promotions_player_statuses
    WHERE promotion_id=promotionID AND requirement_achieved=1
  ) AS NumRequiremntAchieved
  WHERE gaming_promotions.promotion_id=promotionID ;
  
  IF (remainToSelectSeries < 0) THEN
    SET statusCode=4;
    LEAVE root;
  END IF;

 IF (remainToSelectOccurrence < 0) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;


  SET statusCode=0;
END root$$

DELIMITER ;

