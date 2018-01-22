DROP procedure IF EXISTS `GameManufacturerGetJacpots`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameManufacturerGetJacpots`()
BEGIN
  -- Added license type

  SELECT game_manufacturer_jackpot_id, gm_jackpots.name, gm_jackpots.display_name, external_name, gaming_currency.currency_code, current_value, gm_jackpots.game_manufacturer_id, update_game_list, gm_jackpots.date_created, gm_jackpots.last_updated 
  FROM gaming_game_manufacturers_jackpots AS gm_jackpots
  JOIN gaming_game_manufacturers ON gaming_game_manufacturers.is_active=1 AND gm_jackpots.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id 
  JOIN gaming_currency ON gm_jackpots.is_active AND gm_jackpots.currency_id=gaming_currency.currency_id;
  
  SELECT gm_jackpots.game_manufacturer_jackpot_id, gaming_games.game_id, gaming_games.name, manufacturer_game_idf, game_name AS manufacturer_game_name, game_description, manufacturer_game_type, gaming_games.is_launchable, gaming_games.has_play_for_fun, manufacturer_game_launch_type,
    gaming_game_manufacturers.game_manufacturer_id, gaming_game_manufacturers.name AS manufacturer_name, gaming_game_manufacturers.display_name AS manufacturer_display_name, 
    gaming_operator_games.operator_game_id, gaming_operator_games.bonus_wgr_req_weigth, gaming_operator_games.promotion_wgr_req_weight,
    gaming_game_categories_games.game_category_id, gaming_license_type.license_type_id, gaming_license_type.name AS license_type,
	gaming_games.has_auto_play,gaming_games.is_frequent_draws,gaming_games.is_passive, gaming_games.game_outcome_type_id
  FROM gaming_game_manufacturers_jackpots AS gm_jackpots
  JOIN gaming_game_manufacturers ON gaming_game_manufacturers.is_active=1 AND gm_jackpots.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id 
  JOIN gaming_game_manufacturers_jackpots_games AS gm_jackpots_games ON gm_jackpots.is_active=1 AND gm_jackpots.game_manufacturer_jackpot_id=gm_jackpots_games.game_manufacturer_jackpot_id
  JOIN gaming_games ON gm_jackpots_games.game_id=gaming_games.game_id AND gaming_games.is_launchable=1
  JOIN gaming_operator_games ON gaming_games.game_id=gaming_operator_games.game_id 
  JOIN gaming_game_categories_games ON gaming_games.game_id=gaming_game_categories_games.game_id
  JOIN gaming_license_type ON gaming_games.license_type_id=gaming_license_type.license_type_id;

  SELECT ggmjcv.game_manufacturer_jackpot_id, ggmjcv.current_value, gc.currency_code
  FROM gaming_game_manufacturers_jackpots_current_values AS ggmjcv
  JOIN gaming_game_manufacturers_jackpots ggmj ON ggmjcv.game_manufacturer_jackpot_id = ggmj.game_manufacturer_jackpot_id
  JOIN gaming_game_manufacturers ggm ON ggm.is_active=1 AND ggmj.game_manufacturer_id=ggm.game_manufacturer_id 
  JOIN gaming_currency gc ON ggmjcv.currency_id=gc.currency_id
  WHERE ggmj.is_active;

END$$

DELIMITER ;
