DROP procedure IF EXISTS `GameGetPlayerFavouriteGames`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameGetPlayerFavouriteGames`(clientStatID BIGINT)
BEGIN
  
  -- Some query beautification and changed from game_name to game_description since this the game title 
  
  SELECT 
    gaming_games.manufacturer_game_idf, 
    gaming_games.name as ProviderGameName, 
    gaming_games.game_description as GameDescription,
    gaming_game_categories_games.game_category_id as GameCategory, 
    gaming_game_manufacturers.display_name as Provider,
    fv_games.client_stat_id, 
    fv_games.operator_game_id, 
    fv_games.is_player_assigned, 
    fv_games.is_auto_assigned,
    fv_games.ranking, 
    fv_games.client_stats_favourite_games_counter_id,
    gaming_operator_games.game_id, 
    favourite_name 
  FROM gaming_client_stats_favourite_games AS fv_games FORCE INDEX (PRIMARY)
  STRAIGHT_JOIN gaming_operator_games ON fv_games.operator_game_id=gaming_operator_games.operator_game_id 
  STRAIGHT_JOIN gaming_games ON  gaming_games.game_id = gaming_operator_games.game_id 
  STRAIGHT_JOIN gaming_game_categories_games ON gaming_games.game_id=gaming_game_categories_games.game_id
  STRAIGHT_JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id = gaming_game_manufacturers.game_manufacturer_id
  WHERE fv_games.client_stat_id=clientStatID 
  ORDER BY fv_games.ranking ASC;
  
END$$

DELIMITER ;

