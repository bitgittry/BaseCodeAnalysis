DROP procedure IF EXISTS `PromotionGetAllPromotionsForNotLoggedInPlayers`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionGetAllPromotionsForNotLoggedInPlayers`(currencyID BIGINT)
BEGIN
  -- returns also games
  DECLARE promotionGetCounterID BIGINT DEFAULT -1;
	
  INSERT INTO gaming_promotion_get_counter (date_added) VALUES (NOW());
  SET promotionGetCounterID=LAST_INSERT_ID();
  
  SET @curDateTemp = NOW();
  
  INSERT INTO gaming_promotion_get_counter_promotions (promotion_get_counter_id, promotion_id) 
  SELECT promotionGetCounterID, promotion_id 
  FROM gaming_promotions 
  JOIN gaming_player_selections ON
    (achievement_end_date >= @curDateTemp AND gaming_promotions.is_active=1 AND gaming_promotions.is_child=0) AND 
    (gaming_promotions.player_selection_id=gaming_player_selections.player_selection_id AND gaming_player_selections.open_to_all=1);
  
  
  
  SELECT promotion_group_id, name, display_name, start_date, end_date, open_to_all, notes, num_promotions, is_active, is_hidden
  FROM gaming_promotion_groups 
  WHERE gaming_promotion_groups.end_date>=@curDateTemp AND gaming_promotion_groups.is_active=1 AND gaming_promotion_groups.open_to_all=1;
  
  SELECT gaming_promotion_groups.promotion_group_id, gaming_promotion_groups_promotions.promotion_id
  FROM gaming_promotion_groups_promotions
  JOIN gaming_promotion_groups ON 
    gaming_promotion_groups.end_date>=@curDateTemp AND gaming_promotion_groups.is_active=1 AND gaming_promotion_groups.open_to_all=1 AND
    gaming_promotion_groups.promotion_group_id=gaming_promotion_groups_promotions.promotion_group_id;
  
  SET @operatorGameIDFilter=0;
  SET @clientStatID = 0;
  CALL PromotionGetAllPromotionsByPromotionCounterIDAndCurrencyID(promotionGetCounterID, currencyID, @operatorGameIDFilter, @clientStatID);
  
END$$

DELIMITER ;

