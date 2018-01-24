
DROP procedure IF EXISTS `BonusForfeitBonusByUser`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusForfeitBonusByUser`(sessionID BIGINT, clientStatID BIGINT, bonusInstanceID BIGINT, evenIfSecured TINYINT(1))
root: BEGIN
  
  DECLARE bonusEnabledFlag TINYINT(1) DEFAULT 0;
  DECLARE bonusLostCounterID, clientStatIDCheck LONG DEFAULT -1;
  
  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  
  IF NOT (bonusEnabledFlag) THEN
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
  FROM gaming_bonus_instances
  WHERE 
    gaming_bonus_instances.client_stat_id=clientStatID AND
    (bonusInstanceID=0 OR gaming_bonus_instances.bonus_instance_id=bonusInstanceID) AND 
    ((NOT is_secured OR evenIfSecured) AND NOT is_lost); 
  
  
  IF (ROW_COUNT() > 0) THEN 
    CALL BonusOnLostUpdateStats(bonusLostCounterID, 'ForfeitByUser', sessionID, sessionID,0,NULL); 
  END IF;
  
END root$$

DELIMITER ;

