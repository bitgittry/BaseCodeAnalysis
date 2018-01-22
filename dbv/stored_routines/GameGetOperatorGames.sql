DROP procedure IF EXISTS `GameGetOperatorGames`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameGetOperatorGames`(operatorID BIGINT, gameID BIGINT, includeWagerWeights TINYINT(1), weightsCurrenOnly TINYINT(1))
BEGIN 
  SET @operator_id=operatorID;
  SET @game_id=gameID;
  SET @include_wager_weights=includeWagerWeights;
  SET @weights_current_only=weightsCurrenOnly;
  SELECT operator_game_id, operator_id, hit_frequency, theoretical_payout, max_win, max_bet_per_line, total_played, total_payout, gaming_operator_games.date_added, date_live, is_game_blocked, bonus_wgr_req_weigth, promotion_wgr_req_weight, disable_bonus_money, 
    gaming_games.game_id, game_description, is_launchable, include_in_reports, gaming_games.is_sub_game, gaming_games.parent_game_id, has_play_for_fun, has_tournament, has_jackpot, has_shared_jackpot, has_minigame, 
    manufacturer_game_idf, game_name, manufacturer_game_type, fav_num_max, fav_coupon_max, allow_fav_name,	
    gaming_game_manufacturers.game_manufacturer_id, gaming_game_manufacturers.display_name AS game_manufacturer, 
    IFNULL(gaming_game_categories.game_category_id,0) AS game_category_id, gaming_game_categories.description AS game_category,
	gaming_games.has_auto_play, gaming_games.is_frequent_draws, gaming_games.is_passive,
  gaming_games.fav_num_max, gaming_games.fav_coupon_max, gaming_games.allow_fav_name,
  gaming_games.is_active_draw_notification
  FROM gaming_operator_games
  JOIN gaming_games ON gaming_operator_games.game_id=gaming_games.game_id AND gaming_games.is_sub_game=0
  JOIN gaming_game_manufacturers ON gaming_game_manufacturers.is_active=1 AND gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
  LEFT JOIN gaming_game_categories_games ON gaming_game_categories_games.game_id=gaming_games.game_id
  LEFT JOIN gaming_game_categories ON gaming_game_categories_games.game_category_id=gaming_game_categories.game_category_id
  WHERE gaming_operator_games.operator_id=@operator_id AND (@game_id=0 OR (gaming_games.game_id=@game_id OR gaming_games.parent_game_id=@game_id));
  SELECT rule_weights.operator_game_id, rule_weights.bonus_rule_id, rule_weights.bonus_wgr_req_weigth
  FROM gaming_operator_games 
  JOIN gaming_bonus_rules ON (@weights_current_only=0 OR (gaming_bonus_rules.activation_end_date>=NOW() AND gaming_bonus_rules.is_hidden=0))
  JOIN gaming_bonus_rules_wgr_req_weights AS rule_weights ON 
    (gaming_operator_games.operator_id=@operator_id AND (@game_id=0 OR game_id=@game_id)) AND
    gaming_operator_games.operator_game_id=rule_weights.operator_game_id AND
    gaming_bonus_rules.bonus_rule_id=rule_weights.bonus_rule_id
  JOIN gaming_games ON gaming_operator_games.game_id=gaming_games.game_id 
  JOIN gaming_game_manufacturers ON gaming_game_manufacturers.is_active=1 AND gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
  WHERE @include_wager_weights=1;
  SELECT rule_weights.operator_game_id, rule_weights.promotion_id, rule_weights.promotion_wgr_req_weight
  FROM gaming_operator_games 
  JOIN gaming_promotions ON (@weights_current_only=0 OR (gaming_promotions.achievement_end_date>=NOW() AND gaming_promotions.is_hidden=0)) AND gaming_promotions.is_child=0
  JOIN gaming_promotions_games AS rule_weights ON 
    (gaming_operator_games.operator_id=@operator_id AND (@game_id=0 OR game_id=@game_id)) AND
    gaming_operator_games.operator_game_id=rule_weights.operator_game_id AND
    gaming_promotions.promotion_id=rule_weights.promotion_id
  JOIN gaming_games ON gaming_operator_games.game_id=gaming_games.game_id 
  JOIN gaming_game_manufacturers ON gaming_game_manufacturers.is_active=1 AND gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id  
  WHERE @include_wager_weights=1;
END$$

DELIMITER ;