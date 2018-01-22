DROP procedure IF EXISTS `BonusForfeitAllBonusesByRuleID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusForfeitAllBonusesByRuleID`(sessionID BIGINT, bonusRuleID BIGINT, forfeitReason VARCHAR(80))
root: BEGIN
	
  -- Added in batches as not to lock players
  -- Added Pre Auth
  -- Added Free Rounds

  DECLARE bonusEnabledFlag, bonusFreeRoundEnabledFlag, bonusPreAuth, notificationEnabled TINYINT(1) DEFAULT 0;
  DECLARE bonusLostCounterID, lockClientCounterID, userID, bonusRuleIDCheck BIGINT DEFAULT -1;
  DECLARE batchSize INT DEFAULT 10000;  
  DECLARE numPlayerSelected BIGINT DEFAULT 0;

  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  SELECT value_bool INTO bonusFreeRoundEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_FREE_ROUND_ENABLED';
  SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';
  SELECT value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED'; 
  SELECT value_int  INTO batchSize FROM gaming_settings WHERE name='BONUS_BULK_BATCH_SIZE';  

  SELECT user_id INTO userID FROM sessions_main WHERE session_id=sessionID;
  SELECT bonus_rule_id, gaming_bonus_types.name INTO bonusRuleIDCheck, @bonusType FROM gaming_bonus_rules JOIN gaming_bonus_types ON gaming_bonus_rules.bonus_type_id=gaming_bonus_types.bonus_type_id WHERE gaming_bonus_rules.bonus_rule_id=bonusRuleID;

  IF (bonusEnabledFlag=0 OR bonusRuleIDCheck=-1) THEN
    LEAVE root;
  END IF;

  COMMIT;

  -- Bonuses Instances
  REPEAT   
	  START TRANSACTION;

	  INSERT INTO gaming_bonus_lost_counter (date_created)
	  VALUES (NOW());
	  SET bonusLostCounterID=LAST_INSERT_ID();

	  INSERT INTO gaming_bonus_lost_counter_bonus_instances (bonus_lost_counter_id, bonus_instance_id, client_stat_id)
	  SELECT bonusLostCounterID, gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.client_stat_id
	  FROM gaming_bonus_instances 
	  WHERE (gaming_bonus_instances.bonus_rule_id=bonusRuleID) AND gaming_bonus_instances.is_active=1
	  LIMIT batchSize 
      FOR UPDATE;

      SET numPlayerSelected=ROW_COUNT();

	  IF (numPlayerSelected > 0) THEN 
		IF (notificationEnabled) THEN
			INSERT INTO notifications_events (notification_event_type_id, event_id, is_processing) 
			SELECT 300, bonusLostCounterID,0 ON DUPLICATE KEY UPDATE is_processing=0;
		END IF;

        SELECT COUNT(*) INTO @numLocked
        FROM gaming_bonus_lost_counter_bonus_instances AS bonuses_lost
        JOIN gaming_client_stats ON bonuses_lost.client_stat_id=gaming_client_stats.client_stat_id
	    WHERE bonuses_lost.bonus_lost_counter_id=bonusLostCounterID
	    FOR UPDATE;

		CALL BonusOnLostUpdateStats(bonusLostCounterID, 'ForfeitByUser', bonusLostCounterID, sessionID, forfeitReason,0,NULL);
	  END IF;

      COMMIT;
  UNTIL numPlayerSelected < batchSize END REPEAT;

  -- Pre Auth
  IF (bonusPreAuth=1) THEN
	  SET numPlayerSelected=0;

	  REPEAT
		  START TRANSACTION;
			  
		  UPDATE gaming_bonus_instances_pre 
		  SET status=3, status_date=NOW(), auth_user_id=userID, auth_reason=forfeitReason 
		  WHERE bonus_rule_id=bonusRuleID AND status=1
		  LIMIT batchSize;

		  SET numPlayerSelected=ROW_COUNT();
	 
		  COMMIT;
	  UNTIL numPlayerSelected < batchSize END REPEAT;
  END IF; 


  -- Bit8 Free Rounds
  IF (bonusFreeRoundEnabledFlag=1 AND @bonusType IN ('FreeRound')) THEN
      SET numPlayerSelected=0;

	  REPEAT
		  START TRANSACTION;
		  
		  INSERT INTO gaming_bonus_lost_counter (date_created)
		  VALUES (NOW());
		  SET bonusLostCounterID=LAST_INSERT_ID();
	  
		  INSERT INTO gaming_bonus_lost_counter_bonus_free_rounds (bonus_lost_counter_id, bonus_free_round_id, client_stat_id)
		  SELECT bonusLostCounterID, gaming_bonus_free_rounds.bonus_free_round_id, gaming_client_stats.client_stat_id
		  FROM gaming_client_stats
		  JOIN gaming_bonus_free_rounds ON 
			(gaming_bonus_free_rounds.bonus_rule_id=bonusRuleID) AND gaming_bonus_free_rounds.is_active=1 AND
			gaming_bonus_free_rounds.client_stat_id=gaming_client_stats.client_stat_id
		  LIMIT batchSize 
		  FOR UPDATE;

		  SET numPlayerSelected=ROW_COUNT();
		  IF (numPlayerSelected > 0) THEN 
		  
			UPDATE gaming_bonus_free_rounds
			JOIN gaming_bonus_lost_counter_bonus_free_rounds ON gaming_bonus_free_rounds.bonus_free_round_id=gaming_bonus_lost_counter_bonus_free_rounds.bonus_free_round_id
			SET is_active=0, lost_date=NOW(), is_lost=1
			WHERE gaming_bonus_lost_counter_bonus_free_rounds.bonus_lost_counter_id=bonusLostCounterID AND gaming_bonus_free_rounds.is_active=1;
			
		  END IF;
		  
		  COMMIT;
	  UNTIL numPlayerSelected < batchSize END REPEAT;

  END IF;

  

END root$$

DELIMITER ;

