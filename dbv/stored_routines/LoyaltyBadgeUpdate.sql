DROP procedure IF EXISTS `LoyaltyBadgeUpdate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LoyaltyBadgeUpdate`(loyaltyBadgeID BIGINT, badgeName VARCHAR(80), badgeTypeID BIGINT, badgeDescription VARCHAR(255), detailedDescription TEXT, minVipLevel INT, numUnits INT, saveNumUnits TINYINT(1), endDate DATETIME, OUT statusCode INT)
root: BEGIN
  -- Added check to see if date is older than today's date.
  
  DECLARE badgeType, sameNameFound BIGINT DEFAULT 0;
  SET statusCode=0;

  IF endDate < NOW() THEN
	SET statusCode = 3;
	LEAVE root;
  END IF;

  SELECT 1 INTO sameNameFound FROM gaming_loyalty_badges WHERE name=badgeName AND is_hidden=0 AND loyalty_badge_id!=loyaltyBadgeID LIMIT 1;
  
  IF sameNameFound != 0 THEN 
    SET statusCode=1;
    LEAVE root;
  END IF;

  SELECT loyalty_badge_type_id INTO badgeType FROM gaming_loyalty_badge_types WHERE loyalty_badge_type_id = badgeTypeID;
  IF badgeType =0 THEN 
    SET statusCode=2;
    LEAVE root;
  END IF;

  UPDATE gaming_loyalty_badges 
  SET name=badgeName, loyalty_badge_type_id=badgeType, description=badgeDescription, detailed_description=detailedDescription, min_vip_level=minVipLevel, num_units=IF(saveNumUnits, numUnits, num_units), end_date=endDate
  WHERE loyalty_badge_id=loyaltyBadgeID;
	
END root$$

DELIMITER ;
