DROP procedure IF EXISTS `PromotionRandomlySelectPlayersToAward`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionRandomlySelectPlayersToAward`(promotionID BIGINT, recurrenceID BIGINT, sessionID BIGINT, OUT statusCode INT)
root: BEGIN
  
  DECLARE promotionIDCheck, bonusRuleAwardCounterID BIGINT DEFAULT -1;
  DECLARE awardNumPlayers, numPlayersAwarded, numAlreadySelected, numPlayersToSelect INT DEFAULT 0;
  DECLARE prizeType VARCHAR(80) DEFAULT NULL;
  DECLARE hasGivenReward, achievedDisabled TINYINT(1) DEFAULT 0;
  
  SELECT promotion_id, num_players_awarded, IF(award_num_players = 0, 999999999 , award_num_players), gaming_promotions_prize_types.name AS prize_type, has_given_reward, achieved_disabled 
  INTO promotionIDCheck, numPlayersAwarded, awardNumPlayers, prizeType, hasGivenReward, achievedDisabled
  FROM gaming_promotions 
  JOIN gaming_promotions_prize_types ON gaming_promotions.promotion_prize_type_id=gaming_promotions_prize_types.promotion_prize_type_id
  WHERE gaming_promotions.promotion_id=promotionID AND gaming_promotions.is_active=1 AND (award_num_players = 0 OR num_players_awarded<award_num_players)
  FOR UPDATE;
  
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
  
  SELECT COUNT(promotion_player_status_id) INTO numAlreadySelected
  FROM gaming_promotions_player_statuses
  WHERE promotion_id=promotionID AND selected_for_bonus=1 AND has_awarded_bonus=0 AND (promotion_recurrence_date_id = recurrenceID OR recurrenceID=0);

  SET numPlayersToSelect= awardNumPlayers - numPlayersAwarded - numAlreadySelected;

  SET @recNum=0;
  UPDATE gaming_promotions_player_statuses
  JOIN
  ( 
    SELECT @recNum:=@recNum+1 AS rec_num, promotion_player_status_id
    FROM 
    (
      SELECT promotion_player_status_id
      FROM gaming_promotions_player_statuses
      LEFT JOIN gaming_promotions_prize_amounts AS prize_amounts ON prize_amounts.promotion_id=promotionID AND prize_amounts.currency_id=gaming_promotions_player_statuses.currency_id
      WHERE gaming_promotions_player_statuses.promotion_id=promotionID AND ((achievedDisabled=1 AND gaming_promotions_player_statuses.achieved_amount>=prize_amounts.min_cap) OR requirement_achieved=1) AND selected_for_bonus=0 AND has_awarded_bonus=0
		AND (gaming_promotions_player_statuses.promotion_recurrence_date_id = recurrenceID OR recurrenceID = 0) 
		AND client_stat_id NOT IN
					(SELECT innerTab.client_stat_id FROM (SELECT client_stat_id, COUNT(*) AS numAwardedForPromotion, gaming_promotions.award_num_times_per_player
					 FROM gaming_promotions_player_statuses 
					 JOIN gaming_promotions ON gaming_promotions_player_statuses.promotion_id = gaming_promotions.promotion_id
					 WHERE gaming_promotions_player_statuses.promotion_id = promotionID AND has_awarded_bonus = 1
					 GROUP BY client_stat_id
					 HAVING numAwardedForPromotion >= gaming_promotions.award_num_times_per_player) innerTab)
      ORDER BY RAND()
    ) AS GS
  ) AS SelectedPlayers ON gaming_promotions_player_statuses.promotion_player_status_id=SelectedPlayers.promotion_player_status_id 
  SET selected_for_bonus=1, session_id=sessionID
  WHERE SelectedPlayers.rec_num<=numPlayersToSelect;
  
  SET statusCode=0; 
END root$$

DELIMITER ;

