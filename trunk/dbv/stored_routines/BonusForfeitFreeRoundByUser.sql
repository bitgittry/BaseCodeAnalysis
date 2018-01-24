
DROP procedure IF EXISTS `BonusForfeitFreeRoundByUser`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusForfeitFreeRoundByUser`(sessionID BIGINT, clientStatID BIGINT, bonusFreeRoundID BIGINT)
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
  UPDATE gaming_bonus_free_rounds
  SET is_active=0, lost_date=NOW(), is_lost=1
  WHERE 
    gaming_bonus_free_rounds.client_stat_id=clientStatID AND
    (bonusFreeRoundID=0 OR gaming_bonus_free_rounds.bonus_free_round_id=bonusFreeRoundID) AND 
    is_active; 
  
  
  IF (ROW_COUNT() > 0) THEN 
    CALL BonusOnLostUpdateStats(bonusLostCounterID, 'ForfeitByUser', sessionID, sessionID,NULL,0,NULL); 
  END IF;

  
END root$$

DELIMITER ;

