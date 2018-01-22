DROP procedure IF EXISTS `LoyaltyBadgeInsert`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LoyaltyBadgeInsert`(badgeName VARCHAR(80), badgeTypeID BIGINT, badgeDescription VARCHAR(80), detailedDescription TEXT, minVipLevel INT, numUnits INT, endDate DATETIME, OUT badgeID INT, OUT statusCode INT)
root: BEGIN
  -- Added check to see if date is older than today's date.
  
  DECLARE badgeType, sameNameFound BIGINT DEFAULT 0;
  SET statusCode=0;
  
  IF endDate < NOW() THEN
	SET statusCode = 3;
	LEAVE root;
  END IF;

  SELECT 1 INTO sameNameFound FROM gaming_loyalty_badges WHERE name = badgeName AND is_hidden=0 LIMIT 1;
  
  IF sameNameFound != 0 THEN 
    SET statusCode=1;
    LEAVE root;
  END IF;

  SELECT loyalty_badge_type_id INTO badgeType FROM gaming_loyalty_badge_types WHERE loyalty_badge_type_id = badgeTypeID;
  IF badgeType = 0 THEN 
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  INSERT INTO gaming_loyalty_badges (name, loyalty_badge_type_id, description, detailed_description, min_vip_level, num_units, end_date) 
  VALUES (badgeName, badgeType, badgeDescription, detailedDescription, minVipLevel, numUnits ,endDate);
  
  SET badgeID = LAST_INSERT_ID();
	
END root$$

DELIMITER ;

