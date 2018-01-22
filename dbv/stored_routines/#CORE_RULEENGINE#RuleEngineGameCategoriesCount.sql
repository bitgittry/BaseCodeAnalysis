DROP FUNCTION IF EXISTS RuleEngineGameCategoriesCount;
DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `RuleEngineGameCategoriesCount`(arg_GameId int, arg_GameCategoriesCsv varchar(2000)) RETURNS int
root: BEGIN 
DECLARE res int; 


 SELECT count(*) INTO res FROM gaming_game_categories_games 
          JOIN gaming_game_categories ON gaming_game_categories.game_category_id=gaming_game_categories_games.game_category_id
          AND CONCAT(',',arg_GameCategoriesCsv,',') LIKE CONCAT('%,',CAST(gaming_game_categories_games.game_category_id AS CHAR),',%')
          AND gaming_game_categories_games.game_id=arg_GameId;
RETURN res; 
END root$$

DELIMITER ;

