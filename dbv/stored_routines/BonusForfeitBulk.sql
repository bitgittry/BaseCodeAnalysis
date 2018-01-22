DROP procedure IF EXISTS `BonusForfeitBulk`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusForfeitBulk`(sessionID BIGINT, bonusLostCounterID long)
root: BEGIN
  
  DECLARE bonusEnabledFlag TINYINT(1) DEFAULT 0;
  DECLARE rowCount int DEFAULT 0;

  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  
  IF NOT (bonusEnabledFlag) THEN
    LEAVE root;
  END IF;

  SELECT COUNT(*) INTO rowCount FROM gaming_bonus_lost_counter_bonus_instances WHERE bonus_lost_counter_id = bonusLostCounterID;

  IF (rowCount > 0) THEN 
    CALL BonusOnLostUpdateStats(bonusLostCounterID, 'BulkForfeit', sessionID, sessionID, 'Forfeited due to Dormant Account Configurations', 0, NULL);
  END IF;
  
END root$$

DELIMITER ;

