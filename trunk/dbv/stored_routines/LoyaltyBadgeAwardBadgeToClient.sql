DROP procedure IF EXISTS `LoyaltyBadgeAwardBadgeToClient`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LoyaltyBadgeAwardBadgeToClient`(badgeID BIGINT, clientID BIGINT, ruleInstanceID BIGINT, OUT statusCode INT)
root: BEGIN
  
  DECLARE clientIDCheck BIGINT DEFAULT -1;
  DECLARE badgeType VARCHAR(80) DEFAULT '';
  DECLARE numUnits, minVipLevel, playerVipLevel INT DEFAULT NULL;
  DECLARE endDate DATETIME DEFAULT NULL;
  DECLARE badgeAchievedForUser BIGINT DEFAULT 0;
  
  SELECT gaming_clients.client_id,  gaming_clients.vip_level
  INTO clientIDCheck, playerVipLevel 
  FROM gaming_client_stats 
  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
  WHERE gaming_client_stats.client_id=clientID AND gaming_client_stats.is_active=1 LIMIT 1 FOR UPDATE;

  IF (clientIDCheck=-1) THEN
	SET statusCode=0;
	LEAVE root;
  END IF;

  SELECT gaming_loyalty_badge_types.name, gaming_loyalty_badges.num_units, gaming_loyalty_badges.min_vip_level, gaming_loyalty_badges.end_date 
  INTO badgeType, numUnits, minVipLevel, endDate 
  FROM gaming_loyalty_badge_types
  JOIN gaming_loyalty_badges ON gaming_loyalty_badges.loyalty_badge_type_id = gaming_loyalty_badge_types.loyalty_badge_type_id
  WHERE gaming_loyalty_badges.loyalty_badge_id = badgeID FOR UPDATE;

  IF (numUnits IS NOT NULL AND numUnits<1) THEN
	SET statusCode=2;
	LEAVE root;
  END IF;

  IF (endDate IS NOT NULL AND endDate<NOW()) THEN
	SET statusCode=3;
	LEAVE root;
  END IF;

  IF (minVipLevel IS NOT NULL AND playerVipLevel IS NOT NULL AND playerVipLevel<minVipLevel) THEN
	SET statusCode=4;
	LEAVE root;
  END IF;

  CASE badgeType
    WHEN 'Repeatable' THEN

      INSERT INTO gaming_client_loyalty_badges_history (client_id, loyalty_badge_id, time_stamp, rule_instance_id)
      VALUES (clientID, badgeID, NOW(), ruleInstanceID);
      
      INSERT INTO gaming_client_loyalty_badges (client_id, loyalty_badge_id, num_units)
      VALUES (clientID, badgeID, 1)
      ON DUPLICATE KEY UPDATE num_units = num_units+1;
      
    WHEN 'One-time-awarded' THEN 
      SELECT num_units INTO badgeAchievedForUser FROM gaming_client_loyalty_badges WHERE loyalty_badge_id=badgeID AND client_id = clientID LIMIT 1;
      
      IF badgeAchievedForUser=0 THEN
        INSERT INTO gaming_client_loyalty_badges (client_id,loyalty_badge_id,num_units)
        VALUES (clientID,badgeID,1) ON DUPLICATE KEY UPDATE num_units = num_units+1;
      
        INSERT INTO gaming_client_loyalty_badges_history (client_id,loyalty_badge_id,time_stamp,rule_instance_id)
        VALUES (clientID,badgeID,NOW(),ruleInstanceID);
      END IF;
      
    WHEN 'One-of' THEN 
      SELECT num_units INTO badgeAchievedForUser FROM gaming_client_loyalty_badges WHERE loyalty_badge_id=badgeID LIMIT 1;
      
      IF badgeAchievedForUser=0 THEN
		INSERT INTO gaming_client_loyalty_badges (client_id, loyalty_badge_id, num_units)
        VALUES (clientID, badgeID, 1) ON DUPLICATE KEY UPDATE num_units = num_units+1;

        INSERT INTO gaming_client_loyalty_badges_history (client_id,loyalty_badge_id,time_stamp,rule_instance_id)
        VALUES (clientID,badgeID,NOW(),ruleInstanceID);
      END IF;

	ELSE

      INSERT INTO gaming_client_loyalty_badges_history (client_id, loyalty_badge_id, time_stamp, rule_instance_id)
      VALUES (clientID, badgeID, NOW(), ruleInstanceID);
      
      INSERT INTO gaming_client_loyalty_badges (client_id, loyalty_badge_id, num_units)
      VALUES (clientID, badgeID, 1)
      ON DUPLICATE KEY UPDATE num_units = num_units+1;

  END CASE;

  IF (numUnits IS NOT NULL AND numUnits > 0 AND badgeAchievedForUser=0) THEN
	UPDATE gaming_loyalty_badges SET num_units = num_units-1 WHERE gaming_loyalty_badges.loyalty_badge_id = badgeID;
  END IF;
	
  SET statusCode=0;

END root$$

DELIMITER ;
