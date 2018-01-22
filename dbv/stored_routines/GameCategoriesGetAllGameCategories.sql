DROP procedure IF EXISTS `GameCategoriesGetAllGameCategories`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameCategoriesGetAllGameCategories`(returnUnassigned INT, launchableOnly INT)
BEGIN
  -- Added license type  

  SELECT game_category_id, name, description, date_created, is_unassigend_category, level, parent_game_category_id 
  FROM gaming_game_categories 
  WHERE ((gaming_game_categories.is_unassigend_category=0) OR (returnUnassigned=1)) AND is_hidden=0;
  
  SELECT gaming_games.game_id, gaming_games.name, manufacturer_game_idf, game_name AS manufacturer_game_name, game_description, manufacturer_game_type, gaming_games.is_launchable, gaming_games.has_play_for_fun, manufacturer_game_launch_type, 
    gaming_game_manufacturers.game_manufacturer_id, gaming_game_manufacturers.name AS manufacturer_name, gaming_game_manufacturers.display_name AS manufacturer_display_name, 
    gaming_operator_games.operator_game_id, gaming_operator_games.bonus_wgr_req_weigth, gaming_operator_games.promotion_wgr_req_weight,
	gaming_license_type.license_type_id, gaming_license_type.name AS license_type,
    gaming_game_categories.game_category_id, parent_game_category_id, 
	gaming_games.has_auto_play,gaming_games.is_frequent_draws,gaming_games.is_passive, gaming_games.game_outcome_type_id
  FROM gaming_game_categories 
  JOIN gaming_game_categories_games ON 
    gaming_game_categories.is_hidden=0 AND ((gaming_game_categories.is_unassigend_category=0) OR (returnUnassigned=1)) AND
    gaming_game_categories.game_category_id=gaming_game_categories_games.game_category_id 
  JOIN gaming_games ON gaming_game_categories_games.game_id=gaming_games.game_id AND gaming_games.is_sub_game=0 AND (launchableOnly=0 OR gaming_games.is_launchable=1)
  JOIN gaming_game_manufacturers ON gaming_game_manufacturers.is_active=1 AND gaming_games.game_manufacturer_id = gaming_game_manufacturers.game_manufacturer_id 
  JOIN gaming_operator_games ON gaming_games.game_id = gaming_operator_games.game_id
  JOIN gaming_license_type ON gaming_games.license_type_id=gaming_license_type.license_type_id; 
END$$

DELIMITER ;

