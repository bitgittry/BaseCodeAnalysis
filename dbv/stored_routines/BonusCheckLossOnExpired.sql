DROP procedure IF EXISTS `BonusCheckLossOnExpired`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusCheckLossOnExpired`(clientStatID BIGINT)
root: BEGIN
   
  
  

  DECLARE bonusEnabledFlag, bonusFreeRoundEnabledFlag, bonusPreAuth TINYINT(1) DEFAULT 0;
  DECLARE bonusLostCounterID, lockClientCounterID, sessionID, clientStatIDCheck LONG DEFAULT -1;
  DECLARE batchSize INT DEFAULT 10000;  
  DECLARE numPlayerSelected,CWFreeRoundCounterID BIGINT DEFAULT 0;  

  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  SELECT value_bool INTO bonusFreeRoundEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_FREE_ROUND_ENABLED';
  SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';
    
  SELECT value_int  INTO batchSize FROM gaming_settings WHERE name='BONUS_BULK_BATCH_SIZE';  
  SET sessionID=0;
    
  IF (bonusEnabledFlag=0) THEN
    LEAVE root;
  END IF;

  COMMIT;



  
  REPEAT
	  START TRANSACTION;
      
	  INSERT INTO gaming_bonus_lost_counter (date_created)
	  VALUES (NOW());
	  SET bonusLostCounterID=LAST_INSERT_ID();
	  
	  INSERT INTO gaming_bonus_lost_counter_bonus_instances(bonus_lost_counter_id, bonus_instance_id, client_stat_id)
	  SELECT bonusLostCounterID, gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.client_stat_id
	  FROM gaming_bonus_instances 
	  WHERE (clientStatID=0 OR gaming_bonus_instances.client_stat_id=clientStatID) AND 
		gaming_bonus_instances.is_active=1 AND gaming_bonus_instances.expiry_date <= NOW() 
	  UNION
	  SELECT bonusLostCounterID, gaming_bonus_instances.bonus_instance_id, gaming_bonus_instances.client_stat_id
	  FROM gaming_bonus_instances 
	  JOIN gaming_cw_free_rounds ON gaming_bonus_instances.cw_free_round_id = gaming_cw_free_rounds.cw_free_round_id
	  WHERE (clientStatID=0 OR gaming_bonus_instances.client_stat_id=clientStatID) AND 
		gaming_cw_free_rounds.is_active=1 AND gaming_cw_free_rounds.expiry_date <= NOW() AND win_total=0  AND gaming_bonus_instances.is_active=1 
	  LIMIT batchSize;
	  
	  SET numPlayerSelected=ROW_COUNT();

	  IF (numPlayerSelected > 0) THEN 
	  
		SELECT COUNT(*) INTO @numLocked 
		FROM gaming_bonus_lost_counter_bonus_instances AS bonuses_lost
		JOIN gaming_client_stats ON bonuses_lost.client_stat_id=gaming_client_stats.client_stat_id
		WHERE bonuses_lost.bonus_lost_counter_id=bonusLostCounterID
		FOR UPDATE;

		CALL BonusOnLostUpdateStats(bonusLostCounterID, 'Expired', bonusLostCounterID, sessionID, 'Expired',0,NULL);
	  END IF;

      COMMIT;
  UNTIL numPlayerSelected < batchSize END REPEAT;

  REPEAT
	  START TRANSACTION;

	  SELECT COUNT(1) INTO numPlayerSelected 
	  FROM (
		  SELECT bonus_instance_id
		  FROM gaming_bonus_instances 
		  JOIN gaming_cw_free_rounds ON gaming_cw_free_rounds.cw_free_round_id = gaming_bonus_instances.cw_free_round_id  AND gaming_bonus_instances.is_active=1 
		  WHERE (clientStatID=0 OR gaming_bonus_instances.client_stat_id=clientStatID) AND
				 gaming_cw_free_rounds.is_active = 1 AND gaming_cw_free_rounds.expiry_date <= NOW() AND gaming_cw_free_rounds.win_total > 0 
		  LIMIT batchSize
	  ) AS playerToAward;

	  IF (numPlayerSelected > 0) THEN 

			INSERT INTO gaming_cw_free_round_counter (timestamp) VALUES (NOW());
			SET CWFreeRoundCounterID = LAST_INSERT_ID();

			UPDATE gaming_cw_free_rounds
			JOIN
			(
				SELECT gaming_cw_free_rounds.cw_free_round_id 
				FROM gaming_cw_free_rounds
				JOIN gaming_bonus_instances ON gaming_cw_free_rounds.cw_free_round_id = gaming_bonus_instances.cw_free_round_id  AND gaming_bonus_instances.is_active=1 
				WHERE (clientStatID=0 OR gaming_bonus_instances.client_stat_id=clientStatID) AND
					gaming_cw_free_rounds.is_active = 1 AND gaming_cw_free_rounds.expiry_date <= NOW() -- AND gaming_cw_free_rounds.win_total > 0
				LIMIT batchSize
			) AS free_rounds ON free_rounds.cw_free_round_id = gaming_cw_free_rounds.cw_free_round_id
			SET cw_free_round_counter_id = CWFreeRoundCounterID
			;	

			CALL BonusTransferedExpiredFreeRounds(CWFreeRoundCounterID);
	  END IF;

      COMMIT;
  UNTIL numPlayerSelected < batchSize END REPEAT;


  
  IF (bonusPreAuth=1) THEN
	SET numPlayerSelected=0;

	REPEAT
	  START TRANSACTION;
		  
	  UPDATE gaming_bonus_instances_pre 
	  SET status=4, status_date=NOW(), auth_user_id=null, auth_reason=null 
	  WHERE (clientStatID=0 OR client_stat_id=clientStatID) AND status=1 AND pre_expiry_date<=NOW()
	  LIMIT batchSize;

	  SET numPlayerSelected=ROW_COUNT();

	  COMMIT;
	UNTIL numPlayerSelected < batchSize END REPEAT;
  END IF;

  
  IF (bonusFreeRoundEnabledFlag=1) THEN
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
			(clientStatID=0 OR gaming_client_stats.client_stat_id=clientStatID) AND gaming_bonus_free_rounds.is_active=1 AND gaming_bonus_free_rounds.expiry_date <= NOW() AND
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

