DROP procedure IF EXISTS `SportsCreateDefaultSportsEntities`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SportsCreateDefaultSportsEntities`()
BEGIN
	-- First Version
    
    -- Insert default sports book entities if needed
	INSERT INTO gaming_sb_sports (game_manufacturer_id, ext_sport_id, `name`)
	SELECT ggm.game_manufacturer_id, 'default', 'Default'
	FROM gaming_game_manufacturers AS ggm
	LEFT JOIN gaming_sb_sports ON ggm.game_manufacturer_id=gaming_sb_sports.game_manufacturer_id AND gaming_sb_sports.ext_sport_id='default'
	WHERE ggm.license_type_id=3 AND ggm.is_active AND gaming_sb_sports.sb_sport_id IS NULL;

	INSERT INTO gaming_sb_regions (game_manufacturer_id, ext_region_id, `name`, sb_sport_id)
	SELECT ggm.game_manufacturer_id, 'default', 'Default', gaming_sb_sports.sb_sport_id
	FROM gaming_game_manufacturers AS ggm
	JOIN gaming_sb_sports ON ggm.game_manufacturer_id=gaming_sb_sports.game_manufacturer_id AND gaming_sb_sports.ext_sport_id='default'
	LEFT JOIN gaming_sb_regions ON gaming_sb_sports.sb_sport_id=gaming_sb_regions.sb_sport_id AND gaming_sb_regions.ext_region_id='default'
	WHERE ggm.license_type_id=3 AND ggm.is_active AND gaming_sb_regions.sb_region_id IS NULL;

	INSERT INTO gaming_sb_groups (game_manufacturer_id, ext_group_id, `name`, sb_region_id)
	SELECT ggm.game_manufacturer_id, 'default', 'Default', gaming_sb_regions.sb_region_id
	FROM gaming_game_manufacturers AS ggm
	JOIN gaming_sb_sports ON ggm.game_manufacturer_id=gaming_sb_sports.game_manufacturer_id AND gaming_sb_sports.ext_sport_id='default'
	JOIN gaming_sb_regions ON gaming_sb_sports.sb_sport_id=gaming_sb_regions.sb_sport_id AND gaming_sb_regions.ext_region_id='default'
	LEFT JOIN gaming_sb_groups ON gaming_sb_regions.sb_region_id=gaming_sb_groups.sb_region_id AND gaming_sb_groups.ext_group_id='default'
	WHERE ggm.license_type_id=3 AND ggm.is_active AND gaming_sb_groups.sb_group_id IS NULL;

	INSERT INTO gaming_sb_events (game_manufacturer_id, ext_event_id, `name`, sb_group_id, date_start, date_end)
	SELECT ggm.game_manufacturer_id, 'default', 'Default', gaming_sb_groups.sb_group_id, '2015-01-01', '3000-01-01'
	FROM gaming_game_manufacturers AS ggm
	JOIN gaming_sb_sports ON ggm.game_manufacturer_id=gaming_sb_sports.game_manufacturer_id AND gaming_sb_sports.ext_sport_id='default'
	JOIN gaming_sb_regions ON gaming_sb_sports.sb_sport_id=gaming_sb_regions.sb_sport_id AND gaming_sb_regions.ext_region_id='default'
	JOIN gaming_sb_groups ON gaming_sb_regions.sb_region_id=gaming_sb_groups.sb_region_id AND gaming_sb_groups.ext_group_id='default'
	LEFT JOIN gaming_sb_events ON gaming_sb_groups.sb_group_id=gaming_sb_events.sb_group_id AND gaming_sb_events.ext_event_id='default'
	WHERE ggm.license_type_id=3 AND ggm.is_active AND gaming_sb_events.sb_event_id IS NULL;
    -- end of insert
    
END$$

DELIMITER ;

