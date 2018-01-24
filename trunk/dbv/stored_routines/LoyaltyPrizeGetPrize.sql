DROP procedure IF EXISTS `LoyaltyPrizeGetPrize`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LoyaltyPrizeGetPrize`(PrizeID BIGINT)
root : BEGIN
  -- Added new Badge Fields

  SELECT gaming_loyalty_prizes.loyalty_prize_id, gaming_loyalty_prizes.name, gaming_loyalty_prizes.description, gaming_loyalty_prizes.loyalty_points_cost, 
	gaming_loyalty_prizes.active, gaming_loyalty_prize_types.name AS prize_type_name, gaming_loyalty_prizes.begin_date, gaming_loyalty_prizes.end_date, gaming_loyalty_prizes.ext_id 
  FROM gaming_loyalty_prizes
  STRAIGHT_JOIN gaming_loyalty_prize_types ON gaming_loyalty_prize_types.prize_type_id=gaming_loyalty_prizes.prize_type_id
  WHERE gaming_loyalty_prizes.loyalty_prize_id = PrizeID;
  
  SELECT gaming_loyalty_badges.loyalty_badge_id, gaming_loyalty_badges.name, gaming_loyalty_badges.description, gaming_loyalty_badge_types.name AS loyalty_badge_type,
	gaming_loyalty_badges.detailed_description, gaming_loyalty_badges.min_vip_level, gaming_loyalty_badges.num_units, gaming_loyalty_badges.end_date
  FROM gaming_loyalty_prizes
  STRAIGHT_JOIN gaming_loyalty_prize_badge_requirement ON gaming_loyalty_prizes.prize_badge_requirement_id = gaming_loyalty_prize_badge_requirement.prize_badge_requirement_id 
  STRAIGHT_JOIN gaming_loyalty_badges ON gaming_loyalty_badges.loyalty_badge_id=gaming_loyalty_prize_badge_requirement.loyalty_badge_id
  STRAIGHT_JOIN gaming_loyalty_badge_types ON gaming_loyalty_badge_types.loyalty_badge_type_id = gaming_loyalty_badges.loyalty_badge_type_id 
  WHERE gaming_loyalty_prizes.loyalty_prize_id = PrizeID;
          
END$$

DELIMITER ;

