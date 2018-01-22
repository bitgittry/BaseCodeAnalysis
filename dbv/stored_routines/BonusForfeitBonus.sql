DROP procedure IF EXISTS `BonusForfeitBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusForfeitBonus`(sessionID BIGINT, clientStatID BIGINT, bonusInstanceID BIGINT, evenIfSecured TINYINT(1), bonusLostType VARCHAR(80), forfeitReason VARCHAR(80))
root: BEGIN
  
  
  -- If already forfeited return counter_id 
  
  DECLARE bonusEnabledFlag TINYINT(1) DEFAULT 0;
  DECLARE bonusLostCounterID, clientStatIDCheck BIGINT DEFAULT -1;
  
  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  
  IF NOT (bonusEnabledFlag) THEN
    SELECT bonusLostCounterID;
    LEAVE root;
  END IF;
  
  SELECT client_stat_id INTO clientStatIDCheck
  FROM gaming_client_stats
  WHERE client_stat_id=clientStatID
  FOR UPDATE;
  
  INSERT INTO gaming_bonus_lost_counter (date_created)
  VALUES (NOW());
  
  SET bonusLostCounterID=LAST_INSERT_ID();
  
  INSERT INTO gaming_bonus_lost_counter_bonus_instances(bonus_lost_counter_id, bonus_instance_id)
  SELECT bonusLostCounterID, bonus_instance_id
  FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses)
  WHERE 
    gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active=1 AND
    (bonusInstanceID=0 OR gaming_bonus_instances.bonus_instance_id=bonusInstanceID) AND 
    ((NOT is_secured OR evenIfSecured) AND NOT is_lost); 
  
  IF (ROW_COUNT()=0) THEN
	IF (IFNULL(bonusInstanceID, 0) !=0) THEN
		SELECT bonus_lost_counter_id INTO bonusLostCounterID 
        FROM gaming_bonus_lost_counter_bonus_instances WHERE bonus_instance_id=bonusInstanceID 
        LIMIT 1;
        
        SELECT bonusLostCounterID;
	END IF;
  ELSE
  
	  CALL BonusOnLostUpdateStats(bonusLostCounterID, bonusLostType, sessionID, sessionID, forfeitReason,0,NULL); 

	  -- The below IF condition was done because this procedure is now also being called from PlaceWinTypeTwo with the lost type of 'IsUsedAll'.
	  -- Fix due to an error being encountered with the select statement below for functionality - 'Bonus lost through wagering should forfeit bonus program' BGL-184
	  IF (bonusLostType != "IsUsedAll") THEN
		SELECT bonusLostCounterID;
	  END IF;
	  
  END IF;
  
END root$$

DELIMITER ;

