DROP procedure IF EXISTS `PromotionGetAllPromotionsFilterByDateType`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionGetAllPromotionsFilterByDateType`(promotionFilterDateType VARCHAR(80), currencyID BIGINT, operatorGameIDFilter BIGINT, nonHiddenOnly TINYINT(1))
BEGIN
  
  DECLARE promotionGetCounterID BIGINT DEFAULT -1;
	
  INSERT INTO gaming_promotion_get_counter (date_added) VALUES (NOW());
  SET promotionGetCounterID=LAST_INSERT_ID();
  
  SET @curDateTemp = NOW();
  CASE promotionFilterDateType 
    WHEN 'ALL' THEN
      INSERT INTO gaming_promotion_get_counter_promotions (promotion_get_counter_id, promotion_id) 
      SELECT promotionGetCounterID, promotion_id 
      FROM gaming_promotions
      WHERE (nonHiddenOnly=0 OR gaming_promotions.is_hidden=0) AND gaming_promotions.is_child=0; 
    WHEN 'CURRENT' THEN 
      INSERT INTO gaming_promotion_get_counter_promotions (promotion_get_counter_id, promotion_id) 
      SELECT promotionGetCounterID, promotion_id 
      FROM gaming_promotions 
      WHERE (nonHiddenOnly=0 OR gaming_promotions.is_hidden=0) AND gaming_promotions.is_child=0 AND achievement_start_date <= @curDateTemp AND achievement_end_date >= @curDateTemp; 
    WHEN 'CURRENT+FUTURE' THEN 
      INSERT INTO gaming_promotion_get_counter_promotions (promotion_get_counter_id, promotion_id) 
      SELECT promotionGetCounterID, promotion_id 
      FROM gaming_promotions 
      WHERE (nonHiddenOnly=0 OR gaming_promotions.is_hidden=0) AND gaming_promotions.is_child=0 AND achievement_end_date >= @curDateTemp; 
    WHEN 'FUTURE' THEN 
      INSERT INTO gaming_promotion_get_counter_promotions (promotion_get_counter_id, promotion_id) 
      SELECT promotionGetCounterID, promotion_id 
      FROM gaming_promotions 
      WHERE (nonHiddenOnly=0 OR gaming_promotions.is_hidden=0) AND gaming_promotions.is_child=0 AND achievement_start_date >= @curDateTemp; 
    WHEN 'PAST' THEN 
      INSERT INTO gaming_promotion_get_counter_promotions (promotion_get_counter_id, promotion_id) 
      SELECT promotionGetCounterID, promotion_id 
      FROM gaming_promotions 
      WHERE (nonHiddenOnly=0 OR gaming_promotions.is_hidden=0) AND gaming_promotions.is_child=0 AND achievement_end_date <= @curDateTemp; 
  END CASE;
  
  CALL PromotionGetAllPromotionsByPromotionCounterIDAndCurrencyID(promotionGetCounterID, currencyID, operatorGameIDFilter, 0);
  
END$$

DELIMITER ;

