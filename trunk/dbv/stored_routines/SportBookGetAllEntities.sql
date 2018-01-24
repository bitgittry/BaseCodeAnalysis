DROP procedure IF EXISTS `SportBookGetAllEntities`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SportBookGetAllEntities`(gameManufacturerID BIGINT, levelDepth SMALLINT)
BEGIN
  SET @filterDate = DATE_SUB(NOW(), INTERVAL 1 DAY);
  SET @leveDepthLocal = IF(IFNULL(levelDepth, 0) = 0, 6, levelDepth);

  SELECT gaming_sb_sports.sb_sport_id, gaming_sb_sports.name, gaming_sb_sports.ext_sport_id, gaming_sb_sports.game_manufacturer_id 
  FROM gaming_sb_sports 
  WHERE gaming_sb_sports.game_manufacturer_id=gameManufacturerID AND gaming_sb_sports.is_hidden=0;
  
  IF(@leveDepthLocal >= 2) THEN
	  SELECT gaming_sb_regions.sb_region_id, gaming_sb_regions.name, gaming_sb_regions.ext_region_id, gaming_sb_regions.sb_sport_id 
	  FROM gaming_sb_regions 
	  WHERE gaming_sb_regions.game_manufacturer_id=gameManufacturerID AND gaming_sb_regions.is_hidden=0;
  END IF;
  
  IF(@leveDepthLocal >= 3) THEN  
	  SELECT gaming_sb_groups.sb_group_id, gaming_sb_groups.name, gaming_sb_groups.ext_group_id, gaming_sb_groups.sb_region_id 
	  FROM gaming_sb_groups 
	  WHERE gaming_sb_groups.game_manufacturer_id=gameManufacturerID AND gaming_sb_groups.is_hidden=0;
  END IF;
  
  IF(@leveDepthLocal >= 4) THEN  
	  SELECT gaming_sb_events.sb_event_id, gaming_sb_events.name, gaming_sb_events.ext_event_id, gaming_sb_events.date_end, gaming_sb_events.sb_group_id, gaming_sb_events.date_end, gaming_sb_events.status, gaming_sb_events.is_live, gaming_sb_events.reusable_code
	  FROM gaming_sb_events FORCE INDEX (gm_non_expired)
	  WHERE gaming_sb_events.game_manufacturer_id=gameManufacturerID AND gaming_sb_events.is_hidden=0
		AND (gaming_sb_events.date_end > @filterDate OR gaming_sb_events.date_end IS NULL);
  END IF;
  
  IF(@leveDepthLocal >= 5) THEN
	  SELECT gaming_sb_markets.sb_market_id, gaming_sb_markets.name, gaming_sb_markets.ext_market_id, gaming_sb_markets.sb_event_id, gaming_sb_markets.description
	  FROM gaming_sb_events FORCE INDEX (gm_non_expired)
	  STRAIGHT_JOIN gaming_sb_markets FORCE INDEX (sb_event_id) ON gaming_sb_events.sb_event_id = gaming_sb_markets.sb_event_id AND gaming_sb_markets.is_hidden=0
	  WHERE gaming_sb_events.game_manufacturer_id=gameManufacturerID AND gaming_sb_events.is_hidden=0
		AND (gaming_sb_events.date_end > @filterDate OR gaming_sb_events.date_end IS NULL);
  END IF;
  
  IF(@leveDepthLocal >= 6) THEN
	  SELECT gaming_sb_selections.sb_selection_id, gaming_sb_selections.name, gaming_sb_selections.ext_selection_id, gaming_sb_selections.price_down, 
		gaming_sb_selections.price_up, gaming_sb_selections.odd, gaming_sb_selections.sb_market_id, gaming_sb_selections.description
	  FROM gaming_sb_events FORCE INDEX (gm_non_expired)
	  STRAIGHT_JOIN gaming_sb_markets FORCE INDEX (sb_event_id) ON gaming_sb_events.sb_event_id = gaming_sb_markets.sb_event_id AND gaming_sb_markets.is_hidden=0
	  STRAIGHT_JOIN gaming_sb_selections FORCE INDEX (sb_market_id) ON gaming_sb_selections.sb_market_id = gaming_sb_markets.sb_market_id AND gaming_sb_selections.is_hidden=0
	  WHERE gaming_sb_events.game_manufacturer_id=gameManufacturerID AND gaming_sb_events.is_hidden=0
		AND (gaming_sb_events.date_end > @filterDate OR gaming_sb_events.date_end IS NULL);	  
  END IF;

END$$

DELIMITER ;

