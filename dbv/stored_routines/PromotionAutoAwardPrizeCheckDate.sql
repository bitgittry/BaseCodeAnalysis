DROP procedure IF EXISTS `PromotionAutoAwardPrizeCheckDate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionAutoAwardPrizeCheckDate`()
BEGIN
  -- IF award_prize_timing_time is NULL then no condition on time
  -- IF award_prize_timing_time is empty string then no condition on time
  
  
  DECLARE noMoreRecords, promotionAwardPrizeOnAchievementEnabled, singlePromotionEnabled TINYINT(1) DEFAULT 0;
  DECLARE promotionID, promotionRecurrenceID BIGINT DEFAULT -1;
  DECLARE awardPrizeStatusCode INT DEFAULT 0;
  DECLARE dateTimeNow DATETIME DEFAULT NOW(); 
 
  -- Single Occurrence
  DECLARE awardPrizeCursor CURSOR FOR 
  SELECT gaming_promotions.promotion_id 
  FROM gaming_promotions
  LEFT JOIN gaming_promotions_recurrence_dates dates ON gaming_promotions.promotion_id = dates.promotion_id
  WHERE gaming_promotions.is_active=1 AND has_given_reward=0 AND automatic_award_prize_enabled=1
	AND (NOW()>=IFNULL(award_prize_on_date, DATE_ADD(gaming_promotions.achievement_end_date, INTERVAL IFNULL(gaming_promotions.award_prize_timing_num_days,0) DAY)))
    AND gaming_promotions.award_prize_timing_type = 3  
    AND (award_prize_timing_time IS NULL OR award_prize_timing_time = '' OR TIME(dateTimeNow) >= TIME(award_prize_timing_time))
    AND dates.promotion_recurrence_date_id IS NULL;

  -- Re-occerrence promotions
  DECLARE awardDaysAfterOccurrenceCursor CURSOR FOR 
    SELECT gaming_promotions.promotion_id, dates.promotion_recurrence_date_id
    FROM gaming_promotions 
	JOIN gaming_promotions_recurrence_dates dates ON gaming_promotions.promotion_id = dates.promotion_id
    WHERE gaming_promotions.is_active=1 AND gaming_promotions.has_given_reward=0 AND automatic_award_prize_enabled=1 
		AND (NOW()>=IFNULL(award_prize_on_date, DATE_ADD(dates.end_date, INTERVAL IFNULL(gaming_promotions.award_prize_timing_num_days, 0) DAY)))
		AND gaming_promotions.award_prize_timing_type = 3  
		AND (award_prize_timing_time IS NULL OR award_prize_timing_time = '' OR TIME(dateTimeNow) >= TIME(award_prize_timing_time));

  DECLARE promotionAwardOnDaysAchievementCursor CURSOR FOR 
    SELECT pps.promotion_id, IFNULL(pps.promotion_recurrence_date_id, 0) 
     FROM gaming_promotions
    JOIN gaming_promotions_player_statuses AS pps ON
	  
	  (gaming_promotions.award_prize_timing_type = 2 AND gaming_promotions.is_single=0 AND 
		gaming_promotions.achievement_start_date<dateTimeNow AND DATE_ADD(gaming_promotions.achievement_end_date, INTERVAL gaming_promotions.award_prize_timing_num_days+1 DAY)>dateTimeNow) 
		AND (gaming_promotions.award_num_players=0 OR gaming_promotions.num_players_awarded<gaming_promotions.award_num_players) AND gaming_promotions.promotion_achievement_type_id NOT IN (5)	AND
	  
      (pps.promotion_id=gaming_promotions.promotion_id AND pps.requirement_achieved=1 AND pps.has_awarded_bonus=0) AND
	    dateTimeNow>=DATE_ADD(pps.requirement_achieved_date, INTERVAL gaming_promotions.award_prize_timing_num_days DAY)
	    AND (award_prize_timing_time IS NULL OR award_prize_timing_time = '' OR TIME(dateTimeNow) >= TIME(gaming_promotions.award_prize_timing_time))
	LEFT JOIN gaming_promotions_recurrence_dates dates ON dates.promotion_recurrence_date_id = pps.promotion_recurrence_date_id 
	WHERE (IFNULL(gaming_promotions.award_num_players_per_occurence, 99999999999) > IFNULL(dates.awarded_prize_count, 0))
	GROUP BY pps.promotion_id, pps.promotion_recurrence_date_id;     


    DECLARE promotionAwardOnDaysAchievementSingleCursor CURSOR FOR 
	SELECT pps.promotion_id, IFNULL(pps.promotion_recurrence_date_id, 0)
	FROM gaming_promotions
    JOIN gaming_promotions_player_statuses AS pps ON
    
	(gaming_promotions.award_prize_timing_type = 2 AND gaming_promotions.is_single=1 AND 
		gaming_promotions.achievement_start_date<dateTimeNow AND DATE_ADD(gaming_promotions.achievement_end_date, INTERVAL gaming_promotions.award_prize_timing_num_days+1 DAY)>dateTimeNow) 
		AND (gaming_promotions.award_num_players=0 OR gaming_promotions.num_players_awarded<=gaming_promotions.award_num_players) AND gaming_promotions.promotion_achievement_type_id IN (1,2) AND
 
      (pps.promotion_id=gaming_promotions.promotion_id AND pps.requirement_achieved=1 AND pps.has_awarded_bonus=0) AND
		pps.achieved_amount!=pps.single_achieved_amount_awarded AND
	    dateTimeNow>=DATE_ADD(pps.requirement_achieved_date, INTERVAL gaming_promotions.award_prize_timing_num_days DAY)
	    AND (award_prize_timing_time IS NULL OR award_prize_timing_time = '' OR TIME(dateTimeNow) >= TIME(gaming_promotions.award_prize_timing_time))
	LEFT JOIN gaming_promotions_recurrence_dates dates ON dates.promotion_recurrence_date_id = pps.promotion_recurrence_date_id 
	WHERE (IFNULL(gaming_promotions.award_num_players_per_occurence, 99999999999) >= IFNULL(dates.awarded_prize_count, 0)) 
	GROUP BY pps.promotion_id, pps.promotion_recurrence_date_id;  
   
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;

  SET @timeStart=NOW();
  OPEN awardPrizeCursor;
  allPromotionsLabel: LOOP  
    SET noMoreRecords=0;
    FETCH awardPrizeCursor INTO promotionID;
    IF (noMoreRecords) THEN
      LEAVE allPromotionsLabel;
    END IF;
  
    SET @sessionID=0;
    SET awardPrizeStatusCode=0;
    CALL PromotionAwardPrizeToPlayers(promotionID, 0, @sessionID, 0, awardPrizeStatusCode);
  
  END LOOP allPromotionsLabel;
  CLOSE awardPrizeCursor;

    SET noMoreRecords = 0;

 
 OPEN awardDaysAfterOccurrenceCursor;
  occurrenceLabel: LOOP 
    
    FETCH awardDaysAfterOccurrenceCursor INTO promotionID, promotionRecurrenceID;
    IF (noMoreRecords) THEN
      LEAVE occurrenceLabel;
    END IF;
  
    SET @sessionID=0;
    SET awardPrizeStatusCode=0;
    CALL PromotionAwardPrizeToPlayers(promotionID, promotionRecurrenceID, @sessionID, 0, awardPrizeStatusCode);
  
  END LOOP occurrenceLabel;
  CLOSE awardDaysAfterOccurrenceCursor;
   
  
  SELECT value_bool INTO promotionAwardPrizeOnAchievementEnabled FROM gaming_settings WHERE name='PROMOTION_AWARD_PRIZE_ON_ACHIEVEMENT_ENABLED';
  IF (promotionAwardPrizeOnAchievementEnabled=1) THEN

    OPEN promotionAwardOnDaysAchievementCursor;
    allPromotionsOnAchievement: LOOP 
      SET noMoreRecords=0;
      FETCH promotionAwardOnDaysAchievementCursor INTO promotionID, promotionRecurrenceID;
      IF (noMoreRecords) THEN
        LEAVE allPromotionsOnAchievement;
      END IF; 
    
      CALL PromotionAwardPrizeOnAchievement(promotionID, promotionRecurrenceID);
    
    END LOOP allPromotionsOnAchievement;
    CLOSE promotionAwardOnDaysAchievementCursor;
  END IF;
  

  SELECT value_bool INTO singlePromotionEnabled FROM gaming_settings WHERE name='PROMOTION_SINGLE_PROMOS_ENABLED';
  IF (promotionAwardPrizeOnAchievementEnabled=1 AND singlePromotionEnabled = 1) THEN

    OPEN promotionAwardOnDaysAchievementSingleCursor;
    allPromotionsSingleOnAchievement: LOOP 
      SET noMoreRecords=0;
      FETCH promotionAwardOnDaysAchievementSingleCursor INTO promotionID, promotionRecurrenceID;
      IF (noMoreRecords) THEN
        LEAVE allPromotionsSingleOnAchievement;
      END IF; 
    
      CALL PromotionAwardPrizeForSingle(promotionID, promotionRecurrenceID);
    
    END LOOP allPromotionsSingleOnAchievement;
    CLOSE promotionAwardOnDaysAchievementSingleCursor;
  END IF;
  
END$$

DELIMITER ;

